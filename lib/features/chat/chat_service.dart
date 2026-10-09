import '../../models/patient_profile.dart';
import '../../services/universal_medicine_safety_engine.dart';
import 'chat_models.dart';
import 'chat_safety_filter.dart';
import 'cloud_fallback_service.dart';
import 'medicine_retriever.dart';
import 'on_device_chat_service.dart';

class ChatService {
  ChatService({OnDeviceChatService? onDevice, CloudFallbackService? cloud})
    : onDevice = onDevice ?? OnDeviceChatService(),
      cloud = cloud ?? GroqCloudFallbackService();

  final OnDeviceChatService onDevice;
  final CloudFallbackService cloud;

  Future<void> load() => onDevice.load();

  Future<ChatAnswer> answer({
    required String question,
    PatientProfile profile = const PatientProfile(),
    String? contextMedicine,
    bool allowCloudAi = false,
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
      if (allowCloudAi) {
        try {
          final text = await cloud.answer(
            question: question,
            safetyFacts: 'No verified local medicine record was found.',
          );
          if (text?.trim().isNotEmpty == true) {
            return ChatAnswer(
              text: text!.trim(),
              sourceLabel: 'Live AI (consent-gated)',
            );
          }
        } catch (_) {}
      }

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
          'No verified local medicine record was found. This chat remains on-device unless you explicitly opt in to the cloud AI proxy.',
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

    if (allowCloudAi) {
      try {
        final text = await cloud.answer(
          question: question,
          evidence: evidence,
          safetyFacts: safetyFacts,
        );
        if (text?.trim().isNotEmpty == true) {
          return ChatAnswer(
            text: text!.trim(),
            sourceLabel: 'Live AI (consent-gated)',
            evidence: evidence,
          );
        }
      } catch (_) {}
    }

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
        'The local recommendation is available offline. Cloud AI remains off until you explicitly grant consent.',
      ),
      sourceLabel: 'On-device only',
      evidence: evidence,
    );
  }

  Future<void> dispose() => onDevice.dispose();
}
