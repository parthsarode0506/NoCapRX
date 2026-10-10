class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String role;
  final String locale;
  final DateTime? createdAt;
  final String organizationName;
  final String city;
  final String? linkedPatientId;
  final int? linkedPatientBirthYear;
  final String linkedOrganizationId;
  final String linkedOrganizationName;
  final String linkedOrganizationCity;

  AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    this.locale = 'en',
    this.createdAt,
    this.organizationName = '',
    this.city = '',
    this.linkedPatientId,
    this.linkedPatientBirthYear,
    this.linkedOrganizationId = '',
    this.linkedOrganizationName = '',
    this.linkedOrganizationCity = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'accountType': role,
      'locale': locale,
      'createdAt': createdAt?.toIso8601String(),
      'organizationName': organizationName,
      'city': city,
      'linkedPatientId': linkedPatientId,
      'linkedPatientBirthYear': linkedPatientBirthYear,
      'linkedOrganizationId': linkedOrganizationId,
      'linkedOrganizationName': linkedOrganizationName,
      'linkedOrganizationCity': linkedOrganizationCity,
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
      organizationName: json['organizationName'] as String? ?? '',
      city: json['city'] as String? ?? '',
      linkedPatientId: json['linkedPatientId'] as String?,
      linkedPatientBirthYear: (json['linkedPatientBirthYear'] as num?)?.toInt(),
      linkedOrganizationId: json['linkedOrganizationId'] as String? ?? '',
      linkedOrganizationName: json['linkedOrganizationName'] as String? ?? '',
      linkedOrganizationCity: json['linkedOrganizationCity'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}
