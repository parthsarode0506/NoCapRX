import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../services/redacting_logger.dart';

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
  GroqCloudFallbackService({http.Client? client})
      : _client = client ?? http.Client();
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

  List<String> get _models => <String>{
        _model,
        'openai/gpt-oss-120b',
        'openai/gpt-oss-20b',
        'qwen/qwen3.8-27b',
      }.toList();

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
          RedactingLogger.log('Groq chat model $model failed: HTTP ${response.statusCode}');
          continue;
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final text = body['choices']?[0]?['message']?['content']?.toString();
        if (text?.trim().isNotEmpty == true) {
          return ChatSafetyFilter.withFooter(text!.trim());
        }
        RedactingLogger.log('Groq chat model $model returned an empty answer.');
      } catch (error) {
        RedactingLogger.log('Groq chat model $model failed: $error');
      }
    }
    return null;
  }
}

class OpenRouterCloudFallbackService implements CloudFallbackService {
  OpenRouterCloudFallbackService({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  @override
  bool get isConfigured => _key != null;

  String? get _key {
    try {
      const defined = String.fromEnvironment('OPENROUTER_API_KEY');
      final value =
          defined.isNotEmpty ? defined : dotenv.env['OPENROUTER_API_KEY'];
      return value?.trim().isNotEmpty == true ? value!.trim() : null;
    } on NotInitializedError {
      return null;
    }
  }

  String get _model {
    const defined = String.fromEnvironment('OPENROUTER_MODEL');
    final value =
        defined.isNotEmpty ? defined : dotenv.env['OPENROUTER_MODEL'];
    return value?.trim().isNotEmpty == true
        ? value!.trim()
        : 'google/gemma-4-31b-it:free';
  }

  List<String> get _models => <String>{
        _model,
        'google/gemma-4-31b-it:free',
        'apodex/apodex-1.1-mini:free',
        'liquid/lfm-2.5-2.6b:free',
        'nvidia/nemotron-3.5-lightning:free',
      }.toList();

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
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
            'HTTP-Referer': 'https://ondevicerx.app',
            'X-Title': 'NoCapRx AI',
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
          RedactingLogger.log(
              'OpenRouter model $model failed: HTTP ${response.statusCode}');
          continue;
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final text = body['choices']?[0]?['message']?['content']?.toString();
        if (text?.trim().isNotEmpty == true) {
          return ChatSafetyFilter.withFooter(text!.trim());
        }
      } catch (error) {
        RedactingLogger.log('OpenRouter model $model failed: $error');
      }
    }
    return null;
  }
}

class MultiCloudFallbackService implements CloudFallbackService {
  MultiCloudFallbackService({
    GroqCloudFallbackService? groq,
    OpenRouterCloudFallbackService? openRouter,
  })  : _groq = groq ?? GroqCloudFallbackService(),
        _openRouter = openRouter ?? OpenRouterCloudFallbackService();

  final GroqCloudFallbackService _groq;
  final OpenRouterCloudFallbackService _openRouter;

  @override
  bool get isConfigured => _groq.isConfigured || _openRouter.isConfigured;

  @override
  Future<String?> answer({
    required String question,
    DrugEvidence? evidence,
    required String safetyFacts,
  }) async {
    // 1. Try Groq (GROQ_MODEL: openai/gpt-oss-120b)
    if (_groq.isConfigured) {
      final res = await _groq.answer(
        question: question,
        evidence: evidence,
        safetyFacts: safetyFacts,
      );
      if (res != null && res.trim().isNotEmpty) return res;
    }

    // 2. Try OpenRouter (OPENROUTER_MODEL: google/gemma-4-31b-it:free)
    if (_openRouter.isConfigured) {
      final res = await _openRouter.answer(
        question: question,
        evidence: evidence,
        safetyFacts: safetyFacts,
      );
      if (res != null && res.trim().isNotEmpty) return res;
    }

    return null;
  }
}
