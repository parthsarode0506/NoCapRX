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
    final value = dotenv.env['GROQ_API_KEY']?.trim();
    return value == null || value.isEmpty || value.startsWith('YOUR_') ? null : value;
  }

    String get _model => _configuredModel?.trim().isNotEmpty == true
      ? _configuredModel!.trim()
      : dotenv.env['GROQ_MODEL']?.trim().isNotEmpty == true
      ? dotenv.env['GROQ_MODEL']!.trim()
      : _defaultModel;

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
    return AIResponseValidator.validate(response, medicalResult) ?? fallback;
  }

  Future<Map<String, String>> generateClinicalSummary({
    required Map<String, dynamic> medicalResult,
  }) => generateExplanation(medicalResult: medicalResult, userRole: 'clinician');

  Future<Map<String, dynamic>?> _request({
    required String key,
    required String systemPrompt,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final result = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: jsonEncode({
              'model': _model,
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
      if (result.statusCode < 200 || result.statusCode >= 300) return null;
      final body = jsonDecode(result.body) as Map<String, dynamic>;
      final content = body['choices']?[0]?['message']?['content']?.toString();
      return content == null ? null : AIResponseValidator.decodeObject(content);
    } catch (_) {
      return null;
    }
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
      'evidenceSources',
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
    return {
      'summary': '$medicine was classified as $risk by the deterministic medical engine.',
      'mechanism': reason,
      'patient_friendly': 'The AI explanation is unavailable. The medication safety result remains $risk. Discuss it with your doctor or pharmacist before making any changes.',
      'clinician_note': 'AI explanation unavailable. Deterministic result: $risk. $reason',
    };
  }
}