import 'package:mcp_client/mcp_client.dart' as mcp;

import 'kelivo_open_server.dart';

/// Start the in-memory @kelivo/open MCP server and connect a client to it.
/// Returns the connected client and a stop() to dispose both ends.
Future<({mcp.Client client, Future<void> Function() stop})>
startOpenMcpInMemory() async {
  final server = KelivoOpenMcpServerEngine();
  final transport = KelivoOpenInMemoryClientTransport(server);

  final client = mcp.McpClient.createClient(
    mcp.McpClient.simpleConfig(name: 'Kelivo App', version: '1.0.0'),
  );
  await client.connect(transport);

  return (
    client: client,
    stop: () async {
      try {
        client.disconnect();
      } catch (_) {}
      try {
        transport.close();
      } catch (_) {}
    },
  );
}

/// Call the kelivo_open tool directly through an MCP Client.
Future<mcp.CallToolResult> callOpenTool(
  mcp.Client client, {
  required String target,
  String action = 'auto',
  String? title,
}) async {
  final result = await client.callTool('kelivo_open', {
    'target': target,
    'action': action,
    if (title != null && title.isNotEmpty) 'title': title,
  });
  return result;
}
