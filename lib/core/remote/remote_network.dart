import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const String remoteUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36';

http.Client createRemoteHttpClient(String proxy) {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30)
    ..autoUncompress = true
    ..userAgent = remoteUserAgent;
  final value = proxy.trim();
  if (value.isNotEmpty) {
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri != null &&
        uri.host.isNotEmpty &&
        uri.scheme != 'socks' &&
        uri.scheme != 'socks5') {
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      client.findProxy = (_) => 'PROXY ${uri.host}:$port';
    }
  }
  return IOClient(client);
}
