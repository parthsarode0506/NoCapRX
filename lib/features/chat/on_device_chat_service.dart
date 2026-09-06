import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../models/drug_evidence.dart';
import 'chat_models.dart';
import 'grounding_prompt.dart';

class OnDeviceChatService {
  static const modelAsset = 'assets/models/gemma-3n-E2B-it-int4.task';
  InferenceModel? _model;
  InferenceChat? _chat;

  bool get isReady => _chat != null;

  Future<void> load() async {
    if (isReady) return;
    if (!await FlutterGemma.isModelInstalled(modelAsset)) {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromAsset(modelAsset).install();
    }
    _model = await FlutterGemma.getActiveModel(
      maxTokens: 1024,
      preferredBackend: PreferredBackend.gpu,
    );
    _chat = await _model!.createChat(
      systemInstruction: GroundingPrompt.systemInstruction,
      maxOutputTokens: 160,
    );
    debugPrint('NOCAPRx on-device backend requested: GPU (MediaPipe runtime).');
  }

  Future<String> answer({
    required String question,
    required ChatIntent intent,
    required DrugEvidence evidence,
    required String safetyFacts,
  }) async {
    final chat = _chat;
    if (chat == null) throw StateError('On-device model is not loaded.');
    await chat.addQueryChunk(Message.text(
      text: GroundingPrompt.forQuestion(
        question: question,
        intent: intent,
        evidence: evidence,
        safetyFacts: safetyFacts,
      ),
      isUser: true,
    ));
    final response = await chat.generateChatResponse();
    final text = response is TextResponse ? response.token.trim() : '';
    if (text.isEmpty) throw StateError('Empty on-device response.');
    return text;
  }

  Future<String> answerWithoutLocalEvidence({
    required String question,
    required ChatIntent intent,
  }) async {
    final chat = _chat;
    if (chat == null) throw StateError('On-device model is not loaded.');
    await chat.addQueryChunk(Message.text(
      text: GroundingPrompt.forUngroundedQuestion(
        question: question,
        intent: intent,
        medicineName: intent.medicineQuery,
      ),
      isUser: true,
    ));
    final response = await chat.generateChatResponse();
    final text = response is TextResponse ? response.token.trim() : '';
    if (text.isEmpty) throw StateError('Empty on-device response.');
    return text;
  }

  Future<void> dispose() async {
    await _model?.close();
    _chat = null;
    _model = null;
  }
}
