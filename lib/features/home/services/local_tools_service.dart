import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:math_expressions/math_expressions.dart';

import '../../../core/models/assistant.dart';

typedef TextToSpeechStarter = Future<void> Function(String text);

class LocalToolNames {
  const LocalToolNames._();

  static const String timeInfo = 'get_time_info';
  static const String clipboard = 'clipboard_tool';
  static const String textToSpeech = 'text_to_speech';
  static const String askUser = 'ask_user_input_v0';
  static const String calculate = 'calculate';
  static const String mcpServersTool = 'mcp_servers_tool';
  static const String locationInfo = 'get_location_info';
  static const String mapKit = 'map_kit_tool';
  static const String weatherKit = 'weather_kit_tool';
  static const String bleBridge = 'ble_bridge_tool';
  static const String userNotification = 'user_notification_tool';
  static const String deviceInfo = 'device_info_tool';
  static const String healthKit = 'health_kit_tool';
  static const String calendarEvent = 'calendar_event_tool';
  static const String reminderTask = 'reminder_task_tool';
  static const String alarmTimer = 'alarm_timer_tool';
  static const String appleVision = 'apple_vision_tool';
  static const String speechRecognizer = 'speech_recognizer_tool';
  static const String speechSynthesizer = 'speech_synthesizer_tool';
}

class LocalToolsService {
  const LocalToolsService._();

  static List<Map<String, dynamic>> buildToolDefinitions({
    required Assistant? assistant,
    required bool supportsTools,
  }) {
    if (!supportsTools || assistant == null) {
      return const <Map<String, dynamic>>[];
    }

    final tools = <Map<String, dynamic>>[];
    if (assistant.localToolIds.contains(LocalToolNames.timeInfo)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.timeInfo,
          'description':
              'Get the current local date and time info from the device. Returns year, month, day, weekday, ISO date and time strings, timezone, UTC offset, and timestamp.',
          'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.clipboard)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.clipboard,
          'description':
              'Read or write plain text from the device clipboard. Use action: read or write. For write, provide text. Do NOT write to the clipboard unless the user has explicitly requested it.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': ['read', 'write'],
                'description': 'Operation to perform: read or write',
              },
              'text': {
                'type': 'string',
                'description':
                    'Text to write to the clipboard. Required for write.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.textToSpeech)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.textToSpeech,
          'description':
              'Speak text aloud to the user using the configured text-to-speech playback. Use this when the user asks you to read something aloud, or when audio output is appropriate. The tool returns after playback has been requested; audio may continue in the background. Provide natural, readable text without markdown formatting.',
          'parameters': {
            'type': 'object',
            'properties': {
              'text': {
                'type': 'string',
                'description': 'The text to speak aloud.',
              },
            },
            'required': ['text'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.askUser)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.askUser,
          'description':
              'Ask the user one or more short choice questions when you need clarification, additional information, or a decision before continuing. Supports single-choice and multi-choice questions. The UI will provide Other and Skip options automatically, so do not include those options yourself.',
          'parameters': {
            'type': 'object',
            'properties': {
              'questions': {
                'type': 'array',
                'description': 'One to four questions to ask the user.',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {
                      'type': 'string',
                      'description':
                          'Unique stable identifier for this question.',
                    },
                    'question': {
                      'type': 'string',
                      'description':
                          'The full question text shown to the user.',
                    },
                    'type': {
                      'type': 'string',
                      'enum': ['single', 'multi'],
                      'description':
                          'Answer type: single choice or multi choice.',
                    },
                    'options': {
                      'type': 'array',
                      'description':
                          'Suggested options for the user to choose from.',
                      'items': {'type': 'string'},
                    },
                  },
                  'required': ['id', 'question'],
                },
              },
            },
            'required': ['questions'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.calculate)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.calculate,
          'description':
              'Evaluate a mathematical expression. Supports: + - * / ^ % !, sin() cos() tan() sqrt() ln() abs() floor() ceil() sgn(), log(base, value), constants pi e. Example: "5!", "sin(pi/4)", "log(2, 8)", "floor(3.7)"',
          'parameters': {
            'type': 'object',
            'properties': {
              'expression': {
                'type': 'string',
                'description':
                    'A mathematical expression in standard notation, e.g. "(15 + 3) * 2", "2^10", "sqrt(144)"',
              },
            },
            'required': ['expression'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.locationInfo)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.locationInfo,
          'description':
              'Get device GPS coordinates (latitude, longitude, altitude, accuracy) and reverse-geocoded address (country, state, city, district, street, postal code), OR convert a natural language address into GPS coordinates.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': ['current', 'search'],
                'description':
                    'Operation to perform: "current" (default, get device GPS & reverse geocode address) or "search" (forward geocode a specified address to GPS coordinates).',
              },
              'address': {
                'type': 'string',
                'description':
                    'The address to convert to GPS coordinates. Required when action is "search" (e.g. "West Lake, Hangzhou").',
              },
              'include_address': {
                'type': 'boolean',
                'description':
                    'Used with action "current". Whether to automatically perform reverse geocoding to get human-readable address info. Default is true.',
              },
            },
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.mapKit)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.mapKit,
          'description':
              'MapKit tool for place/POI search, road route planning with turn-by-turn steps, ETA estimation, and opening Apple Maps for navigation. Uses Apple MapKit natively on device — no internet API key required.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': ['search_places', 'get_route', 'get_eta', 'open_navigation'],
                'description':
                    '"search_places": find POIs/places near a location; "get_route": full road route with steps+distance+duration; "get_eta": lightweight ETA only; "open_navigation": launch Apple Maps app for turn-by-turn navigation.',
              },
              'query': {
                'type': 'string',
                'description': 'Search keyword for search_places (e.g. "coffee shop", "故宫").',
              },
              'latitude': {
                'type': 'number',
                'description': 'User or center latitude for search_places context.',
              },
              'longitude': {
                'type': 'number',
                'description': 'User or center longitude for search_places context.',
              },
              'radius_meters': {
                'type': 'number',
                'description': 'Search radius in meters for search_places. Default: 1000.',
              },
              'limit': {
                'type': 'integer',
                'description': 'Max results to return for search_places. Default: 10.',
              },
              'from_address': {
                'type': 'string',
                'description': 'Origin as a text address for route/eta/navigation. Use instead of from_latitude+from_longitude.',
              },
              'from_latitude': {'type': 'number', 'description': 'Origin latitude.'},
              'from_longitude': {'type': 'number', 'description': 'Origin longitude.'},
              'to_address': {
                'type': 'string',
                'description': 'Destination as a text address for route/eta/navigation.',
              },
              'to_latitude': {'type': 'number', 'description': 'Destination latitude.'},
              'to_longitude': {'type': 'number', 'description': 'Destination longitude.'},
              'mode': {
                'type': 'string',
                'enum': ['driving', 'walking', 'transit'],
                'description': 'Transport mode. Default: "driving".',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.weatherKit)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.weatherKit,
          'description':
              'Query real-time current weather, 48-hour hourly forecasts, 10-day daily forecasts, and severe weather alerts using Apple WeatherKit. If location is omitted, the device current location is automatically used.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': ['current', 'forecast', 'alerts'],
                'description':
                    'The operation to perform: "current" (default, real-time weather summary), "forecast" (hourly & 10-day daily forecast), or "alerts" (severe weather alert warnings).',
              },
              'location': {
                'type': 'string',
                'description':
                    'City or place name to query weather for (e.g. "Tokyo", "Hangzhou", "New York"). If omitted, uses device current location.',
              },
              'latitude': {
                'type': 'number',
                'description': 'Target latitude (optional, used if location name is not provided).',
              },
              'longitude': {
                'type': 'number',
                'description': 'Target longitude (optional, used if location name is not provided).',
              },
            },
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.bleBridge)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.bleBridge,
          'description':
              'Bluetooth Low Energy (BLE) tool for scanning nearby devices, connecting to peripherals, discovering GATT services & characteristics, reading values (Hex/Base64/UTF8), and writing values to hardware characteristics.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'status',
                  'scan',
                  'connect',
                  'disconnect',
                  'discover_services',
                  'read',
                  'write'
                ],
                'description':
                    'The operation to perform: "status" (check Bluetooth power state), "scan" (scan nearby BLE devices), "connect" (connect peripheral by UUID), "disconnect" (disconnect peripheral), "discover_services" (list GATT services & characteristics), "read" (read characteristic value), "write" (write data to characteristic).',
              },
              'duration_seconds': {
                'type': 'number',
                'description': 'Scan duration in seconds. Default: 5.',
              },
              'uuid': {
                'type': 'string',
                'description': 'Target peripheral UUID (required for connect, disconnect, discover_services, read, write).',
              },
              'service_uuid': {
                'type': 'string',
                'description': 'Target GATT service UUID (required for read, write).',
              },
              'characteristic_uuid': {
                'type': 'string',
                'description': 'Target GATT characteristic UUID (required for read, write).',
              },
              'value_hex': {
                'type': 'string',
                'description': 'Hexadecimal string value to write (e.g. "0100", "0xFF").',
              },
              'value_string': {
                'type': 'string',
                'description': 'UTF-8 text string value to write.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.userNotification)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.userNotification,
          'description':
              'UserNotifications tool for sending immediate/delayed local notifications & reminders, checking notification settings, querying pending/delivered notifications, and cancelling scheduled notifications.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'settings',
                  'request_permission',
                  'schedule',
                  'pending',
                  'delivered',
                  'cancel'
                ],
                'description':
                    'The operation to perform: "settings" (check permission status), "request_permission" (request notification permission), "schedule" (send immediate/delayed notification), "pending" (list scheduled notifications), "delivered" (list delivered notifications), "cancel" (cancel pending notification).',
              },
              'title': {
                'type': 'string',
                'description': 'Notification title (for schedule).',
              },
              'subtitle': {
                'type': 'string',
                'description': 'Notification subtitle (optional, for schedule).',
              },
              'body': {
                'type': 'string',
                'description': 'Notification message body (for schedule).',
              },
              'after_seconds': {
                'type': 'number',
                'description': 'Delay in seconds before triggering the notification (e.g. 300 for 5 minutes).',
              },
              'at_time': {
                'type': 'string',
                'description': 'Target trigger datetime in ISO 8601 format (e.g. 2026-08-10T18:00:00Z) for schedule action.',
              },
              'sound': {
                'type': 'boolean',
                'description': 'Whether to play default notification sound. Default: true.',
              },
              'id': {
                'type': 'string',
                'description': 'Custom notification ID for schedule or cancel.',
              },
              'all': {
                'type': 'boolean',
                'description': 'Used with cancel action to cancel all pending notifications. Default: false.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.deviceInfo)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.deviceInfo,
          'description':
              'DeviceInfo tool for querying device model (e.g. iPhone16,1), system version, battery level & charging state, free/used disk storage space, CPU core count, RAM, and thermal state.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': ['info', 'battery', 'storage'],
                'description':
                    'The operation to perform: "info" (default, comprehensive device info summary), "battery" (battery level percent & charging state), or "storage" (disk space in GB & bytes).',
              },
            },
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.healthKit)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.healthKit,
          'description':
              'HealthKit tool for querying and logging iOS HealthKit data: step count history, heart rate & resting heart rate, sleep analysis (deep/REM/core/awake), active & basal calories, body weight/height/BMI, water & nutrition, and logging new health samples.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'summary',
                  'request_permission',
                  'query_steps',
                  'query_heart_rate',
                  'query_sleep',
                  'query_energy',
                  'query_body',
                  'query_nutrition',
                  'log_sample'
                ],
                'description':
                    'The operation to perform: "summary" (default, aggregated daily health overview), "request_permission" (request HealthKit read/write permissions), "query_steps" (daily step count), "query_heart_rate" (heart rate samples), "query_sleep" (sleep analysis), "query_energy" (calories burned), "query_body" (weight/height/BMI), "query_nutrition" (water/calories consumed), "log_sample" (write a new sample).',
              },
              'days': {
                'type': 'number',
                'description': 'Number of past days to query for steps or sleep. Default: 7.',
              },
              'limit': {
                'type': 'number',
                'description': 'Limit of samples for heart rate query. Default: 20.',
              },
              'type': {
                'type': 'string',
                'enum': ['steps', 'weight', 'water', 'heart_rate', 'calories'],
                'description': 'Sample type to write when action is "log_sample".',
              },
              'value': {
                'type': 'number',
                'description': 'Numerical value to log (e.g. 1000 for steps, 68.5 for weight in kg, 250 for water in ml). Required for log_sample.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.calendarEvent)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.calendarEvent,
          'description':
              'CalendarEvent tool for querying, searching, creating, and deleting iOS EventKit calendar events.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'list_events',
                  'search_events',
                  'create_event',
                  'update_event',
                  'delete_event',
                  'list_calendars',
                  'freebusy',
                  'request_permission'
                ],
                'description':
                    'The operation to perform: "list_events" (default, list upcoming events), "search_events" (search events by query keyword), "create_event" (create a new event), "update_event" (update an existing event), "delete_event" (delete an event by ID), "list_calendars" (list system calendars), "freebusy" (query free/busy time slots), "request_permission" (request calendar access).',
              },
              'days': {
                'type': 'number',
                'description': 'Number of days to query for list_events, search_events, or freebusy (default: 7 for list, 30 for search, 1 for freebusy).',
              },
              'query': {
                'type': 'string',
                'description': 'Keyword query string for search_events.',
              },
              'title': {
                'type': 'string',
                'description': 'Title for create_event or update_event.',
              },
              'start': {
                'type': 'string',
                'description': 'Start datetime in ISO 8601 format (e.g. 2026-08-10T15:00:00Z) for create_event, update_event, or freebusy.',
              },
              'end': {
                'type': 'string',
                'description': 'End datetime in ISO 8601 format for create_event, update_event, or freebusy.',
              },
              'location': {
                'type': 'string',
                'description': 'Location string for create_event or update_event.',
              },
              'notes': {
                'type': 'string',
                'description': 'Notes or description for create_event or update_event.',
              },
              'alarm_minutes': {
                'type': 'number',
                'description': 'Alarm alert offset in minutes before event start for create_event or update_event.',
              },
              'calendar_name': {
                'type': 'string',
                'description': 'Target calendar name (e.g. "Work", "Personal") for list_events, create_event, or update_event.',
              },
              'id': {
                'type': 'string',
                'description': 'Calendar event ID for update_event or delete_event. Required for update_event and delete_event.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.reminderTask)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.reminderTask,
          'description':
              'ReminderTask tool for querying, creating, completing, and deleting iOS EventKit reminders and task lists.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'list_reminders',
                  'create_reminder',
                  'update_reminder',
                  'complete_reminder',
                  'delete_reminder',
                  'list_lists',
                  'request_permission'
                ],
                'description':
                    'The operation to perform: "list_reminders" (default, query to-do items), "create_reminder" (create a new reminder with optional due_date alarm), "update_reminder" (update title, due_date, list, priority, or notes of existing reminder), "complete_reminder" (mark a reminder as complete or incomplete), "delete_reminder" (delete a reminder by ID), "list_lists" (list reminder categories/lists), "request_permission" (request Reminders access).',
              },
              'list_name': {
                'type': 'string',
                'description': 'Reminder list name for filtering in list_reminders or targeting in create_reminder/update_reminder.',
              },
              'include_completed': {
                'type': 'boolean',
                'description': 'Whether to include completed items in list_reminders. Default: false.',
              },
              'title': {
                'type': 'string',
                'description': 'Title for create_reminder or update_reminder.',
              },
              'due_date': {
                'type': 'string',
                'description': 'Due date in ISO 8601 format (e.g. 2026-08-10T18:00:00Z) for create_reminder or update_reminder. Automatically sets system alarm at due time.',
              },
              'priority': {
                'type': 'number',
                'description': 'Priority (0: none, 1-4: high/medium/low) for create_reminder or update_reminder.',
              },
              'notes': {
                'type': 'string',
                'description': 'Notes or description for create_reminder or update_reminder.',
              },
              'id': {
                'type': 'string',
                'description': 'Reminder ID for update_reminder, complete_reminder, or delete_reminder. Required for update_reminder, complete_reminder, delete_reminder.',
              },
              'completed': {
                'type': 'boolean',
                'description': 'Completion status for complete_reminder or update_reminder.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.alarmTimer)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.alarmTimer,
          'description':
              'AlarmTimer tool for setting alarms for specific times, setting countdown timers, listing pending timers/alarms, and cancelling pending alarms/timers.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'set_alarm',
                  'set_timer',
                  'list',
                  'cancel',
                  'request_permission'
                ],
                'description':
                    'The operation to perform: "set_alarm" (set alarm at specific HH:MM time), "set_timer" (set countdown timer), "list" (list pending alarms and timers), "cancel" (cancel alarm/timer by ID or all), "request_permission" (request permissions).',
              },
              'time': {
                'type': 'string',
                'description': 'Alarm time in HH:MM (e.g. "07:30") or ISO string for set_alarm. Required for set_alarm.',
              },
              'label': {
                'type': 'string',
                'description': 'Label or title description for the alarm or timer.',
              },
              'repeat': {
                'type': 'string',
                'enum': ['none', 'daily', 'weekdays'],
                'description': 'Repeat frequency for set_alarm. Default: "none".',
              },
              'duration_seconds': {
                'type': 'number',
                'description': 'Countdown duration in seconds for set_timer (e.g. 300 for 5 minutes).',
              },
              'duration': {
                'type': 'string',
                'description': 'Shorthand countdown duration for set_timer (e.g. "5m", "1h", "30s").',
              },
              'id': {
                'type': 'string',
                'description': 'Alarm or timer ID for cancel. Required for cancel unless "all" is true.',
              },
              'all': {
                'type': 'boolean',
                'description': 'Whether to cancel all pending alarms and timers when action is "cancel". Default: false.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.appleVision)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.appleVision,
          'description':
              'Apple Vision Framework tool for on-device fast OCR text recognition, QR/barcode scanning, face detection, and image classification.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'ocr',
                  'detect_barcodes',
                  'detect_faces',
                  'classify_image',
                  'analyze_all'
                ],
                'description':
                    'The operation to perform: "ocr" (recognize text in image), "detect_barcodes" (detect QR codes & barcodes), "detect_faces" (detect face boxes & landmarks), "classify_image" (classify image category tags), "analyze_all" (run all vision analyses in a single pass).',
              },
              'image_path': {
                'type': 'string',
                'description': 'Absolute local file path to the image file to analyze. Required.',
              },
              'languages': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'Languages array for OCR (e.g. ["zh-Hans", "en-US"]). Optional.',
              },
              'accurate': {
                'type': 'boolean',
                'description': 'Whether to use high-accuracy mode for OCR. Default: true.',
              },
              'include_landmarks': {
                'type': 'boolean',
                'description': 'Whether to include facial landmark points count for face detection. Default: false.',
              },
              'max_results': {
                'type': 'number',
                'description': 'Maximum number of tags to return for classify_image. Default: 10.',
              },
            },
            'required': ['action', 'image_path'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.speechRecognizer)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.speechRecognizer,
          'description':
              'Apple SFSpeechRecognizer tool for on-device offline speech-to-text (STT) transcription of audio files, checking supported locales, and requesting permissions.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'transcribe_file',
                  'get_locales',
                  'request_permission'
                ],
                'description':
                    'The operation to perform: "transcribe_file" (transcribe local audio file to text), "get_locales" (list supported languages and on-device offline status), "request_permission" (request speech recognition permission).',
              },
              'audio_path': {
                'type': 'string',
                'description': 'Absolute local file path to the audio file (.m4a, .mp3, .wav, .aac, .caf) to transcribe. Required for transcribe_file.',
              },
              'locale': {
                'type': 'string',
                'description': 'Locale identifier for recognition (e.g. "zh-CN", "en-US", "zh-HK", "ja-JP"). Default: "zh-CN".',
              },
              'force_offline': {
                'type': 'boolean',
                'description': 'Whether to force 100% on-device offline recognition without network calls. Default: true.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.speechSynthesizer)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.speechSynthesizer,
          'description':
              'Apple AVSpeechSynthesizer tool for on-device offline text-to-speech (TTS) playback, audio file synthesis export, voice query, and speech playback controls.',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'speak',
                  'synthesize_to_file',
                  'get_voices',
                  'stop',
                  'pause',
                  'continue'
                ],
                'description':
                    'The operation to perform: "speak" (real-time offline speech playback), "synthesize_to_file" (render text speech to audio file), "get_voices" (list system voices and Enhanced/Premium quality), "stop" (stop playback), "pause" (pause playback), "continue" (resume playback).',
              },
              'text': {
                'type': 'string',
                'description': 'Text content to speak or synthesize to file. Required for speak and synthesize_to_file.',
              },
              'language': {
                'type': 'string',
                'description': 'Language code (e.g. "zh-CN", "en-US", "zh-HK", "ja-JP"). Default: "zh-CN".',
              },
              'voice': {
                'type': 'string',
                'description': 'Specific voice identifier or name to use. Optional.',
              },
              'rate': {
                'type': 'number',
                'description': 'Speech rate from 0.0 to 1.0. Default: 0.5.',
              },
              'pitch': {
                'type': 'number',
                'description': 'Pitch multiplier from 0.5 to 2.0. Default: 1.0.',
              },
              'volume': {
                'type': 'number',
                'description': 'Volume from 0.0 to 1.0. Default: 1.0.',
              },
              'output_path': {
                'type': 'string',
                'description': 'Custom output audio file path for synthesize_to_file. Optional.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.mcpServersTool)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.mcpServersTool,
          'description':
              'Manage and install MCP (Model Context Protocol) servers and their tools. Supports: "list" (show all servers & tools with binding status), "install" (add new server & auto-bind), "toggle_server" (enable/disable server globally OR bind/unbind to current chat via bind_to_current), "toggle_tool" (enable/disable specific tool under a server globally), "edit" (update name, url, headers), and "remove" (delete disabled server).',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'list',
                  'install',
                  'toggle_server',
                  'toggle_tool',
                  'edit',
                  'remove'
                ],
                'description':
                    'The operation to perform: list, install, toggle_server, toggle_tool, edit, or remove.',
              },
              'server_id': {
                'type': 'string',
                'description':
                    'Target MCP server ID. Required for toggle_server, toggle_tool, edit, and remove.',
              },
              'enabled': {
                'type': 'boolean',
                'description':
                    'Target status boolean. Used with toggle_server (for global enable/disable) or toggle_tool (for tool enable/disable). Note: Disabling a tool via toggle_tool is a global change for that server.',
              },
              'bind_to_current': {
                'type': 'boolean',
                'description':
                    'Used with action "toggle_server" to bind (true) or unbind (false) the server to/from the current assistant and conversation. Can ONLY be used on globally enabled servers.',
              },
              'tool_name': {
                'type': 'string',
                'description':
                    'Target tool name under the server. Required for action "toggle_tool".',
              },
              'name': {
                'type': 'string',
                'description':
                    'Display name or search keyword for the MCP server. Required for "install", optional for "edit", or used to filter servers by name/ID when action is "list".',
              },
              'url': {
                'type': 'string',
                'description':
                    'Remote endpoint URL of the MCP server. Required for "install", optional for "edit".',
              },
              'headers': {
                'type': 'object',
                'description':
                    'Optional HTTP headers map, e.g. {"Authorization": "Bearer token"}. Used for "install" and "edit".',
              },
              'transport': {
                'type': 'string',
                'enum': ['sse', 'http'],
                'description':
                    'Transport protocol ("sse" or "http") used for "install". Only specify if user explicitly mentions it; otherwise OMIT this parameter completely.',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    return tools;
  }

  static Future<String?> tryHandleToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant, {
    TextToSpeechStarter? onSpeakText,
  }) async {
    if (assistant == null || !assistant.localToolIds.contains(name)) {
      return null;
    }
    if (name == LocalToolNames.timeInfo) {
      return jsonEncode(_buildTimeInfoPayload(DateTime.now()));
    }
    if (name == LocalToolNames.clipboard) {
      return _handleClipboardTool(args);
    }
    if (name == LocalToolNames.textToSpeech) {
      return _handleTextToSpeechTool(args, onSpeakText);
    }
    if (name == LocalToolNames.calculate) {
      return _handleCalculateTool(args);
    }
    return null;
  }

  static Future<String> _handleClipboardTool(Map<String, dynamic> args) async {
    final action = (args['action'] ?? '').toString();
    switch (action) {
      case 'read':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return jsonEncode({'text': data?.text ?? ''});
      case 'write':
        final text = args['text']?.toString();
        if (text == null) {
          throw ArgumentError('text is required for clipboard write');
        }
        await Clipboard.setData(ClipboardData(text: text));
        return jsonEncode({'success': true, 'text': text});
      default:
        throw ArgumentError('unknown clipboard action: $action');
    }
  }

  static Future<String> _handleTextToSpeechTool(
    Map<String, dynamic> args,
    TextToSpeechStarter? onSpeakText,
  ) async {
    final text = args['text']?.toString().trim();
    if (text == null || text.isEmpty) {
      throw ArgumentError('text is required for text_to_speech');
    }
    if (onSpeakText == null) {
      throw StateError('text-to-speech executor is unavailable');
    }
    await onSpeakText(text);
    return jsonEncode({'success': true});
  }

  static Map<String, dynamic> _buildTimeInfoPayload(DateTime now) {
    final offset = now.timeZoneOffset;
    final offsetSign = offset.isNegative ? '-' : '+';
    final offsetAbs = offset.abs();
    final offsetHours = offsetAbs.inHours.toString().padLeft(2, '0');
    final offsetMinutes = (offsetAbs.inMinutes % 60).toString().padLeft(2, '0');

    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    final weekdayEn = _englishWeekdayName(now.weekday);

    return <String, dynamic>{
      'year': now.year,
      'month': now.month,
      'day': now.day,
      'weekday': weekdayEn,
      'weekday_en': weekdayEn,
      'weekday_index': now.weekday,
      'date': '$year-$month-$day',
      'time': '$hour:$minute:$second',
      'datetime': now.toIso8601String(),
      'timezone': now.timeZoneName,
      'utc_offset': '$offsetSign$offsetHours:$offsetMinutes',
      'timestamp_ms': now.millisecondsSinceEpoch,
    };
  }

  static String _englishWeekdayName(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Monday',
      DateTime.tuesday => 'Tuesday',
      DateTime.wednesday => 'Wednesday',
      DateTime.thursday => 'Thursday',
      DateTime.friday => 'Friday',
      DateTime.saturday => 'Saturday',
      DateTime.sunday => 'Sunday',
      _ => 'Unknown',
    };
  }

  static String _handleCalculateTool(Map<String, dynamic> args) {
    final expression = (args['expression'] ?? '').toString().trim();
    if (expression.isEmpty) {
      return jsonEncode({
        'error': 'empty_expression',
        'message': 'Expression is empty. Please provide a mathematical expression in standard notation, e.g. "(15 + 3) * 2".',
      });
    }

    try {
      final parsed = GrammarParser().parse(expression);
      final result = parsed.evaluate(EvaluationType.REAL, ContextModel());
      if (!result.isFinite) {
        return jsonEncode({
          'error': 'math_error',
          'message': 'The result is not a finite number. Please check your expression (e.g. division by zero).',
        });
      }
      return jsonEncode({
        'expression': expression,
        'result': result.toString(),
      });
    } catch (e) {
      return jsonEncode({
        'error': 'parse_error',
        'message': 'Could not parse the expression. Use standard notation, e.g. "(15 + 3) * 2".',
        'detail': e.toString(),
      });
    }
  }
}
