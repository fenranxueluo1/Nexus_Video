import 'dart:io';

class ProxyDetector {
  ProxyDetector._();

  static const List<int> _commonPorts = [
    7897,
    7890,
    7891,
    1080,
    10808,
    10809,
    2080,
  ];

  static Future<String> detect() async {
    try {
      if (Platform.isWindows) {
        final system = await _windowsProxy();
        if (system != null) {
          return system;
        }
      } else if (Platform.isMacOS) {
        final system = await _macProxy();
        if (system != null) {
          return system;
        }
      } else if (Platform.isLinux) {
        final system = _environmentProxy();
        if (system != null) {
          return system;
        }
      }
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        return await _probeLocal();
      }
    } on Object {
      // Detection is best-effort; callers fall back to no proxy.
    }
    return '';
  }

  static Future<String?> _windowsProxy() async {
    final enable = await Process.run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyEnable',
    ]);
    if (enable.exitCode != 0 || !enable.stdout.toString().contains('0x1')) {
      return null;
    }
    final server = await Process.run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyServer',
    ]);
    if (server.exitCode != 0) {
      return null;
    }
    final match = RegExp(
      r'ProxyServer\s+REG_SZ\s+([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(server.stdout.toString());
    if (match == null) {
      return null;
    }
    return _normalizeProxy(match.group(1)!);
  }

  static Future<String?> _macProxy() async {
    final result = await Process.run('scutil', ['--proxy']);
    if (result.exitCode != 0) {
      return null;
    }
    final text = result.stdout.toString();
    for (final prefix in ['HTTPS', 'HTTP']) {
      final enabled = RegExp('${prefix}Enable\\s*:\\s*1').hasMatch(text);
      if (!enabled) {
        continue;
      }
      final host = RegExp(
        '${prefix}Proxy\\s*:\\s*([^\\r\\n]+)',
      ).firstMatch(text)?.group(1)?.trim();
      final port = RegExp(
        '${prefix}Port\\s*:\\s*(\\d+)',
      ).firstMatch(text)?.group(1);
      if (host != null && host.isNotEmpty && port != null) {
        return _normalizeProxy('$host:$port');
      }
    }
    return null;
  }

  static String? _environmentProxy() {
    for (final key in [
      'HTTPS_PROXY',
      'https_proxy',
      'HTTP_PROXY',
      'http_proxy',
      'ALL_PROXY',
      'all_proxy',
    ]) {
      final value = Platform.environment[key];
      if (value == null || value.trim().isEmpty) {
        continue;
      }
      final normalized = _normalizeProxy(value);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }

  static Future<String> _probeLocal() async {
    for (final port in _commonPorts) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 250),
        );
        socket.destroy();
        return 'http://127.0.0.1:$port';
      } on SocketException {
        // Try the next common proxy port.
      }
    }
    return '';
  }

  static String? _normalizeProxy(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.contains('=')) {
      final entries = <String, String>{};
      for (final item in value.split(';')) {
        final separator = item.indexOf('=');
        if (separator <= 0) {
          continue;
        }
        entries[item.substring(0, separator).trim().toLowerCase()] = item
            .substring(separator + 1)
            .trim();
      }
      value =
          entries['http'] ??
          entries['https'] ??
          (entries.values.isEmpty ? '' : entries.values.first);
    }
    if (value.isEmpty) {
      return null;
    }
    final lower = value.toLowerCase();
    if (lower.startsWith('socks')) {
      return null;
    }
    if (!value.contains('://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'socks' || scheme == 'socks5') {
      return null;
    }
    final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
    if (port <= 0 || port > 65535) {
      return null;
    }
    return 'http://${uri.host}:$port';
  }
}
