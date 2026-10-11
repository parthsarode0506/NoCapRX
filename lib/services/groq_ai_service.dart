import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'ai_response_validator.dart';

/// AI explanation layer. Cloud AI is used ONLY when an API key is configured
/// in the local .env file (GROQ_API_KEY or OPENROUTER_API_KEY). When no key is
/// present, or the network call fails for any reason, every method falls back
/// to deterministic local template content. Clinical decisions always remain
/// with the on-device CPIC rule engine — this layer only explains.
class GroqAIService {
  GroqAIService({http.Client? client, String? apiKey, String? model})
      : _client = client ?? http.Client(),
        _configuredApiKey = apiKey,
        _configuredModel = model;

  final http.Client _client;
  final String? _configuredApiKey;
  final String? _configuredModel;

  static const _groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _openRouterEndpoint =
      'https://openrouter.ai/api/v1/chat/completions';
  static const _defaultGroqModel = 'openai/gpt-oss-120b';
  static const _defaultOpenRouterModel = 'openai/gpt-6.1-sol';

  /// Resolved endpoint + key + model based on whichever key is configured.
  /// GROQ_API_KEY takes priority; OPENROUTER_API_KEY is the fallback.
  _CloudConfig? get _cloud {
    final groqKey = _configuredApiKey ?? _env('GROQ_API_KEY')?.trim();
    if (groqKey != null && groqKey.isNotEmpty && !groqKey.startsWith('YOUR_')) {
      return _CloudConfig(
        endpoint: _groqEndpoint,
        key: groqKey,
        model: _configuredModel?.trim().isNotEmpty == true
            ? _configuredModel!.trim()
            : _env('GROQ_MODEL')?.trim().isNotEmpty == true
                ? _env('GROQ_MODEL')!.trim()
                : _defaultGroqModel,
        isOpenRouter: false,
      );
    }
    final orKey = _env('OPENROUTER_API_KEY')?.trim();
    if (orKey != null && orKey.isNotEmpty && !orKey.startsWith('YOUR_')) {
      return _CloudConfig(
        endpoint: _openRouterEndpoint,
        key: orKey,
        model: _configuredModel?.trim().isNotEmpty == true
            ? _configuredModel!.trim()
            : _env('OPENROUTER_MODEL')?.trim().isNotEmpty == true
                ? _env('OPENROUTER_MODEL')!.trim()
                : _defaultOpenRouterModel,
        isOpenRouter: true,
      );
    }
    return null;
  }

  /// Builds a structured explanation. Uses cloud AI when a key is configured;
  /// otherwise returns local deterministic content. Never fails hard.
  Future<Map<String, String>> generateExplanation({
    required Map<String, dynamic> medicalResult,
    required String userRole,
    bool allowCloudAi = true, // Cloud is used automatically when a key exists.
  }) async {
    final fallback = _localExplanation(medicalResult, userRole);
    final cloud = allowCloudAi ? _cloud : null;
    if (cloud == null) return fallback;

    final response = await _chat(
      cloud: cloud,
      systemPrompt: _explanationPrompt(userRole),
      userContent: jsonEncode(sanitizeMedicalResult(medicalResult)),
      jsonMode: true,
      maxTokens: 700,
      temperature: 0,
    );
    if (response == null) return fallback;
    final validated = AIResponseValidator.validate(response, medicalResult);
    return validated ?? fallback;
  }

  Future<Map<String, String>> generateClinicalSummary({
    required Map<String, dynamic> medicalResult,
    bool allowCloudAi = true,
  }) =>
      generateExplanation(
        medicalResult: medicalResult,
        userRole: 'clinician',
        allowCloudAi: allowCloudAi,
      );

  /// Looks up public medicine facts. Uses the configured cloud AI; returns
  /// null when no key is configured so callers fall back to local repository.
  Future<Map<String, dynamic>?> searchDrugOnline(
    String medicineName, {
    bool allowCloudAi = true,
  }) async {
    final cloud = allowCloudAi ? _cloud : null;
    if (cloud == null) return null;

    final raw = await _chat(
      cloud: cloud,
      systemPrompt: '''You are a medicine information lookup service.
Return JSON only with exactly these keys: genericName, displayName, uses,
commonSideEffects, seriousSideEffects, precautions, pgxRelevance, pgxGene,
pgxPhenotypes, guidelineSummary, evidenceLevel, confidence, isRealMedicine.
Use comma-separated strings for uses, side effects, precautions, and pgxPhenotypes.
Set isRealMedicine false for an unknown or non-medicine name. Never diagnose,
prescribe, recommend a dose, or classify a medicine as safe or unsafe. Do not
invent a pharmacogenomic relationship.''',
      userContent: medicineName,
      jsonMode: true,
      maxTokens: 700,
      temperature: 0,
      timeoutSeconds: 15,
    );
    return raw;
  }

  /// Answers a health question. Uses cloud AI when a key is configured;
  /// otherwise returns a safe local template grounded in the report context.
  Future<String> answerHealthQuestion({
    required String question,
    String? reportContext,
    bool allowCloudAi = true,
  }) async {
    final cloud = allowCloudAi ? _cloud : null;
    if (cloud == null) {
      return _localHealthAnswer(question, reportContext);
    }

    final context = reportContext == null
        ? ''
        : '\nVERIFIED REPORT CONTEXT:\n$reportContext';
    final raw = await _chatRaw(
      cloud: cloud,
      systemPrompt:
          '''You are NoCapRX AI, a simple and careful health assistant.
Answer health, medicine, side-effect, interaction, and pharmacogenomics questions in plain language.
Use the verified report context when the question is about the user's report.
Never replace the medicine in the report with another medicine or guess a brand's active ingredient. If the verified identity is missing, say that the medicine identity is unverified.
Never diagnose, invent facts, or tell the user to start, stop, or change a medicine or dose.
When information is missing, say what is unknown and advise speaking with a doctor or pharmacist.
Keep the answer concise and easy for a patient to understand.
Format it with short labels when useful, such as "What it means:", "What to watch for:", and "When to get help:". Use bullet points for lists. Always include a brief professional-care reminder.$context''',
      userContent: question,
      maxTokens: 500,
      temperature: 0.3,
    );
    return raw?.trim().isNotEmpty == true
        ? raw!.trim()
        : _localHealthAnswer(question, reportContext);
  }

  // ─── Network helpers ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _chat({
    required _CloudConfig cloud,
    required String systemPrompt,
    required String userContent,
    bool jsonMode = false,
    int maxTokens = 700,
    double temperature = 0,
    int timeoutSeconds = 12,
  }) async {
    final raw = await _chatRaw(
      cloud: cloud,
      systemPrompt: systemPrompt,
      userContent: userContent,
      jsonMode: jsonMode,
      maxTokens: maxTokens,
      temperature: temperature,
      timeoutSeconds: timeoutSeconds,
    );
    if (raw == null) return null;
    return AIResponseValidator.decodeObject(raw);
  }

  Future<String?> _chatRaw({
    required _CloudConfig cloud,
    required String systemPrompt,
    required String userContent,
    bool jsonMode = false,
    int maxTokens = 700,
    double temperature = 0,
    int timeoutSeconds = 12,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${cloud.key}',
      if (cloud.isOpenRouter) ...{
        'HTTP-Referer': 'https://ondevicerx.app',
        'X-Title': 'NoCapRX',
      },
    };
    final body = <String, dynamic>{
      'model': cloud.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userContent},
      ],
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };

    try {
      final result = await _client
          .post(
            Uri.parse(cloud.endpoint),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: timeoutSeconds));
      if (result.statusCode < 200 || result.statusCode >= 300) return null;
      final decoded = jsonDecode(result.body) as Map<String, dynamic>;
      final content =
          decoded['choices']?[0]?['message']?['content']?.toString();
      return content?.trim().isNotEmpty == true ? content : null;
    } catch (_) {
      return null;
    }
  }

  // ─── Local fallback content ───────────────────────────────────────────────

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

  static String _explanationPrompt(String role) =>
      '''You are PharmaGuard's AI-assisted explanation layer.
The supplied JSON was produced by a deterministic evidence-based medical engine. You are not the medical decision engine.
Never change, override, reinterpret, or contradict its riskLabel, verificationStatus, or missing-data state.
Never invent a medicine, interaction, genotype, diplotype, phenotype, evidence, diagnosis, or patient fact.
If a value is missing or Unknown, say it is unavailable. Never say 100% safe.
Never tell anyone to start, stop, change, increase, decrease, or switch a medicine or dose.
Use simple language for patients and concise technical language for clinicians.
Return only JSON with exactly these fields: title, summary, whatItMeans, whyThisResult, importantRisks, sideEffectExplanation, whatToDiscussWithDoctor, technicalDetails, limitations.
Array fields must contain strings. Preserve the deterministic classification exactly.
User role: $role''';

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
      'clinician_note': 'On-device deterministic result: $risk. $reason',
    };
  }

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

  static String? _env(String key) {
    try {
      return dotenv.env[key];
    } on NotInitializedError {
      return null;
    }
  }
}

class _CloudConfig {
  const _CloudConfig({
    required this.endpoint,
    required this.key,
    required this.model,
    required this.isOpenRouter,
  });

  final String endpoint;
  final String key;
  final String model;
  final bool isOpenRouter;
}
