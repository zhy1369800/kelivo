import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/system_permission_policy.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../features/home/services/local_tools_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';
import '../../../core/services/haptics.dart';

class SystemPermissionsPage extends StatelessWidget {
  const SystemPermissionsPage({super.key});

  static const List<String> systemTools = [
    LocalToolNames.healthKit,
    LocalToolNames.calendarEvent,
    LocalToolNames.reminderTask,
    LocalToolNames.locationInfo,
    LocalToolNames.mapKit,
    LocalToolNames.weatherKit,
    LocalToolNames.userNotification,
    LocalToolNames.bleBridge,
    LocalToolNames.clipboard,
    LocalToolNames.deviceInfo,
    LocalToolNames.alarmTimer,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IconButton(
            icon: Icon(Lucide.ArrowLeft, color: cs.onSurface, size: 22),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(
          l10n.systemPermissionsPageTitle,
          style: const TextStyle(fontWeight: AppFontWeights.semibold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonal(
              onPressed: () async {
                HapticFeedbackService.lightImpact();
                await settings.setAllSystemPermissionPolicies(
                  SystemPermissionPolicy.bypass,
                  systemTools,
                );
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                l10n.systemPermissionsBypassAll,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.medium,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              l10n.systemPermissionsSectionHeader,
              style: TextStyle(
                fontSize: 13,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < systemTools.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 52,
                      endIndent: 16,
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  _PermissionRow(
                    toolName: systemTools[i],
                    policy: settings.getSystemPermissionPolicy(systemTools[i]),
                    onChanged: (newPolicy) {
                      HapticFeedbackService.selectionClick();
                      settings.setSystemPermissionPolicy(systemTools[i], newPolicy);
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.systemPermissionsFooterNote,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.toolName,
    required this.policy,
    required this.onChanged,
  });

  final String toolName;
  final SystemPermissionPolicy policy;
  final ValueChanged<SystemPermissionPolicy> onChanged;

  IconData _getIcon() {
    switch (toolName) {
      case LocalToolNames.healthKit:
        return Lucide.Heart;
      case LocalToolNames.calendarEvent:
        return Lucide.Calendar;
      case LocalToolNames.reminderTask:
        return Lucide.CheckSquare;
      case LocalToolNames.locationInfo:
      case LocalToolNames.mapKit:
        return Lucide.Map;
      case LocalToolNames.weatherKit:
        return Lucide.Sun;
      case LocalToolNames.userNotification:
        return Lucide.Vibrate;
      case LocalToolNames.bleBridge:
        return Lucide.Cable;
      case LocalToolNames.clipboard:
        return Lucide.Clipboard;
      case LocalToolNames.deviceInfo:
        return Lucide.Phone;
      case LocalToolNames.alarmTimer:
      default:
        return Lucide.clock;
    }
  }

  String _getTitle(AppLocalizations l10n) {
    switch (toolName) {
      case LocalToolNames.healthKit:
        return 'HealthKit';
      case LocalToolNames.calendarEvent:
        return 'Calendar';
      case LocalToolNames.reminderTask:
        return 'Reminders';
      case LocalToolNames.locationInfo:
        return 'Location';
      case LocalToolNames.mapKit:
        return 'MapKit';
      case LocalToolNames.weatherKit:
        return 'WeatherKit';
      case LocalToolNames.userNotification:
        return 'Notifications';
      case LocalToolNames.bleBridge:
        return 'Bluetooth BLE';
      case LocalToolNames.clipboard:
        return 'Clipboard';
      case LocalToolNames.deviceInfo:
        return 'Device Info';
      case LocalToolNames.alarmTimer:
        return 'Alarms & Timers';
      default:
        return toolName;
    }
  }

  String _getSubtitle(AppLocalizations l10n) {
    switch (toolName) {
      case LocalToolNames.healthKit:
        return 'Steps, heart rate, sleep, and health records';
      case LocalToolNames.calendarEvent:
        return 'Events, schedules, and calendar details';
      case LocalToolNames.reminderTask:
        return 'Tasks, due dates, and reminder lists';
      case LocalToolNames.locationInfo:
        return 'Current GPS coordinates and location history';
      case LocalToolNames.mapKit:
        return 'Search places, route navigation, and Apple Maps';
      case LocalToolNames.weatherKit:
        return 'Real-time weather, forecasts, and severe alerts';
      case LocalToolNames.userNotification:
        return 'Immediate & scheduled local notifications';
      case LocalToolNames.bleBridge:
        return 'Peripheral scanning, GATT discovery, read/write';
      case LocalToolNames.clipboard:
        return 'Text and images copied to device clipboard';
      case LocalToolNames.deviceInfo:
        return 'Hardware model, iOS version, RAM, and battery';
      case LocalToolNames.alarmTimer:
        return 'System alarms, countdown timers, and clock';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    String labelText;
    Color labelColor;

    switch (policy) {
      case SystemPermissionPolicy.bypass:
        labelText = l10n.systemPermissionsPolicyBypass;
        labelColor = cs.primary;
        break;
      case SystemPermissionPolicy.ask:
        labelText = l10n.systemPermissionsPolicyAsk;
        labelColor = cs.onSurface.withValues(alpha: 0.7);
        break;
      case SystemPermissionPolicy.deny:
        labelText = l10n.systemPermissionsPolicyDeny;
        labelColor = cs.error;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(_getIcon(), size: 20, color: cs.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getTitle(l10n),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.medium,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getSubtitle(l10n),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<SystemPermissionPolicy>(
            initialValue: policy,
            onSelected: onChanged,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labelText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppFontWeights.semibold,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Lucide.ChevronsUpDown,
                    size: 14,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: SystemPermissionPolicy.bypass,
                child: Row(
                  children: [
                    Icon(Lucide.Check, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(l10n.systemPermissionsPolicyBypass),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SystemPermissionPolicy.ask,
                child: Row(
                  children: [
                    Icon(Lucide.HelpCircle, size: 16, color: cs.onSurface.withValues(alpha: 0.7)),
                    const SizedBox(width: 8),
                    Text(l10n.systemPermissionsPolicyAsk),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SystemPermissionPolicy.deny,
                child: Row(
                  children: [
                    Icon(Lucide.Ban, size: 16, color: cs.error),
                    const SizedBox(width: 8),
                    Text(l10n.systemPermissionsPolicyDeny),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
