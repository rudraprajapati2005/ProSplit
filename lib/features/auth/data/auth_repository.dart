import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository(this._auth, this._firestore);

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentFirebaseUser => _auth.currentUser;

  Future<UserModel?> getCurrentUser() async {
    print('🔍 Repository: Getting current user...');
    final user = _auth.currentUser;
    if (user == null) {
      print('❌ Repository: No current user found');
      return null;
    }
    print('✅ Repository: Found current user: ${user.uid}');

    print('📄 Repository: Fetching user document from Firestore...');
    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache));
      
      if (doc.exists) {
        print('✅ Repository: User document found, creating UserModel...');
        final userModel = UserModel.fromJson(doc.data()!);
        print('✅ Repository: UserModel created: ${userModel.name}');
        return userModel;
      }
      print('❌ Repository: User document does not exist');
      return null;
    } catch (e) {
      print('⚠️ Repository: Error fetching user document (might be offline): $e');
      // Return null instead of throwing - this prevents the app from hanging
      return null;
    }
  }

  Future<void> signInWithEmailAndPassword(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      // Re-throw Firebase auth exceptions so they can be handled by the UI
      rethrow;
    } catch (e) {
      // Wrap other exceptions in a generic auth exception
      throw FirebaseAuthException(
        code: 'unknown-error',
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  Future<void> createUserWithEmailAndPassword(
    String email,
    String password,
    String name,
  ) async {
    try {
      print('🔐 Starting Firebase Auth user creation...');
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('✅ Firebase Auth user created successfully: ${credential.user!.uid}');

      print('📝 Creating UserModel...');
      final user = UserModel(
        id: credential.user!.uid,
        email: email,
        name: name,
      );
      print('✅ UserModel created: ${user.toJson()}');

      print('💾 Saving user data to Firestore...');
      try {
        await _firestore
            .collection('users')
            .doc(credential.user!.uid)
            .set(user.toJson());
        // Also create/update public user directory entry for suggestions
        await _firestore
            .collection('user_directory')
            .doc(credential.user!.uid)
            .set({
          'email': email,
          'name': name,
          'emailLower': email.toLowerCase(),
          'nameLower': name.toLowerCase(),
        });
        print('✅ User data saved to Firestore successfully');
      } catch (e) {
        print('⚠️ Warning: Could not save to Firestore (might be offline): $e');
        // Don't throw error - user is still created in Firebase Auth
        // The data will sync when connection is restored
      }
    } on FirebaseAuthException catch (e) {
      // Re-throw Firebase auth exceptions so they can be handled by the UI
      rethrow;
    } catch (e) {
      // Wrap other exceptions in a generic auth exception
      throw FirebaseAuthException(
        code: 'unknown-error',
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> updateUserProfile(UserModel user) async {
    await _firestore.collection('users').doc(user.id).update(user.toJson());
    // Keep user_directory in sync for suggestions
    try {
      await _firestore.collection('user_directory').doc(user.id).set({
        'email': user.email,
        'name': user.name,
        'emailLower': user.email.toLowerCase(),
        'nameLower': user.name.toLowerCase(),
      }, SetOptions(merge: true));
    } catch (_) {}
    
    // Also update the user's name in all groups they're part of
    try {
      // Find all groups where this user is a member
      final groupsQuery = await _firestore
          .collection('groups')
          .where('memberUserIds', arrayContains: user.id)
          .get();
      
      final batch = _firestore.batch();
      
      for (final doc in groupsQuery.docs) {
        final data = doc.data();
        final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
        memberNames[user.id] = user.name;
        
        batch.update(doc.reference, {'memberNames': memberNames});
      }
      
      // Also check if user is a group creator
      final creatorGroupsQuery = await _firestore
          .collection('groups')
          .where('createdByUserId', isEqualTo: user.id)
          .get();
      
      for (final doc in creatorGroupsQuery.docs) {
        final data = doc.data();
        final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
        memberNames[user.id] = user.name;
        
        batch.update(doc.reference, {'memberNames': memberNames});
      }
      
      if (groupsQuery.docs.isNotEmpty || creatorGroupsQuery.docs.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      print('Error updating member name in groups: $e');
      // Don't throw - this is not critical
    }
  }

  // Lightweight user search by name/email prefix and id exact/prefix.
  Future<List<UserModel>> searchUsers(String query, {int limit = 5}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final List<UserModel> results = [];
    final seen = <String>{};

    // Try exact ID match first against user_directory (doc id = uid)
    try {
      final byId = await _firestore.collection('user_directory').doc(q).get();
      if (byId.exists && byId.data() != null) {
        final data = byId.data()!;
        final model = UserModel(id: byId.id, email: (data['email'] ?? '').toString(), name: (data['name'] ?? '').toString());
        results.add(model);
        seen.add(model.id);
        if (results.length >= limit) return results.take(limit).toList();
      }
    } catch (_) {}

    // Prefix range helper
    String _endAfterPrefix(String s) {
      if (s.isEmpty) return s;
      final last = s.codeUnitAt(s.length - 1);
      return s.substring(0, s.length - 1) + String.fromCharCode(last + 1);
    }

    // Search by lowercase name prefix in user_directory
    try {
      final ql = q.toLowerCase();
      final end = _endAfterPrefix(ql);
      final snap = await _firestore
          .collection('user_directory')
          .orderBy('nameLower')
          .startAt([ql])
          .endBefore([end])
          .limit(limit)
          .get();
      for (final d in snap.docs) {
        if (seen.contains(d.id)) continue;
        final data = d.data();
        results.add(UserModel(id: d.id, email: (data['email'] ?? '').toString(), name: (data['name'] ?? '').toString()));
        seen.add(d.id);
        if (results.length >= limit) break;
      }
    } catch (_) {}

    if (results.length < limit) {
      // Search by lowercase email prefix in user_directory
      try {
        final ql = q.toLowerCase();
        final end = _endAfterPrefix(ql);
        final snap = await _firestore
            .collection('user_directory')
            .orderBy('emailLower')
            .startAt([ql])
            .endBefore([end])
            .limit(limit - results.length)
            .get();
        for (final d in snap.docs) {
          if (seen.contains(d.id)) continue;
          final data = d.data();
          results.add(UserModel(id: d.id, email: (data['email'] ?? '').toString(), name: (data['name'] ?? '').toString()));
          seen.add(d.id);
          if (results.length >= limit) break;
        }
      } catch (_) {}
    }

    return results.take(limit).toList();
  }
}
