import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

/// Extracts text from a prescription image on supported mobile platforms.
/// Medicine identity is still confirmed by the local resolver after OCR.
class PrescriptionOcrService {
  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const _defaultModel = 'openai/gpt-image-2';

  static Future<String> extractText(
    String imagePath, {
    http.Client? client,
    String? apiKey,
    String? model,
  }) async {
    final key = apiKey?.trim().isNotEmpty == true
        ? apiKey!.trim()
      : _env('OPENROUTER_API_KEY')?.trim();

    if (key == null || key.isEmpty || key.startsWith('YOUR_')) {
      return _extractLocally(imagePath);
    }

    final bytes = await File(imagePath).readAsBytes();
    final mimeType = _mimeType(imagePath);
    try {
      final response = await (client ?? http.Client()).post(
        Uri.parse(_endpoint),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://ondevicerx.app',
          'X-Title': 'PharmaGuard Prescription OCR',
        },
        body: jsonEncode({
            'model': _defaultModel,
          'temperature': 0,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Read all medicine names and prescription instructions '
                      'in this image. Return only the visible text, preserving '
                      'line breaks. Do not add explanations or guesses.',
                },
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
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        // OpenRouter 402 means its paid route is unavailable. ML Kit is the
        // offline path and must still be allowed to read the prescription.
        return _extractLocally(imagePath);
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

      return text.trim().isEmpty ? _extractLocally(imagePath) : text.trim();
    } catch (_) {
      return _extractLocally(imagePath);
    }
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