import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/remote_bridge_endpoint.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/remote_bridge/cc_connect_bridge_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

class RemoteBridgeSettingsPage extends StatefulWidget {
  const RemoteBridgeSettingsPage({super.key});

  @override
  State<RemoteBridgeSettingsPage> createState() =>
      _RemoteBridgeSettingsPageState();
}

class _RemoteBridgeSettingsPageState extends State<RemoteBridgeSettingsPage> {
  final Map<String, int?> _latencies = {};
  final Map<String, bool> _testing = {};

  Future<void> _testEndpoint(RemoteBridgeEndpoint endpoint) async {
    setState(() {
      _testing[endpoint.id] = true;
      _latencies[endpoint.id] = null;
    });

    try {
      final latency = await CcConnectBridgeService.testConnection(endpoint);
      if (mounted) {
        setState(() {
          _latencies[endpoint.id] = latency;
          _testing[endpoint.id] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接成功！延迟: ${latency}ms'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _latencies[endpoint.id] = -1; // -1 represents failed
          _testing[endpoint.id] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showEditDialog({RemoteBridgeEndpoint? endpoint}) {
    final isNew = endpoint == null;
    final nameController =
        TextEditingController(text: endpoint?.name ?? '');
    final urlController = TextEditingController(
      text: endpoint?.url ?? 'ws://127.0.0.1:9810/bridge/ws',
    );
    final tokenController =
        TextEditingController(text: endpoint?.token ?? '');
    final projectController =
        TextEditingController(text: endpoint?.project ?? 'default');
    bool isTesting = false;
    String? testResult;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            Future<void> doTest() async {
              setDialogState(() {
                isTesting = true;
                testResult = null;
              });

              final tempEp = RemoteBridgeEndpoint(
                id: 'temp',
                name: nameController.text.trim(),
                url: RemoteBridgeEndpoint.normalizeBridgeUrl(
                  urlController.text.trim(),
                ),
                token: tokenController.text.trim(),
                project: projectController.text.trim(),
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );

              try {
                final latency =
                    await CcConnectBridgeService.testConnection(tempEp);
                setDialogState(() {
                  isTesting = false;
                  testResult = '✓ 连接成功 (${latency}ms)';
                });
              } catch (e) {
                setDialogState(() {
                  isTesting = false;
                  testResult = '✗ 连接失败: $e';
                });
              }
            }

            return AlertDialog(
              title: Text(isNew ? '添加桌面 Agent (cc-connect)' : '编辑节点'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '节点名称',
                        hintText: '如: 工位 Mac (Claude Code)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'WebSocket 连接地址',
                        hintText: 'ws://192.168.1.5:9810/bridge/ws',
                        helperText: '支持局域网 IP / Tailscale IP / 域名',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tokenController,
                      decoration: const InputDecoration(
                        labelText: 'Bridge Token (必填)',
                        hintText: 'cc-connect config.toml 中的 token',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: projectController,
                      decoration: const InputDecoration(
                        labelText: '目标项目 (Project)',
                        hintText: 'default',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: isTesting ? null : doTest,
                          icon: isTesting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Lucide.Activity, size: 16),
                          label: const Text('测试连接'),
                        ),
                        const SizedBox(width: 8),
                        if (testResult != null)
                          Expanded(
                            child: Text(
                              testResult!,
                              style: TextStyle(
                                fontSize: 12,
                                color: testResult!.startsWith('✓')
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final url = urlController.text.trim();
                    final token = tokenController.text.trim();
                    final project = projectController.text.trim();

                    if (name.isEmpty || url.isEmpty || token.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请填写完整的名称、地址与 Token')),
                      );
                      return;
                    }

                    final settings = context.read<SettingsProvider>();
                    if (isNew) {
                      final newEp = RemoteBridgeEndpoint.create(
                        name: name,
                        url: url,
                        token: token,
                        project: project.isEmpty ? 'default' : project,
                      );
                      await settings.addRemoteBridgeEndpoint(newEp);
                    } else {
                      final updated = endpoint.copyWith(
                        name: name,
                        url: url,
                        token: token,
                        project: project.isEmpty ? 'default' : project,
                      );
                      await settings.updateRemoteBridgeEndpoint(updated);
                    }

                    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final endpoints = settings.remoteBridgeEndpoints;

    return Scaffold(
      appBar: AppBar(
        title: const Text('远程桌面 Agent (cc-connect)'),
        actions: [
          IconButton(
            icon: const Icon(Lucide.Plus),
            tooltip: '添加节点',
            onPressed: () => _showEditDialog(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Lucide.BadgeInfo, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '如何连接桌面端 AI Agent？',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: AppFontWeights.semibold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1. 电脑端启动 cc-connect（开启 [bridge] 监听 :9810）\n'
                        '2. 填入电脑的局域网 IP、Tailscale 组网 IP 或穿透域名\n'
                        '3. 在“助手”设置中选择绑定的桌面 Agent，即可在移动端随时操控 Claude Code、Antigravity、Codex 等！',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (endpoints.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Lucide.Server, size: 48, color: cs.outline),
                    const SizedBox(height: 12),
                    Text(
                      '暂无已配置的桌面 Agent 节点',
                      style: TextStyle(color: cs.outline),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _showEditDialog(),
                      icon: const Icon(Lucide.Plus, size: 18),
                      label: const Text('添加第一个节点'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '已配置节点 (${endpoints.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Card(
              elevation: 0,
              color: cs.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: endpoints.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                itemBuilder: (ctx, idx) {
                  final ep = endpoints[idx];
                  final latency = _latencies[ep.id];
                  final isTesting = _testing[ep.id] ?? false;

                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      child: const Icon(Lucide.Terminal, size: 20),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ep.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: AppFontWeights.medium,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (isTesting)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (latency != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: latency > 0
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              latency > 0 ? '${latency}ms' : '连接失败',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: latency > 0 ? Colors.green : Colors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          ep.url,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '项目: ${ep.project}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.outline,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Lucide.Activity, size: 18),
                          tooltip: '测试连接',
                          onPressed: isTesting ? null : () => _testEndpoint(ep),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Lucide.MoreVertical, size: 18),
                          onSelected: (val) async {
                            if (val == 'edit') {
                              _showEditDialog(endpoint: ep);
                            } else if (val == 'delete') {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('删除节点'),
                                  content: Text('确定要删除节点 "${ep.name}" 吗？'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await settings.removeRemoteBridgeEndpoint(ep.id);
                              }
                            }
                          },
                          itemBuilder: (c) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Lucide.Edit2, size: 16),
                                  SizedBox(width: 8),
                                  Text('编辑'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Lucide.Trash2, size: 16, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('删除', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
