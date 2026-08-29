import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../features/chat/pages/image_viewer_page.dart';
import '../../../shared/pages/webview_page.dart';
import '../../../shared/widgets/resource_preview_modal.dart';
import '../../../shared/widgets/snackbar.dart';

/// Result of an open/preview resource operation.
class ResourceOpenResult {
  final bool success;
  final String message;
  final String target;
  final String openedAs;

  const ResourceOpenResult({
    required this.success,
    required this.message,
    required this.target,
    required this.openedAs,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'message': message,
    'target': target,
    'opened_as': openedAs,
  };
}

/// Core service for opening, routing, and previewing web URLs and local files
/// across all platforms (Android, iOS, Windows, macOS, Linux).
class ResourcePreviewService extends ChangeNotifier {
  ResourcePreviewService._();
  static final ResourcePreviewService instance = ResourcePreviewService._();
  factory ResourcePreviewService() => instance;

  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.svg',
  };

  static const Set<String> _htmlExtensions = {
    '.html',
    '.htm',
  };

  static const Set<String> _markdownExtensions = {
    '.md',
    '.markdown',
  };

  static const Set<String> _textExtensions = {
    '.txt',
    '.log',
    '.json',
    '.csv',
    '.tsv',
    '.xml',
    '.yaml',
    '.yml',
    '.toml',
    '.ini',
    '.sql',
    '.env',
    '.dart',
    '.py',
    '.js',
    '.ts',
    '.jsx',
    '.tsx',
    '.c',
    '.cpp',
    '.h',
    '.hpp',
    '.swift',
    '.kt',
    '.java',
    '.sh',
    '.bat',
    '.ps1',
  };

  /// Open or preview a resource (Web URL or Local File Path).
  Future<ResourceOpenResult> openResource({
    required String target,
    String action = 'auto',
    String? title,
    BuildContext? context,
  }) async {
    final trimmed = target.trim();
    if (trimmed.isEmpty) {
      return const ResourceOpenResult(
        success: false,
        message: 'Empty target provided',
        target: '',
        openedAs: 'none',
      );
    }

    final effectiveContext = context ?? rootNavigatorKey.currentContext;

    // 1. Handle file:// URI scheme specifically
    if (trimmed.startsWith('file://')) {
      final fileUri = Uri.tryParse(trimmed);
      final localFilePath = fileUri != null ? fileUri.toFilePath() : trimmed.replaceFirst('file://', '');
      return _openLocalFile(
        targetPath: localFilePath,
        action: action,
        title: title,
        context: effectiveContext,
      );
    }

    // 2. Web URL Handling (http://, https://)
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
      return _openWebUrl(
        uri: uri,
        action: action,
        title: title,
        context: effectiveContext,
      );
    }

    // 3. General Local File Handling
    return _openLocalFile(
      targetPath: trimmed,
      action: action,
      title: title,
      context: effectiveContext,
    );
  }

  Future<ResourceOpenResult> _openWebUrl({
    required Uri uri,
    required String action,
    String? title,
    BuildContext? context,
  }) async {
    final urlString = uri.toString();
    if (action == 'system_open') {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        return ResourceOpenResult(
          success: launched,
          message: launched
              ? 'Opened in external system browser: $urlString'
              : 'Failed to open external system browser: $urlString',
          target: urlString,
          openedAs: 'system_browser',
        );
      } catch (e) {
        return ResourceOpenResult(
          success: false,
          message: 'Error opening external browser: $e',
          target: urlString,
          openedAs: 'system_browser',
        );
      }
    }

    // In-app WebView preview (default)
    if (context != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebViewPage(url: urlString),
        ),
      );
      return ResourceOpenResult(
        success: true,
        message: 'Opened in in-app WebView: $urlString',
        target: urlString,
        openedAs: 'in_app_webview',
      );
    }

    // Fallback if context is not mounted
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ResourceOpenResult(
        success: launched,
        message: 'Opened in external browser: $urlString',
        target: urlString,
        openedAs: 'system_browser',
      );
    } catch (e) {
      return ResourceOpenResult(
        success: false,
        message: 'No available UI context and failed to launch: $e',
        target: urlString,
        openedAs: 'error',
      );
    }
  }

  Future<ResourceOpenResult> _openLocalFile({
    required String targetPath,
    required String action,
    String? title,
    BuildContext? context,
  }) async {
    final file = File(targetPath);
    if (!file.existsSync()) {
      return ResourceOpenResult(
        success: false,
        message: 'Local file not found on disk: $targetPath',
        target: targetPath,
        openedAs: 'file_not_found',
      );
    }

    final ext = p.extension(targetPath).toLowerCase();
    final effectiveTitle = title ?? p.basename(targetPath);

    // Explicit share action
    if (action == 'share') {
      try {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)]),
        );
        return ResourceOpenResult(
          success: true,
          message: 'Opened system share sheet for file: $targetPath',
          target: targetPath,
          openedAs: 'share_sheet',
        );
      } catch (e) {
        return ResourceOpenResult(
          success: false,
          message: 'Failed to share file: $e',
          target: targetPath,
          openedAs: 'share_sheet',
        );
      }
    }

    // Explicit system_open action
    if (action == 'system_open') {
      final res = await OpenFilex.open(file.path);
      return ResourceOpenResult(
        success: res.type == ResultType.done,
        message: 'Opened with system default application: ${res.message}',
        target: targetPath,
        openedAs: 'system_application',
      );
    }

    // Auto or in_app_preview: Route by extension
    // 1. Image formats
    if (_imageExtensions.contains(ext)) {
      if (context != null && context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImageViewerPage(images: [file.path]),
          ),
        );
        return ResourceOpenResult(
          success: true,
          message: 'Opened in in-app Image Viewer: $targetPath',
          target: targetPath,
          openedAs: 'image_viewer',
        );
      }
    }

    // 2. HTML format
    if (_htmlExtensions.contains(ext)) {
      try {
        final content = await file.readAsString();
        if (defaultTargetPlatform == TargetPlatform.linux) {
          if (context != null && context.mounted) {
            await ResourcePreviewModal.show(
              context: context,
              title: effectiveTitle,
              content: content,
              filePath: file.path,
              isMarkdown: false,
            );
            return ResourceOpenResult(
              success: true,
              message: 'Opened HTML code preview on Linux: $targetPath',
              target: targetPath,
              openedAs: 'text_preview',
            );
          }
        }
        final base64Content = base64Encode(utf8.encode(content));
        if (context != null && context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WebViewPage(contentBase64: base64Content),
            ),
          );
          return ResourceOpenResult(
            success: true,
            message: 'Rendered HTML in in-app WebView: $targetPath',
            target: targetPath,
            openedAs: 'html_preview',
          );
        }
      } catch (e) {
        // Fall back to system open
      }
    }

    // 3. Markdown / Code / Text formats
    if (_markdownExtensions.contains(ext) || _textExtensions.contains(ext)) {
      try {
        final content = await file.readAsString();
        if (context != null && context.mounted) {
          await ResourcePreviewModal.show(
            context: context,
            title: effectiveTitle,
            content: content,
            filePath: file.path,
            isMarkdown: _markdownExtensions.contains(ext),
          );
          return ResourceOpenResult(
            success: true,
            message: 'Opened in in-app Markdown/Text Viewer: $targetPath',
            target: targetPath,
            openedAs: 'text_preview',
          );
        }
      } catch (e) {
        // Fall back to system open
      }
    }

    // 4. Default: Fallback to system application
    try {
      final res = await OpenFilex.open(file.path);
      final success = res.type == ResultType.done;
      return ResourceOpenResult(
        success: success,
        message: success
            ? 'Opened with system associated application: $targetPath'
            : 'Result from system open: ${res.message}',
        target: targetPath,
        openedAs: 'system_application',
      );
    } catch (e) {
      return ResourceOpenResult(
        success: false,
        message: 'Failed to open file: $e',
        target: targetPath,
        openedAs: 'error',
      );
    }
  }
}
