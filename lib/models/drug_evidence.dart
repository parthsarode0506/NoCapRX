class DrugEvidence {
  final String genericName;
  final String displayName;
  final List<String> aliases;
  final List<String> genes;
  final List<String> relevantVariants;
  final List<String> phenotypes;
  final String guidelineCitation;
  final String dosingRecommendation;
  final List<String> alternativeDrugs;
  final String monitoringAdvice;
  final String mechanism;
  final String evidenceLevel; // e.g. "CPIC Level A", "FDA Table of Biomarkers", "PharmGKB 1A"
  final String source; // e.g. "CPIC / PharmGKB / FDA"
  final bool clinicallyActionable;
  final bool hasPgxRelationship;
  final List<String> requiredClinicalData;
  final String retrievalTimestamp;
  final bool isOnlineDiscovered;
    final List<String> activeIngredients;
    final String? strength;
    final String? dosageForm;
    final bool verifiedMedicine;
    final double identityConfidence;

  const DrugEvidence({
    required this.genericName,
    required this.displayName,
    this.aliases = const [],
    this.genes = const [],
    this.relevantVariants = const [],
    this.phenotypes = const [],
    this.guidelineCitation = '',
    this.dosingRecommendation = '',
    this.alternativeDrugs = const [],
    this.monitoringAdvice = '',
    this.mechanism = '',
    this.evidenceLevel = 'CPIC Validated',
    this.source = 'CPIC Guidelines & PharmGKB Database',
    this.clinicallyActionable = true,
    this.hasPgxRelationship = true,
    this.requiredClinicalData = const [],
    required this.retrievalTimestamp,
    this.isOnlineDiscovered = false,
    this.activeIngredients = const [],
    this.strength,
    this.dosageForm,
    this.verifiedMedicine = true,
    this.identityConfidence = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'generic_name': genericName,
        'display_name': displayName,
        'aliases': aliases,
        'genes': genes,
        'relevant_variants': relevantVariants,
        'phenotypes': phenotypes,
        'guideline_citation': guidelineCitation,
        'dosing_recommendation': dosingRecommendation,
        'alternative_drugs': alternativeDrugs,
        'monitoring_advice': monitoringAdvice,
        'mechanism': mechanism,
        'evidence_level': evidenceLevel,
        'source': source,
        'clinically_actionable': clinicallyActionable,
        'has_pgx_relationship': hasPgxRelationship,
        'required_clinical_data': requiredClinicalData,
        'retrieval_timestamp': retrievalTimestamp,
        'is_online_discovered': isOnlineDiscovered,
        'active_ingredients': activeIngredients,
        'strength': strength,
        'dosage_form': dosageForm,
        'verified_medicine': verifiedMedicine,
        'identity_confidence': identityConfidence,
      };

  factory DrugEvidence.fromJson(Map<String, dynamic> json) => DrugEvidence(
        genericName: json['generic_name'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        aliases: (json['aliases'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        genes: (json['genes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        relevantVariants: (json['relevant_variants'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        phenotypes: (json['phenotypes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        guidelineCitation: json['guideline_citation'] as String? ?? '',
        dosingRecommendation: json['dosing_recommendation'] as String? ?? '',
        alternativeDrugs: (json['alternative_drugs'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        monitoringAdvice: json['monitoring_advice'] as String? ?? '',
        mechanism: json['mechanism'] as String? ?? '',
        evidenceLevel: json['evidence_level'] as String? ?? 'CPIC Validated',
        source: json['source'] as String? ?? 'CPIC / PharmGKB',
        clinicallyActionable: json['clinically_actionable'] as bool? ?? true,
        hasPgxRelationship: json['has_pgx_relationship'] as bool? ?? true,
        requiredClinicalData: (json['required_clinical_data'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        retrievalTimestamp: json['retrieval_timestamp'] as String? ??
            DateTime.now().toIso8601String(),
        isOnlineDiscovered: json['is_online_discovered'] as bool? ?? false,
        activeIngredients: (json['active_ingredients'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        strength: json['strength'] as String?,
        dosageForm: json['dosage_form'] as String?,
        verifiedMedicine: json['verified_medicine'] as bool? ?? true,
        identityConfidence:
            (json['identity_confidence'] as num?)?.toDouble() ?? 0.0,
      );
}
