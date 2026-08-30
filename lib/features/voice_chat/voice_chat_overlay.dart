import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'voice_chat_controller.dart';
import 'widgets/particle_fluid_orb.dart';

/// 全屏沉浸式语音聊天 Overlay —— Gemini Live 风格
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryAnim;

  // 滚动控制器（AI 文本区）
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _entryAnim =
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _entryCtrl.forward();

    // 当 AI 文字更新时，自动滚回顶部（最新回复从顶开始读）
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // 每次 AI 开始说话都把滚动位置重置到顶部
    if (widget.controller.state == VoiceChatState.aiSpeaking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _entryCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _entryCtrl.reverse();
    widget.onClose?.call();
  }

  Color get _stateColor {
    return switch (widget.controller.state) {
      VoiceChatState.listening => const Color(0xFF60A5FA),
      VoiceChatState.processing => const Color(0xFFA78BFA),
      VoiceChatState.aiSpeaking => const Color(0xFF34D399),
      VoiceChatState.idle => const Color(0xFF94A3B8),
    };
  }

  String _getStateLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (widget.controller.state) {
      VoiceChatState.idle => l10n?.voiceChatStateIdle ?? 'Ready',
      VoiceChatState.listening => l10n?.voiceChatStateListening ?? 'Listening...',
      VoiceChatState.processing => l10n?.voiceChatStateProcessing ?? 'Thinking...',
      VoiceChatState.aiSpeaking => l10n?.voiceChatStateAiSpeaking ?? 'Speaking...',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryAnim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(_entryAnim),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A0F1E),
                  Color(0xFF0D1117),
                  Color(0xFF0A0F1E),
                ],
              ),
            ),
            child: SafeArea(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  return Column(
                    children: [
                      // ── 顶部状态栏 ──
                      _TopBar(
                        label: _getStateLabel(context),
                        color: _stateColor,
                        onClose: _close,
                      ),
                      const SizedBox(height: 12),

                      // ── 字幕区（可滚动，Expanded 占据剩余空间） ──
                      Expanded(
                        child: _SubtitleArea(
                          controller: widget.controller,
                          scrollCtrl: _scrollCtrl,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── 3D 粒子发光流体球（点击可打断） ──
                      ParticleFluidOrb(
                        controller: widget.controller,
                        size: 230,
                      ),

                      const SizedBox(height: 24),

                      // ── 底部操作区 ──
                      _BottomBar(onClose: _close),

                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 顶部状态栏
// ────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.label,
    required this.color,
    required this.onClose,
  });

  final String label;
  final Color color;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Row(
              key: ValueKey(label),
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              child: Icon(
                Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────
// 闪烁小圆点
// ────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.5 + _a.value * 0.5),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.4 * _a.value),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 字幕区（可滚动）
// ────────────────────────────────────────────
class _SubtitleArea extends StatelessWidget {
  const _SubtitleArea({
    required this.controller,
    required this.scrollCtrl,
  });

  final VoiceChatController controller;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    final isListening = controller.state == VoiceChatState.listening;
    final isAi = controller.state == VoiceChatState.aiSpeaking;
    final isProcessing = controller.state == VoiceChatState.processing;

    final showTranscript = isListening && controller.transcript.isNotEmpty;
    final showUserLast = !isListening && controller.lastUserText.isNotEmpty;
    final showAiText =
        (isAi || isProcessing) && controller.lastAiText.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 用户文字区（固定，不滚动）
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: showTranscript
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _buildUserText(controller.transcript, live: true),
            secondChild: showUserLast
                ? _buildUserText(controller.lastUserText, live: false)
                : const SizedBox.shrink(),
          ),

          if (showAiText) const SizedBox(height: 16),

          // AI 文字区：可滚动，占据剩余空间
          if (showAiText)
            Expanded(
              child: _buildScrollableAiText(controller.lastAiText),
            )
          else
            const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _buildUserText(String text, {required bool live}) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      style: TextStyle(
        color: live ? Colors.white : Colors.white.withValues(alpha: 0.35),
        fontSize: live ? 17 : 13,
        fontWeight: live ? FontWeight.w500 : FontWeight.w400,
        height: 1.55,
        letterSpacing: live ? 0.2 : 0.1,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildScrollableAiText(String text) {
    return SingleChildScrollView(
      controller: scrollCtrl,
      physics: const BouncingScrollPhysics(),
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: const TextStyle(
          color: Color(0xFFCDD9E5),
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.7,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 底部操作栏
// ────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFF87171).withValues(alpha: 0.15),
          border: Border.all(
            color: const Color(0xFFF87171).withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.call_end_rounded,
          color: Color(0xFFF87171),
          size: 28,
        ),
      ),
    );
  }
}
