import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/group_model.dart';

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
  }) async {
    final doc = _groupsCol.doc();
    final model = GroupModel(
      id: doc.id,
      name: name,
      createdByUserId: createdByUserId,
      memberUserIds: initialMemberUserIds,
      pendingInviteEmails: inviteEmails,
      createdAt: DateTime.now(),
    );
    await doc.set(model.toJson()).timeout(const Duration(seconds: 15));
    return doc.id;
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
      
      if (!memberUserIds.contains(userId)) {
        memberUserIds.add(userId);
      }
      pendingInviteEmails.removeWhere((e) => e.toLowerCase() == userEmail.toLowerCase());
      
      // Add member name (you might want to get this from user profile)
      memberNames[userId] = userEmail.split('@')[0]; // Use email prefix as name
      
      txn.update(doc, {
        'memberUserIds': memberUserIds,
        'pendingInviteEmails': pendingInviteEmails,
        'memberNames': memberNames,
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
      
      if (!memberUserIds.contains(userId)) {
        memberUserIds.add(userId);
        memberNames[userId] = userName;
        
        txn.update(doc, {
          'memberUserIds': memberUserIds,
          'memberNames': memberNames,
        });
      }
    }).timeout(const Duration(seconds: 15));
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
      
      memberUserIds.remove(userId);
      memberNames.remove(userId);
      
      txn.update(doc, {
        'memberUserIds': memberUserIds,
        'memberNames': memberNames,
      });
    }).timeout(const Duration(seconds: 15));
  }

  // Get group by ID
  Future<GroupModel?> getGroup(String groupId) async {
    final doc = await _groupsCol.doc(groupId).get();
    if (!doc.exists) return null;
    return GroupModel.fromJson(doc.data()!, doc.id);
  }
}


