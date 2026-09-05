import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/pgx_report.dart';
import '../models/chat_message.dart';
import '../services/llm_service.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';

class ChatbotScreen extends ConsumerStatefulWidget {
  final PgxMultiReport? report;

  const ChatbotScreen({super.key, this.report});

  @override
  ConsumerState<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends ConsumerState<ChatbotScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _localMessages = [];
  bool _isSending = false;

  PgxMultiReport get _report => widget.report ?? PgxMultiReport(
        reportId: 'none',
        patientId: 'unavailable',
        vcfFilename: 'unavailable',
        timestamp: DateTime.now().toIso8601String(),
        drugReports: const [],
      );

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
    final testedDrugs = _report.drugReports.map((d) => d.drug).join(', ');
    _localMessages.add(
      ChatMessage(
        id: 'msg_welcome',
        role: 'assistant',
        text:
            'Hello! I am OnCapRX AI. I explain verified OnCapRX results only. ${testedDrugs.isEmpty ? 'Run a medicine analysis first, then I can explain it.' : 'Your report covers: $testedDrugs.'}',
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

    await FirebaseService.saveChatMessage(_report.reportId, userMessage);

    try {
      final botReplyText = _report.drugReports.isEmpty
          ? 'Please run Check a Medicine first. I can explain a verified medication result after the deterministic analysis is complete.'
          : await LlmService.askReportChatbot(userQuery: text, report: _report);

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

      await FirebaseService.saveChatMessage(
        _report.reportId,
        assistantMessage,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _localMessages.add(ChatMessage(
            id: 'msg_err',
            role: 'assistant',
            text:
                'AI explanation is currently unavailable. Your medication safety result is still available. Please consult your doctor or pharmacist for medication decisions.',
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
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OnCapRX AI Assistant',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.deepInk,
              ),
            ),
            Text(
              'Explanation layer for verified OnCapRX results',
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.secondaryInk),
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
              color: AppTheme.mintSurface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 13, color: AppTheme.primaryEmerald),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'AI explains verified results only. It does not decide medication safety.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.primaryDarkEmerald,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            // Message List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                itemCount: _localMessages.length,
                itemBuilder: (context, index) {
                  final msg = _localMessages[index];
                  final isUser = msg.role == 'user';

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.80,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isUser ? AppTheme.primaryEmerald : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                        border: isUser
                            ? null
                            : Border.all(color: AppTheme.cardBorder, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        msg.text,
                        style: GoogleFonts.inter(
                          color: isUser ? Colors.white : AppTheme.deepInk,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (_isSending)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryEmerald,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'OnCapRX AI is explaining...',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.secondaryInk,
                      ),
                    ),
                  ],
                ),
              ),

            // Input Bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(
                  top: BorderSide(color: AppTheme.cardBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      style: GoogleFonts.inter(fontSize: 14, color: AppTheme.deepInk),
                      decoration: InputDecoration(
                        hintText: 'Ask about your report results...',
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primaryEmerald,
                      foregroundColor: Colors.white,
                    ),
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
