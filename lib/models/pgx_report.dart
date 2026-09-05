import 'dart:convert';

import 'drug_evidence.dart';
import 'personalized_side_effect_risk.dart';

/// Represents a single variant detected in the patient's VCF.
class DetectedVariant {
  final String rsid;
  final String? gene;
  final String? starAllele;

  DetectedVariant({
    required this.rsid,
    this.gene,
    this.starAllele,
  });

  Map<String, dynamic> toJson() {
    return {
      'rsid': rsid,
      if (gene != null) 'gene': gene,
      if (starAllele != null) 'star_allele': starAllele,
    };
  }

  factory DetectedVariant.fromJson(Map<String, dynamic> json) {
    return DetectedVariant(
      rsid: json['rsid'] as String? ?? 'rsUnknown',
      gene: json['gene'] as String?,
      starAllele: json['star_allele'] as String?,
    );
  }
}

/// Represents the risk assessment output.
class RiskAssessment {
  final String riskLabel; // Safe, Adjust Dosage, Toxic, Ineffective, Unknown
  final double confidenceScore; // 0.0 to 1.0
  final String severity; // none, low, moderate, high, critical

  RiskAssessment({
    required this.riskLabel,
    required this.confidenceScore,
    required this.severity,
  });

  Map<String, dynamic> toJson() {
    return {
      'risk_label': riskLabel,
      'confidence_score': confidenceScore,
      'severity': severity,
    };
  }

  factory RiskAssessment.fromJson(Map<String, dynamic> json) {
    return RiskAssessment(
      riskLabel: json['risk_label'] as String? ?? 'Unknown',
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      severity: json['severity'] as String? ?? 'none',
    );
  }
}

/// Represents the PGx profile for a gene.
class PharmacogenomicProfile {
  final String primaryGene;
  final String diplotype;
  final String phenotype;
  final List<DetectedVariant> detectedVariants;

  PharmacogenomicProfile({
    required this.primaryGene,
    required this.diplotype,
    required this.phenotype,
    required this.detectedVariants,
  });

  Map<String, dynamic> toJson() {
    return {
      'primary_gene': primaryGene,
      'diplotype': diplotype,
      'phenotype': phenotype,
      'detected_variants': detectedVariants.map((v) => v.toJson()).toList(),
    };
  }

  factory PharmacogenomicProfile.fromJson(Map<String, dynamic> json) {
    var rawVariants = json['detected_variants'] as List<dynamic>? ?? [];
    return PharmacogenomicProfile(
      primaryGene: json['primary_gene'] as String? ?? 'Unknown',
      diplotype: json['diplotype'] as String? ?? '*1/*1',
      phenotype: json['phenotype'] as String? ?? 'Unknown',
      detectedVariants: rawVariants
          .map((v) => DetectedVariant.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Represents CPIC clinical recommendations.
class ClinicalRecommendation {
  final String cpicGuidelineCitation;
  final String dosingRecommendation;
  final List<String> alternativeDrugs;
  final String monitoringAdvice;
  final String evidenceLevel;
  final String evidenceSource;
  final String evidenceRetrievedAt;

  ClinicalRecommendation({
    required this.cpicGuidelineCitation,
    required this.dosingRecommendation,
    required this.alternativeDrugs,
    required this.monitoringAdvice,
    this.evidenceLevel = '',
    this.evidenceSource = '',
    this.evidenceRetrievedAt = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'cpic_guideline_citation': cpicGuidelineCitation,
      'dosing_recommendation': dosingRecommendation,
      'alternative_drugs': alternativeDrugs,
      'monitoring_advice': monitoringAdvice,
      if (evidenceLevel.isNotEmpty) 'evidence_level': evidenceLevel,
      if (evidenceSource.isNotEmpty) 'evidence_source': evidenceSource,
      if (evidenceRetrievedAt.isNotEmpty)
        'evidence_retrieved_at': evidenceRetrievedAt,
    };
  }

  factory ClinicalRecommendation.fromJson(Map<String, dynamic> json) {
    var rawAlts = json['alternative_drugs'] as List<dynamic>? ?? [];
    return ClinicalRecommendation(
      cpicGuidelineCitation: json['cpic_guideline_citation'] as String? ?? '',
      dosingRecommendation: json['dosing_recommendation'] as String? ?? '',
      alternativeDrugs: rawAlts.map((e) => e.toString()).toList(),
      monitoringAdvice: json['monitoring_advice'] as String? ?? '',
      evidenceLevel: json['evidence_level'] as String? ?? '',
      evidenceSource: json['evidence_source'] as String? ?? '',
      evidenceRetrievedAt: json['evidence_retrieved_at'] as String? ?? '',
    );
  }
}

/// Represents LLM-generated explanation.
class LlmExplanation {
  final String summary;
  final String mechanism;
  final String patientFriendly;
  final String clinicianNote;

  LlmExplanation({
    required this.summary,
    required this.mechanism,
    required this.patientFriendly,
    required this.clinicianNote,
  });

  Map<String, dynamic> toJson() {
    return {
      'summary': summary,
      'mechanism': mechanism,
      'patient_friendly': patientFriendly,
      'clinician_note': clinicianNote,
    };
  }

  factory LlmExplanation.fromJson(Map<String, dynamic> json) {
    return LlmExplanation(
      summary: json['summary'] as String? ?? '',
      mechanism: json['mechanism'] as String? ?? '',
      patientFriendly: json['patient_friendly'] as String? ?? '',
      clinicianNote: json['clinician_note'] as String? ?? '',
    );
  }
}

/// Represents quality metrics for the VCF parsing run.
class QualityMetrics {
  final bool vcfParsingSuccess;
  final int variantsDetected;
  final List<String> genesCovered;
  final bool diplotypeInferred;
  final double annotationCompleteness;

  QualityMetrics({
    required this.vcfParsingSuccess,
    required this.variantsDetected,
    required this.genesCovered,
    required this.diplotypeInferred,
    required this.annotationCompleteness,
  });

  Map<String, dynamic> toJson() {
    return {
      'vcf_parsing_success': vcfParsingSuccess,
      'variants_detected': variantsDetected,
      'genes_covered': genesCovered,
      'diplotype_inferred': diplotypeInferred,
      'annotation_completeness': annotationCompleteness,
    };
  }

  factory QualityMetrics.fromJson(Map<String, dynamic> json) {
    var rawGenes = json['genes_covered'] as List<dynamic>? ?? [];
    return QualityMetrics(
      vcfParsingSuccess: json['vcf_parsing_success'] as bool? ?? false,
      variantsDetected: json['variants_detected'] as int? ?? 0,
      genesCovered: rawGenes.map((e) => e.toString()).toList(),
      diplotypeInferred: json['diplotype_inferred'] as bool? ?? false,
      annotationCompleteness:
          (json['annotation_completeness'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// The exact hackathon output report schema contract.
class PgxReport {
  final String patientId;
  final String drug;
  final String timestamp;
  final RiskAssessment riskAssessment;
  final PharmacogenomicProfile pharmacogenomicProfile;
  final ClinicalRecommendation clinicalRecommendation;
  final LlmExplanation llmGeneratedExplanation;
  final QualityMetrics qualityMetrics;
  final DrugEvidence? evidence;
  final List<PersonalizedSideEffectRisk> personalizedSideEffects;

  PgxReport({
    required this.patientId,
    required this.drug,
    required this.timestamp,
    required this.riskAssessment,
    required this.pharmacogenomicProfile,
    required this.clinicalRecommendation,
    required this.llmGeneratedExplanation,
    required this.qualityMetrics,
    this.evidence,
    this.personalizedSideEffects = const [],
  });

  Map<String, dynamic> toJson() {
    final missingInformation = evidence?.requiredClinicalData ?? const <String>[];
    final finalStatus = riskAssessment.riskLabel == 'No major risk identified'
        ? 'NO_MAJOR_RISK_IDENTIFIED'
        : riskAssessment.riskLabel.toUpperCase().replaceAll(' ', '_');
    return {
      'patient_id': patientId,
      'drug': drug,
      if (evidence != null)
        'medicine_identity': {
          'verified': evidence!.verifiedMedicine,
          'generic_name': evidence!.genericName,
          'display_name': evidence!.displayName,
          'active_ingredients': evidence!.activeIngredients,
          'strength': evidence!.strength,
          'dosage_form': evidence!.dosageForm,
          'confidence': evidence!.identityConfidence,
        },
      'timestamp': timestamp,
      'risk_assessment': riskAssessment.toJson(),
      'pharmacogenomic_profile': pharmacogenomicProfile.toJson(),
      'clinical_recommendation': clinicalRecommendation.toJson(),
      'llm_generated_explanation': llmGeneratedExplanation.toJson(),
      'quality_metrics': qualityMetrics.toJson(),
      if (evidence != null) 'evidence': evidence!.toJson(),
        'personalized_side_effects': personalizedSideEffects
          .map((risk) => risk.toJson())
          .toList(),
      if (evidence != null)
        'pgx_assessment': {
          'has_pgx_relationship': evidence!.hasPgxRelationship,
          'status': evidence!.hasPgxRelationship
              ? 'PGX_EVALUATED_OR_INCOMPLETE'
              : 'NO_ACTIONABLE_PGX_FINDING',
        },
      'missing_information': riskAssessment.confidenceScore == 0.0
          ? missingInformation
          : const <String>[],
      'final_assessment': {'status': finalStatus},
    };
  }

  factory PgxReport.fromJson(Map<String, dynamic> json) {
    return PgxReport(
      patientId: json['patient_id'] as String? ?? 'PATIENT_UNKNOWN',
      drug: json['drug'] as String? ?? 'UNKNOWN',
      timestamp: json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment.fromJson(
          json['risk_assessment'] as Map<String, dynamic>? ?? {}),
      pharmacogenomicProfile: PharmacogenomicProfile.fromJson(
          json['pharmacogenomic_profile'] as Map<String, dynamic>? ?? {}),
      clinicalRecommendation: ClinicalRecommendation.fromJson(
          json['clinical_recommendation'] as Map<String, dynamic>? ?? {}),
      llmGeneratedExplanation: LlmExplanation.fromJson(
          json['llm_generated_explanation'] as Map<String, dynamic>? ?? {}),
      qualityMetrics: QualityMetrics.fromJson(
          json['quality_metrics'] as Map<String, dynamic>? ?? {}),
        evidence: json['evidence'] is Map<String, dynamic>
          ? DrugEvidence.fromJson(json['evidence'] as Map<String, dynamic>)
          : null,
          personalizedSideEffects: (json['personalized_side_effects'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(PersonalizedSideEffectRisk.fromJson)
              .toList() ??
            const [],
    );
  }
}

/// Container for a multi-drug evaluation session saved in Firestore.
class PgxMultiReport {
  final String reportId;
  final String patientId;
  final String vcfFilename;
  final String timestamp;
  final List<PgxReport> drugReports;

  PgxMultiReport({
    required this.reportId,
    required this.patientId,
    required this.vcfFilename,
    required this.timestamp,
    required this.drugReports,
  });

  Map<String, dynamic> toJson() {
    return {
      'report_id': reportId,
      'patient_id': patientId,
      'vcf_filename': vcfFilename,
      'timestamp': timestamp,
      'drug_reports': drugReports.map((r) => r.toJson()).toList(),
    };
  }

  factory PgxMultiReport.fromJson(Map<String, dynamic> json) {
    var rawList = json['drug_reports'] as List<dynamic>? ?? [];
    return PgxMultiReport(
      reportId: json['report_id'] as String? ?? '',
      patientId: json['patient_id'] as String? ?? 'PATIENT_UNKNOWN',
      vcfFilename: json['vcf_filename'] as String? ?? 'sample.vcf',
      timestamp: json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      drugReports: rawList
          .map((r) => PgxReport.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  String toFormattedJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }
}
