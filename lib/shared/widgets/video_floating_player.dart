import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
    if (_lastLoadedSource == source && _pipWebCtrl != null) return;
    _lastLoadedSource = source;

    _pipWebCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    final isNetwork =
        source.startsWith('http://') || source.startsWith('https://');
    final srcAttr = isNetwork
        ? htmlEscape.convert(source)
        : 'file://${htmlEscape.convert(source)}';

    final html = '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { box-sizing: border-box; }
    html, body {
      margin: 0; padding: 0; width: 100%; height: 100%;
      background: #000; overflow: hidden;
      display: flex; align-items: center; justify-content: center;
    }
    video {
      width: 100%; height: 100%; object-fit: contain; background: #000;
    }
  </style>
</head>
<body>
  <video id="pip_player" src="$srcAttr" controls autoplay playsinline webkit-playsinline></video>
</body>
</html>''';

    if (isNetwork) {
      _pipWebCtrl!.loadHtmlString(html);
    } else {
      ResourcePreviewService.resolvePath(source).then((resolved) {
        final file = File(resolved);
        if (file.existsSync()) {
          _pipWebCtrl?.loadHtmlString(
            html,
            baseUrl: 'file://${file.parent.path}/',
          );
        } else {
          _pipWebCtrl?.loadHtmlString(html);
        }
      });
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
                                    );
                                    _dragOffset = Offset.zero;
                                  });
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
                                        // Video surface
                                        if (_pipWebCtrl != null)
                                          Positioned.fill(
                                            child: WebViewWidget(
                                              controller: _pipWebCtrl!,
                                            ),
                                          ),

                                        // Tap-to-expand overlay (bottom area)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          height: 32,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              if (_video.activeSource != null) {
                                                VideoPreviewModal.show(
                                                  context,
                                                  source: _video.activeSource!,
                                                  title: _video.activeTitle,
                                                );
                                              }
                                            },
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
                                        ),

                                        // Close button (Top-Right)
                                        Positioned(
                                          top: 5,
                                          right: 5,
                                          child: GestureDetector(
                                            onTap: () => _video.stop(),
                                            child: Container(
                                              width: 22,
                                              height: 22,
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
