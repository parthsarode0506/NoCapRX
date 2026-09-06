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
    final context = report.drugReports.map((drug) {
      final profile = drug.pharmacogenomicProfile;
      return [
        'Medicine: ${drug.drug}',
        if (drug.evidence != null)
          'Verified identity: ${drug.evidence!.displayName}',
        if (drug.evidence?.activeIngredients.isNotEmpty == true)
          'Active ingredients: ${drug.evidence!.activeIngredients.join(', ')}',
        'Result: ${drug.riskAssessment.riskLabel}',
        'Gene: ${profile.primaryGene}',
        'Phenotype: ${profile.phenotype}',
        'Recommendation: ${drug.clinicalRecommendation.dosingRecommendation}',
        if (drug.evidence?.uses.isNotEmpty == true)
          'Uses: ${drug.evidence!.uses.join('; ')}',
        if (drug.evidence?.commonSideEffects.isNotEmpty == true)
          'Common side effects: ${drug.evidence!.commonSideEffects.join('; ')}',
        if (drug.evidence?.seriousSideEffects.isNotEmpty == true)
          'Serious side effects: ${drug.evidence!.seriousSideEffects.join('; ')}',
      ].join('\n');
    }).join('\n\n');

    return _service.answerHealthQuestion(
      question: userQuery,
      reportContext: context.isEmpty ? null : context,
    );
  }
}
