import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/services/preview/resource_preview_service.dart';
import '../../core/services/video/global_video_player_service.dart';
import '../../icons/lucide_adapter.dart';
import 'snackbar.dart';

/// In-app video preview card sheet with full playback controls,
/// share sheet, and direct minimization to floating PiP player.
class VideoPreviewModal extends StatefulWidget {
  const VideoPreviewModal({
    super.key,
    required this.source,
    this.title,
  });

  final String source;
  final String? title;

  /// Shows the video preview sheet.
  ///
  /// If the modal is already open, updates the source in-place (single-window).
  static Future<void> show(
    BuildContext? context, {
    required String source,
    String? title,
  }) async {
    final video = GlobalVideoPlayerService.instance;
    // If the modal is already open and mounted, update in-place
    if (video.hasActiveModal) {
      video.openVideo(source: source, title: title);
      return;
    }

    // Resolve an active NavigatorState reliably
    NavigatorState? navigator;
    if (context != null && context.mounted) {
      navigator = Navigator.maybeOf(context, rootNavigator: true) ??
          Navigator.maybeOf(context);
    }
    navigator ??= rootNavigatorKey.currentState;

    if (navigator == null || !navigator.mounted) {
      video.stop();
      return;
    }

    video.openVideo(source: source, title: title);
    video.markFullPreviewOpened();

    try {
      final route = PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, anim, secAnim) =>
            VideoPreviewModal(source: source, title: title),
        transitionsBuilder: (ctx, animation, secAnim, child) {
          const curve = Curves.easeOutCubic;
          final tween = Tween<Offset>(
            begin: const Offset(0.0, 0.06),
            end: Offset.zero,
          ).chain(CurveTween(curve: curve));
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(tween),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      );
      await navigator.push(route);
    } catch (e) {
      debugPrint('Error showing VideoPreviewModal: $e');
    } finally {
      video.markFullPreviewDismissed(keepPlayingAsPip: false);
    }
  }

  @override
  State<VideoPreviewModal> createState() => _VideoPreviewModalState();
}

class _VideoPreviewModalState extends State<VideoPreviewModal> {
  final GlobalVideoPlayerService _video = GlobalVideoPlayerService.instance;

  late WebViewController _webCtrl;
  String _currentSource = '';
  bool _isWebReady = false;

  bool _showControls = true;
  Timer? _hideControlsTimer;
  double _currentPosition = 0.0;
  double _duration = 0.0;
  bool _isDraggingSlider = false;

  @override
  void initState() {
    super.initState();
    _currentSource = widget.source;
    _currentPosition = _video.playbackPositionSeconds;

    _initWebViewController();
    _video.registerModalUpdater(_updateSourceInPlace);
    _resetHideControlsTimer();
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showControls && !_isDraggingSlider) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _seekBy(int seconds) {
    _resetHideControlsTimer();
    try {
      _webCtrl.runJavaScript(
        'if (window.__kelivoSeek) { window.__kelivoSeek($seconds); }',
      );
    } catch (_) {}
  }

  void _seekTo(double pos) {
    _resetHideControlsTimer();
    try {
      _webCtrl.runJavaScript(
        'if (window.__kelivoSeekTo) { window.__kelivoSeekTo($pos); }',
      );
    } catch (_) {}
  }

  void _togglePlayPause() {
    _resetHideControlsTimer();
    try {
      _webCtrl.runJavaScript(
        'if (window.__kelivoTogglePlay) { window.__kelivoTogglePlay(); }',
      );
    } catch (_) {}
  }

  String _formatTime(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return '00:00';
    final s = seconds.toInt();
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  void _cleanupWebPlayer() {
    try {
      _webCtrl.runJavaScript(
        'const v = document.getElementById("kelivo_player"); if (v) { v.pause(); v.src = ""; v.load(); }',
      );
      _webCtrl.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _video.registerModalUpdater(null);
    _cleanupWebPlayer();
    super.dispose();
  }

  void _updateSourceInPlace(String newSource, String? newTitle) {
    if (!mounted) return;
    setState(() {
      _currentSource = newSource;
    });
    _loadVideoInWeb(newSource);
  }

  String _buildVideoHtml(
    String videoSrc, {
    bool isRelative = false,
    double initialSeconds = 0.0,
  }) {
    final isNetwork =
        videoSrc.startsWith('http://') || videoSrc.startsWith('https://');
    final String srcAttr;
    if (isNetwork) {
      srcAttr = htmlEscape.convert(videoSrc);
    } else if (isRelative) {
      srcAttr = Uri.encodeComponent(p.basename(videoSrc));
    } else {
      srcAttr = 'file://${htmlEscape.convert(videoSrc)}';
    }

    final startSec =
        initialSeconds > 0 ? initialSeconds.toStringAsFixed(2) : '0';
    final fragment = initialSeconds > 0 ? '#t=${initialSeconds.toStringAsFixed(2)}' : '';
    final fullSrc = '$srcAttr$fragment';

    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body {
      width: 100%; height: 100%;
      background: #000; overflow: hidden;
      display: flex; align-items: center; justify-content: center;
    }
    video {
      width: 100%; height: 100%; object-fit: contain; background: #000;
    }
  </style>
</head>
<body>
  <video id="kelivo_player" src="$fullSrc" autoplay playsinline webkit-playsinline disablePictureInPicture preload="auto"></video>
  <script>
    (function() {
      const v = document.getElementById('kelivo_player');
      const startPos = $startSec;

      window.__kelivoSeek = function(delta) {
        if (!v) return;
        try {
          const maxDur = v.duration || 999999;
          v.currentTime = Math.max(0, Math.min(maxDur, v.currentTime + delta));
        } catch(e) {}
      };

      window.__kelivoSeekTo = function(pos) {
        if (!v) return;
        try {
          v.currentTime = pos;
        } catch(e) {}
      };

      window.__kelivoTogglePlay = function() {
        if (!v) return;
        try {
          if (v.paused) {
            const p = v.play();
            if (p && p.catch) { p.catch(function() {}); }
          } else {
            v.pause();
          }
        } catch(e) {}
      };

      v.addEventListener('loadeddata', () => {
        if (window.KelivoVideoChannel) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({ type: 'ready' }));
        }
      });

      v.addEventListener('loadedmetadata', () => {
        try {
          if (startPos > 0 && Math.abs(v.currentTime - startPos) > 1.0) {
            v.currentTime = startPos;
          }
        } catch(e) {}
        if (window.KelivoVideoChannel && v.videoWidth && v.videoHeight) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({
            type: 'metadata',
            videoWidth: v.videoWidth,
            videoHeight: v.videoHeight,
            duration: v.duration || 0,
            aspectRatio: v.videoWidth / v.videoHeight
          }));
        }
      });
      v.addEventListener('timeupdate', () => {
        if (window.KelivoVideoChannel) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({
            type: 'timeupdate',
            currentTime: v.currentTime,
            duration: v.duration || 0
          }));
        }
      });
      v.addEventListener('play', () => {
        if (window.KelivoVideoChannel) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({ type: 'play' }));
        }
      });
      v.addEventListener('pause', () => {
        if (window.KelivoVideoChannel) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({ type: 'pause' }));
        }
      });
    })();
  </script>
</body>
</html>''';
  }

  void _initWebViewController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _webCtrl = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'KelivoVideoChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (data['type'] == 'ready') {
              if (mounted) setState(() => _isWebReady = true);
            } else if (data['type'] == 'timeupdate') {
              final pos = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
              final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
              _video.updatePlaybackPosition(pos);
              if (mounted && !_isDraggingSlider) {
                setState(() {
                  _currentPosition = pos;
                  if (dur > 0) _duration = dur;
                  _isWebReady = true;
                });
              }
            } else if (data['type'] == 'metadata') {
              final ratio = (data['aspectRatio'] as num?)?.toDouble();
              final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
              if (ratio != null) {
                _video.updateAspectRatio(ratio);
              }
              if (mounted && dur > 0) {
                setState(() => _duration = dur);
              }
            } else if (data['type'] == 'play') {
              _video.setPlaying(true);
            } else if (data['type'] == 'pause') {
              _video.setPlaying(false);
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isWebReady = true);
            }
          },
        ),
      );

    _loadVideoInWeb(_currentSource);
  }

  Future<void> _loadVideoInWeb(String src) async {
    final startSeconds = _video.playbackPositionSeconds;
    final isNetwork = src.startsWith('http://') || src.startsWith('https://');
    if (isNetwork) {
      final html = _buildVideoHtml(src, initialSeconds: startSeconds);
      await _webCtrl.loadHtmlString(html);
    } else {
      final resolved = await ResourcePreviewService.resolvePath(src);
      final file = File(resolved);
      if (file.existsSync()) {
        try {
          final parentDir = file.parent;
          final cleanName = p
              .basenameWithoutExtension(file.path)
              .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          final previewHtml =
              File(p.join(parentDir.path, '.kelivo_${cleanName}_preview.html'));
          final html = _buildVideoHtml(
            file.path,
            isRelative: true,
            initialSeconds: startSeconds,
          );
          previewHtml.writeAsStringSync(html);
          await _webCtrl.loadFile(previewHtml.path);
          return;
        } catch (_) {
          try {
            await _webCtrl.loadFile(file.path);
            return;
          } catch (_) {}
        }
      }
      await _webCtrl.loadHtmlString(
        _buildVideoHtml(src, initialSeconds: startSeconds),
      );
    }
  }

  Future<void> _shareCurrentFile(BuildContext btnContext) async {
    final src = _video.activeSource ?? _currentSource;
    try {
      final box = btnContext.findRenderObject() as RenderBox?;
      final anchor = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromCenter(
              center: MediaQuery.sizeOf(context).center(Offset.zero),
              width: 10,
              height: 10,
            );

      if (src.startsWith('http://') || src.startsWith('https://')) {
        await SharePlus.instance.share(
          ShareParams(
            uri: Uri.tryParse(src),
            sharePositionOrigin: anchor,
          ),
        );
      } else {
        String finalPath = src;
        if (!File(finalPath).existsSync()) {
          finalPath = await ResourcePreviewService.resolvePath(src);
        }
        final file = File(finalPath);
        if (file.existsSync()) {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path)],
              sharePositionOrigin: anchor,
            ),
          );
        } else if (mounted) {
          showAppSnackBar(
            context,
            message: '视频文件不存在，无法分享',
            type: NotificationType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: '分享失败: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  void _stopVideo() {
    _cleanupWebPlayer();
    _video.stop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _video,
      builder: (context, _) {
        final maxDur = math.max(_duration, _currentPosition);
        final safeMax = maxDur > 0 ? maxDur : 1.0;
        final sliderValue = _currentPosition.clamp(0.0, safeMax);

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Center Video Surface (IgnorePointer so all taps/drags go to Flutter)
              Center(
                child: AspectRatio(
                  aspectRatio: _video.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        child: WebViewWidget(controller: _webCtrl),
                      ),
                      if (!_isWebReady)
                        const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white70,
                            strokeWidth: 2.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 2. Dedicated Full-screen Tap Capture Layer (Guarantees 100% reliable tap response on iOS)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                ),
              ),

              // 3. Middle & Bottom Immersive Controls Overlay (Fades in/out on Tap)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Stack(
                      children: [
                        // Center Playback Buttons (Seek -10s, Play/Pause, Seek +10s)
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Seek Backward 10s
                              IconButton(
                                tooltip: '快退 10 秒',
                                onPressed: () => _seekBy(-10),
                                icon: const Icon(
                                  Lucide.RotateCcw,
                                  size: 24,
                                  color: Colors.white,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  padding: const EdgeInsets.all(12),
                                  shape: const CircleBorder(),
                                  side: const BorderSide(
                                    color: Colors.white24,
                                    width: 0.8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),

                              // Play / Pause Toggle
                              IconButton(
                                tooltip: _video.isPlaying ? '暂停' : '播放',
                                onPressed: _togglePlayPause,
                                icon: Icon(
                                  _video.isPlaying
                                      ? Lucide.Pause
                                      : Lucide.Play,
                                  size: 32,
                                  color: Colors.white,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      Colors.black.withValues(alpha: 0.65),
                                  padding: const EdgeInsets.all(18),
                                  shape: const CircleBorder(),
                                  side: const BorderSide(
                                    color: Colors.white38,
                                    width: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),

                              // Seek Forward 10s
                              IconButton(
                                tooltip: '快进 10 秒',
                                onPressed: () => _seekBy(10),
                                icon: const Icon(
                                  Lucide.RotateCw,
                                  size: 24,
                                  color: Colors.white,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  padding: const EdgeInsets.all(12),
                                  shape: const CircleBorder(),
                                  side: const BorderSide(
                                    color: Colors.white24,
                                    width: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bottom Timeline / Progress Bar
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black87,
                                  Colors.black38,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    // Current Position
                                    Text(
                                      _formatTime(_currentPosition),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    // Progress Slider
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3.0,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                            enabledThumbRadius: 6.0,
                                          ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                            overlayRadius: 14.0,
                                          ),
                                          activeTrackColor: cs.primary,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: cs.primary,
                                          overlayColor:
                                              cs.primary.withValues(alpha: 0.2),
                                        ),
                                        child: Slider(
                                          value: sliderValue,
                                          min: 0.0,
                                          max: safeMax,
                                          onChangeStart: (_) {
                                            _isDraggingSlider = true;
                                            _hideControlsTimer?.cancel();
                                          },
                                          onChanged: (val) {
                                            setState(() {
                                              _currentPosition = val;
                                            });
                                          },
                                          onChangeEnd: (val) {
                                            _isDraggingSlider = false;
                                            _seekTo(val);
                                          },
                                        ),
                                      ),
                                    ),
                                    // Duration / Remaining
                                    Text(
                                      _formatTime(_duration),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 4. Top Header Bar (Close & Minimize buttons ALWAYS accessible, never trapped)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: _showControls
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black87,
                              Colors.black38,
                              Colors.transparent,
                            ],
                          )
                        : null,
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          // Close button (Always available)
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () {
                              _stopVideo();
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(
                              Lucide.X,
                              color: Colors.white,
                              size: 22,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black45,
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Video Title (Fades in when controls shown)
                          Expanded(
                            child: AnimatedOpacity(
                              opacity: _showControls ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                _video.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Minimize to PiP button (Always available, accurately syncs progress)
                          IconButton(
                            tooltip: '缩小至画中画',
                            onPressed: () {
                              _video.updatePlaybackPosition(_currentPosition);
                              _video.minimizeToPip();
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(
                              Lucide.Minimize2,
                              color: Colors.white,
                              size: 19,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black45,
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Share button (Fades with controls)
                          AnimatedOpacity(
                            opacity: _showControls ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: IgnorePointer(
                              ignoring: !_showControls,
                              child: Builder(
                                builder: (btnContext) => IconButton(
                                  tooltip: '分享',
                                  onPressed: () =>
                                      _shareCurrentFile(btnContext),
                                  icon: const Icon(
                                    Lucide.Share,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black45,
                                    shape: const CircleBorder(),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
