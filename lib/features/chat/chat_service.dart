import '../../models/patient_profile.dart';
import '../../services/universal_medicine_safety_engine.dart';
import 'chat_models.dart';
import 'chat_safety_filter.dart';
import 'cloud_fallback_service.dart';
import 'medicine_retriever.dart';
import 'on_device_chat_service.dart';

/// Hybrid chat pipeline: uses on-device model when available, seamlessly
/// falls back to grounded cloud AI when configured, or returns safe local facts.
class ChatService {
  ChatService({OnDeviceChatService? onDevice, CloudFallbackService? cloud})
      : onDevice = onDevice ?? OnDeviceChatService(),
        cloud = cloud ?? MultiCloudFallbackService();

  final OnDeviceChatService onDevice;
  final CloudFallbackService cloud;

  bool get isReady => onDevice.isReady || cloud.isConfigured;

  Future<void> load() async {
    try {
      await onDevice.load();
    } catch (_) {
      // On-device model not installed or unsupported on this platform; cloud fallback will be used.
    }
  }

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

      if (cloud.isConfigured) {
        try {
          final text = await cloud.answer(
            question: question,
            evidence: null,
            safetyFacts: 'No verified local medicine record was found.',
          );
          if (text != null && text.trim().isNotEmpty) {
            return ChatAnswer(
              text: text,
              sourceLabel: 'NoCapRx AI',
            );
          }
        } catch (_) {}
      }

      return ChatAnswer(
        text: ChatSafetyFilter.withFooter(
          'No verified local medicine record was found in the database. '
          'Please verify the medicine name or speak with a doctor or pharmacist.',
        ),
        sourceLabel: 'On-device safe mode',
      );
    }

    final findings = UniversalMedicineSafetyEngine.evaluateAll(
      evidence.genericName,
      profile.toClinicalDataMap(),
    );
    final safetyFacts = findings.isEmpty
        ? 'No applicable local safety warning was triggered by your current profile.'
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

    if (cloud.isConfigured) {
      try {
        final text = await cloud.answer(
          question: question,
          evidence: evidence,
          safetyFacts: safetyFacts,
        );
        if (text != null && text.trim().isNotEmpty) {
          return ChatAnswer(
            text: text,
            sourceLabel: 'NoCapRx AI',
            evidence: evidence,
          );
        }
      } catch (_) {}
    }

    final buffer = StringBuffer();
    if (evidence.displayName.isNotEmpty) {
      buffer.writeln('Medicine: ${evidence.displayName}');
    }
    if (evidence.activeIngredients.isNotEmpty) {
      buffer.writeln('Active ingredients: ${evidence.activeIngredients.join(', ')}');
    }
    if (evidence.uses.isNotEmpty) {
      buffer.writeln('Uses: ${evidence.uses.join('; ')}');
    }
    if (evidence.commonSideEffects.isNotEmpty) {
      buffer.writeln('Common side effects: ${evidence.commonSideEffects.join('; ')}');
    }
    if (evidence.seriousSideEffects.isNotEmpty) {
      buffer.writeln('Important warnings: ${evidence.seriousSideEffects.join('; ')}');
    }
    buffer.writeln('\nSafety evaluation:\n$safetyFacts');

    return ChatAnswer(
      text: ChatSafetyFilter.withFooter(buffer.toString().trim()),
      sourceLabel: 'Verified medical record',
      evidence: evidence,
    );
  }

  Future<void> dispose() => onDevice.dispose();
}
