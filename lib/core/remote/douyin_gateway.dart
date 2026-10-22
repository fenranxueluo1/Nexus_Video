import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../api/service_exception.dart';
import 'remote_models.dart';
import 'remote_network.dart';
import 'tube_cookie.dart';

class DouyinGateway {
  DouyinGateway({String proxy = '', String cookiePath = ''}) {
    _proxy = proxy.trim();
    _cookiePath = cookiePath.trim();
    _cookieHeader = readDouyinCookieHeader(_cookiePath);
    _client = createRemoteHttpClient(_proxy);
  }

  static const String _appUserAgent =
      'com.ss.android.ugc.aweme/250000 (Linux; U; Android 13; en_US; '
      'Pixel 7; Build/TD1A.220804.031; Cronet/58.0.2991.0)';
  static const String _webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';

  late http.Client _client;
  String _proxy = '';
  String _cookiePath = '';
  String _cookieHeader = '';
  final Map<String, _DouyinPayload> _cache = {};
  final Map<String, DateTime> _cacheTime = {};
  final Random _random = Random.secure();
  late final String _deviceId = _randomDigits(18);
  late final String _openudid = _randomHex(16);

  set proxy(String value) {
    final next = value.trim();
    if (next == _proxy) {
      return;
    }
    _client.close();
    _proxy = next;
    _client = createRemoteHttpClient(next);
    _cache.clear();
    _cacheTime.clear();
  }

  set cookiePath(String value) {
    final next = value.trim();
    if (next == _cookiePath) {
      return;
    }
    _cookiePath = next;
    _cookieHeader = readDouyinCookieHeader(next);
    _cache.clear();
    _cacheTime.clear();
  }

  Future<RemoteClip> clip(String input) async {
    final payload = await _load(input);
    return payload.clip;
  }

  Future<RemoteStreams> streams(String input) async {
    final payload = await _load(input);
    return payload.streams;
  }

  Future<_DouyinPayload> _load(String input) async {
    final id = await _resolveId(input);
    final cached = _cache[id];
    final cachedAt = _cacheTime[id];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }
    final detail = await _fetchDetail(id);
    final payload = _parseDetail(detail);
    _cache[id] = payload;
    _cacheTime[id] = DateTime.now();
    return payload;
  }

  Future<String> _resolveId(String input) async {
    final value = input.trim();
    if (RegExp(r'^\d+$').hasMatch(value)) {
      return value;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      throw const ApiException('无法识别的抖音链接。');
    }
    final direct = _extractId(uri);
    if (direct != null) {
      return direct;
    }
    if (!_isDouyinHost(uri.host)) {
      throw const ApiException('无法识别的抖音链接。');
    }
    final resolved = await _followRedirects(uri);
    final id = _extractId(resolved);
    if (id != null) {
      return id;
    }
    throw const ApiException('无法从抖音链接中读取视频 ID，请复制完整分享链接。');
  }

  Future<Uri> _followRedirects(Uri start) async {
    var current = start;
    for (var attempt = 0; attempt < 5; attempt += 1) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': _webUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
          if (_cookieHeader.isNotEmpty) 'Cookie': _cookieHeader,
        });
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final body = await response.stream.bytesToString();
      final location = response.headers['location'];
      if (location != null && location.isNotEmpty) {
        current = current.resolve(location);
        final direct = _extractId(current);
        if (direct != null) {
          return current;
        }
        continue;
      }
      final fromBody = RegExp(
        r'(?:/video/|/note/|modal_id=)(\d+)',
      ).firstMatch(body);
      if (fromBody != null) {
        return Uri.parse('https://www.douyin.com/video/${fromBody.group(1)}');
      }
      return current;
    }
    return current;
  }

  Future<Map<String, dynamic>> _fetchDetail(String id) async {
    final query = <String, String>{
      'aweme_id': id,
      'aid': '1128',
      'app_name': 'aweme',
      'version_code': '250000',
      'version_name': '25.0.0',
      'device_platform': 'android',
      'os': 'android',
      'channel': 'googleplay',
      'device_type': 'Pixel 7',
      'os_version': '13',
      'device_id': _deviceId,
      'iid': '0',
      'openudid': _openudid,
      'ts': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    };
    final uri = Uri.https('aweme.snssdk.com', '/aweme/v1/aweme/detail/', query);
    final response = await _client
        .get(
          uri,
          headers: {
            'User-Agent': _appUserAgent,
            'Accept': 'application/json',
            if (_cookieHeader.isNotEmpty) 'Cookie': _cookieHeader,
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw ApiException('抖音接口请求失败（HTTP ${response.statusCode}）。');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const ApiException('抖音接口返回了无法识别的数据。');
    }
    final root = decoded.map((key, value) => MapEntry('$key', value));
    final detail = _map(root['aweme_detail']);
    if (detail == null) {
      final filter = _map(root['filter_detail']);
      final reason = _string(filter?['filter_reason']);
      final notice = _string(filter?['notice']);
      if (reason == 'base_charge_limit_source') {
        throw ApiException(
          '该抖音作品被标记为付费/受限内容，暂时无法下载。'
          '${notice.isEmpty ? '' : '\n$notice'}',
        );
      }
      if (reason.isNotEmpty) {
        throw ApiException(
          '该抖音作品暂时不可访问（$reason）。'
          '${notice.isEmpty ? '' : '\n$notice'}',
        );
      }
      final status = root['status_code'];
      throw ApiException(
        status == null
            ? '抖音没有返回视频信息，可能需要登录或该作品不可访问。'
            : '抖音没有返回视频信息（状态码 $status）。',
      );
    }
    return detail;
  }

  _DouyinPayload _parseDetail(Map<String, dynamic> detail) {
    final id = _string(detail['aweme_id']);
    if (id.isEmpty) {
      throw const ApiException('抖音没有返回作品 ID。');
    }
    final desc = _string(detail['desc']);
    final author = _map(detail['author']);
    final video = _map(detail['video']);
    if (video == null) {
      throw const ApiException('该抖音作品不是可下载的视频。');
    }
    final images = _list(detail['images']);
    final awemeType = _integer(detail['aweme_type']);
    if (images.isNotEmpty || awemeType == 68) {
      throw const ApiException('该抖音作品是图文，暂不支持视频下载。');
    }

    final variants = <RemoteStream>[];
    final seen = <String>{};
    final bitrates = _list(video['bit_rate']);
    for (final item in bitrates) {
      final bitrate = _map(item);
      if (bitrate == null) {
        continue;
      }
      final addr = _map(bitrate['play_addr']);
      final url = _firstUrl(addr?['url_list']);
      if (url.isEmpty || !seen.add(url)) {
        continue;
      }
      final gear = _string(bitrate['gear_name']);
      variants.add(
        _stream(
          url: url,
          height:
              _integer(addr?['height']) ??
              _heightFromGear(gear) ??
              _integer(video['height']) ??
              0,
          bitrate: _integer(bitrate['bit_rate']) ?? 0,
          size: _integer(addr?['data_size']),
          hevc: _integer(video['is_bytevc1']) == 1,
        ),
      );
    }
    final playAddr = _map(video['play_addr']);
    final playUrl = _firstUrl(playAddr?['url_list']);
    if (variants.isEmpty && playUrl.isNotEmpty) {
      variants.add(
        _stream(
          url: playUrl,
          height: _integer(video['height']) ?? 0,
          bitrate: _integer(video['bit_rate']) ?? 0,
          size: _integer(playAddr?['data_size']),
          hevc: _integer(video['is_bytevc1']) == 1,
        ),
      );
    }
    final downloadAddr = _map(video['download_addr']);
    final downloadUrl = _firstUrl(downloadAddr?['url_list']);
    if (variants.isEmpty && downloadUrl.isNotEmpty) {
      variants.add(
        _stream(
          url: downloadUrl,
          height:
              _integer(downloadAddr?['height']) ??
              _integer(video['height']) ??
              0,
          bitrate: 0,
          size: _integer(downloadAddr?['data_size']),
          hevc: false,
        ),
      );
    }
    if (variants.isEmpty) {
      throw const ApiException('该抖音作品没有可下载的视频流。');
    }
    final durationMs =
        _integer(video['duration']) ?? _integer(detail['duration']) ?? 0;
    final cover = _firstUrl(_map(video['cover'])?['url_list']);
    final createTime = _integer(detail['create_time']);
    final title = desc.isEmpty ? '抖音视频 $id' : desc;
    return _DouyinPayload(
      clip: RemoteClip(
        id: id,
        title: title,
        author: _firstNonEmpty([
          _string(author?['nickname']),
          _string(author?['unique_id']),
          '抖音用户',
        ]),
        authorId: _string(author?['sec_uid']),
        description: desc,
        coverUrl: cover.isEmpty
            ? _firstUrl(_map(video['origin_cover'])?['url_list'])
            : cover,
        duration: Duration(milliseconds: durationMs),
        publishedAt: createTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(createTime * 1000),
      ),
      streams: RemoteStreams(muxed: variants),
    );
  }

  RemoteStream _stream({
    required String url,
    required int height,
    required int bitrate,
    required int? size,
    required bool hevc,
  }) {
    return RemoteStream(
      url: url,
      container: 'mp4',
      videoCodec: hevc ? 'hevc' : 'avc',
      audioCodec: 'aac',
      height: height,
      bitrate: bitrate,
      sizeBytes: size,
      isMuxed: true,
      headers: const {'Referer': 'https://www.douyin.com/', 'Accept': '*/*'},
    );
  }

  void close() {
    _client.close();
    _cache.clear();
    _cacheTime.clear();
  }

  String _randomDigits(int length) {
    return List.generate(length, (_) => _random.nextInt(10)).join();
  }

  String _randomHex(int length) {
    const chars = '0123456789abcdef';
    return List.generate(
      length,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  String? _extractId(Uri uri) {
    final modalId = uri.queryParameters['modal_id'];
    if (modalId != null && RegExp(r'^\d+$').hasMatch(modalId)) {
      return modalId;
    }
    final match = RegExp(
      r'/(?:video|note|share/video)/(\d+)',
    ).firstMatch(uri.path);
    return match?.group(1);
  }

  bool _isDouyinHost(String host) {
    final value = host.toLowerCase();
    return value == 'douyin.com' ||
        value.endsWith('.douyin.com') ||
        value == 'iesdouyin.com' ||
        value.endsWith('.iesdouyin.com');
  }

  String _firstUrl(Object? value) {
    final list = _list(value);
    for (final item in list) {
      final text = _string(item);
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  int? _heightFromGear(String gear) {
    final match = RegExp(r'(\d{3,4})p?').firstMatch(gear);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Map<String, dynamic>? _map(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    return null;
  }

  List<Object?> _list(Object? value) {
    return value is List ? value : const [];
  }

  int? _integer(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  String _string(Object? value) {
    if (value is String) {
      return value;
    }
    if (value is num) {
      return '$value';
    }
    return '';
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }
}

class _DouyinPayload {
  const _DouyinPayload({required this.clip, required this.streams});

  final RemoteClip clip;
  final RemoteStreams streams;
}
