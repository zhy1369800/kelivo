import 'dart:async';
import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/memory_provider_v2.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/services/memory/memory_pipeline.dart';
import '../../../core/services/memory/memory_prompts.dart';
import '../../../core/services/memory/memory_tools.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../core/models/system_permission_policy.dart';
import '../../../core/services/native_map_kit_service.dart';
import '../../../core/services/native_weather_kit_service.dart';
import '../../../core/services/native_ble_bridge_service.dart';
import '../../../core/services/native_user_notification_service.dart';
import '../../../core/services/native_device_info_service.dart';
import '../../../core/services/native_health_kit_service.dart';
import '../../../core/services/native_calendar_event_service.dart';
import '../../../core/services/native_reminder_task_service.dart';
import '../../../core/services/native_alarm_timer_service.dart';
import '../../../core/services/native_apple_vision_service.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../core/services/native_speech_recognizer_service.dart';
import '../../../core/services/native_speech_synthesizer_service.dart';
import '../../../core/services/native_shortcut_automation_service.dart';
import 'ask_user_interaction_service.dart';
import 'built_in_tool_names.dart';
import 'local_tools_service.dart';
import 'tool_approval_service.dart';

/// 工具调用处理服务
///
/// 处理各类工具调用：
/// - MCP 工具
/// - Memory 工具 (§10)
/// - Search 工具
class ToolHandlerService {
  ToolHandlerService({required this.contextProvider});

  /// Build context (used for accessing providers)
  final BuildContext contextProvider;

  // ============================================================================
  // Tool Schema Sanitization
  // ============================================================================

  /// Sanitize/translate JSON Schema to each provider's accepted subset.
  ///
  /// Different providers (Google, OpenAI, Claude) have different requirements
  /// for tool parameter schemas. This method normalizes schemas to work across
  /// all providers.
  static Map<String, dynamic> sanitizeToolParametersForProvider(
    Map<String, dynamic> schema,
    ProviderKind kind,
  ) {
    Map<String, dynamic> clone = _deepCloneMap(schema);
    clone = _sanitizeNode(clone, kind) as Map<String, dynamic>;
    return clone;
  }

  static dynamic _sanitizeNode(dynamic node, ProviderKind kind) {
    if (node is List) {
      return node.map((e) => _sanitizeNode(e, kind)).toList();
    }
    if (node is! Map) return node;

    final m = Map<String, dynamic>.from(node);
    // Remove $schema as it's not needed for tool definitions
    m.remove(r'$schema');

    // Convert 'const' to 'enum' for compatibility
    if (m.containsKey('const')) {
      final v = m['const'];
      if (v is String || v is num || v is bool) {
        m['enum'] = [v];
        // Keep the declared type in sync so a non-string const is not mistaken
        // for a string enum downstream.
        if (m['type'] == null) {
          if (v is bool) {
            m['type'] = 'boolean';
          } else if (v is int) {
            m['type'] = 'integer';
          } else if (v is num) {
            m['type'] = 'number';
          } else {
            m['type'] = 'string';
          }
        }
      }
      m.remove('const');
    }

    // Flatten anyOf/oneOf/allOf to first variant for simplicity
    for (final key in [
      'anyOf',
      'oneOf',
      'allOf',
      'any_of',
      'one_of',
      'all_of',
    ]) {
      if (m[key] is List && (m[key] as List).isNotEmpty) {
        final first = (m[key] as List).first;
        final flattened = _sanitizeNode(first, kind);
        m.remove(key);
        if (flattened is Map<String, dynamic>) {
          m
            ..remove('type')
            ..remove('properties')
            ..remove('items');
          m.addAll(flattened);
        }
      }
    }

    // Normalize type array to single type
    final t = m['type'];
    if (t is List && t.isNotEmpty) m['type'] = t.first.toString();

    // Normalize items array to single item
    final items = m['items'];
    if (items is List && items.isNotEmpty) m['items'] = items.first;
    if (m['items'] is Map) m['items'] = _sanitizeNode(m['items'], kind);

    // Recursively sanitize properties
    if (m['properties'] is Map) {
      final props = Map<String, dynamic>.from(m['properties']);
      final norm = <String, dynamic>{};
      props.forEach((k, v) {
        norm[k] = _sanitizeNode(v, kind);
      });
      m['properties'] = norm;
    }

    // additionalProperties can itself be a schema.
    if (m['additionalProperties'] is Map) {
      m['additionalProperties'] = _sanitizeNode(
        m['additionalProperties'],
        kind,
      );
    }

    // Keep only allowed keys based on provider
    Set<String> allowed;
    switch (kind) {
      case ProviderKind.google:
        allowed = {
          'type',
          'description',
          'properties',
          'required',
          'items',
          'enum',
        };
        break;
      case ProviderKind.openai:
      case ProviderKind.claude:
        allowed = {
          'type',
          'description',
          'properties',
          'required',
          'items',
          'enum',
          'additionalProperties',
        };
        break;
    }
    m.removeWhere((k, v) => !allowed.contains(k));
    return m;
  }

  static Map<String, dynamic> _deepCloneMap(Map<String, dynamic> input) {
    return jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
  }

  static String _toolError({
    required String error,
    required String message,
    required String tool,
    String? instruction,
  }) {
    return jsonEncode({
      'type': 'tool_error',
      'error': error,
      'message': message,
      'tool': tool,
      if (instruction != null) 'instruction': instruction,
    });
  }

  // ============================================================================
  // Tool Definitions Builder
  // ============================================================================

  McpToolRouteSnapshot captureMcpToolRoutes(Assistant? assistant) {
    return contextProvider.read<McpToolService>().captureRoutesForAssistant(
      contextProvider.read<McpProvider>(),
      contextProvider.read<AssistantProvider>(),
      assistantId: assistant?.id,
      reservedNames: BuiltInToolNames.all,
    );
  }

  /// Build tool definitions for API call.
  ///
  /// Returns a list of tool definitions including:
  /// - Search tool (if enabled and model supports tools)
  /// - Memory tools (if assistant has memory / past-recall enabled)
  /// - MCP tools (from selected servers for the assistant)
  /// Whether the chat being generated is a throwaway one.
  ///
  /// Tool definitions are built without a conversation id, so this reads the
  /// active conversation the same way the tool handler does.
  bool _isTemporaryConversation() {
    try {
      final chatService = contextProvider.read<ChatService>();
      return chatService.isTemporaryConversation(
        chatService.currentConversationId,
      );
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> buildToolDefinitions(
    SettingsProvider settings,
    Assistant? assistant,
    String providerKey,
    String modelId,
    bool hasBuiltInSearch, {
    required bool Function(String providerKey, String modelId) isToolModel,
    McpToolRouteSnapshot? mcpRouteSnapshot,
  }) {
    final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
    final supportsTools = isToolModel(providerKey, modelId);

    // Search tool (skip when Gemini built-in search is active)
    if (assistant?.searchEnabled == true &&
        !hasBuiltInSearch &&
        supportsTools) {
      toolDefs.add(SearchToolService.getToolDefinition());
    }

    // Memory tools (§10.1)
    if (settings.legacyMemoryMode) {
      if (assistant?.enableMemory == true && supportsTools) {
        toolDefs.addAll(
          _buildLegacyMemoryToolDefinitions(settings.resolvedMemoryPromptLang),
        );
      }
    } else if (supportsTools && assistant != null) {
      toolDefs.addAll(
        MemoryTools.buildDefinitions(
          lang: settings.resolvedMemoryPromptLang,
          writeScope: assistant.memoryWriteScope,
          enableMemory: assistant.enableMemory,
          allowPastConversationRecall: assistant.allowPastConversationRecall,
          allowMemoryWrites: !_isTemporaryConversation(),
        ),
      );
    }

    // Local tools
    toolDefs.addAll(
      LocalToolsService.buildToolDefinitions(
        assistant: assistant,
        supportsTools: supportsTools,
      ),
    );

    // MCP tools
    final mcpTools = _buildMcpToolDefinitions(
      settings: settings,
      assistant: assistant,
      providerKey: providerKey,
      supportsTools: supportsTools,
      mcpRouteSnapshot: mcpRouteSnapshot,
    );
    toolDefs.addAll(mcpTools);

    return toolDefs;
  }

  /// Legacy create/edit/delete_memory tool schemas (pre-v2 memory system).
  ///
  /// Localised by [lang] like [MemoryTools.buildDefinitions], so the schemas
  /// match the language the legacy rules are sent in.
  List<Map<String, dynamic>> _buildLegacyMemoryToolDefinitions(
    MemoryPromptLang lang,
  ) {
    final zh = lang == MemoryPromptLang.zh;
    return [
      {
        'type': 'function',
        'function': {
          'name': 'create_memory',
          'description': zh ? '新增一条记忆记录。' : 'Create a memory record.',
          'parameters': {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': zh
                    ? '记忆记录的内容。'
                    : 'The content of the memory record.',
              },
            },
            'required': ['content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'edit_memory',
          'description': zh
              ? '更新一条已有的记忆记录。'
              : 'Update an existing memory record.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': zh
                    ? '记忆记录的 id。'
                    : 'The id of the memory record.',
              },
              'content': {
                'type': 'string',
                'description': zh
                    ? '记忆记录的内容。'
                    : 'The content of the memory record.',
              },
            },
            'required': ['id', 'content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'delete_memory',
          'description': zh ? '删除一条记忆记录。' : 'Delete a memory record.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': zh
                    ? '记忆记录的 id。'
                    : 'The id of the memory record.',
              },
            },
            'required': ['id'],
          },
        },
      },
    ];
  }

  /// Build MCP tool definitions from connected servers.
  List<Map<String, dynamic>> _buildMcpToolDefinitions({
    required SettingsProvider settings,
    required Assistant? assistant,
    required String providerKey,
    required bool supportsTools,
    McpToolRouteSnapshot? mcpRouteSnapshot,
  }) {
    if (!supportsTools) return [];

    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    final tools = toolSvc.listAvailableToolsForAssistant(
      mcp,
      contextProvider.read<AssistantProvider>(),
      assistant?.id,
      routeSnapshot: mcpRouteSnapshot,
      reservedNames: BuiltInToolNames.all,
    );

    if (tools.isEmpty) return [];

    final providerCfg = settings.getProviderConfig(providerKey);
    final providerKind = ProviderConfig.classify(
      providerCfg.id,
      explicitType: providerCfg.providerType,
    );

    return tools.map((t) {
      Map<String, dynamic> baseSchema;
      if (t.schema != null && t.schema!.isNotEmpty) {
        baseSchema = Map<String, dynamic>.from(t.schema!);
      } else {
        final props = <String, dynamic>{
          for (final p in t.params) p.name: {'type': (p.type ?? 'string')},
        };
        final required = [
          for (final p in t.params.where((e) => e.required)) p.name,
        ];
        baseSchema = {
          'type': 'object',
          'properties': props,
          if (required.isNotEmpty) 'required': required,
        };
      }
      final sanitized = sanitizeToolParametersForProvider(
        baseSchema,
        providerKind,
      );
      return {
        'type': 'function',
        'function': {
          'name': t.name,
          if ((t.description ?? '').isNotEmpty) 'description': t.description,
          'parameters': sanitized,
        },
      };
    }).toList();
  }

  // ============================================================================
  // Tool Call Handler
  // ============================================================================

  /// Build tool call handler function.
  ///
  /// Returns a function that handles tool calls by name and arguments.
  /// Supports:
  /// - Search tool calls
  /// - Memory tool calls (§10)
  /// - MCP tool calls
  ToolCallHandler? buildToolCallHandler(
    SettingsProvider settings,
    Assistant? assistant, {
    ToolApprovalService? approvalService,
    AskUserInteractionService? askUserService,
    String? conversationId,
    McpToolRouteSnapshot? mcpRouteSnapshot,
  }) {
    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    // Capture AssistantProvider reference before async gap to avoid
    // use_build_context_synchronously warning
    final assistantProvider = contextProvider.read<AssistantProvider>();
    final routes =
        mcpRouteSnapshot ??
        toolSvc.captureRoutesForAssistant(
          mcp,
          assistantProvider,
          assistantId: assistant?.id,
          reservedNames: BuiltInToolNames.all,
        );

    Future<String> approveAndExecuteMcp(
      String name,
      Map<String, dynamic> args,
    ) async {
      if (approvalService != null &&
          toolSvc.toolNeedsApprovalForAssistant(
            mcp,
            assistantProvider,
            assistantId: assistant?.id,
            toolName: name,
            routeSnapshot: routes,
            reservedNames: BuiltInToolNames.all,
          )) {
        // Generate a unique id for this tool call approval request
        final toolCallId = '${name}_${DateTime.now().microsecondsSinceEpoch}';
        final result = await approvalService.requestApproval(
          toolCallId: toolCallId,
          toolName: name,
          arguments: args,
          conversationId: conversationId,
        );
        if (!result.approved) {
          return _toolError(
            error: 'approval_denied',
            message: result.denyReason ?? 'User denied the tool call',
            tool: name,
          );
        }
      }

      final text = await toolSvc.callToolTextForAssistant(
        mcp,
        assistantProvider,
        assistantId: assistant?.id,
        toolName: name,
        arguments: args,
        routeSnapshot: routes,
        reservedNames: BuiltInToolNames.all,
      );
      return text;
    }

    return (name, args, {toolCallId}) async {
      try {
        if (routes.containsExposedName(name)) {
          return await approveAndExecuteMcp(name, args);
        }

        // Search tool
        if (name == SearchToolService.toolName &&
            assistant?.searchEnabled == true) {
          final q = (args['query'] ?? '').toString();
          return await SearchToolService.executeSearch(q, settings);
        }

        // Memory tools
        final memoryResult = await _handleMemoryToolCall(
          name,
          args,
          assistant,
          conversationId: conversationId,
        );
        if (memoryResult != null) {
          return memoryResult;
        }

         // Creating calendar events modifies user data, so it always requires
         // explicit user approval before the local tool runs.
         if (name == LocalToolNames.calendarCreate &&
             assistant != null &&
             assistant.localToolIds.contains(LocalToolNames.calendarCreate) &&
             approvalService != null) {
           final approvalId = (toolCallId?.trim().isNotEmpty == true)
               ? toolCallId!.trim()
               : '${name}_${DateTime.now().microsecondsSinceEpoch}';
           final approval = await approvalService.requestApproval(
             toolCallId: approvalId,
             toolName: name,
             arguments: args,
             conversationId: conversationId,
           );
           if (!approval.approved) {
             return _toolError(
               error: 'approval_denied',
               message: approval.denyReason ?? 'User denied the tool call',
               tool: name,
             );
           }
         }
 
        // Local tools
        final localResult = await LocalToolsService.tryHandleToolCall(
          name,
          args,
          assistant,
          onSpeakText: (text) async {
            final tts = contextProvider.read<TtsProvider>();
            if (!tts.isAvailable) {
              throw StateError('Text-to-speech is unavailable.');
            }
            unawaited(
              tts.speak(text).catchError((Object error, StackTrace stack) {
                FlutterError.reportError(
                  FlutterErrorDetails(
                    exception: error,
                    stack: stack,
                    library: 'Kelivo local tools',
                    context: ErrorDescription('while playing text-to-speech'),
                  ),
                );
              }),
            );
          },
        );
        if (localResult != null) {
          return localResult;
        }

        if (name == LocalToolNames.askUser &&
            assistant != null &&
            assistant.localToolIds.contains(LocalToolNames.askUser)) {
          if (askUserService == null) {
            return _toolError(
              error: 'ask_user_unavailable',
              message: 'Ask user interaction service is unavailable.',
              tool: name,
            );
          }
          try {
            final result = await askUserService.requestAnswer(
              toolCallId: (toolCallId?.trim().isNotEmpty == true)
                  ? toolCallId!.trim()
                  : '${name}_${DateTime.now().microsecondsSinceEpoch}',
              arguments: args,
              conversationId: conversationId,
            );
            return result.toJsonString();
          } on AskUserInvalidRequestException catch (e) {
            return _toolError(
              error: 'invalid_ask_user_request',
              message: e.message,
              tool: name,
            );
          }
        }

        // Handle mcp_servers_tool
        if (name == LocalToolNames.mcpServersTool) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.mcpServersTool)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The mcp_servers_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final action = (args['action'] ?? '').toString().trim().toLowerCase();
          // Gate all write actions (everything except list) with user approval
          if (action != 'list' && approvalService != null) {
            final toolCallId =
                '${name}_${DateTime.now().microsecondsSinceEpoch}';
            final result = await approvalService.requestApproval(
              toolCallId: toolCallId,
              toolName: name,
              arguments: args,
              conversationId: conversationId,
            );
            if (!result.approved) {
              return _toolError(
                error: 'approval_denied',
                message:
                    result.denyReason ?? 'User denied the MCP management request.',
                tool: name,
              );
            }
          }
          return await _handleMcpServersTool(
            args: args,
            assistant: assistant,
            conversationId: conversationId,
          );
        }

        // Helper function to check system framework permission policy (bypass / ask / deny)
        Future<ToolApprovalResult> checkSystemPermission(
          String toolName, {
          bool defaultRequiresApproval = true,
          String? defaultDenyMessage,
        }) async {
          final policy = settings.getSystemPermissionPolicy(toolName);
          if (policy == SystemPermissionPolicy.deny) {
            return ToolApprovalResult.denied(
              'System permission for "$toolName" is set to Deny in Settings -> Permissions.',
            );
          }
          if (policy == SystemPermissionPolicy.bypass) {
            return ToolApprovalResult.approved();
          }
          // policy == SystemPermissionPolicy.ask
          if (defaultRequiresApproval && approvalService != null) {
            final toolCallId =
                '${toolName}_${DateTime.now().microsecondsSinceEpoch}';
            return await approvalService.requestApproval(
              toolCallId: toolCallId,
              toolName: toolName,
              arguments: args,
              conversationId: conversationId,
            );
          }
          return ToolApprovalResult.approved();
        }

        // Handle get_location_info tool
        if (name == LocalToolNames.locationInfo) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.locationInfo)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The get_location_info tool is disabled for this assistant.',
              tool: name,
            );
          }
          final locationAction = (args['action'] ?? 'current').toString().trim().toLowerCase();
          final approval = await checkSystemPermission(
            name,
            defaultRequiresApproval: locationAction != 'search',
          );
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied access to location information.',
              tool: name,
            );
          }
          return await _handleLocationInfoTool(args: args);
        }

        // Handle map_kit_tool
        if (name == LocalToolNames.mapKit) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.mapKit)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The map_kit_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final mapAction = (args['action'] ?? '').toString().trim().toLowerCase();
          final approval = await checkSystemPermission(
            name,
            defaultRequiresApproval: mapAction == 'open_navigation',
          );
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied opening Apple Maps.',
              tool: name,
            );
          }
          return await _handleMapKitTool(args: args);
        }

        // Handle weather_kit_tool
        if (name == LocalToolNames.weatherKit) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.weatherKit)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The weather_kit_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final hasExplicitLocation =
              (args['location'] ?? '').toString().trim().isNotEmpty ||
                  args['latitude'] != null;
          final approval = await checkSystemPermission(
            name,
            defaultRequiresApproval: !hasExplicitLocation,
          );
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied access to location for weather query.',
              tool: name,
            );
          }
          return await _handleWeatherKitTool(args: args);
        }

        // Handle ble_bridge_tool
        if (name == LocalToolNames.bleBridge) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.bleBridge)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The ble_bridge_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final bleAction = (args['action'] ?? '').toString().trim().toLowerCase();
          final approval = await checkSystemPermission(
            name,
            defaultRequiresApproval: bleAction == 'write',
          );
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied BLE write operation.',
              tool: name,
            );
          }
          return await _handleBleBridgeTool(args: args);
        }

        // Handle user_notification_tool
        if (name == LocalToolNames.userNotification) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.userNotification)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The user_notification_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final approval = await checkSystemPermission(name, defaultRequiresApproval: false);
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied UserNotification operation.',
              tool: name,
            );
          }
          return await _handleUserNotificationTool(args: args);
        }

        // Handle device_info_tool
        if (name == LocalToolNames.deviceInfo) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.deviceInfo)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The device_info_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final approval = await checkSystemPermission(name, defaultRequiresApproval: false);
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied DeviceInfo operation.',
              tool: name,
            );
          }
          return await _handleDeviceInfoTool(args: args);
        }

        // Handle health_kit_tool
        if (name == LocalToolNames.healthKit) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.healthKit)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The health_kit_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final hkAction = (args['action'] ?? '').toString().trim().toLowerCase();
          final approval = await checkSystemPermission(
            name,
            defaultRequiresApproval: hkAction == 'log_sample' || hkAction == 'request_permission',
          );
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied HealthKit operation.',
              tool: name,
            );
          }
          return await _handleHealthKitTool(args: args);
        }

        // Handle calendar_event_tool
        if (name == LocalToolNames.calendarEvent) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.calendarEvent)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The calendar_event_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final calAction = (args['action'] ?? '').toString().trim().toLowerCase();
          final approval = await checkSystemPermission(
            name,
            defaultRequiresApproval: calAction == 'create_event' ||
                calAction == 'update_event' ||
                calAction == 'delete_event' ||
                calAction == 'request_permission',
          );
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied Calendar operation.',
              tool: name,
            );
          }
          return await _handleCalendarEventTool(args: args);
        }

        // Handle reminder_task_tool
        if (name == LocalToolNames.reminderTask) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.reminderTask)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The reminder_task_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final remAction = (args['action'] ?? '').toString().trim().toLowerCase();
          final approval = await checkSystemPermission(
            name,
            defaultRequiresApproval: remAction == 'create_reminder' ||
                remAction == 'update_reminder' ||
                remAction == 'complete_reminder' ||
                remAction == 'delete_reminder' ||
                remAction == 'request_permission',
          );
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied Reminders operation.',
              tool: name,
            );
          }
          return await _handleReminderTaskTool(args: args);
        }

        // Handle alarm_timer_tool
        if (name == LocalToolNames.alarmTimer) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.alarmTimer)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The alarm_timer_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final approval = await checkSystemPermission(name, defaultRequiresApproval: false);
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied AlarmTimer operation.',
              tool: name,
            );
          }
          return await _handleAlarmTimerTool(args: args);
        }

        // Handle apple_vision_tool
        if (name == LocalToolNames.appleVision) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.appleVision)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The apple_vision_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final approval = await checkSystemPermission(name, defaultRequiresApproval: false);
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied AppleVision operation.',
              tool: name,
            );
          }
          return await _handleAppleVisionTool(args: args);
        }

        // Handle speech_recognizer_tool
        if (name == LocalToolNames.speechRecognizer) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.speechRecognizer)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The speech_recognizer_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final approval = await checkSystemPermission(name, defaultRequiresApproval: false);
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied SpeechRecognizer operation.',
              tool: name,
            );
          }
          return await _handleSpeechRecognizerTool(args: args);
        }

        // Handle speech_synthesizer_tool
        if (name == LocalToolNames.speechSynthesizer) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.speechSynthesizer)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The speech_synthesizer_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final approval = await checkSystemPermission(name, defaultRequiresApproval: false);
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied SpeechSynthesizer operation.',
              tool: name,
            );
          }
          return await _handleSpeechSynthesizerTool(args: args);
        }

        // Handle shortcut_automation_tool
        if (name == LocalToolNames.shortcutAutomation) {
          if (assistant == null ||
              !assistant.localToolIds.contains(LocalToolNames.shortcutAutomation)) {
            return _toolError(
              error: 'tool_disabled',
              message: 'The shortcut_automation_tool is disabled for this assistant.',
              tool: name,
            );
          }
          final approval = await checkSystemPermission(name, defaultRequiresApproval: false);
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied ShortcutAutomation operation.',
              tool: name,
            );
          }
          return await _handleShortcutAutomationTool(args: args);
        }

        return await approveAndExecuteMcp(name, args);
      } catch (e) {
        // Catch unexpected exceptions and return error JSON to LLM
        // This prevents tool failures from terminating the chat flow
        return _toolError(
          error: 'execution_error',
          message: e.toString(),
          tool: name,
          instruction:
              'The tool execution failed unexpectedly. You may try again with different parameters or inform the user about the issue.',
        );
      }
    };
  }

  /// Handle memory tool calls (§10).
  ///
  /// Returns null if the tool is not a memory tool or the relevant gate is off.
  Future<String?> _handleMemoryToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant, {
    String? conversationId,
  }) async {
    final settings = contextProvider.read<SettingsProvider>();
    if (settings.legacyMemoryMode) {
      if (MemoryTools.allToolNames.contains(name)) return null;
      return _handleLegacyMemoryToolCall(name, args, assistant);
    }

    if (assistant == null) return null;
    if (!MemoryTools.allToolNames.contains(name)) return null;

    final memoryV2 = contextProvider.read<MemoryProviderV2>();
    ChatService? chatService;
    try {
      chatService = contextProvider.read<ChatService>();
    } catch (_) {
      chatService = null;
    }

    MemoryPipelineService? pipeline;
    try {
      pipeline = contextProvider.read<MemoryPipelineService>();
    } catch (_) {
      pipeline = null;
    }

    Future<String> Function(String prompt)? memoryLlmCall;
    final provKey = settings.memoryModelProvider;
    final mdlId = settings.memoryModelId;
    if (provKey != null && mdlId != null) {
      final cfg = settings.getProviderConfig(provKey);
      final budget = settings.memoryModelThinkingEnabled
          ? (assistant.thinkingBudget ?? settings.thinkingBudget)
          : 0;
      memoryLlmCall = (prompt) => ChatApiService.generateText(
        config: cfg,
        modelId: mdlId,
        prompt: prompt,
        thinkingBudget: budget,
      );
    }

    final temporary =
        chatService?.isTemporaryConversation(conversationId) ?? false;
    return MemoryTools.handle(
      name: name,
      args: args,
      assistant: assistant,
      repository: memoryV2.repository,
      chatRepository: memoryV2.chatRepository,
      chatService: chatService,
      conversationId: conversationId,
      // Reload without changing which assistants the open memory UI is showing.
      onMutated: memoryV2.reloadCurrentScope,
      smartAdd: pipeline?.smartAdd,
      promptLang: settings.resolvedMemoryPromptLang,
      memoryLlmCall: memoryLlmCall,
      smartAddPromptZh: settings.memorySmartAddPromptZh,
      smartAddPromptEn: settings.memorySmartAddPromptEn,
      // Temporary chats are discarded on exit; their tool traces must not linger.
      traceRecorder: temporary ? null : pipeline?.traceRecorder,
      conversationTitle: conversationId == null
          ? null
          : chatService?.getConversation(conversationId)?.title,
    );
  }

  /// Handle legacy create/edit/delete_memory calls via [MemoryProvider].
  ///
  /// Returns null if memory is disabled or [name] is not a legacy memory tool.
  Future<String?> _handleLegacyMemoryToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant,
  ) async {
    if (assistant?.enableMemory != true) return null;
    if (name != 'create_memory' &&
        name != 'edit_memory' &&
        name != 'delete_memory') {
      return null;
    }

    try {
      final mp = contextProvider.read<MemoryProvider>();

      if (name == 'create_memory') {
        final content = (args['content'] ?? '').toString();
        if (content.isEmpty) {
          return _toolError(
            error: 'invalid_memory_content',
            message: 'Memory content must not be empty.',
            tool: name,
          );
        }
        final m = await mp.add(assistantId: assistant!.id, content: content);
        return m.content;
      } else if (name == 'edit_memory') {
        final id = (args['id'] as num?)?.toInt() ?? -1;
        final content = (args['content'] ?? '').toString();
        if (id <= 0) {
          return _toolError(
            error: 'invalid_memory_id',
            message: 'Memory id must be a positive integer.',
            tool: name,
          );
        }
        if (content.isEmpty) {
          return _toolError(
            error: 'invalid_memory_content',
            message: 'Memory content must not be empty.',
            tool: name,
          );
        }
        final m = await mp.update(id: id, content: content);
        if (m == null) {
          return _toolError(
            error: 'memory_not_found',
            message: 'No memory record was found for id $id.',
            tool: name,
            instruction:
                'Use the available memory records shown in context, or create a new memory instead of editing a missing one.',
          );
        }
        return m.content;
      } else if (name == 'delete_memory') {
        final id = (args['id'] as num?)?.toInt() ?? -1;
        if (id <= 0) {
          return _toolError(
            error: 'invalid_memory_id',
            message: 'Memory id must be a positive integer.',
            tool: name,
          );
        }
        final ok = await mp.delete(id: id);
        if (!ok) {
          return _toolError(
            error: 'memory_not_found',
            message: 'No memory record was found for id $id.',
            tool: name,
            instruction:
                'Use the available memory records shown in context, or skip deleting a missing memory.',
          );
        }
        return 'deleted';
      }
    } catch (e) {
      return _toolError(
        error: 'memory_execution_error',
        message: e.toString(),
        tool: name,
        instruction:
            'The memory tool failed. Retry only after correcting the parameters, or inform the user about the issue.',
      );
    }

    return null;
  }

  /// Handle MCP servers management tool (mcp_servers_tool)
  Future<String> _handleMcpServersTool({
    required Map<String, dynamic> args,
    required Assistant? assistant,
    required String? conversationId,
  }) async {
    final action = (args['action'] ?? '').toString().trim().toLowerCase();
    final mcp = contextProvider.read<McpProvider>();
    final assistantProvider = contextProvider.read<AssistantProvider>();
    final chatService = contextProvider.read<ChatService>();

    switch (action) {
      case 'list':
        final filterName = (args['name'] ?? '').toString().trim().toLowerCase();
        final List<Map<String, dynamic>> serverList = [];
        final convMcpIds = conversationId != null
            ? chatService.getConversationMcpServers(conversationId)
            : const <String>[];

        for (final s in mcp.servers) {
          if (filterName.isNotEmpty) {
            final sName = s.name.toLowerCase();
            final sId = s.id.toLowerCase();
            if (!sName.contains(filterName) && !sId.contains(filterName)) {
              continue;
            }
          }
          final isBoundToAssistant =
              assistant?.mcpServerIds.contains(s.id) ?? false;
          final isBoundToConv = convMcpIds.contains(s.id);
          final isConnected = mcp.statusFor(s.id) == McpStatus.connected;

          // Redact header values to protect sensitive secrets
          final Map<String, String> redactedHeaders = {};
          s.headers.forEach((k, _) {
            redactedHeaders[k] = '[REDACTED]';
          });

          final toolsList = s.tools.map((t) {
            final usableInChat = s.enabled &&
                t.enabled &&
                (isBoundToAssistant || isBoundToConv);
            return {
              'name': t.name,
              'description': t.description ?? '',
              'enabled_in_server': t.enabled,
              'currently_usable_in_chat': usableInChat,
            };
          }).toList();

          serverList.add({
            'server_id': s.id,
            'name': s.name,
            'transport': s.transport.name,
            'url': s.url,
            'global_enabled': s.enabled,
            'bound_to_current_assistant': isBoundToAssistant,
            'bound_to_current_conversation': isBoundToConv,
            'connection_status': mcp.statusFor(s.id).name,
            'connection_error': mcp.errorFor(s.id),
            'headers_keys': s.headers.keys.toList(),
            'redacted_headers': redactedHeaders,
            'tools': toolsList,
          });
        }

        return jsonEncode({
          'success': true,
          'action': 'list',
          'current_assistant_id': assistant?.id,
          'current_conversation_id': conversationId,
          'total_servers_count': serverList.length,
          'servers': serverList,
        });

      case 'install':
        final name = (args['name'] ?? '').toString().trim();
        final url = (args['url'] ?? '').toString().trim();
        final rawTransport =
            (args['transport'] ?? '').toString().trim().toLowerCase();

        if (name.isEmpty) {
          return _toolError(
            error: 'invalid_parameters',
            message: 'Parameter "name" is required for install action.',
            tool: LocalToolNames.mcpServersTool,
          );
        }
        if (url.isEmpty ||
            (!url.startsWith('http://') && !url.startsWith('https://'))) {
          return _toolError(
            error: 'invalid_parameters',
            message: 'Parameter "url" must be a valid HTTP or HTTPS URL.',
            tool: LocalToolNames.mcpServersTool,
          );
        }

        McpTransportType transportType;
        if (rawTransport == 'sse') {
          transportType = McpTransportType.sse;
        } else if (rawTransport == 'http') {
          transportType = McpTransportType.http;
        } else if (url.contains('/sse')) {
          transportType = McpTransportType.sse;
        } else {
          transportType = McpTransportType.http;
        }

        final headers = <String, String>{};
        if (args['headers'] is Map) {
          (args['headers'] as Map).forEach((k, v) {
            if (k != null && v != null) {
              headers[k.toString()] = v.toString();
            }
          });
        }

        final serverId = await mcp.addServer(
          enabled: true,
          name: name,
          transport: transportType,
          url: url,
          headers: headers,
        );

        // Wait up to 5s for connection status
        int elapsedMs = 0;
        const maxWaitMs = 5000;
        const checkIntervalMs = 200;
        while (elapsedMs < maxWaitMs) {
          final status = mcp.statusFor(serverId);
          if (status == McpStatus.connected || status == McpStatus.error) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: checkIntervalMs));
          elapsedMs += checkIntervalMs;
        }

        final serverConfig = mcp.servers.firstWhere(
          (s) => s.id == serverId,
          orElse: () => McpServerConfig(
            id: serverId,
            enabled: true,
            name: name,
            transport: transportType,
            url: url,
          ),
        );

        final status = mcp.statusFor(serverId);
        final connectionError = mcp.errorFor(serverId);

        // Only auto-bind to current assistant and conversation if connection succeeded!
        if (status == McpStatus.connected) {
          if (assistant != null &&
              !assistant.mcpServerIds.contains(serverId)) {
            final updatedAssistant = assistant.copyWith(
              mcpServerIds: [...assistant.mcpServerIds, serverId],
            );
            await assistantProvider.updateAssistant(updatedAssistant);
          }
          if (conversationId != null && conversationId.isNotEmpty) {
            final currentMcpIds =
                chatService.getConversationMcpServers(conversationId);
            if (!currentMcpIds.contains(serverId)) {
              await chatService.setConversationMcpServers(
                conversationId,
                [...currentMcpIds, serverId],
              );
            }
          }
        }

        return jsonEncode({
          'success': status == McpStatus.connected,
          'action': 'install',
          'server_id': serverId,
          'name': name,
          'url': url,
          'transport': transportType.name,
          'status': status.name,
          'error': connectionError,
          'available_tools': serverConfig.tools
              .map((t) => {'name': t.name, 'description': t.description ?? ''})
              .toList(),
          'message': status == McpStatus.connected
              ? 'MCP server installed and connected successfully.'
              : 'MCP server installed, but connection failed with status "${status.name}". Not bound to current chat. Error: $connectionError',
        });

      case 'toggle_server':
        final serverId = (args['server_id'] ?? '').toString().trim();
        if (serverId.isEmpty) {
          return _toolError(
            error: 'invalid_parameters',
            message: 'Parameter "server_id" is required for toggle_server action.',
            tool: LocalToolNames.mcpServersTool,
          );
        }
        final server = mcp.getById(serverId);
        if (server == null) {
          return _toolError(
            error: 'server_not_found',
            message: 'No MCP server found with ID "$serverId".',
            tool: LocalToolNames.mcpServersTool,
          );
        }

        // Handle bind/unbind to current assistant & conversation
        if (args.containsKey('bind_to_current')) {
          final bind = args['bind_to_current'] == true;
          if (!server.enabled) {
            return _toolError(
              error: 'server_disabled',
              message:
                  'Cannot bind/unbind a globally disabled MCP server. Please enable the server globally first.',
              tool: LocalToolNames.mcpServersTool,
            );
          }

          if (assistant != null) {
            final set = assistant.mcpServerIds.toSet();
            if (bind) {
              set.add(serverId);
            } else {
              set.remove(serverId);
            }
            await assistantProvider.updateAssistant(
              assistant.copyWith(mcpServerIds: set.toList()),
            );
          }

          if (conversationId != null && conversationId.isNotEmpty) {
            final currentMcpIds =
                chatService.getConversationMcpServers(conversationId);
            final set = currentMcpIds.toSet();
            if (bind) {
              set.add(serverId);
            } else {
              set.remove(serverId);
            }
            await chatService.setConversationMcpServers(
              conversationId,
              set.toList(),
            );
          }

          return jsonEncode({
            'success': true,
            'action': 'toggle_server',
            'server_id': serverId,
            'bound_to_current': bind,
            'message': bind
                ? 'MCP server "$serverId" bound to current assistant and chat.'
                : 'MCP server "$serverId" unbound from current assistant and chat.',
          });
        }

        // Handle global enable/disable
        if (args.containsKey('enabled')) {
          final enableGlobal = args['enabled'] == true;
          await mcp.updateServerMetadata(server.copyWith(enabled: enableGlobal));

          // If disabling globally, perform cascade cleanup of bindings across ALL assistants and current conversation
          if (!enableGlobal) {
            for (final a in assistantProvider.assistants) {
              if (a.mcpServerIds.contains(serverId)) {
                final newIds =
                    a.mcpServerIds.where((id) => id != serverId).toList();
                await assistantProvider.updateAssistant(
                  a.copyWith(mcpServerIds: newIds),
                );
              }
            }
            if (conversationId != null && conversationId.isNotEmpty) {
              final currentMcpIds =
                  chatService.getConversationMcpServers(conversationId);
              if (currentMcpIds.contains(serverId)) {
                final newIds =
                    currentMcpIds.where((id) => id != serverId).toList();
                await chatService.setConversationMcpServers(
                  conversationId,
                  newIds,
                );
              }
            }
          }

          return jsonEncode({
            'success': true,
            'action': 'toggle_server',
            'server_id': serverId,
            'global_enabled': enableGlobal,
            'message': enableGlobal
                ? 'MCP server "${server.name}" enabled globally.'
                : 'MCP server "${server.name}" disabled globally and un-bound from all assistants.',
          });
        }

        return _toolError(
          error: 'invalid_parameters',
          message:
              'Either "enabled" (boolean) or "bind_to_current" (boolean) must be provided for toggle_server.',
          tool: LocalToolNames.mcpServersTool,
        );

      case 'toggle_tool':
        final serverId = (args['server_id'] ?? '').toString().trim();
        final toolName = (args['tool_name'] ?? '').toString().trim();
        if (serverId.isEmpty || toolName.isEmpty || !args.containsKey('enabled')) {
          return _toolError(
            error: 'invalid_parameters',
            message:
                'Parameters "server_id", "tool_name", and "enabled" (boolean) are required for toggle_tool.',
            tool: LocalToolNames.mcpServersTool,
          );
        }
        final server = mcp.getById(serverId);
        if (server == null) {
          return _toolError(
            error: 'server_not_found',
            message: 'No MCP server found with ID "$serverId".',
            tool: LocalToolNames.mcpServersTool,
          );
        }

        final targetEnabled = args['enabled'] == true;
        final updatedTools = server.tools.map((t) {
          if (t.name == toolName) {
            return t.copyWith(enabled: targetEnabled);
          }
          return t;
        }).toList();

        final updatedServer = server.copyWith(tools: updatedTools);
        await mcp.updateServer(updatedServer);

        return jsonEncode({
          'success': true,
          'action': 'toggle_tool',
          'server_id': serverId,
          'tool_name': toolName,
          'enabled': targetEnabled,
          'message':
              'Tool "$toolName" under MCP server "${server.name}" set to enabled=$targetEnabled globally.',
        });

      case 'edit':
        final serverId = (args['server_id'] ?? '').toString().trim();
        if (serverId.isEmpty) {
          return _toolError(
            error: 'invalid_parameters',
            message: 'Parameter "server_id" is required for edit action.',
            tool: LocalToolNames.mcpServersTool,
          );
        }
        final server = mcp.getById(serverId);
        if (server == null) {
          return _toolError(
            error: 'server_not_found',
            message: 'No MCP server found with ID "$serverId".',
            tool: LocalToolNames.mcpServersTool,
          );
        }

        String newName = server.name;
        if (args['name'] != null && args['name'].toString().trim().isNotEmpty) {
          newName = args['name'].toString().trim();
        }
        String newUrl = server.url;
        if (args['url'] != null && args['url'].toString().trim().isNotEmpty) {
          newUrl = args['url'].toString().trim();
        }

        Map<String, String> newHeaders = Map.of(server.headers);
        if (args['headers'] is Map) {
          newHeaders.clear();
          (args['headers'] as Map).forEach((k, v) {
            if (k != null && v != null) {
              newHeaders[k.toString()] = v.toString();
            }
          });
        }

        McpTransportType newTransport = server.transport;
        if (args['transport'] != null) {
          final tRaw = args['transport'].toString().trim().toLowerCase();
          if (tRaw == 'sse') {
            newTransport = McpTransportType.sse;
          } else if (tRaw == 'http') {
            newTransport = McpTransportType.http;
          }
        }

        final updatedServer = server.copyWith(
          name: newName,
          url: newUrl,
          headers: newHeaders,
          transport: newTransport,
        );

        await mcp.updateServerMetadata(updatedServer);

        // Wait up to 5s for reconnection to finish and tools to initialize
        int elapsedMs = 0;
        const maxWaitMs = 5000;
        const checkIntervalMs = 200;
        while (elapsedMs < maxWaitMs) {
          final status = mcp.statusFor(serverId);
          if (status == McpStatus.connected || status == McpStatus.error) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: checkIntervalMs));
          elapsedMs += checkIntervalMs;
        }

        final status = mcp.statusFor(serverId);
        final connectionError = mcp.errorFor(serverId);

        // If edit successfully connected the server, auto-bind to current assistant & chat if not bound yet
        if (status == McpStatus.connected) {
          if (assistant != null &&
              !assistant.mcpServerIds.contains(serverId)) {
            final updatedAssistant = assistant.copyWith(
              mcpServerIds: [...assistant.mcpServerIds, serverId],
            );
            await assistantProvider.updateAssistant(updatedAssistant);
          }
          if (conversationId != null && conversationId.isNotEmpty) {
            final currentMcpIds =
                chatService.getConversationMcpServers(conversationId);
            if (!currentMcpIds.contains(serverId)) {
              await chatService.setConversationMcpServers(
                conversationId,
                [...currentMcpIds, serverId],
              );
            }
          }
        }

        final latestServerConfig = mcp.servers.firstWhere(
          (s) => s.id == serverId,
          orElse: () => updatedServer,
        );

        final isBoundToAssistant = assistant != null &&
            assistantProvider
                .getById(assistant.id)
                ?.mcpServerIds
                .contains(serverId) ==
                true;
        final isBoundToConv = conversationId != null &&
            chatService
                .getConversationMcpServers(conversationId)
                .contains(serverId);

        return jsonEncode({
          'success': status == McpStatus.connected,
          'action': 'edit',
          'server_id': serverId,
          'name': newName,
          'url': newUrl,
          'transport': newTransport.name,
          'connection_status': status.name,
          'connection_error': connectionError,
          'bound_to_current_assistant': isBoundToAssistant,
          'bound_to_current_conversation': isBoundToConv,
          'available_tools': latestServerConfig.tools
              .map((t) => {'name': t.name, 'description': t.description ?? ''})
              .toList(),
          'message': status == McpStatus.connected
              ? 'MCP server "${server.name}" configuration updated, reconnected, and bound successfully.'
              : 'MCP server "${server.name}" configuration updated, but connection status is currently "${status.name}". Error: $connectionError',
        });

      case 'remove':
        final serverId = (args['server_id'] ?? '').toString().trim();
        if (serverId.isEmpty) {
          return _toolError(
            error: 'invalid_parameters',
            message: 'Parameter "server_id" is required for remove action.',
            tool: LocalToolNames.mcpServersTool,
          );
        }
        final server = mcp.getById(serverId);
        if (server == null) {
          return _toolError(
            error: 'server_not_found',
            message: 'No MCP server found with ID "$serverId".',
            tool: LocalToolNames.mcpServersTool,
          );
        }

        // Rule constraint: Only allow deleting disabled servers
        if (server.enabled) {
          return _toolError(
            error: 'server_active',
            message:
                'Cannot remove an active/enabled MCP server. Please disable it globally first using action "toggle_server" (enabled: false).',
            tool: LocalToolNames.mcpServersTool,
          );
        }

        await mcp.removeServer(serverId);

        return jsonEncode({
          'success': true,
          'action': 'remove',
          'server_id': serverId,
          'message': 'MCP server "${server.name}" ($serverId) deleted successfully.',
        });

      default:
        return _toolError(
          error: 'invalid_action',
          message:
              'Unknown action "$action". Valid actions are: list, install, toggle_server, toggle_tool, edit, remove.',
          tool: LocalToolNames.mcpServersTool,
        );
    }
  }

  /// Handle get_location_info tool (GPS & reverse geocoding)
  Future<String> _handleLocationInfoTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'current').toString().trim().toLowerCase();

    if (action == 'search') {
      final addressQuery = (args['address'] ?? '').toString().trim();
      if (addressQuery.isEmpty) {
        return _toolError(
          error: 'invalid_parameters',
          message: 'Parameter "address" is required for search action.',
          tool: LocalToolNames.locationInfo,
        );
      }
      try {
        final locations = await locationFromAddress(addressQuery);
        if (locations.isEmpty) {
          return jsonEncode({
            'success': false,
            'action': 'search',
            'query': addressQuery,
            'message': 'No GPS coordinates found for the specified address.',
          });
        }
        final results = locations.map((loc) => {
          'latitude': loc.latitude,
          'longitude': loc.longitude,
          'timestamp': loc.timestamp?.toIso8601String(),
        }).toList();

        return jsonEncode({
          'success': true,
          'action': 'search',
          'query': addressQuery,
          'results_count': results.length,
          'coordinates': results,
        });
      } catch (e) {
        return _toolError(
          error: 'geocoding_failed',
          message: 'Failed to geocode address: $e',
          tool: LocalToolNames.locationInfo,
        );
      }
    }

    // Default action: 'current' - Get device GPS coordinates and reverse geocode
    final bool includeAddress = args['include_address'] != false;

    // Check location service status
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _toolError(
        error: 'location_service_disabled',
        message: 'Location services (GPS) are disabled on the device. Please turn on Location Services in device settings.',
        tool: LocalToolNames.locationInfo,
      );
    }

    // Check and request location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _toolError(
          error: 'location_permission_denied',
          message: 'Location permission was denied by user.',
          tool: LocalToolNames.locationInfo,
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return _toolError(
        error: 'location_permission_permanently_denied',
        message: 'Location permission is permanently denied in device settings. User needs to enable it in Settings.',
        tool: LocalToolNames.locationInfo,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      Map<String, dynamic>? addressDetails;
      String? formattedAddress;

      if (includeAddress) {
        try {
          final placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            addressDetails = {
              'name': p.name,
              'street': p.street,
              'subThoroughfare': p.subThoroughfare,
              'thoroughfare': p.thoroughfare,
              'subLocality': p.subLocality,
              'locality': p.locality,
              'subAdministrativeArea': p.subAdministrativeArea,
              'administrativeArea': p.administrativeArea,
              'postalCode': p.postalCode,
              'country': p.country,
              'isoCountryCode': p.isoCountryCode,
            };

            // Build a human readable formatted address string
            final parts = <String>[];
            if ((p.country ?? '').isNotEmpty) parts.add(p.country!);
            if ((p.administrativeArea ?? '').isNotEmpty && p.administrativeArea != p.country) parts.add(p.administrativeArea!);
            if ((p.locality ?? '').isNotEmpty && p.locality != p.administrativeArea) parts.add(p.locality!);
            if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
            if ((p.thoroughfare ?? '').isNotEmpty) parts.add(p.thoroughfare!);
            if ((p.subThoroughfare ?? '').isNotEmpty) parts.add(p.subThoroughfare!);
            formattedAddress = parts.isNotEmpty ? parts.join(' ') : (p.name ?? '');
          }
        } catch (_) {
          // Reverse geocoding optional fallback failure
        }
      }

      return jsonEncode({
        'success': true,
        'action': 'current',
        'coordinates': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'altitude': position.altitude,
          'accuracy_meters': position.accuracy,
          'heading': position.heading,
          'speed': position.speed,
          'timestamp': position.timestamp.toIso8601String(),
        },
        'formatted_address': formattedAddress,
        'address_details': addressDetails,
      });
    } catch (e) {
      return _toolError(
        error: 'location_fetch_failed',
        message: 'Failed to acquire location coordinates: $e',
        tool: LocalToolNames.locationInfo,
      );
    }
  }

  /// Handle map_kit_tool (MKLocalSearch, MKDirections, Apple Maps URL)
  Future<String> _handleMapKitTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? '').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'search_places':
          final query = (args['query'] ?? '').toString().trim();
          if (query.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "query" is required for search_places.',
              tool: LocalToolNames.mapKit,
            );
          }
          final data = await NativeMapKitService.searchPlaces(
            query: query,
            latitude: args['latitude'] as double?,
            longitude: args['longitude'] as double?,
            radiusMeters: (args['radius_meters'] as num?)?.toDouble() ?? 1000,
            limit: (args['limit'] as num?)?.toInt() ?? 10,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'get_route':
          final data = await NativeMapKitService.getRoute(
            fromAddress: args['from_address'] as String?,
            fromLatitude: args['from_latitude'] as double?,
            fromLongitude: args['from_longitude'] as double?,
            toAddress: args['to_address'] as String?,
            toLatitude: args['to_latitude'] as double?,
            toLongitude: args['to_longitude'] as double?,
            mode: (args['mode'] ?? 'driving').toString(),
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'get_eta':
          final data = await NativeMapKitService.getEta(
            fromAddress: args['from_address'] as String?,
            fromLatitude: args['from_latitude'] as double?,
            fromLongitude: args['from_longitude'] as double?,
            toAddress: args['to_address'] as String?,
            toLatitude: args['to_latitude'] as double?,
            toLongitude: args['to_longitude'] as double?,
            mode: (args['mode'] ?? 'driving').toString(),
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'open_navigation':
          final opened = await NativeMapKitService.openNavigation(
            fromAddress: args['from_address'] as String?,
            fromLatitude: args['from_latitude'] as double?,
            fromLongitude: args['from_longitude'] as double?,
            toAddress: args['to_address'] as String?,
            toLatitude: args['to_latitude'] as double?,
            toLongitude: args['to_longitude'] as double?,
            mode: (args['mode'] ?? 'driving').toString(),
          );
          return jsonEncode({
            'success': opened,
            'action': action,
            'message': opened
                ? 'Apple Maps opened for navigation.'
                : 'Failed to open Apple Maps.',
          });

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: search_places, get_route, get_eta, open_navigation.',
            tool: LocalToolNames.mapKit,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'map_kit_error',
        message: e.toString(),
        tool: LocalToolNames.mapKit,
      );
    }
  }

  /// Handle weather_kit_tool (Apple WeatherKit)
  Future<String> _handleWeatherKitTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'current').toString().trim().toLowerCase();
    final locationName = (args['location'] ?? '').toString().trim();
    double? lat = (args['latitude'] as num?)?.toDouble();
    double? lng = (args['longitude'] as num?)?.toDouble();

    String resolvedLocationName = locationName;

    // 1. Resolve coordinates
    if (lat == null || lng == null) {
      if (locationName.isNotEmpty) {
        try {
          final locations = await locationFromAddress(locationName);
          if (locations.isEmpty) {
            return _toolError(
              error: 'location_not_found',
              message: 'Could not resolve location "$locationName" to GPS coordinates.',
              tool: LocalToolNames.weatherKit,
            );
          }
          lat = locations.first.latitude;
          lng = locations.first.longitude;
        } catch (e) {
          return _toolError(
            error: 'geocoding_failed',
            message: 'Failed to geocode location "$locationName": $e',
            tool: LocalToolNames.weatherKit,
          );
        }
      } else {
        // Fallback to device current GPS location
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          return _toolError(
            error: 'location_service_disabled',
            message: 'Location services (GPS) are disabled on the device.',
            tool: LocalToolNames.weatherKit,
          );
        }
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            return _toolError(
              error: 'location_permission_denied',
              message: 'Location permission denied by user.',
              tool: LocalToolNames.weatherKit,
            );
          }
        }
        if (permission == LocationPermission.deniedForever) {
          return _toolError(
            error: 'location_permission_permanently_denied',
            message: 'Location permission is permanently denied in device settings.',
            tool: LocalToolNames.weatherKit,
          );
        }
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          );
          lat = pos.latitude;
          lng = pos.longitude;
          try {
            final placemarks = await placemarkFromCoordinates(lat, lng);
            if (placemarks.isNotEmpty) {
              final p = placemarks.first;
              resolvedLocationName = [p.locality, p.administrativeArea, p.country]
                  .where((s) => (s ?? '').isNotEmpty)
                  .join(', ');
            }
          } catch (_) {}
        } catch (e) {
          return _toolError(
            error: 'location_fetch_failed',
            message: 'Failed to acquire current location: $e',
            tool: LocalToolNames.weatherKit,
          );
        }
      }
    }

    try {
      final data = await NativeWeatherKitService.getWeather(
        latitude: lat!,
        longitude: lng!,
      );

      if (resolvedLocationName.isNotEmpty) {
        data['resolved_location_name'] = resolvedLocationName;
      }

      // Filter by action if user only wants specific payload
      if (action == 'forecast') {
        data.remove('alerts');
      } else if (action == 'alerts') {
        data.remove('hourly');
        data.remove('daily');
      } else if (action == 'current') {
        data.remove('hourly');
        data.remove('daily');
        data.remove('alerts');
      }

      return jsonEncode({'success': true, 'action': action, ...data});
    } on Exception catch (e) {
      return _toolError(
        error: 'weather_fetch_failed',
        message: e.toString(),
        tool: LocalToolNames.weatherKit,
      );
    }
  }

  /// Handle ble_bridge_tool (CoreBluetooth BLE)
  Future<String> _handleBleBridgeTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'status').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'status':
          final data = await NativeBleBridgeService.getStatus();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'scan':
          final duration = (args['duration_seconds'] as num?)?.toDouble() ?? 5.0;
          final data = await NativeBleBridgeService.scan(durationSeconds: duration);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'connect':
          final uuid = (args['uuid'] ?? '').toString().trim();
          if (uuid.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "uuid" is required for connect.',
              tool: LocalToolNames.bleBridge,
            );
          }
          final data = await NativeBleBridgeService.connect(uuid: uuid);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'disconnect':
          final uuid = (args['uuid'] ?? '').toString().trim();
          if (uuid.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "uuid" is required for disconnect.',
              tool: LocalToolNames.bleBridge,
            );
          }
          final data = await NativeBleBridgeService.disconnect(uuid: uuid);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'discover_services':
          final uuid = (args['uuid'] ?? '').toString().trim();
          if (uuid.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "uuid" is required for discover_services.',
              tool: LocalToolNames.bleBridge,
            );
          }
          final data = await NativeBleBridgeService.discoverServices(uuid: uuid);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'read':
          final uuid = (args['uuid'] ?? '').toString().trim();
          final serviceUuid = (args['service_uuid'] ?? '').toString().trim();
          final charUuid = (args['characteristic_uuid'] ?? '').toString().trim();
          if (uuid.isEmpty || serviceUuid.isEmpty || charUuid.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameters "uuid", "service_uuid", and "characteristic_uuid" are required for read.',
              tool: LocalToolNames.bleBridge,
            );
          }
          final data = await NativeBleBridgeService.readCharacteristic(
            uuid: uuid,
            serviceUuid: serviceUuid,
            characteristicUuid: charUuid,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'write':
          final uuid = (args['uuid'] ?? '').toString().trim();
          final serviceUuid = (args['service_uuid'] ?? '').toString().trim();
          final charUuid = (args['characteristic_uuid'] ?? '').toString().trim();
          final valueHex = args['value_hex'] as String?;
          final valueString = args['value_string'] as String?;
          if (uuid.isEmpty || serviceUuid.isEmpty || charUuid.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameters "uuid", "service_uuid", and "characteristic_uuid" are required for write.',
              tool: LocalToolNames.bleBridge,
            );
          }
          if ((valueHex ?? '').isEmpty && (valueString ?? '').isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Either "value_hex" or "value_string" is required for write.',
              tool: LocalToolNames.bleBridge,
            );
          }
          final data = await NativeBleBridgeService.writeCharacteristic(
            uuid: uuid,
            serviceUuid: serviceUuid,
            characteristicUuid: charUuid,
            valueHex: valueHex,
            valueString: valueString,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: status, scan, connect, disconnect, discover_services, read, write.',
            tool: LocalToolNames.bleBridge,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'ble_bridge_error',
        message: e.toString(),
        tool: LocalToolNames.bleBridge,
      );
    }
  }

  /// Handle user_notification_tool (UserNotifications)
  Future<String> _handleUserNotificationTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'settings').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'settings':
          final data = await NativeUserNotificationService.getSettings();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'request_permission':
          final data = await NativeUserNotificationService.requestPermission();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'schedule':
          final title = (args['title'] ?? '').toString().trim();
          final body = (args['body'] ?? '').toString().trim();
          if (title.isEmpty || body.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameters "title" and "body" are required for schedule.',
              tool: LocalToolNames.userNotification,
            );
          }
          final data = await NativeUserNotificationService.schedule(
            title: title,
            subtitle: args['subtitle'] as String?,
            body: body,
            afterSeconds: (args['after_seconds'] as num?)?.toDouble(),
            atTime: args['at_time'] as String?,
            sound: (args['sound'] as bool?) ?? true,
            id: args['id'] as String?,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'pending':
          final data = await NativeUserNotificationService.getPending();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'delivered':
          final data = await NativeUserNotificationService.getDelivered();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'cancel':
          final id = args['id'] as String?;
          final all = (args['all'] as bool?) ?? false;
          if ((id ?? '').isEmpty && !all) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Provide either "id" or set "all" to true for cancel.',
              tool: LocalToolNames.userNotification,
            );
          }
          final data = await NativeUserNotificationService.cancel(id: id, all: all);
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: settings, request_permission, schedule, pending, delivered, cancel.',
            tool: LocalToolNames.userNotification,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'user_notification_error',
        message: e.toString(),
        tool: LocalToolNames.userNotification,
      );
    }
  }

  /// Handle device_info_tool (UIKit & NSProcessInfo)
  Future<String> _handleDeviceInfoTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'info').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'info':
          final data = await NativeDeviceInfoService.getInfo();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'battery':
          final data = await NativeDeviceInfoService.getBattery();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'storage':
          final data = await NativeDeviceInfoService.getStorage();
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message: 'Unknown action "$action". Valid: info, battery, storage.',
            tool: LocalToolNames.deviceInfo,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'device_info_error',
        message: e.toString(),
        tool: LocalToolNames.deviceInfo,
      );
    }
  }

  /// Handle health_kit_tool (iOS HealthKit HKHealthStore)
  Future<String> _handleHealthKitTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'summary').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'summary':
          final data = await NativeHealthKitService.getSummary();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'request_permission':
          final data = await NativeHealthKitService.requestPermission();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'query_steps':
          final days = (args['days'] as num?)?.toInt() ?? 7;
          final data = await NativeHealthKitService.querySteps(days: days);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'query_heart_rate':
          final limit = (args['limit'] as num?)?.toInt() ?? 20;
          final data = await NativeHealthKitService.queryHeartRate(limit: limit);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'query_sleep':
          final days = (args['days'] as num?)?.toInt() ?? 7;
          final data = await NativeHealthKitService.querySleep(days: days);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'query_energy':
          final data = await NativeHealthKitService.queryEnergy();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'query_body':
          final data = await NativeHealthKitService.queryBody();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'query_nutrition':
          final data = await NativeHealthKitService.queryNutrition();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'log_sample':
          final typeName = (args['type'] ?? '').toString().trim();
          final value = (args['value'] as num?)?.toDouble();
          if (typeName.isEmpty || value == null) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameters "type" and "value" are required for log_sample.',
              tool: LocalToolNames.healthKit,
            );
          }
          final data = await NativeHealthKitService.logSample(type: typeName, value: value);
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: summary, request_permission, query_steps, query_heart_rate, query_sleep, query_energy, query_body, query_nutrition, log_sample.',
            tool: LocalToolNames.healthKit,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'health_kit_error',
        message: e.toString(),
        tool: LocalToolNames.healthKit,
      );
    }
  }

  /// Handle calendar_event_tool (iOS EventKit EKEventStore)
  Future<String> _handleCalendarEventTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'list_events').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'list_events':
          final days = (args['days'] as num?)?.toInt() ?? 7;
          final calendarName = args['calendar_name']?.toString();
          final data = await NativeCalendarEventService.listEvents(
            days: days,
            calendarName: calendarName,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'search_events':
          final query = (args['query'] ?? '').toString();
          final days = (args['days'] as num?)?.toInt() ?? 30;
          final data = await NativeCalendarEventService.searchEvents(query: query, days: days);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'create_event':
          final title = (args['title'] ?? '').toString().trim();
          if (title.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "title" is required for create_event.',
              tool: LocalToolNames.calendarEvent,
            );
          }
          final start = args['start']?.toString();
          final end = args['end']?.toString();
          final location = args['location']?.toString();
          final notes = args['notes']?.toString();
          final alarmMinutes = (args['alarm_minutes'] as num?)?.toInt();
          final calendarName = args['calendar_name']?.toString();

          final data = await NativeCalendarEventService.createEvent(
            title: title,
            start: start,
            end: end,
            location: location,
            notes: notes,
            alarmMinutes: alarmMinutes,
            calendarName: calendarName,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'update_event':
          final id = (args['id'] ?? '').toString().trim();
          if (id.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "id" is required for update_event.',
              tool: LocalToolNames.calendarEvent,
            );
          }
          final title = args['title']?.toString();
          final start = args['start']?.toString();
          final end = args['end']?.toString();
          final location = args['location']?.toString();
          final notes = args['notes']?.toString();
          final alarmMinutes = (args['alarm_minutes'] as num?)?.toInt();
          final calendarName = args['calendar_name']?.toString();
          final span = args['span']?.toString();

          final data = await NativeCalendarEventService.updateEvent(
            id: id,
            title: title,
            start: start,
            end: end,
            location: location,
            notes: notes,
            alarmMinutes: alarmMinutes,
            calendarName: calendarName,
            span: span,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'delete_event':
          final id = (args['id'] ?? '').toString().trim();
          if (id.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "id" is required for delete_event.',
              tool: LocalToolNames.calendarEvent,
            );
          }
          final span = args['span']?.toString();
          final data = await NativeCalendarEventService.deleteEvent(
            id: id,
            span: span,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'list_calendars':
          final data = await NativeCalendarEventService.listCalendars();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'freebusy':
          final days = (args['days'] as num?)?.toInt() ?? 1;
          final start = args['start']?.toString();
          final end = args['end']?.toString();
          final data = await NativeCalendarEventService.freebusy(
            days: days,
            start: start,
            end: end,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'request_permission':
          final data = await NativeCalendarEventService.requestPermission();
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: list_events, search_events, create_event, update_event, delete_event, list_calendars, freebusy, request_permission.',
            tool: LocalToolNames.calendarEvent,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'calendar_event_error',
        message: e.toString(),
        tool: LocalToolNames.calendarEvent,
      );
    }
  }

  /// Handle reminder_task_tool (iOS EventKit EKEventStore entityType: .reminder)
  Future<String> _handleReminderTaskTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'list_reminders').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'list_reminders':
          final listName = args['list_name']?.toString();
          final includeCompleted = (args['include_completed'] as bool?) ?? false;
          final data = await NativeReminderTaskService.listReminders(
            listName: listName,
            includeCompleted: includeCompleted,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'create_reminder':
          final title = (args['title'] ?? '').toString().trim();
          if (title.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "title" is required for create_reminder.',
              tool: LocalToolNames.reminderTask,
            );
          }
          final listName = args['list_name']?.toString();
          final dueDate = args['due_date']?.toString();
          final priority = (args['priority'] as num?)?.toInt() ?? 0;
          final notes = args['notes']?.toString();

          final data = await NativeReminderTaskService.createReminder(
            title: title,
            listName: listName,
            dueDate: dueDate,
            priority: priority,
            notes: notes,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'update_reminder':
          final id = (args['id'] ?? '').toString().trim();
          if (id.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "id" is required for update_reminder.',
              tool: LocalToolNames.reminderTask,
            );
          }
          final title = args['title']?.toString();
          final listName = args['list_name']?.toString();
          final dueDate = args['due_date']?.toString();
          final priority = (args['priority'] as num?)?.toInt();
          final notes = args['notes']?.toString();
          final completed = args['completed'] as bool?;

          final data = await NativeReminderTaskService.updateReminder(
            id: id,
            title: title,
            listName: listName,
            dueDate: dueDate,
            priority: priority,
            notes: notes,
            completed: completed,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'complete_reminder':
          final id = (args['id'] ?? '').toString().trim();
          if (id.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "id" is required for complete_reminder.',
              tool: LocalToolNames.reminderTask,
            );
          }
          final completed = (args['completed'] as bool?) ?? true;
          final data = await NativeReminderTaskService.completeReminder(
            id: id,
            completed: completed,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'delete_reminder':
          final id = (args['id'] ?? '').toString().trim();
          if (id.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "id" is required for delete_reminder.',
              tool: LocalToolNames.reminderTask,
            );
          }
          final data = await NativeReminderTaskService.deleteReminder(id: id);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'list_lists':
          final data = await NativeReminderTaskService.listLists();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'request_permission':
          final data = await NativeReminderTaskService.requestPermission();
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: list_reminders, create_reminder, complete_reminder, delete_reminder, list_lists, request_permission.',
            tool: LocalToolNames.reminderTask,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'reminder_task_error',
        message: e.toString(),
        tool: LocalToolNames.reminderTask,
      );
    }
  }

  /// Handle alarm_timer_tool (iOS UserNotifications & EventKit Alarm/Timer)
  Future<String> _handleAlarmTimerTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'list').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'set_alarm':
          final time = (args['time'] ?? '').toString().trim();
          if (time.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "time" (e.g. "07:30") is required for set_alarm.',
              tool: LocalToolNames.alarmTimer,
            );
          }
          final label = (args['label'] ?? '闹钟').toString();
          final repeat = (args['repeat'] ?? 'none').toString();

          final data = await NativeAlarmTimerService.setAlarm(
            time: time,
            label: label,
            repeat: repeat,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'set_timer':
          final durSec = (args['duration_seconds'] as num?)?.toInt();
          final durStr = args['duration']?.toString();
          final label = (args['label'] ?? '倒计时定时器').toString();

          if (durSec == null && (durStr == null || durStr.isEmpty)) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Provide "duration_seconds" (e.g. 300) or "duration" (e.g. "5m") for set_timer.',
              tool: LocalToolNames.alarmTimer,
            );
          }

          final data = await NativeAlarmTimerService.setTimer(
            durationSeconds: durSec,
            duration: durStr,
            label: label,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'list':
          final data = await NativeAlarmTimerService.list();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'cancel':
          final id = args['id']?.toString();
          final cancelAll = (args['all'] as bool?) ?? false;
          if ((id == null || id.isEmpty) && !cancelAll) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Provide "id" or set "all" to true for cancel.',
              tool: LocalToolNames.alarmTimer,
            );
          }
          final data = await NativeAlarmTimerService.cancel(id: id, all: cancelAll);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'request_permission':
          final data = await NativeAlarmTimerService.requestPermission();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'open_clock_app':
          final clockType = args['type']?.toString() ?? 'alarm';
          final data = await NativeAlarmTimerService.openClockApp(type: clockType);
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: set_alarm, set_timer, list, cancel, open_clock_app, request_permission.',
            tool: LocalToolNames.alarmTimer,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'alarm_timer_error',
        message: e.toString(),
        tool: LocalToolNames.alarmTimer,
      );
    }
  }

  Future<String> _handleAppleVisionTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'analyze_all').toString().trim().toLowerCase();
    final rawImagePath = (args['image_path'] ?? '').toString().trim();
    final imagePath = SandboxPathResolver.fix(rawImagePath);

    if (imagePath.isEmpty) {
      return _toolError(
        error: 'invalid_parameters',
        message: 'Parameter "image_path" is required for apple_vision_tool.',
        tool: LocalToolNames.appleVision,
      );
    }

    try {
      switch (action) {
        case 'ocr':
        case 'recognize_text':
          final languages = (args['languages'] as List?)?.map((e) => e.toString()).toList();
          final accurate = (args['accurate'] as bool?) ?? true;
          final data = await NativeAppleVisionService.recognizeText(
            imagePath: imagePath,
            languages: languages,
            accurate: accurate,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'detect_barcodes':
        case 'qr_scan':
          final data = await NativeAppleVisionService.detectBarcodes(imagePath: imagePath);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'detect_faces':
        case 'face_detection':
          final includeLandmarks = (args['include_landmarks'] as bool?) ?? false;
          final data = await NativeAppleVisionService.detectFaces(
            imagePath: imagePath,
            includeLandmarks: includeLandmarks,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'classify_image':
        case 'image_classification':
          final maxResults = (args['max_results'] as num?)?.toInt() ?? 10;
          final minConfidence = (args['min_confidence'] as num?)?.toDouble() ?? 0.05;
          final data = await NativeAppleVisionService.classifyImage(
            imagePath: imagePath,
            maxResults: maxResults,
            minConfidence: minConfidence,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'analyze_all':
        default:
          final data = await NativeAppleVisionService.analyzeAll(imagePath: imagePath);
          return jsonEncode({'success': true, 'action': action, ...data});
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'apple_vision_error',
        message: e.toString(),
        tool: LocalToolNames.appleVision,
      );
    }
  }

  Future<String> _handleSpeechRecognizerTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'transcribe_file').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'transcribe_file':
        case 'recognize_file':
          final audioPath = (args['audio_path'] ?? '').toString().trim();
          if (audioPath.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "audio_path" is required for transcribe_file action.',
              tool: LocalToolNames.speechRecognizer,
            );
          }
          final locale = (args['locale'] ?? 'zh-CN').toString().trim();
          final forceOffline = (args['force_offline'] as bool?) ?? true;
          final data = await NativeSpeechRecognizerService.transcribeFile(
            audioPath: audioPath,
            locale: locale,
            forceOffline: forceOffline,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'get_locales':
        case 'supported_locales':
          final data = await NativeSpeechRecognizerService.getSupportedLocales();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'request_permission':
          final data = await NativeSpeechRecognizerService.requestPermission();
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: transcribe_file, get_locales, request_permission.',
            tool: LocalToolNames.speechRecognizer,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'speech_recognizer_error',
        message: e.toString(),
        tool: LocalToolNames.speechRecognizer,
      );
    }
  }

  Future<String> _handleSpeechSynthesizerTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? 'speak').toString().trim().toLowerCase();

    try {
      switch (action) {
        case 'speak':
          final text = (args['text'] ?? '').toString().trim();
          if (text.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "text" is required for speak action.',
              tool: LocalToolNames.speechSynthesizer,
            );
          }
          final language = (args['language'] ?? 'zh-CN').toString().trim();
          final voice = args['voice']?.toString();
          final rate = (args['rate'] as num?)?.toDouble() ?? 0.5;
          final pitch = (args['pitch'] as num?)?.toDouble() ?? 1.0;
          final volume = (args['volume'] as num?)?.toDouble() ?? 1.0;
          final data = await NativeSpeechSynthesizerService.speak(
            text: text,
            language: language,
            voice: voice,
            rate: rate,
            pitch: pitch,
            volume: volume,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'synthesize_to_file':
        case 'write_to_file':
          final text = (args['text'] ?? '').toString().trim();
          if (text.isEmpty) {
            return _toolError(
              error: 'invalid_parameters',
              message: 'Parameter "text" is required for synthesize_to_file action.',
              tool: LocalToolNames.speechSynthesizer,
            );
          }
          final outputPath = args['output_path']?.toString();
          final language = (args['language'] ?? 'zh-CN').toString().trim();
          final voice = args['voice']?.toString();
          final rate = (args['rate'] as num?)?.toDouble() ?? 0.5;
          final pitch = (args['pitch'] as num?)?.toDouble() ?? 1.0;
          final data = await NativeSpeechSynthesizerService.synthesizeToFile(
            text: text,
            outputPath: outputPath,
            language: language,
            voice: voice,
            rate: rate,
            pitch: pitch,
          );
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'get_voices':
        case 'list_voices':
          final language = args['language']?.toString();
          final data = await NativeSpeechSynthesizerService.getVoices(language: language);
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'stop':
          final data = await NativeSpeechSynthesizerService.stop();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'pause':
          final data = await NativeSpeechSynthesizerService.pause();
          return jsonEncode({'success': true, 'action': action, ...data});

        case 'continue':
        case 'resume':
          final data = await NativeSpeechSynthesizerService.continueSpeech();
          return jsonEncode({'success': true, 'action': action, ...data});

        default:
          return _toolError(
            error: 'invalid_action',
            message:
                'Unknown action "$action". Valid: speak, synthesize_to_file, get_voices, stop, pause, continue.',
            tool: LocalToolNames.speechSynthesizer,
          );
      }
    } on Exception catch (e) {
      return _toolError(
        error: 'speech_synthesizer_error',
        message: e.toString(),
        tool: LocalToolNames.speechSynthesizer,
      );
    }
  }

  static Future<String> _handleShortcutAutomationTool({
    required Map<String, dynamic> args,
  }) async {
    final action = (args['action'] ?? '').toString().trim();
    final shortcut = args['shortcut']?.toString();
    final params = args['params']?.toString();
    final taskId = args['taskId']?.toString();

    final result = await NativeShortcutAutomationService.executeTask(
      action: action,
      shortcut: shortcut,
      params: params,
      taskId: taskId,
    );

    return jsonEncode(result);
  }
}
