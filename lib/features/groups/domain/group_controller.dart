import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../data/group_repository.dart';
import 'group_model.dart';

final groupControllerProvider = StateNotifierProvider<GroupController, AsyncValue<List<GroupModel>>>((ref) {
  final repo = ref.watch(groupRepositoryProvider);
  final auth = ref.watch(authControllerProvider).value;
  return GroupController(repo, currentUserId: auth?.id);
});

final pendingInvitesProvider = StreamProvider.family<List<GroupModel>, String>((ref, email) {
  return ref.watch(groupRepositoryProvider).streamPendingInvitesForEmail(email);
});

class GroupController extends StateNotifier<AsyncValue<List<GroupModel>>> {
  final GroupRepository _repo;
  final String? currentUserId;

  GroupController(this._repo, {required this.currentUserId}) : super(const AsyncValue.loading()) {
    if (currentUserId != null) {
      _repo.streamUserGroups(currentUserId!).listen(
        (groups) => state = AsyncValue.data(groups),
        onError: (e, st) => state = AsyncValue.error(e, st),
      );
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<String> createGroup({required String name, required String creatorUserId, required List<String> inviteEmails}) async {
    return _repo.createGroup(
      name: name,
      createdByUserId: creatorUserId,
      initialMemberUserIds: [creatorUserId],
      inviteEmails: inviteEmails,
    );
  }

  Future<void> acceptInvite(String groupId, String userId, String userEmail) {
    return _repo.acceptInvite(groupId: groupId, userId: userId, userEmail: userEmail);
  }

  // Add member to group (only admin can do this)
  Future<void> addMemberToGroup(String groupId, String userId, String userName) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    
    final groups = state.value ?? [];
    final group = groups.firstWhere((g) => g.id == groupId);
    
    if (!group.isAdmin(currentUserId!)) {
      throw Exception('Only group admin can add members');
    }
    
    await _repo.addMemberToGroup(groupId, userId, userName);
  }

  // Remove member from group (only admin can do this)
  Future<void> removeMemberFromGroup(String groupId, String userId) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    
    final groups = state.value ?? [];
    final group = groups.firstWhere((g) => g.id == groupId);
    
    if (!group.isAdmin(currentUserId!)) {
      throw Exception('Only group admin can remove members');
    }
    
    if (group.createdByUserId == userId) {
      throw Exception('Cannot remove group admin');
    }
    
    await _repo.removeMemberFromGroup(groupId, userId);
  }

  // Leave group (member can leave, admin cannot)
  Future<void> leaveGroup(String groupId) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    
    final groups = state.value ?? [];
    final group = groups.firstWhere((g) => g.id == groupId);
    
    if (group.isAdmin(currentUserId!)) {
      throw Exception('Group admin cannot leave. Transfer admin rights first.');
    }
    
    await _repo.removeMemberFromGroup(groupId, currentUserId!);
  }

  // Get group details
  Future<GroupModel?> getGroup(String groupId) async {
    return await _repo.getGroup(groupId);
  }
}


