import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/pgx_report.dart';

/// LLM Service powered by Groq AI (free tier) with offline bundled fallback.
/// Replaces Gemini API with Groq's OpenAI-compatible chat completions endpoint.
class LlmService {
  static const String _groqBaseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'llama-3.3-70b-versatile'; // Free Groq model
  static Map<String, dynamic>? _offlineExplanationsCache;

  /// Loads bundled offline explanations asset JSON.
  static Future<void> _ensureOfflineCacheLoaded() async {
    if (_offlineExplanationsCache != null) return;
    try {
      final jsonString = await rootBundle.loadString('assets/data/bundled_explanations.json');
      _offlineExplanationsCache = json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      _offlineExplanationsCache = {};
    }
  }

  /// Browser clients must not carry a provider secret. Until a secure backend
  /// issues explanation requests, use bundled/offline explanations. This also
  /// keeps core analysis available when no dotenv asset is loaded.
  static String? get _apiKey => null;

  /// Uses AI only to resolve an entered generic/brand name to one of the
  /// caller-provided, validated drug rules.  The response is allow-listed so a
  /// model can never create a new clinical mapping or safety conclusion.
  static Future<String?> resolveDrugForValidatedPanel({
    required String enteredDrug,
    required Iterable<String> canonicalDrugNames,
  }) async {
    final validNames = canonicalDrugNames
        .map((name) => name.trim().toUpperCase())
        .toSet();
    final normalizedInput = enteredDrug.trim().toUpperCase();
    if (validNames.contains(normalizedInput)) return normalizedInput;

    final apiKey = _apiKey;
    if (apiKey == null || normalizedInput.isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse(_groqBaseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: json.encode({
              'model': _groqModel,
              'messages': [
                {
                  'role': 'system',
                  'content': 'Match the entered medication to exactly one name in the allowed list only when it is the same drug (including a brand name). Return only that uppercase name. Return UNKNOWN when there is no exact match. Do not infer a pharmacogenomic recommendation.'
                },
                {
                  'role': 'user',
                  'content': 'Entered medication: "$enteredDrug"\nAllowed names: ${validNames.join(', ')}'
                },
              ],
              'temperature': 0,
              'max_tokens': 30,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final candidate = body['choices']?[0]?['message']?['content']
            ?.toString()
            .trim()
            .toUpperCase();
        return validNames.contains(candidate) ? candidate : null;
      }
    } catch (_) {
      // A missing connection must not change a clinical result.
    }
    return null;
  }

  /// Generates structured clinical explanation using Groq AI, with bundled asset fallback.
  static Future<Map<String, String>> generateExplanation({
    required String gene,
    required String phenotype,
    required String drug,
    required String riskLabel,
    required String mechanism,
    required String cpicRec,
  }) async {
    await _ensureOfflineCacheLoaded();
    final cacheKey = '${gene}_${phenotype}_$drug'.replaceAll(' ', '_').toUpperCase();

    // Check offline asset cache first
    final cached = _offlineExplanationsCache?[cacheKey];

    final apiKey = _apiKey;
    if (apiKey == null) {
      return _extractFromCacheOrFallback(cached, gene, phenotype, drug, riskLabel, mechanism, cpicRec);
    }

    try {
      final systemPrompt = '''You are an expert clinical pharmacogenomics decision support engine.
Generate a patient-friendly explanation based STRICTLY on the validated facts provided by the user.
Do not change the risk label, phenotype, mechanism, dosing recommendation, alternatives, or monitoring. Do not add a new recommendation.
Return ONLY a valid JSON object matching this exact key format (no markdown formatting, no code block backticks):
{
  "summary": "1-2 sentence overview of the genetic risk for this drug",
  "mechanism": "Clear molecular mechanism explaining the enzyme alteration",
  "patient_friendly": "Empathetic, clear patient-level explanation avoiding medical jargon, advising actions to discuss with their clinician",
  "clinician_note": "Detailed clinical guidance with CPIC citations and actionable prescribing recommendations"
}''';

      final userPrompt = '''Analyze this pharmacogenomic interaction:
- Gene: $gene
- Phenotype: $phenotype
- Drug: $drug
- Risk Label: $riskLabel
- Mechanism: $mechanism
- CPIC Guidance: $cpicRec''';

      final response = await http
          .post(
            Uri.parse(_groqBaseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: json.encode({
              'model': _groqModel,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
              'temperature': 0.2,
              'max_tokens': 800,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final rawText = body['choices']?[0]?['message']?['content'] ?? '';
        final cleanJsonStr = rawText.toString().replaceAll('```json', '').replaceAll('```', '').trim();
        final Map<String, dynamic> parsed = json.decode(cleanJsonStr);

        return {
          'summary': parsed['summary']?.toString() ?? '',
          // The deterministic engine owns the biological mechanism and all
          // clinical recommendations. Do not accept an LLM rewrite of either.
          'mechanism': mechanism,
          'patient_friendly': parsed['patient_friendly']?.toString() ?? '',
          'clinician_note': 'Validated rule input: $gene ($phenotype), $drug, $riskLabel. $cpicRec',
        };
      }
    } catch (e) {
      // Fallback on network or API failure
    }

    return _extractFromCacheOrFallback(cached, gene, phenotype, drug, riskLabel, mechanism, cpicRec);
  }

  static Map<String, String> _extractFromCacheOrFallback(
    dynamic cached,
    String gene,
    String phenotype,
    String drug,
    String riskLabel,
    String mechanism,
    String cpicRec,
  ) {
    if (cached != null && cached is Map<String, dynamic>) {
      return {
        'summary': cached['summary']?.toString() ?? '',
        'mechanism': mechanism,
        'patient_friendly': cached['patient_friendly']?.toString() ?? '',
        'clinician_note': 'Validated rule input: $gene ($phenotype), $drug, $riskLabel. $cpicRec',
      };
    }

    return {
      'summary': '$gene ($phenotype) risk for $drug is $riskLabel.',
      'mechanism': mechanism,
      'patient_friendly':
          'Your genetic test shows your $gene gene has $phenotype function. For $drug, your risk is rated as $riskLabel. Please discuss this with your physician before changing medications.',
      'clinician_note':
          'CPIC Guideline evaluation: $gene diplotype ($phenotype) assigned $riskLabel for $drug. $cpicRec',
    };
  }

  /// Answers report-grounded user questions using Groq AI or offline canned pattern matching.
  static Future<String> askReportChatbot({
    required String userQuery,
    required PgxMultiReport report,
  }) async {
    final reportJson = report.toFormattedJson();
    final lowerQuery = userQuery.toLowerCase();

    // Check if query is out of scope (general medical advice, un-analyzed drugs, non-medical trivia)
    if (_isOutOfScope(lowerQuery, report)) {
      return 'I am PharmaGuard AI, trained strictly on your specific Pharmacogenomic Report (#${report.reportId}). I cannot provide general medical advice or answer questions about un-analyzed drugs. Please consult your physician or pharmacist for medical advice outside this report.';
    }

    final apiKey = _apiKey;
    if (apiKey != null) {
      try {
        final systemPrompt = '''You are PharmaGuard AI, a grounded clinical pharmacogenomic assistant.
You are provided with the patient's EXACT report JSON below:

<REPORT_JSON>
$reportJson
</REPORT_JSON>

STRICT INSTRUCTIONS:
1. Base your answer ONLY on the facts present in the provided report JSON.
2. If the user asks about a drug NOT present in the report, or asks general medical/non-medical questions, politely refuse to answer and suggest consulting a healthcare professional.
3. Be concise, clear, patient-friendly, and medically precise.''';

        final response = await http
            .post(
              Uri.parse(_groqBaseUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: json.encode({
                'model': _groqModel,
                'messages': [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': userQuery},
                ],
                'temperature': 0.3,
                'max_tokens': 500,
              }),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final body = json.decode(response.body);
          final text = body['choices']?[0]?['message']?['content'];
          if (text != null && text.toString().isNotEmpty) {
            return text.toString().trim();
          }
        }
      } catch (e) {
        // Fall through to offline canned answer
      }
    }

    // Offline Canned Pattern-Matching Response
    return _generateOfflineCannedAnswer(lowerQuery, report);
  }

  static bool _isOutOfScope(String query, PgxMultiReport report) {
    final testedDrugs = report.drugReports.map((r) => r.drug.toLowerCase()).toSet();
    
    final nonMedicalKeywords = [
      'weather', 'capital', 'president', 'recipe', 'football', 'cricket', 'math', 'code', 'programming', 'who are you', 'tell me a joke'
    ];
    for (var kw in nonMedicalKeywords) {
      if (query.contains(kw) && !query.contains('pharmaguard')) return true;
    }

    // Common drugs not in report check
    final externalDrugs = ['ibuprofen', 'aspirin', 'paracetamol', 'lisinopril', 'metformin', 'atorvastatin', 'levothyroxine', 'amoxicillin', 'omeprazole'];
    for (var d in externalDrugs) {
      if (query.contains(d) && !testedDrugs.contains(d)) {
        return true;
      }
    }

    return false;
  }

  static String _generateOfflineCannedAnswer(String query, PgxMultiReport report) {
    for (var d in report.drugReports) {
      final drugName = d.drug.toLowerCase();
      if (query.contains(drugName) || query.contains('why') || query.contains('safe') || query.contains('risk') || query.contains('dose')) {
        return 'Based on your report for ${d.drug}: Your ${d.pharmacogenomicProfile.primaryGene} gene diplotype is ${d.pharmacogenomicProfile.diplotype} (${d.pharmacogenomicProfile.phenotype} phenotype). The assigned risk label is "${d.riskAssessment.riskLabel}" with severity "${d.riskAssessment.severity}". Recommendation: ${d.clinicalRecommendation.dosingRecommendation}';
      }
    }

    if (query.contains('summary') || query.contains('overview') || query.contains('report')) {
      final summaryList = report.drugReports
          .map((r) => '${r.drug}: ${r.riskAssessment.riskLabel} (${r.pharmacogenomicProfile.primaryGene} ${r.pharmacogenomicProfile.phenotype})')
          .join('\n• ');
      return 'Here is your report overview:\n• $summaryList';
    }

    return 'Your report includes evaluation for ${report.drugReports.map((r) => r.drug).join(', ')}. All predictions are based on your on-device parsed VCF file. Consult your clinician for prescribing decisions.';
  }
}
