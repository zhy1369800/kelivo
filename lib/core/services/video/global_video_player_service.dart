import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Global video player singleton service.
///
/// Controls the active in-app video playback session, supporting:
/// - Single-window enforcement (new video replaces old in-place without stacking modals)
/// - Asynchronous, non-blocking opening with in-flight lock protection
/// - Smooth transition between full preview modal and floating PiP player
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

  // Active modal updater callback for in-place source switching
  void Function(String source, String? title)? _modalSourceUpdater;

  // Getters
  String? get activeSource => _activeSource;
  String? get activeTitle => _activeTitle;
  bool get isPlaying => _isPlaying;
  bool get isPipActive => _isPipActive;
  bool get isFullPreviewOpen => _isFullPreviewOpen;
  double _playbackPositionSeconds = 0.0;

  /// Current playback position in seconds, preserved across modal and PiP transitions.
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

  /// Whether a full modal is actively mounted and receptive to in-place source updates.
  bool get hasActiveModal => _isFullPreviewOpen && _modalSourceUpdater != null;

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

  /// Register active full modal updater for in-place switching.
  void registerModalUpdater(void Function(String source, String? title)? updater) {
    _modalSourceUpdater = updater;
  }

  /// Set the active video source.
  ///
  /// If the full modal is currently open, updates it in-place (new replaces old).
  bool openVideo({
    required String source,
    String? title,
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

    // If modal is currently open, switch in-place
    if (_isFullPreviewOpen && _modalSourceUpdater != null) {
      _activeSource = trimmed;
      _activeTitle = title;
      _isPlaying = true;
      _isPipActive = false;
      notifyListeners();
      _modalSourceUpdater!(trimmed, title);
      return true;
    }

    _activeSource = trimmed;
    _activeTitle = title;
    _isPlaying = true;
    _isPipActive = false;
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

  /// Minimize full preview modal to floating PiP capsule.
  void minimizeToPip() {
    _isPipActive = true;
    _isFullPreviewOpen = false;
    notifyListeners();
  }

  /// Mark full preview modal as open.
  void markFullPreviewOpened() {
    _isFullPreviewOpen = true;
    _isPipActive = false;
    notifyListeners();
  }

  /// Mark full preview modal as dismissed.
  void markFullPreviewDismissed({bool keepPlayingAsPip = false}) {
    _isFullPreviewOpen = false;
    if (keepPlayingAsPip && _isPipActive && (_isPlaying || _activeSource != null)) {
      _isPipActive = true;
    } else if (!_isPipActive) {
      stop();
    }
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
    notifyListeners();
  }
}
