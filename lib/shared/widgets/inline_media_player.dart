import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../core/services/audio/global_audio_player_service.dart';
import '../../icons/lucide_adapter.dart';
import 'package:path/path.dart' as p;
import '../../core/services/preview/resource_preview_service.dart';

/// Helper to detect media types from URLs or file paths.
class InlineMediaDetector {
  InlineMediaDetector._();

  static const Set<String> audioExtensions = {
    '.mp3',
    '.wav',
    '.m4a',
    '.aac',
    '.ogg',
    '.flac',
    '.opus',
    '.wma',
  };

  static const Set<String> videoExtensions = {
    '.mp4',
    '.mov',
    '.mkv',
    '.webm',
    '.m4v',
    '.avi',
  };

  /// Returns true if [src] ends with an audio extension.
  static bool isAudio(String src) {
    final clean = src.split('?').first.split('#').first.trim().toLowerCase();
    final ext = p.extension(clean);
    return audioExtensions.contains(ext);
  }

  /// Returns true if [src] ends with a video extension.
  static bool isVideo(String src) {
    final clean = src.split('?').first.split('#').first.trim().toLowerCase();
    final ext = p.extension(clean);
    return videoExtensions.contains(ext);
  }
}

/// Compact in-place audio player capsule for Markdown message bodies.
class InlineAudioPlayer extends StatefulWidget {
  const InlineAudioPlayer({
    super.key,
    required this.source,
    this.title,
  });

  final String source;
  final String? title;

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = false;
  bool _hasError = false;
  String? _resolvedPath;

  bool get _isPlaying => _playerState == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.setAudioContext(GlobalAudioPlayerService.mediaAudioContext).catchError((_) {});
    _initSubscriptions();
    GlobalAudioPlayerService.instance.addListener(_onGlobalAudioChanged);
  }

  void _onGlobalAudioChanged() {
    if (!mounted) return;
    if (GlobalAudioPlayerService.instance.isPlaying && _isPlaying) {
      _player.pause();
    }
  }

  void _initSubscriptions() {
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _playerState = state;
        if (state == PlayerState.playing || state == PlayerState.paused) {
          _isLoading = false;
        }
      });
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    });

    _posSub = _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
  }

  Future<void> _togglePlay() async {
    if (_isLoading) return;

    if (_isPlaying) {
      await _player.pause();
      return;
    }

    if (GlobalAudioPlayerService.instance.isPlaying) {
      await GlobalAudioPlayerService.instance.pause();
    }

    try {
      try {
        await _player.setAudioContext(GlobalAudioPlayerService.mediaAudioContext);
      } catch (_) {}
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final target = widget.source.trim();
      final isWeb = target.startsWith('http://') || target.startsWith('https://');

      if (isWeb) {
        await _player.play(UrlSource(target));
      } else {
        _resolvedPath ??= await ResourcePreviewService.resolvePath(target);
        final file = File(_resolvedPath!);
        if (!file.existsSync()) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
          return;
        }
        await _player.play(DeviceFileSource(file.path));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    GlobalAudioPlayerService.instance.removeListener(_onGlobalAudioChanged);
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : p.basename(widget.source.split('?').first);

    final double maxVal = _duration.inMilliseconds.toDouble();
    final double curVal = _position.inMilliseconds.toDouble().clamp(0.0, maxVal > 0 ? maxVal : 0.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Play / Pause button
              InkWell(
                onTap: _togglePlay,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimaryContainer,
                            ),
                          )
                        : Icon(
                            _isPlaying ? Lucide.Pause : Lucide.Play,
                            size: 16,
                            color: cs.onPrimaryContainer,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // File name
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Duration text
              Text(
                _hasError
                    ? '加载失败'
                    : '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: _hasError ? cs.error : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // Progress Slider
          SizedBox(
            height: 18,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.4),
                thumbColor: cs.primary,
              ),
              child: Slider(
                value: curVal,
                max: maxVal > 0 ? maxVal : 1.0,
                onChanged: maxVal > 0
                    ? (val) {
                        _player.seek(Duration(milliseconds: val.toInt()));
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight inline video card for Markdown message bodies.
///
/// Tapping the card opens the video in the app's floating resource preview.
class InlineVideoCard extends StatelessWidget {
  const InlineVideoCard({
    super.key,
    required this.source,
    this.title,
  });

  final String source;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = title?.trim().isNotEmpty == true
        ? title!.trim()
        : p.basename(source.split('?').first);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ResourcePreviewService.instance.openResource(
              target: source,
              title: displayName,
              context: context,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                // Video thumbnail placeholder / icon badge
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(
                      Lucide.Video,
                      size: 22,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // File info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '点击直接播放视频',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Play circular icon
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Lucide.Play,
                      size: 15,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
