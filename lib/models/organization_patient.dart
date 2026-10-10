class OrganizationPatient {
  const OrganizationPatient({
    required this.patientId,
    required this.name,
    this.patientUid,
    this.birthYear,
    this.vcfStatus = 'not_shared',
    this.analysisStatus = 'not_available',
    this.vcfFileName,
    this.latestReportAt,
    this.reportCount,
    this.prescriptionCount,
  });

  final String patientId;
  final String name;
  final String? patientUid;
  final int? birthYear;
  final String vcfStatus;
  final String analysisStatus;
  final String? vcfFileName;
  final DateTime? latestReportAt;
  final int? reportCount;
  final int? prescriptionCount;

  Map<String, dynamic> toJson() => {
        'patientId': patientId,
        'name': name,
        'patientUid': patientUid,
        'birthYear': birthYear,
        'vcfStatus': vcfStatus,
        'analysisStatus': analysisStatus,
        'vcfFileName': vcfFileName,
        'latestReportAt': latestReportAt?.toIso8601String(),
        'reportCount': reportCount,
        'prescriptionCount': prescriptionCount,
      };

  factory OrganizationPatient.fromJson(Map<String, dynamic> json) {
    final reportDate = json['latestReportAt'];
    return OrganizationPatient(
      patientId: json['patientId'] as String? ?? '',
      name: json['name'] as String? ?? 'Patient',
      patientUid: json['patientUid'] as String?,
      birthYear: (json['birthYear'] as num?)?.toInt(),
      vcfStatus: json['vcfStatus'] as String? ?? 'not_shared',
      analysisStatus: json['analysisStatus'] as String? ?? 'not_available',
      vcfFileName: json['vcfFileName'] as String?,
      latestReportAt: reportDate is DateTime
          ? reportDate
          : reportDate is String
          ? DateTime.tryParse(reportDate)
          : null,
      reportCount: (json['reportCount'] as num?)?.toInt(),
      prescriptionCount: (json['prescriptionCount'] as num?)?.toInt(),
    );
  }

  factory OrganizationPatient.fromCallable(Map<String, dynamic> json) =>
      OrganizationPatient.fromJson(json);
}

class PatientInvitationPreview {
  const PatientInvitationPreview({
    required this.patientId,
    required this.patientName,
    required this.organizationName,
    required this.organizationCity,
  });

  final String patientId;
  final String patientName;
  final String organizationName;
  final String organizationCity;

  factory PatientInvitationPreview.fromCallable(Map<String, dynamic> json) =>
      PatientInvitationPreview(
        patientId: json['patientId'] as String? ?? '',
        patientName: json['patientName'] as String? ?? 'Patient',
        organizationName: json['organizationName'] as String? ?? 'Organization',
        organizationCity: json['organizationCity'] as String? ?? '',
      );
}

class PatientOrganizationInvitation {
  const PatientOrganizationInvitation({
    required this.organizationId,
    required this.organizationName,
    required this.patientUid,
    required this.patientId,
    required this.patientName,
    required this.status,
    this.consentActive = false,
    this.requestedAt,
  });

  final String organizationId;
  final String organizationName;
  final String patientUid;
  final String patientId;
  final String patientName;
  final String status;
  final bool consentActive;
  final DateTime? requestedAt;

  factory PatientOrganizationInvitation.fromCallable(
    Map<String, dynamic> json,
  ) {
    final requestedAt = json['requestedAt'];
    return PatientOrganizationInvitation(
      organizationId: json['organizationId'] as String? ?? '',
      organizationName: json['organizationName'] as String? ?? 'Organization',
      patientUid: json['patientUid'] as String? ?? '',
      patientId: json['patientId'] as String? ?? '',
      patientName: json['patientName'] as String? ?? 'Patient',
      status: json['status'] as String? ?? 'pending_org_review',
      consentActive: json['consentActive'] as bool? ?? false,
      requestedAt: requestedAt is String
          ? DateTime.tryParse(requestedAt)
          : null,
    );
  }
}
