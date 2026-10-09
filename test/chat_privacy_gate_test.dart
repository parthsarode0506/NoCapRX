import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/features/chat/chat_models.dart';
import 'package:ondevicerx/features/chat/chat_service.dart';
import 'package:ondevicerx/features/chat/cloud_fallback_service.dart';
import 'package:ondevicerx/features/chat/on_device_chat_service.dart';

class _FakeCloudFallbackService implements CloudFallbackService {
  bool called = false;

  @override
  bool get isConfigured => true;

  @override
  Future<String?> answer({
    required String question,
    required String safetyFacts,
    dynamic evidence,
  }) async {
    called = true;
    return 'cloud answer';
  }
}

class _FakeOnDeviceChatService extends OnDeviceChatService {
  @override
  Future<String> answerWithoutLocalEvidence({
    required String question,
    required ChatIntent intent,
  }) async {
    return 'offline answer';
  }

  @override
  Future<String> answer({
    required String question,
    required ChatIntent intent,
    required dynamic evidence,
    required String safetyFacts,
  }) async {
    return 'offline answer';
  }
}

void main() {
  test('cloud AI is blocked unless explicit user consent is granted', () async {
    final cloud = _FakeCloudFallbackService();
    final service = ChatService(
      cloud: cloud,
      onDevice: _FakeOnDeviceChatService(),
    );

    final answer = await service.answer(
      question: 'What is amoxicillin?',
      allowCloudAi: false,
    );

    expect(cloud.called, isFalse);
    expect(answer.sourceLabel, isNot(contains('Live AI')));
    expect(answer.text, contains('No verified local medicine record was found'));
  });
}
