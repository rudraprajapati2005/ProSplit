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
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> createUserWithEmailAndPassword(
    String email,
    String password,
    String name,
  ) async {
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
      print('✅ User data saved to Firestore successfully');
    } catch (e) {
      print('⚠️ Warning: Could not save to Firestore (might be offline): $e');
      // Don't throw error - user is still created in Firebase Auth
      // The data will sync when connection is restored
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> updateUserProfile(UserModel user) async {
    await _firestore.collection('users').doc(user.id).update(user.toJson());
  }

  // Lightweight user search by name/email prefix and id exact/prefix.
  Future<List<UserModel>> searchUsers(String query, {int limit = 5}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final List<UserModel> results = [];
    final seen = <String>{};

    // Try exact ID match first
    try {
      final byId = await _firestore.collection('users').doc(q).get();
      if (byId.exists) {
        final model = UserModel.fromJson(byId.data()!);
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

    // Search by name prefix
    try {
      final end = _endAfterPrefix(q);
      final snap = await _firestore
          .collection('users')
          .orderBy('name')
          .startAt([q])
          .endBefore([end])
          .limit(limit)
          .get();
      for (final d in snap.docs) {
        if (seen.contains(d.id)) continue;
        results.add(UserModel.fromJson(d.data()));
        seen.add(d.id);
        if (results.length >= limit) break;
      }
    } catch (_) {}

    if (results.length < limit) {
      // Search by email prefix
      try {
        final end = _endAfterPrefix(q);
        final snap = await _firestore
            .collection('users')
            .orderBy('email')
            .startAt([q])
            .endBefore([end])
            .limit(limit - results.length)
            .get();
        for (final d in snap.docs) {
          if (seen.contains(d.id)) continue;
          results.add(UserModel.fromJson(d.data()));
          seen.add(d.id);
          if (results.length >= limit) break;
        }
      } catch (_) {}
    }

    return results.take(limit).toList();
  }
}
