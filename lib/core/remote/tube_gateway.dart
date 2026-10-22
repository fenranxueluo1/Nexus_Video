import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../api/service_exception.dart';
import 'remote_models.dart';
import 'remote_network.dart';
import 'tube_dlp_bridge.dart';

class TubeGateway {
  TubeGateway({String proxy = '', String cookiePath = ''}) {
    _proxy = proxy.trim();
    _cookiePath = cookiePath.trim();
    _tube = _create();
    _dlp = TubeDlpBridge(proxy: _proxy, cookiePath: _cookiePath);
  }

  late YoutubeExplode _tube;
  late TubeDlpBridge _dlp;
  String _proxy = '';
  String _cookiePath = '';

  set cookiePath(String value) {
    final next = value.trim();
    if (next == _cookiePath) {
      return;
    }
    _cookiePath = next;
    _dlp.cookiePath = next;
  }

  set proxy(String value) {
    final next = value.trim();
    if (next == _proxy) {
      return;
    }
    _tube.close();
    _proxy = next;
    _tube = _create();
    _dlp.proxy = next;
  }

  YoutubeExplode _create() {
    return YoutubeExplode(
      httpClient: YoutubeHttpClient(createRemoteHttpClient(_proxy)),
    );
  }

  Future<RemoteClip> clip(String id) async {
    try {
      final fromTool = await _dlp.clip(id);
      if (fromTool != null) {
        return fromTool;
      }
      final video = await _tube.videos.get(id);
      return _toClip(video);
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      throw _error(error);
    }
  }

  Future<RemoteCollection> collection(String id) async {
    try {
      final fromTool = await _dlp.collection(id);
      if (fromTool != null) {
        return fromTool;
      }
      final playlist = await _tube.playlists.get(id);
      final videos = await _tube.playlists.getVideos(id).take(200).toList();
      if (videos.isEmpty) {
        throw const ApiException('该播放列表为空或无法访问。');
      }
      return RemoteCollection(
        id: playlist.id.value,
        title: playlist.title.isEmpty ? 'YouTube 播放列表' : playlist.title,
        author: playlist.author,
        description: playlist.description,
        coverUrl: videos.first.thumbnails.highResUrl,
        clips: videos.map(_toClip).toList(),
      );
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      throw _error(error);
    }
  }

  Future<RemoteStreams> streams(String id) async {
    try {
      final fromTool = await _dlp.streams(id);
      if (fromTool != null) {
        return fromTool;
      }
      final manifest = await _tube.videos.streams.getManifest(id);
      final videos = <RemoteStream>[];
      final audios = <RemoteStream>[];
      final muxed = <RemoteStream>[];

      for (final stream in manifest.videoOnly) {
        if (stream.container != StreamContainer.mp4) {
          continue;
        }
        videos.add(
          RemoteStream(
            url: stream.url.toString(),
            container: stream.container.name,
            videoCodec: stream.videoCodec,
            audioCodec: '',
            height: stream.videoResolution.height,
            bitrate: stream.bitrate.bitsPerSecond,
            sizeBytes: stream.size.totalBytes > 0
                ? stream.size.totalBytes
                : null,
          ),
        );
      }

      for (final stream in manifest.audioOnly) {
        final isMp4Audio =
            stream.container == StreamContainer.mp4 ||
            stream.audioCodec.toLowerCase().contains('mp4a');
        if (!isMp4Audio) {
          continue;
        }
        audios.add(
          RemoteStream(
            url: stream.url.toString(),
            container: stream.container.name,
            videoCodec: '',
            audioCodec: stream.audioCodec,
            height: 0,
            bitrate: stream.bitrate.bitsPerSecond,
            sizeBytes: stream.size.totalBytes > 0
                ? stream.size.totalBytes
                : null,
          ),
        );
      }

      for (final stream in manifest.muxed) {
        if (stream.container != StreamContainer.mp4) {
          continue;
        }
        muxed.add(
          RemoteStream(
            url: stream.url.toString(),
            container: stream.container.name,
            videoCodec: stream.videoCodec,
            audioCodec: stream.audioCodec,
            height: stream.videoResolution.height,
            bitrate: stream.bitrate.bitsPerSecond,
            sizeBytes: stream.size.totalBytes > 0
                ? stream.size.totalBytes
                : null,
            isMuxed: true,
          ),
        );
      }

      if (videos.isEmpty && audios.isEmpty && muxed.isEmpty) {
        throw const ApiException('没有找到可下载的 MP4/M4A 流，请更换代理后重试。');
      }
      return RemoteStreams(videos: videos, audios: audios, muxed: muxed);
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      throw _error(error);
    }
  }

  RemoteClip _toClip(Video video) {
    if (video.isLive) {
      throw const ApiException('暂不支持下载 YouTube 直播。');
    }
    return RemoteClip(
      id: video.id.value,
      title: video.title,
      author: video.author,
      authorId: video.channelId.value,
      description: video.description,
      coverUrl: video.thumbnails.highResUrl,
      duration: video.duration ?? Duration.zero,
      publishedAt: video.publishDate ?? video.uploadDate,
    );
  }

  ApiException _error(Object error) {
    final text = error.toString();
    if (text.contains('RequestLimitExceeded')) {
      return const ApiException('YouTube 请求被限流，请更换代理或稍后重试。');
    }
    if (text.contains('VideoUnavailable') ||
        text.contains('VideoUnplayable') ||
        text.contains('VideoRequiresPurchase')) {
      return const ApiException('YouTube 视频不可用，或当前地区/账号无法访问。');
    }
    if (text.contains('SocketException') ||
        text.contains('HttpException') ||
        text.contains('HandshakeException')) {
      return const ApiException('无法连接 YouTube，请检查网络或代理设置。');
    }
    return ApiException('YouTube 解析失败：$text');
  }

  void close() {
    _tube.close();
    _dlp.close();
  }
}
