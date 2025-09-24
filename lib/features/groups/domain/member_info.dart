class MemberInfo {
  final String userId;
  final String username;
  final String? email;

  const MemberInfo({
    required this.userId,
    required this.username,
    this.email,
  });

  factory MemberInfo.fromJson(Map<String, dynamic> json) {
    return MemberInfo(
      userId: json['userId'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      if (email != null) 'email': email,
    };
  }

  MemberInfo copyWith({
    String? userId,
    String? username,
    String? email,
  }) {
    return MemberInfo(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      email: email ?? this.email,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MemberInfo &&
        other.userId == userId &&
        other.username == username &&
        other.email == email;
  }

  @override
  int get hashCode => Object.hash(userId, username, email);

  @override
  String toString() => 'MemberInfo(userId: $userId, username: $username, email: $email)';
}

