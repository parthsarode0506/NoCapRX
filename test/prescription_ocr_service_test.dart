import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondevicerx/services/prescription_ocr_service.dart';

void main() {
  test('sends the prescription image to OpenRouter and returns OCR text', () async {
    final image = File('${Directory.systemTemp.path}/prescription.png');
    await image.writeAsBytes(<int>[137, 80, 78, 71]);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });

    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final content = ((body['messages'] as List).first
              as Map<String, dynamic>)['content'] as List;
      final imagePart = content.last as Map<String, dynamic>;

      expect(request.url.toString(),
          'https://openrouter.ai/api/v1/chat/completions');
      expect(request.headers['authorization'], 'Bearer test-key');
      expect(body['model'], 'openai/gpt-image-2');
      expect((imagePart['image_url'] as Map)['url'], startsWith('data:image/png;base64,'));

      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': 'Amoxicillin 500 mg'}},
          ],
        }),
        200,
      );
    });

    final result = await PrescriptionOcrService.extractText(
      image.path,
      client: client,
      apiKey: 'test-key',
    );

    expect(result, 'Amoxicillin 500 mg');
  });

  test('always uses the OpenAI image OCR model', () async {
    final image = File('${Directory.systemTemp.path}/prescription-model.png');
    await image.writeAsBytes(<int>[137, 80, 78, 71]);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });

    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'openai/gpt-image-2');
      return http.Response(
        jsonEncode({'choices': [{'message': {'content': 'Aspirin'}}]}),
        200,
      );
    });

    await PrescriptionOcrService.extractText(
      image.path,
      client: client,
      apiKey: 'test-key',
      model: 'meta-llama/llama-4-scout-17b-16e-instruct',
    );
  });
}