import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String name;
  final String createdByUserId;
  final List<String> memberUserIds;
  final List<String> pendingInviteEmails;
  final DateTime createdAt;
  final Map<String, String> memberNames; // userId -> displayName mapping

  GroupModel({
    required this.id,
    required this.name,
    required this.createdByUserId,
    required this.memberUserIds,
    required this.pendingInviteEmails,
    required this.createdAt,
    this.memberNames = const {},
  });

  factory GroupModel.fromJson(Map<String, dynamic> json, String id) {
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
      memberNames: (json['memberNames'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value.toString())),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'createdByUserId': createdByUserId,
      'memberUserIds': memberUserIds,
      'pendingInviteEmails': pendingInviteEmails,
      'createdAt': Timestamp.fromDate(createdAt),
      'memberNames': memberNames,
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
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      memberUserIds: memberUserIds ?? this.memberUserIds,
      pendingInviteEmails: pendingInviteEmails ?? this.pendingInviteEmails,
      createdAt: createdAt ?? this.createdAt,
      memberNames: memberNames ?? this.memberNames,
    );
  }

  // Helper methods
  bool isAdmin(String userId) => createdByUserId == userId;
  
  bool isMember(String userId) => memberUserIds.contains(userId);
  
  List<String> get allMemberIds => [createdByUserId, ...memberUserIds];
  
  String getMemberName(String userId) => memberNames[userId] ?? 'Unknown User';
}


