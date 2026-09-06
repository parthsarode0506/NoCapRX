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

  test('rejects an AI response that contradicts deterministic risk', () async {
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

    expect(
      () => service.generateExplanation(
        userRole: 'patient',
        medicalResult: {'medicine': 'Clopidogrel', 'riskLabel': 'High Risk'},
      ),
      throwsA(isA<StateError>()),
    );
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

  test('preserves medicine safety findings for the explanation request', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': jsonEncode(validResponse())}},
          ],
        }),
        200,
      );
    });
    final service = GroqAIService(client: client, apiKey: 'test-key');

    await service.generateExplanation(
      userRole: 'patient',
      medicalResult: {
        'medicine': 'Ibuprofen',
        'riskLabel': 'High Risk',
        'interactions': [
          {
            'status': 'DRUG_INTERACTION_DETECTED',
            'title': 'Anticoagulant Interaction (Warfarin)',
            'explanation': 'Bleeding risk is increased.',
            'evidence_source': 'FDA warning',
            'interacting_drug': 'Warfarin',
          },
        ],
      },
    );

    final userContent = (requestBody['messages'] as List)
        .last as Map<String, dynamic>;
    final payload = jsonDecode(userContent['content'] as String)
        as Map<String, dynamic>;
    final finding = (payload['interactions'] as List).single
        as Map<String, dynamic>;
    expect(finding['status'], 'DRUG_INTERACTION_DETECTED');
    expect(finding['title'], 'Anticoagulant Interaction (Warfarin)');
    expect(finding['explanation'], 'Bleeding risk is increased.');
    expect(finding['interacting_drug'], 'Warfarin');
  });

  test('rejects direct medication-change instructions', () {
    final unsafe = validResponse()
      ..['whatItMeans'] = 'Stop your medicine immediately.';

    expect(
      AIResponseValidator.validate(unsafe, {'riskLabel': 'High Risk'}),
      isNull,
    );
  });

  test('answers a general health question through the chat endpoint', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['messages'], hasLength(2));
      final userMessage = (body['messages'] as List).last as Map<String, dynamic>;
      expect(userMessage['content'], 'What is a fever?');

      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'A fever is a temporary rise in body temperature.'
              }
            }
          ],
        }),
        200,
      );
    });
    final service = GroqAIService(client: client, apiKey: 'test-key');

    final result = await service.answerHealthQuestion(
      question: 'What is a fever?',
    );

    expect(result, contains('temporary rise'));
    expect(calls, 1);
  });

  test('does not return a static answer when live AI is unavailable', () async {
    final service = GroqAIService(client: MockClient((_) async => http.Response('', 503)));

    expect(
      () => service.answerHealthQuestion(question: 'What is a fever?'),
      throwsA(isA<StateError>()),
    );
  });

  test('retries the health answer with a supported fallback model', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (calls == 1) return http.Response('model unavailable', 404);
      expect(body['model'], 'openai/gpt-oss-120b');
      return http.Response(
        jsonEncode({'choices': [{'message': {'content': 'Genetics is the study of inherited traits.'}}]}),
        200,
      );
    });
    final service = GroqAIService(
      client: client,
      apiKey: 'test-key',
      model: 'unavailable-model',
    );

    final result = await service.answerHealthQuestion(question: 'What is genetics?');

    expect(result, contains('inherited traits'));
    expect(calls, 2);
  });

  test('looks up unknown medicine facts without assigning risk', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['response_format'], {'type': 'json_object'});
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'genericName': 'Examplemab',
                  'displayName': 'Examplemab',
                  'uses': 'Treatment of a condition',
                  'commonSideEffects': 'Headache',
                  'seriousSideEffects': 'Severe allergic reaction',
                  'precautions': 'Use under medical supervision',
                  'pgxRelevance': 'no',
                  'pgxGene': '',
                  'pgxPhenotypes': '',
                  'guidelineSummary': 'No verified PGx guideline found.',
                  'evidenceLevel': 'No actionable PGx association',
                  'confidence': 0.9,
                  'isRealMedicine': true,
                }),
              },
            },
          ],
        }),
        200,
      );
    });
    final service = GroqAIService(client: client, apiKey: 'test-key');
    final result = await service.searchDrugOnline('Examplemab');

    expect(result?['genericName'], 'Examplemab');
    expect(result?['uses'], 'Treatment of a condition');
  });
}
