import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

/// Extracts text and medicine names from a prescription image.
///
/// Cloud vision (OpenRouter) is used automatically when OPENROUTER_API_KEY is
/// configured in .env. On-device Google ML Kit is always the fallback when
/// cloud is unavailable, rate-limited, or fails for any reason.
class PrescriptionOcrService {
  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  // Free vision-capable model on OpenRouter. Paid defaults (e.g. gpt-6.1-sol)
  // return 402 on free keys, so keep the default on the free tier.
  static const _defaultModel = 'google/gemma-4-31b-it:free';

  /// Human-readable reason the last cloud attempt failed, for UI diagnostics.
  static String? lastCloudError;

  static String? get _apiKey {
    final value = _env('OPENROUTER_API_KEY')?.trim();
    return value == null || value.isEmpty || value.startsWith('YOUR_')
        ? null
        : value;
  }

  static String get _model {
    final value = _env('OPENROUTER_MODEL')?.trim();
    return value == null || value.isEmpty ? _defaultModel : value;
  }

  /// Extracts raw visible text from the image.
  static Future<String> extractText(
    String imagePath, {
    http.Client? client,
    String? apiKey,
    String? model,
    bool? allowCloudAi, // null = auto: cloud only when a key exists
  }) async {
    final cloud = await _cloudVision(
      imagePath,
      prompt: 'Read all medicine names and prescription instructions '
          'in this image. Return only the visible text, preserving '
          'line breaks. Do not add explanations or guesses.',
      client: client,
      apiKey: apiKey,
      model: model,
      allowCloudAi: allowCloudAi,
      maxTokens: 1024,
    );
    if (cloud != null && cloud.trim().isNotEmpty) return cloud.trim();
    return _extractLocally(imagePath);
  }

  /// Asks the vision model to return medicine names as JSON.
  /// Returns null when cloud is unavailable or parsing fails — the caller
  /// should then fall back to [extractText] + local matching.
  static Future<List<String>?> extractMedicinesFromImage(
    String imagePath, {
    http.Client? client,
    String? apiKey,
    String? model,
  }) async {
    final raw = await _cloudVision(
      imagePath,
      prompt: 'Look at this prescription image. Identify every medicine name '
          'written on it (generic or brand). Ignore dosages, strengths, '
          'frequencies, durations, doctor details, and patient details. '
          'Return ONLY a JSON object of the form '
          '{"medicines": ["name1", "name2"]}. '
          'If no medicine names are visible, return {"medicines": []}.',
      client: client,
      apiKey: apiKey,
      model: model,
      allowCloudAi: null,
      maxTokens: 400,
      jsonMode: true,
    );
    if (raw == null) return null;
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start == -1 || end <= start) return null;
      final decoded = jsonDecode(raw.substring(start, end + 1));
      final list = decoded is Map ? decoded['medicines'] : null;
      if (list is! List) return null;
      final names = list
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty && e.length > 1)
          .toSet()
          .toList();
      return names;
    } catch (_) {
      return null;
    }
  }

  /// Shared cloud vision call. Returns null on any failure and records why.
  static Future<String?> _cloudVision(
    String imagePath, {
    required String prompt,
    http.Client? client,
    String? apiKey,
    String? model,
    bool? allowCloudAi,
    int maxTokens = 1024,
    bool jsonMode = false,
  }) async {
    final key = apiKey?.trim().isNotEmpty == true
        ? apiKey!.trim()
        : _apiKey;
    final keyAvailable = key != null && key.isNotEmpty;
    final useCloud = allowCloudAi ?? keyAvailable;

    if (!useCloud || !keyAvailable) {
      lastCloudError = 'No OpenRouter API key configured';
      return null;
    }

    final effectiveModel = model?.trim().isNotEmpty == true
        ? model!.trim()
        : _model;

    final File file;
    try {
      file = File(imagePath);
      if (!file.existsSync()) {
        lastCloudError = 'Image file not found';
        return null;
      }
    } catch (_) {
      lastCloudError = 'Image file not found';
      return null;
    }

    final bytes = await file.readAsBytes();
    final mimeType = _mimeType(imagePath);

    // One retry with backoff for rate-limited free-tier models.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await (client ?? http.Client())
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://ondevicerx.app',
                'X-Title': 'NoCapRX Prescription OCR',
              },
              body: jsonEncode({
                'model': effectiveModel,
                'temperature': 0,
                'max_tokens': maxTokens,
                'messages': [
                  {
                    'role': 'user',
                    'content': [
                      {'type': 'text', 'text': prompt},
                      {
                        'type': 'image_url',
                        'image_url': {
                          'url': 'data:$mimeType;base64,${base64Encode(bytes)}',
                        },
                      },
                    ],
                  },
                ],
              }),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 429) {
          lastCloudError = 'Cloud AI is rate-limited (free tier). Retrying…';
          debugPrint('PrescriptionOcrService: 429 rate limited (attempt $attempt)');
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 4));
            continue;
          }
          return null;
        }
        if (response.statusCode == 402) {
          lastCloudError =
              'Model "$effectiveModel" requires a paid plan. Set OPENROUTER_MODEL to a free model in .env';
          debugPrint('PrescriptionOcrService: 402 payment required for $effectiveModel');
          return null;
        }
        if (response.statusCode == 404) {
          lastCloudError =
              'Model "$effectiveModel" not found. Check OPENROUTER_MODEL in .env';
          debugPrint('PrescriptionOcrService: 404 model not found: $effectiveModel');
          return null;
        }
        if (response.statusCode == 401 || response.statusCode == 403) {
          lastCloudError = 'OpenRouter API key was rejected. Check OPENROUTER_API_KEY';
          debugPrint('PrescriptionOcrService: auth error ${response.statusCode}');
          return null;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastCloudError = 'Cloud OCR failed (HTTP ${response.statusCode})';
          debugPrint('PrescriptionOcrService: HTTP ${response.statusCode}: '
              '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
          return null;
        }

        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = payload['choices'] as List<dynamic>?;
        final message = choices?.isNotEmpty == true
            ? choices!.first['message'] as Map<String, dynamic>?
            : null;
        final content = message?['content'];
        final text = content is String
            ? content
            : content is List
                ? content
                    .whereType<Map<String, dynamic>>()
                    .map((part) => part['text'])
                    .whereType<String>()
                    .join()
                : '';

        if (text.trim().isEmpty) {
          lastCloudError = 'Cloud OCR returned an empty response';
          debugPrint('PrescriptionOcrService: empty cloud response');
          return null;
        }
        lastCloudError = null;
        debugPrint('PrescriptionOcrService: cloud OCR succeeded via $effectiveModel');
        return text.trim();
      } catch (e) {
        lastCloudError = 'Cloud OCR unreachable. Check internet connection.';
        debugPrint('PrescriptionOcrService: network error (attempt $attempt): $e');
        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        return null;
      }
    }
    return null;
  }

  static Future<String> writeImageBytesToTempFile(
    List<int> bytes, {
    String extension = 'jpg',
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('nocaprx_prescription_');
    final fileName =
        'prescription_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<String> _extractLocally(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(input);
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }

  static String _mimeType(String path) {
    switch (path.toLowerCase().split('.').last) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  static String? _env(String key) {
    try {
      return dotenv.env[key];
    } on NotInitializedError {
      return null;
    }
  }
}
