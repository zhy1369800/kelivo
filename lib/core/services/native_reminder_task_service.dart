import 'package:flutter/services.dart';

/// Dart-side wrapper for EventKit Reminders operations (`app.reminder_task` MethodChannel).
class NativeReminderTaskService {
  static const _channel = MethodChannel('app.reminder_task');

  /// Requests Reminders access permission.
  static Future<Map<String, dynamic>> requestPermission() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('requestPermission');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Lists reminders, optionally filtering by list name or including completed.
  static Future<Map<String, dynamic>> listReminders({
    String? listName,
    bool includeCompleted = false,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'listReminders',
      {
        if (listName != null) 'list_name': listName,
        'include_completed': includeCompleted,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Creates a new reminder task.
  static Future<Map<String, dynamic>> createReminder({
    required String title,
    String? listName,
    String? dueDate,
    int priority = 0,
    String? notes,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'createReminder',
      {
        'title': title,
        if (listName != null) 'list_name': listName,
        if (dueDate != null) 'due_date': dueDate,
        'priority': priority,
        if (notes != null) 'notes': notes,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Marks a reminder task as completed or incomplete.
  static Future<Map<String, dynamic>> completeReminder({
    required String id,
    bool completed = true,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'completeReminder',
      {
        'id': id,
        'completed': completed,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Deletes a reminder task by its [id].
  static Future<Map<String, dynamic>> deleteReminder({
    required String id,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'deleteReminder',
      {'id': id},
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Lists all reminder lists (calendars).
  static Future<Map<String, dynamic>> listLists() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('listLists');
    return Map<String, dynamic>.from(res ?? {});
  }
}
