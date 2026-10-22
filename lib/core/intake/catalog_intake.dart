import '../api/service_exception.dart';
import '../api/bili_gateway.dart';
import '../domain/catalog.dart';
import '../util/identifiers.dart';
import 'link_recognizer.dart';

class CatalogIntake {
  CatalogIntake(this.client);

  final BiliGateway client;

  Future<MediaCatalog> ingest(String rawInput) async {
    var classified = recognizeLink(rawInput);
    if (classified.kind == LinkKind.shortLink && classified.url != null) {
      final expanded = await client.expandShortUrl(Uri.parse(classified.url!));
      classified = recognizeLink(expanded.toString());
    }
    if (!classified.isKnown) {
      throw const ApiException('无法识别的输入，请粘贴视频、番剧、收藏夹或 创作者链接，或直接输入 BV/AV 号。');
    }
    switch (classified.kind) {
      case LinkKind.video:
        return _resolveVideo(classified, rawInput);
      case LinkKind.bangumi:
        return _resolveBangumi(classified, rawInput);
      case LinkKind.cheese:
        return _resolveCheese(classified, rawInput);
      case LinkKind.favorite:
        return _resolveFavorite(classified, rawInput);
      case LinkKind.uploader:
        return _resolveUploader(classified, rawInput);
      case LinkKind.season:
      case LinkKind.series:
        return _resolveCollection(classified, rawInput);
      case LinkKind.watchLater:
        return _resolveWatchLater(rawInput);
      case LinkKind.tubeClip:
      case LinkKind.tubeList:
      case LinkKind.chirpPost:
      case LinkKind.douyinClip:
        throw const ApiException('该链接需要由远程来源解析。');
      case LinkKind.shortLink:
      case LinkKind.unknown:
        throw const ApiException('无法识别的输入。');
    }
  }

  Future<MediaCatalog> fetchNextPage(MediaCatalog catalog) async {
    if (!catalog.hasMore) {
      return catalog;
    }
    final currentPage = int.tryParse(catalog.cursor ?? '1') ?? 1;
    final nextPage = currentPage + 1;
    switch (catalog.kind) {
      case CatalogKind.favorite:
        final mediaId = int.tryParse(catalog.meta['mediaId'] ?? '');
        if (mediaId == null) {
          return catalog;
        }
        final result = await client.favoriteItems(mediaId, page: nextPage);
        return catalog.appendPage(
          next: _favoriteItems(result.items, catalog.title),
          cursor: '$nextPage',
          hasMore: result.hasMore,
        );
      case CatalogKind.uploader:
        final mid = int.tryParse(catalog.meta['mid'] ?? '');
        if (mid == null) {
          return catalog;
        }
        final result = await client.uploaderVideos(mid, page: nextPage);
        return catalog.appendPage(
          next: _summaryItems(result.items, catalog.title),
          cursor: '$nextPage',
          hasMore: result.hasMore,
          total: result.total,
        );
      case CatalogKind.season:
      case CatalogKind.series:
        final mid = int.tryParse(catalog.meta['mid'] ?? '');
        final id = int.tryParse(catalog.meta['collectionId'] ?? '');
        if (mid == null || id == null) {
          return catalog;
        }
        final result = await client.collectionArchives(
          mid: mid,
          id: id,
          kind: catalog.kind == CatalogKind.season ? 'season' : 'series',
          page: nextPage,
        );
        return catalog.appendPage(
          next: _summaryItems(result.items, catalog.title),
          cursor: '$nextPage',
          hasMore: result.hasMore,
          total: result.total,
        );
      case _:
        return catalog;
    }
  }

  Future<MediaCatalog> _resolveVideo(
    RecognizedLink input,
    String rawInput,
  ) async {
    final detail = await client.videoDetail(bvid: input.bvid, aid: input.aid);
    final tracks = detail.pages.asMap().entries.map((entry) {
      final page = entry.value;
      return CatalogTrack(
        id: 'video:${detail.bvid}:${page.cid}',
        title: page.track.isEmpty ? detail.title : page.track,
        index: page.page == 0 ? entry.key + 1 : page.page,
        durationMs: page.durationMs,
        bvid: detail.bvid,
        aid: detail.aid,
        cid: page.cid,
        coverUrl: detail.cover,
        pubDate: detail.pubDate?.toIso8601String(),
        creator: detail.creator,
        creatorId: detail.creatorId,
      );
    }).toList();
    if (tracks.isEmpty) {
      throw const ApiException('没有解析到可用的分段。');
    }
    final item = CatalogEntry(
      id: detail.bvid,
      title: detail.title,
      coverUrl: detail.cover,
      creator: detail.creator,
      creatorId: detail.creatorId,
      pubDate: detail.pubDate?.toIso8601String(),
      durationMs: detail.durationMs,
      tracks: tracks,
      summary: detail.description,
    );
    return MediaCatalog(
      id: makeId('src'),
      kind: CatalogKind.video,
      title: detail.title,
      input: rawInput,
      items: [item],
      coverUrl: detail.cover,
      creator: detail.creator,
      creatorId: detail.creatorId,
      total: tracks.length,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  Future<MediaCatalog> _resolveBangumi(
    RecognizedLink input,
    String rawInput,
  ) async {
    final season = await client.bangumiSeason(
      epId: input.epId,
      seasonId: input.seasonId,
    );
    return _seasonSource(season, CatalogKind.bangumi, rawInput);
  }

  Future<MediaCatalog> _resolveCheese(
    RecognizedLink input,
    String rawInput,
  ) async {
    final season = await client.cheeseSeason(
      seasonId: input.seasonId,
      epId: input.epId,
    );
    return _seasonSource(season, CatalogKind.cheese, rawInput);
  }

  MediaCatalog _seasonSource(
    SeasonDetail season,
    CatalogKind kind,
    String rawInput,
  ) {
    final items = season.episodes.map((episode) {
      final title = episode.longTitle.isNotEmpty
          ? episode.longTitle
          : episode.title;
      final track = CatalogTrack(
        id: '${kind.wire}:${episode.epId}:${episode.cid}',
        title: title,
        index: episode.index,
        durationMs: episode.durationMs,
        bvid: episode.bvid.isEmpty ? null : episode.bvid,
        aid: episode.aid == 0 ? null : episode.aid,
        cid: episode.cid == 0 ? null : episode.cid,
        epId: episode.epId,
        seasonId: episode.seasonId,
        coverUrl: episode.cover.isEmpty ? season.cover : episode.cover,
        pubDate: episode.pubDate?.toIso8601String(),
        series: season.title,
        episodeNo: episode.index,
      );
      return CatalogEntry(
        id: '${kind.wire}:${episode.epId}',
        title: title,
        coverUrl: track.coverUrl,
        pubDate: track.pubDate,
        durationMs: episode.durationMs,
        tracks: [track],
      );
    }).toList();
    if (items.isEmpty) {
      throw const ApiException('没有解析到可用的剧集。');
    }
    return MediaCatalog(
      id: makeId('src'),
      kind: kind,
      title: season.title,
      input: rawInput,
      items: items,
      coverUrl: season.cover,
      creator: season.creator,
      creatorId: season.creatorId,
      total: items.length,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  Future<MediaCatalog> _resolveFavorite(
    RecognizedLink input,
    String rawInput,
  ) async {
    final mediaId = input.mediaId;
    if (mediaId == null) {
      throw const ApiException('无法从链接中读取收藏夹 ID。');
    }
    FavoriteFolder? folder;
    try {
      folder = await client.favoriteFolder(mediaId);
    } on Object {
      folder = null;
    }
    final page = await client.favoriteItems(mediaId, page: 1);
    final title = folder?.title.isNotEmpty == true
        ? folder!.title
        : '收藏夹 $mediaId';
    final items = _favoriteItems(page.items, title);
    if (items.isEmpty && !page.hasMore) {
      throw const ApiException('收藏夹为空，或没有访问权限。');
    }
    return MediaCatalog(
      id: makeId('src'),
      kind: CatalogKind.favorite,
      title: title,
      input: rawInput,
      items: items,
      coverUrl: folder?.cover,
      creator: folder?.creator,
      creatorId: folder?.creatorId ?? input.mid,
      cursor: '1',
      hasMore: page.hasMore,
      total: folder?.mediaCount,
      createdAt: DateTime.now().toIso8601String(),
      meta: {'mediaId': '$mediaId'},
    );
  }

  Future<MediaCatalog> _resolveUploader(
    RecognizedLink input,
    String rawInput,
  ) async {
    final mid = input.mid;
    if (mid == null) {
      throw const ApiException('无法从链接中读取 创作者 ID。');
    }
    final page = await client.uploaderVideos(mid, page: 1);
    final title = page.items.isNotEmpty
        ? '${page.items.first.creator} 的投稿'
        : '创作者 $mid';
    return MediaCatalog(
      id: makeId('src'),
      kind: CatalogKind.uploader,
      title: title,
      input: rawInput,
      items: _summaryItems(page.items, title),
      creator: page.items.isNotEmpty ? page.items.first.creator : '',
      creatorId: mid,
      cursor: '1',
      hasMore: page.hasMore,
      total: page.total,
      createdAt: DateTime.now().toIso8601String(),
      meta: {'mid': '$mid'},
    );
  }

  Future<MediaCatalog> _resolveCollection(
    RecognizedLink input,
    String rawInput,
  ) async {
    final mid = input.mid;
    final collectionId = input.collectionId;
    if (mid == null || collectionId == null) {
      throw const ApiException('无法从链接中读取合集 ID。');
    }
    final isSeason = input.kind == LinkKind.season;
    final page = await client.collectionArchives(
      mid: mid,
      id: collectionId,
      kind: isSeason ? 'season' : 'series',
      page: 1,
    );
    String title = isSeason ? '合集 $collectionId' : '系列 $collectionId';
    try {
      final collections = await client.spaceCollections(mid);
      for (final collection in collections) {
        if (collection.id == collectionId &&
            collection.kind == (isSeason ? 'season' : 'series')) {
          title = collection.title;
          break;
        }
      }
    } on Object {
      // The archives endpoint already succeeded; a title fallback is acceptable.
    }
    return MediaCatalog(
      id: makeId('src'),
      kind: isSeason ? CatalogKind.season : CatalogKind.series,
      title: title,
      input: rawInput,
      items: _summaryItems(page.items, title),
      creatorId: mid,
      cursor: '1',
      hasMore: page.hasMore,
      total: page.total,
      createdAt: DateTime.now().toIso8601String(),
      meta: {'mid': '$mid', 'collectionId': '$collectionId'},
    );
  }

  Future<MediaCatalog> _resolveWatchLater(String rawInput) async {
    final items = await client.watchLater();
    if (items.isEmpty) {
      throw const ApiException('稍后再看为空，或当前账号未登录。');
    }
    return MediaCatalog(
      id: makeId('src'),
      kind: CatalogKind.watchLater,
      title: '稍后再看',
      input: rawInput,
      items: items.map((item) {
        return CatalogEntry(
          id: 'watchlater:${item.bvid}',
          title: item.title,
          coverUrl: item.cover,
          creator: item.creator,
          creatorId: item.creatorId,
          pubDate: item.pubDate?.toIso8601String(),
          durationMs: item.durationMs,
          tracks: [
            CatalogTrack(
              id: 'video:${item.bvid}:${item.cid}',
              title: item.title,
              index: 1,
              durationMs: item.durationMs,
              bvid: item.bvid,
              aid: item.aid,
              cid: item.cid == 0 ? null : item.cid,
              coverUrl: item.cover,
              pubDate: item.pubDate?.toIso8601String(),
              creator: item.creator,
              creatorId: item.creatorId,
              collection: '稍后再看',
            ),
          ],
        );
      }).toList(),
      total: items.length,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  List<CatalogEntry> _favoriteItems(
    List<VideoSummary> videos,
    String collection,
  ) {
    return videos.map((video) {
      return CatalogEntry(
        id: video.bvid.isNotEmpty ? video.bvid : 'av${video.aid}',
        title: video.title,
        coverUrl: video.cover,
        creator: video.creator,
        creatorId: video.creatorId,
        pubDate: video.pubDate?.toIso8601String(),
        durationMs: video.durationMs,
        summary: video.summary,
        tracks: [
          CatalogTrack(
            id: 'video:${video.bvid.isNotEmpty ? video.bvid : video.aid}:0',
            title: video.title,
            index: 1,
            durationMs: video.durationMs,
            bvid: video.bvid.isEmpty ? null : video.bvid,
            aid: video.aid == 0 ? null : video.aid,
            cid: null,
            coverUrl: video.cover,
            pubDate: video.pubDate?.toIso8601String(),
            creator: video.creator,
            creatorId: video.creatorId,
            collection: collection,
          ),
        ],
      );
    }).toList();
  }

  List<CatalogEntry> _summaryItems(
    List<VideoSummary> videos,
    String collection,
  ) {
    return _favoriteItems(videos, collection);
  }
}
