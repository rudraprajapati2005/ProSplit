import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/group_model.dart';
import '../domain/member_info.dart';
import '../domain/deleted_group_model.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(FirebaseFirestore.instance);
});

class GroupRepository {
  final FirebaseFirestore _firestore;
  GroupRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> get _groupsCol =>
      _firestore.collection('groups');

  Stream<List<GroupModel>> streamUserGroups(String userId) {
    return _groupsCol
        .where('memberUserIds', arrayContains: userId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => GroupModel.fromJson(d.data(), d.id))
            .toList());
  }

  Stream<List<GroupModel>> streamPendingInvitesForEmail(String email) {
    return _groupsCol
        .where('pendingInviteEmails', arrayContains: email)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => GroupModel.fromJson(d.data(), d.id))
            .toList());
  }

  Future<String> createGroup({
    required String name,
    required String createdByUserId,
    required List<String> initialMemberUserIds,
    required List<String> inviteEmails,
    String? creatorName,
  }) async {
    final doc = _groupsCol.doc();
    
    // Build memberNames map (legacy) and members map (new) with creator and initial members
    final memberNames = <String, String>{};
    final members = <String, MemberInfo>{};
    
    // Helper function to fetch user info
    Future<MemberInfo> _fetchUserInfo(String userId, String? fallbackName) async {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data()!;
          return MemberInfo(
            userId: userId,
            username: userData['name'] ?? fallbackName ?? 'User $userId',
            email: userData['email'],
          );
        } else {
          return MemberInfo(
            userId: userId,
            username: fallbackName ?? 'User $userId',
          );
        }
      } catch (e) {
        return MemberInfo(
          userId: userId,
          username: fallbackName ?? 'User $userId',
        );
      }
    }
    
    // Fetch creator info
    final creatorInfo = await _fetchUserInfo(createdByUserId, creatorName);
    memberNames[createdByUserId] = creatorInfo.username; // Legacy support
    members[createdByUserId] = creatorInfo;
    
    // Resolve invited emails to existing users (auto-join), collect unmatched emails as pending invites
    final normalizedInvites = inviteEmails
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final Map<String, Map<String, String>> emailToUser = {}; // emailLower -> {id, name, email}

    // Firestore whereIn is limited to 10; chunk queries
    const int chunkSize = 10;
    for (var i = 0; i < normalizedInvites.length; i += chunkSize) {
      final chunk = normalizedInvites
          .skip(i)
          .take(chunkSize)
          .map((e) => e.toLowerCase())
          .toList();
      if (chunk.isEmpty) continue;
      try {
        final snap = await _firestore
            .collection('user_directory')
            .where('emailLower', whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          final email = (data['email'] as String? ?? '').trim();
          if (email.isEmpty) continue;
          emailToUser[(data['emailLower'] as String? ?? email.toLowerCase())] = {
            'id': d.id,
            'name': (data['name'] as String? ?? '').trim(),
            'email': email,
          };
        }
      } catch (_) {
        // Ignore lookup errors; unmatched emails will stay as pending invites
      }
    }

    // Start with provided initial members (e.g., creator), then add resolved invitees
    final resolvedMemberIds = <String>{...initialMemberUserIds};

    // Add resolved users to members
    for (final originalEmail in normalizedInvites) {
      final key = originalEmail.toLowerCase();
      if (!emailToUser.containsKey(key)) continue;
      final info = emailToUser[key]!;
      final userId = info['id']!;
      if (userId == createdByUserId) continue; // skip duplicate creator
      if (resolvedMemberIds.add(userId)) {
        final displayName = (info['name']?.isNotEmpty == true)
            ? info['name']!
            : originalEmail.split('@').first;
        memberNames[userId] = displayName; // Legacy support
        members[userId] = MemberInfo(
          userId: userId,
          username: displayName,
          email: info['email'],
        );
      }
    }

    // Prepare pending invites only for unmatched emails
    final pendingEmails = <String>[];
    for (final originalEmail in normalizedInvites) {
      if (!emailToUser.containsKey(originalEmail.toLowerCase())) {
        pendingEmails.add(originalEmail);
      }
    }
    
    final model = GroupModel(
      id: doc.id,
      name: name,
      createdByUserId: createdByUserId,
      memberUserIds: resolvedMemberIds.toList(),
      pendingInviteEmails: pendingEmails,
      createdAt: DateTime.now(),
      memberNames: memberNames, // Legacy support
      members: members, // New structure
    );
    await doc.set(model.toJson()).timeout(const Duration(seconds: 15));

    // Create per-user notifications for auto-joined users (excluding creator)
    try {
      final String addedByName = creatorInfo.username;
      final String groupName = name;
      final batch = _firestore.batch();
      for (final userId in resolvedMemberIds) {
        if (userId == createdByUserId) continue;
        final notifRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .doc();
        batch.set(notifRef, {
          'title': 'Added to group',
          'body': '$addedByName added you to group "$groupName"',
          'groupId': doc.id,
          'createdAt': Timestamp.fromDate(DateTime.now()),
          'type': 'group_added',
          'read': false,
        });
      }
      await batch.commit();
    } catch (_) {
      // Notifications are best-effort; ignore failures
    }
    return doc.id;
  }

  // Update group details (e.g., name or invites)
  Future<void> updateGroupDetails({
    required String groupId,
    String? name,
    List<String>? pendingInviteEmails,
  }) async {
    final doc = _groupsCol.doc(groupId);
    final update = <String, dynamic>{};
    if (name != null) update['name'] = name;
    if (pendingInviteEmails != null) {
      update['pendingInviteEmails'] = pendingInviteEmails;
    }
    if (update.isEmpty) return;
    await doc.update(update).timeout(const Duration(seconds: 15));
  }

  Future<void> acceptInvite({
    required String groupId,
    required String userId,
    required String userEmail,
  }) async {
    final doc = _groupsCol.doc(groupId);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(doc);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final memberUserIds = List<String>.from(data['memberUserIds'] ?? []);
      final pendingInviteEmails =
          List<String>.from(data['pendingInviteEmails'] ?? []);
      final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
      final members = Map<String, dynamic>.from(data['members'] ?? {});
      
      if (!memberUserIds.contains(userId)) {
        memberUserIds.add(userId);
      }
      pendingInviteEmails.removeWhere((e) => e.toLowerCase() == userEmail.toLowerCase());
      
      // Add member info - try to get from user profile first, fallback to email prefix
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data()!;
          final username = userData['name'] ?? userEmail.split('@')[0];
          memberNames[userId] = username; // Legacy support
          
          // Add to new members structure
          members[userId] = {
            'userId': userId,
            'username': username,
            'email': userData['email'],
          };
        } else {
          final username = userEmail.split('@')[0]; // Fallback to email prefix
          memberNames[userId] = username; // Legacy support
          
          // Add to new members structure
          members[userId] = {
            'userId': userId,
            'username': username,
            'email': userEmail,
          };
        }
      } catch (e) {
        // If we can't fetch user data, use email prefix as fallback
        final username = userEmail.split('@')[0];
        memberNames[userId] = username; // Legacy support
        
        // Add to new members structure
        members[userId] = {
          'userId': userId,
          'username': username,
          'email': userEmail,
        };
      }
      
      txn.update(doc, {
        'memberUserIds': memberUserIds,
        'pendingInviteEmails': pendingInviteEmails,
        'memberNames': memberNames, // Legacy support
        'members': members, // New structure
      });
    }).timeout(const Duration(seconds: 15));
  }

  // Add member to group
  Future<void> addMemberToGroup(String groupId, String userId, String userName) async {
    final doc = _groupsCol.doc(groupId);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(doc);
      if (!snap.exists) throw Exception('Group not found');
      
      final data = snap.data() as Map<String, dynamic>;
      final memberUserIds = List<String>.from(data['memberUserIds'] ?? []);
      final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
      final members = Map<String, dynamic>.from(data['members'] ?? {});
      final createdByUserId = data['createdByUserId'] as String? ?? '';
      final groupName = data['name'] as String? ?? '';
      
      if (!memberUserIds.contains(userId)) {
        memberUserIds.add(userId);
        memberNames[userId] = userName; // Legacy support
        
        // Add to new members structure
        members[userId] = {
          'userId': userId,
          'username': userName,
        };
        
        txn.update(doc, {
          'memberUserIds': memberUserIds,
          'memberNames': memberNames, // Legacy support
          'members': members, // New structure
        });
      }
    }).timeout(const Duration(seconds: 15));

    // Best-effort: create a per-user notification for the newly added member
    // so background FCM (Cloud Function) and foreground local listener can notify.
    try {
      // Attempt to fetch creator name for nicer message
      String addedByName = 'A member';
      try {
        final group = await _groupsCol.doc(groupId).get();
        if (group.exists && group.data() != null) {
          final data = group.data()!;
          final creatorId = data['createdByUserId'] as String? ?? '';
          if (creatorId.isNotEmpty) {
            final userDoc = await _firestore.collection('users').doc(creatorId).get();
            if (userDoc.exists && userDoc.data() != null) {
              addedByName = (userDoc.data()!['name'] as String?)?.trim().isNotEmpty == true
                  ? userDoc.data()!['name'] as String
                  : addedByName;
            }
          }
        }
      } catch (_) {}

      // Fetch group name for message
      String groupNameFallback = '';
      try {
        final g = await _groupsCol.doc(groupId).get();
        if (g.exists && g.data() != null) {
          groupNameFallback = (g.data()!['name'] as String?) ?? '';
        }
      } catch (_) {}

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .add({
        'title': 'Added to group',
        'body': '$addedByName added you to group "${groupNameFallback}"',
        'groupId': groupId,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'type': 'group_added',
        'read': false,
      });
    } catch (_) {
      // Ignore failures; notification is best-effort
    }
  }

  // Remove member from group
  Future<void> removeMemberFromGroup(String groupId, String userId) async {
    final doc = _groupsCol.doc(groupId);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(doc);
      if (!snap.exists) throw Exception('Group not found');
      
      final data = snap.data() as Map<String, dynamic>;
      final memberUserIds = List<String>.from(data['memberUserIds'] ?? []);
      final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
      final members = Map<String, dynamic>.from(data['members'] ?? {});
      
      memberUserIds.remove(userId);
      memberNames.remove(userId); // Legacy support
      members.remove(userId); // New structure
      
      txn.update(doc, {
        'memberUserIds': memberUserIds,
        'memberNames': memberNames, // Legacy support
        'members': members, // New structure
      });
    }).timeout(const Duration(seconds: 15));
  }

  // Get group by ID
  Future<GroupModel?> getGroup(String groupId) async {
    final doc = await _groupsCol.doc(groupId).get();
    if (!doc.exists) return null;
    return GroupModel.fromJson(doc.data()!, doc.id);
  }

  // Populate missing member names for a group
  Future<void> populateMissingMemberNames(String groupId) async {
    final doc = _groupsCol.doc(groupId);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(doc);
      if (!snap.exists) return;
      
      final data = snap.data() as Map<String, dynamic>;
      final memberUserIds = List<String>.from(data['memberUserIds'] ?? []);
      final createdByUserId = data['createdByUserId'] as String? ?? '';
      final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
      final members = Map<String, dynamic>.from(data['members'] ?? {});
      
      // Get all member IDs (including creator)
      final allMemberIds = <String>{createdByUserId};
      allMemberIds.addAll(memberUserIds);
      
      bool hasUpdates = false;
      
      // Check each member and fetch their info if missing or if it looks like a user ID
      for (final userId in allMemberIds) {
        final currentName = memberNames[userId];
        final needsUpdate = currentName == null || 
                           currentName.isEmpty || 
                           currentName == userId || // Name is same as user ID
                           currentName.length > 20; // Likely a Firebase UID
        
        if (needsUpdate) {
          try {
            final userDoc = await _firestore.collection('users').doc(userId).get();
            if (userDoc.exists && userDoc.data() != null) {
              final userData = userDoc.data()!;
              final username = userData['name'] ?? 'User $userId';
              memberNames[userId] = username; // Legacy support
              
              // Update new members structure
              members[userId] = {
                'userId': userId,
                'username': username,
                'email': userData['email'],
              };
            } else {
              final username = 'User $userId';
              memberNames[userId] = username; // Legacy support
              
              // Update new members structure
              members[userId] = {
                'userId': userId,
                'username': username,
              };
            }
            hasUpdates = true;
          } catch (e) {
            final username = 'User $userId';
            memberNames[userId] = username; // Legacy support
            
            // Update new members structure
            members[userId] = {
              'userId': userId,
              'username': username,
            };
            hasUpdates = true;
          }
        }
      }
      
      // Update the document if we found missing names
      if (hasUpdates) {
        txn.update(doc, {
          'memberNames': memberNames, // Legacy support
          'members': members, // New structure
        });
      }
    }).timeout(const Duration(seconds: 15));
  }

  // Migrate existing groups to the new members structure
  Future<void> migrateGroupToNewStructure(String groupId) async {
    final doc = _groupsCol.doc(groupId);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(doc);
      if (!snap.exists) return;
      
      final data = snap.data() as Map<String, dynamic>;
      final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
      final members = Map<String, dynamic>.from(data['members'] ?? {});
      
      // If we already have the new structure, no need to migrate
      if (members.isNotEmpty) return;
      
      // Migrate from legacy memberNames to new members structure
      final newMembers = <String, dynamic>{};
      for (final entry in memberNames.entries) {
        newMembers[entry.key] = {
          'userId': entry.key,
          'username': entry.value,
        };
      }
      
      // Update the document with the new structure
      txn.update(doc, {'members': newMembers});
    }).timeout(const Duration(seconds: 15));
  }

  // Update member name in all groups when user updates their profile
  Future<void> updateMemberNameInAllGroups(String userId, String newName) async {
    try {
      // Find all groups where this user is a member
      final groupsQuery = await _groupsCol
          .where('memberUserIds', arrayContains: userId)
          .get();
      
      final batch = _firestore.batch();
      
      for (final doc in groupsQuery.docs) {
        final data = doc.data();
        final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
        final members = Map<String, dynamic>.from(data['members'] ?? {});
        
        memberNames[userId] = newName; // Legacy support
        
        // Update new members structure
        if (members.containsKey(userId)) {
          members[userId]['username'] = newName;
        } else {
          members[userId] = {
            'userId': userId,
            'username': newName,
          };
        }
        
        batch.update(doc.reference, {
          'memberNames': memberNames, // Legacy support
          'members': members, // New structure
        });
      }
      
      // Also check if user is a group creator
      final creatorGroupsQuery = await _groupsCol
          .where('createdByUserId', isEqualTo: userId)
          .get();
      
      for (final doc in creatorGroupsQuery.docs) {
        final data = doc.data();
        final memberNames = Map<String, String>.from(data['memberNames'] ?? {});
        final members = Map<String, dynamic>.from(data['members'] ?? {});
        
        memberNames[userId] = newName; // Legacy support
        
        // Update new members structure
        if (members.containsKey(userId)) {
          members[userId]['username'] = newName;
        } else {
          members[userId] = {
            'userId': userId,
            'username': newName,
          };
        }
        
        batch.update(doc.reference, {
          'memberNames': memberNames, // Legacy support
          'members': members, // New structure
        });
      }
      
      if (groupsQuery.docs.isNotEmpty || creatorGroupsQuery.docs.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      print('Error updating member name in groups: $e');
      // Don't throw - this is not critical
    }
  }

  // Delete a group: archive group and its expenses, then delete originals
  Future<void> deleteGroupAndExpenses({required String groupId}) async {
    final groupDoc = _groupsCol.doc(groupId);
    final deletedGroupsCol = _firestore.collection('deleted_groups');
    final expensesCol = _firestore.collection('expenses');

    await _firestore.runTransaction((txn) async {
      final groupSnap = await txn.get(groupDoc);
      if (!groupSnap.exists) {
        throw Exception('Group not found');
      }
      final data = groupSnap.data() as Map<String, dynamic>;

      final deletedModel = DeletedGroupModel(
        originalGroupId: groupId,
        name: data['name'] as String? ?? '',
        createdByUserId: data['createdByUserId'] as String? ?? '',
        memberUserIds: List<String>.from(data['memberUserIds'] ?? const <String>[]),
        pendingInviteEmails: List<String>.from(data['pendingInviteEmails'] ?? const <String>[]),
        createdAt: (data['createdAt'] is Timestamp)
            ? (data['createdAt'] as Timestamp).toDate()
            : DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now(),
        memberNames: Map<String, String>.from(data['memberNames'] ?? {}),
        members: Map<String, dynamic>.from(data['members'] ?? {}).map(
          (k, v) => MapEntry(k, MemberInfo.fromJson(Map<String, dynamic>.from(v))),
        ),
        deletedAt: DateTime.now(),
      );

      // Archive group
      final deletedDoc = deletedGroupsCol.doc(groupId);
      txn.set(deletedDoc, deletedModel.toJson());

      // Query expenses for this group
      final expensesSnap = await expensesCol.where('groupId', isEqualTo: groupId).get();

      // Archive each expense into a subcollection under deleted group
      for (final expDoc in expensesSnap.docs) {
        final deletedExpenseDoc = deletedDoc.collection('expenses').doc(expDoc.id);
        txn.set(deletedExpenseDoc, expDoc.data());
        // Delete original expense
        txn.delete(expensesCol.doc(expDoc.id));
      }

      // Finally delete the group document
      txn.delete(groupDoc);
    });
  }
}


