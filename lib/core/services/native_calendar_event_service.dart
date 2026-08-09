import 'package:flutter/services.dart';

/// Dart-side wrapper for EventKit Calendar operations (`app.calendar_event` MethodChannel).
class NativeCalendarEventService {
  static const _channel = MethodChannel('app.calendar_event');

  /// Requests Calendar access permission.
  static Future<Map<String, dynamic>> requestPermission() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('requestPermission');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Lists upcoming calendar events over the next [days].
  static Future<Map<String, dynamic>> listEvents({
    int days = 7,
    String? calendarName,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'listEvents',
      {
        'days': days,
        if (calendarName != null) 'calendar_name': calendarName,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Searches calendar events matching [query] over the past 7 days to next [days].
  static Future<Map<String, dynamic>> searchEvents({
    required String query,
    int days = 30,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'searchEvents',
      {
        'query': query,
        'days': days,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Creates a new event in calendar.
  static Future<Map<String, dynamic>> createEvent({
    required String title,
    String? start,
    String? end,
    String? location,
    String? notes,
    int? alarmMinutes,
    String? calendarName,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'createEvent',
      {
        'title': title,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
        if (location != null) 'location': location,
        if (notes != null) 'notes': notes,
        if (alarmMinutes != null) 'alarm_minutes': alarmMinutes,
        if (calendarName != null) 'calendar_name': calendarName,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Updates an existing calendar event.
  static Future<Map<String, dynamic>> updateEvent({
    required String id,
    String? title,
    String? start,
    String? end,
    String? location,
    String? notes,
    int? alarmMinutes,
    String? calendarName,
    String? span,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'updateEvent',
      {
        'id': id,
        if (title != null) 'title': title,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
        if (location != null) 'location': location,
        if (notes != null) 'notes': notes,
        if (alarmMinutes != null) 'alarm_minutes': alarmMinutes,
        if (calendarName != null) 'calendar_name': calendarName,
        if (span != null) 'span': span,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Deletes a calendar event by its [id].
  static Future<Map<String, dynamic>> deleteEvent({
    required String id,
    String? span,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'deleteEvent',
      {
        'id': id,
        if (span != null) 'span': span,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Lists all system calendar accounts.
  static Future<Map<String, dynamic>> listCalendars() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('listCalendars');
    return Map<String, dynamic>.from(res ?? {});
  }

  /// Analyzes free and busy time slots in the given date range.
  static Future<Map<String, dynamic>> freebusy({
    int days = 1,
    String? start,
    String? end,
  }) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'freebusy',
      {
        'days': days,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
      },
    );
    return Map<String, dynamic>.from(res ?? {});
  }
}
