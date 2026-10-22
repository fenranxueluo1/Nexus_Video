import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:path/path.dart' as p;

import '../../core/remote/tube_cookie.dart';
import '../../core/util/storage_paths.dart';

class RemoteCookieSource {
  const RemoteCookieSource(this.url, this.defaultDomain);

  final String url;
  final String defaultDomain;
}

class RemoteLoginProfile {
  const RemoteLoginProfile({
    required this.title,
    required this.loginUrl,
    required this.sources,
    required this.authNames,
    required this.fileName,
    required this.buildFile,
  });

  final String title;
  final String loginUrl;
  final List<RemoteCookieSource> sources;
  final Set<String> authNames;
  final String fileName;
  final String Function(Iterable<TubeCookieEntry> entries) buildFile;
}

const RemoteLoginProfile _tubeLoginProfile = RemoteLoginProfile(
  title: '登录 YouTube',
  loginUrl:
      'https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F',
  sources: [
    RemoteCookieSource('https://www.youtube.com', '.youtube.com'),
    RemoteCookieSource('https://m.youtube.com', '.youtube.com'),
    RemoteCookieSource('https://www.google.com', '.google.com'),
    RemoteCookieSource('https://accounts.google.com', '.google.com'),
  ],
  authNames: {
    'SID',
    'SAPISID',
    '__Secure-1PSID',
    '__Secure-3PSID',
    '__Secure-3PAPISID',
  },
  fileName: 'youtube_cookies.txt',
  buildFile: buildTubeCookieFile,
);

const RemoteLoginProfile _chirpLoginProfile = RemoteLoginProfile(
  title: '登录 X',
  loginUrl: 'https://x.com/i/flow/login',
  sources: [
    RemoteCookieSource('https://x.com', '.x.com'),
    RemoteCookieSource('https://twitter.com', '.twitter.com'),
    RemoteCookieSource('https://video.twimg.com', '.twimg.com'),
  ],
  authNames: {'auth_token', 'ct0', 'twid'},
  fileName: 'x_cookies.txt',
  buildFile: buildChirpCookieFile,
);

const RemoteLoginProfile _douyinLoginProfile = RemoteLoginProfile(
  title: '登录抖音',
  loginUrl: 'https://www.douyin.com/',
  sources: [
    RemoteCookieSource('https://www.douyin.com', '.douyin.com'),
    RemoteCookieSource('https://www.iesdouyin.com', '.iesdouyin.com'),
    RemoteCookieSource('https://m.douyin.com', '.douyin.com'),
  ],
  authNames: {'sessionid', 'sessionid_ss', 'sid_tt', 'sid_guard'},
  fileName: 'douyin_cookies.txt',
  buildFile: buildDouyinCookieFile,
);

Future<String?> showTubeLoginSheet(BuildContext context) {
  return _showRemoteLoginSheet(context, _tubeLoginProfile);
}

Future<String?> showChirpLoginSheet(BuildContext context) {
  return _showRemoteLoginSheet(context, _chirpLoginProfile);
}

Future<String?> showDouyinLoginSheet(BuildContext context) {
  return _showRemoteLoginSheet(context, _douyinLoginProfile);
}

Future<String?> _showRemoteLoginSheet(
  BuildContext context,
  RemoteLoginProfile profile,
) {
  final size = MediaQuery.sizeOf(context);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.max(320, math.min(980, size.width - 24)),
        height: math.max(420, math.min(760, size.height - 24)),
        child: _RemoteLoginView(profile: profile),
      ),
    ),
  );
}

class _RemoteLoginView extends StatefulWidget {
  const _RemoteLoginView({required this.profile});

  final RemoteLoginProfile profile;

  @override
  State<_RemoteLoginView> createState() => _RemoteLoginViewState();
}

class _RemoteLoginViewState extends State<_RemoteLoginView> {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  webview.InAppWebViewController? _controller;
  double _progress = 0;
  String _status = '请在页面中登录账号，完成后点击“完成并读取”。';
  bool _error = false;
  bool _busy = false;

  Future<void> _saveCookies() async {
    setState(() {
      _busy = true;
      _error = false;
      _status = '正在读取登录 Cookie...';
    });
    try {
      final entries = <TubeCookieEntry>[];
      for (final source in widget.profile.sources) {
        final cookies = await webview.CookieManager.instance().getCookies(
          url: webview.WebUri(source.url),
          webViewController: _controller,
        );
        for (final cookie in cookies) {
          final domain = (cookie.domain?.trim().isNotEmpty ?? false)
              ? cookie.domain!.trim()
              : source.defaultDomain;
          final rawExpiry = cookie.expiresDate;
          final expires = rawExpiry == null || rawExpiry <= 0
              ? 0
              : rawExpiry > 100000000000
              ? rawExpiry ~/ 1000
              : rawExpiry;
          entries.add(
            TubeCookieEntry(
              name: cookie.name,
              value: cookie.value?.toString() ?? '',
              domain: domain,
              path: cookie.path ?? '/',
              secure: cookie.isSecure ?? false,
              httpOnly: cookie.isHttpOnly ?? false,
              expires: expires,
            ),
          );
        }
      }
      final names = entries.map((entry) => entry.name).toSet();
      if (!names.any(widget.profile.authNames.contains)) {
        setState(() {
          _busy = false;
          _error = true;
          _status = '还没有检测到登录状态，请先在页面中完成登录。';
        });
        return;
      }
      final text = widget.profile.buildFile(entries);
      if (text.isEmpty) {
        setState(() {
          _busy = false;
          _error = true;
          _status = '没有读取到可用的登录 Cookie。';
        });
        return;
      }
      final file = File(
        p.join(StoragePaths.credentialsDir.path, widget.profile.fileName),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(text, flush: true);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(file.path);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = true;
        _status = '读取 Cookie 失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _controller?.goBack(),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: '后退',
                  ),
                  IconButton(
                    onPressed: () => _controller?.reload(),
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.profile.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  webview.InAppWebView(
                    initialUrlRequest: webview.URLRequest(
                      url: webview.WebUri(widget.profile.loginUrl),
                    ),
                    initialSettings: webview.InAppWebViewSettings(
                      javaScriptEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      sharedCookiesEnabled: true,
                      supportMultipleWindows: false,
                      useShouldOverrideUrlLoading: true,
                      userAgent: _userAgent,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onProgressChanged: (controller, progress) {
                      setState(() => _progress = progress / 100);
                    },
                    onLoadStop: (controller, url) {
                      setState(() {
                        _progress = 1;
                        if (_status.startsWith('页面加载失败')) {
                          _status = '请在页面中登录账号，完成后点击“完成并读取”。';
                          _error = false;
                        }
                      });
                    },
                    onReceivedError: (controller, request, error) {
                      setState(() {
                        _progress = 1;
                        _status = '页面加载失败：${error.description}';
                        _error = true;
                      });
                    },
                    shouldOverrideUrlLoading: (controller, action) async {
                      final uri = action.request.url;
                      if (uri == null) {
                        return webview.NavigationActionPolicy.ALLOW;
                      }
                      if (uri.scheme == 'http' ||
                          uri.scheme == 'https' ||
                          uri.scheme == 'about') {
                        return webview.NavigationActionPolicy.ALLOW;
                      }
                      return webview.NavigationActionPolicy.CANCEL;
                    },
                  ),
                  if (_progress < 1) LinearProgressIndicator(value: _progress),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _status,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _error
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _busy ? null : _saveCookies,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_busy ? '读取中' : '完成并读取'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
