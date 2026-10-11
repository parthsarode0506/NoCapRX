/// LOCAL-ONLY AI explanation layer.
///
/// This service previously called the Groq cloud API. It has been converted
/// to a fully local implementation: every method returns deterministic,
/// template-based content derived from the local medical result. No network
/// calls are ever made, and no patient data ever leaves the device.
///
/// The class name is kept for backward compatibility with existing callers.
class GroqAIService {
  GroqAIService({dynamic client, String? apiKey, String? model});

  /// Builds a structured explanation from the local medical result.
  /// Never contacts the network.
  Future<Map<String, String>> generateExplanation({
    required Map<String, dynamic> medicalResult,
    required String userRole,
    bool allowCloudAi = false, // Ignored — cloud AI is permanently disabled.
  }) async {
    return _localExplanation(medicalResult, userRole);
  }

  Future<Map<String, String>> generateClinicalSummary({
    required Map<String, dynamic> medicalResult,
    bool allowCloudAi = false,
  }) =>
      generateExplanation(
        medicalResult: medicalResult,
        userRole: 'clinician',
        allowCloudAi: allowCloudAi,
      );

  /// Online medicine lookup is disabled in local-only mode.
  /// Always returns null so callers fall back to the local repository.
  Future<Map<String, dynamic>?> searchDrugOnline(
    String medicineName, {
    bool allowCloudAi = false,
  }) async {
    return null;
  }

  /// Answers a health question using only local context.
  /// Returns a safe, templated answer grounded in the verified report.
  Future<String> answerHealthQuestion({
    required String question,
    String? reportContext,
    bool allowCloudAi = false,
  }) async {
    return _localHealthAnswer(question, reportContext);
  }

  static Map<String, dynamic> sanitizeMedicalResult(
    Map<String, dynamic> result,
  ) {
    const allowed = {
      'medicine',
      'activeIngredient',
      'verificationStatus',
      'riskLabel',
      'severity',
      'gene',
      'genotype',
      'diplotype',
      'phenotype',
      'recommendation',
      'patientRiskFactors',
      'interactions',
      'contraindications',
      'personalizedSideEffects',
      'status',
      'title',
      'explanation',
      'evidence_source',
      'interacting_drug',
      'side_effect',
      'frequency',
      'higher_risk_groups',
      'patient_risk_factors',
      'relevance',
      'evidence_sources',
      'evidenceSources',
      'uses',
      'commonSideEffects',
      'seriousSideEffects',
      'precautions',
      'request',
      'drugFindings',
    };
    dynamic clean(dynamic value) {
      if (value is Map) {
        return value.entries
            .where((entry) => allowed.contains(entry.key.toString()))
            .fold<Map<String, dynamic>>({}, (map, entry) {
              map[entry.key.toString()] = clean(entry.value);
              return map;
            });
      }
      if (value is Iterable) return value.map(clean).toList();
      return value;
    }

    return clean(result) as Map<String, dynamic>;
  }

  /// Deterministic, template-based explanation built from local result fields.
  static Map<String, String> _localExplanation(
    Map<String, dynamic> result,
    String userRole,
  ) {
    final medicine = result['medicine']?.toString() ?? 'This medicine';
    final risk = result['riskLabel']?.toString() ?? 'Unknown';
    final severity = result['severity']?.toString() ?? '';
    final gene = result['gene']?.toString() ?? '';
    final phenotype = result['phenotype']?.toString() ?? '';
    final diplotype = result['diplotype']?.toString() ?? '';
    final reason =
        result['recommendation']?.toString() ??
        'No additional explanation is available.';
    final uses = result['uses']?.toString();
    final sideEffects = result['commonSideEffects']?.toString();
    final serious = result['seriousSideEffects']?.toString();

    final geneticContext = [
      if (gene.isNotEmpty) 'Gene: $gene',
      if (diplotype.isNotEmpty) 'Diplotype: $diplotype',
      if (phenotype.isNotEmpty) 'Phenotype: $phenotype',
    ].join(' · ');

    final facts = [
      if (uses != null && uses.isNotEmpty) 'It is commonly used for $uses.',
      if (sideEffects != null && sideEffects.isNotEmpty)
        'Common side effects may include $sideEffects.',
      if (serious != null && serious.isNotEmpty)
        'Get medical help for $serious.',
    ].join(' ');

    final isPatient = userRole == 'patient';

    return {
      'title': '$medicine — $risk',
      'summary':
          '$medicine was classified as "$risk"${severity.isNotEmpty ? ' (severity: $severity)' : ''} by the on-device clinical rule engine.'
          '${geneticContext.isNotEmpty ? ' $geneticContext.' : ''}',
      'whatItMeans': isPatient
          ? 'Your genetic results suggest how your body may handle $medicine. '
              'The classification "$risk" comes from published CPIC guidelines, '
              'not from an AI guess.'
          : 'Deterministic CPIC evaluation${geneticContext.isNotEmpty ? ' ($geneticContext)' : ''} produced risk label "$risk".',
      'whyThisResult': reason,
      'importantRisks': serious != null && serious.isNotEmpty
          ? serious
          : 'No additional risk details are available locally.',
      'sideEffectExplanation':
          sideEffects != null && sideEffects.isNotEmpty
              ? sideEffects
              : 'Side-effect details are not available in the local record.',
      'whatToDiscussWithDoctor':
          'Review this result with your prescriber or pharmacist before any '
          'change to medicine or dose. Never start, stop, or switch a medicine '
          'based only on this report.',
      'technicalDetails': [
        if (geneticContext.isNotEmpty) geneticContext,
        'Risk label: $risk',
        if (severity.isNotEmpty) 'Severity: $severity',
      ].join('\n'),
      'limitations':
          'This explanation is generated on-device from local data only. '
          'It is advisory, never directive, and is not a substitute for '
          'professional medical advice.',
      'mechanism': reason,
      'patient_friendly':
          '${facts.isEmpty ? '' : '$facts '}'
          'The checked result is $risk. Discuss any change with your prescriber or pharmacist.',
      'clinician_note':
          'On-device deterministic result: $risk. $reason',
    };
  }

  /// Safe local answer for health questions. Uses only the verified local
  /// report context, never invents facts, and always redirects to a clinician
  /// when information is missing.
  static String _localHealthAnswer(String question, String? reportContext) {
    final hasContext = reportContext != null && reportContext.trim().isNotEmpty;

    final buffer = StringBuffer();
    buffer.writeln('Here is what your verified local report says:');
    if (hasContext) {
      buffer.writeln();
      buffer.writeln(reportContext.trim());
      buffer.writeln();
    } else {
      buffer.writeln();
      buffer.writeln(
        'No matching medicine record was found in the on-device database, '
        'so no medicine-specific claim can be made.',
      );
      buffer.writeln();
    }

    buffer.writeln('What this means:');
    buffer.writeln(
      '• All classifications come from the deterministic CPIC rule engine, not from AI guesswork.',
    );
    buffer.writeln(
      '• This chat runs fully on your device. No question or result leaves this phone.',
    );
    buffer.writeln();
    buffer.writeln('When to get help:');
    buffer.writeln(
      '• Talk to your doctor or pharmacist before starting, stopping, or changing any medicine.',
    );
    buffer.writeln(
      '• Seek urgent care for severe allergic reactions, chest pain, or trouble breathing.',
    );

    return buffer.toString().trim();
  }
}
