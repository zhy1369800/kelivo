import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/models/chat_input_data.dart';
import '../../core/providers/asr_provider.dart';
import '../../core/providers/tts_provider.dart';
import '../../core/services/asr/asr_service_options.dart';
import '../../core/services/tts/tts_playback_models.dart';
import 'services/live_activity_service.dart';
import 'utils/voice_text_sanitizer.dart';

enum VoiceChatState { idle, listening, processing, aiSpeaking }

/// Controller that orchestrates the continuous voice chat loop, iOS Live Activity,
/// full-duplex background keepalive, and customizable idle timeout / barge-in.
class VoiceChatController extends ChangeNotifier with WidgetsBindingObserver {
  VoiceChatController({
    required this.asrProvider,
    required this.ttsProvider,
    required this.sendMessage,
    this.assistantName = 'AI 助手',
    this.avatarPath,
    this.preferredAsrService,
    this.silenceThreshold = 0.04,
    this.silenceDuration = const Duration(milliseconds: 1500),
    this.enableBargeIn = true,
    this.idleTimeout = const Duration(seconds: 30),
    this.bargeInThreshold = 0.35,
    this.bargeInDuration = const Duration(milliseconds: 250),
  }) {
    WidgetsBinding.instance.addObserver(this);
    final initialLifecycle = WidgetsBinding.instance.lifecycleState;
    _isInBackground = initialLifecycle != null &&
        initialLifecycle != AppLifecycleState.resumed;

    VoiceChatLiveActivityService.instance.onStopRequested = () {
      if (!_disposed && isActive) {
        stop();
      }
    };
  }

  final AsrProvider asrProvider;
  final TtsProvider ttsProvider;
  final Future<void> Function(ChatInputData) sendMessage;
  final String assistantName;
  final String? avatarPath;
  final AsrServiceOptions? preferredAsrService;
  final double silenceThreshold;
  final Duration silenceDuration;
  final bool enableBargeIn;
  final Duration idleTimeout;
  final double bargeInThreshold;
  final Duration bargeInDuration;

  VoiceChatState _state = VoiceChatState.idle;
  String _transcript = '';
  String _lastUserText = '';
  String _lastAiText = '';
  String? _error;
  bool _disposed = false;
  bool _stopping = false;
  bool _isInBackground = false;

  Timer? _silenceTimer;
  Timer? _idleTimer;
  Timer? _bargeInTimer;
  DateTime? _ttsStartTime;
  VoidCallback? _asrListener;
  VoidCallback? _ttsListener;

  VoiceChatState get state => _state;
  String get transcript => _transcript;
  String get lastUserText => _lastUserText;
  String get lastAiText => _lastAiText;
  String? get error => _error;
  bool get isActive => _state != VoiceChatState.idle;
  double get soundLevel => asrProvider.soundLevel;
  bool get isInBackground => _isInBackground;

  String get stateLabel {
    return switch (_state) {
      VoiceChatState.idle => '准备就绪',
      VoiceChatState.listening => '在听呢...',
      VoiceChatState.processing => 'AI 思考中...',
      VoiceChatState.aiSpeaking => 'AI 回复中...',
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    final inBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden;

    if (inBackground != _isInBackground) {
      _isInBackground = inBackground;
      if (_isInBackground) {
        // 进入后台：取消前台静音超时定时器（后台永不超时断开，对标 Gemini）
        _idleTimer?.cancel();
        _idleTimer = null;
        // 若处于活跃会话且麦克风未激活，立即确保拉起麦克风保持后台活跃（麦克风小黄灯常亮）
        if (isActive && !asrProvider.isActive && !_stopping) {
          final service = _resolveAsrService();
          asrProvider.start(service).catchError((_) {});
        }
      } else {
        // 回到前台：如果处于聆听状态且配置了超时，重新启动静音超时计时
        if (_state == VoiceChatState.listening) {
          _resetIdleTimer();
        }
      }
    }
  }

  Future<void> start() async {
    if (_state != VoiceChatState.idle) return;
    _error = null;
    ttsProvider.suppressFloatingPlayer = true;
    await VoiceChatLiveActivityService.instance.start(
      assistantName: assistantName,
      avatarPath: avatarPath,
    );
    await _startListening();
  }

  Future<void> stop() async {
    _stopping = true;
    ttsProvider.suppressFloatingPlayer = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _bargeInTimer?.cancel();
    _bargeInTimer = null;
    _removeAsrListener();
    _removeTtsListener();
    if (asrProvider.isActive) await asrProvider.cancel();
    ttsProvider.stop();
    _state = VoiceChatState.idle;
    _transcript = '';
    await VoiceChatLiveActivityService.instance.stop();
    _stopping = false;
    if (!_disposed) notifyListeners();
  }

  void updateStreamingText(String text) {
    if (_disposed || _state != VoiceChatState.processing) return;
    final cleanText = VoiceTextSanitizer.clean(text);
    if (cleanText.isNotEmpty && cleanText != _lastAiText) {
      _lastAiText = cleanText;
      _syncLiveActivity();
      notifyListeners();
    }
  }

  void onAiReplyComplete(String text) {
    if (_disposed || _state != VoiceChatState.processing) return;
    final cleanText = VoiceTextSanitizer.clean(text);
    _lastAiText = cleanText.isNotEmpty ? cleanText : text;
    _state = VoiceChatState.aiSpeaking;
    _idleTimer?.cancel();
    _idleTimer = null;
    _syncLiveActivity();
    notifyListeners();
    _startTts(_lastAiText);
  }

  /// 打断 TTS 并立刻重新开始聆听（支持手动点击打断与 Voice Barge-in 声控打断）
  Future<void> interruptTts() async {
    if (_disposed || _state != VoiceChatState.aiSpeaking) return;
    _removeTtsListener();
    _stopBargeInListener();
    _removeAsrListener();
    ttsProvider.stop();
    await _startListening();
  }

  /// 手动点击唤醒或重启拾音（用于点击 3D 粒子球时强制重置并拉起麦克风）
  Future<void> manualWakeupOrRestart() async {
    if (_disposed || _stopping) return;
    _error = null;

    // 如果正在播报中，停止 TTS
    if (_state == VoiceChatState.aiSpeaking) {
      _removeTtsListener();
      _stopBargeInListener();
      ttsProvider.stop();
    }

    // 重启拾音，强制重启 ASR 会话拉起麦克风
    await _startListening(forceRestartAsr: true);
  }

  Future<void> _startListening({bool forceRestartAsr = false}) async {
    if (_disposed || _stopping) return;
    _transcript = '';
    _state = VoiceChatState.listening;
    _resetIdleTimer();
    _syncLiveActivity();
    notifyListeners();

    final service = _resolveAsrService();
    try {
      if (forceRestartAsr && asrProvider.isActive) {
        await asrProvider.cancel();
      }
      if (!asrProvider.isActive) {
        await asrProvider.start(service);
      } else {
        asrProvider.resetTranscript();
      }
    } catch (e) {
      _error = e.toString();
      _state = VoiceChatState.idle;
      _syncLiveActivity();
      if (!_disposed) notifyListeners();
      return;
    }

    _removeAsrListener();
    void listener() => _onAsrChanged();
    _asrListener = listener;
    asrProvider.addListener(listener);
  }

  void _onAsrChanged() {
    if (_disposed || _state != VoiceChatState.listening) return;
    final t = asrProvider.transcript;
    if (t != _transcript) {
      _transcript = t;
      _resetIdleTimer();
      _syncLiveActivity();
      notifyListeners();
    }
    final level = asrProvider.soundLevel;
    if (level > silenceThreshold) {
      _resetIdleTimer();
      _silenceTimer?.cancel();
      _silenceTimer = null;
    } else if (_transcript.trim().isNotEmpty && _silenceTimer == null) {
      _silenceTimer = Timer(silenceDuration, _onSilenceDetected);
    }
    if (!asrProvider.isActive &&
        _state == VoiceChatState.listening &&
        _transcript.trim().isEmpty) {
      _removeAsrListener();
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!_disposed && _state == VoiceChatState.listening) {
          _startListening();
        }
      });
    }
  }

  Future<void> _onSilenceDetected() async {
    _silenceTimer = null;
    if (_disposed || _state != VoiceChatState.listening) return;
    final text = _transcript.trim();
    if (text.isEmpty) {
      _resetIdleTimer();
      return;
    }
    _removeAsrListener();
    _idleTimer?.cancel();
    _idleTimer = null;

    _lastUserText = text;
    _lastAiText = '';
    _state = VoiceChatState.processing;
    _transcript = '';
    _syncLiveActivity();
    notifyListeners();

    if (!_isInBackground) {
      // 前台模式：正常关闭麦克风，等待回复
      try {
        await asrProvider.finish().catchError((_) => text);
      } catch (_) {}
    } else {
      // 后台模式：绝不关闭麦克风，麦克风小黄灯持续常亮，保活进程不被系统挂起
      asrProvider.resetTranscript();
      if (!asrProvider.isActive && !_stopping) {
        final service = _resolveAsrService();
        asrProvider.start(service).catchError((_) {});
      }
    }

    try {
      await sendMessage(
        ChatInputData(
          text: _lastUserText,
          disableReasoning: true,
          isVoiceMode: true,
        ),
      );
    } catch (e) {
      _error = e.toString();
      await _startListening();
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    // 只有在【前台】且【配置了超时大于0】时，才开启前台超时休眠定时器（后台永不超时）
    if (!_isInBackground && _state == VoiceChatState.listening && idleTimeout > Duration.zero) {
      _idleTimer = Timer(idleTimeout, _onIdleTimeout);
    }
  }

  Future<void> _onIdleTimeout() async {
    if (_disposed || _state != VoiceChatState.listening || _isInBackground) return;
    _idleTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _removeAsrListener();
    if (asrProvider.isActive) {
      await asrProvider.cancel();
    }
    _state = VoiceChatState.idle;
    _syncLiveActivity();
    if (!_disposed) notifyListeners();
  }

  void _startTts(String text) async {
    _removeTtsListener();
    _ttsStartTime = DateTime.now();

    final clean = text.trim();
    if (clean.isEmpty) {
      _finishSpeakingAndListen();
      return;
    }

    // ★ 先立即触发 TTS 播报，确保后台时播报不被 await 阻塞
    ttsProvider.speak(clean);
    void listener() => _onTtsChanged();
    _ttsListener = listener;
    ttsProvider.addListener(listener);

    // 再异步处理麦克风：
    // 后台模式下强制全双工常开（小黄灯常亮保活并支持打断），前台模式下若未开启打断则关闭麦克风
    if (!enableBargeIn && !_isInBackground) {
      _stopBargeInListener();
      _removeAsrListener();
      if (asrProvider.isActive) {
        await asrProvider.cancel();
      }
    } else {
      if (!asrProvider.isActive) {
        final service = _resolveAsrService();
        asrProvider.start(service).catchError((_) {});
      }
      _startBargeInDetector();
    }
  }

  void _startBargeInDetector() {
    _stopBargeInListener();
    _removeAsrListener();

    void bargeInListener() => _onBargeInSoundChanged();
    _asrListener = bargeInListener;
    asrProvider.addListener(bargeInListener);
  }

  void _onBargeInSoundChanged() {
    if (_disposed || _state != VoiceChatState.aiSpeaking) return;

    // 1. 声学滤波器收敛免扰期（前 600ms 内不触发打断，防止扬声器启动瞬态冲击）
    final startTime = _ttsStartTime;
    if (startTime != null &&
        DateTime.now().difference(startTime) < const Duration(milliseconds: 600)) {
      return;
    }

    // 2. 自适应近场人声突刺阈值（防回音保底 0.55，并兼容用户调高的自定义配置）
    final level = asrProvider.soundLevel;
    final effectiveThreshold = math.max(bargeInThreshold, 0.55);
    final effectiveDuration = bargeInDuration > const Duration(milliseconds: 300)
        ? bargeInDuration
        : const Duration(milliseconds: 300);

    if (level > effectiveThreshold) {
      _bargeInTimer ??= Timer(effectiveDuration, () {
        if (!_disposed && _state == VoiceChatState.aiSpeaking) {
          interruptTts();
        }
      });
    } else {
      _bargeInTimer?.cancel();
      _bargeInTimer = null;
    }
  }

  void _onTtsChanged() {
    if (_disposed || _state != VoiceChatState.aiSpeaking) return;

    final status = ttsProvider.playbackState.status;

    // 1. 明确终结状态（播放完毕 ended 或错误 error）立即切回拾音，绝不拦截！彻底杜绝短回复死锁
    if (status == TtsPlaybackStatus.ended || status == TtsPlaybackStatus.error) {
      _finishSpeakingAndListen();
      return;
    }

    // 2. 针对非终结的中间状态抖动（如初始空态或未就绪态），在刚调用的前 400ms 内忽略
    final startTime = _ttsStartTime;
    if (startTime != null &&
        DateTime.now().difference(startTime) < const Duration(milliseconds: 400)) {
      return;
    }

    // 3. 兜底判定：如果 TTS 已不再发声且不在播放/缓冲/暂停中，切回拾音
    if (!ttsProvider.isSpeaking &&
        !ttsProvider.isPaused &&
        status != TtsPlaybackStatus.buffering &&
        status != TtsPlaybackStatus.playing) {
      _finishSpeakingAndListen();
    }
  }

  Future<void> _finishSpeakingAndListen() async {
    _removeTtsListener();
    _stopBargeInListener();
    _removeAsrListener();
    if (_disposed || _stopping || _state != VoiceChatState.aiSpeaking) return;

    if (!_isInBackground) {
      // 前台模式：
      // 1. 彻底清空可能在播报期间残留在 ASR 缓冲区的脏数据
      if (asrProvider.isActive) {
        await asrProvider.cancel();
      }
      if (_disposed || _stopping) return;

      // 2. 给硬件扬声器 200ms 回声物理消退期，防止扬声器刚停瞬间的残响被拾音
      await Future.delayed(const Duration(milliseconds: 200));
      if (!_disposed && !_stopping && _state == VoiceChatState.aiSpeaking) {
        await _startListening(forceRestartAsr: true);
      }
    } else {
      // 后台模式：
      // 绝不调用 cancel() 导致麦克风小黄灯熄灭，给硬件扬声器 120ms 缓冲后无缝切回拾音
      asrProvider.resetTranscript();
      await Future.delayed(const Duration(milliseconds: 120));
      if (!_disposed && !_stopping && _state == VoiceChatState.aiSpeaking) {
        await _startListening(forceRestartAsr: false);
      }
    }
  }

  void _stopBargeInListener() {
    _bargeInTimer?.cancel();
    _bargeInTimer = null;
  }

  void _syncLiveActivity() {
    if (_disposed) return;
    final stateString = switch (_state) {
      VoiceChatState.listening => 'listening',
      VoiceChatState.processing => 'processing',
      VoiceChatState.aiSpeaking => 'aiSpeaking',
      VoiceChatState.idle => 'idle',
    };

    final currentTranscript = switch (_state) {
      VoiceChatState.listening => _transcript,
      VoiceChatState.processing => _lastUserText,
      VoiceChatState.aiSpeaking => _lastAiText,
      VoiceChatState.idle => '',
    };

    VoiceChatLiveActivityService.instance.update(
      state: stateString,
      stateLabel: stateLabel,
      transcript: currentTranscript,
      assistantName: assistantName,
      waveLevel: soundLevel,
      isFinished: _state == VoiceChatState.idle,
    );
  }

  AsrServiceOptions _resolveAsrService() {
    final preferred = preferredAsrService;
    if (preferred != null &&
        preferred.isConfigured &&
        asrProvider.canUse(preferred)) {
      return preferred;
    }
    return SystemAsrOptions();
  }

  void _removeAsrListener() {
    final l = _asrListener;
    if (l != null) {
      asrProvider.removeListener(l);
      _asrListener = null;
    }
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _removeTtsListener() {
    final l = _ttsListener;
    if (l != null) {
      ttsProvider.removeListener(l);
      _ttsListener = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    ttsProvider.suppressFloatingPlayer = false;
    _silenceTimer?.cancel();
    _idleTimer?.cancel();
    _bargeInTimer?.cancel();
    _removeAsrListener();
    _removeTtsListener();
    VoiceChatLiveActivityService.instance.onStopRequested = null;
    super.dispose();
  }
}
