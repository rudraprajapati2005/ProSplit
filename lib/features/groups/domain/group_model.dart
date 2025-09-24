import 'package:cloud_firestore/cloud_firestore.dart';
import 'member_info.dart';

class GroupModel {
  final String id;
  final String name;
  final String createdByUserId;
  final List<String> memberUserIds;
  final List<String> pendingInviteEmails;
  final DateTime createdAt;
  final Map<String, String> memberNames; // userId -> displayName mapping (legacy)
  final Map<String, MemberInfo> members; // userId -> MemberInfo mapping (new)

  GroupModel({
    required this.id,
    required this.name,
    required this.createdByUserId,
    required this.memberUserIds,
    required this.pendingInviteEmails,
    required this.createdAt,
    this.memberNames = const {},
    this.members = const {},
  });

  factory GroupModel.fromJson(Map<String, dynamic> json, String id) {
    // Parse legacy memberNames
    final memberNames = (json['memberNames'] as Map<String, dynamic>? ?? {})
        .map((key, value) => MapEntry(key, value.toString()));
    
    // Parse new members structure
    final members = <String, MemberInfo>{};
    if (json['members'] != null) {
      final membersData = json['members'] as Map<String, dynamic>;
      for (final entry in membersData.entries) {
        try {
          members[entry.key] = MemberInfo.fromJson(entry.value as Map<String, dynamic>);
        } catch (e) {
          // If parsing fails, skip this member
          print('Error parsing member info for ${entry.key}: $e');
        }
      }
    }
    
    return GroupModel(
      id: id,
      name: json['name'] as String? ?? '',
      createdByUserId: json['createdByUserId'] as String? ?? '',
      memberUserIds: (json['memberUserIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      pendingInviteEmails:
          (json['pendingInviteEmails'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
      createdAt: (json['createdAt'] is Timestamp)
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
              DateTime.now(),
      memberNames: memberNames,
      members: members,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'createdByUserId': createdByUserId,
      'memberUserIds': memberUserIds,
      'pendingInviteEmails': pendingInviteEmails,
      'createdAt': Timestamp.fromDate(createdAt),
      'memberNames': memberNames, // Keep for backward compatibility
      'members': members.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  GroupModel copyWith({
    String? id,
    String? name,
    String? createdByUserId,
    List<String>? memberUserIds,
    List<String>? pendingInviteEmails,
    DateTime? createdAt,
    Map<String, String>? memberNames,
    Map<String, MemberInfo>? members,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      memberUserIds: memberUserIds ?? this.memberUserIds,
      pendingInviteEmails: pendingInviteEmails ?? this.pendingInviteEmails,
      createdAt: createdAt ?? this.createdAt,
      memberNames: memberNames ?? this.memberNames,
      members: members ?? this.members,
    );
  }

  // Helper methods
  bool isAdmin(String userId) => createdByUserId == userId;
  
  bool isMember(String userId) => memberUserIds.contains(userId);
  
  List<String> get allMemberIds {
    final allIds = <String>{createdByUserId};
    allIds.addAll(memberUserIds);
    return allIds.toList();
  }
  
  String getMemberName(String userId) {
    if (userId.isEmpty) return 'Unknown User';
    
    // First try the new members structure
    if (members.containsKey(userId)) {
      return members[userId]!.username;
    }
    
    // Fall back to legacy memberNames
    return memberNames[userId] ?? userId; // fall back to identifier which might be a readable name
  }
  
  MemberInfo? getMemberInfo(String userId) {
    return members[userId];
  }
  
  // Get all member info for display purposes
  List<MemberInfo> getAllMemberInfo() {
    final allMemberIds = <String>{createdByUserId};
    allMemberIds.addAll(memberUserIds);
    
    return allMemberIds.map((id) {
      if (members.containsKey(id)) {
        return members[id]!;
      } else {
        // Create a MemberInfo from legacy data
        return MemberInfo(
          userId: id,
          username: memberNames[id] ?? 'User $id',
        );
      }
    }).toList();
  }
}


