import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:uuid/uuid.dart';

import 'core/database/app_database.dart';
import 'core/database/business_preferences.dart';
import 'core/database/chat_database_gateway.dart';
import 'core/models/assistant.dart';
import 'core/models/chat_message.dart';
import 'core/models/conversation.dart';
import 'core/models/message_part.dart';
import 'core/providers/mcp_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/api/chat_api_service.dart';
import 'core/services/api/stream/stream_chunk.dart';
import 'core/services/search/search_service.dart';
import 'core/services/search/search_tool_service.dart';
import 'utils/app_directories.dart';

const MethodChannel _channel = MethodChannel('app.intent_chat');

/// iOS 快捷指令后台无界面执行入口
@pragma('vm:entry-point')
void backgroundIntentMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 主动向 Native 端获取任务参数
    final rawArgs = await _channel.invokeMethod<dynamic>('getIntentParams');
    if (rawArgs == null) {
      await _channel.invokeMethod('onIntentError', '未收到快捷指令传入的参数');
      return;
    }
    final args = Map<String, dynamic>.from(rawArgs as Map);
    final result = await _handleExecuteIntent(args);
    await _channel.invokeMethod('onIntentComplete', result);
  } catch (e, stack) {
    debugPrint('backgroundIntentMain error: $e\n$stack');
    try {
      await _channel.invokeMethod('onIntentError', '后台执行异常: $e');
    } catch (_) {}
  }
}

Future<Map<String, dynamic>> _handleExecuteIntent(Map<String, dynamic> args) async {
  final prompt = args['prompt'] as String? ?? '';
  final assistantId = args['assistantId'] as String?;
  final existingSessionId = args['sessionId'] as String?;
  final modelOverride = args['modelId'] as String?;
  final filePaths = (args['filePaths'] as List?)?.map((e) => e.toString()).toList() ?? [];

  final appDir = await AppDirectories.getAppDataDirectory();
  final dbFile = File('${appDir.path}/${AppDatabase.databaseFileName}');

  final gateway = ChatDatabaseGateway.instance;
  final lease = await gateway.acquire(dbFile);
  final dbRepo = lease.repository;
  final busRepo = lease.businessRepository;

  try {

  final prefs = BusinessPreferences(busRepo);
  await prefs.load();

  // 1. 读取或创建助手
  Assistant assistant = const Assistant(id: 'default', name: '默认助手');
  final rawAssistants = prefs.getString('assistants_v1');
  if (rawAssistants != null && rawAssistants.isNotEmpty) {
    try {
      final list = (jsonDecode(rawAssistants) as List)
          .map((e) => Assistant.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (assistantId != null && assistantId != 'default') {
        assistant = list.firstWhere(
          (a) => a.id == assistantId,
          orElse: () => list.isNotEmpty ? list.first : assistant,
        );
      } else if (list.isNotEmpty) {
        assistant = list.first;
      }
    } catch (_) {}
  }

  // 2. 获取或创建会话
  String conversationId;
  if (existingSessionId != null && existingSessionId.isNotEmpty) {
    conversationId = existingSessionId;
  } else {
    conversationId = const Uuid().v4();
    final now = DateTime.now();
    final newConv = Conversation(
      id: conversationId,
      title: prompt.length > 20 ? '${prompt.substring(0, 20)}...' : prompt,
      createdAt: now,
      updatedAt: now,
      assistantId: assistant.id,
    );
    await dbRepo.putConversation(newConv);
  }

  // 3. 构建用户消息
  final userMessageId = const Uuid().v4();
  final userParts = <MessagePart>[
    TextPart(prompt),
  ];

  // 附件处理（图片/文件）
  final userImagePaths = <String>[];
  for (final path in filePaths) {
    final file = File(path);
    if (await file.exists()) {
      final filename = file.uri.pathSegments.last;
      userParts.add(FilePart(
        uri: path,
        name: filename,
      ));
      if (filename.toLowerCase().endsWith('.png') ||
          filename.toLowerCase().endsWith('.jpg') ||
          filename.toLowerCase().endsWith('.jpeg') ||
          filename.toLowerCase().endsWith('.webp')) {
        userImagePaths.add(path);
      }
    }
  }

  final userMsg = ChatMessage(
    id: userMessageId,
    conversationId: conversationId,
    role: 'user',
    content: prompt,
    parts: userParts,
  );
  await dbRepo.putMessage(userMsg);

  // 4. 读取历史消息以形成上下文
  final history = await dbRepo.getSelectedContextMessages(
    conversationId,
    truncateIndex: -1,
    limit: 100,
  );
  final apiMessages = <Map<String, dynamic>>[];

  // 注入助手 System Prompt
  if (assistant.systemPrompt.trim().isNotEmpty) {
    apiMessages.add({
      'role': 'system',
      'content': assistant.systemPrompt.trim(),
    });
  }

  for (final msg in history) {
    if (msg.role == 'user' || msg.role == 'assistant') {
      apiMessages.add({
        'role': msg.role,
        'content': msg.content,
      });
    }
  }

  // 5. 解析 Provider 配置
  final providerKey = assistant.chatModelProvider ?? 'openai';
  final selectedModel = (modelOverride != null && modelOverride != 'default')
      ? modelOverride
      : (assistant.chatModelId ?? 'gpt-4o');

  ProviderConfig? providerConfig;
  final rawProviders = prefs.getString('provider_configs_v1');
  if (rawProviders != null && rawProviders.isNotEmpty) {
    try {
      final providersMap = jsonDecode(rawProviders) as Map<String, dynamic>;
      final rawConfig = providersMap[providerKey];
      if (rawConfig != null) {
        providerConfig = ProviderConfig.fromJson(
          Map<String, dynamic>.from(rawConfig as Map),
        );
      }
    } catch (_) {}
  }

  providerConfig ??= ProviderConfig(
    id: providerKey,
    name: providerKey,
    apiKey: '',
    baseUrl: 'https://api.openai.com/v1',
    enabled: true,
  );

  // 6. 收集助手中开启的工具 (MCP + 网络搜索)
  final toolDefs = <Map<String, dynamic>>[];
  McpProvider? mcpProvider;
  List<McpServerConfig> activeMcpServers = [];

  // 6.1 网络搜索工具
  if (assistant.searchEnabled == true) {
    toolDefs.add(SearchToolService.getToolDefinition());
    // 注入搜索 inline citations 说明
    if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
      apiMessages.first['content'] =
          '${apiMessages.first['content']}\n\n${SearchToolService.getSystemPrompt()}';
    } else {
      apiMessages.insert(0, {
        'role': 'system',
        'content': SearchToolService.getSystemPrompt(),
      });
    }
  }

  // 6.2 MCP 工具（直接从已加载的 BusinessPreferences 中同步反序列化，避免异步竞态）
  final mcpServerIds = assistant.mcpServerIds.toSet();
  if (mcpServerIds.isNotEmpty) {
    final rawMcp = prefs.getString('mcp_servers_v1');
    if (rawMcp != null && rawMcp.isNotEmpty) {
      try {
        final allServers = (jsonDecode(rawMcp) as List)
            .map((e) => McpServerConfig.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        activeMcpServers = allServers
            .where((s) => mcpServerIds.contains(s.id) && s.enabled)
            .toList();

        if (activeMcpServers.isNotEmpty) {
          mcpProvider = McpProvider(preferences: prefs);
          for (final server in activeMcpServers) {
            for (final tool in server.tools.where((t) => t.enabled)) {
              final toolSchema = tool.schema ??
                  {
                    'type': 'object',
                    'properties': {
                      for (final p in tool.params)
                        p.name: {
                          'type': p.type ?? 'string',
                        },
                    },
                  };
              toolDefs.add({
                'type': 'function',
                'function': {
                  'name': tool.name,
                  'description': tool.description ?? '',
                  'parameters': toolSchema,
                },
              });
            }
          }
        }
      } catch (_) {}
    }
  }

  // 6.3 Tool-Call 执行器 handler
  Future<String> handleToolCall(
    String name,
    Map<String, dynamic> toolArgs, {
    String? toolCallId,
  }) async {
    // A. 处理网络搜索
    if (name == SearchToolService.toolName) {
      final query = toolArgs['query'] as String? ?? '';
      if (query.trim().isEmpty) {
        return jsonEncode({'error': 'Search query is empty'});
      }

      final rawServices = prefs.getString('search_services_v1');
      if (rawServices == null || rawServices.isEmpty) {
        return jsonEncode({'error': 'No search services configured in Kelivo'});
      }

      try {
        final serviceList = (jsonDecode(rawServices) as List)
            .map((e) => SearchServiceOptions.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        if (serviceList.isEmpty) {
          return jsonEncode({'error': 'No search services configured'});
        }

        final selectedIdx = (prefs.getInt('search_selected_v1') ?? 0)
            .clamp(0, serviceList.length - 1);
        final serviceOpt = serviceList[selectedIdx];
        final service = SearchService.getService(serviceOpt);

        SearchCommonOptions commonOpt = const SearchCommonOptions();
        final rawCommon = prefs.getString('search_common_v1');
        if (rawCommon != null && rawCommon.isNotEmpty) {
          try {
            commonOpt = SearchCommonOptions.fromJson(
              Map<String, dynamic>.from(jsonDecode(rawCommon) as Map),
            );
          } catch (_) {}
        }

        final result = await service.search(
          query: query,
          commonOptions: commonOpt,
          serviceOptions: serviceOpt,
        );

        final itemsWithIds = result.items.asMap().entries.map((entry) {
          final item = entry.value;
          return SearchResultItem(
            title: item.title,
            url: item.url,
            text: item.text,
            id: const Uuid().v4().substring(0, 6),
            index: entry.key + 1,
          );
        }).toList();

        return jsonEncode({
          if (result.answer != null) 'answer': result.answer,
          'items': itemsWithIds.map((item) => item.toJson()).toList(),
        });
      } catch (e) {
        return jsonEncode({'error': 'Search failed: $e'});
      }
    }

    // B. 处理 MCP 工具
    if (mcpProvider != null && activeMcpServers.isNotEmpty) {
      try {
        for (final server in activeMcpServers) {
          final toolMatch = server.tools.any((t) => t.name == name && t.enabled);
          if (toolMatch) {
            final res = await mcpProvider.callTool(server.id, name, toolArgs);
            if (res != null) {
              final buf = StringBuffer();
              for (final c in res.content) {
                if (c is mcp.TextContent) {
                  if (c.text.trim().isNotEmpty) buf.writeln(c.text);
                } else if (c is mcp.ResourceContent) {
                  final t = (c.text ?? '').toString();
                  if (t.trim().isNotEmpty) buf.writeln(t);
                }
              }
              final text = buf.toString().trim();
              return text.isNotEmpty ? text : 'Tool executed successfully';
            }
          }
        }
      } catch (e) {
        return jsonEncode({'error': 'MCP tool execution error: $e'});
      }
    }

    return jsonEncode({'error': 'Unknown tool: $name'});
  }

  // 7. 执行调用大模型并收集回复
  final completer = Completer<String>();
  final buffer = StringBuffer();

  try {
    final stream = ChatApiService.sendMessageStream(
      config: providerConfig,
      modelId: selectedModel,
      messages: apiMessages,
      userImagePaths: userImagePaths.isNotEmpty ? userImagePaths : null,
      temperature: assistant.temperature,
      maxTokens: assistant.maxTokens,
      tools: toolDefs.isNotEmpty ? toolDefs : null,
      onToolCall: toolDefs.isNotEmpty ? handleToolCall : null,
    );

    await for (final chunk in stream) {
      if (chunk is TextDelta && chunk.text.isNotEmpty) {
        buffer.write(chunk.text);
      }
    }
    completer.complete(buffer.toString());
  } catch (e) {
    if (!completer.isCompleted) {
      completer.complete('生成出错: $e');
    }
  }

  final assistantResponse = await completer.future;

  // 8. 保存 Assistant 消息到数据库
  final assistantMessageId = const Uuid().v4();
  final assistantMsg = ChatMessage(
    id: assistantMessageId,
    conversationId: conversationId,
    role: 'assistant',
    content: assistantResponse,
    parts: [TextPart(assistantResponse)],
    modelId: selectedModel,
    providerId: providerKey,
  );
  await dbRepo.putMessage(assistantMsg);

    return {
      'sessionId': conversationId,
      'response': assistantResponse,
      'assistantName': assistant.name,
      'modelName': selectedModel,
    };
  } finally {
    await lease.release();
  }
}
