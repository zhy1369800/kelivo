import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/chat_input_data.dart';
import '../../core/providers/asr_provider.dart';
import '../../core/providers/tts_provider.dart';
import '../../core/services/asr/asr_service_options.dart';
import '../../core/services/tts/tts_playback_models.dart';
import 'services/live_activity_service.dart';
import 'utils/voice_text_sanitizer.dart';

enum VoiceChatState { idle, listening, processing, aiSpeaking }

/// Controller that orchestrates the continuous voice chat loop, iOS Live Activity,
/// low-power voice barge-in, and auto-idle timeout.
class VoiceChatController extends ChangeNotifier {
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

  Timer? _silenceTimer;
  Timer? _idleTimer;
  Timer? _bargeInTimer;
  VoidCallback? _asrListener;
  VoidCallback? _ttsListener;

  VoiceChatState get state => _state;
  String get transcript => _transcript;
  String get lastUserText => _lastUserText;
  String get lastAiText => _lastAiText;
  String? get error => _error;
  bool get isActive => _state != VoiceChatState.idle;
  double get soundLevel => asrProvider.soundLevel;

  String get stateLabel {
    return switch (_state) {
      VoiceChatState.idle => '准备就绪',
      VoiceChatState.listening => '在听呢...',
      VoiceChatState.processing => 'AI 思考中...',
      VoiceChatState.aiSpeaking => 'AI 回复中...',
    };
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

  Future<void> _startListening() async {
    if (_disposed) return;
    _transcript = '';
    _state = VoiceChatState.listening;
    _resetIdleTimer();
    _syncLiveActivity();
    notifyListeners();

    final service = _resolveAsrService();
    try {
      if (!asrProvider.isActive) {
        await asrProvider.start(service);
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
      await asrProvider.cancel();
      _removeAsrListener();
      await _startListening();
      return;
    }
    _removeAsrListener();
    _idleTimer?.cancel();
    _idleTimer = null;
    try {
      final finalText = (await asrProvider.finish()).trim();
      _lastUserText = finalText.isNotEmpty ? finalText : text;
    } catch (_) {
      _lastUserText = text;
    }
    _state = VoiceChatState.processing;
    _transcript = '';
    _syncLiveActivity();
    notifyListeners();
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
    if (_state == VoiceChatState.listening && idleTimeout > Duration.zero) {
      _idleTimer = Timer(idleTimeout, _onIdleTimeout);
    }
  }

  Future<void> _onIdleTimeout() async {
    if (_disposed || _state != VoiceChatState.listening) return;
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

  void _startTts(String text) {
    _removeTtsListener();
    ttsProvider.speak(text);
    void listener() => _onTtsChanged();
    _ttsListener = listener;
    ttsProvider.addListener(listener);

    if (enableBargeIn) {
      _startBargeInDetector();
    }
  }

  void _startBargeInDetector() {
    _stopBargeInListener();
    _removeAsrListener();

    if (!asrProvider.isActive) {
      final service = _resolveAsrService();
      asrProvider.start(service).catchError((_) {});
    }

    void bargeInListener() => _onBargeInSoundChanged();
    _asrListener = bargeInListener;
    asrProvider.addListener(bargeInListener);
  }

  void _onBargeInSoundChanged() {
    if (_disposed || _state != VoiceChatState.aiSpeaking) return;
    final level = asrProvider.soundLevel;
    if (level > bargeInThreshold) {
      _bargeInTimer ??= Timer(bargeInDuration, () {
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
    if (status == TtsPlaybackStatus.ended ||
        (!ttsProvider.isSpeaking && !ttsProvider.isPaused &&
            status != TtsPlaybackStatus.buffering &&
            status != TtsPlaybackStatus.playing)) {
      _removeTtsListener();
      _stopBargeInListener();
      _removeAsrListener();
      if (!_disposed && _state == VoiceChatState.aiSpeaking) {
        _startListening();
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
