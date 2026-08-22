import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Represents a remote desktop Agent (cc-connect) bridge endpoint.
class RemoteBridgeEndpoint {
  final String id;
  final String name;
  final String url; // e.g. "ws://192.168.1.5:9810/bridge/ws" or "wss://agent.domain.com/bridge/ws"
  final String token; // Bearer token
  final String project; // Target project name in cc-connect (defaults to "default")
  final bool enabled;
  final int createdAt; // Milliseconds since epoch
  final int? lastConnectedAt; // Milliseconds since epoch

  const RemoteBridgeEndpoint({
    required this.id,
    required this.name,
    required this.url,
    required this.token,
    this.project = 'default',
    this.enabled = true,
    required this.createdAt,
    this.lastConnectedAt,
  });

  /// Factory constructor to create a new endpoint with a generated UUID.
  factory RemoteBridgeEndpoint.create({
    required String name,
    required String url,
    required String token,
    String project = 'default',
    bool enabled = true,
  }) {
    return RemoteBridgeEndpoint(
      id: const Uuid().v4(),
      name: name.trim(),
      url: normalizeBridgeUrl(url),
      token: token.trim(),
      project: project.trim().isEmpty ? 'default' : project.trim(),
      enabled: enabled,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Normalizes a bridge URL (e.g. adding ws:// if missing, appending /bridge/ws path if missing).
  static String normalizeBridgeUrl(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return '';

    // If starts with http(s)://, convert to ws(s)://
    if (raw.startsWith('http://')) {
      raw = 'ws://${raw.substring(7)}';
    } else if (raw.startsWith('https://')) {
      raw = 'wss://${raw.substring(8)}';
    } else if (!raw.startsWith('ws://') && !raw.startsWith('wss://')) {
      // Default to ws://
      raw = 'ws://$raw';
    }

    try {
      final uri = Uri.parse(raw);
      var path = uri.path;
      if (path.isEmpty || path == '/') {
        path = '/bridge/ws';
      }
      return uri.replace(path: path).toString();
    } catch (_) {
      return raw;
    }
  }

  /// Derives the HTTP REST base URL from the WebSocket URL.
  String get httpBaseUrl {
    try {
      final uri = Uri.parse(url);
      final scheme = (uri.scheme == 'wss') ? 'https' : 'http';
      final portSuffix = uri.hasPort ? ':${uri.port}' : '';
      return '$scheme://${uri.host}$portSuffix';
    } catch (_) {
      return url;
    }
  }

  RemoteBridgeEndpoint copyWith({
    String? name,
    String? url,
    String? token,
    String? project,
    bool? enabled,
    int? lastConnectedAt,
  }) {
    return RemoteBridgeEndpoint(
      id: id,
      name: name ?? this.name,
      url: url != null ? normalizeBridgeUrl(url) : this.url,
      token: token ?? this.token,
      project: project ?? this.project,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'token': token,
      'project': project,
      'enabled': enabled,
      'createdAt': createdAt,
      if (lastConnectedAt != null) 'lastConnectedAt': lastConnectedAt,
    };
  }

  factory RemoteBridgeEndpoint.fromJson(Map<String, dynamic> json) {
    return RemoteBridgeEndpoint(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? 'Unnamed Bridge',
      url: normalizeBridgeUrl(json['url'] as String? ?? ''),
      token: json['token'] as String? ?? '',
      project: json['project'] as String? ?? 'default',
      enabled: json['enabled'] as bool? ?? true,
      createdAt: json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      lastConnectedAt: json['lastConnectedAt'] as int?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory RemoteBridgeEndpoint.fromJsonString(String jsonStr) =>
      RemoteBridgeEndpoint.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteBridgeEndpoint &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          url == other.url &&
          token == other.token &&
          project == other.project &&
          enabled == other.enabled;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      url.hashCode ^
      token.hashCode ^
      project.hashCode ^
      enabled.hashCode;
}
