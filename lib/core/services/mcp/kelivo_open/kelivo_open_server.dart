import 'dart:async';
import 'package:mcp_client/mcp_client.dart' as mcp;

import '../../preview/resource_preview_service.dart';

/// Request payload for the `kelivo_open` MCP tool.
class KelivoOpenRequestPayload {
  final String target;
  final String action;
  final String? title;

  const KelivoOpenRequestPayload({
    required this.target,
    this.action = 'auto',
    this.title,
  });

  static KelivoOpenRequestPayload parse(Object? args) {
    if (args is! Map) {
      throw ArgumentError(
        'Invalid arguments: expected an object containing target',
      );
    }
    final map = args.cast<String, dynamic>();
    final targetRaw = (map['target'] ?? map['url'] ?? map['path'] ?? '')
        .toString()
        .trim();
    if (targetRaw.isEmpty) {
      throw ArgumentError('Invalid target: target cannot be empty');
    }

    final actionRaw = (map['action'] ?? 'auto').toString().trim().toLowerCase();
    const validActions = {
      'auto',
      'in_app_preview',
      'system_open',
      'share',
    };
    final action = validActions.contains(actionRaw) ? actionRaw : 'auto';

    final titleRaw = map['title']?.toString().trim();
    final title = (titleRaw != null && titleRaw.isNotEmpty) ? titleRaw : null;

    return KelivoOpenRequestPayload(
      target: targetRaw,
      action: action,
      title: title,
    );
  }
}

/// Minimal JSON-RPC MCP server engine that serves the `@kelivo/open` tool.
class KelivoOpenMcpServerEngine {
  bool _closed = false;
  final ResourcePreviewService _previewService;

  KelivoOpenMcpServerEngine({ResourcePreviewService? previewService})
      : _previewService = previewService ?? ResourcePreviewService.instance;

  Future<dynamic> handleMessage(dynamic message) async {
    if (_closed) return null;

    if (message is List) {
      final out = <dynamic>[];
      for (final m in message) {
        out.add(await _handleSingle(m));
      }
      return out;
    }
    return await _handleSingle(message);
  }

  Future<Map<String, dynamic>> _handleSingle(dynamic raw) async {
    try {
      if (raw is! Map) {
        return _error(null, code: -32600, message: 'Invalid Request');
      }
      final req = raw.cast<String, dynamic>();
      final id = req['id'];
      final method = (req['method'] ?? '').toString();
      final params = (req['params'] is Map)
          ? (req['params'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      switch (method) {
        case mcp.McpProtocol.methodInitialize:
          return _ok(
            id,
            result: {
              'serverInfo': {'name': '@kelivo/open', 'version': '1.0.0'},
              'protocolVersion': mcp.McpProtocol.defaultVersion,
              'capabilities': {
                'tools': {'listChanged': false},
              },
            },
          );

        case mcp.McpProtocol.methodListTools:
          return _ok(id, result: {'tools': _toolDefinitions()});

        case mcp.McpProtocol.methodCallTool:
          final name = (params['name'] ?? '').toString();
          final arguments = (params['arguments'] is Map)
              ? (params['arguments'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};

          KelivoOpenRequestPayload payload;
          try {
            payload = KelivoOpenRequestPayload.parse(arguments);
          } catch (e) {
            return _ok(
              id,
              result: _toolResult(
                text: 'Error parsing parameters: $e',
                isError: true,
              ),
            );
          }

          if (name == 'kelivo_open' || name == 'open_resource') {
            final res = await _previewService.openResource(
              target: payload.target,
              action: payload.action,
              title: payload.title,
            );
            return _ok(
              id,
              result: _toolResult(
                text: res.message,
                isError: !res.success,
              ),
            );
          }
          return _error(id, code: -32101, message: 'Tool not found: $name');

        default:
          if (id == null) {
            return _noop();
          }
          return _error(id, code: -32601, message: 'Method not found: $method');
      }
    } catch (e) {
      return _error(null, code: -32603, message: 'Internal error: $e');
    }
  }

  void close() {
    _closed = true;
  }

  Map<String, dynamic> _ok(dynamic id, {required Map<String, dynamic> result}) {
    return {'jsonrpc': '2.0', if (id != null) 'id': id, 'result': result};
  }

  Map<String, dynamic> _error(
    dynamic id, {
    required int code,
    required String message,
  }) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };
  }

  Map<String, dynamic> _noop() => {'jsonrpc': '2.0'};

  Map<String, dynamic> _toolResult({
    required String text,
    required bool isError,
  }) {
    return {
      'content': [
        {'type': 'text', 'text': text},
      ],
      'isStreaming': false,
      'isError': isError,
    };
  }

  List<Map<String, dynamic>> _toolDefinitions() {
    Map<String, dynamic> schema() => {
      'type': 'object',
      'properties': {
        'target': {
          'type': 'string',
          'description':
              'The URL (http:// or https://) or local file absolute path to open or preview.',
        },
        'action': {
          'type': 'string',
          'enum': ['auto', 'in_app_preview', 'system_open', 'share'],
          'description':
              'Preview strategy: auto (default, smart match by file type/url), '
              'in_app_preview (force in-app WebView/Markdown/Image preview), '
              'system_open (force external system application/browser), '
              'or share (open system share sheet).',
        },
        'title': {
          'type': 'string',
          'description': 'Optional display title for the preview modal/window.',
        },
      },
      'required': ['target'],
    };

    return [
      {
        'name': 'kelivo_open',
        'description':
            'Open or preview web URLs, images, HTML, Markdown, documents, or local files directly for the user. '
            'Web URLs open in an in-app browser/WebView, images open in an image viewer, '
            'Markdown/text files open in a rich text preview, and other files launch in their system default application.',
        'inputSchema': schema(),
      },
    ];
  }
}

/// In-memory transport connecting MCP Client with [KelivoOpenMcpServerEngine].
class KelivoOpenInMemoryClientTransport implements mcp.ClientTransport {
  final KelivoOpenMcpServerEngine _server;
  final StreamController<dynamic> _messageController =
      StreamController<dynamic>.broadcast();
  final Completer<void> _closeCompleter = Completer<void>();
  bool _closed = false;

  KelivoOpenInMemoryClientTransport(this._server);

  @override
  Stream<dynamic> get onMessage => _messageController.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  mcp.TransportSendOperation send(dynamic message) {
    if (_closed) return mcp.TransportSendOperation.completed();
    Future.microtask(() async {
      final resp = await _server.handleMessage(message);
      if (_closed) return;
      if (resp != null) {
        _messageController.add(resp);
      }
    });
    return mcp.TransportSendOperation.completed();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _server.close();
    } catch (_) {}
    if (!_messageController.isClosed) _messageController.close();
    if (!_closeCompleter.isCompleted) _closeCompleter.complete();
  }
}
