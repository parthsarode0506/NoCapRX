import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondevicerx/services/ai_response_validator.dart';
import 'package:ondevicerx/services/groq_ai_service.dart';

Map<String, dynamic> validResponse() => {
      'title': 'High Risk',
      'summary': 'The deterministic result is High Risk.',
      'whatItMeans': 'This medicine may carry a higher concern for you.',
      'whyThisResult': 'The supplied verified finding supports this classification.',
      'importantRisks': <String>['Discuss the result with a clinician.'],
      'sideEffectExplanation': <String>['No additional side-effect explanation is available.'],
      'whatToDiscussWithDoctor': <String>['Ask your doctor or pharmacist to review this result.'],
      'technicalDetails': 'The supplied deterministic result remains authoritative.',
      'limitations': 'Do not change your medicine without professional advice.',
    };

void main() {
  test('accepts a valid grounded response and preserves deterministic risk', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': jsonEncode(validResponse())}},
            ],
          }),
          200,
        ));
    final service = GroqAIService(client: client, apiKey: 'test-key');

    final result = await service.generateExplanation(
      userRole: 'patient',
      medicalResult: {'medicine': 'Clopidogrel', 'riskLabel': 'High Risk'},
    );

    expect(result['summary'], contains('High Risk'));
  });

  test('falls back when the response contradicts deterministic risk', () async {
    final contradictory = validResponse()..['summary'] = 'This is safe.';
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': jsonEncode(contradictory)}},
            ],
          }),
          200,
        ));
    final service = GroqAIService(client: client, apiKey: 'test-key');

    final result = await service.generateExplanation(
      userRole: 'patient',
      medicalResult: {'medicine': 'Clopidogrel', 'riskLabel': 'High Risk'},
    );

    expect(result['patient_friendly'], contains('AI explanation is unavailable'));
  });

  test('does not transmit raw VCF or unapproved fields', () async {
    final sanitized = GroqAIService.sanitizeMedicalResult({
      'medicine': 'Clopidogrel',
      'riskLabel': 'Unknown',
      'rawVcf': '##fileformat=VCFv4.2\nchr1 sensitive genotype data',
      'patientId': 'PATIENT-PRIVATE',
    });

    final requestBody = jsonEncode(sanitized);
    expect(requestBody, contains('Clopidogrel'));
    expect(requestBody, isNot(contains('sensitive genotype data')));
    expect(requestBody, isNot(contains('PATIENT-PRIVATE')));
  });

  test('rejects direct medication-change instructions', () {
    final unsafe = validResponse()
      ..['whatItMeans'] = 'Stop your medicine immediately.';

    expect(
      AIResponseValidator.validate(unsafe, {'riskLabel': 'High Risk'}),
      isNull,
    );
  });
}
