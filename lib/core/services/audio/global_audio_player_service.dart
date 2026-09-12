import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../preview/resource_preview_service.dart';

/// Global audio player singleton service.
///
/// Owns the active audio playback instance across the entire application,
/// supporting speed switching, background/in-chat persistence, PiP capsule mode,
/// and full sheet previews.
class GlobalAudioPlayerService extends ChangeNotifier {
  GlobalAudioPlayerService._() {
    _initPlayer();
  }

  static final GlobalAudioPlayerService instance =
      GlobalAudioPlayerService._();
  factory GlobalAudioPlayerService() => instance;

  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  String? _activeSource;
  String? _activeTitle;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackRate = 1.0;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _hasError = false;

  /// Whether the floating mini-capsule (PiP) is currently active in the UI.
  bool _isPipActive = false;

  /// Whether the full card preview sheet is open.
  bool _isFullPreviewOpen = false;

  // Getters
  String? get activeSource => _activeSource;
  String get displayName {
    if (_activeTitle != null && _activeTitle!.trim().isNotEmpty) {
      return _activeTitle!.trim();
    }
    if (_activeSource == null || _activeSource!.isEmpty) {
      return '音频播放';
    }
    final clean = _activeSource!.split('?').first.split('#').first;
    return p.basename(clean);
  }

  String get fileFormatLabel {
    if (_activeSource == null || _activeSource!.isEmpty) return 'Audio';
    final clean = _activeSource!.split('?').first.split('#').first;
    final ext = p.extension(clean).replaceFirst('.', '').toUpperCase();
    return ext.isNotEmpty ? '$ext Audio' : 'Audio';
  }

  bool get isPlaying => _playerState == PlayerState.playing;
  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  bool get isPipActive => _isPipActive;
  bool get isFullPreviewOpen => _isFullPreviewOpen;
  Duration get duration => _duration;
  Duration get position => _position;
  double get playbackRate => _playbackRate;

  /// Whether playback has finished or reached the very end.
  bool get isAtEnd =>
      _playerState == PlayerState.completed ||
      (_duration > Duration.zero &&
          _position >= _duration - const Duration(milliseconds: 500));

  static const List<double> supportedRates = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  static final AudioContext mediaAudioContext = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {
        AVAudioSessionOptions.mixWithOthers,
      },
    ),
    android: const AudioContextAndroid(
      isSpeakerphoneOn: true,
      stayAwake: true,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
    ),
  );

  void _initPlayer() {
    _player = AudioPlayer();
    _player.setAudioContext(mediaAudioContext).catchError((_) {});

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      _playerState = state;
      if (state == PlayerState.playing || state == PlayerState.paused) {
        _isLoading = false;
      }
      if (state == PlayerState.completed) {
        _position = _duration;
      }
      notifyListeners();
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });

    _posSub = _player.onPositionChanged.listen((pos) {
      if (_playerState != PlayerState.completed) {
        _position = pos;
        notifyListeners();
      }
    });
  }

  /// Start playing an audio file or web URL.
  Future<void> play(String source, {String? title}) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return;

    if (_activeSource == trimmed && _isLoaded) {
      if (!isPlaying) {
        if (isAtEnd) {
          await seek(Duration.zero);
        }
        try {
          await _player.setAudioContext(mediaAudioContext);
        } catch (_) {}
        await _player.resume();
      }
      return;
    }

    _isLoading = true;
    _hasError = false;
    _activeSource = trimmed;
    _activeTitle = title;
    _isLoaded = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playbackRate = 1.0;
    notifyListeners();

    try {
      try {
        await _player.setAudioContext(mediaAudioContext);
      } catch (_) {}

      final isWeb =
          trimmed.startsWith('http://') || trimmed.startsWith('https://');
      if (isWeb) {
        await _player.setSource(UrlSource(trimmed));
      } else {
        final resolved = await ResourcePreviewService.resolvePath(trimmed);
        final file = File(resolved);
        if (!file.existsSync()) {
          _isLoading = false;
          _hasError = true;
          notifyListeners();
          return;
        }
        await _player.setSource(DeviceFileSource(file.path));
      }

      await _player.setPlaybackRate(_playbackRate);
      await _player.resume();
      _isLoaded = true;
      _isLoading = false;
      _hasError = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[GlobalAudioPlayerService] Play error: $e');
      _isLoading = false;
      _hasError = true;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (isPlaying) {
      await _player.pause();
    }
  }

  Future<void> resume() async {
    if (!isPlaying && _isLoaded) {
      if (isAtEnd) {
        await seek(Duration.zero);
      }
      try {
        await _player.setAudioContext(mediaAudioContext);
      } catch (_) {}
      await _player.resume();
    }
  }

  Future<void> togglePlayPause() async {
    if (!_isLoaded && !_isLoading) {
      if (_activeSource != null) {
        await play(_activeSource!, title: _activeTitle);
      }
      return;
    }
    if (isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seek(Duration position) async {
    _position = position;
    notifyListeners();
    await _player.seek(position);
  }

  Future<void> skip(Duration delta) async {
    final targetMs = (_position + delta).inMilliseconds;
    final maxMs = _duration.inMilliseconds;
    final clamped = targetMs.clamp(0, maxMs > 0 ? maxMs : 0);
    await seek(Duration(milliseconds: clamped));
  }

  Future<void> setPlaybackRate(double rate) async {
    if (!supportedRates.contains(rate)) return;
    _playbackRate = rate;
    notifyListeners();
    try {
      await _player.setPlaybackRate(rate);
    } catch (_) {}
  }

  /// Minimize active player to in-chat floating PiP capsule.
  void minimizeToPip() {
    _isPipActive = true;
    _isFullPreviewOpen = false;
    notifyListeners();
  }

  /// Mark full card preview as opened.
  void markFullPreviewOpened() {
    _isFullPreviewOpen = true;
    _isPipActive = false;
    notifyListeners();
  }

  /// Mark full card preview as dismissed/closed.
  void markFullPreviewDismissed({bool keepPlayingAsPip = true}) {
    _isFullPreviewOpen = false;
    if (keepPlayingAsPip &&
        (_isLoaded || _isLoading || isPlaying || _activeSource != null)) {
      _isPipActive = true;
    }
    notifyListeners();
  }

  /// Fully stop playback, dismiss capsule, and reset state.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _playerState = PlayerState.stopped;
    _isLoaded = false;
    _isLoading = false;
    _hasError = false;
    _isPipActive = false;
    _isFullPreviewOpen = false;
    _activeSource = null;
    _activeTitle = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
