import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/remote_bridge_endpoint.dart';
import '../api/stream/stream_chunk.dart';

/// Connection state of a remote bridge.
enum BridgeConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Abstract base event received from R-Connect bridge.
sealed class BridgeEvent {
  const BridgeEvent();
}

/// Emitted when connection state changes.
class BridgeStatusEvent extends BridgeEvent {
  final BridgeConnectionState state;
  final String? message;
  final int? latencyMs;
  const BridgeStatusEvent(this.state, {this.message, this.latencyMs});
}

/// Emitted when the agent starts a streaming preview turn.
class BridgePreviewStartEvent extends BridgeEvent {
  final String refId;
  final String sessionKey;
  final String replyCtx;
  final String initialContent;
  const BridgePreviewStartEvent({
    required this.refId,
    required this.sessionKey,
    required this.replyCtx,
    required this.initialContent,
  });
}

/// Emitted when the agent updates the streaming message in-place.
class BridgeUpdateMessageEvent extends BridgeEvent {
  final String sessionKey;
  final String previewHandle;
  final String content;
  const BridgeUpdateMessageEvent({
    required this.sessionKey,
    required this.previewHandle,
    required this.content,
  });
}

/// Emitted when the agent sends a full/final reply.
class BridgeReplyEvent extends BridgeEvent {
  final String sessionKey;
  final String replyCtx;
  final String content;
  final String format;
  const BridgeReplyEvent({
    required this.sessionKey,
    required this.replyCtx,
    required this.content,
    this.format = 'text',
  });
}

/// A button in a permission or selection card.
class BridgeButtonOption {
  final String label;
  final String action; // e.g. "perm:allow", "perm:deny", "perm:allow_all"
  final String style; // "primary", "danger", "default"
  final String? url;

  const BridgeButtonOption({
    required this.label,
    required this.action,
    this.style = 'default',
    this.url,
  });

  factory BridgeButtonOption.fromJson(Map<String, dynamic> json) {
    return BridgeButtonOption(
      label: json['label'] as String? ?? json['text'] as String? ?? '',
      action: json['action'] as String? ?? '',
      style: json['style'] as String? ?? 'default',
      url: json['url'] as String?,
    );
  }
}

/// Emitted when the agent requests permissions or provides interactive buttons.
class BridgeButtonsEvent extends BridgeEvent {
  final String sessionKey;
  final String replyCtx;
  final String content;
  final List<List<BridgeButtonOption>> buttons; // Row-major grid of buttons

  const BridgeButtonsEvent({
    required this.sessionKey,
    required this.replyCtx,
    required this.content,
    required this.buttons,
  });
}

/// Emitted when an interactive card is sent by the bridge.
class BridgeCardEvent extends BridgeEvent {
  final String sessionKey;
  final String replyCtx;
  final Map<String, dynamic> cardData;

  const BridgeCardEvent({
    required this.sessionKey,
    required this.replyCtx,
    required this.cardData,
  });
}

/// Client service managing a WebSocket session to an R-Connect remote agent bridge.
class RConnectBridgeService {
  RemoteBridgeEndpoint? _endpoint;
  WebSocket? _ws;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _disposed = false;
  bool _manuallyDisconnected = false;

  BridgeConnectionState _state = BridgeConnectionState.disconnected;
  BridgeConnectionState get state => _state;
  RemoteBridgeEndpoint? get currentEndpoint => _endpoint;

  final StreamController<BridgeEvent> _eventController =
      StreamController<BridgeEvent>.broadcast();
  Stream<BridgeEvent> get events => _eventController.stream;

  int _lastPingSentAt = 0;
  int? _latencyMs;
  int? get latencyMs => _latencyMs;

  /// Active streaming sessions currently being awaited by an executeStream call.
  final Set<String> _activeStreamingSessions = {};

  /// Callback when a reply event is received for a session that has no active executeStream.
  void Function(String sessionKey, String content, String? endpointName)?
      onUnhandledReply;

  /// Checks if a reply content is a transient queue or busy notification from cc-connect.
  static bool isQueuedNotification(String content) {
    final text = content.trim();
    if (text.isEmpty) return false;
    return text.contains('消息已收到') ||
        text.contains('Message received') ||
        text.contains('上一个请求仍在处理中') ||
        text.contains('still being processed') ||
        text.contains('消息队列已满') ||
        text.contains('queue is full');
  }

  /// Connect to the given remote bridge endpoint.
  Future<void> connect(RemoteBridgeEndpoint endpoint) async {
    if (_disposed) return;
    _endpoint = endpoint;
    _manuallyDisconnected = false;
    _cancelTimers();
    await _closeSocket();

    _updateState(BridgeConnectionState.connecting);

    try {
      final headers = <String, dynamic>{};
      if (endpoint.token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${endpoint.token}';
      }

      final uri = Uri.parse(endpoint.url);
      _ws = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      _reconnectAttempts = 0;
      _listenToSocket();
      _sendRegisterHandshake();
      _startPingLoop();
    } catch (e) {
      debugPrint('[RConnectBridgeService] Connection error: $e');
      _updateState(
        BridgeConnectionState.error,
        message: 'Failed to connect: $e',
      );
      _scheduleReconnect();
    }
  }

  /// Disconnect the current session.
  Future<void> disconnect() async {
    _manuallyDisconnected = true;
    _cancelTimers();
    await _closeSocket();
    _updateState(BridgeConnectionState.disconnected);
  }

  /// Send a user message or command to the remote agent.
  Future<bool> sendMessage({
    required String sessionKey,
    required String content,
    String? msgId,
    String userId = 'kelivo_user',
    String? userName,
    String? replyCtx,
    List<Map<String, String>> images = const [],
    List<Map<String, String>> files = const [],
  }) async {
    if (_ws == null || _state != BridgeConnectionState.connected) {
      return false;
    }

    final payload = {
      'type': 'message',
      'msg_id': msgId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'session_key': sessionKey,
      'user_id': userId,
      if (userName != null) 'user_name': userName,
      'content': content,
      'reply_ctx': replyCtx ?? '',
      'project': _endpoint?.project ?? 'default',
      if (images.isNotEmpty) 'images': images,
      if (files.isNotEmpty) 'files': files,
    };

    return _sendJson(payload);
  }

  /// Send an interactive card action (such as "perm:allow" or button click) back to the bridge.
  Future<bool> sendCardAction({
    required String sessionKey,
    required String action,
    required String replyCtx,
  }) async {
    if (_ws == null || _state != BridgeConnectionState.connected) {
      return false;
    }

    final payload = {
      'type': 'card_action',
      'session_key': sessionKey,
      'action': action,
      'reply_ctx': replyCtx,
      'project': _endpoint?.project ?? 'default',
    };

    return _sendJson(payload);
  }

  /// Send preview acknowledgement back to the bridge.
  Future<bool> sendPreviewAck({
    required String refId,
    required String previewHandle,
  }) async {
    final payload = {
      'type': 'preview_ack',
      'ref_id': refId,
      'preview_handle': previewHandle,
      'project': _endpoint?.project ?? 'default',
    };
    return _sendJson(payload);
  }

  void _sendRegisterHandshake() {
    final registerPayload = {
      'type': 'register',
      'platform': 'kelivo',
      'capabilities': [
        'text',
        'image',
        'file',
        'card',
        'buttons',
        'preview',
        'update_message',
        'reconstruct_reply',
      ],
      'project': _endpoint?.project ?? 'default',
      'metadata': {
        'control_plane': ['capabilities_snapshot_v1'],
        'client_version': '1.2.3',
      },
    };
    _sendJson(registerPayload);
  }

  void _listenToSocket() {
    _ws?.listen(
      (data) {
        if (data is String) {
          _handleIncomingJson(data);
        }
      },
      onError: (error) {
        debugPrint('[RConnectBridgeService] WebSocket error: $error');
        _updateState(
          BridgeConnectionState.error,
          message: error.toString(),
        );
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint('[RConnectBridgeService] WebSocket closed');
        if (!_manuallyDisconnected) {
          _updateState(BridgeConnectionState.disconnected);
          _scheduleReconnect();
        }
      },
      cancelOnError: true,
    );
  }

  void _handleIncomingJson(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      switch (type) {
        case 'register_ack':
          final ok = json['ok'] as bool? ?? false;
          if (ok) {
            _updateState(BridgeConnectionState.connected);
          } else {
            _updateState(
              BridgeConnectionState.error,
              message: 'Registration rejected: ${json['error']}',
            );
          }
          break;

        case 'pong':
          if (_lastPingSentAt > 0) {
            _latencyMs = DateTime.now().millisecondsSinceEpoch - _lastPingSentAt;
            _eventController.add(BridgeStatusEvent(
              _state,
              latencyMs: _latencyMs,
            ));
          }
          break;

        case 'preview_start':
          final refId = json['ref_id'] as String? ?? '';
          final sessionKey = json['session_key'] as String? ?? '';
          final replyCtx = json['reply_ctx'] as String? ?? '';
          final content = json['content'] as String? ?? '';

          // Auto acknowledge preview start
          sendPreviewAck(refId: refId, previewHandle: refId);

          _eventController.add(BridgePreviewStartEvent(
            refId: refId,
            sessionKey: sessionKey,
            replyCtx: replyCtx,
            initialContent: content,
          ));
          break;

        case 'update_message':
          final sessionKey = json['session_key'] as String? ?? '';
          final previewHandle = json['preview_handle'] as String? ?? '';
          final content = json['content'] as String? ?? '';

          _eventController.add(BridgeUpdateMessageEvent(
            sessionKey: sessionKey,
            previewHandle: previewHandle,
            content: content,
          ));
          break;

        case 'reply':
          final sessionKey = json['session_key'] as String? ?? '';
          final replyCtx = json['reply_ctx'] as String? ?? '';
          final content = json['content'] as String? ?? '';
          final format = json['format'] as String? ?? 'text';

          _eventController.add(BridgeReplyEvent(
            sessionKey: sessionKey,
            replyCtx: replyCtx,
            content: content,
            format: format,
          ));

          final hasActiveStream = _activeStreamingSessions.any(
            (activeKey) => _matchesSessionKey(sessionKey, activeKey),
          );
          if (!hasActiveStream &&
              !isQueuedNotification(content) &&
              content.trim().isNotEmpty) {
            debugPrint(
              '[RConnectBridgeService] Unhandled reply for session $sessionKey: $content',
            );
            onUnhandledReply?.call(sessionKey, content, _endpoint?.name);
          }
          break;

        case 'buttons':
          final sessionKey = json['session_key'] as String? ?? '';
          final replyCtx = json['reply_ctx'] as String? ?? '';
          final content = json['content'] as String? ?? '';
          final rawButtons = json['buttons'] as List<dynamic>? ?? [];

          final buttonRows = <List<BridgeButtonOption>>[];
          for (final row in rawButtons) {
            if (row is List) {
              final rowItems = row
                  .map((b) => BridgeButtonOption.fromJson(b as Map<String, dynamic>))
                  .toList();
              buttonRows.add(rowItems);
            }
          }

          _eventController.add(BridgeButtonsEvent(
            sessionKey: sessionKey,
            replyCtx: replyCtx,
            content: content,
            buttons: buttonRows,
          ));
          break;

        case 'card':
          final sessionKey = json['session_key'] as String? ?? '';
          final replyCtx = json['reply_ctx'] as String? ?? '';
          final cardData = json['card'] as Map<String, dynamic>? ?? {};

          _eventController.add(BridgeCardEvent(
            sessionKey: sessionKey,
            replyCtx: replyCtx,
            cardData: cardData,
          ));
          break;

        default:
          debugPrint('[RConnectBridgeService] Unhandled message type: $type');
      }
    } catch (e) {
      debugPrint('[RConnectBridgeService] JSON parse error: $e');
    }
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_ws != null && _state == BridgeConnectionState.connected) {
        _lastPingSentAt = DateTime.now().millisecondsSinceEpoch;
        _sendJson({'type': 'ping', 'ts': _lastPingSentAt});
      }
    });
  }

  void _scheduleReconnect() {
    if (_manuallyDisconnected || _disposed || _endpoint == null) return;
    _reconnectTimer?.cancel();

    _reconnectAttempts++;
    // Exponential backoff: 2s, 4s, 8s, max 30s
    final delaySeconds = (_reconnectAttempts > 5) ? 30 : (1 << _reconnectAttempts);
    _updateState(BridgeConnectionState.reconnecting,
        message: 'Reconnecting in ${delaySeconds}s...');

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_manuallyDisconnected && !_disposed && _endpoint != null) {
        connect(_endpoint!);
      }
    });
  }

  bool _sendJson(Map<String, dynamic> data) {
    if (_ws == null || _ws!.readyState != WebSocket.open) return false;
    try {
      _ws!.add(jsonEncode(data));
      return true;
    } catch (e) {
      debugPrint('[RConnectBridgeService] send error: $e');
      return false;
    }
  }

  void _updateState(BridgeConnectionState newState, {String? message, int? latencyMs}) {
    _state = newState;
    _eventController.add(BridgeStatusEvent(newState, message: message, latencyMs: latencyMs));
  }

  void _cancelTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _closeSocket() async {
    if (_ws != null) {
      try {
        await _ws!.close();
      } catch (_) {}
      _ws = null;
    }
  }

  void dispose() {
    _disposed = true;
    _manuallyDisconnected = true;
    _cancelTimers();
    _closeSocket();
    _eventController.close();
  }

  // =========================================================================
  // Static Helper Methods (Connection test & REST endpoints)
  // =========================================================================

  /// Test connectivity to an R-Connect bridge endpoint. Returns latency in milliseconds, or throws error.
  static Future<int> testConnection(RemoteBridgeEndpoint endpoint) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    final uri = Uri.parse(endpoint.url);
    final headers = <String, dynamic>{};
    if (endpoint.token.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${endpoint.token}';
    }

    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
    ).timeout(const Duration(seconds: 5));

    final completer = Completer<int>();

    socket.listen(
      (data) {
        if (data is String) {
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            if (json['type'] == 'register_ack') {
              final latency = DateTime.now().millisecondsSinceEpoch - start;
              if (!completer.isCompleted) completer.complete(latency);
            }
          } catch (_) {}
        }
      },
      onError: (err) {
        if (!completer.isCompleted) completer.completeError(err);
      },
      cancelOnError: true,
    );

    // Send register handshake
    socket.add(jsonEncode({
      'type': 'register',
      'platform': 'kelivo_probe',
      'capabilities': ['text'],
      'project': endpoint.project,
    }));

    try {
      final result = await completer.future.timeout(const Duration(seconds: 5));
      await socket.close();
      return result;
    } catch (e) {
      await socket.close();
      rethrow;
    }
  }

  /// List active sessions from the bridge REST API.
  static Future<List<Map<String, dynamic>>> listSessions(RemoteBridgeEndpoint endpoint) async {
    final url = Uri.parse('${endpoint.httpBaseUrl}/bridge/sessions');
    final response = await http.get(
      url,
      headers: {
        if (endpoint.token.isNotEmpty) 'Authorization': 'Bearer ${endpoint.token}',
      },
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      } else if (data is Map && data['sessions'] is List) {
        return (data['sessions'] as List).cast<Map<String, dynamic>>();
      }
    }
    return [];
  }

  /// Fetch remote message history for a specific sessionKey from cc-connect REST API.
  static Future<List<Map<String, String>>> fetchRemoteHistory({
    required RemoteBridgeEndpoint endpoint,
    required String sessionKey,
    int limit = 50,
  }) async {
    try {
      final base = endpoint.httpBaseUrl;
      // 1. Query sessions for this session_key to locate the active session id
      final listUri =
          Uri.parse('$base/bridge/sessions').replace(queryParameters: {
        'session_key': sessionKey,
        'project': endpoint.project,
      });
      final headers = {
        if (endpoint.token.isNotEmpty)
          'Authorization': 'Bearer ${endpoint.token}',
      };

      final listResp = await http
          .get(listUri, headers: headers)
          .timeout(const Duration(seconds: 5));
      if (listResp.statusCode != 200) return [];

      final listData = jsonDecode(listResp.body);
      String? activeId;
      if (listData is Map) {
        activeId = listData['active_session_id'] as String?;
        if (activeId == null &&
            listData['sessions'] is List &&
            (listData['sessions'] as List).isNotEmpty) {
          activeId = (listData['sessions'] as List).first['id'] as String?;
        }
      }
      if (activeId == null || activeId.isEmpty) return [];

      // 2. Query session history
      final detailUri = Uri.parse('$base/bridge/sessions/$activeId')
          .replace(queryParameters: {
        'session_key': sessionKey,
        'project': endpoint.project,
        'history_limit': limit.toString(),
      });

      final detailResp = await http
          .get(detailUri, headers: headers)
          .timeout(const Duration(seconds: 5));
      if (detailResp.statusCode != 200) return [];

      final detailData = jsonDecode(detailResp.body);
      final rawHist = (detailData is Map && detailData['history'] is List)
          ? detailData['history'] as List<dynamic>
          : [];

      final result = <Map<String, String>>[];
      for (final item in rawHist) {
        if (item is Map) {
          result.add({
            'role': (item['role'] ?? 'assistant').toString(),
            'content': (item['content'] ?? '').toString(),
          });
        }
      }
      return result;
    } catch (e) {
      debugPrint('[RConnectBridgeService] fetchRemoteHistory error: $e');
      return [];
    }
  }

  bool _matchesSessionKey(String eventSessionKey, String expectedSessionKey) {
    if (eventSessionKey.isEmpty) return true;
    if (eventSessionKey == expectedSessionKey) return true;
    final cleanEvent = eventSessionKey.replaceAll('kelivo:', '');
    final cleanExpected = expectedSessionKey.replaceAll('kelivo:', '');
    return cleanEvent == cleanExpected;
  }

  /// Sends a message and returns a Stream of standard StreamChunks for Kelivo UI rendering.
  Stream<StreamChunk> executeStream({
    required String sessionKey,
    required String content,
    String? msgId,
    String? replyCtx,
    List<Map<String, String>> images = const [],
    List<Map<String, String>> files = const [],
  }) async* {
    final textChunkId = 'text_${DateTime.now().millisecondsSinceEpoch}';
    var textStarted = false;
    String lastFullContent = '';

    // Send user message
    final success = await sendMessage(
      sessionKey: sessionKey,
      content: content,
      msgId: msgId,
      replyCtx: replyCtx,
      images: images,
      files: files,
    );

    if (!success) {
      throw Exception('Failed to send message to R-Connect bridge daemon.');
    }

    _activeStreamingSessions.add(sessionKey);
    try {
      await for (final event in events) {
        if (event is BridgeStatusEvent &&
            (event.state == BridgeConnectionState.error ||
                event.state == BridgeConnectionState.disconnected)) {
          throw Exception(event.message ?? 'R-Connect bridge connection lost.');
        }

        if (event is BridgePreviewStartEvent) {
          if (_matchesSessionKey(event.sessionKey, sessionKey)) {
            if (!textStarted) {
              textStarted = true;
              yield TextStart(textChunkId);
            }
            if (event.initialContent.isNotEmpty) {
              yield TextDelta(id: textChunkId, text: event.initialContent);
              lastFullContent = event.initialContent;
            }
          }
        } else if (event is BridgeUpdateMessageEvent) {
          if (_matchesSessionKey(event.sessionKey, sessionKey)) {
            if (!textStarted) {
              textStarted = true;
              yield TextStart(textChunkId);
            }
            final newContent = event.content;
            if (newContent == lastFullContent) {
              continue;
            }
            if (newContent.startsWith(lastFullContent)) {
              final delta = newContent.substring(lastFullContent.length);
              yield TextDelta(id: textChunkId, text: delta);
              lastFullContent = newContent;
            } else {
              // If the content is new or replaced
              if (newContent.length > lastFullContent.length) {
                final delta = newContent.substring(lastFullContent.length);
                yield TextDelta(id: textChunkId, text: delta);
                lastFullContent = newContent;
              } else {
                // Shorter content or standalone block
                final prefix = lastFullContent.isNotEmpty ? '\n\n' : '';
                yield TextDelta(id: textChunkId, text: '$prefix$newContent');
                lastFullContent = newContent;
              }
            }
          }
        } else if (event is BridgeCardEvent) {
          if (_matchesSessionKey(event.sessionKey, sessionKey)) {
            if (!textStarted) {
              textStarted = true;
              yield TextStart(textChunkId);
            }
            final cardTitle = event.cardData['title'] ?? event.cardData['name'] ?? '交互卡片';
            final cardBody = event.cardData['description'] ?? event.cardData['text'] ?? jsonEncode(event.cardData);
            final buffer = StringBuffer()
              ..writeln('\n\n> 🎴 **[$cardTitle]**')
              ..writeln('> $cardBody\n');
            yield TextDelta(id: textChunkId, text: buffer.toString());
            lastFullContent += buffer.toString();
          }
        } else if (event is BridgeButtonsEvent) {
          if (_matchesSessionKey(event.sessionKey, sessionKey)) {
            if (!textStarted) {
              textStarted = true;
              yield TextStart(textChunkId);
            }

            final buffer = StringBuffer();
            if (event.content.isNotEmpty) {
              buffer.writeln('\n\n${event.content}\n');
            }
            buffer.writeln('\n> **[Agent 操作交互 / 审批请求]**');
            for (final row in event.buttons) {
              for (final btn in row) {
                buffer.writeln('- **[ ${btn.label} ]** (操作指令: `${btn.action}`)');
              }
            }
            yield TextDelta(id: textChunkId, text: buffer.toString());
            lastFullContent += buffer.toString();
          }
        } else if (event is BridgeReplyEvent) {
          if (_matchesSessionKey(event.sessionKey, sessionKey)) {
            final replyContent = event.content;

            // 方案 A：如果是排队/繁忙状态回执，告知前端当前状态，但不结束流，继续等待最终执行结果
            if (isQueuedNotification(replyContent)) {
              if (!textStarted) {
                textStarted = true;
                yield TextStart(textChunkId);
              }
              if (replyContent != lastFullContent) {
                final prefix = lastFullContent.isNotEmpty ? '\n\n' : '';
                yield TextDelta(id: textChunkId, text: '$prefix$replyContent\n\n');
                lastFullContent = '$lastFullContent$prefix$replyContent\n\n';
              }
              continue;
            }

            if (!textStarted) {
              textStarted = true;
              yield TextStart(textChunkId);
            }
            if (replyContent.isNotEmpty) {
              if (replyContent == lastFullContent) {
                // Content has already been fully streamed, avoid duplicate output
              } else if (replyContent.startsWith(lastFullContent)) {
                final delta = replyContent.substring(lastFullContent.length);
                yield TextDelta(id: textChunkId, text: delta);
                lastFullContent = replyContent;
              } else {
                // Standalone final reply or reconstructed reply after tool output
                final prefix = lastFullContent.isNotEmpty ? '\n\n' : '';
                yield TextDelta(id: textChunkId, text: '$prefix$replyContent');
                lastFullContent = replyContent;
              }
            }
            yield TextEnd(textChunkId);
            yield const Finish();
            break;
          }
        }
      }
    } finally {
      _activeStreamingSessions.remove(sessionKey);
    }
  }
}

/// Global manager caching active RConnectBridgeService instances by endpoint ID.
class RConnectBridgeManager {
  RConnectBridgeManager._();
  static final RConnectBridgeManager instance = RConnectBridgeManager._();

  final Map<String, RConnectBridgeService> _services = {};
  void Function(String sessionKey, String content, String? endpointName)?
      _unhandledReplyHandler;

  /// Registers a global handler for reply events that were not consumed by an active Stream.
  void setUnhandledReplyHandler(
    void Function(String sessionKey, String content, String? endpointName)?
        handler,
  ) {
    _unhandledReplyHandler = handler;
    for (final service in _services.values) {
      service.onUnhandledReply = handler;
    }
  }

  /// Get or create a connected bridge service for the specified endpoint.
  Future<RConnectBridgeService> getService(RemoteBridgeEndpoint endpoint) async {
    var service = _services[endpoint.id];
    if (service == null) {
      service = RConnectBridgeService();
      service.onUnhandledReply = _unhandledReplyHandler;
      _services[endpoint.id] = service;
      await service.connect(endpoint);
    } else {
      service.onUnhandledReply ??= _unhandledReplyHandler;
      if (service.state == BridgeConnectionState.disconnected ||
          service.state == BridgeConnectionState.error) {
        await service.connect(endpoint);
      }
    }
    return service;
  }

  /// Close and remove all cached services.
  void disposeAll() {
    for (final s in _services.values) {
      s.dispose();
    }
    _services.clear();
  }
}
