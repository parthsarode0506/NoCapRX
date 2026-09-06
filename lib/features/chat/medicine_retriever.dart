import '../../models/drug_evidence.dart';
import '../../services/drug_repository.dart';
import 'chat_models.dart';

class MedicineRetriever {
  static DrugEvidence? retrieve(String question, {String? contextMedicine}) {
    final query = contextMedicine?.trim().isNotEmpty == true
        ? contextMedicine!
        : _medicineMention(question);
    if (query == null || query.isEmpty) return null;
    final metadata = DrugRepository.resolve(query);
    return metadata == null ? null : DrugRepository.toDrugEvidence(metadata);
  }

  static ChatIntent parse(String question, {String? contextMedicine}) {
    final lower = question.toLowerCase();
    final category = lower.contains('side effect') || lower.contains('reaction')
        ? ChatQuestionCategory.sideEffects
        : lower.contains('interaction') ||
              lower.contains('combine') ||
              lower.contains('together')
        ? ChatQuestionCategory.interactions
        : lower.contains('warning') ||
              lower.contains('precaution') ||
              lower.contains('when should')
        ? ChatQuestionCategory.warnings
        : lower.contains('use') || lower.contains('prescribed')
        ? ChatQuestionCategory.use
        : lower.contains('form') ||
              lower.contains('tablet or capsule') ||
              lower.contains('capsule or tablet')
        ? ChatQuestionCategory.dosageForm
        : ChatQuestionCategory.unknown;
    return ChatIntent(
      medicineQuery: contextMedicine ?? _medicineMention(question),
      category: category,
    );
  }

  static String? _medicineMention(String question) {
    final words = question
        .replaceAll(RegExp(r'[^A-Za-z0-9+#/-]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    const ignoredWords = {
      'a',
      'about',
      'and',
      'are',
      'can',
      'does',
      'for',
      'how',
      'is',
      ' medicine',
      'my',
      'of',
      ' the',
      'this',
      'to',
      'use',
      'used',
      'what',
      'which',
      'with',
    };

    // Try the longest phrases first so brand names such as "Dolo 650" win
    // over a shorter token from the same question.
    for (var length = 4; length >= 1; length--) {
      for (var start = 0; start + length <= words.length; start++) {
        final phraseWords = words.sublist(start, start + length);
        if (phraseWords.any(
          (word) => ignoredWords.contains(word.toLowerCase()),
        )) {
          continue;
        }
        final metadata = DrugRepository.resolve(phraseWords.join(' '));
        if (metadata != null) return metadata.genericName;
      }
    }
    return null;
  }
}
