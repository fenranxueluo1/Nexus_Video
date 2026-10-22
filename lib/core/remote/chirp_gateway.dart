import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/service_exception.dart';
import 'remote_models.dart';
import 'remote_network.dart';

class ChirpGateway {
  ChirpGateway({String proxy = ''}) {
    _proxy = proxy.trim();
    _client = createRemoteHttpClient(_proxy);
  }

  late http.Client _client;
  String _proxy = '';
  final Map<String, _ChirpPayload> _cache = {};
  final Map<String, DateTime> _cacheTime = {};

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

  Future<RemoteClip> post(String id) async {
    final payload = await _payload(id);
    return RemoteClip(
      id: id,
      title: payload.title,
      author: payload.author,
      authorId: payload.handle,
      description: payload.description,
      coverUrl: payload.coverUrl,
      duration: payload.duration,
      publishedAt: payload.publishedAt,
    );
  }

  Future<RemoteStreams> streams(String id) async {
    final payload = await _payload(id);
    return RemoteStreams(
      muxed: [
        RemoteStream(
          url: payload.videoUrl,
          container: 'mp4',
          videoCodec: 'avc',
          audioCodec: 'aac',
          height: payload.height,
          bitrate: payload.bitrate,
          isMuxed: true,
        ),
      ],
    );
  }

  Future<_ChirpPayload> _payload(String id) async {
    final cached = _cache[id];
    final cachedAt = _cacheTime[id];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }
    Object? lastError;
    try {
      final payload = await _fetchFx(id);
      if (payload != null) {
        _cache[id] = payload;
        _cacheTime[id] = DateTime.now();
        return payload;
      }
    } on Object catch (error) {
      lastError = error;
    }
    try {
      final payload = await _fetchSyndication(id);
      if (payload != null) {
        _cache[id] = payload;
        _cacheTime[id] = DateTime.now();
        return payload;
      }
    } on Object catch (error) {
      lastError = error;
    }
    if (lastError != null) {
      throw ApiException('X 解析失败：$lastError');
    }
    throw const ApiException('该 X 帖子没有可下载的视频。');
  }

  Future<_ChirpPayload?> _fetchFx(String id) async {
    final response = await _client
        .get(
          Uri.parse('https://api.fxtwitter.com/2/status/$id'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      return null;
    }
    final root = _asMap(jsonDecode(response.body));
    final tweet = _asMap(root?['status']) ?? _asMap(root?['tweet']);
    if (tweet == null) {
      return null;
    }
    final media = _asMap(tweet['media']);
    final videos = _asList(
      media?['videos'],
    ).map(_asMap).whereType<Map<String, dynamic>>().toList();
    if (videos.isEmpty) {
      return null;
    }
    final video = videos.first;
    final rawFormats = _asList(video['formats']);
    final rawVariants = rawFormats.isNotEmpty
        ? rawFormats
        : _asList(video['variants']);
    final variants = rawVariants
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .toList();
    final variant = _bestVariant(variants);
    final videoUrl = _firstNonEmpty([
      _asString(variant?['url']),
      _asString(video['url']),
    ]);
    if (videoUrl.isEmpty) {
      return null;
    }
    final author = _asMap(tweet['author']);
    final text = _asString(tweet['text']);
    final authorName = _firstNonEmpty([
      _asString(author?['name']),
      _asString(author?['screen_name']),
      'X 用户',
    ]);
    return _ChirpPayload(
      title: _headline(text, id),
      description: text,
      author: authorName,
      handle: _asString(author?['screen_name']),
      coverUrl: _firstNonEmpty([
        _asString(video['thumbnail_url']),
        _asString(author?['avatar_url']),
      ]),
      videoUrl: videoUrl,
      duration: Duration(
        milliseconds: ((_asDouble(video['duration']) ?? 0) * 1000).round(),
      ),
      bitrate: _asInt(variant?['bitrate']) ?? 0,
      height: _asInt(variant?['height']) ?? 0,
      publishedAt: _parseDate(tweet['created_at']),
    );
  }

  Future<_ChirpPayload?> _fetchSyndication(String id) async {
    final response = await _client
        .get(
          Uri.parse(
            'https://cdn.syndication.twimg.com/tweet-result?id=$id&lang=en',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      return null;
    }
    final root = _asMap(jsonDecode(response.body));
    if (root == null) {
      return null;
    }
    final details = _asList(
      root['mediaDetails'],
    ).map(_asMap).whereType<Map<String, dynamic>>().toList();
    for (final item in details) {
      final info = _asMap(item['video_info']);
      final variants = _asList(
        info?['variants'],
      ).map(_asMap).whereType<Map<String, dynamic>>().toList();
      final variant = _bestVariant(variants);
      final url = _asString(variant?['url']);
      if (url.isEmpty) {
        continue;
      }
      final user = _asMap(root['user']);
      final text = _asString(root['text']);
      final durationMs = _asInt(info?['duration_millis']) ?? 0;
      final authorName = _firstNonEmpty([
        _asString(user?['name']),
        _asString(user?['screen_name']),
        'X 用户',
      ]);
      return _ChirpPayload(
        title: _headline(text, id),
        description: text,
        author: authorName,
        handle: _asString(user?['screen_name']),
        coverUrl: _firstNonEmpty([
          _asString(item['media_url_https']),
          _asString(user?['profile_image_url_https']),
        ]),
        videoUrl: url,
        duration: Duration(milliseconds: durationMs),
        bitrate: _asInt(variant?['bitrate']) ?? 0,
        height: _asInt(variant?['height']) ?? 0,
        publishedAt: _parseDate(root['created_at']),
      );
    }
    return null;
  }

  Map<String, dynamic>? _bestVariant(List<Map<String, dynamic>> variants) {
    final mp4 = variants.where((variant) {
      final type = _asString(variant['content_type']).toLowerCase();
      final container = _asString(variant['container']).toLowerCase();
      final url = _asString(variant['url']).toLowerCase();
      return container == 'mp4' || type.contains('mp4') || url.contains('.mp4');
    }).toList();
    if (mp4.isEmpty) {
      return null;
    }
    mp4.sort(
      (left, right) => (_asInt(right['bitrate']) ?? 0).compareTo(
        _asInt(left['bitrate']) ?? 0,
      ),
    );
    return mp4.first;
  }

  Map<String, String> get _headers => {
    'User-Agent': remoteUserAgent,
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://x.com/',
  };

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _headline(String text, String id) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.isEmpty ? 'X 视频 $id' : line;
  }

  DateTime? _parseDate(Object? value) {
    final text = _asString(value);
    if (text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text);
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    return null;
  }

  List<Object?> _asList(Object? value) {
    return value is List ? value : const [];
  }

  String _asString(Object? value) {
    return value is String ? value : '';
  }

  int? _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value');
  }

  void close() {
    _client.close();
  }
}

class _ChirpPayload {
  const _ChirpPayload({
    required this.title,
    required this.description,
    required this.author,
    required this.handle,
    required this.videoUrl,
    required this.duration,
    required this.bitrate,
    required this.height,
    this.coverUrl,
    this.publishedAt,
  });

  final String title;
  final String description;
  final String author;
  final String? handle;
  final String videoUrl;
  final Duration duration;
  final int bitrate;
  final int height;
  final String? coverUrl;
  final DateTime? publishedAt;
}
