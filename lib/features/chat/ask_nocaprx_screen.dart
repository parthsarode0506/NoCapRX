import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import 'chat_service.dart';

class AskNocapRxScreen extends ConsumerStatefulWidget {
  final String? medicineName;
  const AskNocapRxScreen({super.key, this.medicineName});

  @override
  ConsumerState<AskNocapRxScreen> createState() => _AskNocapRxScreenState();
}

class _AskNocapRxScreenState extends ConsumerState<AskNocapRxScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  final _service = ChatService();
  final List<Map<String, String>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _messages.add({'role': 'assistant', 'text': widget.medicineName == null
        ? 'Ask me about a medicine in the local database.'
        : 'Ask me about ${widget.medicineName}.'});
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      await _service.load();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _service.dispose();
    _speech.stop();
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ready = await _speech.initialize();
    if (!ready) return;
    setState(() => _listening = true);
    await _speech.listen(onResult: (result) {
      _input.text = result.recognizedWords;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    });
  }

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add({'role': 'user', 'text': question});
      _sending = true;
    });
    final answer = await _service.answer(
      question: question,
      profile: ref.read(patientProfileProvider),
      contextMedicine: widget.medicineName,
    );
    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'assistant', 'text': '${answer.sourceLabel}\n\n${answer.text}'});
      _sending = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(title: Text('Ask NOCAPRx', style: GoogleFonts.inter(fontWeight: FontWeight.w700))),
      body: SafeArea(child: Column(children: [
        Container(
          width: double.infinity,
          color: AppTheme.mintSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const Text('🟢'), const SizedBox(width: 6),
            Expanded(child: Text(_loading ? 'On-device AI is loading...' : 'On-device AI', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.primaryDarkEmerald))),
            if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
        Expanded(child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          itemCount: _messages.length,
          itemBuilder: (_, index) {
            final message = _messages[index];
            final user = message['role'] == 'user';
            return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: user ? AppTheme.primaryEmerald : Colors.white, borderRadius: BorderRadius.circular(14), border: user ? null : Border.all(color: AppTheme.cardBorder)),
              child: Text(message['text']!, style: GoogleFonts.inter(color: user ? Colors.white : AppTheme.deepInk, height: 1.4)),
            ));
          },
        )),
        if (_sending) const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Thinking on this device...')),
        Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 12), child: Row(children: [
          IconButton(tooltip: 'Ask by voice', onPressed: _toggleListening, icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_none_rounded)),
          Expanded(child: TextField(controller: _input, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Ask about a medicine...', border: OutlineInputBorder()))),
          const SizedBox(width: 6),
          IconButton(tooltip: 'Send question', onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded, color: AppTheme.primaryEmerald)),
        ])),
      ])),
    );
  }
}
