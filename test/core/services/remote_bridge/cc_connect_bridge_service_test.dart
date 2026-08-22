import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/remote_bridge_endpoint.dart';
import 'package:Kelivo/core/services/remote_bridge/cc_connect_bridge_service.dart';

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
        RemoteBridgeEndpoint.normalizeBridgeUrl('https://agent.example.com'),
        'wss://agent.example.com/bridge/ws',
      );
      expect(
        RemoteBridgeEndpoint.normalizeBridgeUrl('ws://100.80.1.2:9810/custom/path'),
        'ws://100.80.1.2:9810/custom/path',
      );
    });

    test('derives httpBaseUrl correctly', () {
      final ep1 = RemoteBridgeEndpoint.create(
        name: 'Local',
        url: 'ws://192.168.1.5:9810/bridge/ws',
        token: 'secret',
      );
      expect(ep1.httpBaseUrl, 'http://192.168.1.5:9810');

      final ep2 = RemoteBridgeEndpoint.create(
        name: 'Cloud',
        url: 'wss://agent.mydomain.com/bridge/ws',
        token: 'secret',
      );
      expect(ep2.httpBaseUrl, 'https://agent.mydomain.com');
    });

    test('serializes and deserializes JSON cleanly', () {
      final ep = RemoteBridgeEndpoint.create(
        name: 'Test Node',
        url: 'ws://100.1.2.3:9810',
        token: 'token123',
        project: 'my-project',
      );

      final json = ep.toJson();
      final revived = RemoteBridgeEndpoint.fromJson(json);

      expect(revived.id, ep.id);
      expect(revived.name, 'Test Node');
      expect(revived.url, 'ws://100.1.2.3:9810/bridge/ws');
      expect(revived.token, 'token123');
      expect(revived.project, 'my-project');
      expect(revived.enabled, isTrue);
    });
  });

  group('BridgeButtonOption', () {
    test('parses button json correctly', () {
      final opt = BridgeButtonOption.fromJson({
        'label': 'Allow Command',
        'action': 'perm:allow',
        'style': 'primary',
      });
      expect(opt.label, 'Allow Command');
      expect(opt.action, 'perm:allow');
      expect(opt.style, 'primary');
    });
  });
}
