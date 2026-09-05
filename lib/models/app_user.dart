class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String role; // "Patient" or "Clinician"
  final DateTime? createdAt;

  AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'role': role,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      uid: json['uid'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'Patient',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}
