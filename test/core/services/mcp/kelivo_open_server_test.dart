import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/mcp/kelivo_open/kelivo_open_server.dart';
import 'package:Kelivo/core/services/preview/resource_preview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kelivo Open MCP Server', () {
    late KelivoOpenMcpServerEngine engine;
    late Directory tempDir;

    setUp(() async {
      engine = KelivoOpenMcpServerEngine();
      tempDir = await Directory.systemTemp.createTemp('kelivo_open_test_');
    });

    tearDown(() async {
      engine.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initializes and advertises kelivo_open tool', () async {
      final initResponse =
          await engine.handleMessage({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
          }) as Map<String, dynamic>;

      final serverInfo =
          (initResponse['result'] as Map<String, dynamic>)['serverInfo']
              as Map<String, dynamic>;
      expect(serverInfo['name'], '@kelivo/open');

      final listResponse =
          await engine.handleMessage({
            'jsonrpc': '2.0',
            'id': 2,
            'method': 'tools/list',
          }) as Map<String, dynamic>;

      final tools =
          (listResponse['result'] as Map<String, dynamic>)['tools'] as List;
      expect(tools, hasLength(1));
      final tool = (tools.single as Map).cast<String, dynamic>();
      expect(tool['name'], 'kelivo_open');
      expect(tool['description'], contains('Open or preview'));

      final schema = (tool['inputSchema'] as Map).cast<String, dynamic>();
      final properties = (schema['properties'] as Map).cast<String, dynamic>();
      expect(properties.containsKey('target'), isTrue);
      expect(properties.containsKey('action'), isTrue);
      expect(properties.containsKey('title'), isTrue);
    });

    test('validates payload arguments', () {
      expect(
        () => KelivoOpenRequestPayload.parse({}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => KelivoOpenRequestPayload.parse({'target': '   '}),
        throwsA(isA<ArgumentError>()),
      );

      final payload = KelivoOpenRequestPayload.parse({
        'target': 'https://example.com',
        'action': 'system_open',
        'title': 'Example Site',
      });
      expect(payload.target, 'https://example.com');
      expect(payload.action, 'system_open');
      expect(payload.title, 'Example Site');
    });

    test('handles file not found gracefully', () async {
      final nonExistentPath = '${tempDir.path}/non_existent_file.png';
      final callResponse =
          await engine.handleMessage({
            'jsonrpc': '2.0',
            'id': 3,
            'method': 'tools/call',
            'params': {
              'name': 'kelivo_open',
              'arguments': {'target': nonExistentPath},
            },
          }) as Map<String, dynamic>;

      final result = callResponse['result'] as Map<String, dynamic>;
      expect(result['isError'], isTrue);
      final content = result['content'] as List;
      final text = (content.first as Map)['text'] as String;
      expect(text, contains('Local file not found'));
    });

    test('preview service handles local text/markdown files', () async {
      final testFile = File('${tempDir.path}/test_doc.md');
      await testFile.writeAsString('# Hello Kelivo\nTesting preview.');

      final res = await ResourcePreviewService.instance.openResource(
        target: testFile.path,
        action: 'in_app_preview',
      );

      expect(res.target, contains('test_doc.md'));
      expect(res.openedAs, isIn(['text_preview', 'system_application']));
    });

    test('preview service resolves kelivo:// URIs', () async {
      final res = await ResourcePreviewService.instance.openResource(
        target: 'kelivo://workspace/test.html',
      );
      // Even if file does not exist, target path is correctly resolved to local path
      expect(res.target, contains('workspace'));
      expect(res.target, contains('test.html'));
      expect(res.openedAs, 'file_not_found');
    });

    test('preview service handles share action for web URLs and local files', () async {
      final webRes = await ResourcePreviewService.instance.openResource(
        target: 'https://flutter.dev',
        action: 'share',
      );
      expect(webRes.success, isTrue);
      expect(webRes.openedAs, 'share_sheet');

      final testFile = File('${tempDir.path}/share_test.png');
      await testFile.writeAsBytes([1, 2, 3]);
      final fileRes = await ResourcePreviewService.instance.openResource(
        target: testFile.path,
        action: 'share',
      );
      expect(fileRes.success, isTrue);
      expect(fileRes.openedAs, 'share_sheet');
    });
  });
}
