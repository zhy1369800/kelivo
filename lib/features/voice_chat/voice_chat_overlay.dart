import 'package:flutter/material.dart';

import 'voice_chat_controller.dart';

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
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryAnim;
  late final AnimationController _rippleCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

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

    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim =
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

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
    _rippleCtrl.dispose();
    _pulseCtrl.dispose();
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

  String get _stateLabel {
    return switch (widget.controller.state) {
      VoiceChatState.idle => '准备就绪',
      VoiceChatState.listening => '正在聆听',
      VoiceChatState.processing => 'AI 思考中',
      VoiceChatState.aiSpeaking => 'AI 回复中',
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
                        label: _stateLabel,
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

                      const SizedBox(height: 24),

                      // ── 动效 Orb（点击打断） ──
                      _OrbSection(
                        controller: widget.controller,
                        rippleAnim: _rippleCtrl,
                        pulseAnim: _pulseAnim,
                        color: _stateColor,
                      ),

                      const SizedBox(height: 28),

                      // ── 底部操作区 ──
                      _BottomBar(onClose: _close),

                      const SizedBox(height: 24),
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
// 中央动效 Orb（点击可打断 TTS）
// ────────────────────────────────────────────
class _OrbSection extends StatefulWidget {
  const _OrbSection({
    required this.controller,
    required this.rippleAnim,
    required this.pulseAnim,
    required this.color,
  });

  final VoiceChatController controller;
  final Animation<double> rippleAnim;
  final Animation<double> pulseAnim;
  final Color color;

  @override
  State<_OrbSection> createState() => _OrbSectionState();
}

class _OrbSectionState extends State<_OrbSection> {
  bool _pressing = false;

  Future<void> _onTap() async {
    if (widget.controller.state == VoiceChatState.aiSpeaking) {
      await widget.controller.interruptTts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAiSpeaking =
        widget.controller.state == VoiceChatState.aiSpeaking;

    return Column(
      children: [
        // 提示文字：AI 说话中才显示点击提示
        AnimatedOpacity(
          opacity: isAiSpeaking ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Text(
            '点击打断',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Orb 本体
        GestureDetector(
          onTap: _onTap,
          onTapDown: (_) => setState(() => _pressing = true),
          onTapUp: (_) => setState(() => _pressing = false),
          onTapCancel: () => setState(() => _pressing = false),
          child: AnimatedScale(
            scale: _pressing ? 0.93 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: SizedBox(
              width: 180,
              height: 180,
              child: AnimatedBuilder(
                animation:
                    Listenable.merge([widget.rippleAnim, widget.pulseAnim]),
                builder: (_, __) {
                  final state = widget.controller.state;
                  final soundLevel =
                      widget.controller.soundLevel.clamp(0.0, 1.0);
                  final isActive = state == VoiceChatState.listening ||
                      state == VoiceChatState.aiSpeaking;

                  const baseR = 52.0;
                  final dynamicR = isActive
                      ? baseR +
                          soundLevel * 22 +
                          widget.pulseAnim.value * 10
                      : baseR;
                  final ripplePhase = widget.rippleAnim.value;

                  return CustomPaint(
                    painter: _OrbPainter(
                      color: widget.color,
                      baseRadius: dynamicR,
                      ripplePhase: ripplePhase,
                      isActive: isActive,
                      pulseValue: widget.pulseAnim.value,
                    ),
                    child: Center(
                      child: _OrbIcon(
                        state: state,
                        isAiSpeaking: isAiSpeaking,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrbIcon extends StatelessWidget {
  const _OrbIcon({required this.state, required this.isAiSpeaking});
  final VoiceChatState state;
  final bool isAiSpeaking;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      VoiceChatState.listening => Icons.mic_rounded,
      VoiceChatState.processing => Icons.auto_awesome_rounded,
      // AI 说话时改用 stop 图标提示可打断
      VoiceChatState.aiSpeaking => Icons.stop_rounded,
      VoiceChatState.idle => Icons.mic_none_rounded,
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Icon(icon, key: ValueKey(state), color: Colors.white, size: 34),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.color,
    required this.baseRadius,
    required this.ripplePhase,
    required this.isActive,
    required this.pulseValue,
  });

  final Color color;
  final double baseRadius;
  final double ripplePhase;
  final bool isActive;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 多层波纹
    if (isActive) {
      for (int i = 0; i < 3; i++) {
        final phase = (ripplePhase + i / 3) % 1.0;
        final ringRadius = baseRadius + phase * 44;
        final opacity = (1.0 - phase) * 0.2;
        canvas.drawCircle(
          center,
          ringRadius,
          Paint()
            ..color = color.withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // 外光晕
    final glowR = baseRadius + 16;
    canvas.drawCircle(
      center,
      glowR * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: isActive ? 0.20 + pulseValue * 0.08 : 0.06),
            color.withValues(alpha: 0),
          ],
        ).createShader(
            Rect.fromCircle(center: center, radius: glowR * 1.5)),
    );

    // 中间环
    canvas.drawCircle(
      center,
      baseRadius + 10,
      Paint()..color = color.withValues(alpha: isActive ? 0.14 : 0.05),
    );

    // 核心渐变圆
    canvas.drawCircle(
      center,
      baseRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [
            Color.lerp(Colors.white, color, 0.35)!,
            color,
            Color.lerp(color, Colors.black, 0.22)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: baseRadius)),
    );

    // 高光
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-baseRadius * 0.25, -baseRadius * 0.28),
        width: baseRadius * 0.65,
        height: baseRadius * 0.38,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.ripplePhase != ripplePhase ||
      old.baseRadius != baseRadius ||
      old.pulseValue != pulseValue ||
      old.isActive != isActive ||
      old.color != color;
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
