import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/services/preview/resource_preview_service.dart';
import '../../core/services/video/global_video_player_service.dart';
import '../../icons/lucide_adapter.dart';
import 'video_preview_modal.dart';

/// Floating in-chat video PiP player window.
///
/// Features:
/// - Appears in the bottom-right (or user-dragged position) when minimized from full preview.
/// - Allows the user to continue chatting with AI while watching the video.
/// - Full gesture pass-through on empty areas so user can type/scroll without interference.
/// - Tap to re-expand to the full card preview sheet.
/// - Drag to move smoothly anywhere on screen.
/// - Top-right close button stops video and dismisses the PiP window.
class VideoFloatingPlayer extends StatefulWidget {
  const VideoFloatingPlayer({super.key});

  @override
  State<VideoFloatingPlayer> createState() => _VideoFloatingPlayerState();
}

class _VideoFloatingPlayerState extends State<VideoFloatingPlayer> {
  final GlobalVideoPlayerService _video = GlobalVideoPlayerService.instance;

  Offset? _position;
  Offset _dragOffset = Offset.zero;
  bool _isControlHit = false;

  bool _isEnlarged = false;
  bool _showControls = false;
  Timer? _hideControlsTimer;

  WebViewController? _pipWebCtrl;
  String? _lastLoadedSource;

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

  void _expand() async {
    final src = _video.activeSource;
    if (src == null) return;

    // Try to get precise playback position from the WebView before expanding
    try {
      final result = await _pipWebCtrl?.runJavaScriptReturningResult(
        '(function() { const v = document.getElementById("pip_player"); return v ? v.currentTime : 0; })()',
      );
      if (result != null) {
        final pos = double.tryParse(result.toString()) ?? _video.playbackPositionSeconds;
        if (pos > 0) {
          _video.updatePlaybackPosition(pos);
        }
      }
    } catch (_) {}

    // Immediately mute PiP to avoid audio overlap during transition
    _mutePip();

    // Check if widget is still mounted after async operation
    if (!mounted) return;

    // Show full preview modal (will initialize at current position)
    VideoPreviewModal.show(
      context,
      source: src,
      title: _video.activeTitle,
    );

    // Delay pausing PiP to allow smooth visual transition
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _pausePip();
      }
    });
  }

  void _syncPipWebView(String source) {
    if (_lastLoadedSource == source && _pipWebCtrl != null) {
      final pos = _video.playbackPositionSeconds;
      final isPlaying = _video.isPlaying;
      try {
        // Sync position and actual playing state
        _pipWebCtrl!.runJavaScript(
          'if (window.__kelivoSyncState) { window.__kelivoSyncState($pos, $isPlaying); }',
        );
      } catch (_) {}
      return;
    }
    _lastLoadedSource = source;

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _pipWebCtrl = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'KelivoVideoChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (data['type'] == 'timeupdate') {
              final pos = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
              _video.updatePlaybackPosition(pos);
            } else if (data['type'] == 'metadata') {
              final ratio = (data['aspectRatio'] as num?)?.toDouble();
              if (ratio != null) {
                _video.updateAspectRatio(ratio);
              }
            } else if (data['type'] == 'play') {
              _video.setPlaying(true);
            } else if (data['type'] == 'pause') {
              _video.setPlaying(false);
            }
          } catch (_) {}
        },
      );

    _loadPipVideo(source);
  }

  void _toggleControls() {
    _hideControlsTimer?.cancel();
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showControls) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _seekBy(int seconds) {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
    try {
      _pipWebCtrl?.runJavaScript(
        'if (window.__kelivoSeek) { window.__kelivoSeek($seconds); }',
      );
    } catch (_) {}
  }

  void _togglePlayPause() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
    try {
      _pipWebCtrl?.runJavaScript(
        'if (window.__kelivoTogglePlay) { window.__kelivoTogglePlay(); }',
      );
    } catch (_) {}
  }

  void _pausePip() {
    try {
      _pipWebCtrl?.runJavaScript(
        'if (window.__kelivoPause) { window.__kelivoPause(); }',
      );
    } catch (_) {}
  }

  void _mutePip() {
    try {
      _pipWebCtrl?.runJavaScript(
        '(function() { const v = document.getElementById("pip_player"); if (v) v.muted = true; })()',
      );
    } catch (_) {}
  }

  File? _activeTempHtml;

  void _cleanupTempHtml() {
    try {
      if (_activeTempHtml != null && _activeTempHtml!.existsSync()) {
        _activeTempHtml!.deleteSync();
      }
    } catch (_) {}
    _activeTempHtml = null;
  }

  void _stopPip() {
    _hideControlsTimer?.cancel();
    _showControls = false;
    _cleanupTempHtml();
    try {
      _pipWebCtrl?.runJavaScript(
        'if (window.__kelivoStop) { window.__kelivoStop(); }',
      );
      _pipWebCtrl?.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    _lastLoadedSource = null;
  }

  Future<void> _loadPipVideo(String source) async {
    final startSeconds = _video.playbackPositionSeconds;
    final isNetwork =
        source.startsWith('http://') || source.startsWith('https://');

    final autoPlay = _video.isPlaying;
    if (isNetwork) {
      final html = _buildPipHtml(
        source,
        initialSeconds: startSeconds,
        autoPlay: autoPlay,
      );
      await _pipWebCtrl?.loadHtmlString(html);
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
              File(p.join(parentDir.path, '.kelivo_${cleanName}_pip.html'));
          final html = _buildPipHtml(
            file.path,
            isRelative: true,
            initialSeconds: startSeconds,
            autoPlay: autoPlay,
          );
          await previewHtml.writeAsString(html);
          _activeTempHtml = previewHtml;
          await _pipWebCtrl?.loadFile(previewHtml.path);
          return;
        } catch (_) {
          try {
            await _pipWebCtrl?.loadFile(file.path);
            return;
          } catch (_) {}
        }
      }
      await _pipWebCtrl?.loadHtmlString(
        _buildPipHtml(
          source,
          initialSeconds: startSeconds,
          autoPlay: autoPlay,
        ),
      );
    }
  }

  String _buildPipHtml(
    String videoSrc, {
    bool isRelative = false,
    double initialSeconds = 0.0,
    bool autoPlay = true,
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
    final autoPlayAttr = autoPlay ? 'autoplay' : '';

    // In PiP mode, omit native controls, disable system PiP, auto-play with playsinline
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
  <video id="pip_player" src="$srcAttr" $autoPlayAttr playsinline webkit-playsinline disablePictureInPicture></video>
  <script>
    (function() {
      const v = document.getElementById('pip_player');
      const startPos = $startSec;

      window.__kelivoSeek = function(delta) {
        if (!v) return;
        try {
          const maxDur = v.duration || 999999;
          v.currentTime = Math.max(0, Math.min(maxDur, v.currentTime + delta));
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

      window.__kelivoPause = function() {
        if (!v) return;
        try { v.pause(); } catch(e) {}
      };

      window.__kelivoStop = function() {
        if (!v) return;
        try {
          v.pause();
          v.src = '';
          v.load();
        } catch(e) {}
      };

      window.__kelivoSyncState = function(pos, isPlaying) {
        if (!v) return;
        try {
          if (Math.abs(v.currentTime - pos) > 0.5) {
            v.currentTime = pos;
          }
          if (isPlaying && v.paused) {
            const p = v.play();
            if (p && p.catch) { p.catch(function() {}); }
          } else if (!isPlaying && !v.paused) {
            v.pause();
          }
        } catch(e) {}
      };

      window.__kelivoSyncPosition = function(pos) {
        if (!v) return;
        try {
          if (Math.abs(v.currentTime - pos) > 1.5) {
            v.currentTime = pos;
          }
        } catch(e) {}
      };

      v.addEventListener('loadedmetadata', () => {
        try {
          if (startPos > 0) { v.currentTime = startPos; }
        } catch(e) {}
        if (window.KelivoVideoChannel && v.videoWidth && v.videoHeight) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({
            type: 'metadata',
            videoWidth: v.videoWidth,
            videoHeight: v.videoHeight,
            aspectRatio: v.videoWidth / v.videoHeight
          }));
        }
      });
      v.addEventListener('timeupdate', () => {
        if (window.KelivoVideoChannel && !v.paused) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({
            type: 'timeupdate',
            currentTime: v.currentTime
          }));
        }
      });
      v.addEventListener('play', () => {
        if (window.KelivoVideoChannel) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({
            type: 'play'
          }));
        }
      });
      v.addEventListener('pause', () => {
        if (window.KelivoVideoChannel) {
          window.KelivoVideoChannel.postMessage(JSON.stringify({
            type: 'pause'
          }));
        }
      });
    })();
  </script>
</body>
</html>''';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _cleanupTempHtml();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _video,
      builder: (context, _) {
        final visible = _video.isPipActive &&
            !_video.isFullPreviewOpen &&
            _video.activeSource != null;

        if (visible && _video.activeSource != null) {
          _syncPipWebView(_video.activeSource!);
        } else if (_video.activeSource == null) {
          _stopPip();
        } else if (!visible) {
          _pausePip();
        }

        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: visible
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final padding = MediaQuery.paddingOf(context);
                      final pipSize = _getPipSize(size);
                      final currentPos =
                          _position ?? _defaultPosition(size, padding, pipSize);
                      final effectivePos = _clamp(
                        Offset(
                          currentPos.dx + _dragOffset.dx,
                          currentPos.dy + _dragOffset.dy,
                        ),
                        size,
                        padding,
                        pipSize,
                      );
                      final cs = Theme.of(context).colorScheme;

                      return SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: Stack(
                          children: [
                            Positioned(
                              left: effectivePos.dx,
                              top: effectivePos.dy,
                              width: pipSize.width,
                              height: pipSize.height,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
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
                                    _toggleControls();
                                  }
                                  _isControlHit = false;
                                },
                                onPanUpdate: (details) {
                                  setState(() {
                                    _dragOffset += details.delta;
                                  });
                                },
                                onPanEnd: (_) {
                                  setState(() {
                                    _position = _clamp(
                                      currentPos + _dragOffset,
                                      size,
                                      padding,
                                      pipSize,
                                    );
                                    _dragOffset = Offset.zero;
                                  });
                                  _isControlHit = false;
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: cs.outlineVariant
                                          .withValues(alpha: 0.55),
                                      width: 1.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.35),
                                        blurRadius: 18,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(17),
                                    child: Stack(
                                      children: [
                                        // Video surface (with IgnorePointer so all taps/drags are handled cleanly by Flutter)
                                        if (_pipWebCtrl != null)
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: WebViewWidget(
                                                controller: _pipWebCtrl!,
                                              ),
                                            ),
                                          ),

                                        // Media Controls Overlay (Fade in/out on Single Tap)
                                        Positioned.fill(
                                          child: AnimatedOpacity(
                                            opacity: _showControls ? 1.0 : 0.0,
                                            duration:
                                                const Duration(milliseconds: 200),
                                            curve: Curves.easeInOut,
                                            child: IgnorePointer(
                                              ignoring: !_showControls,
                                              child: Container(
                                                color: Colors.black45,
                                                child: Center(
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.center,
                                                    children: [
                                                      // Seek Backward 10s
                                                      GestureDetector(
                                                        behavior:
                                                            HitTestBehavior.opaque,
                                                        onTapDown: (_) =>
                                                            _isControlHit = true,
                                                        onTapCancel: () =>
                                                            _isControlHit = false,
                                                        onTap: () {
                                                          _isControlHit = false;
                                                          _seekBy(-10);
                                                        },
                                                        child: Container(
                                                          width: 36,
                                                          height: 36,
                                                          decoration: BoxDecoration(
                                                            color: Colors.black54,
                                                            shape: BoxShape.circle,
                                                            border: Border.all(
                                                              color: Colors.white24,
                                                              width: 0.8,
                                                            ),
                                                          ),
                                                          child: const Center(
                                                            child: Icon(
                                                              Lucide.RotateCcw,
                                                              size: 18,
                                                              color: Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 14),

                                                      // Play / Pause Toggle
                                                      GestureDetector(
                                                        behavior:
                                                            HitTestBehavior.opaque,
                                                        onTapDown: (_) =>
                                                            _isControlHit = true,
                                                        onTapCancel: () =>
                                                            _isControlHit = false,
                                                        onTap: () {
                                                          _isControlHit = false;
                                                          _togglePlayPause();
                                                        },
                                                        child: Container(
                                                          width: 44,
                                                          height: 44,
                                                          decoration: BoxDecoration(
                                                            color: Colors.black
                                                                .withValues(alpha: 0.65),
                                                            shape: BoxShape.circle,
                                                            border: Border.all(
                                                              color: Colors.white38,
                                                              width: 1.0,
                                                            ),
                                                          ),
                                                          child: Center(
                                                            child: Icon(
                                                              _video.isPlaying
                                                                  ? Lucide.Pause
                                                                  : Lucide.Play,
                                                              size: 22,
                                                              color: Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 14),

                                                      // Seek Forward 10s
                                                      GestureDetector(
                                                        behavior:
                                                            HitTestBehavior.opaque,
                                                        onTapDown: (_) =>
                                                            _isControlHit = true,
                                                        onTapCancel: () =>
                                                            _isControlHit = false,
                                                        onTap: () {
                                                          _isControlHit = false;
                                                          _seekBy(10);
                                                        },
                                                        child: Container(
                                                          width: 36,
                                                          height: 36,
                                                          decoration: BoxDecoration(
                                                            color: Colors.black54,
                                                            shape: BoxShape.circle,
                                                            border: Border.all(
                                                              color: Colors.white24,
                                                              width: 0.8,
                                                            ),
                                                          ),
                                                          child: const Center(
                                                            child: Icon(
                                                              Lucide.RotateCw,
                                                              size: 18,
                                                              color: Colors.white,
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
                                        ),

                                        // Expand button (Top-Left)
                                        if (_video.canExpand)
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTapDown: (_) =>
                                                  _isControlHit = true,
                                              onTapCancel: () =>
                                                  _isControlHit = false,
                                              onTap: () {
                                                _isControlHit = false;
                                                _expand();
                                              },
                                              child: Container(
                                                width: 26,
                                                height: 26,
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white24,
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Center(
                                                  child: Icon(
                                                    Lucide.Maximize2,
                                                    size: 13,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                        // Close button (Top-Right)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTapDown: (_) {
                                              _isControlHit = true;
                                            },
                                            onTapCancel: () {
                                              _isControlHit = false;
                                            },
                                            onTap: () {
                                              _isControlHit = false;
                                              _stopPip();
                                              _video.stop();
                                            },
                                            child: Container(
                                              width: 26,
                                              height: 26,
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white24,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Lucide.X,
                                                  size: 13,
                                                  color: Colors.white,
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
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
