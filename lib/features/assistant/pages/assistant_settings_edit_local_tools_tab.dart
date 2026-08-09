part of 'assistant_settings_edit_page.dart';

class _LocalToolsTab extends StatelessWidget {
  const _LocalToolsTab({required this.assistantId});
  final String assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ap = context.watch<AssistantProvider>();
    final assistant = ap.getById(assistantId)!;
    final timeEnabled = assistant.localToolIds.contains(
      LocalToolNames.timeInfo,
    );
    final clipboardEnabled = assistant.localToolIds.contains(
      LocalToolNames.clipboard,
    );
    final textToSpeechEnabled = assistant.localToolIds.contains(
      LocalToolNames.textToSpeech,
    );
    final askUserEnabled = assistant.localToolIds.contains(
      LocalToolNames.askUser,
    );
    final calculateEnabled = assistant.localToolIds.contains(
      LocalToolNames.calculate,
    );
    final mcpServersToolEnabled = assistant.localToolIds.contains(
      LocalToolNames.mcpServersTool,
    );
    final locationEnabled = assistant.localToolIds.contains(
      LocalToolNames.locationInfo,
    );
    final mapKitEnabled = assistant.localToolIds.contains(
      LocalToolNames.mapKit,
    );
    final weatherKitEnabled = assistant.localToolIds.contains(
      LocalToolNames.weatherKit,
    );
    final bleBridgeEnabled = assistant.localToolIds.contains(
      LocalToolNames.bleBridge,
    );
    final userNotificationEnabled = assistant.localToolIds.contains(
      LocalToolNames.userNotification,
    );
    final deviceInfoEnabled = assistant.localToolIds.contains(
      LocalToolNames.deviceInfo,
    );
    final healthKitEnabled = assistant.localToolIds.contains(
      LocalToolNames.healthKit,
    );
    final calendarEventEnabled = assistant.localToolIds.contains(
      LocalToolNames.calendarEvent,
    );
    final reminderTaskEnabled = assistant.localToolIds.contains(
      LocalToolNames.reminderTask,
    );
    final alarmTimerEnabled = assistant.localToolIds.contains(
      LocalToolNames.alarmTimer,
    );

    Future<void> updateTool(String toolId, bool value) {
      final ids = assistant.localToolIds.toSet();
      if (value) {
        ids.add(toolId);
      } else {
        ids.remove(toolId);
      }
      return context.read<AssistantProvider>().updateAssistant(
        assistant.copyWith(localToolIds: ids.toList(growable: false)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        _iosSectionCard(
          children: [
            _LocalToolRow(
              icon: Lucide.clock,
              title: l10n.assistantEditLocalToolTimeInfoTitle,
              subtitle: l10n.assistantEditLocalToolTimeInfoSubtitle,
              enabled: timeEnabled,
              onChanged: (value) => updateTool(LocalToolNames.timeInfo, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Clipboard,
              title: l10n.assistantEditLocalToolClipboardTitle,
              subtitle: l10n.assistantEditLocalToolClipboardSubtitle,
              enabled: clipboardEnabled,
              onChanged: (value) => updateTool(LocalToolNames.clipboard, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Volume2,
              title: l10n.assistantEditLocalToolTextToSpeechTitle,
              subtitle: l10n.assistantEditLocalToolTextToSpeechSubtitle,
              enabled: textToSpeechEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.textToSpeech, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.MessageCircleQuestionMark,
              title: l10n.assistantEditLocalToolAskUserTitle,
              subtitle: l10n.assistantEditLocalToolAskUserSubtitle,
              enabled: askUserEnabled,
              onChanged: (value) => updateTool(LocalToolNames.askUser, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Calculator,
              title: l10n.assistantEditLocalToolCalculateTitle,
              subtitle: l10n.assistantEditLocalToolCalculateSubtitle,
              enabled: calculateEnabled,
              onChanged: (value) => updateTool(LocalToolNames.calculate, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Boxes,
              title: l10n.assistantEditLocalToolMcpServersTitle,
              subtitle: l10n.assistantEditLocalToolMcpServersSubtitle,
              enabled: mcpServersToolEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.mcpServersTool, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Map,
              title: l10n.assistantEditLocalToolLocationTitle,
              subtitle: l10n.assistantEditLocalToolLocationSubtitle,
              enabled: locationEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.locationInfo, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Map,
              title: l10n.assistantEditLocalToolMapKitTitle,
              subtitle: l10n.assistantEditLocalToolMapKitSubtitle,
              enabled: mapKitEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.mapKit, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Sun,
              title: l10n.assistantEditLocalToolWeatherKitTitle,
              subtitle: l10n.assistantEditLocalToolWeatherKitSubtitle,
              enabled: weatherKitEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.weatherKit, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Bluetooth,
              title: l10n.assistantEditLocalToolBleBridgeTitle,
              subtitle: l10n.assistantEditLocalToolBleBridgeSubtitle,
              enabled: bleBridgeEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.bleBridge, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Bell,
              title: l10n.assistantEditLocalToolUserNotificationTitle,
              subtitle: l10n.assistantEditLocalToolUserNotificationSubtitle,
              enabled: userNotificationEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.userNotification, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Smartphone,
              title: l10n.assistantEditLocalToolDeviceInfoTitle,
              subtitle: l10n.assistantEditLocalToolDeviceInfoSubtitle,
              enabled: deviceInfoEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.deviceInfo, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Heart,
              title: l10n.assistantEditLocalToolHealthKitTitle,
              subtitle: l10n.assistantEditLocalToolHealthKitSubtitle,
              enabled: healthKitEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.healthKit, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Calendar,
              title: l10n.assistantEditLocalToolCalendarEventTitle,
              subtitle: l10n.assistantEditLocalToolCalendarEventSubtitle,
              enabled: calendarEventEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.calendarEvent, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.CheckSquare,
              title: l10n.assistantEditLocalToolReminderTaskTitle,
              subtitle: l10n.assistantEditLocalToolReminderTaskSubtitle,
              enabled: reminderTaskEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.reminderTask, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Clock,
              title: l10n.assistantEditLocalToolAlarmTimerTitle,
              subtitle: l10n.assistantEditLocalToolAlarmTimerSubtitle,
              enabled: alarmTimerEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.alarmTimer, value),
            ),
          ],
        ),
      ],
    );
  }
}

class _LocalToolRow extends StatelessWidget {
  const _LocalToolRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _TactileRow(
      onTap: () => onChanged(!enabled),
      builder: (pressed) {
        final baseColor = cs.onSurface.withValues(alpha: 0.9);
        return _AnimatedPressColor(
          pressed: pressed,
          base: baseColor,
          builder: (color) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    child: Icon(
                      icon,
                      size: 20,
                      color: enabled ? cs.primary : color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: color,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: cs.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  IosSwitch(value: enabled, onChanged: onChanged),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
