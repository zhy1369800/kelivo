import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Global video player singleton service.
///
/// Controls the active in-app video playback session, supporting:
/// - Single persistent player core with seamless viewport tweening (PiP <-> Fullscreen)
/// - Asynchronous, non-blocking opening with in-flight lock protection
/// - Smooth transition between fullscreen preview and floating PiP player
class GlobalVideoPlayerService extends ChangeNotifier {
  GlobalVideoPlayerService._();
  static final GlobalVideoPlayerService instance = GlobalVideoPlayerService._();
  factory GlobalVideoPlayerService() => instance;

  String? _activeSource;
  String? _activeTitle;
  bool _isPlaying = false;
  bool _isPipActive = false;
  bool _isFullPreviewOpen = false;

  // In-flight debounce lock to prevent duplicate opens on rapid double taps
  DateTime? _lastOpenTime;

  // Getters
  String? get activeSource => _activeSource;
  String? get activeTitle => _activeTitle;
  bool get isPlaying => _isPlaying;
  bool get isPipActive => _isPipActive;
  bool get isFullPreviewOpen => _isFullPreviewOpen;
  double _playbackPositionSeconds = 0.0;

  /// Current playback position in seconds, preserved across fullscreen and PiP transitions.
  double get playbackPositionSeconds => _playbackPositionSeconds;

  /// Updates current playback position in seconds.
  void updatePlaybackPosition(double seconds) {
    if (seconds >= 0) {
      _playbackPositionSeconds = seconds;
    }
  }

  static const double defaultAspectRatio = 16 / 9;
  double _aspectRatio = defaultAspectRatio;

  /// Video display aspect ratio (width / height), defaults to 16:9.
  double get aspectRatio => _aspectRatio;

  /// Updates the detected aspect ratio if valid.
  void updateAspectRatio(double ratio) {
    if (ratio >= 0.2 && ratio <= 5.0 && (_aspectRatio - ratio).abs() > 0.01) {
      _aspectRatio = ratio;
      notifyListeners();
    }
  }

  String get displayName {
    if (_activeTitle != null && _activeTitle!.trim().isNotEmpty) {
      return _activeTitle!.trim();
    }
    if (_activeSource == null || _activeSource!.isEmpty) {
      return '视频播放';
    }
    final clean = _activeSource!.split('?').first.split('#').first;
    return p.basename(clean);
  }

  bool _canExpand = true;

  /// Whether the floating player is allowed to be expanded into fullscreen preview.
  bool get canExpand => _canExpand;

  /// Set the active video source.
  ///
  /// If [asPip] is true, launches directly into floating PiP mode.
  /// Otherwise, launches into immersive fullscreen preview mode.
  bool openVideo({
    required String source,
    String? title,
    bool asPip = false,
    bool canExpand = true,
  }) {
    final now = DateTime.now();
    // 400ms debounce
    if (_lastOpenTime != null &&
        now.difference(_lastOpenTime!).inMilliseconds < 400 &&
        _activeSource == source) {
      return false; // Debounced duplicate request
    }
    _lastOpenTime = now;

    final trimmed = source.trim();
    if (trimmed.isEmpty) return false;

    final isNewSource = _activeSource != trimmed;
    if (isNewSource) {
      _playbackPositionSeconds = 0.0;
      _aspectRatio = defaultAspectRatio;
    }

    _canExpand = canExpand;

    if (asPip) {
      _activeSource = trimmed;
      _activeTitle = title;
      _isPlaying = true;
      _isPipActive = true;
      _isFullPreviewOpen = false;
      notifyListeners();
      return true;
    }

    _activeSource = trimmed;
    _activeTitle = title;
    _isPlaying = true;
    _isPipActive = false;
    _isFullPreviewOpen = true;
    notifyListeners();
    return true;
  }

  /// Update playback playing state (called by video view controllers).
  void setPlaying(bool playing) {
    if (_isPlaying != playing) {
      _isPlaying = playing;
      notifyListeners();
    }
  }

  /// Toggle play / pause.
  void togglePlayPause() {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  /// Minimize fullscreen preview to floating PiP capsule.
  void minimizeToPip() {
    _isPipActive = true;
    _isFullPreviewOpen = false;
    notifyListeners();
  }

  /// Expand floating PiP player to full screen preview.
  void expandToFullscreen() {
    _isFullPreviewOpen = true;
    _isPipActive = false;
    notifyListeners();
  }

  /// Fully stop video playback, dismiss PiP capsule and reset state.
  void stop() {
    _isPlaying = false;
    _isPipActive = false;
    _isFullPreviewOpen = false;
    _activeSource = null;
    _activeTitle = null;
    _playbackPositionSeconds = 0.0;
    _aspectRatio = defaultAspectRatio;
    _canExpand = true;
    notifyListeners();
  }
}
