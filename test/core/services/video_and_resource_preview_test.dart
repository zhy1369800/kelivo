import 'package:Kelivo/core/services/preview/resource_preview_service.dart';
import 'package:Kelivo/core/services/video/global_video_player_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobalVideoPlayerService Tests', () {
    final video = GlobalVideoPlayerService.instance;

    setUp(() {
      video.stop();
    });

    test('openVideo sets active state and toggles play/pause', () {
      final success = video.openVideo(
        source: 'https://example.com/test.mp4',
        title: 'Test Video',
      );
      expect(success, isTrue);
      expect(video.activeSource, 'https://example.com/test.mp4');
      expect(video.activeTitle, 'Test Video');
      expect(video.displayName, 'Test Video');
      expect(video.isPlaying, isTrue);
      expect(video.isPipActive, isFalse);

      video.togglePlayPause();
      expect(video.isPlaying, isFalse);

      video.togglePlayPause();
      expect(video.isPlaying, isTrue);
    });

    test('minimizeToPip transitions state to PiP', () {
      video.openVideo(source: 'https://example.com/test.mp4');
      video.markFullPreviewOpened();
      expect(video.isFullPreviewOpen, isTrue);
      expect(video.isPipActive, isFalse);

      video.minimizeToPip();
      expect(video.isFullPreviewOpen, isFalse);
      expect(video.isPipActive, isTrue);
    });

    test('in-place updater replaces source when modal is open', () {
      String? updatedSource;
      String? updatedTitle;
      video.registerModalUpdater((src, title) {
        updatedSource = src;
        updatedTitle = title;
      });

      video.markFullPreviewOpened();
      final opened = video.openVideo(
        source: 'https://example.com/new.mp4',
        title: 'New Video',
      );

      expect(opened, isTrue);
      expect(updatedSource, 'https://example.com/new.mp4');
      expect(updatedTitle, 'New Video');
      expect(video.activeSource, 'https://example.com/new.mp4');

      video.registerModalUpdater(null);
    });

    test('stop clears all active playback states and position', () {
      video.openVideo(source: 'https://example.com/test.mp4');
      video.updatePlaybackPosition(12.5);
      expect(video.playbackPositionSeconds, 12.5);

      video.minimizeToPip();
      expect(video.activeSource, isNotNull);

      video.stop();
      expect(video.activeSource, isNull);
      expect(video.isPlaying, isFalse);
      expect(video.isPipActive, isFalse);
      expect(video.isFullPreviewOpen, isFalse);
      expect(video.playbackPositionSeconds, 0.0);
    });

    test('opening new video resets playback position', () {
      video.openVideo(source: 'https://example.com/test.mp4');
      video.updatePlaybackPosition(30.0);
      expect(video.playbackPositionSeconds, 30.0);

      video.openVideo(source: 'https://example.com/other.mp4');
      expect(video.playbackPositionSeconds, 0.0);
    });

    test('dismissing modal without minimize stops playback completely', () {
      video.openVideo(source: 'https://example.com/test.mp4');
      video.markFullPreviewOpened();

      // Dismissing without minimizeToPip stops playback
      video.markFullPreviewDismissed(keepPlayingAsPip: false);
      expect(video.isFullPreviewOpen, isFalse);
      expect(video.isPipActive, isFalse);
      expect(video.activeSource, isNull);
    });

    test('dismissing modal after minimizeToPip keeps PiP active', () {
      video.openVideo(source: 'https://example.com/test.mp4');
      video.markFullPreviewOpened();

      // User explicitly clicked minimizeToPip
      video.minimizeToPip();
      video.markFullPreviewDismissed(keepPlayingAsPip: true);
      expect(video.isFullPreviewOpen, isFalse);
      expect(video.isPipActive, isTrue);
      expect(video.activeSource, 'https://example.com/test.mp4');
    });

    test('aspectRatio defaults to 16:9, updates with valid ratio, and resets on new video or stop', () {
      expect(video.aspectRatio, closeTo(16 / 9, 0.001));

      // Update with portrait video (e.g. 9:16)
      video.updateAspectRatio(9 / 16);
      expect(video.aspectRatio, closeTo(9 / 16, 0.001));

      // Invalid ratio should be ignored
      video.updateAspectRatio(0.05);
      expect(video.aspectRatio, closeTo(9 / 16, 0.001));

      // Opening new video resets to default 16:9
      video.openVideo(source: 'https://example.com/new.mp4');
      expect(video.aspectRatio, closeTo(16 / 9, 0.001));

      // Update again and verify stop resets it
      video.updateAspectRatio(4 / 3);
      expect(video.aspectRatio, closeTo(4 / 3, 0.001));
      video.stop();
      expect(video.aspectRatio, closeTo(16 / 9, 0.001));
    });
  });

  group('ResourcePreviewService Debounce Tests', () {
    final preview = ResourcePreviewService.instance;

    test('rapid multi-taps on same target are debounced', () async {
      final res1 = await preview.openResource(target: 'https://example.com/movie.mp4');
      final res2 = await preview.openResource(target: 'https://example.com/movie.mp4');

      expect(res1.target, 'https://example.com/movie.mp4');
      expect(res2.openedAs, 'debounced');
    });
  });
}
