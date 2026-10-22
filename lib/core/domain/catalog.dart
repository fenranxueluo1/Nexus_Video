enum CatalogKind {
  video('video'),
  bangumi('bangumi'),
  cheese('cheese'),
  favorite('favorite'),
  collectedFavorite('collected_favorite'),
  uploader('uploader'),
  season('season'),
  series('series'),
  watchLater('watch_later'),
  tube('tube'),
  chirp('chirp'),
  douyin('douyin'),
  unknown('unknown');

  const CatalogKind(this.wire);
  final String wire;

  static CatalogKind fromWire(String? value) {
    return CatalogKind.values.firstWhere(
      (kind) => kind.wire == value,
      orElse: () => CatalogKind.unknown,
    );
  }
}

class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.title,
    required this.index,
    this.durationMs = 0,
    this.bvid,
    this.aid,
    this.cid,
    this.epId,
    this.seasonId,
    this.coverUrl,
    this.pubDate,
    this.creator,
    this.creatorId,
    this.series,
    this.seasonNo,
    this.episodeNo,
    this.collection,
  });

  final String id;
  final String title;
  final int index;
  final int durationMs;
  final String? bvid;
  final int? aid;
  final int? cid;
  final int? epId;
  final int? seasonId;
  final String? coverUrl;
  final String? pubDate;
  final String? creator;
  final int? creatorId;
  final String? series;
  final int? seasonNo;
  final int? episodeNo;
  final String? collection;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'index': index,
    'durationMs': durationMs,
    'bvid': bvid,
    'aid': aid,
    'cid': cid,
    'epId': epId,
    'seasonId': seasonId,
    'coverUrl': coverUrl,
    'pubDate': pubDate,
    'creator': creator,
    'creatorId': creatorId,
    'series': series,
    'seasonNo': seasonNo,
    'episodeNo': episodeNo,
    'collection': collection,
  };

  factory CatalogTrack.fromJson(Map<String, dynamic> json) => CatalogTrack(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    index: (json['index'] as num?)?.toInt() ?? 1,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    bvid: json['bvid'] as String?,
    aid: (json['aid'] as num?)?.toInt(),
    cid: (json['cid'] as num?)?.toInt(),
    epId: (json['epId'] as num?)?.toInt(),
    seasonId: (json['seasonId'] as num?)?.toInt(),
    coverUrl: json['coverUrl'] as String?,
    pubDate: json['pubDate'] as String?,
    creator: json['creator'] as String?,
    creatorId: (json['creatorId'] as num?)?.toInt(),
    series: json['series'] as String?,
    seasonNo: (json['seasonNo'] as num?)?.toInt(),
    episodeNo: (json['episodeNo'] as num?)?.toInt(),
    collection: json['collection'] as String?,
  );

  CatalogTrack copyWith({int? cid, String? coverUrl, String? bvid, int? aid}) =>
      CatalogTrack(
        id: id,
        title: title,
        index: index,
        durationMs: durationMs,
        bvid: bvid ?? this.bvid,
        aid: aid ?? this.aid,
        cid: cid ?? this.cid,
        epId: epId,
        seasonId: seasonId,
        coverUrl: coverUrl ?? this.coverUrl,
        pubDate: pubDate,
        creator: creator,
        creatorId: creatorId,
        series: series,
        seasonNo: seasonNo,
        episodeNo: episodeNo,
        collection: collection,
      );
}

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.title,
    this.coverUrl,
    this.creator,
    this.creatorId,
    this.pubDate,
    this.durationMs = 0,
    this.tracks = const [],
    this.summary,
  });

  final String id;
  final String title;
  final String? coverUrl;
  final String? creator;
  final int? creatorId;
  final String? pubDate;
  final int durationMs;
  final List<CatalogTrack> tracks;
  final String? summary;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'creator': creator,
    'creatorId': creatorId,
    'pubDate': pubDate,
    'durationMs': durationMs,
    'tracks': tracks.map((track) => track.toJson()).toList(),
    'summary': summary,
  };

  factory CatalogEntry.fromJson(Map<String, dynamic> json) => CatalogEntry(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    coverUrl: json['coverUrl'] as String?,
    creator: json['creator'] as String?,
    creatorId: (json['creatorId'] as num?)?.toInt(),
    pubDate: json['pubDate'] as String?,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    tracks: ((json['tracks'] as List?) ?? const [])
        .map((track) => CatalogTrack.fromJson(track as Map<String, dynamic>))
        .toList(),
    summary: json['summary'] as String?,
  );
}

class MediaCatalog {
  const MediaCatalog({
    required this.id,
    required this.kind,
    required this.title,
    required this.input,
    required this.items,
    this.coverUrl,
    this.creator,
    this.creatorId,
    this.cursor,
    this.hasMore = false,
    this.total,
    this.createdAt,
    this.meta = const {},
  });

  final String id;
  final CatalogKind kind;
  final String title;
  final String input;
  final List<CatalogEntry> items;
  final String? coverUrl;
  final String? creator;
  final int? creatorId;
  final String? cursor;
  final bool hasMore;
  final int? total;
  final String? createdAt;
  final Map<String, String> meta;

  int get trackCount => items.fold(0, (sum, item) => sum + item.tracks.length);

  MediaCatalog appendPage({
    required List<CatalogEntry> next,
    String? cursor,
    bool? hasMore,
    int? total,
  }) {
    return MediaCatalog(
      id: id,
      kind: kind,
      title: title,
      input: input,
      items: [...items, ...next],
      coverUrl: coverUrl,
      creator: creator,
      creatorId: creatorId,
      cursor: cursor ?? this.cursor,
      hasMore: hasMore ?? this.hasMore,
      total: total ?? this.total,
      createdAt: createdAt,
      meta: meta,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.wire,
    'title': title,
    'input': input,
    'items': items.map((item) => item.toJson()).toList(),
    'coverUrl': coverUrl,
    'creator': creator,
    'creatorId': creatorId,
    'cursor': cursor,
    'hasMore': hasMore,
    'total': total,
    'createdAt': createdAt ?? DateTime.now().toIso8601String(),
    'meta': meta,
  };

  factory MediaCatalog.fromJson(Map<String, dynamic> json) => MediaCatalog(
    id: json['id'] as String,
    kind: CatalogKind.fromWire(json['kind'] as String?),
    title: json['title'] as String? ?? '',
    input: json['input'] as String? ?? '',
    items: ((json['items'] as List?) ?? const [])
        .map((item) => CatalogEntry.fromJson(item as Map<String, dynamic>))
        .toList(),
    coverUrl: json['coverUrl'] as String?,
    creator: json['creator'] as String?,
    creatorId: (json['creatorId'] as num?)?.toInt(),
    cursor: json['cursor'] as String?,
    hasMore: json['hasMore'] as bool? ?? false,
    total: (json['total'] as num?)?.toInt(),
    createdAt: json['createdAt'] as String?,
    meta: ((json['meta'] as Map?) ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
  );
}
