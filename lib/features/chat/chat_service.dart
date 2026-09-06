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
  }) async {
    final intent = MedicineRetriever.parse(question, contextMedicine: contextMedicine);
    final evidence = MedicineRetriever.retrieve(question, contextMedicine: contextMedicine);
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
            sourceLabel: 'On-device AI',
          );
        }
      } catch (_) {
        // The UI will show a local-model availability message below.
      }
      try {
        final text = await cloud.answer(
          question: question,
          safetyFacts: 'No verified local medicine record was found.',
        );
        if (text?.trim().isNotEmpty == true) {
          return ChatAnswer(
            text: text!.trim(),
            sourceLabel: 'Live AI',
          );
        }
      } catch (_) {}
      return ChatAnswer(
        text: ChatSafetyFilter.withFooter(
          'The on-device AI is not ready yet. Please wait for it to finish loading and ask again.',
        ),
        sourceLabel: 'On-device AI',
      );
    }

    final findings = UniversalMedicineSafetyEngine.evaluateAll(
      evidence.genericName,
      profile.toClinicalDataMap(),
    );
    final safetyFacts = findings.isEmpty
        ? 'No applicable local safety finding was generated. Do not interpret this as a safety guarantee.'
        : findings.map((finding) => finding.toJson().entries.map((e) => '${e.key}: ${e.value}').join(', ')).join('\n');
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
          sourceLabel: 'On-device AI',
          evidence: evidence,
        );
      }
    } catch (_) {}

    try {
      final text = await cloud.answer(
        question: question,
        evidence: evidence,
        safetyFacts: safetyFacts,
      );
      if (text?.trim().isNotEmpty == true) {
        return ChatAnswer(
          text: text!.trim(),
          sourceLabel: 'Live AI',
          evidence: evidence,
        );
      }
    } catch (_) {}

    return ChatAnswer(
      text: ChatSafetyFilter.withFooter(
        'The on-device AI could not produce an answer. Please wait a moment and try again.',
      ),
      sourceLabel: 'On-device AI',
      evidence: evidence,
    );
  }

  Future<void> dispose() => onDevice.dispose();
}
