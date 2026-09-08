import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/services/audio/global_audio_player_service.dart';
import '../../icons/lucide_adapter.dart';
import 'audio_preview_modal.dart';

/// Floating audio PiP capsule shown over chat and global UI.
///
/// Matches the OpenMinis `AudioPiPCapsule` widget:
/// - Appears in the bottom-right (or user dragged position) when minimized.
/// - Allows the user to continue chatting with AI while listening.
/// - Left button: Waveform icon that re-expands the full card preview sheet.
/// - Middle button: Toggle play / pause.
/// - Right button: Close X that stops playback and removes the capsule.
class AudioFloatingCapsule extends StatefulWidget {
  const AudioFloatingCapsule({super.key});

  @override
  State<AudioFloatingCapsule> createState() => _AudioFloatingCapsuleState();
}

class _AudioFloatingCapsuleState extends State<AudioFloatingCapsule> {
  final GlobalAudioPlayerService _audio = GlobalAudioPlayerService.instance;

  Offset? _position;
  Offset _dragOffset = Offset.zero;

  static const double _capsuleWidth = 156.0;
  static const double _capsuleHeight = 44.0;

  Offset _defaultPosition(Size size, EdgeInsets padding) {
    return Offset(
      size.width - _capsuleWidth - 16,
      size.height - _capsuleHeight - padding.bottom - 88,
    );
  }

  Offset _clamp(Offset point, Size size, EdgeInsets padding) {
    const margin = 10.0;
    final minX = margin;
    final maxX = size.width - _capsuleWidth - margin;
    final minY = padding.top + margin;
    final maxY = size.height - _capsuleHeight - padding.bottom - margin;

    return Offset(
      point.dx.clamp(math.min(minX, maxX), math.max(minX, maxX)),
      point.dy.clamp(math.min(minY, maxY), math.max(minY, maxY)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _audio,
      builder: (context, _) {
        if (!_audio.isPipActive || _audio.isFullPreviewOpen) {
          return const SizedBox.shrink();
        }

        final size = MediaQuery.sizeOf(context);
        final padding = MediaQuery.paddingOf(context);
        final currentPos = _position ?? _defaultPosition(size, padding);
        final effectivePos = Offset(
          currentPos.dx + _dragOffset.dx,
          currentPos.dy + _dragOffset.dy,
        );

        final cs = Theme.of(context).colorScheme;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: effectivePos.dx,
              top: effectivePos.dy,
              child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _dragOffset += details.delta;
              });
            },
            onPanEnd: (_) {
              setState(() {
                _position = _clamp(currentPos + _dragOffset, size, padding);
                _dragOffset = Offset.zero;
              });
            },
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: _capsuleWidth,
                height: _capsuleHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF22242A)
                          : Colors.white)
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Waveform (Tap to re-expand full modal)
                    IconButton(
                      tooltip: '展开音频卡片',
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        Lucide.AudioWaveform,
                        color: _audio.isPlaying
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      onPressed: () {
                        if (_audio.activeSource != null) {
                          AudioPreviewModal.show(
                            context,
                            source: _audio.activeSource!,
                            title: _audio.displayName,
                          );
                        }
                      },
                    ),

                    // Play / Pause
                    IconButton(
                      tooltip: _audio.isPlaying ? '暂停' : '播放',
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: Icon(
                        _audio.isPlaying ? Lucide.Pause : Lucide.Play,
                        color: cs.onSurface,
                      ),
                      onPressed: () => _audio.togglePlayPause(),
                    ),

                    // Close (Stop playback & dismiss PiP)
                    IconButton(
                      tooltip: '关闭播放',
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        Lucide.X,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      onPressed: () => _audio.stop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
      },
    );
  }
}
