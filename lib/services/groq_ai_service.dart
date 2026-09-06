import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'ai_response_validator.dart';

/// Groq is an explanation layer only. Deterministic medical results stay authoritative.
class GroqAIService {
  GroqAIService({http.Client? client, String? apiKey, String? model})
      : _client = client ?? http.Client(),
        _configuredApiKey = apiKey,
        _configuredModel = model;

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _defaultModel = 'openai/gpt-oss-120b';
  final http.Client _client;
  final String? _configuredApiKey;
  final String? _configuredModel;

  String? get _apiKey {
    if (_configuredApiKey != null) return _configuredApiKey;
    final value = _env('GROQ_API_KEY')?.trim();
    return value == null || value.isEmpty || value.startsWith('YOUR_') ? null : value;
  }

    String get _model => _configuredModel?.trim().isNotEmpty == true
      ? _configuredModel!.trim()
      : _env('GROQ_MODEL')?.trim().isNotEmpty == true
      ? _env('GROQ_MODEL')!.trim()
      : _defaultModel;

    List<String> get _chatModels => <String>{
          _model,
          'openai/gpt-oss-120b',
          _defaultModel,
        }.toList();

  Future<Map<String, String>> generateExplanation({
    required Map<String, dynamic> medicalResult,
    required String userRole,
  }) async {
    final fallback = _fallback(medicalResult);
    final key = _apiKey;
    if (key == null) return fallback;

    final response = await _request(
      key: key,
      systemPrompt: _systemPrompt(userRole),
      payload: medicalResult,
    );
    if (response == null) return fallback;
    final validated = AIResponseValidator.validate(response, medicalResult);
    if (validated == null) {
      throw StateError('Live AI response failed safety validation.');
    }
    return validated;
  }

  Future<Map<String, String>> generateClinicalSummary({
    required Map<String, dynamic> medicalResult,
  }) => generateExplanation(medicalResult: medicalResult, userRole: 'clinician');

  /// Looks up public medicine facts only; it never assigns a patient risk.
  Future<Map<String, dynamic>?> searchDrugOnline(String medicineName) async {
    final key = _apiKey;
    if (key == null) return null;
    return _requestLookup(
      key: key,
      medicineName: medicineName,
    );
  }

  Future<String> answerHealthQuestion({
    required String question,
    String? reportContext,
  }) async {
    final key = _apiKey;
    if (key == null) {
      throw StateError('Live AI is unavailable: GROQ_API_KEY is not configured.');
    }

    final context = reportContext == null
        ? ''
        : '\nVERIFIED REPORT CONTEXT:\n$reportContext';
    final response = await _rawChatRequest(
      key: key,
      systemPrompt: '''You are OnCapRX AI, a simple and careful health assistant.
Answer health, medicine, side-effect, interaction, and pharmacogenomics questions in plain language.
Use the verified report context when the question is about the user's report.
Never replace the medicine in the report with another medicine or guess a brand's active ingredient. If the verified identity is missing, say that the medicine identity is unverified.
Never diagnose, invent facts, or tell the user to start, stop, or change a medicine or dose.
When information is missing, say what is unknown and advise speaking with a doctor or pharmacist.
Keep the answer concise and easy for a patient to understand.
Format it with short labels when useful, such as "What it means:", "What to watch for:", and "When to get help:". Use bullet points for lists. Always include a brief professional-care reminder.$context''',
      userContent: question,
    );

    if (response?.trim().isNotEmpty != true) {
      throw StateError('Live AI did not return an answer. Check the API key, model, and internet connection.');
    }
    return response!.trim();
  }

  Future<Map<String, dynamic>?> _request({
    required String key,
    required String systemPrompt,
    required Map<String, dynamic> payload,
  }) async {
    for (final model in _chatModels) {
        try {
          final result = await _client
              .post(
                Uri.parse(_endpoint),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $key',
                },
                body: jsonEncode({
                  'model': model,
                  'messages': [
                    {'role': 'system', 'content': systemPrompt},
                    {'role': 'user', 'content': jsonEncode(sanitizeMedicalResult(payload))},
                  ],
                  'temperature': 0,
                  'max_tokens': 700,
                  'response_format': {'type': 'json_object'},
                }),
              )
              .timeout(const Duration(seconds: 12));
          if (result.statusCode < 200 || result.statusCode >= 300) continue;
          final body = jsonDecode(result.body) as Map<String, dynamic>;
          final content = body['choices']?[0]?['message']?['content']?.toString();
          final decoded = content == null ? null : AIResponseValidator.decodeObject(content);
          if (decoded != null) return decoded;
        } catch (_) {}
      }
    return null;
  }

  Future<Map<String, dynamic>?> _requestLookup({
    required String key,
    required String medicineName,
  }) async {
    for (final model in _chatModels) {
        try {
          final result = await _client
              .post(
                Uri.parse(_endpoint),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $key',
                },
                body: jsonEncode({
                  'model': model,
                  'messages': [
                    {
                      'role': 'system',
                      'content': '''You are a medicine information lookup service.
Return JSON only with exactly these keys: genericName, displayName, uses,
commonSideEffects, seriousSideEffects, precautions, pgxRelevance, pgxGene,
pgxPhenotypes, guidelineSummary, evidenceLevel, confidence, isRealMedicine.
Use comma-separated strings for uses, side effects, precautions, and pgxPhenotypes.
Set isRealMedicine false for an unknown or non-medicine name. Never diagnose,
prescribe, recommend a dose, or classify a medicine as safe or unsafe. Do not
invent a pharmacogenomic relationship.''',
                    },
                    {'role': 'user', 'content': medicineName},
                  ],
                  'temperature': 0,
                  'max_tokens': 700,
                  'response_format': {'type': 'json_object'},
                }),
              )
              .timeout(const Duration(seconds: 15));
          if (result.statusCode < 200 || result.statusCode >= 300) continue;
          final body = jsonDecode(result.body) as Map<String, dynamic>;
          final content = body['choices']?[0]?['message']?['content']?.toString();
          final decoded = content == null ? null : AIResponseValidator.decodeObject(content);
          if (decoded != null) return decoded;
        } catch (_) {}
      }
    return null;
  }

  Future<String?> _rawChatRequest({
    required String key,
    required String systemPrompt,
    required String userContent,
  }) async {
    for (final model in _chatModels) {
      try {
        final result = await _client
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $key',
              },
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': userContent},
                ],
                'temperature': 0.3,
                'max_tokens': 500,
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (result.statusCode < 200 || result.statusCode >= 300) continue;
        final body = jsonDecode(result.body) as Map<String, dynamic>;
        final content = body['choices']?[0]?['message']?['content']?.toString();
        if (content?.trim().isNotEmpty == true) return content;
      } catch (_) {
        // Try the next supported model before showing the user a fallback.
      }
    }
    return null;
  }

  static Map<String, dynamic> sanitizeMedicalResult(Map<String, dynamic> result) {
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

  static String _systemPrompt(String role) => '''You are PharmaGuard's AI-assisted explanation layer.
The supplied JSON was produced by a deterministic evidence-based medical engine. You are not the medical decision engine.
Never change, override, reinterpret, or contradict its riskLabel, verificationStatus, or missing-data state.
Never invent a medicine, interaction, genotype, diplotype, phenotype, evidence, diagnosis, or patient fact.
If a value is missing or Unknown, say it is unavailable. Never say 100% safe.
Never tell anyone to start, stop, change, increase, decrease, or switch a medicine or dose.
Use simple language for patients and concise technical language for clinicians.
Return only JSON with exactly these fields: title, summary, whatItMeans, whyThisResult, importantRisks, sideEffectExplanation, whatToDiscussWithDoctor, technicalDetails, limitations.
Array fields must contain strings. Preserve the deterministic classification exactly.
User role: $role''';

  static Map<String, String> _fallback(Map<String, dynamic> result) {
    final medicine = result['medicine']?.toString() ?? 'This medicine';
    final risk = result['riskLabel']?.toString() ?? 'Unknown';
    final reason = result['recommendation']?.toString() ?? 'No additional explanation is available.';
    final uses = result['uses']?.toString();
    final sideEffects = result['commonSideEffects']?.toString();
    final serious = result['seriousSideEffects']?.toString();
    final facts = [
      if (uses != null && uses.isNotEmpty) 'It is commonly used for $uses.',
      if (sideEffects != null && sideEffects.isNotEmpty)
        'Common side effects may include $sideEffects.',
      if (serious != null && serious.isNotEmpty)
        'Get medical help for $serious.',
    ].join(' ');
    return {
      'summary': '$medicine was classified as $risk by the deterministic medical engine.',
      'mechanism': reason,
        'patient_friendly': '${facts.isEmpty ? '' : '$facts '}'
          'The checked result is $risk. Do not start, stop, or change this medicine without advice from a doctor or pharmacist.',
      'clinician_note': 'AI explanation unavailable. Deterministic result: $risk. $reason',
    };
  }

  static String? _env(String key) {
    try {
      return dotenv.env[key];
    } on NotInitializedError {
      return null;
    }
  }
}