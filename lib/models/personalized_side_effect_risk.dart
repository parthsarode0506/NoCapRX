class PersonalizedSideEffectRisk {
  final String sideEffect;
  final String severity;
  final String frequency;
  final List<String> higherRiskGroups;
  final List<String> patientRiskFactors;
  final String relevance;
  final String explanation;
  final List<String> evidenceSources;

  const PersonalizedSideEffectRisk({
    required this.sideEffect,
    required this.severity,
    required this.frequency,
    required this.higherRiskGroups,
    required this.patientRiskFactors,
    required this.relevance,
    required this.explanation,
    required this.evidenceSources,
  });

  Map<String, dynamic> toJson() => {
        'side_effect': sideEffect,
        'severity': severity,
        'frequency': frequency,
        'higher_risk_groups': higherRiskGroups,
        'patient_risk_factors': patientRiskFactors,
        'relevance': relevance,
        'explanation': explanation,
        'evidence_sources': evidenceSources,
      };

  factory PersonalizedSideEffectRisk.fromJson(Map<String, dynamic> json) =>
      PersonalizedSideEffectRisk(
        sideEffect: json['side_effect'] as String? ?? '',
        severity: json['severity'] as String? ?? 'unknown',
        frequency: json['frequency'] as String? ?? 'unknown',
        higherRiskGroups: _strings(json['higher_risk_groups']),
        patientRiskFactors: _strings(json['patient_risk_factors']),
        relevance: json['relevance'] as String? ?? 'CANNOT_ASSESS',
        explanation: json['explanation'] as String? ?? '',
        evidenceSources: _strings(json['evidence_sources']),
      );

  static List<String> _strings(dynamic value) => value is List
      ? value.map((item) => item.toString()).toList()
      : const [];
}
