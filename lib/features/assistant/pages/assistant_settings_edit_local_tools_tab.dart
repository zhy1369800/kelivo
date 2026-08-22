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
    final screenTimeEnabled = assistant.localToolIds.contains(
      LocalToolNames.screenTime,
    );
    final calendarQueryEnabled = assistant.localToolIds.contains(
      LocalToolNames.calendarQuery,
    );
    final calendarCreateEnabled = assistant.localToolIds.contains(
      LocalToolNames.calendarCreate,
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
    final appleVisionEnabled = assistant.localToolIds.contains(
      LocalToolNames.appleVision,
    );
    final speechRecognizerEnabled = assistant.localToolIds.contains(
      LocalToolNames.speechRecognizer,
    );
    final speechSynthesizerEnabled = assistant.localToolIds.contains(
      LocalToolNames.speechSynthesizer,
    );
    final shortcutAutomationEnabled = assistant.localToolIds.contains(
      LocalToolNames.shortcutAutomation,
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

    Future<void> toggleTool(String toolId, bool value) async {
      if (!value) {
        await updateTool(toolId, false);
        return;
      }

      if (toolId == LocalToolNames.screenTime &&
          DeviceLocalTools.screenTimeSupported) {
        final granted = await DeviceLocalTools.hasUsageStatsPermission();
        if (!granted) {
          if (context.mounted) {
            showAppSnackBar(
              context,
              message: l10n.chatMessageWidgetScreenTimePermissionRequired,
              type: NotificationType.warning,
            );
          }
          await DeviceLocalTools.openUsageAccessSettings();
        }
        // Still enable even if Usage Access is not granted yet.
        await updateTool(toolId, true);
        return;
      }

      if ((toolId == LocalToolNames.calendarQuery ||
              toolId == LocalToolNames.calendarCreate) &&
          DeviceLocalTools.calendarSupported) {
        final granted = await DeviceLocalTools.hasCalendarPermission();
        if (!granted) {
          final requested = await DeviceLocalTools.requestCalendarPermission();
          if (!requested) {
            // Do not enable until the user grants calendar access.
            return;
          }
        }
        await updateTool(toolId, true);
        return;
      }

      await updateTool(toolId, true);
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
              onChanged: (value) => toggleTool(LocalToolNames.timeInfo, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Clipboard,
              title: l10n.assistantEditLocalToolClipboardTitle,
              subtitle: l10n.assistantEditLocalToolClipboardSubtitle,
              enabled: clipboardEnabled,
              onChanged: (value) => toggleTool(LocalToolNames.clipboard, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Volume2,
              title: l10n.assistantEditLocalToolTextToSpeechTitle,
              subtitle: l10n.assistantEditLocalToolTextToSpeechSubtitle,
              enabled: textToSpeechEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.textToSpeech, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.MessageCircleQuestionMark,
              title: l10n.assistantEditLocalToolAskUserTitle,
              subtitle: l10n.assistantEditLocalToolAskUserSubtitle,
              enabled: askUserEnabled,
              onChanged: (value) => toggleTool(LocalToolNames.askUser, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Calculator,
              title: l10n.assistantEditLocalToolCalculateTitle,
              subtitle: l10n.assistantEditLocalToolCalculateSubtitle,
              enabled: calculateEnabled,
              onChanged: (value) => toggleTool(LocalToolNames.calculate, value),
            ),
            if (DeviceLocalTools.screenTimeSupported) ...[
              _iosDivider(context),
              _LocalToolRow(
                icon: Lucide.Smartphone,
                title: l10n.assistantEditLocalToolScreenTimeTitle,
                subtitle: l10n.assistantEditLocalToolScreenTimeSubtitle,
                enabled: screenTimeEnabled,
                onChanged: (value) =>
                    toggleTool(LocalToolNames.screenTime, value),
              ),
            ],
            if (DeviceLocalTools.calendarSupported) ...[
              _iosDivider(context),
              _LocalToolRow(
                icon: Lucide.Calendar,
                title: l10n.assistantEditLocalToolCalendarQueryTitle,
                subtitle: l10n.assistantEditLocalToolCalendarQuerySubtitle,
                enabled: calendarQueryEnabled,
                onChanged: (value) =>
                    toggleTool(LocalToolNames.calendarQuery, value),
              ),
              _iosDivider(context),
              _LocalToolRow(
                icon: Lucide.CalendarPlus,
                title: l10n.assistantEditLocalToolCalendarCreateTitle,
                subtitle: l10n.assistantEditLocalToolCalendarCreateSubtitle,
                enabled: calendarCreateEnabled,
                onChanged: (value) =>
                    toggleTool(LocalToolNames.calendarCreate, value),
              ),
            ],
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
              icon: Lucide.Cable,
              title: l10n.assistantEditLocalToolBleBridgeTitle,
              subtitle: l10n.assistantEditLocalToolBleBridgeSubtitle,
              enabled: bleBridgeEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.bleBridge, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Vibrate,
              title: l10n.assistantEditLocalToolUserNotificationTitle,
              subtitle: l10n.assistantEditLocalToolUserNotificationSubtitle,
              enabled: userNotificationEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.userNotification, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Phone,
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
              icon: Lucide.clock,
              title: l10n.assistantEditLocalToolAlarmTimerTitle,
              subtitle: l10n.assistantEditLocalToolAlarmTimerSubtitle,
              enabled: alarmTimerEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.alarmTimer, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Eye,
              title: l10n.assistantEditLocalToolAppleVisionTitle,
              subtitle: l10n.assistantEditLocalToolAppleVisionSubtitle,
              enabled: appleVisionEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.appleVision, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Mic,
              title: l10n.assistantEditLocalToolSpeechRecognizerTitle,
              subtitle: l10n.assistantEditLocalToolSpeechRecognizerSubtitle,
              enabled: speechRecognizerEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.speechRecognizer, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Volume2,
              title: l10n.assistantEditLocalToolSpeechSynthesizerTitle,
              subtitle: l10n.assistantEditLocalToolSpeechSynthesizerSubtitle,
              enabled: speechSynthesizerEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.speechSynthesizer, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Zap,
              title: l10n.assistantEditLocalToolShortcutAutomationTitle,
              subtitle: l10n.assistantEditLocalToolShortcutAutomationSubtitle,
              enabled: shortcutAutomationEnabled,
              onChanged: (value) =>
                  updateTool(LocalToolNames.shortcutAutomation, value),
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
