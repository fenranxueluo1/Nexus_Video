import '../api/service_exception.dart';
import '../domain/catalog.dart';
import '../intake/link_recognizer.dart';
import '../util/identifiers.dart';
import 'chirp_gateway.dart';
import 'douyin_gateway.dart';
import 'remote_models.dart';
import 'tube_gateway.dart';

class RemoteIntake {
  RemoteIntake(this._tube, this._chirp, this._douyin);

  final TubeGateway _tube;
  final ChirpGateway _chirp;
  final DouyinGateway _douyin;

  Future<MediaCatalog> ingest(String rawInput) async {
    final link = recognizeLink(rawInput);
    switch (link.kind) {
      case LinkKind.tubeClip:
        final id = link.tubeId;
        if (id == null || id.isEmpty) {
          throw const ApiException('无法从链接中读取 YouTube 视频 ID。');
        }
        final clip = await _tube.clip(id);
        return _singleClip(clip, CatalogKind.tube, rawInput);
      case LinkKind.tubeList:
        final id = link.tubeListId;
        if (id == null || id.isEmpty) {
          throw const ApiException('无法从链接中读取 YouTube 播放列表 ID。');
        }
        final collection = await _tube.collection(id);
        return _collection(collection, rawInput);
      case LinkKind.chirpPost:
        final id = link.chirpId;
        if (id == null || id.isEmpty) {
          throw const ApiException('无法从链接中读取 X 帖子 ID。');
        }
        final clip = await _chirp.post(id);
        return _singleClip(clip, CatalogKind.chirp, rawInput);
      case LinkKind.douyinClip:
        final target = (link.url ?? '').trim().isNotEmpty
            ? link.url!
            : (link.douyinId ?? '');
        if (target.isEmpty) {
          throw const ApiException('无法从链接中读取抖音视频 ID。');
        }
        final clip = await _douyin.clip(target);
        return _singleClip(clip, CatalogKind.douyin, rawInput);
      case LinkKind.unknown:
      case LinkKind.shortLink:
        throw const ApiException('无法识别的远程链接。');
      default:
        throw const ApiException('该链接不是 YouTube、X 或抖音链接。');
    }
  }

  Future<MediaCatalog> fetchNextPage(MediaCatalog catalog) async => catalog;

  MediaCatalog _singleClip(RemoteClip clip, CatalogKind kind, String rawInput) {
    final track = _track(clip, kind, index: 1, series: clip.author);
    final item = CatalogEntry(
      id: '${kind.wire}:${clip.id}',
      title: clip.title,
      coverUrl: clip.coverUrl,
      creator: clip.author,
      pubDate: clip.publishedAt?.toIso8601String(),
      durationMs: clip.duration.inMilliseconds,
      summary: clip.description,
      tracks: [track],
    );
    return MediaCatalog(
      id: makeId('src'),
      kind: kind,
      title: clip.title,
      input: rawInput,
      items: [item],
      coverUrl: clip.coverUrl,
      creator: clip.author,
      total: 1,
      createdAt: DateTime.now().toIso8601String(),
      meta: {'remoteId': clip.id},
    );
  }

  MediaCatalog _collection(RemoteCollection collection, String rawInput) {
    if (collection.clips.isEmpty) {
      throw const ApiException('播放列表中没有可下载的内容。');
    }
    final tracks = <CatalogTrack>[];
    for (var index = 0; index < collection.clips.length; index += 1) {
      final clip = collection.clips[index];
      tracks.add(
        _track(
          clip,
          CatalogKind.tube,
          index: index + 1,
          series: collection.title,
        ),
      );
    }
    final duration = collection.clips.fold<Duration>(
      Duration.zero,
      (sum, clip) => sum + clip.duration,
    );
    final item = CatalogEntry(
      id: '${CatalogKind.tube.wire}:${collection.id}',
      title: collection.title,
      coverUrl: collection.coverUrl ?? collection.clips.first.coverUrl,
      creator: collection.author,
      durationMs: duration.inMilliseconds,
      summary: collection.description,
      tracks: tracks,
    );
    return MediaCatalog(
      id: makeId('src'),
      kind: CatalogKind.tube,
      title: collection.title,
      input: rawInput,
      items: [item],
      coverUrl: item.coverUrl,
      creator: collection.author,
      total: tracks.length,
      createdAt: DateTime.now().toIso8601String(),
      meta: {'remoteId': collection.id},
    );
  }

  CatalogTrack _track(
    RemoteClip clip,
    CatalogKind kind, {
    required int index,
    required String series,
  }) {
    return CatalogTrack(
      id: '${kind.wire}:${clip.id}',
      title: clip.title,
      index: index,
      durationMs: clip.duration.inMilliseconds,
      coverUrl: clip.coverUrl,
      pubDate: clip.publishedAt?.toIso8601String(),
      creator: clip.author,
      series: series,
    );
  }
}
