import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/remote_bridge_endpoint.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/remote_bridge/r_connect_bridge_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _testing[endpoint.id] = true;
      _latencies[endpoint.id] = null;
    });

    try {
      final latency = await RConnectBridgeService.testConnection(endpoint);
      if (mounted) {
        setState(() {
          _latencies[endpoint.id] = latency;
          _testing[endpoint.id] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.remoteAgentTestSuccess(latency)),
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
            content: Text(l10n.remoteAgentTestFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showEditSheet({RemoteBridgeEndpoint? endpoint}) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _RemoteBridgeEditSheet(
        endpoint: endpoint,
        onSave: (newOrUpdatedEndpoint) async {
          final settings = context.read<SettingsProvider>();
          if (endpoint == null) {
            await settings.addRemoteBridgeEndpoint(newOrUpdatedEndpoint);
          } else {
            await settings.updateRemoteBridgeEndpoint(newOrUpdatedEndpoint);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final endpoints = settings.remoteBridgeEndpoints;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remoteAgentSettingsPageTitle),
        actions: [
          IconButton(
            icon: const Icon(Lucide.Plus),
            tooltip: l10n.remoteAgentAddNode,
            onPressed: () => _showEditSheet(),
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
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
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
                        l10n.remoteAgentHowToConnectTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: AppFontWeights.semibold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.remoteAgentHowToConnectDesc,
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
                      l10n.remoteAgentEmpty,
                      style: TextStyle(color: cs.outline),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _showEditSheet(),
                      icon: const Icon(Lucide.Plus, size: 18),
                      label: Text(l10n.remoteAgentAddFirst),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '${l10n.remoteAgentSettingsPageTitle} (${endpoints.length})',
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
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
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

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        // Terminal Icon Avatar
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Lucide.Terminal,
                            size: 19,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Main info: Node Name + Project Pill & WS URL
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      ep.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: AppFontWeights.semibold,
                                        color: cs.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Project Badge Pill
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: cs.outlineVariant
                                            .withValues(alpha: 0.35),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Lucide.Folder,
                                          size: 10,
                                          color: cs.onSurfaceVariant
                                              .withValues(alpha: 0.75),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          ep.project.isEmpty
                                              ? 'default'
                                              : ep.project,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: AppFontWeights.medium,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                ep.url,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Status Indicator & Actions
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isTesting)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                                  latency > 0
                                      ? '${latency}ms'
                                      : l10n.remoteAgentLatencyFailed,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: latency > 0
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Lucide.Activity, size: 18),
                              tooltip: l10n.remoteAgentTestConnection,
                              onPressed: isTesting
                                  ? null
                                  : () => _testEndpoint(ep),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Lucide.MoreVertical, size: 18),
                              onSelected: (val) async {
                                if (val == 'edit') {
                                  _showEditSheet(endpoint: ep);
                                } else if (val == 'delete') {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: Text(l10n.remoteAgentDelete),
                                      content: Text(
                                        l10n.remoteAgentDeleteConfirm(ep.name),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: Text(l10n.remoteAgentCancel),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: Text(
                                            l10n.remoteAgentDelete,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await settings
                                        .removeRemoteBridgeEndpoint(ep.id);
                                  }
                                }
                              },
                              itemBuilder: (c) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Lucide.Pencil, size: 16),
                                      const SizedBox(width: 8),
                                      Text(l10n.remoteAgentEdit),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Lucide.Trash2,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.remoteAgentDelete,
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

class _RemoteBridgeEditSheet extends StatefulWidget {
  const _RemoteBridgeEditSheet({
    this.endpoint,
    required this.onSave,
  });

  final RemoteBridgeEndpoint? endpoint;
  final Future<void> Function(RemoteBridgeEndpoint endpoint) onSave;

  @override
  State<_RemoteBridgeEditSheet> createState() => _RemoteBridgeEditSheetState();
}

class _RemoteBridgeEditSheetState extends State<_RemoteBridgeEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _projectController;

  bool _obscureToken = true;
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final ep = widget.endpoint;
    _nameController = TextEditingController(text: ep?.name ?? '');
    _urlController = TextEditingController(
      text: ep?.url ?? 'ws://127.0.0.1:9810/bridge/ws',
    );
    _tokenController = TextEditingController(text: ep?.token ?? '');
    _projectController = TextEditingController(text: ep?.project ?? 'default');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    _projectController.dispose();
    super.dispose();
  }

  Future<void> _doTest() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final tempEp = RemoteBridgeEndpoint(
      id: 'temp',
      name: _nameController.text.trim(),
      url: RemoteBridgeEndpoint.normalizeBridgeUrl(
        _urlController.text.trim(),
      ),
      token: _tokenController.text.trim(),
      project: _projectController.text.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      final latency = await RConnectBridgeService.testConnection(tempEp);
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testResult = '✓ ${l10n.remoteAgentTestSuccess(latency)}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testResult = '✗ ${l10n.remoteAgentTestFailed(e.toString())}';
        });
      }
    }
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();
    final project = _projectController.text.trim();

    if (name.isEmpty || url.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remoteAgentFillRequired)),
      );
      return;
    }

    final isNew = widget.endpoint == null;
    final ep = isNew
        ? RemoteBridgeEndpoint.create(
            name: name,
            url: url,
            token: token,
            project: project.isEmpty ? 'default' : project,
          )
        : widget.endpoint!.copyWith(
            name: name,
            url: url,
            token: token,
            project: project.isEmpty ? 'default' : project,
          );

    await widget.onSave(ep);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isNew = widget.endpoint == null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.9,
          minChildSize: 0.45,
          builder: (ctx, controller) => Column(
            children: [
              const SizedBox(height: 8),
              // Top drag indicator bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              // Header title & close button
              SizedBox(
                height: 36,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        isNew
                            ? l10n.remoteAgentAddNode
                            : l10n.remoteAgentEditNode,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: AppFontWeights.semibold,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: IconButton(
                          icon: const Icon(Lucide.X, size: 20),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              // Form Body
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Node Name Input
                    _buildInputField(
                      label: l10n.remoteAgentNodeName,
                      controller: _nameController,
                      hint: l10n.remoteAgentNodeNameHint,
                    ),
                    const SizedBox(height: 14),

                    // WebSocket URL Input
                    _buildInputField(
                      label: l10n.remoteAgentWsUrl,
                      controller: _urlController,
                      hint: l10n.remoteAgentWsUrlHint,
                      helperText: l10n.remoteAgentWsUrlHelper,
                    ),
                    const SizedBox(height: 14),

                    // Bridge Token Input with Mask Toggle
                    _buildInputField(
                      label: l10n.remoteAgentToken,
                      controller: _tokenController,
                      hint: l10n.remoteAgentTokenHint,
                      obscureText: _obscureToken,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureToken ? Lucide.EyeOff : Lucide.Eye,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureToken = !_obscureToken;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Project Input
                    _buildInputField(
                      label: l10n.remoteAgentProject,
                      controller: _projectController,
                      hint: 'default',
                    ),
                    const SizedBox(height: 16),

                    // Test Connection Row
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isTesting ? null : _doTest,
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Lucide.Activity, size: 16),
                          label: Text(
                            _isTesting
                                ? l10n.remoteAgentTesting
                                : l10n.remoteAgentTestConnection,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (_testResult != null)
                          Expanded(
                            child: Text(
                              _testResult!,
                              style: TextStyle(
                                fontSize: 12,
                                color: _testResult!.startsWith('✓')
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
              // Bottom Save Button Action Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _handleSave,
                    icon: const Icon(Lucide.Check, size: 18),
                    label: Text(
                      l10n.remoteAgentSave,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? helperText,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: AppFontWeights.medium,
            color: cs.onSurface.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText,
            helperMaxLines: 2,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}

