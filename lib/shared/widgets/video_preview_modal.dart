import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
    BuildContext context, {
    required String source,
    String? title,
  }) {
    final video = GlobalVideoPlayerService.instance;
    if (video.isFullPreviewOpen) {
      video.openVideo(source: source, title: title);
      return Future.value();
    }

    video.openVideo(source: source, title: title);
    video.markFullPreviewOpened();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VideoPreviewModal(source: source, title: title),
    ).whenComplete(() {
      video.markFullPreviewDismissed(keepPlayingAsPip: true);
    });
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
    super.dispose();
  }

  void _updateSourceInPlace(String newSource, String? newTitle) {
    if (!mounted) return;
    setState(() {
      _currentSource = newSource;
    });
    _loadVideoInWeb(newSource);
  }

  String _buildVideoHtml(String videoSrc) {
    final isNetwork =
        videoSrc.startsWith('http://') || videoSrc.startsWith('https://');
    final srcAttr = isNetwork
        ? htmlEscape.convert(videoSrc)
        : 'file://${htmlEscape.convert(videoSrc)}';

    return '''<!DOCTYPE html>
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
  <video id="kelivo_player" src="$srcAttr" controls autoplay playsinline webkit-playsinline></video>
</body>
</html>''';
  }

  void _initWebViewController() {
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
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
    final isNetwork = src.startsWith('http://') || src.startsWith('https://');
    if (isNetwork) {
      final html = _buildVideoHtml(src);
      await _webCtrl.loadHtmlString(html);
    } else {
      final resolved = await ResourcePreviewService.resolvePath(src);
      final file = File(resolved);
      if (file.existsSync()) {
        final html = _buildVideoHtml(file.path);
        await _webCtrl.loadHtmlString(html, baseUrl: 'file://${file.parent.path}/');
      } else {
        await _webCtrl.loadHtmlString(_buildVideoHtml(src));
      }
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

              // Top Bar: Close (Left) & Actions (Right: PiP Minimize, Share)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button
                    IconButton.filledTonal(
                      tooltip: '关闭',
                      onPressed: () {
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

                    // Title
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          _video.displayName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: AppFontWeights.emphasis,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ),

                    // Right Actions (PiP minimize & Share)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Minimize to PiP
                        IconButton.filledTonal(
                          tooltip: '缩小至画中画',
                          onPressed: () {
                            _video.minimizeToPip();
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Lucide.Minimize2, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                cs.surfaceContainerHighest.withValues(alpha: 0.8),
                            foregroundColor: cs.onSurface,
                            shape: const CircleBorder(),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Share
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
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Video Player Area
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Colors.black,
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
            ],
          ),
        );
      },
    );
  }
}
