import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/asr_provider.dart';
import '../../core/providers/tts_provider.dart';
import 'voice_chat_controller.dart';

class VoiceChatOverlay extends StatefulWidget {
  const VoiceChatOverlay({
    super.key,
    required this.controller,
    this.onClose,
  });

  final VoiceChatController controller;
  final VoidCallback? onClose;

  @override
  State<VoiceChatOverlay> createState() => _VoiceChatOverlayState();
}

class _VoiceChatOverlayState extends State<VoiceChatOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _entryController;
  late Animation<double> _entryAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _entryAnim = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _entryController.reverse();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entryAnim,
      builder: (context, child) => FadeTransition(
        opacity: _entryAnim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(_entryAnim),
          child: child,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.88),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    // Drag handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // State label
                    _StateLabel(state: widget.controller.state),
                    const SizedBox(height: 40),
                    // Transcript / AI text
                    _ConversationDisplay(controller: widget.controller),
                    const SizedBox(height: 40),
                    // Waveform
                    _Waveform(
                      controller: widget.controller,
                      pulseAnim: _pulseController,
                    ),
                    const SizedBox(height: 48),
                    // Close button
                    GestureDetector(
                      onTap: _close,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.state});
  final VoiceChatState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      VoiceChatState.idle => ('准备中...', Colors.white54),
      VoiceChatState.listening => ('聆听中...', Colors.white70),
      VoiceChatState.processing => ('AI 思考中...', const Color(0xFF8AB4F8)),
      VoiceChatState.aiSpeaking => ('AI 回复中...', const Color(0xFF81C995)),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        label,
        key: ValueKey(state),
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ConversationDisplay extends StatelessWidget {
  const _ConversationDisplay({required this.controller});
  final VoiceChatController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // User's recognized text (while listening)
          if (controller.state == VoiceChatState.listening &&
              controller.transcript.isNotEmpty)
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                controller.transcript,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ),
          // Last user message
          if (controller.state != VoiceChatState.listening &&
              controller.lastUserText.isNotEmpty)
            Text(
              controller.lastUserText,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          if (controller.lastAiText.isNotEmpty &&
              controller.state == VoiceChatState.aiSpeaking) ...[
            const SizedBox(height: 12),
            Text(
              controller.lastAiText,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                height: 1.55,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.controller, required this.pulseAnim});
  final VoiceChatController controller;
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (context, _) {
        final level = controller.soundLevel;
        final isListening = controller.state == VoiceChatState.listening;
        final isAi = controller.state == VoiceChatState.aiSpeaking;

        final baseRadius = 48.0;
        final pulse = isListening
            ? baseRadius + level * 32 + pulseAnim.value * 8
            : isAi
                ? baseRadius + pulseAnim.value * 14
                : baseRadius;

        final color = isAi
            ? const Color(0xFF81C995)
            : isListening
                ? const Color(0xFF8AB4F8)
                : Colors.white30;

        return SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: pulse * 2,
                height: pulse * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.12),
                ),
              ),
              // Middle ring
              Container(
                width: (baseRadius + 16) * 2,
                height: (baseRadius + 16) * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.18),
                ),
              ),
              // Core circle
              Container(
                width: baseRadius * 2,
                height: baseRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.85),
                ),
                child: Icon(
                  isAi ? Icons.volume_up_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
