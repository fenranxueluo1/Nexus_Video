import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'service_exception.dart';

const String biliUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class BiliTransport {
  BiliTransport({String cookie = '', String proxy = ''}) {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      ..autoUncompress = true
      ..userAgent = biliUserAgent;
    this.cookie = cookie;
    this.proxy = proxy;
  }

  late final HttpClient _client;
  String _cookie = '';
  String _proxyUrl = '';
  String _tubeCookie = '';
  String _chirpCookie = '';
  String _douyinCookie = '';

  String get cookie => _cookie;

  set cookie(String value) {
    _cookie = value.trim();
  }

  String get tubeCookie => _tubeCookie;

  set tubeCookie(String value) {
    _tubeCookie = value.trim();
  }

  String get chirpCookie => _chirpCookie;

  set chirpCookie(String value) {
    _chirpCookie = value.trim();
  }

  String get douyinCookie => _douyinCookie;

  set douyinCookie(String value) {
    _douyinCookie = value.trim();
  }

  String get proxy => _proxyUrl;

  set proxy(String value) {
    _proxyUrl = value.trim();
    if (_proxyUrl.isEmpty) {
      _client.findProxy = (_) => 'DIRECT';
      return;
    }
    final uri = Uri.tryParse(
      _proxyUrl.contains('://') ? _proxyUrl : 'http://$_proxyUrl',
    );
    if (uri == null || uri.host.isEmpty) {
      throw const ApiException('代理地址无效，请填写 http://host:port 形式。');
    }
    if (uri.scheme == 'socks' || uri.scheme == 'socks5') {
      throw const ApiException('当前版本仅支持 HTTP/HTTPS 代理，暂不支持 SOCKS。');
    }
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    _client.findProxy = (_) => 'PROXY ${uri.host}:$port';
  }

  Map<String, String> requestHeaders({
    Map<String, String>? extra,
    bool withCookie = true,
    String referer = 'https://www.bilibili.com/',
  }) {
    final headers = <String, String>{
      'User-Agent': biliUserAgent,
      'Referer': referer,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
    };
    if (withCookie && _cookie.isNotEmpty) {
      headers['Cookie'] = _cookie;
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Future<HttpClientRequest> open(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    bool withCookie = true,
  }) async {
    try {
      final request = await _client.openUrl(method, uri);
      requestHeaders(
        extra: headers,
        withCookie: withCookie,
      ).forEach(request.headers.set);
      if (_tubeCookie.isNotEmpty && _isTubeHost(uri.host)) {
        request.headers.set(HttpHeaders.cookieHeader, _tubeCookie);
      }
      if (_chirpCookie.isNotEmpty && _isChirpHost(uri.host)) {
        request.headers.set(HttpHeaders.cookieHeader, _chirpCookie);
      }
      if (_douyinCookie.isNotEmpty && _isDouyinHost(uri.host)) {
        request.headers.set(HttpHeaders.cookieHeader, _douyinCookie);
      }
      return request;
    } on SocketException catch (error) {
      throw ApiException('网络连接失败：${error.message}');
    } on HandshakeException catch (error) {
      throw ApiException('TLS 握手失败：${error.message}');
    }
  }

  Future<TransportResponse> response(
    HttpClientRequest request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await request.close().timeout(timeout);
      final bytes = await response
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          )
          .timeout(timeout);
      final decoded = _decodeBody(bytes.takeBytes(), response.headers);
      return TransportResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: decoded,
      );
    } on TimeoutException {
      try {
        request.abort();
      } catch (_) {}
      throw const ApiException('请求超时，请检查网络或代理设置。');
    } on SocketException catch (error) {
      throw ApiException('网络请求失败：${error.message}');
    } on HttpException catch (error) {
      throw ApiException('网络请求失败：${error.message}');
    }
  }

  Uint8List _decodeBody(Uint8List bytes, HttpHeaders headers) {
    final encoding = (headers.value('content-encoding') ?? '').toLowerCase();
    if (encoding.contains('gzip')) {
      try {
        return Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
      } catch (_) {
        return bytes;
      }
    }
    if (encoding.contains('deflate')) {
      try {
        return Uint8List.fromList(const ZLibDecoder().decodeBytes(bytes));
      } catch (_) {
        try {
          return Uint8List.fromList(Inflate(bytes).getBytes());
        } catch (_) {
          return bytes;
        }
      }
    }
    return bytes;
  }

  Future<dynamic> getJson(
    Uri uri, {
    Map<String, String>? headers,
    bool withCookie = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = await open(
      'GET',
      uri,
      headers: headers,
      withCookie: withCookie,
    );
    final result = await response(request, timeout: timeout);
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw ApiException(
        '接口返回 HTTP ${result.statusCode}',
        statusCode: result.statusCode,
      );
    }
    final text = utf8.decode(result.body, allowMalformed: true).trim();
    if (text.isEmpty) {
      throw const ApiException('接口返回空响应。');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const ApiException('接口返回了非 JSON 数据，可能触发了风控或需要登录。');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('接口返回了无法识别的数据。');
    }
    final code = (decoded['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      final message =
          decoded['message']?.toString() ??
          decoded['msg']?.toString() ??
          '未知错误';
      throw BiliServiceException(message, code: code);
    }
    return decoded['data'];
  }

  Future<TransportResponse> getResponse(
    Uri uri, {
    Map<String, String>? headers,
    bool withCookie = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = await open(
      'GET',
      uri,
      headers: headers,
      withCookie: withCookie,
    );
    return response(request, timeout: timeout);
  }

  Future<Uint8List> getBytes(
    Uri uri, {
    Map<String, String>? headers,
    bool withCookie = true,
    int maxBytes = 32 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final request = await open(
      'GET',
      uri,
      headers: headers,
      withCookie: withCookie,
    );
    try {
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw ApiException(
          '任务失败：HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw ApiException('响应体超过大小上限（${maxBytes ~/ (1024 * 1024)} MB）。');
        }
      }
      return _decodeBody(builder.takeBytes(), response.headers);
    } on TimeoutException {
      try {
        request.abort();
      } catch (_) {}
      throw const ApiException('任务超时，请重试。');
    } on SocketException catch (error) {
      throw ApiException('网络请求失败：${error.message}');
    }
  }

  void close() {
    _client.close(force: true);
  }
}

class TransportResponse {
  const TransportResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final Uint8List body;

  List<String> get setCookies {
    final values = <String>[];
    headers.forEach((name, list) {
      if (name.toLowerCase() == 'set-cookie') {
        values.addAll(list);
      }
    });
    return values;
  }

  String get text => utf8.decode(body, allowMalformed: true);
}

bool _isTubeHost(String host) {
  final value = host.toLowerCase();
  return value == 'youtube.com' ||
      value.endsWith('.youtube.com') ||
      value == 'googlevideo.com' ||
      value.endsWith('.googlevideo.com');
}

bool _isChirpHost(String host) {
  final value = host.toLowerCase();
  return value == 'x.com' ||
      value.endsWith('.x.com') ||
      value == 'twitter.com' ||
      value.endsWith('.twitter.com') ||
      value == 'twimg.com' ||
      value.endsWith('.twimg.com');
}

bool _isDouyinHost(String host) {
  final value = host.toLowerCase();
  return value == 'douyin.com' ||
      value.endsWith('.douyin.com') ||
      value == 'iesdouyin.com' ||
      value.endsWith('.iesdouyin.com') ||
      value == 'amemv.com' ||
      value.endsWith('.amemv.com') ||
      value == 'douyinvod.com' ||
      value.endsWith('.douyinvod.com');
}
