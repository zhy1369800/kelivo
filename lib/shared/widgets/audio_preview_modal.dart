import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/audio/global_audio_player_service.dart';
import '../../core/services/preview/resource_preview_service.dart';
import '../../icons/lucide_adapter.dart';
import '../../theme/app_font_weights.dart';
import 'snackbar.dart';

/// Full card audio preview sheet (matches OpenMinis `MinisAudioPreviewView`).
///
/// Features:
/// - iOS Card Sheet layout: does NOT cover top status bar completely, top rounded corners (R=24).
/// - Track artwork/waveform placeholder, track name, format subtitle.
/// - Scrubber with elapsed & remaining time labels.
/// - Controls: Rewind 10s, Play/Pause, Forward 10s.
/// - Speed switcher (0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x) with badge pill.
/// - PiP minimize button: transitions directly to the floating audio capsule.
class AudioPreviewModal extends StatefulWidget {
  const AudioPreviewModal({
    super.key,
    required this.source,
    this.title,
  });

  final String source;
  final String? title;

  static Future<void> show(
    BuildContext? context, {
    required String source,
    String? title,
  }) async {
    final audio = GlobalAudioPlayerService.instance;
    if (audio.isFullPreviewOpen) {
      audio.play(source, title: title);
      return;
    }

    final effectiveContext = (context != null &&
            context.mounted &&
            Navigator.maybeOf(context) != null)
        ? context
        : rootNavigatorKey.currentContext;

    if (effectiveContext == null || !effectiveContext.mounted) {
      audio.stop();
      return;
    }

    audio.markFullPreviewOpened();
    try {
      await showModalBottomSheet<void>(
        context: effectiveContext,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => AudioPreviewModal(source: source, title: title),
      );
    } catch (e) {
      debugPrint('Error showing AudioPreviewModal: $e');
    } finally {
      audio.markFullPreviewDismissed(keepPlayingAsPip: true);
    }
  }

  @override
  State<AudioPreviewModal> createState() => _AudioPreviewModalState();
}

class _AudioPreviewModalState extends State<AudioPreviewModal> {
  final GlobalAudioPlayerService _audio = GlobalAudioPlayerService.instance;

  @override
  void initState() {
    super.initState();
    if (_audio.activeSource != widget.source) {
      _audio.play(widget.source, title: widget.title);
    }
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _rateBadgeText(double rate) {
    if (rate == rate.toInt()) {
      return '${rate.toInt()}x';
    }
    return '${rate.toStringAsFixed(2).replaceAll(RegExp(r'\.0+$'), '')}x';
  }

  Future<void> _shareCurrentFile(BuildContext btnContext) async {
    final src = _audio.activeSource ?? widget.source;
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
            message: '音频文件不存在，无法分享',
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
      listenable: _audio,
      builder: (context, _) {
        final curMs = _audio.position.inMilliseconds.toDouble();
        final maxMs = _audio.duration.inMilliseconds.toDouble();
        final clampedProgress = (maxMs > 0 ? curMs / maxMs : 0.0).clamp(0.0, 1.0);

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

              // Top Bar (Close & Share)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button
                    IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Lucide.X, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.8),
                        foregroundColor: cs.onSurface,
                        shape: const CircleBorder(),
                      ),
                    ),
                    // Action Buttons (Share)
                    Builder(
                      builder: (btnContext) => IconButton.filledTonal(
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

              // Main Track Artwork / Waveform Area
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AspectRatio(
                  aspectRatio: 1.1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: _audio.isLoading
                          ? CircularProgressIndicator(
                              color: cs.primary,
                              strokeWidth: 3,
                            )
                          : Icon(
                              Lucide.AudioWaveform,
                              size: 72,
                              color: _audio.isPlaying
                                  ? cs.primary
                                  : cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Track Title & Subtitle Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _audio.displayName,
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
                        _audio.fileFormatLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Progress Section (Scrubber + Time labels)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: cs.primary,
                        inactiveTrackColor:
                            cs.outlineVariant.withValues(alpha: 0.35),
                        thumbColor: cs.primary,
                      ),
                      child: Slider(
                        value: clampedProgress,
                        onChanged: maxMs > 0
                            ? (ratio) {
                                final target = Duration(
                                  milliseconds: (maxMs * ratio).toInt(),
                                );
                                _audio.seek(target);
                              }
                            : null,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTime(_audio.position),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            _formatTime(_audio.duration),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Control Row (-10s, Play/Pause, +10s)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Rewind 10s
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Lucide.RotateCcw),
                    onPressed: () =>
                        _audio.skip(const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 24),
                  // Play / Pause big button
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.32),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      iconSize: 30,
                      color: cs.onPrimary,
                      icon: Icon(
                        _audio.isPlaying ? Lucide.Pause : Lucide.Play,
                      ),
                      onPressed: () => _audio.togglePlayPause(),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Forward 10s
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Lucide.RotateCw),
                    onPressed: () =>
                        _audio.skip(const Duration(seconds: 10)),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Bottom Bar: Speed Switcher (Left) & PiP Minimize (Right)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 4, 32, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Speed switcher with badge pill
                    PopupMenuButton<double>(
                      tooltip: '播放速度',
                      initialValue: _audio.playbackRate,
                      onSelected: (rate) => _audio.setPlaybackRate(rate),
                      itemBuilder: (ctx) => [
                        for (final r in GlobalAudioPlayerService.supportedRates)
                          PopupMenuItem<double>(
                            value: r,
                            child: Row(
                              children: [
                                if (r == _audio.playbackRate)
                                  Icon(Lucide.Check,
                                      size: 16, color: cs.primary)
                                else
                                  const SizedBox(width: 16),
                                const SizedBox(width: 8),
                                Text('${r}x 速度'),
                              ],
                            ),
                          ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Lucide.Gauge, size: 18, color: cs.onSurface),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _rateBadgeText(_audio.playbackRate),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Minimize / PiP Button
                    IconButton.filledTonal(
                      tooltip: '缩小至浮动胶囊',
                      onPressed: () {
                        _audio.minimizeToPip();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Lucide.Minimize2, size: 19),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.7),
                        foregroundColor: cs.onSurface,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
