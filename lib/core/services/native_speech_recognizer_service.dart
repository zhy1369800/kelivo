import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side wrapper for Apple SFSpeechRecognizer operations (`app.speech_recognizer` MethodChannel).
class NativeSpeechRecognizerService {
  static const _channel = MethodChannel('app.speech_recognizer');

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Transcribes an audio file (.m4a, .mp3, .wav, .aac, .caf) to text using SFSpeechRecognizer.
  static Future<Map<String, dynamic>> transcribeFile({
    required String audioPath,
    String locale = 'zh-CN',
    bool forceOffline = true,
  }) async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple SFSpeechRecognizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'transcribeFile',
      {
        'audio_path': audioPath,
        'locale': locale,
        'force_offline': forceOffline,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Returns supported locales on device and their on-device offline STT support status.
  static Future<Map<String, dynamic>> getSupportedLocales() async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple SFSpeechRecognizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>('getLocales');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Requests SFSpeechRecognizer permission authorization.
  static Future<Map<String, dynamic>> requestPermission() async {
    if (!isSupported) {
      return {
        'error': 'platform_not_supported',
        'message': 'Apple SFSpeechRecognizer requires iOS platform.',
      };
    }
    final res = await _channel.invokeMapMethod<String, dynamic>('requestPermission');
    return Map<String, dynamic>.from(res ?? {});
  }
}
