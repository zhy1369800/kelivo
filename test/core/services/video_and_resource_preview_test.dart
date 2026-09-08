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

    test('stop clears all active playback states', () {
      video.openVideo(source: 'https://example.com/test.mp4');
      video.minimizeToPip();
      expect(video.activeSource, isNotNull);

      video.stop();
      expect(video.activeSource, isNull);
      expect(video.isPlaying, isFalse);
      expect(video.isPipActive, isFalse);
      expect(video.isFullPreviewOpen, isFalse);
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
