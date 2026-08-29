import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../icons/lucide_adapter.dart';
import 'custom_bottom_sheet.dart';
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
    return showCustomBottomSheet<void>(
      context: context,
      title: title,
      expandedHeightFactor: 0.90,
      partialHeightFactor: 0.65,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '复制内容',
                    icon: const Icon(Lucide.Copy, size: 20),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (ctx.mounted) {
                        showAppSnackBar(
                          ctx,
                          message: '已复制到剪贴板',
                          type: NotificationType.success,
                        );
                      }
                    },
                  ),
                  if (filePath != null && File(filePath).existsSync()) ...[
                    IconButton(
                      tooltip: '使用系统应用打开',
                      icon: const Icon(Lucide.ExternalLink, size: 20),
                      onPressed: () async {
                        await OpenFilex.open(filePath);
                      },
                    ),
                    IconButton(
                      tooltip: '分享文件',
                      icon: const Icon(Lucide.Share2, size: 20),
                      onPressed: () async {
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
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
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
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
