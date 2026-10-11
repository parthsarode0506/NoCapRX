import '../../models/patient_profile.dart';
import '../../services/universal_medicine_safety_engine.dart';
import 'chat_models.dart';
import 'chat_safety_filter.dart';
import 'medicine_retriever.dart';
import 'on_device_chat_service.dart';

/// Fully on-device chat pipeline. No cloud AI is ever contacted.
class ChatService {
  ChatService({OnDeviceChatService? onDevice})
    : onDevice = onDevice ?? OnDeviceChatService();

  final OnDeviceChatService onDevice;

  Future<void> load() => onDevice.load();

  Future<ChatAnswer> answer({
    required String question,
    PatientProfile profile = const PatientProfile(),
    String? contextMedicine,
  }) async {
    final intent = MedicineRetriever.parse(
      question,
      contextMedicine: contextMedicine,
    );
    final evidence = MedicineRetriever.retrieve(
      question,
      contextMedicine: contextMedicine,
    );

    if (evidence == null) {
      try {
        final text = await onDevice.answerWithoutLocalEvidence(
          question: question,
          intent: intent,
        );
        final valid = ChatSafetyFilter.validate(text);
        if (valid != null) {
          return ChatAnswer(
            text: ChatSafetyFilter.withFooter(valid),
            sourceLabel: 'On-device AI fallback',
          );
        }
      } catch (_) {}

      return ChatAnswer(
        text: ChatSafetyFilter.withFooter(
          'No verified local medicine record was found. This chat stays entirely on this device.',
        ),
        sourceLabel: 'On-device only',
      );
    }

    final findings = UniversalMedicineSafetyEngine.evaluateAll(
      evidence.genericName,
      profile.toClinicalDataMap(),
    );
    final safetyFacts = findings.isEmpty
        ? 'No applicable local safety finding was generated. Do not interpret this as a safety guarantee.'
        : findings
              .map(
                (finding) => finding
                    .toJson()
                    .entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join(', '),
              )
              .join('\n');

    try {
      final text = await onDevice.answer(
        question: question,
        intent: intent,
        evidence: evidence,
        safetyFacts: safetyFacts,
      );
      final valid = ChatSafetyFilter.validate(text);
      if (valid != null) {
        return ChatAnswer(
          text: ChatSafetyFilter.withFooter(valid),
          sourceLabel: 'On-device AI fallback',
          evidence: evidence,
        );
      }
    } catch (_) {}

    return ChatAnswer(
      text: ChatSafetyFilter.withFooter(
        'The local recommendation is available offline. No cloud AI is used.',
      ),
      sourceLabel: 'On-device only',
      evidence: evidence,
    );
  }

  Future<void> dispose() => onDevice.dispose();
}
