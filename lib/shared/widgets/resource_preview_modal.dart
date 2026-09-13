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

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String content,
    String? filePath,
    bool isMarkdown = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final fileExists = filePath != null && File(filePath).existsSync();

    final actions = <Widget>[
      IosIconButton(
        icon: Lucide.Copy,
        size: 18,
        padding: const EdgeInsets.all(5),
        color: cs.onSurface.withValues(alpha: 0.72),
        semanticLabel: '复制内容',
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: content));
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
            await OpenFilex.open(filePath);
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
                files: [XFile(filePath)],
                sharePositionOrigin: anchor,
              ),
            );
          },
        ),
      ],
    ];

    return showCustomBottomSheet<void>(
      context: context,
      title: title,
      leading: Icon(
        Lucide.FileText,
        size: 17,
        color: cs.primary.withValues(alpha: 0.85),
      ),
      actions: actions,
      showDivider: true,
      expandedHeightFactor: 0.90,
      partialHeightFactor: 0.65,
      builder: (ctx, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: isMarkdown
              ? MarkdownWithCodeHighlight(text: content)
              : SelectableText(
                  content,
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

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
