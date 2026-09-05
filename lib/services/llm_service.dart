import '../models/pgx_report.dart';
import 'groq_ai_service.dart';

/// Compatibility facade for existing screens. GroqAIService owns the API path.
class LlmService {
  static final GroqAIService _service = GroqAIService();

  static Future<Map<String, String>> generateExplanation({
    required String gene,
    required String phenotype,
    required String drug,
    required String riskLabel,
    required String mechanism,
    required String cpicRec,
  }) {
    return _service.generateExplanation(
      userRole: 'patient',
      medicalResult: {
        'medicine': drug,
        'riskLabel': riskLabel,
        'gene': gene,
        if (phenotype.isNotEmpty && phenotype != 'Unknown') 'phenotype': phenotype,
        'recommendation': cpicRec,
        'limitations': mechanism,
        'verificationStatus': 'verified',
      },
    );
  }

  /// Kept for the existing chat screen. Only derived, per-drug results are sent.
  static Future<String> askReportChatbot({
    required String userQuery,
    required PgxMultiReport report,
  }) async {
    final result = await _service.generateExplanation(
      userRole: 'patient',
      medicalResult: {
        'request': userQuery,
        'reportId': report.reportId,
        'drugFindings': report.drugReports.map((drug) {
          final profile = drug.pharmacogenomicProfile;
          return {
            'medicine': drug.drug,
            'riskLabel': drug.riskAssessment.riskLabel,
            'severity': drug.riskAssessment.severity,
            'gene': profile.primaryGene,
            if (profile.phenotype != 'Unknown') 'phenotype': profile.phenotype,
            if (profile.diplotype != 'Unknown') 'diplotype': profile.diplotype,
            'recommendation': drug.clinicalRecommendation.dosingRecommendation,
          };
        }).toList(),
        'verificationStatus': 'verified',
      },
    );
    return result['patient_friendly'] ?? result['summary'] ?? 'AI explanation unavailable.';
  }
}
