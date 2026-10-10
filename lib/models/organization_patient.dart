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
    this.sharedGenomicProfiles = const [],
    this.prescriptionSharingAllowed = false,
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
  final List<SharedGenomicProfile> sharedGenomicProfiles;
  final bool prescriptionSharingAllowed;

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
        'sharedGenomicProfiles':
            sharedGenomicProfiles.map((profile) => profile.toJson()).toList(),
        'prescriptionSharingAllowed': prescriptionSharingAllowed,
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
      sharedGenomicProfiles: (json['sharedGenomicProfiles'] as List?)
              ?.whereType<Map>()
              .map(
                (profile) => SharedGenomicProfile.fromJson(
                  Map<String, dynamic>.from(profile),
                ),
              )
              .toList(growable: false) ??
          const [],
      prescriptionSharingAllowed:
          json['prescriptionSharingAllowed'] as bool? ?? false,
    );
  }

  factory OrganizationPatient.fromCallable(Map<String, dynamic> json) =>
      OrganizationPatient.fromJson(json);
}

class SharedGenomicProfile {
  const SharedGenomicProfile({
    required this.gene,
    required this.diplotype,
    required this.phenotype,
    required this.isInferred,
  });

  final String gene;
  final String diplotype;
  final String phenotype;
  final bool isInferred;

  Map<String, dynamic> toJson() => {
        'gene': gene,
        'diplotype': diplotype,
        'phenotype': phenotype,
        'isInferred': isInferred,
      };

  factory SharedGenomicProfile.fromJson(Map<String, dynamic> json) =>
      SharedGenomicProfile(
        gene: json['gene'] as String? ?? 'Unknown',
        diplotype: json['diplotype'] as String? ?? 'Unknown',
        phenotype: json['phenotype'] as String? ?? 'Unknown',
        isInferred: json['isInferred'] as bool? ?? true,
      );
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
    this.shareGenomicProfile = false,
    this.allowPrescriptions = false,
    this.requestedAt,
  });

  final String organizationId;
  final String organizationName;
  final String patientUid;
  final String patientId;
  final String patientName;
  final String status;
  final bool consentActive;
  final bool shareGenomicProfile;
  final bool allowPrescriptions;
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
      shareGenomicProfile: json['shareGenomicProfile'] as bool? ?? false,
      allowPrescriptions: json['allowPrescriptions'] as bool? ?? false,
      requestedAt: requestedAt is String
          ? DateTime.tryParse(requestedAt)
          : null,
    );
  }
}
