import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pgx_report.dart';
import '../models/chat_message.dart';
import '../services/llm_service.dart';
import '../services/firebase_service.dart';

class ChatbotScreen extends ConsumerStatefulWidget {
  final PgxMultiReport report;

  const ChatbotScreen({super.key, required this.report});

  @override
  ConsumerState<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends ConsumerState<ChatbotScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _localMessages = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _addInitialGreeting();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addInitialGreeting() {
    final testedDrugs = widget.report.drugReports.map((d) => d.drug).join(', ');
    _localMessages.add(
      ChatMessage(
        id: 'msg_welcome',
        role: 'assistant',
        text: 'Hello! I am PharmaGuard AI. I am strictly grounded to your Pharmacogenomic Report #${widget.report.reportId} covering [$testedDrugs]. How can I help clarify your results today?',
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    _inputController.clear();

    final userMessage = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      text: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _localMessages.add(userMessage);
      _isSending = true;
    });

    _scrollToBottom();

    // Persist user message to Firestore
    await FirebaseService.saveChatMessage(widget.report.reportId, userMessage);

    try {
      // Call grounded Chatbot API (or offline fallback)
      final botReplyText = await LlmService.askReportChatbot(
        userQuery: text,
        report: widget.report,
      );

      final assistantMessage = ChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch + 1}',
        role: 'assistant',
        text: botReplyText,
        timestamp: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _localMessages.add(assistantMessage);
        });
        _scrollToBottom();
      }

      // Persist assistant message to Firestore
      await FirebaseService.saveChatMessage(widget.report.reportId, assistantMessage);
    } catch (e) {
      if (mounted) {
        setState(() {
          _localMessages.add(ChatMessage(
            id: 'msg_err',
            role: 'assistant',
            text: 'I am currently operating in offline mode. For your evaluated drugs (${widget.report.drugReports.map((r) => r.drug).join(', ')}), all predictions are strictly derived from CPIC rules. Please consult your physician.',
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Report AI Assistant', style: TextStyle(fontSize: 16)),
            Text(
              'Grounded strictly to Report #${widget.report.reportId}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Out of scope disclaimer banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: const Text(
                '🔒 Grounded Context: AI will only answer questions regarding drugs tested in this report.',
                style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),

            // Message List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _localMessages.length,
                itemBuilder: (context, index) {
                  final msg = _localMessages[index];
                  final isUser = msg.role == 'user';

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isUser ? theme.colorScheme.primary : Colors.grey.shade200,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                      ),
                      child: Text(
                        msg.text,
                        style: TextStyle(
                          color: isUser ? Colors.white : Colors.black87,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (_isSending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('PharmaGuard AI is thinking...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),

            // Input Bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Ask about your report results...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
