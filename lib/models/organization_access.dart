class OrganizationDirectoryEntry {
  const OrganizationDirectoryEntry({
    required this.organizationId,
    required this.name,
    required this.city,
    this.selfRegistered = false,
    this.active = true,
  });

  final String organizationId;
  final String name;
  final String city;
  final bool selfRegistered;
  final bool active;

  Map<String, dynamic> toJson() => {
        'organizationId': organizationId,
        'name': name,
        'city': city,
        'selfRegistered': selfRegistered,
        'active': active,
      };

  factory OrganizationDirectoryEntry.fromJson(Map<String, dynamic> json) =>
      OrganizationDirectoryEntry(
        organizationId: json['organizationId'] as String? ?? '',
        name: json['name'] as String? ?? 'Organization',
        city: json['city'] as String? ?? '',
        selfRegistered: json['selfRegistered'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
      );
}

class OrganizationAccessRequest {
  const OrganizationAccessRequest({
    required this.organizationId,
    required this.organizationName,
    required this.patientUid,
    required this.patientId,
    required this.patientName,
    required this.status,
    this.requestedAt,
    this.isDirectoryContactRequest = false,
  });

  final String organizationId;
  final String organizationName;
  final String patientUid;
  final String patientId;
  final String patientName;
  final String status;
  final DateTime? requestedAt;
  final bool isDirectoryContactRequest;

  Map<String, dynamic> toJson() => {
        'organizationId': organizationId,
        'organizationName': organizationName,
        'patientUid': patientUid,
        'patientId': patientId,
        'patientName': patientName,
        'status': status,
        'requestedAt': requestedAt?.toIso8601String(),
        'isDirectoryContactRequest': isDirectoryContactRequest,
      };

  factory OrganizationAccessRequest.fromJson(Map<String, dynamic> json) {
    final requestedAt = json['requestedAt'];
    return OrganizationAccessRequest(
      organizationId: json['organizationId'] as String? ?? '',
      organizationName: json['organizationName'] as String? ?? 'Organization',
      patientUid: json['patientUid'] as String? ?? '',
      patientId: json['patientId'] as String? ?? '',
      patientName: json['patientName'] as String? ?? 'Patient',
      status: json['status'] as String? ?? 'pending_org_review',
      requestedAt: requestedAt is DateTime
          ? requestedAt
          : requestedAt is String
          ? DateTime.tryParse(requestedAt)
          : null,
      isDirectoryContactRequest:
          json['isDirectoryContactRequest'] as bool? ?? false,
    );
  }
}

