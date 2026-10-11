import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/features/chat/chat_models.dart';
import 'package:ondevicerx/features/chat/chat_service.dart';
import 'package:ondevicerx/features/chat/on_device_chat_service.dart';

class _FakeOnDeviceChatService extends OnDeviceChatService {
  bool called = false;

  @override
  Future<String> answerWithoutLocalEvidence({
    required String question,
    required ChatIntent intent,
  }) async {
    called = true;
    return 'offline answer';
  }

  @override
  Future<String> answer({
    required String question,
    required ChatIntent intent,
    required dynamic evidence,
    required String safetyFacts,
  }) async {
    called = true;
    return 'offline answer';
  }
}

void main() {
  test('chat service is fully on-device and never uses cloud AI', () async {
    final onDevice = _FakeOnDeviceChatService();
    final service = ChatService(onDevice: onDevice);

    final answer = await service.answer(
      question: 'What is amoxicillin?',
    );

    expect(onDevice.called, isTrue);
    expect(answer.sourceLabel, isNot(contains('Live AI')));
    expect(answer.sourceLabel, contains('On-device'));
    expect(answer.text, contains('offline answer'));
  });
}
