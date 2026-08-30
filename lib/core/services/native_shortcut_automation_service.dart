import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../utils/app_directories.dart';
import '../../utils/sandbox_path_resolver.dart';
import 'native_user_notification_service.dart';
import 'notification_service.dart';

/// Service for running iOS Shortcuts automations by writing a JSON task file,
/// sending a local notification to trigger Shortcuts, and waiting for the
/// shortcut execution result written back to the task JSON file.
class NativeShortcutAutomationService {
  NativeShortcutAutomationService._();

  static const String _tasksSubdir = 'tasks';
  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const Duration _pollInterval = Duration(milliseconds: 500);

  /// Ensure `Documents/tasks/` directory exists with a placeholder file.
  static Future<Directory> _getTasksDirectory() async {
    final root = await AppDirectories.getAppDataDirectory();
    final tasksDir = Directory('${root.path}/$_tasksSubdir');
    if (!await tasksDir.exists()) {
      await tasksDir.create(recursive: true);
    }
    // Create a placeholder file so iOS Files app indexes the directory
    final placeholder = File('${tasksDir.path}/.placeholder');
    if (!await placeholder.exists()) {
      try {
        await placeholder.writeAsString('Kelivo tasks directory', flush: true);
      } catch (_) {}
    }
    return tasksDir;
  }

  /// Execute a shortcut automation task.
  ///
  /// - [action]: `"list"` or `"exec"`
  /// - [shortcut]: Shortcut name to execute (required when [action] is `"exec"`)
  /// - [taskId]: Task ID (UUID). If omitted or empty, generated automatically.
  /// - [timeout]: Maximum wait duration (defaults to 10 seconds).
  static Future<Map<String, dynamic>> executeTask({
    required String action,
    String? shortcut,
    String? params,
    String? taskId,
    String? notificationTitle,
    String? notificationBody,
    Duration timeout = _defaultTimeout,
  }) async {
    final normalizedAction = action.trim().toLowerCase();
    if (normalizedAction != 'list' && normalizedAction != 'exec') {
      return {
        'error': 'invalid_action',
        'message': 'Parameter "action" must be either "list" or "exec".',
      };
    }

    if (normalizedAction == 'exec' && (shortcut == null || shortcut.trim().isEmpty)) {
      return {
        'error': 'missing_shortcut',
        'message': 'Parameter "shortcut" is required when action is "exec".',
      };
    }

    final effectiveTaskId = (taskId != null && taskId.trim().isNotEmpty)
        ? taskId.trim()
        : const Uuid().v4();
    final effectiveShortcut = (shortcut ?? '').trim();
    final rawParamsStr = (params ?? '').trim();

    dynamic parsedParams = rawParamsStr;
    if (rawParamsStr.startsWith('{') || rawParamsStr.startsWith('[')) {
      try {
        parsedParams = jsonDecode(rawParamsStr);
      } catch (_) {}
    }

    try {
      final tasksDir = await _getTasksDirectory();
      final taskFile = File('${tasksDir.path}/task_$effectiveTaskId.json');

      final initialPayload = <String, dynamic>{
        'taskId': effectiveTaskId,
        'action': normalizedAction,
        'shortcut': effectiveShortcut,
        'params': parsedParams,
        'status': 'pending',
        'result': '',
      };

      await taskFile.writeAsString(
        jsonEncode(initialPayload),
        flush: true,
      );

      final String effectiveTitle = (notificationTitle != null && notificationTitle.trim().isNotEmpty)
          ? notificationTitle.trim()
          : 'Automation Task';

      final String effectiveBody = (notificationBody != null && notificationBody.trim().isNotEmpty)
          ? notificationBody.trim()
          : (normalizedAction == 'list'
              ? 'List all shortcuts'
              : 'Execute shortcut: $effectiveShortcut');

      // Send local notification to trigger iOS Shortcuts automation
      try {
        await NativeUserNotificationService.schedule(
          title: effectiveTitle,
          subtitle: '#$effectiveTaskId',
          body: effectiveBody,
          sound: false,
          id: 'task_$effectiveTaskId',
        );
      } catch (_) {
        try {
          await NotificationService.showChatCompleted(
            title: '$effectiveTitle #$effectiveTaskId',
            body: effectiveBody,
          );
        } catch (_) {}
      }

      // Wait/poll for completed result with timeout
      final result = await _waitForTaskCompletion(
        taskFile: taskFile,
        timeout: timeout,
      );

      return result;
    } catch (e) {
      return {
        'error': 'execution_failed',
        'message': 'Shortcut automation execution failed: $e',
      };
    }
  }

  /// Polls and watches the task JSON file until `status == "completed"` or [timeout] expires.
  static Future<Map<String, dynamic>> _waitForTaskCompletion({
    required File taskFile,
    required Duration timeout,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    StreamSubscription<FileSystemEvent>? watchSubscription;
    Timer? pollTimer;
    Timer? timeoutTimer;

    void cleanup() {
      pollTimer?.cancel();
      timeoutTimer?.cancel();
      watchSubscription?.cancel();
    }

    Future<void> checkFile() async {
      if (completer.isCompleted) return;
      try {
        if (!await taskFile.exists()) return;
        final content = await taskFile.readAsString();
        if (content.trim().isEmpty) return;

        final map = jsonDecode(content) as Map<String, dynamic>;
        final status = (map['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'completed') {
          cleanup();
          completer.complete({
            'success': true,
            'taskId': map['taskId'],
            'action': map['action'],
            'shortcut': map['shortcut'],
            'status': status,
            'result': map['result'] ?? '',
          });
        } else if (status == 'failed' || status == 'error') {
          cleanup();
          completer.complete({
            'success': false,
            'error': 'shortcut_execution_failed',
            'taskId': map['taskId'],
            'action': map['action'],
            'shortcut': map['shortcut'],
            'status': status,
            'result': map['result'] ?? '',
            'message': (map['result'] != null && map['result'].toString().isNotEmpty)
                ? map['result'].toString()
                : 'Shortcut execution failed.',
          });
        }
      } catch (_) {}
    }

    // Set up file watcher
    try {
      final parentDir = taskFile.parent;
      watchSubscription = parentDir.watch(events: FileSystemEvent.modify | FileSystemEvent.create).listen((_) {
        checkFile();
      });
    } catch (e) {
      debugPrint('[NativeShortcutAutomationService] Watch error: $e');
    }

    // Set up interval polling fallback
    pollTimer = Timer.periodic(_pollInterval, (_) {
      checkFile();
    });

    // Set up timeout timer
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        cleanup();
        completer.complete({
          'error': 'timeout',
          'message': 'Shortcut automation timed out waiting for completion (${timeout.inSeconds}s).',
          'taskId': taskFile.path.split('task_').last.replaceAll('.json', ''),
        });
      }
    });

    // Initial check in case it completed synchronously
    await checkFile();

    return completer.future;
  }
}
