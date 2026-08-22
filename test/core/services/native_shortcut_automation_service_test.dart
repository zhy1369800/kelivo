import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/core/services/native_shortcut_automation_service.dart';
import 'package:kelivo/utils/app_directories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeShortcutAutomationService Unit Tests', () {
    late Directory tempDocsDir;

    setUp(() async {
      tempDocsDir = await Directory.systemTemp.createTemp('shortcut_test_');
    });

    tearDown(() async {
      try {
        if (await tempDocsDir.exists()) {
          await tempDocsDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('invalid action returns error', () async {
      final res = await NativeShortcutAutomationService.executeTask(
        action: 'unknown_action',
      );
      expect(res['error'], equals('invalid_action'));
    });

    test('missing shortcut when action is exec returns error', () async {
      final res = await NativeShortcutAutomationService.executeTask(
        action: 'exec',
        shortcut: '   ',
      );
      expect(res['error'], equals('missing_shortcut'));
    });
  });
}
