import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../voice_chat_controller.dart';

/// 3D 粒子点模型
class _SpherePoint {
  const _SpherePoint(this.x, this.y, this.z, this.u, this.v);
  final double x;
  final double y;
  final double z;
  final double u;
  final double v;
}

/// 粒子流体样式数据模型
class _OrbStyle {
  const _OrbStyle(this.primary, this.glow, this.speed, this.amp);

  final Color primary;
  final Color glow;
  final double speed;
  final double amp;

  static _OrbStyle lerp(_OrbStyle a, _OrbStyle b, double t) {
    return _OrbStyle(
      Color.lerp(a.primary, b.primary, t)!,
      Color.lerp(a.glow, b.glow, t)!,
      ui.lerpDouble(a.speed, b.speed, t)!,
      ui.lerpDouble(a.amp, b.amp, t)!,
    );
  }
}

/// 3D 粒子发光流体球组件 —— ChatGPT / Siri 风格
class ParticleFluidOrb extends StatefulWidget {
  const ParticleFluidOrb({
    super.key,
    required this.controller,
    this.size = 240,
    this.onTap,
  });

  final VoiceChatController controller;
  final double size;
  final VoidCallback? onTap;

  @override
  State<ParticleFluidOrb> createState() => _ParticleFluidOrbState();
}

class _ParticleFluidOrbState extends State<ParticleFluidOrb>
    with TickerProviderStateMixin {
  late final AnimationController _animController;
  late final AnimationController _transitionCtrl;
  late final Animation<double> _transitionAnim;
  late final List<_SpherePoint> _basePoints;

  VoiceChatState _previousState = VoiceChatState.idle;
  _OrbStyle _oldStyle = _resolveStyle(VoiceChatState.idle, 0);
  _OrbStyle _targetStyle = _resolveStyle(VoiceChatState.idle, 0);

  bool _pressing = false;
  static const int _pointCount = 480;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _transitionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _transitionAnim = CurvedAnimation(
      parent: _transitionCtrl,
      curve: Curves.easeOutCubic,
    );
    _transitionCtrl.value = 1.0; // 初始无需过渡

    _previousState = widget.controller.state;
    _targetStyle = _resolveStyle(_previousState, widget.controller.soundLevel);
    _oldStyle = _targetStyle;

    _basePoints = _generateFibonacciSphere(_pointCount);
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final newState = widget.controller.state;
    if (newState != _previousState) {
      _oldStyle = _OrbStyle.lerp(_oldStyle, _targetStyle, _transitionAnim.value);
      _targetStyle = _resolveStyle(newState, widget.controller.soundLevel);
      _previousState = newState;
      _transitionCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _animController.dispose();
    _transitionCtrl.dispose();
    super.dispose();
  }

  static _OrbStyle _resolveStyle(VoiceChatState state, double soundLevel) {
    switch (state) {
      case VoiceChatState.listening:
        return _OrbStyle(
          const Color(0xFF38BDF8),
          const Color(0xFF0284C7),
          1.2,
          1.1 + soundLevel * 1.2,
        );
      case VoiceChatState.processing:
        return const _OrbStyle(
          Color(0xFFA855F7),
          Color(0xFF7C3AED),
          2.0,
          0.85,
        );
      case VoiceChatState.aiSpeaking:
        return const _OrbStyle(
          Color(0xFF34D399),
          Color(0xFF059669),
          1.5,
          1.35,
        );
      case VoiceChatState.idle:
        return const _OrbStyle(
          Color(0xFF94A3B8),
          Color(0xFF64748B),
          0.5,
          0.45,
        );
    }
  }

  /// 使用斐波那契黄金螺旋算法在单位球面上生成均匀分布的点
  List<_SpherePoint> _generateFibonacciSphere(int samples) {
    final points = <_SpherePoint>[];
    final phi = (1.0 + math.sqrt(5.0)) / 2.0;

    for (int i = 0; i < samples; i++) {
      final y = 1.0 - (i / (samples - 1.0)) * 2.0;
      final radius = math.sqrt(math.max(0.0, 1.0 - y * y));

      final theta = 2.0 * math.pi * i / phi;
      final x = math.cos(theta) * radius;
      final z = math.sin(theta) * radius;

      final u = 0.5 + (math.atan2(z, x) / (2.0 * math.pi));
      final v = 0.5 - (math.asin(y) / math.pi);

      points.add(_SpherePoint(x, y, z, u, v));
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAiSpeaking = widget.controller.state == VoiceChatState.aiSpeaking;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部“点击打断”轻提示
        AnimatedOpacity(
          opacity: isAiSpeaking ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Text(
            l10n?.voiceChatClickToInterrupt ?? 'Tap to interrupt',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 3D 粒子球区域
        GestureDetector(
          onTap: () {
            if (isAiSpeaking) {
              widget.controller.interruptTts();
            }
            widget.onTap?.call();
          },
          onTapDown: (_) => setState(() => _pressing = true),
          onTapUp: (_) => setState(() => _pressing = false),
          onTapCancel: () => setState(() => _pressing = false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _pressing ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: AnimatedBuilder(
                animation: Listenable.merge([_animController, _transitionCtrl]),
                builder: (context, _) {
                  final activeTargetStyle = _resolveStyle(
                    widget.controller.state,
                    widget.controller.soundLevel,
                  );
                  final currentStyle = _OrbStyle.lerp(
                    _oldStyle,
                    activeTargetStyle,
                    _transitionAnim.value,
                  );

                  return CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: _ParticleFluidPainter(
                      points: _basePoints,
                      progress: _animController.value,
                      style: currentStyle,
                      state: widget.controller.state,
                      soundLevel: widget.controller.soundLevel,
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

/// 3D 粒子流体渲染画笔
class _ParticleFluidPainter extends CustomPainter {
  _ParticleFluidPainter({
    required this.points,
    required this.progress,
    required this.style,
    required this.state,
    required this.soundLevel,
  });

  final List<_SpherePoint> points;
  final double progress;
  final _OrbStyle style;
  final VoiceChatState state;
  final double soundLevel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.38;

    final primaryColor = style.primary;
    final glowColor = style.glow;
    final waveSpeed = style.speed;
    final waveAmp = style.amp;

    // 1. 绘制核心漫反射背景辉光
    final bgGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withValues(alpha: 0.28),
          glowColor.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: baseRadius * 1.35),
      );
    canvas.drawCircle(center, baseRadius * 1.35, bgGlowPaint);

    // 2. 计算 3D 旋转角度
    final time = progress * 2 * math.pi * waveSpeed;
    final rotY = time * 0.45;
    final rotX = math.sin(time * 0.3) * 0.28;

    final cosY = math.cos(rotY);
    final sinY = math.sin(rotY);
    final cosX = math.cos(rotX);
    final sinX = math.sin(rotX);

    // 3. 计算并投影所有 3D 粒子点
    final projectedPoints = <_ProjectedPoint>[];

    for (final pt in points) {
      // 3D 复合流体谐波形变
      final wave1 = math.sin(pt.x * 3.5 + pt.y * 2.8 + time * 1.2);
      final wave2 = math.cos(pt.z * 4.0 - pt.x * 2.2 + time * 1.6);
      final wave3 = math.sin((pt.x + pt.y + pt.z) * 3.0 + time * 2.0);

      // 音量爆发增益 (仅在 listening 时显著)
      final soundBoost = (state == VoiceChatState.listening)
          ? soundLevel.clamp(0.0, 1.0) * 0.55
          : 0.0;

      final displacement =
          1.0 + (wave1 * 0.10 + wave2 * 0.08 + wave3 * 0.06) * waveAmp + soundBoost;
      final currentRadius = baseRadius * displacement;

      final sx = pt.x * currentRadius;
      final sy = pt.y * currentRadius;
      final sz = pt.z * currentRadius;

      // 绕 Y 轴旋转
      final x1 = sx * cosY + sz * sinY;
      final y1 = sy;
      final z1 = -sx * sinY + sz * cosY;

      // 绕 X 轴旋转
      final x2 = x1;
      final y2 = y1 * cosX - z1 * sinX;
      final z2 = y1 * sinX + z1 * cosX;

      // 3D 透视投影 (Perspective Projection)
      final cameraDist = baseRadius * 3.2;
      final perspective = cameraDist / (cameraDist - z2);

      final screenX = center.dx + x2 * perspective;
      final screenY = center.dy + y2 * perspective;
      final depth = (z2 / baseRadius).clamp(-1.0, 1.0); // -1 (后) ~ 1 (前)

      projectedPoints.add(
        _ProjectedPoint(
          x: screenX,
          y: screenY,
          depth: depth,
        ),
      );
    }

    // 4. 按深度排序（从后往前绘制，保证前后遮挡与光影层次）
    projectedPoints.sort((a, b) => a.depth.compareTo(b.depth));

    // 5. 绘制所有粒子点
    final particlePaint = Paint()..style = PaintingStyle.fill;

    for (final p in projectedPoints) {
      // 深度越靠前：尺寸越大、更白更亮、透明度更高
      final normDepth = (p.depth + 1.0) / 2.0; // 0.0 ~ 1.0
      final dotRadius = 1.3 + normDepth * 2.2;
      final alpha = 0.25 + normDepth * 0.72;

      // 前景粒子偏白发光，后景粒子偏暗
      final dotColor = Color.lerp(
        glowColor.withValues(alpha: alpha * 0.7),
        Colors.white.withValues(alpha: alpha),
        normDepth * 0.85,
      )!;

      particlePaint.color = dotColor;
      canvas.drawCircle(Offset(p.x, p.y), dotRadius, particlePaint);

      // 前景大粒子增加微型光晕
      if (normDepth > 0.75) {
        final glowPaint = Paint()
          ..color = primaryColor.withValues(alpha: (normDepth - 0.75) * 0.4)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(p.x, p.y), dotRadius * 2.4, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleFluidPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.style != style ||
        oldDelegate.state != state ||
        oldDelegate.soundLevel != soundLevel;
  }
}

class _ProjectedPoint {
  const _ProjectedPoint({
    required this.x,
    required this.y,
    required this.depth,
  });
  final double x;
  final double y;
  final double depth;
}