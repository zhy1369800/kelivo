import 'package:flutter/services.dart';

/// Dart-side wrapper for EventKit Reminders operations (`app.reminder_task` MethodChannel).
class NativeReminderTaskService {
  static const _channel = MethodChannel('app.reminder_task');

  /// Requests Reminders access permission.
  static Future<Map<String, dynamic>> requestPermission() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('requestPermission');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Requests Location permission (needed for geofence reminders).
  static Future<Map<String, dynamic>> requestLocationPermission() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('requestLocationPermission');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Lists reminders, optionally filtering by list name, limit, or including completed.
  static Future<Map<String, dynamic>> listReminders({
    String? listName,
    bool includeCompleted = false,
    int? limit,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'listReminders',
      {
        if (listName != null) 'list_name': listName,
        'include_completed': includeCompleted,
        if (limit != null) 'limit': limit,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Creates a new reminder task.
  /// Supports time-based due dates, geofence location alarms, and recurrence rules.
  static Future<Map<String, dynamic>> createReminder({
    required String title,
    String? listName,
    String? dueDate,
    int priority = 0,
    String? notes,
    String? parentId,
    // Geofence
    double? lat,
    double? lng,
    String? locationName,
    double? radius,
    String? proximity, // "enter" | "leave"
    // Recurrence
    String? recur, // "daily" | "weekly" | "monthly" | "yearly"
    int? recurInterval,
    String? recurDays, // comma-separated: "mon,wed,fri"
    int? recurCount,
    String? recurUntil, // ISO 8601
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'createReminder',
      {
        'title': title,
        if (listName != null) 'list_name': listName,
        if (dueDate != null) 'due_date': dueDate,
        'priority': priority,
        if (notes != null) 'notes': notes,
        if (parentId != null) 'parent_id': parentId,
        // Geofence
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (locationName != null) 'location_name': locationName,
        if (radius != null) 'radius': radius,
        if (proximity != null) 'proximity': proximity,
        // Recurrence
        if (recur != null) 'recur': recur,
        if (recurInterval != null) 'recur_interval': recurInterval,
        if (recurDays != null) 'recur_days': recurDays,
        if (recurCount != null) 'recur_count': recurCount,
        if (recurUntil != null) 'recur_until': recurUntil,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Updates an existing reminder task.
  /// Supports time-based due dates, geofence location alarms, and recurrence rules.
  static Future<Map<String, dynamic>> updateReminder({
    required String id,
    String? title,
    String? listName,
    String? dueDate,
    int? priority,
    String? notes,
    bool? completed,
    // Geofence
    double? lat,
    double? lng,
    String? locationName,
    double? radius,
    String? proximity,
    bool clearLocation = false,
    // Recurrence
    String? recur,
    int? recurInterval,
    String? recurDays,
    int? recurCount,
    String? recurUntil,
    bool clearRecur = false,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'updateReminder',
      {
        'id': id,
        if (title != null) 'title': title,
        if (listName != null) 'list_name': listName,
        if (dueDate != null) 'due_date': dueDate,
        if (priority != null) 'priority': priority,
        if (notes != null) 'notes': notes,
        if (completed != null) 'completed': completed,
        // Geofence
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (locationName != null) 'location_name': locationName,
        if (radius != null) 'radius': radius,
        if (proximity != null) 'proximity': proximity,
        if (clearLocation) 'clear_location': true,
        // Recurrence
        if (recur != null) 'recur': recur,
        if (recurInterval != null) 'recur_interval': recurInterval,
        if (recurDays != null) 'recur_days': recurDays,
        if (recurCount != null) 'recur_count': recurCount,
        if (recurUntil != null) 'recur_until': recurUntil,
        if (clearRecur) 'clear_recur': true,
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
