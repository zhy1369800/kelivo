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
import '../../theme/app_font_weights.dart';
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

    final effectiveContext = navigator.overlay?.context ?? navigator.context;

    video.openVideo(source: source, title: title);
    video.markFullPreviewOpened();

    try {
      await showModalBottomSheet<void>(
        context: effectiveContext,
        useRootNavigator: false,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => VideoPreviewModal(source: source, title: title),
      );
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

  @override
  void initState() {
    super.initState();
    _currentSource = widget.source;

    _initWebViewController();
    _video.registerModalUpdater(_updateSourceInPlace);
  }

  @override
  void dispose() {
    _video.registerModalUpdater(null);
    try {
      _webCtrl.runJavaScript(
        'const v = document.getElementById("kelivo_player"); if (v) { v.pause(); v.src = ""; v.load(); }',
      );
      _webCtrl.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
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
    video::-webkit-media-controls-picture-in-picture-button {
      display: none !important;
    }
  </style>
</head>
<body>
  <video id="kelivo_player" src="$srcAttr" controls autoplay playsinline webkit-playsinline
         disablePictureInPicture controlsList="nofullscreen nodownload noremoteplayback"></video>
  <script>
    const v = document.getElementById('kelivo_player');
    const startPos = $startSec;
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
            if (data['type'] == 'timeupdate') {
              final pos = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
              _video.updatePlaybackPosition(pos);
            } else if (data['type'] == 'metadata') {
              final ratio = (data['aspectRatio'] as num?)?.toDouble();
              if (ratio != null) {
                _video.updateAspectRatio(ratio);
              }
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
          await previewHtml.writeAsString(html);
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

  String get _fileFormatLabel {
    final src = _video.activeSource ?? _currentSource;
    if (src.isEmpty) return '视频';
    final clean = src.split('?').first.split('#').first;
    final dotIndex = clean.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < clean.length - 1) {
      final ext = clean.substring(dotIndex + 1).toUpperCase();
      return '$ext 视频';
    }
    return '视频';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenH = MediaQuery.sizeOf(context).height;
    final maxSheetH = math.max(480.0, screenH * 0.88);

    return ListenableBuilder(
      listenable: _video,
      builder: (context, _) {
        return Container(
          constraints: BoxConstraints(maxHeight: maxSheetH),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Indicator Bar
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Top Bar: Close (Left) & Share (Right)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button
                    IconButton.filledTonal(
                      tooltip: '关闭',
                      onPressed: () {
                        try {
                          _webCtrl.runJavaScript(
                            'const v = document.getElementById("kelivo_player"); if (v) { v.pause(); v.src = ""; v.load(); }',
                          );
                          _webCtrl.loadRequest(Uri.parse('about:blank'));
                        } catch (_) {}
                        _video.stop();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Lucide.X, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.8),
                        foregroundColor: cs.onSurface,
                        shape: const CircleBorder(),
                      ),
                    ),

                    // Right Actions (Share)
                    Builder(
                      builder: (btnContext) => IconButton.filledTonal(
                        tooltip: '分享',
                        onPressed: () => _shareCurrentFile(btnContext),
                        icon: const Icon(Lucide.Share, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              cs.surfaceContainerHighest.withValues(alpha: 0.8),
                          foregroundColor: cs.onSurface,
                          shape: const CircleBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Scrollable body to prevent overflow on small screens or landscape mode
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Main Video Display Area (Adaptive Aspect Ratio)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.50,
                          ),
                          child: AspectRatio(
                            aspectRatio: _video.aspectRatio.clamp(0.56, 2.4),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: cs.outlineVariant.withValues(alpha: 0.3),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                children: [
                                  WebViewWidget(controller: _webCtrl),
                                  if (!_isWebReady)
                                    Center(
                                      child: CircularProgressIndicator(
                                        color: cs.primary,
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Track Title & Subtitle Info (File name + format label)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _video.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: AppFontWeights.emphasis,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _fileFormatLabel,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Bottom Action Bar: Minimize to PiP (Large tonal button)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              _video.minimizeToPip();
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Lucide.Minimize2, size: 18),
                            label: const Text(
                              '缩小至画中画',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
