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

/// Abstract base event received from cc-connect bridge.
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

/// Client service managing a WebSocket session to a cc-connect desktop daemon.
class CcConnectBridgeService {
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
      debugPrint('[CcConnectBridgeService] Connection error: $e');
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

  /// Send an interactive card action (such as "perm:allow" or button click) back to cc-connect.
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

  /// Send preview acknowledgement back to cc-connect.
  Future<bool> sendPreviewAck({
    required String refId,
    required String previewHandle,
  }) async {
    final payload = {
      'type': 'preview_ack',
      'ref_id': refId,
      'preview_handle': previewHandle,
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
        debugPrint('[CcConnectBridgeService] WebSocket error: $error');
        _updateState(
          BridgeConnectionState.error,
          message: error.toString(),
        );
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint('[CcConnectBridgeService] WebSocket closed');
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
          debugPrint('[CcConnectBridgeService] Unhandled message type: $type');
      }
    } catch (e) {
      debugPrint('[CcConnectBridgeService] JSON parse error: $e');
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
    if (_ws == null) return false;
    try {
      _ws!.add(jsonEncode(data));
      return true;
    } catch (e) {
      debugPrint('[CcConnectBridgeService] send error: $e');
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

  /// Test connectivity to a bridge endpoint. Returns latency in milliseconds, or throws error.
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
    var accumulatedLength = 0;

    final completer = Completer<void>();
    final sub = events.listen((event) {
      if (completer.isCompleted) return;

      if (event is BridgeStatusEvent && event.state == BridgeConnectionState.error) {
        if (!completer.isCompleted) {
          completer.completeError(Exception(event.message ?? 'Bridge connection error'));
        }
      }
    });

    try {
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
        yield StreamError(Exception('Failed to send message to cc-connect daemon.'));
        return;
      }

      await for (final event in events) {
        if (event is BridgePreviewStartEvent) {
          if (event.sessionKey == sessionKey) {
            if (!textStarted) {
              textStarted = true;
              yield TextStart(textChunkId);
            }
            if (event.initialContent.isNotEmpty) {
              yield TextDelta(id: textChunkId, text: event.initialContent);
              accumulatedLength = event.initialContent.length;
            }
          }
        } else if (event is BridgeUpdateMessageEvent) {
          if (event.sessionKey == sessionKey) {
            if (!textStarted) {
              textStarted = true;
              yield TextStart(textChunkId);
            }
            final newContent = event.content;
            if (newContent.length > accumulatedLength) {
              final delta = newContent.substring(accumulatedLength);
              yield TextDelta(id: textChunkId, text: delta);
              accumulatedLength = newContent.length;
            }
          }
        } else if (event is BridgeButtonsEvent) {
          if (event.sessionKey == sessionKey) {
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
            accumulatedLength += buffer.length;
          }
        } else if (event is BridgeReplyEvent) {
          if (event.sessionKey == sessionKey) {
            if (!textStarted) {
              textStarted = true;
              yield TextStart(textChunkId);
            }
            if (event.content.length > accumulatedLength) {
              final delta = event.content.substring(accumulatedLength);
              yield TextDelta(id: textChunkId, text: delta);
            }
            yield TextEnd(textChunkId);
            yield const StreamDone();
            break;
          }
        }
      }
    } finally {
      await sub.cancel();
    }
  }
}

/// Global manager caching active CcConnectBridgeService instances by endpoint ID.
class CcConnectBridgeManager {
  CcConnectBridgeManager._();
  static final CcConnectBridgeManager instance = CcConnectBridgeManager._();

  final Map<String, CcConnectBridgeService> _services = {};

  /// Get or create a connected bridge service for the specified endpoint.
  Future<CcConnectBridgeService> getService(RemoteBridgeEndpoint endpoint) async {
    var service = _services[endpoint.id];
    if (service == null) {
      service = CcConnectBridgeService();
      _services[endpoint.id] = service;
      await service.connect(endpoint);
    } else if (service.state == BridgeConnectionState.disconnected ||
        service.state == BridgeConnectionState.error) {
      await service.connect(endpoint);
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
