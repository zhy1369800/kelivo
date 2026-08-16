import 'dart:math' as math;

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
  // 入场动画
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryAnim;

  // 呼吸 / 波纹循环动画
  late final AnimationController _rippleCtrl;

  // 内圆脉冲
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _entryAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _entryCtrl.forward();

    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _rippleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _entryCtrl.reverse();
    widget.onClose?.call();
  }

  // 状态色
  Color get _stateColor {
    return switch (widget.controller.state) {
      VoiceChatState.listening => const Color(0xFF60A5FA), // blue-400
      VoiceChatState.processing => const Color(0xFFA78BFA), // violet-400
      VoiceChatState.aiSpeaking => const Color(0xFF34D399), // emerald-400
      VoiceChatState.idle => const Color(0xFF94A3B8), // slate-400
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
                  Color(0xFF0A0F1E), // 深海蓝黑
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

                      // ── 字幕区（中间弹性区） ──
                      Expanded(
                        child: _SubtitleArea(controller: widget.controller),
                      ),

                      // ── 动效圆 + 波纹 ──
                      _OrbSection(
                        controller: widget.controller,
                        rippleAnim: _rippleCtrl,
                        pulseAnim: _pulseAnim,
                        color: _stateColor,
                      ),

                      const SizedBox(height: 32),

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
          // 状态指示点 + 文字
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
          // 关闭按钮 - 右上角
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
              child: Icon(
                Icons.close_rounded,
                color: Colors.white.withOpacity(0.7),
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
          color: widget.color.withOpacity(0.5 + _a.value * 0.5),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.4 * _a.value),
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
// 字幕区
// ────────────────────────────────────────────
class _SubtitleArea extends StatelessWidget {
  const _SubtitleArea({required this.controller});
  final VoiceChatController controller;

  @override
  Widget build(BuildContext context) {
    final isListening = controller.state == VoiceChatState.listening;
    final isAi = controller.state == VoiceChatState.aiSpeaking;

    final showTranscript = isListening && controller.transcript.isNotEmpty;
    final showUserLast =
        !isListening && controller.lastUserText.isNotEmpty;
    final showAiText =
        (isAi || controller.state == VoiceChatState.processing) &&
            controller.lastAiText.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 用户说话实时识别
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

          if (showAiText) ...[
            const SizedBox(height: 20),
            _buildAiText(controller.lastAiText),
          ],
        ],
      ),
    );
  }

  Widget _buildUserText(String text, {required bool live}) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      style: TextStyle(
        color: live ? Colors.white : Colors.white.withOpacity(0.35),
        fontSize: live ? 22 : 15,
        fontWeight: live ? FontWeight.w500 : FontWeight.w400,
        height: 1.55,
        letterSpacing: live ? 0.2 : 0.1,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildAiText(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.65,
        letterSpacing: 0.15,
      ),
    );
  }
}

// ────────────────────────────────────────────
// 中央动效 Orb + 波纹
// ────────────────────────────────────────────
class _OrbSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: Listenable.merge([rippleAnim, pulseAnim]),
        builder: (_, __) {
          final state = controller.state;
          final soundLevel = controller.soundLevel.clamp(0.0, 1.0);
          final isActive =
              state == VoiceChatState.listening || state == VoiceChatState.aiSpeaking;

          // 波纹半径随声音动态变化
          final baseR = 52.0;
          final dynamicR = isActive ? baseR + soundLevel * 24 + pulseAnim.value * 10 : baseR;
          final ripplePhase = rippleAnim.value; // 0..1

          return CustomPaint(
            painter: _OrbPainter(
              color: color,
              baseRadius: dynamicR,
              ripplePhase: ripplePhase,
              isActive: isActive,
              state: state,
              soundLevel: soundLevel,
              pulseValue: pulseAnim.value,
            ),
            child: Center(
              child: _OrbIcon(state: state, color: color),
            ),
          );
        },
      ),
    );
  }
}

class _OrbIcon extends StatelessWidget {
  const _OrbIcon({required this.state, required this.color});
  final VoiceChatState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      VoiceChatState.listening => Icons.mic_rounded,
      VoiceChatState.processing => Icons.auto_awesome_rounded,
      VoiceChatState.aiSpeaking => Icons.volume_up_rounded,
      VoiceChatState.idle => Icons.mic_none_rounded,
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
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
    required this.state,
    required this.soundLevel,
    required this.pulseValue,
  });

  final Color color;
  final double baseRadius;
  final double ripplePhase;
  final bool isActive;
  final VoiceChatState state;
  final double soundLevel;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // ── 多层波纹圆环 ──
    if (isActive) {
      for (int i = 0; i < 3; i++) {
        final phase = (ripplePhase + i / 3) % 1.0;
        final ringRadius = baseRadius + phase * 50;
        final opacity = (1.0 - phase) * 0.22;
        final paint = Paint()
          ..color = color.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(center, ringRadius, paint);
      }
    }

    // ── 外光晕 ──
    final glowR = baseRadius + 18;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(isActive ? 0.22 + pulseValue * 0.1 : 0.08),
          color.withOpacity(0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: glowR * 1.6));
    canvas.drawCircle(center, glowR * 1.6, glowPaint);

    // ── 中间过渡环 ──
    final midPaint = Paint()
      ..color = color.withOpacity(isActive ? 0.15 : 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius + 10, midPaint);

    // ── 核心圆 ──
    final corePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          Color.lerp(Colors.white, color, 0.4)!,
          color,
          Color.lerp(color, Colors.black, 0.25)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius));
    canvas.drawCircle(center, baseRadius, corePaint);

    // ── 高光 ──
    final hlPaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-baseRadius * 0.25, -baseRadius * 0.3),
        width: baseRadius * 0.7,
        height: baseRadius * 0.4,
      ),
      hlPaint,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 结束通话按钮 —— 红色圆形
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF87171).withOpacity(0.15),
                border: Border.all(
                  color: const Color(0xFFF87171).withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.call_end_rounded,
                color: Color(0xFFF87171),
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
