import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'core/database/app_database.dart';
import 'core/database/business_preferences.dart';
import 'core/database/chat_database_gateway.dart';
import 'core/models/assistant.dart';
import 'core/models/chat_message.dart';
import 'core/models/conversation.dart';
import 'core/models/message_part.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/api/chat_api_service.dart';
import 'core/services/api/stream/stream_chunk.dart';
import 'utils/app_directories.dart';

const MethodChannel _channel = MethodChannel('app.intent_chat');

/// iOS 快捷指令后台无界面执行入口
@pragma('vm:entry-point')
void backgroundIntentMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  _channel.setMethodCallHandler((call) async {
    if (call.method == 'executeIntent') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      return await _handleExecuteIntent(args);
    }
    throw PlatformException(code: 'not_implemented', message: 'Method not implemented');
  });
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
  // 实际存储 key 是 'provider_configs_v1'（即 BusinessEntityKind.provider.sourceKey），
  // 值是 JSON 对象：{ providerKey: { ...config } }
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

  // 兜底：仅在找不到配置时才使用空白 Provider（会让 API 调用失败，但不崩溃）
  providerConfig ??= ProviderConfig(
    id: providerKey,
    name: providerKey,
    apiKey: '',
    baseUrl: 'https://api.openai.com/v1',
    enabled: true,
  );

  // 6. 执行调用大模型并收集回复
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

  // 7. 保存 Assistant 消息到数据库
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
}
