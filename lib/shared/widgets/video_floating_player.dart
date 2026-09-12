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

/// Unified persistent in-app video player overlay.
///
/// Implements Architecture Option B (Single Player Core with Viewport Tweening):
/// - Hosts the ONLY [WebViewController] and HTML5 `<video>` instance in the app.
/// - Smoothly transforms between floating draggable PiP window and immersive fullscreen preview.
/// - Zero reload, zero audio interruption, zero black-screen lag, and zero autoplay policy failures.
class VideoFloatingPlayer extends StatefulWidget {
  const VideoFloatingPlayer({super.key});

  @override
  State<VideoFloatingPlayer> createState() => _VideoFloatingPlayerState();
}

class _VideoFloatingPlayerState extends State<VideoFloatingPlayer> {
  final GlobalVideoPlayerService _video = GlobalVideoPlayerService.instance;

  // Floating PiP position & drag
  Offset? _position;
  Offset _dragOffset = Offset.zero;
  bool _isControlHit = false;
  bool _isEnlarged = false;
  bool _showPipControls = false;
  Timer? _hidePipControlsTimer;

  // Fullscreen controls & buffering
  bool _showFullControls = true;
  Timer? _hideFullControlsTimer;
  Timer? _bufferingTimer;
  bool _showBuffering = false;
  bool _hasRenderedFirstFrame = false;

  // Playback position & slider tracking
  double _currentPosition = 0.0;
  double _duration = 0.0;
  bool _isDraggingSlider = false;

  WebViewController? _webCtrl;
  String? _lastLoadedSource;
  File? _activeTempHtml;

  @override
  void initState() {
    super.initState();
    _video.addListener(_onVideoServiceChanged);
    final src = _video.activeSource;
    if (src != null) {
      _syncWebView(src);
    }
  }

  void _onVideoServiceChanged() {
    final activeSource = _video.activeSource;
    if (activeSource != null) {
      _syncWebView(activeSource);
    } else {
      _teardownWebPlayer();
    }
  }

  Size _getPipSize([Size? screenSize]) {
    final ratio = _video.aspectRatio;
    final screenW = screenSize?.width ?? 390.0;
    if (ratio < 0.9) {
      // Portrait video
      final width = _isEnlarged
          ? (screenW * 0.62).clamp(220.0, 260.0)
          : (screenW * 0.42).clamp(152.0, 180.0);
      final height = _isEnlarged
          ? (width / ratio).clamp(360.0, 460.0)
          : (width / ratio).clamp(240.0, 315.0);
      return Size(width, height);
    } else {
      // Landscape video
      final width = _isEnlarged
          ? (screenW * 0.92).clamp(320.0, 380.0)
          : (screenW * 0.64).clamp(236.0, 276.0);
      final height = _isEnlarged
          ? (width / ratio).clamp(180.0, 240.0)
          : (width / ratio).clamp(130.0, 180.0);
      return Size(width, height);
    }
  }

  Offset _defaultPosition(Size size, EdgeInsets padding, Size pipSize) {
    return Offset(
      size.width - pipSize.width - 16,
      size.height - pipSize.height - padding.bottom - 88,
    );
  }

  Offset _clamp(Offset point, Size size, EdgeInsets padding, Size pipSize) {
    const margin = 10.0;
    final minX = margin;
    final maxX = size.width - pipSize.width - margin;
    final minY = padding.top + margin;
    final maxY = size.height - pipSize.height - padding.bottom - margin;

    return Offset(
      point.dx.clamp(math.min(minX, maxX), math.max(minX, maxX)),
      point.dy.clamp(math.min(minY, maxY), math.max(minY, maxY)),
    );
  }

  void _startBufferingTimer() {
    _bufferingTimer?.cancel();
    _hasRenderedFirstFrame = false;
    if (_showBuffering) {
      setState(() => _showBuffering = false);
    }
    // 800ms debounce: local or fast videos render in <300ms, completely avoiding spinner flicker
    _bufferingTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_hasRenderedFirstFrame && _video.isFullPreviewOpen) {
        setState(() => _showBuffering = true);
      }
    });
  }

  void _markFirstFrameRendered() {
    if (_hasRenderedFirstFrame) return;
    _hasRenderedFirstFrame = true;
    _bufferingTimer?.cancel();
    if (_showBuffering && mounted) {
      setState(() => _showBuffering = false);
    }
  }

  void _resetHideFullControlsTimer() {
    _hideFullControlsTimer?.cancel();
    if (_showFullControls) {
      _hideFullControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showFullControls && !_isDraggingSlider) {
          setState(() => _showFullControls = false);
        }
      });
    }
  }

  void _toggleFullControls() {
    setState(() {
      _showFullControls = !_showFullControls;
    });
    if (_showFullControls) {
      _resetHideFullControlsTimer();
    } else {
      _hideFullControlsTimer?.cancel();
    }
  }

  void _resetHidePipControlsTimer() {
    _hidePipControlsTimer?.cancel();
    if (_showPipControls) {
      _hidePipControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showPipControls) {
          setState(() => _showPipControls = false);
        }
      });
    }
  }

  void _togglePipControls() {
    setState(() {
      _showPipControls = !_showPipControls;
    });
    if (_showPipControls) {
      _resetHidePipControlsTimer();
    } else {
      _hidePipControlsTimer?.cancel();
    }
  }

  void _syncWebView(String source) {
    if (_lastLoadedSource == source && _webCtrl != null) {
      return; // Reusing active player session without reloading
    }
    _lastLoadedSource = source;
    _startBufferingTimer();

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
            final type = data['type'];
            if (type == 'loadeddata') {
              _markFirstFrameRendered();
            } else if (type == 'timeupdate') {
              _markFirstFrameRendered();
              final pos = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
              final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
              _video.updatePlaybackPosition(pos);
              if (mounted && !_isDraggingSlider) {
                setState(() {
                  _currentPosition = pos;
                  if (dur > 0) _duration = dur;
                });
              }
            } else if (type == 'metadata') {
              final ratio = (data['aspectRatio'] as num?)?.toDouble();
              final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
              if (ratio != null) {
                _video.updateAspectRatio(ratio);
              }
              if (mounted && dur > 0) {
                setState(() => _duration = dur);
              }
            } else if (type == 'play') {
              _video.setPlaying(true);
            } else if (type == 'pause') {
              _video.setPlaying(false);
            } else if (type == 'ended') {
              _video.updatePlaybackPosition(0.0);
              _video.setPlaying(false);
            }
          } catch (_) {}
        },
      );

    _loadVideo(source);
  }

  Future<void> _loadVideo(String source) async {
    final startSeconds = _video.playbackPositionSeconds;
    final isNetwork =
        source.startsWith('http://') || source.startsWith('https://');

    if (isNetwork) {
      final html = _buildVideoHtml(
        source,
        initialSeconds: startSeconds,
      );
      await _webCtrl?.loadHtmlString(html);
    } else {
      final resolved = await ResourcePreviewService.resolvePath(source);
      final file = File(resolved);
      if (file.existsSync()) {
        try {
          _cleanupTempHtml();
          final parentDir = file.parent;
          final cleanName = p
              .basenameWithoutExtension(file.path)
              .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          final previewHtml =
              File(p.join(parentDir.path, '.kelivo_${cleanName}_player.html'));
          final html = _buildVideoHtml(
            file.path,
            isRelative: true,
            initialSeconds: startSeconds,
          );
          await previewHtml.writeAsString(html);
          _activeTempHtml = previewHtml;
          await _webCtrl?.loadFile(previewHtml.path);
          return;
        } catch (_) {
          try {
            await _webCtrl?.loadFile(file.path);
            return;
          } catch (_) {}
        }
      }
      await _webCtrl?.loadHtmlString(
        _buildVideoHtml(
          source,
          initialSeconds: startSeconds,
        ),
      );
    }
  }

  void _cleanupTempHtml() {
    try {
      if (_activeTempHtml != null && _activeTempHtml!.existsSync()) {
        _activeTempHtml!.deleteSync();
      }
    } catch (_) {}
    _activeTempHtml = null;
  }

  void _togglePlayPause() {
    try {
      _webCtrl?.runJavaScript(
        'if (window.__kelivoTogglePlay) { window.__kelivoTogglePlay(); }',
      );
    } catch (_) {}
  }

  void _seekBy(int seconds) {
    _resetHideFullControlsTimer();
    try {
      _webCtrl?.runJavaScript(
        'if (window.__kelivoSeek) { window.__kelivoSeek($seconds); }',
      );
    } catch (_) {}
  }

  void _seekTo(double pos) {
    _resetHideFullControlsTimer();
    try {
      _webCtrl?.runJavaScript(
        'if (window.__kelivoSeekTo) { window.__kelivoSeekTo($pos); }',
      );
    } catch (_) {}
  }

  void _teardownWebPlayer() {
    _hidePipControlsTimer?.cancel();
    _hideFullControlsTimer?.cancel();
    _bufferingTimer?.cancel();
    _cleanupTempHtml();
    try {
      _webCtrl?.runJavaScript('window.KelivoVideoChannel = null;');
      _webCtrl?.runJavaScript(
        'if (window.__kelivoStop) { window.__kelivoStop(); }',
      );
      _webCtrl?.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    _lastLoadedSource = null;
    _webCtrl = null;
  }

  void _stopVideo() {
    _teardownWebPlayer();
    _video.stop();
  }

  Future<void> _shareCurrentFile(BuildContext btnContext) async {
    final src = _video.activeSource;
    if (src == null) return;
    try {
      final box = btnContext.findRenderObject() as RenderBox?;
      final anchor = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromCenter(
              center: MediaQuery.sizeOf(context).center(Offset.zero),
              width: 10,
              height: 10,
            );

      final isNetwork = src.startsWith('http://') || src.startsWith('https://');
      if (isNetwork) {
        await SharePlus.instance.share(
          ShareParams(
            uri: Uri.parse(src),
            sharePositionOrigin: anchor,
          ),
        );
      } else {
        final resolved = await ResourcePreviewService.resolvePath(src);
        final file = File(resolved);
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

  String _formatTime(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return '00:00';
    final s = seconds.toInt();
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
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
  <video id="kelivo_player" src="$srcAttr" autoplay playsinline webkit-playsinline disablePictureInPicture></video>
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
            v.muted = false;
            const p = v.play();
            if (p && p.catch) { p.catch(function() {}); }
          } else {
            v.pause();
          }
        } catch(e) {}
      };

      window.__kelivoStop = function() {
        if (!v) return;
        try {
          v.pause();
          v.src = '';
          v.load();
        } catch(e) {}
      };

      v.addEventListener('loadeddata', () => {
        if (v.paused) {
          const p = v.play();
          if (p && p.catch) { p.catch(function() {}); }
        }
        if (window.KelivoVideoChannel) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({ type: 'loadeddata' }));
        }
      });

      v.addEventListener('loadedmetadata', () => {
        try {
          if (startPos > 0 && Math.abs(v.currentTime - startPos) > 0.5) {
            v.currentTime = startPos;
            const p = v.play();
            if (p && p.catch) { p.catch(function() {}); }
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

      v.addEventListener('ended', () => {
        if (window.KelivoVideoChannel) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({ type: 'ended' }));
        }
      });
    })();
  </script>
</body>
</html>''';
  }

  @override
  void dispose() {
    _video.removeListener(_onVideoServiceChanged);
    _teardownWebPlayer();
    super.dispose();
  }

  Widget _buildFullscreenControls(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxDur = math.max(_duration, _currentPosition);
    final safeMax = maxDur > 0 ? maxDur : 1.0;
    final sliderValue = _currentPosition.clamp(0.0, safeMax);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Dedicated Full-screen Tap Capture Layer
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleFullControls,
          ),
        ),

        // 2. Middle & Bottom Controls Overlay
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _showFullControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: IgnorePointer(
              ignoring: !_showFullControls,
              child: Stack(
                children: [
                  // Center Playback Buttons
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
                            _video.isPlaying ? Lucide.Pause : Lucide.Play,
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
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3.0,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6.0,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
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
                                      _hideFullControlsTimer?.cancel();
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

        // 3. Top Header Bar (Minimize, Title, Share, Close)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: _showFullControls
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
                    // Minimize to PiP button
                    IconButton(
                      tooltip: '缩小至画中画',
                      onPressed: () {
                        _video.minimizeToPip();
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
                    const SizedBox(width: 8),

                    // Title
                    Expanded(
                      child: Center(
                        child: Text(
                          _video.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Share button
                    AnimatedOpacity(
                      opacity: _showFullControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_showFullControls,
                        child: Builder(
                          builder: (btnCtx) => IconButton(
                            tooltip: '分享',
                            onPressed: () => _shareCurrentFile(btnCtx),
                            icon: const Icon(
                              Lucide.Share2,
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
                    const SizedBox(width: 6),

                    // Close button
                    IconButton(
                      tooltip: '关闭',
                      onPressed: _stopVideo,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPipControls(
    BuildContext context,
    Size size,
    EdgeInsets padding,
    Offset currentPos,
  ) {
    final maxDur = math.max(_duration, _currentPosition);
    final progress = maxDur > 0 ? (_currentPosition / maxDur).clamp(0.0, 1.0) : 0.0;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        _dragOffset = Offset.zero;
      },
      onPanUpdate: (details) {
        setState(() {
          _dragOffset += details.delta;
        });
      },
      onPanEnd: (_) {
        setState(() {
          final pipSize = _getPipSize(size);
          _position = _clamp(
            Offset(
              currentPos.dx + _dragOffset.dx,
              currentPos.dy + _dragOffset.dy,
            ),
            size,
            padding,
            pipSize,
          );
          _dragOffset = Offset.zero;
        });
      },
      onDoubleTap: () {
        setState(() {
          _isEnlarged = !_isEnlarged;
          final newPipSize = _getPipSize(size);
          _position = _clamp(
            currentPos,
            size,
            padding,
            newPipSize,
          );
        });
      },
      onTap: () {
        if (!_isControlHit) {
          _togglePipControls();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // PiP Controls Overlay
          AnimatedOpacity(
            opacity: _showPipControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_showPipControls,
              child: Container(
                color: Colors.black45,
                child: Stack(
                  children: [
                    // Top Bar: Expand on left, Close on right
                    Positioned(
                      top: 4,
                      left: 4,
                      right: 4,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Expand to Fullscreen (if permitted)
                          if (_video.canExpand)
                            Listener(
                              onPointerDown: (_) => _isControlHit = true,
                              onPointerUp: (_) => _isControlHit = false,
                              child: IconButton(
                                iconSize: 18,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  shape: const CircleBorder(),
                                ),
                                icon: const Icon(
                                  Lucide.Maximize2,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  _video.expandToFullscreen();
                                },
                              ),
                            )
                          else
                            const SizedBox.shrink(),

                          // Close Player
                          Listener(
                            onPointerDown: (_) => _isControlHit = true,
                            onPointerUp: (_) => _isControlHit = false,
                            child: IconButton(
                              iconSize: 18,
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                shape: const CircleBorder(),
                              ),
                              icon: const Icon(
                                Lucide.X,
                                color: Colors.white,
                              ),
                              onPressed: _stopVideo,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Center: Play / Pause
                    Center(
                      child: Listener(
                        onPointerDown: (_) => _isControlHit = true,
                        onPointerUp: (_) => _isControlHit = false,
                        child: IconButton(
                          iconSize: 28,
                          padding: const EdgeInsets.all(10),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            shape: const CircleBorder(),
                          ),
                          icon: Icon(
                            _video.isPlaying ? Lucide.Pause : Lucide.Play,
                            color: Colors.white,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Thin Progress Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 2.5,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _video,
      builder: (context, _) {
        final activeSource = _video.activeSource;
        final visible = activeSource != null;
        if (!visible) {
          return const SizedBox.shrink();
        }

        final isFull = _video.isFullPreviewOpen;

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
            final padding = MediaQuery.paddingOf(context);
            final pipSize = _getPipSize(screenSize);
            final currentPos =
                _position ?? _defaultPosition(screenSize, padding, pipSize);
            final effectivePos = _clamp(
              Offset(
                currentPos.dx + _dragOffset.dx,
                currentPos.dy + _dragOffset.dy,
              ),
              screenSize,
              padding,
              pipSize,
            );

            final targetLeft = isFull ? 0.0 : effectivePos.dx;
            final targetTop = isFull ? 0.0 : effectivePos.dy;
            final targetWidth = isFull ? screenSize.width : pipSize.width;
            final targetHeight = isFull ? screenSize.height : pipSize.height;

            return PopScope(
              canPop: !isFull,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && isFull) {
                  _video.minimizeToPip();
                }
              },
              child: Stack(
                children: [
                  // Fullscreen Background Black Mask
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !isFull,
                      child: AnimatedOpacity(
                        opacity: isFull ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),

                  // Main Player Viewport with Tween Transformation
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: targetLeft,
                    top: targetTop,
                    width: targetWidth,
                    height: targetHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isFull ? 0 : 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(isFull ? 0 : 12),
                          boxShadow: isFull
                              ? null
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Shared Video WebView Surface
                            Center(
                              child: AspectRatio(
                                aspectRatio: _video.aspectRatio,
                                child: _webCtrl != null
                                    ? IgnorePointer(
                                        child: WebViewWidget(controller: _webCtrl!),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),

                            // Delayed Buffering Indicator in Fullscreen
                            if (isFull)
                              IgnorePointer(
                                ignoring: !_showBuffering,
                                child: Center(
                                  child: AnimatedOpacity(
                                    opacity: _showBuffering ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 240),
                                    curve: Curves.easeInOut,
                                    child: const CircularProgressIndicator(
                                      color: Colors.white70,
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                ),
                              ),

                            // Fullscreen Controls vs PiP Controls
                            if (isFull)
                              _buildFullscreenControls(context)
                            else
                              _buildPipControls(context, screenSize, padding, currentPos),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
