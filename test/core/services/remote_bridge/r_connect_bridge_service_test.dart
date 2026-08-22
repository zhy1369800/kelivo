import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/remote_bridge_endpoint.dart';
import 'package:Kelivo/core/services/remote_bridge/r_connect_bridge_service.dart';

void main() {
  group('RemoteBridgeEndpoint', () {
    test('normalizes bridge URL properly', () {
      expect(
        RemoteBridgeEndpoint.normalizeBridgeUrl('192.168.1.100:9810'),
        'ws://192.168.1.100:9810/bridge/ws',
      );

      expect(
        RemoteBridgeEndpoint.normalizeBridgeUrl('http://192.168.1.100:9810'),
        'ws://192.168.1.100:9810/bridge/ws',
      );

      expect(
        RemoteBridgeEndpoint.normalizeBridgeUrl('https://my-agent.domain.com'),
        'wss://my-agent.domain.com/bridge/ws',
      );

      expect(
        RemoteBridgeEndpoint.normalizeBridgeUrl('wss://my-agent.domain.com/bridge/ws'),
        'wss://my-agent.domain.com/bridge/ws',
      );
    });

    test('derives httpBaseUrl correctly', () {
      final ep1 = RemoteBridgeEndpoint.create(
        name: 'Local',
        url: 'ws://192.168.1.100:9810/bridge/ws',
        token: 'test_token',
      );
      expect(ep1.httpBaseUrl, 'http://192.168.1.100:9810');

      final ep2 = RemoteBridgeEndpoint.create(
        name: 'SSL',
        url: 'wss://my-agent.domain.com/bridge/ws',
        token: 'test_token',
      );
      expect(ep2.httpBaseUrl, 'https://my-agent.domain.com');
    });

    test('serializes and deserializes JSON cleanly', () {
      final ep = RemoteBridgeEndpoint.create(
        name: 'Office Mac',
        url: 'ws://10.0.0.5:9810',
        token: 'secret_token',
        project: 'custom_proj',
      );

      final json = ep.toJson();
      final restored = RemoteBridgeEndpoint.fromJson(json);

      expect(restored.id, ep.id);
      expect(restored.name, 'Office Mac');
      expect(restored.url, 'ws://10.0.0.5:9810/bridge/ws');
      expect(restored.token, 'secret_token');
      expect(restored.project, 'custom_proj');
    });
  });

  group('BridgeButtonOption', () {
    test('parses button json correctly', () {
      final json = {
        'label': 'Allow Execution',
        'action': 'perm:allow',
        'style': 'primary',
      };
      final btn = BridgeButtonOption.fromJson(json);
      expect(btn.label, 'Allow Execution');
      expect(btn.action, 'perm:allow');
      expect(btn.style, 'primary');
    });
  });
}
