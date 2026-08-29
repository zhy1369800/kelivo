import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../widgets/snackbar.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, this.url, this.contentBase64});
  final String? url;
  final String? contentBase64; // HTML string in Base64

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  String? _title;
  String? _currentUrl;
  bool _isLoading = true;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isDesktopMode = false;
  double _topDragAccumulated = 0;
  final List<_ConsoleMessage> _console = <_ConsoleMessage>[];

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Console', onMessageReceived: _onConsoleMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            setState(() {
              _isLoading = p < 100;
              _progress = p;
            });
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) async {
            setState(() {
              _isLoading = false;
              _progress = 100;
              _currentUrl = url;
            });
            await _refreshCanGoStates();
            await _updateTitle();
          },
          onWebResourceError: (err) {
            _pushConsole(
              level: 'error',
              message: 'Web error ${err.errorCode}: ${err.description}',
              source: _currentUrl,
            );
          },
        ),
      );
    // Initial load
    scheduleMicrotask(_initialLoad);
  }

  Future<void> _initialLoad() async {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // Keep parity with existing Linux limitation: no WebView support
      final l10n = AppLocalizations.of(context)!;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.htmlPreviewNotSupportedOnLinux)),
      );
      Navigator.of(context).maybePop();
      return;
    }
    final url = widget.url?.trim() ?? '';
    if (url.isNotEmpty) {
      await _controller.loadRequest(Uri.parse(url));
    } else {
      final data = widget.contentBase64 ?? '';
      final html = data.isEmpty
          ? '<!doctype html><html><body></body></html>'
          : utf8.decode(base64Decode(data));
      await _controller.loadHtmlString(html);
    }
  }

  void _onConsoleMessage(JavaScriptMessage msg) {
    try {
      final obj = jsonDecode(msg.message) as Map<String, dynamic>;
      _pushConsole(
        level: obj['level']?.toString() ?? 'log',
        message: obj['message']?.toString() ?? '',
        source: obj['source']?.toString(),
        line: (obj['line'] as num?)?.toInt(),
      );
    } catch (_) {
      _pushConsole(level: 'log', message: msg.message);
    }
  }

  void _pushConsole({
    required String level,
    required String message,
    String? source,
    int? line,
  }) {
    setState(() {
      _console.add(
        _ConsoleMessage(
          level: level.toUpperCase(),
          message: message,
          source: source,
          line: line,
        ),
      );
      if (_console.length > 128) {
        _console.removeRange(0, _console.length - 128);
      }
    });
  }

  Future<void> _updateTitle() async {
    try {
      final t = await _controller.runJavaScriptReturningResult(
        'document.title',
      );
      setState(() {
        _title = _stripJsString(t);
      });
    } catch (_) {}
  }

  String? _stripJsString(Object? v) {
    if (v == null) return null;
    var s = '$v';
    if (s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s;
  }

  Future<void> _refreshCanGoStates() async {
    try {
      final back = await _controller.canGoBack();
      final fwd = await _controller.canGoForward();
      setState(() {
        _canGoBack = back;
        _canGoForward = fwd;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final bool contentMode =
        (widget.contentBase64 != null && (widget.contentBase64!.isNotEmpty)) &&
        ((widget.url == null) || widget.url!.isEmpty);

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_canGoBack) {
          _controller.goBack();
        }
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) {
              _topDragAccumulated = 0;
            },
            onVerticalDragUpdate: (details) {
              if (details.delta.dy > 0) {
                _topDragAccumulated += details.delta.dy;
              }
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_topDragAccumulated > 40 || velocity > 400) {
                Navigator.of(context).maybePop();
              }
              _topDragAccumulated = 0;
            },
            child: AppBar(
              toolbarHeight: 56,
              titleSpacing: 0,
              leading: IconButton(
                icon: Icon(_canGoBack ? Lucide.ArrowLeft : Lucide.X),
                onPressed: () async {
                  if (_canGoBack) {
                    _controller.goBack();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    _title?.isNotEmpty == true ? _title! : (_currentUrl ?? ''),
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              centerTitle: true,
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Lucide.MoreVertical),
                  onSelected: (value) async {
                    final currentTarget = _currentUrl ?? widget.url ?? '';
                    final uri = Uri.tryParse(currentTarget);

                    switch (value) {
                      case 'reload':
                        _controller.reload();
                        break;
                      case 'forward':
                        if (_canGoForward) {
                          _controller.goForward();
                        }
                        break;
                      case 'desktop_mode':
                        setState(() {
                          _isDesktopMode = !_isDesktopMode;
                        });
                        await _controller.setUserAgent(
                          _isDesktopMode ? _desktopUserAgent : null,
                        );
                        await _controller.reload();
                        if (context.mounted) {
                          showAppSnackBar(
                            context,
                            message: _isDesktopMode ? '已切换至电脑桌面版' : '已切换至手机版',
                            type: NotificationType.info,
                          );
                        }
                        break;
                      case 'open':
                        if (uri != null &&
                            (uri.isScheme('http') || uri.isScheme('https'))) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                        break;
                      case 'share':
                        if (uri != null) {
                          final size = MediaQuery.maybeOf(context)?.size;
                          final anchor = (size != null &&
                                  size.width > 0 &&
                                  size.height > 0)
                              ? Rect.fromCenter(
                                  center: Offset(
                                    size.width / 2,
                                    size.height / 2,
                                  ),
                                  width: 10,
                                  height: 10,
                                )
                              : null;
                          await SharePlus.instance.share(
                            ShareParams(
                              uri: uri,
                              sharePositionOrigin: anchor,
                            ),
                          );
                        }
                        break;
                      case 'copy_link':
                        if (currentTarget.isNotEmpty) {
                          await Clipboard.setData(
                            ClipboardData(text: currentTarget),
                          );
                          if (context.mounted) {
                            showAppSnackBar(
                              context,
                              message: l10n.chatMessageWidgetCopiedToClipboard,
                              type: NotificationType.success,
                            );
                          }
                        }
                        break;
                      case 'console':
                        final isConsoleEmpty = _console.isEmpty;
                        showCustomBottomSheet(
                          context: context,
                          title: l10n.messageWebViewConsoleLogs,
                          count: _console.length,
                          partialHeightFactor: isConsoleEmpty ? 0.25 : 0.65,
                          expandedHeightFactor: isConsoleEmpty ? 0.25 : 0.90,
                          builder: (sheetContext, scrollController) {
                            return _ConsoleSheet(
                              messages: _console,
                              scrollController: scrollController,
                              onClear: () {
                                setState(() {
                                  _console.clear();
                                });
                              },
                            );
                          },
                        );
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem<String>(
                      value: 'reload',
                      child: Row(
                        children: [
                          Icon(Lucide.RotateCw, size: 18),
                          SizedBox(width: 12),
                          Text('重新加载'),
                        ],
                      ),
                    ),
                    if (_canGoForward)
                      const PopupMenuItem<String>(
                        value: 'forward',
                        child: Row(
                          children: [
                            Icon(Lucide.ArrowRight, size: 18),
                            SizedBox(width: 12),
                            Text('前进'),
                          ],
                        ),
                      ),
                    if (!contentMode) ...[
                      PopupMenuItem<String>(
                        value: 'desktop_mode',
                        child: Row(
                          children: [
                            Icon(Lucide.Monitor, size: 18),
                            SizedBox(width: 12),
                            Text(_isDesktopMode ? '请求移动网站' : '请求桌面网站'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'open',
                        child: Row(
                          children: [
                            const Icon(Lucide.Compass, size: 18),
                            const SizedBox(width: 12),
                            Text(l10n.messageWebViewOpenInBrowser),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Lucide.Share2, size: 18),
                            SizedBox(width: 12),
                            Text('分享'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'copy_link',
                        child: Row(
                          children: [
                            const Icon(Lucide.Copy, size: 18),
                            const SizedBox(width: 12),
                            Text(l10n.sideDrawerMenuCopy),
                          ],
                        ),
                      ),
                    ],
                    PopupMenuItem<String>(
                      value: 'console',
                      child: Row(
                        children: [
                          const Icon(Lucide.Terminal, size: 18),
                          const SizedBox(width: 12),
                          Text(
                            '${l10n.messageWebViewConsoleLogs} (${_console.length})',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            if (_isLoading)
              LinearProgressIndicator(
                value: _progress > 0 ? _progress / 100 : null,
              ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

class _ConsoleMessage {
  _ConsoleMessage({
    required this.level,
    required this.message,
    this.source,
    this.line,
  });
  final String level;
  final String message;
  final String? source;
  final int? line;
}

class _ConsoleSheet extends StatelessWidget {
  const _ConsoleSheet({
    required this.messages,
    required this.scrollController,
    required this.onClear,
  });

  final List<_ConsoleMessage> messages;
  final ScrollController scrollController;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (messages.isNotEmpty) ...[
            // Action Bar (Copy All, Clear)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final allLogs = messages
                        .map(
                          (m) =>
                              '[${m.level}] ${m.message}'
                              '${m.source != null ? '\nSource: ${m.source}${m.line != null ? ':${m.line}' : ''}' : ''}',
                        )
                        .join('\n\n');
                    await Clipboard.setData(ClipboardData(text: allLogs));
                    if (context.mounted) {
                      showAppSnackBar(
                        context,
                        message: l10n.chatMessageWidgetCopiedToClipboard,
                        type: NotificationType.success,
                      );
                    }
                  },
                  icon: const Icon(Lucide.Copy, size: 16),
                  label: Text(l10n.sideDrawerMenuCopy),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    onClear();
                    Navigator.of(context).maybePop();
                  },
                  icon: const Icon(Lucide.Trash2, size: 16),
                  label: Text(l10n.memoryTraceClearAction),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
          ],
          if (messages.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Lucide.Terminal,
                      size: 28,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.messageWebViewNoConsoleMessages,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final m = messages[i];
                  final isError = m.level == 'ERROR';
                  final isWarn = m.level == 'WARN' || m.level == 'WARNING';
                  final badgeColor = isError
                      ? cs.error
                      : isWarn
                          ? cs.tertiary
                          : cs.primary;
                  final badgeBg = isError
                      ? cs.errorContainer.withValues(alpha: 0.5)
                      : isWarn
                          ? cs.tertiaryContainer.withValues(alpha: 0.5)
                          : cs.surfaceContainerHighest;

                  return Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                m.level,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              icon: const Icon(Lucide.Copy, size: 14),
                              tooltip: l10n.sideDrawerMenuCopy,
                              onPressed: () async {
                                final logText =
                                    '[${m.level}] ${m.message}'
                                    '${m.source != null ? '\nSource: ${m.source}${m.line != null ? ':${m.line}' : ''}' : ''}';
                                await Clipboard.setData(
                                  ClipboardData(text: logText),
                                );
                                if (ctx.mounted) {
                                  showAppSnackBar(
                                    ctx,
                                    message: l10n.chatMessageWidgetCopiedToClipboard,
                                    type: NotificationType.success,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          m.message,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            color: isError ? cs.error : cs.onSurface,
                          ),
                        ),
                        if (m.source != null && m.source!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Source: ${m.source}${m.line != null ? ':${m.line}' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
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
