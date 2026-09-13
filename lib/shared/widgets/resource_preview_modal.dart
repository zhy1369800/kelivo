import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../icons/lucide_adapter.dart';
import 'custom_bottom_sheet.dart';
import 'ios_tactile.dart';
import 'markdown_with_highlight.dart';
import 'snackbar.dart';

/// In-app preview modal for markdown, text, code, and documents.
class ResourcePreviewModal extends StatelessWidget {
  const ResourcePreviewModal({
    super.key,
    required this.title,
    required this.content,
    this.filePath,
    this.isMarkdown = true,
  });

  final String title;
  final String content;
  final String? filePath;
  final bool isMarkdown;

  /// Global handle to currently mounted resource preview sheet instance (if any).
  // ignore: library_private_types_in_public_api
  static _ResourcePreviewSheetState? activeState;

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String content,
    String? filePath,
    bool isMarkdown = true,
  }) async {
    final active = activeState;
    if (active != null && active.mounted) {
      active.updateTarget(
        title: title,
        content: content,
        filePath: filePath,
        isMarkdown: isMarkdown,
      );
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, _, __) {
        return _ResourcePreviewSheet(
          initialTitle: title,
          initialContent: content,
          initialFilePath: filePath,
          initialIsMarkdown: isMarkdown,
          onDismiss: () => Navigator.of(dialogContext).maybePop(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _ResourcePreviewSheet extends StatefulWidget {
  const _ResourcePreviewSheet({
    required this.initialTitle,
    required this.initialContent,
    this.initialFilePath,
    this.initialIsMarkdown = true,
    required this.onDismiss,
  });

  final String initialTitle;
  final String initialContent;
  final String? initialFilePath;
  final bool initialIsMarkdown;
  final VoidCallback onDismiss;

  @override
  State<_ResourcePreviewSheet> createState() => _ResourcePreviewSheetState();
}

class _ResourcePreviewSheetState extends State<_ResourcePreviewSheet> {
  late String _title;
  late String _content;
  String? _filePath;
  late bool _isMarkdown;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ResourcePreviewModal.activeState = this;
    _title = widget.initialTitle;
    _content = widget.initialContent;
    _filePath = widget.initialFilePath;
    _isMarkdown = widget.initialIsMarkdown;
  }

  @override
  void dispose() {
    if (ResourcePreviewModal.activeState == this) {
      ResourcePreviewModal.activeState = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  void updateTarget({
    required String title,
    required String content,
    String? filePath,
    bool isMarkdown = true,
  }) {
    setState(() {
      _title = title;
      _content = content;
      _filePath = filePath;
      _isMarkdown = isMarkdown;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fileExists = _filePath != null && File(_filePath!).existsSync();

    final actions = <Widget>[
      IosIconButton(
        icon: Lucide.Copy,
        size: 18,
        padding: const EdgeInsets.all(5),
        color: cs.onSurface.withValues(alpha: 0.72),
        semanticLabel: '复制内容',
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: _content));
          if (context.mounted) {
            showAppSnackBar(
              context,
              message: '已复制到剪贴板',
              type: NotificationType.success,
            );
          }
        },
      ),
      if (fileExists) ...[
        IosIconButton(
          icon: Lucide.ExternalLink,
          size: 18,
          padding: const EdgeInsets.all(5),
          color: cs.onSurface.withValues(alpha: 0.72),
          semanticLabel: '使用系统应用打开',
          onTap: () async {
            await OpenFilex.open(_filePath!);
          },
        ),
        IosIconButton(
          icon: Lucide.Share2,
          size: 18,
          padding: const EdgeInsets.all(5),
          color: cs.onSurface.withValues(alpha: 0.72),
          semanticLabel: '分享文件',
          onTap: () async {
            final size = MediaQuery.maybeOf(context)?.size;
            final anchor = (size != null && size.width > 0 && size.height > 0)
                ? Rect.fromCenter(
                    center: Offset(size.width / 2, size.height / 2),
                    width: 10,
                    height: 10,
                  )
                : null;
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(_filePath!)],
                sharePositionOrigin: anchor,
              ),
            );
          },
        ),
      ],
    ];

    return CustomBottomSheet(
      title: _title,
      leading: Icon(
        Lucide.FileText,
        size: 17,
        color: cs.primary.withValues(alpha: 0.85),
      ),
      actions: actions,
      showDivider: true,
      expandedHeightFactor: 0.90,
      partialHeightFactor: 0.65,
      onDismiss: widget.onDismiss,
      builder: (ctx, scrollController) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: _isMarkdown
              ? MarkdownWithCodeHighlight(text: _content)
              : SelectableText(
                  _content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
        );
      },
    );
  }
}
