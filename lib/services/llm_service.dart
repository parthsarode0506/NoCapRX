import '../models/pgx_report.dart';
import '../features/chat/medicine_retriever.dart';
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
      allowCloudAi: true,
    );
  }

  /// Kept for the existing chat screen. Only derived, per-drug results are sent.
  static Future<String> askReportChatbot({
    required String userQuery,
    required PgxMultiReport report,
  }) async {
    final reportContext = report.drugReports.map((drug) {
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

    final localEvidence = MedicineRetriever.retrieve(userQuery);
    final medicineContext = localEvidence == null
        ? ''
        : [
            'Verified local medicine record:',
            'Medicine: ${localEvidence.displayName}',
            'Active ingredients: ${localEvidence.activeIngredients.join(', ')}',
            if (localEvidence.uses.isNotEmpty)
              'Uses: ${localEvidence.uses.join('; ')}',
            if (localEvidence.commonSideEffects.isNotEmpty)
              'Common side effects: ${localEvidence.commonSideEffects.join('; ')}',
            if (localEvidence.seriousSideEffects.isNotEmpty)
              'Serious side effects: ${localEvidence.seriousSideEffects.join('; ')}',
            if (localEvidence.precautions.isNotEmpty)
              'Precautions: ${localEvidence.precautions.join('; ')}',
          ].join('\n');

    final context = [
      if (reportContext.isNotEmpty) reportContext,
      if (medicineContext.isNotEmpty) medicineContext,
    ].join('\n\n');

    return _service.answerHealthQuestion(
      question: userQuery,
      reportContext: context.isEmpty ? null : context,
      allowCloudAi: true,
    );
  }
}
