import 'package:flutter/material.dart';
import '../../core/services/video/global_video_player_service.dart';

/// Lightweight facade for opening videos in fullscreen preview mode.
///
/// Under the unified single-player architecture (Option B), both fullscreen
/// and floating PiP states are handled by the persistent [VideoFloatingPlayer]
/// overlay. This class provides 100% backward-compatible API for callers.
class VideoPreviewModal {
  const VideoPreviewModal._();

  /// Opens the video directly in fullscreen mode within the unified overlay.
  static Future<void> show(
    BuildContext? context, {
    required String source,
    String? title,
  }) async {
    GlobalVideoPlayerService.instance.openVideo(
      source: source,
      title: title,
      asPip: false,
    );
  }
}
