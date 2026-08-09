import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side wrapper for Apple AVSpeechSynthesizer operations (`app.speech_synthesizer` MethodChannel).
class NativeSpeechSynthesizerService {
  static const _channel = MethodChannel('app.speech_synthesizer');

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Synthesizes text to speech audio and plays it in real-time.
  static Future<Map<String, dynamic>> speak({
    required String text,
    String language = 'zh-CN',
    String? voice,
    double rate = 0.5,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple AVSpeechSynthesizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'speak',
      {
        'text': text,
        'language': language,
        if (voice != null) 'voice': voice,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Synthesizes text and exports to an audio file (.caf / .wav).
  static Future<Map<String, dynamic>> synthesizeToFile({
    required String text,
    String? outputPath,
    String language = 'zh-CN',
    String? voice,
    double rate = 0.5,
    double pitch = 1.0,
  }) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple AVSpeechSynthesizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'synthesizeToFile',
      {
        'text': text,
        if (outputPath != null) 'output_path': outputPath,
        'language': language,
        if (voice != null) 'voice': voice,
        'rate': rate,
        'pitch': pitch,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Returns available system voices on device.
  static Future<Map<String, dynamic>> getVoices({String? language}) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple AVSpeechSynthesizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'getVoices',
      {if (language != null) 'language': language},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Stops current speech playback immediately.
  static Future<Map<String, dynamic>> stop() async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple AVSpeechSynthesizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>('stop');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Pauses current speech playback.
  static Future<Map<String, dynamic>> pause() async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple AVSpeechSynthesizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>('pause');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Resumes paused speech playback.
  static Future<Map<String, dynamic>> continueSpeech() async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple AVSpeechSynthesizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>('continue');
    return Map<String, dynamic>.from(res ?? {});
  }
}
