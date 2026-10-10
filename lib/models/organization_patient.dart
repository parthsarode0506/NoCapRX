class OrganizationPatient {
  const OrganizationPatient({
    required this.patientId,
    required this.name,
    this.birthYear,
    this.vcfStatus = 'not_uploaded',
    this.analysisStatus = 'not_started',
    this.latestReportAt,
    this.reportCount = 0,
    this.prescriptionCount = 0,
  });

  final String patientId;
  final String name;
  final int? birthYear;
  final String vcfStatus;
  final String analysisStatus;
  final DateTime? latestReportAt;
  final int reportCount;
  final int prescriptionCount;

  factory OrganizationPatient.fromCallable(Map<String, dynamic> json) {
    final reportDate = json['latestReportAt'];
    return OrganizationPatient(
      patientId: json['patientId'] as String? ?? '',
      name: json['name'] as String? ?? 'Patient',
      birthYear: (json['birthYear'] as num?)?.toInt(),
      vcfStatus: json['vcfStatus'] as String? ?? 'not_uploaded',
      analysisStatus: json['analysisStatus'] as String? ?? 'not_started',
      latestReportAt: reportDate is String
          ? DateTime.tryParse(reportDate)
          : null,
      reportCount: (json['reportCount'] as num?)?.toInt() ?? 0,
      prescriptionCount: (json['prescriptionCount'] as num?)?.toInt() ?? 0,
    );
  }
}
