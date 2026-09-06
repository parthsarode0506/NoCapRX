import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../models/drug_evidence.dart';
import 'chat_models.dart';
import 'chat_safety_filter.dart';
import 'grounding_prompt.dart';

abstract interface class CloudFallbackService {
  bool get isConfigured;

  Future<String?> answer({
    required String question,
    DrugEvidence? evidence,
    required String safetyFacts,
  });
}

class GroqCloudFallbackService implements CloudFallbackService {
  GroqCloudFallbackService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  bool get isConfigured => _key != null;

  String? get _key {
    try {
      const defined = String.fromEnvironment('GROQ_API_KEY');
      final value = defined.isNotEmpty ? defined : dotenv.env['GROQ_API_KEY'];
      return value?.trim().isNotEmpty == true ? value!.trim() : null;
    } on NotInitializedError {
      return null;
    }
  }

  String get _model {
    const defined = String.fromEnvironment('GROQ_MODEL');
    final value = defined.isNotEmpty ? defined : dotenv.env['GROQ_MODEL'];
    return value?.trim().isNotEmpty == true
        ? value!.trim()
        : 'openai/gpt-oss-120b';
  }

  List<String> get _models => <String>{_model, 'openai/gpt-oss-120b'}.toList();

  @override
  Future<String?> answer({
    required String question,
    DrugEvidence? evidence,
    required String safetyFacts,
  }) async {
    final key = _key;
    if (key == null) return null;
    for (final model in _models) {
      try {
        final response = await _client.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': model,
            'temperature': 0.7,
            'max_tokens': 180,
            'messages': [
              {'role': 'system', 'content': GroundingPrompt.systemInstruction},
              {
                'role': 'user',
                'content': evidence == null
                    ? '${GroundingPrompt.systemInstruction}\n\nNo verified local medicine record was found. Say that you do not have reliable information and do not identify, explain, or guess the medicine. User question: $question'
                    : GroundingPrompt.forQuestion(
                        question: question,
                        intent: const ChatIntent(category: ChatQuestionCategory.unknown),
                        evidence: evidence,
                        safetyFacts: safetyFacts,
                      ),
              },
            ],
          }),
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint('Groq chat model $model failed: HTTP ${response.statusCode}');
          continue;
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final text = body['choices']?[0]?['message']?['content']?.toString();
        if (text?.trim().isNotEmpty == true) {
          return ChatSafetyFilter.withFooter(text!.trim());
        }
        debugPrint('Groq chat model $model returned an empty answer.');
      } catch (error) {
        debugPrint('Groq chat model $model failed: $error');
      }
    }
    return null;
  }
}
