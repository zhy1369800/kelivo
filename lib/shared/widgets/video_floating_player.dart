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
  double _dragDistance = 0.0;
  bool _isCloseButtonHit = false;

  static const double _pipWidth = 208.0;
  static const double _pipHeight = 120.0;

  WebViewController? _pipWebCtrl;
  String? _lastLoadedSource;

  Offset _defaultPosition(Size size, EdgeInsets padding) {
    return Offset(
      size.width - _pipWidth - 16,
      size.height - _pipHeight - padding.bottom - 88,
    );
  }

  Offset _clamp(Offset point, Size size, EdgeInsets padding) {
    const margin = 10.0;
    final minX = margin;
    final maxX = size.width - _pipWidth - margin;
    final minY = padding.top + margin;
    final maxY = size.height - _pipHeight - padding.bottom - margin;

    return Offset(
      point.dx.clamp(math.min(minX, maxX), math.max(minX, maxX)),
      point.dy.clamp(math.min(minY, maxY), math.max(minY, maxY)),
    );
  }

  void _syncPipWebView(String source) {
    if (_lastLoadedSource == source && _pipWebCtrl != null) {
      final pos = _video.playbackPositionSeconds;
      if (pos > 0) {
        _pipWebCtrl!.runJavaScript(
          'const v = document.getElementById("pip_player"); if (v && Math.abs(v.currentTime - $pos) > 1.5) { v.currentTime = $pos; } if (v && v.paused) { v.play(); }',
        );
      }
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
            }
          } catch (_) {}
        },
      );

    _loadPipVideo(source);
  }

  void _pausePip() {
    try {
      _pipWebCtrl?.runJavaScript(
        'const v = document.getElementById("pip_player"); if (v) { v.pause(); }',
      );
    } catch (_) {}
  }

  void _stopPip() {
    try {
      _pipWebCtrl?.runJavaScript(
        'const v = document.getElementById("pip_player"); if (v) { v.pause(); v.src = ""; v.load(); }',
      );
      _pipWebCtrl?.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    _lastLoadedSource = null;
  }

  Future<void> _loadPipVideo(String source) async {
    final startSeconds = _video.playbackPositionSeconds;
    final isNetwork =
        source.startsWith('http://') || source.startsWith('https://');

    if (isNetwork) {
      final html = _buildPipHtml(source, initialSeconds: startSeconds);
      await _pipWebCtrl?.loadHtmlString(html);
    } else {
      final resolved = await ResourcePreviewService.resolvePath(source);
      final file = File(resolved);
      if (file.existsSync()) {
        try {
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
          );
          await previewHtml.writeAsString(html);
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
        _buildPipHtml(source, initialSeconds: startSeconds),
      );
    }
  }

  String _buildPipHtml(
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
  <video id="pip_player" src="$srcAttr" autoplay playsinline webkit-playsinline disablePictureInPicture></video>
  <script>
    const v = document.getElementById('pip_player');
    const startPos = $startSec;
    if (startPos > 0) {
      v.addEventListener('loadedmetadata', () => {
        try { v.currentTime = startPos; } catch(e) {}
      }, { once: true });
    }
    v.addEventListener('timeupdate', () => {
      if (window.KelivoVideoChannel && !v.paused) {
        window.KelivoVideoChannel.postMessage(JSON.stringify({
          type: 'timeupdate',
          currentTime: v.currentTime
        }));
      }
    });
  </script>
</body>
</html>''';
  }

  void _expand() {
    if (_video.activeSource != null) {
      _pausePip();
      VideoPreviewModal.show(
        context,
        source: _video.activeSource!,
        title: _video.activeTitle,
      );
    }
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
                      final currentPos =
                          _position ?? _defaultPosition(size, padding);
                      final effectivePos = Offset(
                        currentPos.dx + _dragOffset.dx,
                        currentPos.dy + _dragOffset.dy,
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
                              width: _pipWidth,
                              height: _pipHeight,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (_) {
                                  _dragDistance = 0.0;
                                },
                                onPanUpdate: (details) {
                                  _dragDistance += details.delta.distance;
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
                                    );
                                    _dragOffset = Offset.zero;
                                  });
                                  if (!_isCloseButtonHit &&
                                      _dragDistance < 8.0) {
                                    _expand();
                                  }
                                  _isCloseButtonHit = false;
                                },
                                onTap: () {
                                  if (!_isCloseButtonHit) {
                                    _expand();
                                  }
                                  _isCloseButtonHit = false;
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(16),
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
                                    borderRadius: BorderRadius.circular(15),
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

                                        // Tap-to-expand overlay (bottom area)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          height: 28,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            color: Colors.black54,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _video.displayName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                const Icon(
                                                  Lucide.Maximize2,
                                                  size: 13,
                                                  color: Colors.white70,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Close button (Top-Right)
                                        Positioned(
                                          top: 5,
                                          right: 5,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTapDown: (_) {
                                              _isCloseButtonHit = true;
                                            },
                                            onTapCancel: () {
                                              _isCloseButtonHit = false;
                                            },
                                            onTap: () {
                                              _isCloseButtonHit = false;
                                              _stopPip();
                                              _video.stop();
                                            },
                                            child: Container(
                                              width: 24,
                                              height: 24,
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
