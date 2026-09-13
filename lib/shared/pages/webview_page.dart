import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../widgets/snackbar.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    this.url,
    this.contentBase64,
    this.filePath,
    this.title,
  });

  final String? url;
  final String? contentBase64; // HTML string in Base64
  final String? filePath; // local HTML file path
  final String? title;

  /// Global handle to currently mounted WebViewPage instance (if any).
  // ignore: library_private_types_in_public_api
  static _WebViewPageState? activeState;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  String? _title;
  String? _currentUrl;
  String? _filePath;
  String? _contentBase64;
  bool _isLoading = true;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isDesktopMode = false;
  late bool _contentMode; // true when rendering inline HTML (not a URL)
  final List<_ConsoleMessage> _console = <_ConsoleMessage>[];

  // Drawer / Sheet states
  double? _currentTop;
  double _animFrom = 0.0;
  double _animTo = 0.0;
  bool _isDismissing = false;
  late final AnimationController _slideCtrl;

  // Web scroll boundary detection for edge-drag linkage
  bool _isWebAtTop = true;
  int? _webDragPointer;
  double? _lastWebPointerY;
  bool _isPullingDownFromWeb = false;

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, Gecko) Chrome/125.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _contentMode =
        (widget.contentBase64 != null && widget.contentBase64!.isNotEmpty) &&
        (widget.url == null || widget.url!.isEmpty);
    WebViewPage.activeState = this;
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )
      ..addListener(() {
        final curve = _isDismissing ? Curves.easeInCubic : Curves.easeOutCubic;
        final t = curve.transform(_slideCtrl.value);
        setState(() {
          _currentTop = _animFrom + (_animTo - _animFrom) * t;
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && _isDismissing) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Console', onMessageReceived: _onConsoleMessage)
      ..addJavaScriptChannel(
        'ScrollNotifier',
        onMessageReceived: (JavaScriptMessage msg) {
          _isWebAtTop = msg.message == '1';
        },
      )
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
            await _injectScrollListener();
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

    // Set initial drawer position after first frame (MediaQuery is available then)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentTop != null) return;
      final media = MediaQuery.of(context);
      final screenH = media.size.height;
      final statusBarH = media.padding.top;
      final defaultTop = math.max(screenH * 0.15, statusBarH + 36.0);
      setState(() {
        _currentTop = defaultTop;
      });
    });

    // Initial load
    scheduleMicrotask(_initialLoad);
  }

  @override
  void dispose() {
    if (WebViewPage.activeState == this) {
      WebViewPage.activeState = null;
    }
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _injectScrollListener() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          if (window._hasScrollNotifier) return;
          window._hasScrollNotifier = true;

          // Prevent native overscroll bounce so sheet drag stays smooth
          try {
            var style = document.createElement('style');
            style.textContent = 'html, body { overscroll-behavior-y: none !important; }';
            (document.head || document.documentElement).appendChild(style);
          } catch (_) {}

          var lastIsTop = null;
          var notify = function() {
            var y = window.scrollY || document.documentElement.scrollTop || 0;
            var isTop = y <= 2.0;
            if (isTop !== lastIsTop) {
              lastIsTop = isTop;
              if (window.ScrollNotifier) {
                window.ScrollNotifier.postMessage(isTop ? '1' : '0');
              }
            }
          };
          window.addEventListener('scroll', notify, {passive: true});
          notify();
        })();
      ''');
    } catch (_) {}
  }

  /// Update content in-place without rebuilding or reopening the page.
  Future<void> updateTarget({
    String? url,
    String? contentBase64,
    String? filePath,
    String? title,
  }) async {
    if (!mounted) return;
    _slideCtrl.stop();
    final targetUrl = url?.trim() ?? '';
    setState(() {
      if (title != null && title.trim().isNotEmpty) {
        _title = title.trim();
      }
      if (filePath != null) {
        _filePath = filePath;
      }
      if (contentBase64 != null) {
        _contentBase64 = contentBase64;
      }
      _contentMode = targetUrl.isEmpty;
      _isLoading = true;
      _progress = 0;
      _isDismissing = false;
    });

    if (targetUrl.isNotEmpty) {
      await _controller.loadRequest(Uri.parse(targetUrl));
    } else {
      await _loadLocalHtml();
    }
  }

  Future<void> _loadLocalHtml() async {
    String html = '';
    // Priority: Read newest content from filePath if available
    if (_filePath != null && _filePath!.isNotEmpty) {
      try {
        final f = File(_filePath!);
        if (await f.exists()) {
          html = await f.readAsString();
        }
      } catch (_) {}
    }

    if (html.isEmpty && _contentBase64 != null && _contentBase64!.isNotEmpty) {
      try {
        html = utf8.decode(base64Decode(_contentBase64!));
      } catch (_) {}
    }

    if (html.isEmpty) {
      html = '<!doctype html><html><body></body></html>';
    }

    final baseUrl = (_filePath != null && _filePath!.isNotEmpty)
        ? (p.isAbsolute(_filePath!)
            ? Uri.file(p.dirname(_filePath!)).toString()
            : Uri.file(p.dirname(p.absolute(_filePath!))).toString())
        : null;

    await _controller.loadHtmlString(html, baseUrl: baseUrl);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _progress = 100;
      });
      await _refreshCanGoStates();
      await _updateTitle();
      await _injectScrollListener();
    }
  }

  Future<void> _initialLoad() async {
    if (defaultTargetPlatform == TargetPlatform.linux) {
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
      await _loadLocalHtml();
    }
  }

  /// Safe reload that respects both remote URLs and local HTML files.
  Future<void> _reloadContent() async {
    if (_contentMode) {
      setState(() {
        _isLoading = true;
        _progress = 0;
      });
      await _loadLocalHtml();
    } else {
      await _controller.reload();
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
      final stripped = _stripJsString(t);
      if (stripped != null && stripped.isNotEmpty) {
        setState(() {
          _title = stripped;
        });
      }
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

  void _dismissDownwards() {
    if (_isDismissing) return;
    _slideCtrl.stop();
    final screenH = MediaQuery.sizeOf(context).height;
    _animFrom = _currentTop ?? 0.0;
    _animTo = screenH > 0 ? screenH : 800.0;
    _isDismissing = true;
    _slideCtrl.forward(from: 0.0);
  }

  void _animateTo(double targetTop) {
    if (_isDismissing) return;
    _slideCtrl.stop();
    _animFrom = _currentTop ?? targetTop;
    _animTo = targetTop;
    _slideCtrl.forward(from: 0.0);
  }

  void _handleDragUpdate(double dy, double expandedTop) {
    _slideCtrl.stop();
    final cur = _currentTop ?? expandedTop;
    final next = math.max(expandedTop, cur + dy);
    setState(() {
      _currentTop = next;
    });
  }

  void _handleDragEnd({
    required double velocityY,
    required double expandedTop,
    required double defaultTop,
  }) {
    final cur = _currentTop ?? defaultTop;
    final dismissThreshold = defaultTop + 90.0;

    // Fling down -> dismiss
    if (velocityY > 700 || cur > dismissThreshold) {
      _dismissDownwards();
      return;
    }

    // Fling up -> expand to near full screen
    if (velocityY < -500) {
      _animateTo(expandedTop);
      return;
    }

    // Settle to nearest snap point (expandedTop vs defaultTop)
    final mid = expandedTop + (defaultTop - expandedTop) * 0.5;
    if (cur < mid) {
      _animateTo(expandedTop);
    } else {
      _animateTo(defaultTop);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final statusBarH = media.padding.top;

    // Two drawer card stop points:
    // 1. expandedTop: near full-screen (top edge just below status bar / dynamic island)
    final expandedTop = math.max(statusBarH + 8.0, 24.0);
    // 2. defaultTop: standard drawer card height (~85% screen height, revealing scrim above)
    final defaultTop = math.max(screenH * 0.15, statusBarH + 36.0);

    final topOffset = _currentTop ?? defaultTop;

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_canGoBack) {
          _controller.goBack();
        }
      },
      child: Stack(
        children: [
          // Top scrim area tap to dismiss
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissDownwards,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),

          // Drawer Card Container
          Positioned(
            left: 0,
            right: 0,
            top: topOffset,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Scaffold(
                  backgroundColor: cs.surface,
                  // We implement our own compact header without Scaffold's extra top SafeArea
                  body: Column(
                    children: [
                      _buildHeader(
                        context: context,
                        cs: cs,
                        l10n: l10n,
                        expandedTop: expandedTop,
                        defaultTop: defaultTop,
                      ),
                      if (_isLoading)
                        LinearProgressIndicator(
                          value: _progress > 0 ? _progress / 100 : null,
                          minHeight: 2,
                        ),
                      Expanded(
                        child: Listener(
                          onPointerDown: (e) {
                            _webDragPointer = e.pointer;
                            _lastWebPointerY = e.position.dy;
                            _isPullingDownFromWeb = false;
                          },
                          onPointerMove: (e) {
                            if (_webDragPointer != e.pointer) return;
                            final currentY = e.position.dy;
                            final dy =
                                currentY - (_lastWebPointerY ?? currentY);
                            _lastWebPointerY = currentY;

                            // When web content is scrolled to the very top and user drags down
                            if (_isWebAtTop && dy > 0) {
                              _isPullingDownFromWeb = true;
                              _handleDragUpdate(dy, expandedTop);
                            } else if (_isPullingDownFromWeb && dy < 0) {
                              _handleDragUpdate(dy, expandedTop);
                            }
                          },
                          onPointerUp: (e) {
                            if (_webDragPointer != e.pointer) return;
                            _webDragPointer = null;
                            _lastWebPointerY = null;
                            if (_isPullingDownFromWeb) {
                              _isPullingDownFromWeb = false;
                              _handleDragEnd(
                                velocityY: 0,
                                expandedTop: expandedTop,
                                defaultTop: defaultTop,
                              );
                            }
                          },
                          onPointerCancel: (e) {
                            if (_webDragPointer != e.pointer) return;
                            _webDragPointer = null;
                            _lastWebPointerY = null;
                            if (_isPullingDownFromWeb) {
                              _isPullingDownFromWeb = false;
                              _handleDragEnd(
                                velocityY: 0,
                                expandedTop: expandedTop,
                                defaultTop: defaultTop,
                              );
                            }
                          },
                          child: WebViewWidget(controller: _controller),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required ColorScheme cs,
    required AppLocalizations l10n,
    required double expandedTop,
    required double defaultTop,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) {
        _slideCtrl.stop();
      },
      onVerticalDragUpdate: (details) {
        _handleDragUpdate(details.delta.dy, expandedTop);
      },
      onVerticalDragEnd: (details) {
        _handleDragEnd(
          velocityY: details.primaryVelocity ?? 0,
          expandedTop: expandedTop,
          defaultTop: defaultTop,
        );
      },
      child: Container(
        color: cs.surface,
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drawer Drag Handle (matching add_provider_sheet style)
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            // Compact Header Bar (height 44px)
            SizedBox(
              height: 44,
              child: NavigationToolbar(
                leading: IconButton(
                  icon: Icon(_canGoBack ? Lucide.ArrowLeft : Lucide.X),
                  iconSize: 20,
                  tooltip: _canGoBack ? 'Back' : 'Close',
                  onPressed: () {
                    if (_canGoBack) {
                      _controller.goBack();
                    } else {
                      _dismissDownwards();
                    }
                  },
                ),
                middle: Text(
                  _title?.isNotEmpty == true
                      ? _title!
                      : (_currentUrl ?? _filePath ?? ''),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _buildPopupMenu(context, cs, l10n),
              ),
            ),
            const Divider(height: 1, thickness: 0.6),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupMenu(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    return PopupMenuButton<String>(
      icon: const Icon(Lucide.MoreVertical, size: 20),
      onSelected: (value) async {
        final currentTarget = _currentUrl ?? widget.url ?? _filePath ?? '';
        final uri = Uri.tryParse(currentTarget);

        switch (value) {
          case 'reload':
            await _reloadContent();
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
            await _reloadContent();
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
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            break;
          case 'share':
            if (uri != null) {
              final size = MediaQuery.maybeOf(context)?.size;
              final anchor = (size != null && size.width > 0 && size.height > 0)
                  ? Rect.fromCenter(
                      center: Offset(size.width / 2, size.height / 2),
                      width: 10,
                      height: 10,
                    )
                  : null;
              await SharePlus.instance.share(
                ShareParams(uri: uri, sharePositionOrigin: anchor),
              );
            }
            break;
          case 'copy_link':
            if (currentTarget.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: currentTarget));
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
        if (!_contentMode) ...[
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
              Text('${l10n.messageWebViewConsoleLogs} (${_console.length})'),
            ],
          ),
        ),
      ],
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
