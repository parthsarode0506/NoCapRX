class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String role;
  final String locale;
  final DateTime? createdAt;

  AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    this.locale = 'en',
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'accountType': role,
      'locale': locale,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      uid: json['uid'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      role:
          json['accountType'] as String? ??
          json['role'] as String? ??
          'patient',
      locale: json['locale'] as String? ?? 'en',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}
