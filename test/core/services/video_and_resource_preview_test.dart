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

    test('minimizeToPip and expandToFullscreen transition states', () {
      video.openVideo(source: 'https://example.com/test.mp4');
      expect(video.isFullPreviewOpen, isTrue);
      expect(video.isPipActive, isFalse);

      video.minimizeToPip();
      expect(video.isFullPreviewOpen, isFalse);
      expect(video.isPipActive, isTrue);

      video.expandToFullscreen();
      expect(video.isFullPreviewOpen, isTrue);
      expect(video.isPipActive, isFalse);
    });

    test('opening new video replaces source in-place and updates metadata', () {
      final opened1 = video.openVideo(
        source: 'https://example.com/test.mp4',
        title: 'First Video',
      );
      expect(opened1, isTrue);
      expect(video.activeSource, 'https://example.com/test.mp4');
      expect(video.activeTitle, 'First Video');

      final opened2 = video.openVideo(
        source: 'https://example.com/new.mp4',
        title: 'New Video',
      );
      expect(opened2, isTrue);
      expect(video.activeSource, 'https://example.com/new.mp4');
      expect(video.activeTitle, 'New Video');
      expect(video.displayName, 'New Video');
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

    test('playbackRate updates and supports valid presets', () {
      video.openVideo(source: 'https://example.com/test.mp4');
      expect(video.playbackRate, 1.0);

      video.setPlaybackRate(1.5);
      expect(video.playbackRate, 1.5);

      // Unsupported rate should be ignored
      video.setPlaybackRate(3.0);
      expect(video.playbackRate, 1.5);

      // Opening new video resets playback rate
      video.openVideo(source: 'https://example.com/other.mp4');
      expect(video.playbackRate, 1.0);
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

    test('openVideo with asPip launches directly into PiP with custom canExpand', () {
      final success = video.openVideo(
        source: 'https://example.com/card_video.mp4',
        asPip: true,
        canExpand: false,
      );
      expect(success, isTrue);
      expect(video.isPipActive, isTrue);
      expect(video.isFullPreviewOpen, isFalse);
      expect(video.isPlaying, isTrue);
      expect(video.canExpand, isFalse);

      video.stop();
      expect(video.canExpand, isTrue);
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

    test('openResource with action: pip launches into PiP player', () async {
      final res = await preview.openResource(
        target: 'https://example.com/stream.mp4',
        action: 'pip',
      );
      expect(res.success, isTrue);
      expect(res.openedAs, 'video_player');
      expect(res.message, contains('PiP Player'));
      expect(GlobalVideoPlayerService.instance.isPipActive, isTrue);
      expect(GlobalVideoPlayerService.instance.canExpand, isTrue);
      GlobalVideoPlayerService.instance.stop();
    });

    test('openResource with action: auto launches into full video player without PiP', () async {
      final res = await preview.openResource(
        target: 'https://example.com/full_stream.mp4',
        action: 'auto',
      );
      expect(res.success, isTrue);
      expect(res.openedAs, 'video_player');
      expect(res.message, contains('in-app Video Player'));
      expect(GlobalVideoPlayerService.instance.isPipActive, isFalse);
      GlobalVideoPlayerService.instance.stop();
    });
  });
}
