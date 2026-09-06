import '../../models/drug_evidence.dart';

enum ChatQuestionCategory { use, sideEffects, warnings, interactions, dosageForm, unknown }

class ChatIntent {
  final String? medicineQuery;
  final ChatQuestionCategory category;

  const ChatIntent({this.medicineQuery, required this.category});
}

class ChatAnswer {
  final String text;
  final String sourceLabel;
  final bool canUseCloudFallback;
  final DrugEvidence? evidence;

  const ChatAnswer({
    required this.text,
    required this.sourceLabel,
    this.canUseCloudFallback = false,
    this.evidence,
  });
}