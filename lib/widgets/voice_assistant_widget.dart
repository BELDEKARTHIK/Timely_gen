import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/voice_assistant_service.dart';
import '../utils/app_theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  VOICE ASSISTANT OVERLAY  — floats over every dashboard screen.
//  Android : full voice (mic + TTS via native Android APIs)
//  Windows : text-only mode (keyboard input, no mic button)
// ══════════════════════════════════════════════════════════════════════════════

class VoiceAssistantWrapper extends StatefulWidget {
  final Widget child;
  final void Function(int tabIndex)? onNavigate;

  const VoiceAssistantWrapper({
    super.key,
    required this.child,
    this.onNavigate,
  });

  @override
  State<VoiceAssistantWrapper> createState() => _VoiceAssistantWrapperState();
}

class _VoiceAssistantWrapperState extends State<VoiceAssistantWrapper>
    with SingleTickerProviderStateMixin {

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  bool _panelOpen = false;
  final _textCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _pulseAnim = Tween(begin: 1.0, end: 1.18)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VoiceAssistantService>().init();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  // Tap mic inside panel → toggle listen on/off
  void _onMicTap(VoiceAssistantService svc) {
    if (svc.isListening) {
      svc.stopListening();
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    } else {
      setState(() => _panelOpen = true);
      svc.startListening();
      _pulseCtrl.repeat(reverse: true);
    }
  }

  // Long-press FAB → hold to talk (release stops)
  void _onHoldStart(VoiceAssistantService svc) {
    setState(() => _panelOpen = true);
    if (!svc.isListening) {
      svc.startListening();
      _pulseCtrl.repeat(reverse: true);
    }
  }

  void _onHoldEnd(VoiceAssistantService svc) {
    if (svc.isListening) {
      svc.stopListening();
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  void _onSend(VoiceAssistantService svc) {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    svc.sendText(text);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceAssistantService>(
      builder: (ctx, svc, _) {
        // Handle pending navigation
        if (svc.pendingNav != null && widget.onNavigate != null) {
          final nav = svc.pendingNav!;
          svc.clearPendingNav();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (nav.tabIndex != null) widget.onNavigate!(nav.tabIndex!);
          });
        }

        if (!svc.isListening) {
          _pulseCtrl.stop();
          _pulseCtrl.reset();
        }

        return Stack(children: [
          widget.child,

          // ── Chat panel ────────────────────────────────────────────────────
          if (_panelOpen)
            Positioned(
              bottom: 110, right: 12, left: 12,
              child: _AssistantPanel(
                svc: svc,
                textCtrl: _textCtrl,
                onSend:  () => _onSend(svc),
                onMic:   () => _onMicTap(svc),
                onClose: () {
                  setState(() => _panelOpen = false);
                  svc.stopListening();
                  svc.stopSpeaking();
                },
              ),
            ),

          // ── Floating button + hold hint ───────────────────────────────────
          Positioned(
            bottom: 8, right: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (svc.voiceAvailable)
                  AnimatedOpacity(
                    opacity: svc.isListening ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.error.withOpacity(0.35))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 6, height: 6,
                          decoration: const BoxDecoration(
                            color: AppTheme.error, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('Listening… release to send',
                          style: TextStyle(color: AppTheme.error,
                            fontSize: 11, fontWeight: FontWeight.w600)),
                      ]))),
                if (!svc.isListening && !svc.voiceAvailable)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6, right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.25))),
                    child: const Text('AI Chat',
                      style: TextStyle(color: AppTheme.primaryLt,
                        fontSize: 11, fontWeight: FontWeight.w600))),
              AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: svc.isListening ? _pulseAnim.value : 1.0,
                child: child,
              ),
              child: svc.voiceAvailable
                // Android: tap = open panel, long-press = hold to talk
                ? GestureDetector(
                    onTap: () => setState(() => _panelOpen = !_panelOpen),
                    onLongPressStart: (_) => _onHoldStart(svc),
                    onLongPressEnd:   (_) => _onHoldEnd(svc),
                    child: _MicFab(
                      isListening:  svc.isListening,
                      isSpeaking:   svc.isSpeaking,
                      isProcessing: svc.isProcessing,
                    ),
                  )
                // Windows: plain chat bubble button
                : _ChatFab(onTap: () => setState(() => _panelOpen = !_panelOpen)),
            ),
          ),
        ]);
      },
    );
  }
}

// ── Android mic FAB ───────────────────────────────────────────────────────────
class _MicFab extends StatelessWidget {
  final bool isListening, isSpeaking, isProcessing;
  const _MicFab({
    required this.isListening, required this.isSpeaking,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final IconData icon;
    if (isListening)      { bg = AppTheme.error;     icon = Icons.mic_rounded; }
    else if (isSpeaking)  { bg = AppTheme.emerald;   icon = Icons.volume_up_rounded; }
    else if (isProcessing){ bg = AppTheme.secondary; icon = Icons.hourglass_top_rounded; }
    else                  { bg = AppTheme.primary;   icon = Icons.mic_none_rounded; }

    return Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: bg, shape: BoxShape.circle,
          boxShadow: [BoxShadow(
            color: bg.withOpacity(0.45),
            blurRadius: 16, offset: const Offset(0, 4))]),
        child: isProcessing
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Icon(icon, color: Colors.white, size: 24),
    );
  }
}

// ── Windows chat FAB ──────────────────────────────────────────────────────────
class _ChatFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ChatFab({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        gradient: AppTheme.purpleGradient, shape: BoxShape.circle,
        boxShadow: [BoxShadow(
          color: AppTheme.primary.withOpacity(0.45),
          blurRadius: 16, offset: const Offset(0, 4))]),
      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
    ),
  );
}

// ── Chat panel ────────────────────────────────────────────────────────────────
class _AssistantPanel extends StatefulWidget {
  final VoiceAssistantService svc;
  final TextEditingController textCtrl;
  final VoidCallback onSend, onMic, onClose;
  const _AssistantPanel({
    required this.svc, required this.textCtrl,
    required this.onSend, required this.onMic, required this.onClose,
  });
  @override
  State<_AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<_AssistantPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset>   _slideAnim;
  late Animation<double>   _fadeAnim;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _slideAnim = Tween<Offset>(
        begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_AssistantPanel old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.svc;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          height: 340,
          decoration: BoxDecoration(
            color: AppTheme.sidebar,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 24, offset: const Offset(0, 8))]),
          child: Column(children: [
            // Header
            _PanelHeader(svc: svc, onClose: widget.onClose),

            // Live transcript (Android only)
            if (svc.isListening && svc.liveText.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.error.withOpacity(0.25))),
                child: Row(children: [
                  Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.error, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(svc.liveText,
                    style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12.5,
                      fontStyle: FontStyle.italic))),
                ])),

            // Messages
            Expanded(child: svc.messages.isEmpty
              ? _EmptyState(voiceAvailable: svc.voiceAvailable)
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  itemCount: svc.messages.length,
                  itemBuilder: (_, i) => _Bubble(msg: svc.messages[i]))),

            // Thinking indicator
            if (svc.isProcessing)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primaryLt)),
                  const SizedBox(width: 8),
                  const Text('Thinking…',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5)),
                ])),

            // Input bar
            _InputBar(
              textCtrl: widget.textCtrl,
              svc: svc,
              onSend: widget.onSend,
              onMic: widget.onMic,
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _PanelHeader extends StatelessWidget {
  final VoiceAssistantService svc;
  final VoidCallback onClose;
  const _PanelHeader({required this.svc, required this.onClose});

  @override
  Widget build(BuildContext context) {
    String status = svc.voiceAvailable ? 'AI Voice Assistant' : 'AI Chat Assistant';
    Color  sc     = AppTheme.primaryLt;
    if (svc.isListening)  { status = 'Listening…';  sc = AppTheme.error; }
    if (svc.isSpeaking)   { status = 'Speaking…';   sc = AppTheme.emerald; }
    if (svc.isProcessing) { status = 'Thinking…';   sc = AppTheme.secondary; }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(children: [
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: sc, shape: BoxShape.circle)),
        const SizedBox(width: 9),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(status,
            style: const TextStyle(color: AppTheme.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w700)),
          Text(svc.voiceAvailable ? 'Tap mic or type' : 'Type your question',
            style: TextStyle(color: sc, fontSize: 10.5)),
        ]),
        const Spacer(),
        // Clear
        _HeaderBtn(icon: Icons.delete_outline_rounded, onTap: svc.clearHistory),
        const SizedBox(width: 6),
        // Stop speaking (Android)
        if (svc.isSpeaking) ...[
          _HeaderBtn(
            icon: Icons.stop_rounded, color: AppTheme.emerald,
            onTap: svc.stopSpeaking),
          const SizedBox(width: 6),
        ],
        // Close
        _HeaderBtn(icon: Icons.close_rounded, onTap: onClose),
      ]),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;
  const _HeaderBtn({required this.icon, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: color != null ? color!.withOpacity(0.15) : AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: color != null ? color!.withOpacity(0.3) : AppTheme.border)),
      child: Icon(icon, color: color ?? AppTheme.textMuted, size: 14)));
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool voiceAvailable;
  const _EmptyState({required this.voiceAvailable});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(width: 48, height: 48,
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.10), shape: BoxShape.circle),
        child: Icon(
          voiceAvailable ? Icons.mic_none_rounded : Icons.chat_bubble_outline_rounded,
          color: AppTheme.primaryLt, size: 24)),
      const SizedBox(height: 10),
      Text(
        voiceAvailable ? 'Tap the mic and speak' : 'Type your question below',
        style: const TextStyle(color: AppTheme.textPrimary,
          fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('"Who teaches AI today?"',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 11,
          fontStyle: FontStyle.italic)),
      const Text('"What is my attendance in Maths?"',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 11,
          fontStyle: FontStyle.italic)),
      const Text('"Open timetable"',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 11,
          fontStyle: FontStyle.italic)),
    ],
  );
}

// ── Message bubble ────────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final AssistantMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(width: 26, height: 26,
              decoration: BoxDecoration(
                gradient: AppTheme.purpleGradient, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 12)),
            const SizedBox(width: 6),
          ],
          Flexible(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isUser
                  ? AppTheme.primary.withOpacity(0.18)
                  : AppTheme.cardAlt,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(14),
                topRight:    const Radius.circular(14),
                bottomLeft:  Radius.circular(isUser ? 14 : 3),
                bottomRight: Radius.circular(isUser ? 3 : 14)),
              border: Border.all(
                color: isUser
                    ? AppTheme.primary.withOpacity(0.25)
                    : AppTheme.border)),
            child: Text(msg.text,
              style: TextStyle(
                color: isUser
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
                fontSize: 12.5, height: 1.4)),
          )),
          if (isUser) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController textCtrl;
  final VoiceAssistantService svc;
  final VoidCallback onSend, onMic;
  const _InputBar({
    required this.textCtrl, required this.svc,
    required this.onSend, required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border))),
      child: Row(children: [
        // Mic button — Android only
        if (svc.voiceAvailable) ...[
          GestureDetector(
            onTap: onMic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: svc.isListening
                    ? AppTheme.error.withOpacity(0.15)
                    : AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: svc.isListening
                      ? AppTheme.error.withOpacity(0.4)
                      : AppTheme.border)),
              child: Icon(
                svc.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: svc.isListening ? AppTheme.error : AppTheme.textSecondary,
                size: 17))),
          const SizedBox(width: 8),
        ],
        // Text field
        Expanded(child: TextField(
          controller: textCtrl,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
          decoration: InputDecoration(
            hintText: svc.voiceAvailable
                ? 'Type or speak a question…'
                : 'Type your question here…',
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9)),
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSend(),
        )),
        const SizedBox(width: 8),
        // Send button
        GestureDetector(
          onTap: onSend,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: AppTheme.purpleGradient,
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 16))),
      ]),
    );
  }
}
