import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../api/service_exception.dart';
import '../util/storage_paths.dart';
import 'remote_models.dart';
import 'remote_network.dart';

class TubeDlpBridge {
  TubeDlpBridge({String proxy = '', String cookiePath = ''})
    : _proxy = proxy.trim(),
      _cookiePath = cookiePath.trim();

  String _proxy;
  String _cookiePath;
  String? _tool;
  bool _toolChecked = false;
  String? _jsRuntime;
  Future<String?>? _jsRuntimeFuture;
  final Map<String, _CachedJson> _cache = {};

  set proxy(String value) {
    _proxy = value.trim();
  }

  set cookiePath(String value) {
    final next = value.trim();
    if (next == _cookiePath) {
      return;
    }
    _cookiePath = next;
    _cache.clear();
  }

  bool get _desktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<RemoteClip?> clip(String id) async {
    if (!_desktop) {
      return null;
    }
    final tool = await _ensureTool();
    if (tool == null) {
      return null;
    }
    final json = await _jsonFor(
      'clip:$id',
      _watchUrl(id),
      playlist: false,
      tool: tool,
    );
    return _clipFromJson(json);
  }

  Future<RemoteCollection?> collection(String id) async {
    if (!_desktop) {
      return null;
    }
    final tool = await _ensureTool();
    if (tool == null) {
      return null;
    }
    final json = await _jsonFor(
      'list:$id',
      _listUrl(id),
      playlist: true,
      tool: tool,
    );
    return _collectionFromJson(json);
  }

  Future<RemoteStreams?> streams(String id) async {
    if (!_desktop) {
      return null;
    }
    final tool = await _ensureTool();
    if (tool == null) {
      return null;
    }
    final url = _watchUrl(id);
    final json = await _jsonFor('clip:$id', url, playlist: false, tool: tool);
    try {
      return _streamsFromJson(json);
    } on ApiException catch (first) {
      if (!first.message.contains('没有返回')) {
        rethrow;
      }
      if (_jsRuntime == null) {
        throw ApiException(
          '${first.message}\n'
          'yt-dlp 缺少 Deno JS runtime，无法解 YouTube 签名。请检查网络后重试，'
          '或把 deno.exe 放入应用目录的 tools/ 文件夹。',
        );
      }
      String? lastFormatError;
      for (final client in const ['web_safari', 'android_vr', 'tv', 'ios']) {
        try {
          final retry = await _runJson(
            tool,
            url,
            playlist: false,
            extractorArgs: 'youtube:player_client=$client',
          );
          final streams = _streamsFromJson(retry);
          _cache['clip:$id'] = _CachedJson(retry, DateTime.now());
          return streams;
        } on ApiException catch (error) {
          lastFormatError = error.message;
        }
      }
      throw ApiException(
        '${first.message}'
        '${lastFormatError == null ? '' : '\n备用播放器客户端仍失败：$lastFormatError'}',
      );
    }
  }

  Future<RemoteClip?> clipFromUrl(String url) async {
    if (!_desktop) {
      return null;
    }
    final tool = await _ensureTool();
    if (tool == null) {
      return null;
    }
    final json = await _jsonFor(
      'url:$url',
      url,
      playlist: false,
      tool: tool,
      ensureJsRuntime: false,
    );
    return _clipFromJson(json);
  }

  Future<RemoteStreams?> streamsFromUrl(String url) async {
    if (!_desktop) {
      return null;
    }
    final tool = await _ensureTool();
    if (tool == null) {
      return null;
    }
    final json = await _jsonFor(
      'url:$url',
      url,
      playlist: false,
      tool: tool,
      ensureJsRuntime: false,
    );
    return _streamsFromJson(json);
  }

  Future<String?> _ensureTool() async {
    if (_toolChecked) {
      return _tool;
    }
    _toolChecked = true;
    if (!_desktop) {
      return null;
    }
    _tool = await _findLocalTool();
    _tool ??= await _findManagedTool();
    _tool ??= await _findOnPath();
    _tool ??= await _downloadTool();
    return _tool;
  }

  Future<String?> _findLocalTool() async {
    final executable = File(Platform.resolvedExecutable).parent.path;
    final names = _toolNames;
    for (final base in [
      executable,
      p.join(executable, 'tools'),
      p.join(executable, 'bin'),
    ]) {
      for (final name in names) {
        final candidate = p.join(base, name);
        if (await File(candidate).exists()) {
          return candidate;
        }
      }
    }
    return null;
  }

  Future<String?> _findManagedTool() async {
    final candidate = p.join(
      StoragePaths.dataDir.path,
      'tools',
      _managedToolName,
    );
    if (await File(candidate).exists()) {
      return candidate;
    }
    return null;
  }

  Future<String?> _findOnPath() async {
    try {
      final result = Platform.isWindows
          ? await Process.run('where', ['yt-dlp.exe'])
          : await Process.run('which', ['yt-dlp']);
      if (result.exitCode != 0) {
        return null;
      }
      final lines = (result.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      for (final line in lines) {
        if (await File(line).exists()) {
          return line;
        }
      }
    } on ProcessException {
      // Fall through to managed download.
    }
    return null;
  }

  Future<String?> _downloadTool() async {
    if (!_desktop) {
      return null;
    }
    final asset = _releaseAssetName;
    final dir = Directory(p.join(StoragePaths.dataDir.path, 'tools'));
    final target = File(p.join(dir.path, _managedToolName));
    http.Client? client;
    try {
      await dir.create(recursive: true);
      client = createRemoteHttpClient(_proxy);
      final sumsResponse = await client
          .get(
            Uri.parse(
              'https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS',
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (sumsResponse.statusCode != 200) {
        return null;
      }
      final expected = _checksumFor(
        utf8.decode(sumsResponse.bodyBytes, allowMalformed: true),
        asset,
      );
      if (expected.isEmpty) {
        return null;
      }
      final response = await client
          .get(
            Uri.parse(
              'https://github.com/yt-dlp/yt-dlp/releases/latest/download/$asset',
            ),
          )
          .timeout(const Duration(seconds: 180));
      if (response.statusCode != 200) {
        return null;
      }
      final actual = sha256.convert(response.bodyBytes).toString();
      if (actual != expected) {
        return null;
      }
      await target.writeAsBytes(response.bodyBytes, flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', target.path]);
      }
      return target.path;
    } on Object {
      return null;
    } finally {
      client?.close();
    }
  }

  Future<String?> _ensureJsRuntime() {
    return _jsRuntimeFuture ??= _loadJsRuntime();
  }

  Future<String?> _loadJsRuntime() async {
    if (!_desktop) {
      return null;
    }
    final local = await _findLocalRuntime();
    if (local != null) {
      _jsRuntime = local;
      return local;
    }
    final onPath = await _findRuntimeOnPath();
    if (onPath != null) {
      _jsRuntime = onPath;
      return onPath;
    }
    final downloaded = await _downloadJsRuntime();
    _jsRuntime = downloaded;
    return downloaded;
  }

  Future<String?> _findLocalRuntime() async {
    final executable = File(Platform.resolvedExecutable).parent.path;
    for (final base in [
      executable,
      p.join(executable, 'tools'),
      p.join(executable, 'bin'),
      p.join(StoragePaths.dataDir.path, 'tools'),
    ]) {
      final candidate = p.join(base, _runtimeName);
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<String?> _findRuntimeOnPath() async {
    try {
      final result = Platform.isWindows
          ? await Process.run('where', [_runtimeName])
          : await Process.run('which', ['deno']);
      if (result.exitCode != 0) {
        return null;
      }
      final lines = (result.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      for (final line in lines) {
        if (await File(line).exists()) {
          return line;
        }
      }
    } on ProcessException {
      // Fall through to managed download.
    }
    return null;
  }

  Future<String?> _downloadJsRuntime() async {
    if (!_desktop) {
      return null;
    }
    final dir = Directory(p.join(StoragePaths.dataDir.path, 'tools'));
    final target = File(p.join(dir.path, _runtimeName));
    http.Client? client;
    try {
      await dir.create(recursive: true);
      client = createRemoteHttpClient(_proxy);
      final response = await client
          .get(Uri.parse(_runtimeReleaseUrl))
          .timeout(const Duration(seconds: 300));
      if (response.statusCode != 200) {
        return null;
      }
      final archive = ZipDecoder().decodeBytes(response.bodyBytes);
      ArchiveFile? binary;
      for (final file in archive.files) {
        if (file.isFile &&
            p.basename(file.name).toLowerCase() == _runtimeName.toLowerCase()) {
          binary = file;
          break;
        }
      }
      if (binary == null) {
        return null;
      }
      await target.writeAsBytes(binary.content as List<int>, flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', target.path]);
      }
      return target.path;
    } on Object {
      return null;
    } finally {
      client?.close();
    }
  }

  Map<String, String> _runtimeEnvironment() {
    final environment = Map<String, String>.from(Platform.environment);
    final runtime = _jsRuntime;
    if (runtime == null) {
      return environment;
    }
    final directory = File(runtime).parent.path;
    final key = environment.keys.firstWhere(
      (item) => item.toUpperCase() == 'PATH',
      orElse: () => 'PATH',
    );
    final separator = Platform.isWindows ? ';' : ':';
    final current = environment[key] ?? '';
    final present = current.split(separator).contains(directory);
    environment[key] = present ? current : '$directory$separator$current';
    return environment;
  }

  Future<Map<String, dynamic>> _jsonFor(
    String key,
    String url, {
    required bool playlist,
    required String tool,
    bool ensureJsRuntime = true,
  }) async {
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return cached.json;
    }
    final json = await _runJson(
      tool,
      url,
      playlist: playlist,
      ensureJsRuntime: ensureJsRuntime,
    );
    _cache[key] = _CachedJson(json, DateTime.now());
    return json;
  }

  Future<Map<String, dynamic>> _runJson(
    String tool,
    String url, {
    required bool playlist,
    String? extractorArgs,
    bool ensureJsRuntime = true,
  }) async {
    final args = <String>[
      '--ignore-config',
      '--ignore-no-formats-error',
      '--no-check-formats',
      '--format',
      'all',
      '--dump-single-json',
      '--no-warnings',
      '--skip-download',
      '--socket-timeout',
      '20',
      '--retries',
      '3',
    ];
    if (_proxy.isNotEmpty) {
      args.addAll([
        '--proxy',
        _proxy.contains('://') ? _proxy : 'http://$_proxy',
      ]);
    }
    if (_cookiePath.isNotEmpty) {
      if (!File(_cookiePath).existsSync()) {
        throw ApiException('YouTube Cookie 文件不存在：$_cookiePath');
      }
      args.addAll(['--cookies', _cookiePath]);
    }
    if (extractorArgs != null && extractorArgs.isNotEmpty) {
      args.addAll(['--extractor-args', extractorArgs]);
    }
    if (playlist) {
      args.add('--flat-playlist');
    } else {
      args.add('--no-playlist');
    }
    args.add(url);

    if (ensureJsRuntime) {
      await _ensureJsRuntime();
    }
    final process = await Process.start(
      tool,
      args,
      runInShell: false,
      environment: _runtimeEnvironment(),
    );
    final output = StringBuffer();
    final errors = StringBuffer();
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .forEach(output.write);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .forEach(errors.write);
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await Future.wait([stdoutDone, stderrDone]);
    if (exitCode != 0) {
      final detail = errors.toString().trim();
      throw ApiException(
        detail.isEmpty
            ? 'yt-dlp 解析失败（退出码 $exitCode）。'
            : 'yt-dlp 解析失败：${_shorten(detail)}',
      );
    }
    final text = output.toString().trim();
    if (text.isEmpty) {
      throw const ApiException('yt-dlp 没有返回解析结果。');
    }
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    throw const ApiException('yt-dlp 返回了无法识别的数据。');
  }

  RemoteClip _clipFromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    if (id.isEmpty) {
      throw const ApiException('yt-dlp 没有返回视频 ID。');
    }
    if (json['is_live'] == true) {
      throw const ApiException('暂不支持下载 YouTube 直播。');
    }
    final title = _string(json['title']);
    return RemoteClip(
      id: id,
      title: title.isEmpty ? 'YouTube 视频 $id' : title,
      author: _author(json),
      authorId: _string(json['channel_id']),
      description: _string(json['description']),
      coverUrl: _cover(json, id),
      duration: Duration(
        milliseconds: ((_number(json['duration']) ?? 0) * 1000).round(),
      ),
      publishedAt: _uploadDate(json['upload_date']),
    );
  }

  RemoteCollection _collectionFromJson(Map<String, dynamic> json) {
    final entries = (json['entries'] as List?) ?? const [];
    final clips = <RemoteClip>[];
    final fallbackAuthor = _author(json);
    for (final entry in entries) {
      if (entry is! Map) {
        continue;
      }
      final map = entry.map((key, value) => MapEntry('$key', value));
      final id = _string(map['id']);
      if (id.isEmpty) {
        continue;
      }
      final title = _string(map['title']);
      clips.add(
        RemoteClip(
          id: id,
          title: title.isEmpty ? 'YouTube 视频 $id' : title,
          author: _author(map).isEmpty ? fallbackAuthor : _author(map),
          authorId: _string(map['channel_id']),
          description: _string(map['description']),
          coverUrl: _cover(map, id),
          duration: Duration(
            milliseconds: ((_number(map['duration']) ?? 0) * 1000).round(),
          ),
          publishedAt: _uploadDate(map['upload_date']),
        ),
      );
    }
    if (clips.isEmpty) {
      throw const ApiException('yt-dlp 没有返回播放列表内容。');
    }
    final title = _string(json['title']);
    return RemoteCollection(
      id: _string(json['id']),
      title: title.isEmpty ? 'YouTube 播放列表' : title,
      author: fallbackAuthor,
      description: _string(json['description']),
      coverUrl: _cover(json, clips.first.id),
      clips: clips,
    );
  }

  RemoteStreams _streamsFromJson(Map<String, dynamic> json) {
    final formats = (json['formats'] as List?) ?? const [];
    final videos = <RemoteStream>[];
    final audios = <RemoteStream>[];
    final muxed = <RemoteStream>[];
    final rejected = <String>[];
    for (final entry in formats) {
      if (entry is! Map) {
        continue;
      }
      final map = entry.map((key, value) => MapEntry('$key', value));
      final url = _string(map['url']);
      final ext = _string(map['ext']).toLowerCase();
      final videoCodec = _string(map['vcodec']).toLowerCase();
      final audioCodec = _string(map['acodec']).toLowerCase();
      if (url.isEmpty) {
        rejected.add('${ext.isEmpty ? '未知' : ext} 无直链');
        continue;
      }
      final protocol = _string(map['protocol']).toLowerCase();
      if (protocol.contains('m3u8') || protocol.contains('dash')) {
        rejected.add('$ext $protocol');
        continue;
      }
      final hasVideo = videoCodec.isNotEmpty && videoCodec != 'none';
      final hasAudio = audioCodec.isNotEmpty && audioCodec != 'none';
      if (!hasVideo && !hasAudio) {
        rejected.add('$ext 无音视频编码');
        continue;
      }
      final videoSupported = ext == 'mp4' || (_desktop && ext == 'webm');
      final audioSupported =
          ext == 'm4a' || ext == 'mp4' || (_desktop && ext == 'webm');
      if ((hasVideo && !videoSupported) || (hasAudio && !audioSupported)) {
        rejected.add('$ext $videoCodec/$audioCodec');
        continue;
      }
      final streamHeaders = _headers(map['http_headers'])
        ..removeWhere(
          (key, value) =>
              key.toLowerCase() == 'cookie' ||
              key.toLowerCase() == 'authorization',
        );
      final stream = RemoteStream(
        url: url,
        container: ext,
        videoCodec: hasVideo ? videoCodec : '',
        audioCodec: hasAudio ? audioCodec : '',
        height: _integer(map['height']) ?? 0,
        bitrate: ((_number(map['tbr']) ?? 0) * 1000).round(),
        sizeBytes:
            _integer(map['filesize']) ?? _integer(map['filesize_approx']),
        isMuxed: hasVideo && hasAudio,
        headers: streamHeaders,
      );
      if (hasVideo && !hasAudio) {
        videos.add(stream);
      } else if (hasAudio && !hasVideo) {
        audios.add(stream);
      } else {
        muxed.add(stream);
      }
    }
    if (videos.isEmpty && audios.isEmpty && muxed.isEmpty) {
      final detail = rejected.isEmpty
          ? 'yt-dlp 没有返回任何可下载格式。'
          : 'yt-dlp 没有返回可用的 MP4/M4A/WebM 直链格式。可用格式：'
                '${rejected.take(8).join('；')}';
      throw ApiException(detail);
    }
    return RemoteStreams(videos: videos, audios: audios, muxed: muxed);
  }

  String _author(Map<String, dynamic> json) {
    return _firstNonEmpty([
      _string(json['uploader']),
      _string(json['channel']),
      _string(json['creator']),
    ]);
  }

  String? _cover(Map<String, dynamic> json, String id) {
    final direct = _string(json['thumbnail']);
    if (direct.isNotEmpty) {
      return direct;
    }
    final thumbnails = (json['thumbnails'] as List?) ?? const [];
    for (final thumbnail in thumbnails.reversed) {
      if (thumbnail is Map) {
        final url = _string(thumbnail['url']);
        if (url.isNotEmpty) {
          return url;
        }
      }
    }
    return id.isEmpty ? null : 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  }

  Map<String, String> _headers(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return value.map(
      (key, item) => MapEntry('$key', item == null ? '' : '$item'),
    )..removeWhere((key, value) => value.isEmpty);
  }

  DateTime? _uploadDate(Object? value) {
    final text = _string(value);
    if (!RegExp(r'^\d{8}$').hasMatch(text)) {
      return null;
    }
    return DateTime.tryParse(
      '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}',
    );
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

  int? _integer(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  double? _number(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value');
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _shorten(String value) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 400 ? text : text.substring(0, 400);
  }

  String _checksumFor(String sums, String asset) {
    for (final line in const LineSplitter().convert(sums)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts.last == asset) {
        return parts.first.toLowerCase();
      }
    }
    return '';
  }

  String get _managedToolName => Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';

  String get _runtimeName => Platform.isWindows ? 'deno.exe' : 'deno';

  String get _runtimeReleaseUrl {
    if (Platform.isWindows) {
      return 'https://github.com/denoland/deno/releases/latest/download/'
          'deno-x86_64-pc-windows-msvc.zip';
    }
    final version = Platform.version.toLowerCase();
    final arm = version.contains('aarch64') || version.contains('arm64');
    if (Platform.isMacOS) {
      return arm
          ? 'https://github.com/denoland/deno/releases/latest/download/'
                'deno-aarch64-apple-darwin.zip'
          : 'https://github.com/denoland/deno/releases/latest/download/'
                'deno-x86_64-apple-darwin.zip';
    }
    return arm
        ? 'https://github.com/denoland/deno/releases/latest/download/'
              'deno-aarch64-unknown-linux-gnu.zip'
        : 'https://github.com/denoland/deno/releases/latest/download/'
              'deno-x86_64-unknown-linux-gnu.zip';
  }

  List<String> get _toolNames =>
      Platform.isWindows ? const ['yt-dlp.exe'] : const ['yt-dlp'];

  String get _releaseAssetName {
    if (Platform.isWindows) {
      return 'yt-dlp.exe';
    }
    if (Platform.isMacOS) {
      return 'yt-dlp_macos';
    }
    final version = Platform.version.toLowerCase();
    if (version.contains('aarch64') || version.contains('arm64')) {
      return 'yt-dlp_linux_aarch64';
    }
    return 'yt-dlp_linux';
  }

  String _watchUrl(String id) => 'https://www.youtube.com/watch?v=$id';

  String _listUrl(String id) => 'https://www.youtube.com/playlist?list=$id';

  void close() {
    _cache.clear();
  }
}

class _CachedJson {
  const _CachedJson(this.json, this.at);

  final Map<String, dynamic> json;
  final DateTime at;
}
