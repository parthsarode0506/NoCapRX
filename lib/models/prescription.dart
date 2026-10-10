class PrescriptionItem {
  final String medicineName;
  final String dosage;
  final String frequency;
  final String duration;
  final String instructions;
  final String pgxRiskLabel; // Safe, Adjust Dosage, Toxic, Ineffective, Unknown
  final String severity; // none, low, moderate, high, critical
  final String? gene;
  final String? phenotype;
  final String? recommendation;
  final List<String> alternativeDrugs;

  const PrescriptionItem({
    required this.medicineName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    this.instructions = '',
    this.pgxRiskLabel = 'Safe',
    this.severity = 'none',
    this.gene,
    this.phenotype,
    this.recommendation,
    this.alternativeDrugs = const [],
  });

  bool get isActionableRisk =>
      pgxRiskLabel == 'Toxic' ||
      pgxRiskLabel == 'Ineffective' ||
      severity == 'critical' ||
      severity == 'high';

  bool get isCaution =>
      pgxRiskLabel == 'Adjust Dosage' || severity == 'moderate';

  Map<String, dynamic> toJson() => {
        'medicineName': medicineName,
        'dosage': dosage,
        'frequency': frequency,
        'duration': duration,
        'instructions': instructions,
        'pgxRiskLabel': pgxRiskLabel,
        'severity': severity,
        'gene': gene,
        'phenotype': phenotype,
        'recommendation': recommendation,
        'alternativeDrugs': alternativeDrugs,
      };

  factory PrescriptionItem.fromJson(Map<String, dynamic> json) =>
      PrescriptionItem(
        medicineName: json['medicineName'] as String? ?? '',
        dosage: json['dosage'] as String? ?? '',
        frequency: json['frequency'] as String? ?? '',
        duration: json['duration'] as String? ?? '',
        instructions: json['instructions'] as String? ?? '',
        pgxRiskLabel: json['pgxRiskLabel'] as String? ?? 'Safe',
        severity: json['severity'] as String? ?? 'none',
        gene: json['gene'] as String?,
        phenotype: json['phenotype'] as String?,
        recommendation: json['recommendation'] as String?,
        alternativeDrugs: (json['alternativeDrugs'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  PrescriptionItem copyWith({
    String? medicineName,
    String? dosage,
    String? frequency,
    String? duration,
    String? instructions,
    String? pgxRiskLabel,
    String? severity,
    String? gene,
    String? phenotype,
    String? recommendation,
    List<String>? alternativeDrugs,
  }) =>
      PrescriptionItem(
        medicineName: medicineName ?? this.medicineName,
        dosage: dosage ?? this.dosage,
        frequency: frequency ?? this.frequency,
        duration: duration ?? this.duration,
        instructions: instructions ?? this.instructions,
        pgxRiskLabel: pgxRiskLabel ?? this.pgxRiskLabel,
        severity: severity ?? this.severity,
        gene: gene ?? this.gene,
        phenotype: phenotype ?? this.phenotype,
        recommendation: recommendation ?? this.recommendation,
        alternativeDrugs: alternativeDrugs ?? this.alternativeDrugs,
      );
}

class Prescription {
  final String prescriptionId;
  final String patientId;
  final String patientName;
  final String? patientUid;
  final String organizationId;
  final String organizationName;
  final String prescriberId;
  final String prescriberName;
  final List<PrescriptionItem> items;
  final String status; // 'draft', 'issued', 'cancelled'
  final String notes;
  final DateTime createdAt;
  final DateTime? issuedAt;

  const Prescription({
    required this.prescriptionId,
    required this.patientId,
    required this.patientName,
    this.patientUid,
    required this.organizationId,
    required this.organizationName,
    required this.prescriberId,
    required this.prescriberName,
    required this.items,
    this.status = 'draft',
    this.notes = '',
    required this.createdAt,
    this.issuedAt,
  });

  bool get isIssued => status == 'issued';
  bool get isDraft => status == 'draft';
  bool get isCancelled => status == 'cancelled';

  bool get hasActionableRisks => items.any((i) => i.isActionableRisk);

  Map<String, dynamic> toJson() => {
        'prescriptionId': prescriptionId,
        'patientId': patientId,
        'patientName': patientName,
        'patientUid': patientUid,
        'organizationId': organizationId,
        'organizationName': organizationName,
        'prescriberId': prescriberId,
        'prescriberName': prescriberName,
        'items': items.map((i) => i.toJson()).toList(),
        'status': status,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'issuedAt': issuedAt?.toIso8601String(),
      };

  factory Prescription.fromJson(Map<String, dynamic> json) => Prescription(
        prescriptionId: json['prescriptionId'] as String? ?? '',
        patientId: json['patientId'] as String? ?? '',
        patientName: json['patientName'] as String? ?? 'Patient',
        patientUid: json['patientUid'] as String?,
        organizationId: json['organizationId'] as String? ?? '',
        organizationName:
            json['organizationName'] as String? ?? 'Medical Center',
        prescriberId: json['prescriberId'] as String? ?? '',
        prescriberName: json['prescriberName'] as String? ?? 'Prescribing Clinician',
        items: (json['items'] as List?)
                ?.map((i) => PrescriptionItem.fromJson(
                    Map<String, dynamic>.from(i as Map)))
                .toList() ??
            const [],
        status: json['status'] as String? ?? 'draft',
        notes: json['notes'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        issuedAt: json['issuedAt'] != null
            ? DateTime.tryParse(json['issuedAt'].toString())
            : null,
      );

  Prescription copyWith({
    String? prescriptionId,
    String? patientId,
    String? patientName,
    String? patientUid,
    String? organizationId,
    String? organizationName,
    String? prescriberId,
    String? prescriberName,
    List<PrescriptionItem>? items,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? issuedAt,
  }) =>
      Prescription(
        prescriptionId: prescriptionId ?? this.prescriptionId,
        patientId: patientId ?? this.patientId,
        patientName: patientName ?? this.patientName,
        patientUid: patientUid ?? this.patientUid,
        organizationId: organizationId ?? this.organizationId,
        organizationName: organizationName ?? this.organizationName,
        prescriberId: prescriberId ?? this.prescriberId,
        prescriberName: prescriberName ?? this.prescriberName,
        items: items ?? this.items,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        issuedAt: issuedAt ?? this.issuedAt,
      );
}
