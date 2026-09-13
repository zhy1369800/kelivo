import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/services/native_shortcut_automation_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kelivo_shortcut_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('executeTask normalizes Map params correctly into task file', () async {
    const taskId = 'test-map-task-1';
    final taskFilePath = '${tempDir.path}/tasks/task_$taskId.json';

    final future = NativeShortcutAutomationService.executeTask(
      action: 'exec',
      shortcut: '停止并输出',
      params: {'msg': '测试输出：一切正常！'},
      taskId: taskId,
      timeout: const Duration(seconds: 2),
    );

    final taskFile = File(taskFilePath);
    var waited = 0;
    while (!await taskFile.exists() && waited < 20) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      waited++;
    }
    expect(await taskFile.exists(), isTrue);

    final content = await taskFile.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    expect(data['taskId'], taskId);
    expect(data['action'], 'exec');
    expect(data['shortcut'], '停止并输出');
    expect(data['params'], isA<Map<String, dynamic>>());
    expect(data['params']['msg'], '测试输出：一切正常！');

    data['status'] = 'completed';
    data['result'] = '执行成功！';
    await taskFile.writeAsString(jsonEncode(data), flush: true);

    final result = await future;
    expect(result['success'], isTrue);
    expect(result['status'], 'completed');
    expect(result['result'], '执行成功！');
  });

  test('executeTask normalizes JSON string params correctly into task file', () async {
    const taskId = 'test-json-str-task-2';
    final taskFilePath = '${tempDir.path}/tasks/task_$taskId.json';

    final future = NativeShortcutAutomationService.executeTask(
      action: 'exec',
      shortcut: '停止并输出',
      params: '{"msg": "测试输出：格式正确，执行成功！"}',
      taskId: taskId,
      timeout: const Duration(seconds: 2),
    );

    final taskFile = File(taskFilePath);
    var waited = 0;
    while (!await taskFile.exists() && waited < 20) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      waited++;
    }
    expect(await taskFile.exists(), isTrue);

    final content = await taskFile.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    expect(data['params'], isA<Map<String, dynamic>>());
    expect(data['params']['msg'], '测试输出：格式正确，执行成功！');

    data['status'] = 'completed';
    data['result'] = '测试输出：格式正确，执行成功！';
    await taskFile.writeAsString(jsonEncode(data), flush: true);

    final result = await future;
    expect(result['success'], isTrue);
    expect(result['result'], '测试输出：格式正确，执行成功！');
  });

  test('executeTask keeps plain text string params as string', () async {
    const taskId = 'test-plain-str-task-3';
    final taskFilePath = '${tempDir.path}/tasks/task_$taskId.json';

    final future = NativeShortcutAutomationService.executeTask(
      action: 'exec',
      shortcut: '纯文本测试',
      params: '简单文本内容',
      taskId: taskId,
      timeout: const Duration(seconds: 2),
    );

    final taskFile = File(taskFilePath);
    var waited = 0;
    while (!await taskFile.exists() && waited < 20) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      waited++;
    }
    expect(await taskFile.exists(), isTrue);

    final content = await taskFile.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    expect(data['params'], '简单文本内容');

    data['status'] = 'completed';
    data['result'] = 'ok';
    await taskFile.writeAsString(jsonEncode(data), flush: true);

    final result = await future;
    expect(result['success'], isTrue);
  });
}
