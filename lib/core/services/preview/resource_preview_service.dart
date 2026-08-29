import 'dart:async';
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

import '../../../utils/app_directories.dart';
import '../../../utils/kelivo_file_uri.dart';
import '../../../utils/sandbox_path_resolver.dart';

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

  /// Open or preview a resource (Web URL, Custom App URI, or Local File Path).
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
    final initialContext = (context != null && context.mounted) ? context : null;
    // 1. Web URL Handling (http://, https://)
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
      return _openWebUrl(
        uri: uri,
        action: action,
        title: title,
        context: initialContext,
      );
    }

    // 2. Resolve local path (supports file://, kelivo-file:///, kelivo://, relative, and absolute paths)
    final resolvedPath = await _resolveLocalPath(trimmed);
    return _openLocalFile(
      targetPath: resolvedPath,
      action: action,
      title: title,
      context: (initialContext != null && initialContext.mounted) ? initialContext : null,
    );
  }

  /// Resolves custom schemes and relative paths to a canonical absolute local file path.
  Future<String> _resolveLocalPath(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;

    // 1. file:// URI scheme
    if (trimmed.startsWith('file://')) {
      final fileUri = Uri.tryParse(trimmed);
      return fileUri != null ? fileUri.toFilePath() : trimmed.replaceFirst('file://', '');
    }

    // 2. Canonical kelivo-file:/// scheme (e.g. kelivo-file:///upload/test.png)
    if (KelivoFileUri.isKelivoFileUri(trimmed)) {
      try {
        final appDataDir = await AppDirectories.getAppDataDirectory();
        final resolved = KelivoFileUri.resolveToAbsolute(trimmed, root: appDataDir.path);
        if (resolved != null) return resolved;
      } catch (_) {}
    }

    // 3. kelivo:// scheme (e.g. kelivo://workspace/test.html or kelivo://upload/photo.png)
    if (trimmed.startsWith('kelivo://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.host.isNotEmpty) {
        try {
          final appDataDir = await AppDirectories.getAppDataDirectory();
          final namespace = uri.host;
          final subpath = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
          return p.join(appDataDir.path, namespace, subpath);
        } catch (_) {}
      }
    }

    // 4. Absolute path
    if (p.isAbsolute(trimmed) || File(trimmed).existsSync()) {
      return SandboxPathResolver.fix(trimmed);
    }

    // 5. Relative path (e.g. workspace/test.html, upload/image.png)
    try {
      final appDataDir = await AppDirectories.getAppDataDirectory();
      return p.join(appDataDir.path, trimmed);
    } catch (_) {}

    return SandboxPathResolver.fix(trimmed);
  }

  Rect? _calculateShareAnchor(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final size = MediaQuery.maybeOf(context)?.size;
    if (size != null && size.width > 0 && size.height > 0) {
      return Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 10,
        height: 10,
      );
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final boxSize = renderBox.size;
      return Rect.fromCenter(
        center: Offset(boxSize.width / 2, boxSize.height / 2),
        width: 10,
        height: 10,
      );
    }
    return null;
  }

  Future<ResourceOpenResult> _openWebUrl({
    required Uri uri,
    required String action,
    String? title,
    BuildContext? context,
  }) async {
    final urlString = uri.toString();
    final effectiveContext =
        (context != null && context.mounted) ? context : rootNavigatorKey.currentContext;

    // Explicit share action for Web URL
    if (action == 'share') {
      try {
        final anchor = _calculateShareAnchor(effectiveContext);
        unawaited(
          SharePlus.instance
              .share(
                ShareParams(
                  uri: uri,
                  sharePositionOrigin: anchor,
                ),
              )
              .catchError((_) => ShareResult.unavailable),
        );
        return ResourceOpenResult(
          success: true,
          message: 'Opened system share sheet for URL: $urlString',
          target: urlString,
          openedAs: 'share_sheet',
        );
      } catch (e) {
        return ResourceOpenResult(
          success: false,
          message: 'Failed to share URL: $e',
          target: urlString,
          openedAs: 'share_sheet',
        );
      }
    }

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
    if (effectiveContext != null && effectiveContext.mounted) {
      unawaited(
        Navigator.of(effectiveContext).push(
          MaterialPageRoute<void>(
            builder: (_) => WebViewPage(url: urlString),
          ),
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
    final effectivePath = SandboxPathResolver.fix(targetPath);
    final file = File(effectivePath);
    if (!file.existsSync()) {
      return ResourceOpenResult(
        success: false,
        message: 'Local file not found on disk: $effectivePath',
        target: effectivePath,
        openedAs: 'file_not_found',
      );
    }

    final ext = p.extension(effectivePath).toLowerCase();
    final effectiveTitle = title ?? p.basename(effectivePath);
    final effectiveContext =
        (context != null && context.mounted) ? context : rootNavigatorKey.currentContext;

    // Explicit share action
    if (action == 'share') {
      try {
        final anchor = _calculateShareAnchor(effectiveContext);
        unawaited(
          SharePlus.instance
              .share(
                ShareParams(
                  files: [XFile(file.path)],
                  sharePositionOrigin: anchor,
                ),
              )
              .catchError((_) => ShareResult.unavailable),
        );
        return ResourceOpenResult(
          success: true,
          message: 'Opened system share sheet for file: $effectivePath',
          target: effectivePath,
          openedAs: 'share_sheet',
        );
      } catch (e) {
        return ResourceOpenResult(
          success: false,
          message: 'Failed to share file: $e',
          target: effectivePath,
          openedAs: 'share_sheet',
        );
      }
    }

    // Explicit system_open action
    if (action == 'system_open') {
      return _openWithSystemDefault(file.path, effectivePath);
    }

    // Auto or in_app_preview: Route by extension
    // 1. Image formats
    if (_imageExtensions.contains(ext)) {
      if (effectiveContext != null && effectiveContext.mounted) {
        unawaited(
          Navigator.of(effectiveContext).push(
            MaterialPageRoute<void>(
              builder: (_) => ImageViewerPage(images: [file.path]),
            ),
          ),
        );
        return ResourceOpenResult(
          success: true,
          message: 'Opened in in-app Image Viewer: $effectivePath',
          target: effectivePath,
          openedAs: 'image_viewer',
        );
      }
      return _openWithSystemDefault(file.path, effectivePath);
    }

    // 2. HTML format
    if (_htmlExtensions.contains(ext)) {
      try {
        final content = await file.readAsString();
        if (defaultTargetPlatform == TargetPlatform.linux) {
          if (effectiveContext != null && effectiveContext.mounted) {
            unawaited(
              ResourcePreviewModal.show(
                context: effectiveContext,
                title: effectiveTitle,
                content: content,
                filePath: file.path,
                isMarkdown: false,
              ),
            );
            return ResourceOpenResult(
              success: true,
              message: 'Opened HTML code preview on Linux: $effectivePath',
              target: effectivePath,
              openedAs: 'text_preview',
            );
          }
        }
        final base64Content = base64Encode(utf8.encode(content));
        if (effectiveContext != null && effectiveContext.mounted) {
          unawaited(
            Navigator.of(effectiveContext).push(
              MaterialPageRoute<void>(
                builder: (_) => WebViewPage(contentBase64: base64Content),
              ),
            ),
          );
          return ResourceOpenResult(
            success: true,
            message: 'Rendered HTML in in-app WebView: $effectivePath',
            target: effectivePath,
            openedAs: 'html_preview',
          );
        }
      } catch (_) {}
      return _openWithSystemDefault(file.path, effectivePath);
    }

    // 3. Markdown / Code / Text formats
    if (_markdownExtensions.contains(ext) || _textExtensions.contains(ext)) {
      try {
        final content = await file.readAsString();
        if (effectiveContext != null && effectiveContext.mounted) {
          unawaited(
            ResourcePreviewModal.show(
              context: effectiveContext,
              title: effectiveTitle,
              content: content,
              filePath: file.path,
              isMarkdown: _markdownExtensions.contains(ext),
            ),
          );
          return ResourceOpenResult(
            success: true,
            message: 'Opened in in-app Markdown/Text Viewer: $effectivePath',
            target: effectivePath,
            openedAs: 'text_preview',
          );
        }
      } catch (_) {}
      return _openWithSystemDefault(file.path, effectivePath);
    }

    // 4. Default: Fallback to system application
    return _openWithSystemDefault(file.path, effectivePath);
  }

  Future<ResourceOpenResult> _openWithSystemDefault(
    String filePath,
    String effectivePath,
  ) async {
    try {
      final res = await OpenFilex.open(filePath);
      final success = res.type == ResultType.done;
      return ResourceOpenResult(
        success: success,
        message: success
            ? 'Opened with system associated application: $effectivePath'
            : 'Result from system open: ${res.message}',
        target: effectivePath,
        openedAs: 'system_application',
      );
    } catch (e) {
      return ResourceOpenResult(
        success: false,
        message: 'Failed to open file: $e',
        target: effectivePath,
        openedAs: 'error',
      );
    }
  }
}
