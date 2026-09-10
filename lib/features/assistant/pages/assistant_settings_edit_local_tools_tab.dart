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
    final locationInfoEnabled = assistant.localToolIds.contains(
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
    final fileSystemEnabled = assistant.localToolIds.contains(
      LocalToolNames.fileSystem,
    );
    final locationEnabled = assistant.localToolIds.contains(
      LocalToolNames.currentLocation,
    );
    final weatherEnabled = assistant.localToolIds.contains(
      LocalToolNames.weather,
    );
    final healthEnabled = assistant.localToolIds.contains(
      LocalToolNames.healthSummary,
    );
    final remindersQueryEnabled = assistant.localToolIds.contains(
      LocalToolNames.remindersQuery,
    );
    final remindersCreateEnabled = assistant.localToolIds.contains(
      LocalToolNames.remindersCreate,
    );
    final remindersCompleteEnabled = assistant.localToolIds.contains(
      LocalToolNames.remindersComplete,
    );

    Future<void> toggleTool(String toolId, bool value) {
      return setLocalToolEnabled(
        context,
        assistant: assistant,
        toolId: toolId,
        value: value,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        SectionCard(
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
                  toggleTool(LocalToolNames.mcpServersTool, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Map,
              title: l10n.assistantEditLocalToolLocationTitle,
              subtitle: l10n.assistantEditLocalToolLocationSubtitle,
              enabled: locationInfoEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.locationInfo, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Map,
              title: l10n.assistantEditLocalToolMapKitTitle,
              subtitle: l10n.assistantEditLocalToolMapKitSubtitle,
              enabled: mapKitEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.mapKit, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Sun,
              title: l10n.assistantEditLocalToolWeatherKitTitle,
              subtitle: l10n.assistantEditLocalToolWeatherKitSubtitle,
              enabled: weatherKitEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.weatherKit, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Cable,
              title: l10n.assistantEditLocalToolBleBridgeTitle,
              subtitle: l10n.assistantEditLocalToolBleBridgeSubtitle,
              enabled: bleBridgeEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.bleBridge, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Vibrate,
              title: l10n.assistantEditLocalToolUserNotificationTitle,
              subtitle: l10n.assistantEditLocalToolUserNotificationSubtitle,
              enabled: userNotificationEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.userNotification, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Phone,
              title: l10n.assistantEditLocalToolDeviceInfoTitle,
              subtitle: l10n.assistantEditLocalToolDeviceInfoSubtitle,
              enabled: deviceInfoEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.deviceInfo, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Heart,
              title: l10n.assistantEditLocalToolHealthKitTitle,
              subtitle: l10n.assistantEditLocalToolHealthKitSubtitle,
              enabled: healthKitEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.healthKit, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Calendar,
              title: l10n.assistantEditLocalToolCalendarEventTitle,
              subtitle: l10n.assistantEditLocalToolCalendarEventSubtitle,
              enabled: calendarEventEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.calendarEvent, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.CheckSquare,
              title: l10n.assistantEditLocalToolReminderTaskTitle,
              subtitle: l10n.assistantEditLocalToolReminderTaskSubtitle,
              enabled: reminderTaskEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.reminderTask, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.clock,
              title: l10n.assistantEditLocalToolAlarmTimerTitle,
              subtitle: l10n.assistantEditLocalToolAlarmTimerSubtitle,
              enabled: alarmTimerEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.alarmTimer, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Eye,
              title: l10n.assistantEditLocalToolAppleVisionTitle,
              subtitle: l10n.assistantEditLocalToolAppleVisionSubtitle,
              enabled: appleVisionEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.appleVision, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Mic,
              title: l10n.assistantEditLocalToolSpeechRecognizerTitle,
              subtitle: l10n.assistantEditLocalToolSpeechRecognizerSubtitle,
              enabled: speechRecognizerEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.speechRecognizer, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Volume2,
              title: l10n.assistantEditLocalToolSpeechSynthesizerTitle,
              subtitle: l10n.assistantEditLocalToolSpeechSynthesizerSubtitle,
              enabled: speechSynthesizerEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.speechSynthesizer, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.Zap,
              title: l10n.assistantEditLocalToolShortcutAutomationTitle,
              subtitle: l10n.assistantEditLocalToolShortcutAutomationSubtitle,
              enabled: shortcutAutomationEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.shortcutAutomation, value),
            ),
            _iosDivider(context),
            _LocalToolRow(
              icon: Lucide.FolderOpen,
              title: l10n.assistantEditLocalToolFileSystemTitle,
              subtitle: l10n.assistantEditLocalToolFileSystemSubtitle,
              enabled: fileSystemEnabled,
              onChanged: (value) =>
                  toggleTool(LocalToolNames.fileSystem, value),
            ),
            if (fileSystemEnabled && NativeFileSystemService.isSupported) ...[
              _iosDivider(context),
              _LocalToolSubActionRow(
                icon: Lucide.FolderOpen,
                title: l10n.fileSystemManageAuthorizedPathsTitle,
                subtitle: l10n.fileSystemManageAuthorizedPathsSubtitle,
                onTap: () => _showAuthorizedPathsModal(context),
              ),
            ],
            if (DeviceLocalTools.locationSupported) ...[
              _iosDivider(context),
              _LocalToolRow(
                icon: Lucide.MapPin,
                title: l10n.assistantEditLocalToolLocationTitle,
                subtitle: l10n.assistantEditLocalToolLocationSubtitle,
                enabled: locationEnabled,
                onChanged: (value) =>
                    toggleTool(LocalToolNames.currentLocation, value),
              ),
            ],
            if (DeviceLocalTools.iosDeviceToolsSupported)
              FutureBuilder<bool>(
                future: DeviceLocalTools.prefetchIosCapabilities(),
                builder: (context, snapshot) {
                  if (!DeviceLocalTools.weatherSupported) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _iosDivider(context),
                      _LocalToolRow(
                        icon: Lucide.CloudSun,
                        title: l10n.assistantEditLocalToolWeatherTitle,
                        subtitle: l10n.assistantEditLocalToolWeatherSubtitle,
                        enabled: weatherEnabled,
                        onChanged: (value) =>
                            toggleTool(LocalToolNames.weather, value),
                      ),
                    ],
                  );
                },
              ),
            if (DeviceLocalTools.remindersSupported) ...[
              _iosDivider(context),
              _LocalToolRow(
                icon: Lucide.ListTodo,
                title: l10n.assistantEditLocalToolRemindersQueryTitle,
                subtitle: l10n.assistantEditLocalToolRemindersQuerySubtitle,
                enabled: remindersQueryEnabled,
                onChanged: (value) =>
                    toggleTool(LocalToolNames.remindersQuery, value),
              ),
              _iosDivider(context),
              _LocalToolRow(
                icon: Lucide.ListPlus,
                title: l10n.assistantEditLocalToolRemindersCreateTitle,
                subtitle: l10n.assistantEditLocalToolRemindersCreateSubtitle,
                enabled: remindersCreateEnabled,
                onChanged: (value) =>
                    toggleTool(LocalToolNames.remindersCreate, value),
              ),
              _iosDivider(context),
              _LocalToolRow(
                icon: Lucide.CheckCircle,
                title: l10n.assistantEditLocalToolRemindersCompleteTitle,
                subtitle: l10n.assistantEditLocalToolRemindersCompleteSubtitle,
                enabled: remindersCompleteEnabled,
                onChanged: (value) =>
                    toggleTool(LocalToolNames.remindersComplete, value),
              ),
            ],
            if (DeviceLocalTools.iosDeviceToolsSupported)
              FutureBuilder<bool>(
                future: DeviceLocalTools.prefetchIosCapabilities(),
                builder: (context, snapshot) {
                  if (!DeviceLocalTools.healthSupported) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _iosDivider(context),
                      _HealthToolRow(
                        title: l10n.assistantEditLocalToolHealthTitle,
                        subtitle: l10n.assistantEditLocalToolHealthSubtitle,
                        selectedSummary: l10n
                            .assistantEditLocalToolHealthSelectedCount(
                              HealthDataTypeIds.intersectAvailable(
                                assistant.healthDataTypeIds,
                                DeviceLocalTools.availableHealthTypeIds,
                              ).length,
                              DeviceLocalTools.availableHealthTypeIds.length,
                            ),
                        enabled: healthEnabled,
                        onChanged: (value) =>
                            toggleTool(LocalToolNames.healthSummary, value),
                        onOpenSettings: () =>
                            HealthDataSettingsPage.open(context, assistantId),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  void _showAuthorizedPathsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _AuthorizedPathsSheet(),
    );
  }
}

class _LocalToolSubActionRow extends StatelessWidget {
  const _LocalToolSubActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _TactileRow(
      onTap: onTap,
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
                      size: 18,
                      color: cs.primary,
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
                            fontSize: 14,
                            color: color,
                            fontWeight: AppFontWeights.medium,
                          ),
                        ),
                        const SizedBox(height: 2),
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
                  const SizedBox(width: 8),
                  Icon(
                    Lucide.ChevronRight,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AuthorizedPathsSheet extends StatefulWidget {
  const _AuthorizedPathsSheet();

  @override
  State<_AuthorizedPathsSheet> createState() => _AuthorizedPathsSheetState();
}

class _AuthorizedPathsSheetState extends State<_AuthorizedPathsSheet> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await NativeFileSystemService.listBookmarks();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _revoke(String path, String name, AppLocalizations l10n) async {
    final ok = await NativeFileSystemService.revokeBookmark(path);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _items = _items.where((e) => e['path'] != path).toList();
      });
      showAppSnackBar(
        context,
        message: l10n.fileSystemRevokeSuccess(name),
        type: NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.fileSystemAuthorizedPathsSheetTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: AppFontWeights.emphasis,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.fileSystemAuthorizedPathsSheetSubtitle,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (_items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Lucide.Folder,
                    size: 36,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.fileSystemAuthorizedPathsEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final path = (item['path'] ?? '').toString();
                  final name = (item['name'] ?? '').toString();
                  final isDir = item['is_directory'] == true;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      child: Icon(
                        isDir ? Lucide.Folder : Lucide.FileText,
                        size: 18,
                        color: cs.primary,
                      ),
                    ),
                    title: Text(
                      name.isNotEmpty ? name : path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.medium,
                      ),
                    ),
                    subtitle: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Lucide.Trash2,
                        size: 18,
                        color: cs.error,
                      ),
                      onPressed: () =>
                          _revoke(path, name.isNotEmpty ? name : path, l10n),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
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

class _HealthToolRow extends StatelessWidget {
  const _HealthToolRow({
    required this.title,
    required this.subtitle,
    required this.selectedSummary,
    required this.enabled,
    required this.onChanged,
    required this.onOpenSettings,
  });

  final String title;
  final String subtitle;
  final String selectedSummary;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _TactileRow(
              onTap: onOpenSettings,
              builder: (pressed) {
                final baseColor = cs.onSurface.withValues(alpha: 0.9);
                return _AnimatedPressColor(
                  pressed: pressed,
                  base: baseColor,
                  builder: (color) {
                    return Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Icon(
                            Lucide.HeartPulse,
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
                              const SizedBox(height: 3),
                              Text(
                                selectedSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.25,
                                  color: cs.primary.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Lucide.ChevronRight,
                          size: 16,
                          color: cs.onSurface.withValues(alpha: 0.35),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          IosSwitch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}
