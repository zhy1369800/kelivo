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
import 'core/models/memory_entry.dart';
import 'core/models/message_part.dart';
import 'core/providers/mcp_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/api/chat_api_service.dart';
import 'core/services/api/stream/stream_chunk.dart';
import 'core/services/memory/memory_block_builder.dart';
import 'core/services/memory/memory_prompts.dart';
import 'core/services/memory/memory_repository.dart';
import 'core/services/memory/memory_tools.dart';
import 'core/services/search/search_service.dart';
import 'core/services/search/search_tool_service.dart';
import 'features/home/services/local_tools_service.dart';
import 'utils/app_directories.dart';

const MethodChannel _channel = MethodChannel('app.intent_chat');
bool _isListenerInstalled = false;

/// 初始化全局后台快捷指令通道监听（供主 App main() 调用，支持复用已存在的活跃引擎）
void initBackgroundIntentListener() {
  if (_isListenerInstalled) return;
  _isListenerInstalled = true;

  _channel.setMethodCallHandler((call) async {
    if (call.method == 'executeIntent') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      return await handleExecuteIntent(args);
    }
    throw PlatformException(code: 'not_implemented', message: 'Method not implemented');
  });
}

/// iOS 快捷指令后台独立无界面 Headless 执行入口
@pragma('vm:entry-point')
void backgroundIntentMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  initBackgroundIntentListener();

  try {
    // 带有重试机制的参数拉取（确保 Native Channel Handler 100% 就绪，彻底杜绝 Timeout 丢包）
    Map<String, dynamic>? args;
    for (var i = 0; i < 10; i++) {
      try {
        final rawArgs = await _channel.invokeMethod<dynamic>('getIntentParams');
        if (rawArgs != null) {
          args = Map<String, dynamic>.from(rawArgs as Map);
          break;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (args != null) {
      final result = await handleExecuteIntent(args);
      await _channel.invokeMethod('onIntentComplete', result);
    } else {
      await _channel.invokeMethod('onIntentError', '未能从快捷指令获取到执行参数（握手超时）');
    }
  } catch (e, stack) {
    debugPrint('backgroundIntentMain error: $e\n$stack');
    try {
      await _channel.invokeMethod('onIntentError', '后台执行异常: $e');
    } catch (_) {}
  }
}

Future<Map<String, dynamic>> handleExecuteIntent(Map<String, dynamic> args) async {
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
  String effectivePrompt = prompt;
  if (assistant.appendCurrentTimeToUserMessage) {
    final nowStr = DateTime.now().toString();
    effectivePrompt = '$prompt\n\n[System Current Time: $nowStr]';
  }

  final userParts = <MessagePart>[
    TextPart(effectivePrompt),
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
    content: effectivePrompt,
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

  // 注入预设对话消息 (Preset Messages)
  if (existingSessionId == null || existingSessionId.isEmpty) {
    for (final preset in assistant.presetMessages) {
      if (preset.content.trim().isNotEmpty) {
        apiMessages.add({
          'role': preset.role,
          'content': preset.content.trim(),
        });
      }
    }
  }

  for (final msg in history) {
    if (msg.role == 'user' || msg.role == 'assistant') {
      apiMessages.add({
        'role': msg.role,
        'content': msg.content,
      });
    }
  }

  // 4.1 记忆系统 (Memory System) 动态上下文注入
  if (assistant.enableMemory) {
    try {
      final visibleMemories = await dbRepo.queryVisibleMemories(
        assistantId: assistant.id,
      );
      final profileFields = await dbRepo.readProfileFields();
      final profileBlock = MemoryBlockBuilder.buildProfileBlock(
        fields: profileFields,
        lang: MemoryPromptLang.zh,
      );
      final totalByType = <MemoryType, int>{
        for (final t in MemoryType.values)
          t: visibleMemories.where((e) => e.type == t).length,
      };
      final memoryBlock = MemoryBlockBuilder.buildMemoryBlock(
        visible: visibleMemories,
        totalByType: totalByType,
        lang: MemoryPromptLang.zh,
        maxItems: 50,
      );
      final memoryBlockText = MemoryBlockBuilder.buildFullSnapshotPrefix(
        profileBlock,
        memoryBlock,
        MemoryPromptLang.zh,
      );
      if (memoryBlockText.trim().isNotEmpty) {
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages.first['content'] =
              '${apiMessages.first['content']}\n\n$memoryBlockText';
        } else {
          apiMessages.insert(0, {
            'role': 'system',
            'content': memoryBlockText,
          });
        }
      }
    } catch (e) {
      debugPrint('Memory prompt injection error: $e');
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

  // 6. 收集助手中开启的工具 (Local Tools + Memory Tools + Search + MCP)
  final toolDefs = <Map<String, dynamic>>[];
  McpProvider? mcpProvider;
  List<McpServerConfig> activeMcpServers = [];

  // 6.1 本地原生工具 (Local Tools)
  final localToolDefs = LocalToolsService.buildToolDefinitions(
    assistant: assistant,
    supportsTools: true,
  );
  if (localToolDefs.isNotEmpty) {
    toolDefs.addAll(localToolDefs);
  }

  // 6.2 记忆系统工具 (Memory Tools)
  if (assistant.enableMemory || assistant.allowPastConversationRecall) {
    final memoryToolDefs = MemoryTools.buildDefinitions(
      lang: MemoryPromptLang.zh,
      writeScope: assistant.memoryWriteScope,
      enableMemory: assistant.enableMemory,
      allowPastConversationRecall: assistant.allowPastConversationRecall,
    );
    if (memoryToolDefs.isNotEmpty) {
      toolDefs.addAll(memoryToolDefs);
    }
  }

  // 6.3 网络搜索工具
  if (assistant.searchEnabled == true) {
    toolDefs.add(SearchToolService.getToolDefinition());
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

  // 6.4 MCP 工具
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
          final mcpProv = McpProvider(preferences: prefs);
          mcpProvider = mcpProv;
          for (final server in activeMcpServers) {
            try {
              await mcpProv.ensureConnected(server.id);
            } catch (_) {}
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

  // 6.5 Tool-Call 执行器 handler
  Future<String> handleToolCall(
    String name,
    Map<String, dynamic> toolArgs, {
    String? toolCallId,
  }) async {
    // A. 处理本地原生工具 (Local Tools)
    try {
      final localRes = await LocalToolsService.tryHandleToolCall(
        name,
        toolArgs,
        assistant,
      );
      if (localRes != null) {
        return localRes;
      }
    } catch (e) {
      debugPrint('Local tool execution failed: $e');
    }

    // B. 处理记忆系统工具 (Memory Tools)
    if (assistant.enableMemory || assistant.allowPastConversationRecall) {
      try {
        final memRepo = MemoryRepository(prefs);
        final memRes = await MemoryTools.handle(
          name: name,
          args: toolArgs,
          assistant: assistant,
          repository: memRepo,
          chatRepository: dbRepo,
          conversationId: conversationId,
          promptLang: MemoryPromptLang.zh,
        );
        if (memRes != null) {
          return memRes;
        }
      } catch (e) {
        debugPrint('Memory tool execution failed: $e');
      }
    }

    // C. 处理网络搜索
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

    // D. 处理 MCP 工具
    final provider = mcpProvider;
    if (provider != null && activeMcpServers.isNotEmpty) {
      try {
        for (final server in activeMcpServers) {
          final toolMatch = server.tools.any((t) => t.name == name && t.enabled);
          if (toolMatch) {
            try {
              await provider.ensureConnected(server.id);
            } catch (_) {}
            final res = await provider.callTool(server.id, name, toolArgs);
            if (res != null) {
              if (res.isError == true) {
                final errBuf = StringBuffer('MCP Tool Error:\n');
                for (final c in res.content) {
                  if (c is mcp.TextContent) errBuf.writeln(c.text);
                }
                final errText = errBuf.toString().trim();
                return errText.isNotEmpty ? errText : jsonEncode({'error': 'MCP Tool execution error'});
              }
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
