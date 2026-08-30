import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 灵动岛 (Dynamic Island) 与实时活动 (Live Activity) 桥接服务
class VoiceChatLiveActivityService {
  static final VoiceChatLiveActivityService instance =
      VoiceChatLiveActivityService._();
  VoiceChatLiveActivityService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'app.voice_chat_live_activity',
  );

  VoidCallback? onStopRequested;

  Timer? _throttleTimer;
  Map<String, dynamic>? _pendingUpdate;
  String _lastState = '';

  bool get isSupportedPlatform => Platform.isIOS;

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onStopFromLiveActivity':
        onStopRequested?.call();
        break;
      default:
        break;
    }
  }

  /// 开启实时活动
  Future<void> start({
    required String assistantName,
    String? avatarPath,
    String? sessionId,
  }) async {
    if (!isSupportedPlatform) return;
    try {
      _lastState = 'listening';
      _pendingUpdate = null;
      _throttleTimer?.cancel();
      _throttleTimer = null;

      await _channel.invokeMethod('start', {
        'sessionId': sessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'assistantName': assistantName,
        'avatarPath': avatarPath,
      });
    } catch (e) {
      debugPrint('[LiveActivityService] start failed: $e');
    }
  }

  /// 更新实时活动（内置 300ms 智能防抖与状态直通）
  void update({
    required String state,
    required String stateLabel,
    required String transcript,
    required String assistantName,
    required double waveLevel,
    bool isFinished = false,
  }) {
    if (!isSupportedPlatform) return;

    final updateData = {
      'state': state,
      'stateLabel': stateLabel,
      'transcript': transcript,
      'assistantName': assistantName,
      'waveLevel': waveLevel.clamp(0.0, 1.0),
      'isFinished': isFinished,
    };

    // 如果状态发生流转（如 listening -> processing -> aiSpeaking），立即直通无延迟发送
    if (state != _lastState || isFinished) {
      _lastState = state;
      _throttleTimer?.cancel();
      _throttleTimer = null;
      _pendingUpdate = null;
      _invokeUpdate(updateData);
      return;
    }

    // 同一状态下的文本或波形更新进行 300ms 节流
    _pendingUpdate = updateData;
    _throttleTimer ??= Timer(const Duration(milliseconds: 300), () {
      _throttleTimer = null;
      final pending = _pendingUpdate;
      if (pending != null) {
        _pendingUpdate = null;
        _invokeUpdate(pending);
      }
    });
  }

  Future<void> _invokeUpdate(Map<String, dynamic> data) async {
    try {
      await _channel.invokeMethod('update', data);
    } catch (e) {
      debugPrint('[LiveActivityService] update failed: $e');
    }
  }

  /// 停止并销毁实时活动
  Future<void> stop() async {
    if (!isSupportedPlatform) return;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _pendingUpdate = null;
    _lastState = '';

    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('[LiveActivityService] stop failed: $e');
    }
  }
}
