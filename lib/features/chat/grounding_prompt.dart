import '../../models/drug_evidence.dart';
import 'chat_models.dart';

class GroundingPrompt {
  static const systemInstruction =
      '''You are a medicine-information assistant. Only use the facts provided below. Do not add any medical facts, dosages, or advice not explicitly given. If the answer isn't in the provided facts, say you don't have reliable information and suggest asking a doctor or pharmacist. Never tell the user to stop or change their medication.''';

  static String forQuestion({
    required String question,
    required ChatIntent intent,
    required DrugEvidence evidence,
    required String safetyFacts,
  }) {
    return '''$systemInstruction

Question category: ${intent.category.name}
User question: $question

VERIFIED LOCAL MEDICINE FACTS (the only allowed source):
Medicine: ${evidence.displayName}
Active ingredients: ${evidence.activeIngredients.join('; ')}
Uses: ${evidence.uses.join('; ')}
Common side effects: ${evidence.commonSideEffects.join('; ')}
Serious side effects: ${evidence.seriousSideEffects.join('; ')}
Precautions: ${evidence.precautions.join('; ')}
Dosage form: ${evidence.dosageForm ?? 'not available'}

LOCAL SAFETY ENGINE OUTPUT (authoritative for interaction questions):
$safetyFacts

Answer in simple language, in at most 120 words. For a question asking what a
tablet or medicine is used for, answer directly from the Uses field first. A
tablet is a dosage form, not a medicine name; do not guess its contents from
the word tablet alone. If the requested fact is missing, say you don't have
reliable information about it.''';
  }

  /// Used when the medicine has not been found in the bundled catalogue.
  /// The local model can still provide a general educational answer, but is
  /// explicitly prevented from presenting an uncertain answer as a verified
  /// record or from giving individual treatment instructions.
  static String forUngroundedQuestion({
    required String question,
    required ChatIntent intent,
    String? medicineName,
  }) {
    return '''You are an on-device medicine-information assistant. Answer the
user's question using your general medical knowledge. No local medicine record
is available for this request, so do not claim that you checked a label,
database, prescription, or the user's medical record. Be clear when details
can vary by product, country, strength, or person. Do not give personalised
dosages, diagnose, or tell the user to start, stop, or change a medicine.
Encourage urgent professional help for severe symptoms or an emergency.

Question category: ${intent.category.name}
Medicine mentioned: ${medicineName ?? 'not identified'}
User question: $question

Give a helpful, concise answer in simple language, at most 120 words.''';
  }
}
