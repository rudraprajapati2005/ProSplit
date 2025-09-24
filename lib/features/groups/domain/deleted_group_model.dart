import 'member_info.dart';

class DeletedGroupModel {
  final String originalGroupId;
  final String name;
  final String createdByUserId;
  final List<String> memberUserIds;
  final List<String> pendingInviteEmails;
  final DateTime createdAt;
  final Map<String, String> memberNames; // legacy
  final Map<String, MemberInfo> members; // new
  final DateTime deletedAt;

  DeletedGroupModel({
    required this.originalGroupId,
    required this.name,
    required this.createdByUserId,
    required this.memberUserIds,
    required this.pendingInviteEmails,
    required this.createdAt,
    required this.memberNames,
    required this.members,
    required this.deletedAt,
  });

  factory DeletedGroupModel.fromJson(Map<String, dynamic> json) {
    return DeletedGroupModel(
      originalGroupId: json['originalGroupId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdByUserId: json['createdByUserId'] as String? ?? '',
      memberUserIds: List<String>.from(json['memberUserIds'] ?? const <String>[]),
      pendingInviteEmails: List<String>.from(json['pendingInviteEmails'] ?? const <String>[]),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      memberNames: Map<String, String>.from(json['memberNames'] ?? {}),
      members: Map<String, dynamic>.from(json['members'] ?? {}).map(
        (k, v) => MapEntry(k, MemberInfo.fromJson(Map<String, dynamic>.from(v))),
      ),
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'originalGroupId': originalGroupId,
      'name': name,
      'createdByUserId': createdByUserId,
      'memberUserIds': memberUserIds,
      'pendingInviteEmails': pendingInviteEmails,
      'createdAt': createdAt.toIso8601String(),
      'memberNames': memberNames,
      'members': members.map((k, v) => MapEntry(k, v.toJson())),
      'deletedAt': deletedAt.toIso8601String(),
    };
  }
}


