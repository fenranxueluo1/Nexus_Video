import 'dart:async';
import 'dart:convert';

import '../domain/streams.dart';
import 'bili_transport.dart';
import 'request_signer.dart';
import 'service_exception.dart';

class AccountSnapshot {
  const AccountSnapshot({
    required this.isLogin,
    this.mid = 0,
    this.name = '',
    this.avatar = '',
    this.vipLabel = '',
    this.level = 0,
  });

  final bool isLogin;
  final int mid;
  final String name;
  final String avatar;
  final String vipLabel;
  final int level;

  static const empty = AccountSnapshot(isLogin: false);

  Map<String, dynamic> toJson() => {
    'isLogin': isLogin,
    'mid': mid,
    'name': name,
    'avatar': avatar,
    'vipLabel': vipLabel,
    'level': level,
  };

  factory AccountSnapshot.fromJson(Map<String, dynamic> json) =>
      AccountSnapshot(
        isLogin: json['isLogin'] as bool? ?? false,
        mid: (json['mid'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '',
        vipLabel: json['vipLabel'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? 0,
      );
}

class VideoPage {
  const VideoPage({
    required this.cid,
    required this.page,
    required this.track,
    this.durationMs = 0,
  });

  final int cid;
  final int page;
  final String track;
  final int durationMs;
}

class VideoDetail {
  const VideoDetail({
    required this.bvid,
    required this.aid,
    required this.title,
    required this.cover,
    required this.pages,
    this.description = '',
    this.creator = '',
    this.creatorId = 0,
    this.pubDate,
    this.durationMs = 0,
  });

  final String bvid;
  final int aid;
  final String title;
  final String cover;
  final String description;
  final String creator;
  final int creatorId;
  final DateTime? pubDate;
  final int durationMs;
  final List<VideoPage> pages;
}

class EpisodeInfo {
  const EpisodeInfo({
    required this.epId,
    required this.seasonId,
    required this.title,
    required this.longTitle,
    required this.cover,
    required this.index,
    this.aid = 0,
    this.bvid = '',
    this.cid = 0,
    this.durationMs = 0,
    this.pubDate,
  });

  final int epId;
  final int seasonId;
  final String title;
  final String longTitle;
  final String cover;
  final int index;
  final int aid;
  final String bvid;
  final int cid;
  final int durationMs;
  final DateTime? pubDate;
}

class SeasonDetail {
  const SeasonDetail({
    required this.seasonId,
    required this.title,
    required this.cover,
    required this.episodes,
    this.description = '',
    this.creator = '',
    this.creatorId = 0,
    this.kind = 'bangumi',
  });

  final int seasonId;
  final String title;
  final String cover;
  final String description;
  final String creator;
  final int creatorId;
  final List<EpisodeInfo> episodes;
  final String kind;
}

class VideoSummary {
  const VideoSummary({
    required this.bvid,
    required this.aid,
    required this.title,
    required this.cover,
    this.cid = 0,
    this.durationMs = 0,
    this.creator = '',
    this.creatorId = 0,
    this.pubDate,
    this.summary = '',
  });

  final String bvid;
  final int aid;
  final int cid;
  final String title;
  final String cover;
  final int durationMs;
  final String creator;
  final int creatorId;
  final DateTime? pubDate;
  final String summary;
}

class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.hasMore,
    this.total = 0,
  });

  final List<T> items;
  final bool hasMore;
  final int total;
}

class FavoriteFolder {
  const FavoriteFolder({
    required this.id,
    required this.title,
    required this.mediaCount,
    this.cover = '',
    this.creator = '',
    this.creatorId = 0,
  });

  final int id;
  final String title;
  final int mediaCount;
  final String cover;
  final String creator;
  final int creatorId;
}

class SpaceCollection {
  const SpaceCollection({
    required this.id,
    required this.kind,
    required this.title,
    required this.count,
    this.cover = '',
    this.description = '',
  });

  final int id;
  final String kind;
  final String title;
  final int count;
  final String cover;
  final String description;
}

class CaptionInfo {
  const CaptionInfo({
    required this.language,
    required this.label,
    required this.url,
    this.isAi = false,
  });

  final String language;
  final String label;
  final String url;
  final bool isAi;
}

class QrLoginTicket {
  const QrLoginTicket({required this.url, required this.key});

  final String url;
  final String key;
}

class QrPollResult {
  const QrPollResult({required this.code, required this.message, this.cookie});

  final int code;
  final String message;
  final String? cookie;

  bool get isSuccess => code == 0;
  bool get isExpired => code == 86038;
  bool get isScanned => code == 86090;
}

class BiliGateway {
  BiliGateway({String cookie = '', String proxy = ''})
    : http = BiliTransport(cookie: cookie, proxy: proxy);

  final BiliTransport http;
  SigningKeys? _keys;
  Map<String, dynamic>? _nav;
  AccountSnapshot _account = AccountSnapshot.empty;
  String _anonymousCookie = '';

  AccountSnapshot get account => _account;
  String get cookie => http.cookie;

  set cookie(String value) {
    http.cookie = value;
    _anonymousCookie = '';
    _keys = null;
    _nav = null;
    _account = AccountSnapshot.empty;
  }

  set proxy(String value) => http.proxy = value;

  void close() => http.close();

  Uri _query(String base, Map<String, Object?> params) {
    final query = <String, String>{};
    params.forEach((key, value) {
      if (value != null) {
        query[key] = '$value';
      }
    });
    return Uri.parse(base).replace(queryParameters: query);
  }

  Future<AccountSnapshot> fetchAccount({bool force = false}) async {
    if (!force && _nav != null) {
      return _account;
    }
    final data = _map(
      await http.getJson(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
      ),
    );
    _nav = data;
    final wbi = _map(data['wbi_img']);
    final imgKey = fileNameFromUrl(_string(wbi['img_url']));
    final subKey = fileNameFromUrl(_string(wbi['sub_url']));
    if (imgKey.isNotEmpty && subKey.isNotEmpty) {
      _keys = SigningKeys(
        imgKey: imgKey,
        subKey: subKey,
        fetchedAt: DateTime.now(),
      );
    }
    final isLogin = data['isLogin'] == true;
    _account = AccountSnapshot(
      isLogin: isLogin,
      mid: _int(data['mid']),
      name: _string(data['uname']),
      avatar: _string(data['face']),
      vipLabel: _string(data['vip_label']),
      level: _int(_map(data['level_info'])['current_level']),
    );
    return _account;
  }

  Future<SigningKeys> _ensureKeys({bool force = false}) async {
    if (!force && _keys != null && _keys!.isFresh) {
      return _keys!;
    }
    await fetchAccount(force: true);
    final keys = _keys;
    if (keys == null) {
      throw const ApiException('无法获取 Bilibili 签名密钥，请检查网络后重试。');
    }
    return keys;
  }

  Future<void> _ensureAnonymousCookie() async {
    if (http.cookie.trim().isNotEmpty || _anonymousCookie.isNotEmpty) {
      return;
    }
    try {
      final data = _map(
        await http.getJson(
          Uri.parse('https://api.bilibili.com/x/frontend/finger/spi'),
          withCookie: false,
        ),
      );
      final b3 = _string(data['b_3']);
      final b4 = _string(data['b_4']);
      if (b3.isEmpty) {
        return;
      }
      _anonymousCookie =
          'buvid3=$b3; buvid4=${Uri.encodeQueryComponent(b4)}; b_nut=${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
      http.cookie = _anonymousCookie;
    } on Object {
      // Fingerprint cookies are an enhancement; continue without them.
    }
  }

  Future<dynamic> _signedJson(String base, Map<String, Object?> params) async {
    Future<dynamic> attempt(bool forceKeys) async {
      final keys = await _ensureKeys(force: forceKeys);
      final signed = RequestSigner.sign(params, keys.mixinKey);
      final uri = Uri.parse('$base?${RequestSigner.queryString(signed)}');
      return http.getJson(
        uri,
        headers: {'Referer': 'https://www.bilibili.com/'},
      );
    }

    try {
      return await attempt(false);
    } on BiliServiceException catch (error) {
      if (error.code == -403 || error.code == -352 || error.code == -412) {
        return attempt(true);
      }
      rethrow;
    } on ApiException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 412) {
        return attempt(true);
      }
      rethrow;
    }
  }

  Future<VideoDetail> videoDetail({String? bvid, int? aid}) async {
    final data = _map(
      await http.getJson(
        _query('https://api.bilibili.com/x/web-interface/view', {
          'bvid': bvid,
          'aid': aid,
        }),
      ),
    );
    final pages = _list(data['pages']).map((entry) {
      final page = _map(entry);
      return VideoPage(
        cid: _int(page['cid']),
        page: _int(page['page']),
        track: _string(page['part']),
        durationMs: _durationMs(page['duration'], assumeMs: false),
      );
    }).toList();
    final owner = _map(data['owner']);
    return VideoDetail(
      bvid: _string(data['bvid']),
      aid: _int(data['aid']),
      title: _string(data['title']),
      cover: _normalizeUrl(_string(data['pic'])),
      description: _string(data['desc']),
      creator: _string(owner['name']),
      creatorId: _int(owner['mid']),
      pubDate: _dateFromSeconds(data['pubdate']),
      durationMs: _durationMs(data['duration'], assumeMs: false),
      pages: pages,
    );
  }

  Future<StreamManifest> playUrl({
    required String bvid,
    required int cid,
    int qn = 127,
  }) async {
    await _ensureAnonymousCookie();
    final params = <String, Object?>{
      'bvid': bvid,
      'cid': cid,
      'qn': qn,
      'fnval': 4048,
      'fnver': 0,
      'fourk': 1,
      'platform': 'pc',
    };
    const base = 'https://api.bilibili.com/x/player/playurl';
    StreamManifest? info;
    try {
      info = parseStreamManifest(
        await _signedJson(
          'https://api.bilibili.com/x/player/wbi/playurl',
          params,
        ),
      );
    } on BiliServiceException catch (error) {
      if (error.code != -101) {
        rethrow;
      }
    }
    if (info == null) {
      try {
        info = parseStreamManifest(await http.getJson(_query(base, params)));
      } on BiliServiceException catch (error) {
        if (error.code != -101) {
          rethrow;
        }
      }
    }
    if (info == null ||
        (info.videoStreams.isNotEmpty && info.audioStreams.isEmpty) ||
        (info.videoStreams.isEmpty && info.audioStreams.isEmpty)) {
      info = await _durlFallback(base, params, info) ?? info;
    }
    if (info == null) {
      throw const BiliServiceException(
        '该视频需要登录后才能获取播放地址，请先登录或提供 Cookie。',
        code: -101,
      );
    }
    return info;
  }

  Future<StreamManifest?> _durlFallback(
    String base,
    Map<String, Object?> params,
    StreamManifest? current,
  ) async {
    try {
      final data = await http.getJson(_query(base, {...params, 'fnval': 0}));
      final fallback = parseStreamManifest(data);
      final muxed =
          fallback.videoStreams.where((stream) => stream.isCombined).toList()
            ..sort((left, right) => right.bandwidth.compareTo(left.bandwidth));
      if (muxed.isNotEmpty) {
        return StreamManifest(
          videoStreams: [muxed.first],
          durationMs: fallback.durationMs,
          acceptQuality: fallback.acceptQuality,
        );
      }
      if (current == null &&
          (fallback.videoStreams.isNotEmpty ||
              fallback.audioStreams.isNotEmpty)) {
        return fallback;
      }
    } on Object {
      // The legacy durl endpoint is best-effort.
    }
    return null;
  }

  Future<StreamManifest> bangumiPlayUrl({
    required int epId,
    required int cid,
    int qn = 127,
  }) async {
    await _ensureAnonymousCookie();
    final params = <String, Object?>{
      'ep_id': epId,
      'cid': cid,
      'qn': qn,
      'fnval': 4048,
      'fnver': 0,
      'fourk': 1,
      'platform': 'pc',
    };
    const base = 'https://api.bilibili.com/pgc/player/web/playurl';
    try {
      var info = parseStreamManifest(await http.getJson(_query(base, params)));
      if (info.videoStreams.isNotEmpty && info.audioStreams.isEmpty) {
        info = await _durlFallback(base, params, info) ?? info;
      }
      return info;
    } on BiliServiceException catch (error) {
      if (error.code == -101) {
        throw const BiliServiceException(
          '该番剧需要登录后才能获取播放地址，请先登录或提供 Cookie。',
          code: -101,
        );
      }
      rethrow;
    }
  }

  Future<StreamManifest> cheesePlayUrl({
    required int epId,
    required int cid,
    int qn = 127,
  }) async {
    await _ensureAnonymousCookie();
    final params = <String, Object?>{
      'ep_id': epId,
      'cid': cid,
      'qn': qn,
      'fnval': 4048,
      'fnver': 0,
      'fourk': 1,
      'platform': 'pc',
    };
    const base = 'https://api.bilibili.com/pugv/player/web/playurl';
    try {
      var info = parseStreamManifest(await http.getJson(_query(base, params)));
      if (info.videoStreams.isNotEmpty && info.audioStreams.isEmpty) {
        info = await _durlFallback(base, params, info) ?? info;
      }
      return info;
    } on BiliServiceException catch (error) {
      if (error.code == -101) {
        throw const BiliServiceException(
          '该课程需要登录后才能获取播放地址，请先登录或提供 Cookie。',
          code: -101,
        );
      }
      rethrow;
    }
  }

  StreamManifest parseStreamManifest(dynamic raw) {
    final rawMap = _map(raw);
    final nested = rawMap['result'];
    final root = nested is Map ? _map(nested) : rawMap;
    final dash = _map(root['dash']);
    var videos = _list(dash['video'])
        .map((entry) => _videoStream(_map(entry)))
        .whereType<StreamVariant>()
        .toList();
    final audios = _list(dash['audio'])
        .map((entry) => _audioStream(_map(entry)))
        .whereType<StreamVariant>()
        .toList();
    if (videos.isEmpty) {
      final durl = _list(root['durl']);
      if (durl.isNotEmpty) {
        final first = _map(durl.first);
        final url = _normalizeUrl(_string(first['url']));
        if (url.isNotEmpty) {
          videos = [
            StreamVariant(
              url: url,
              backupUrls: _list(
                first['backup_url'],
              ).map((value) => _normalizeUrl('$value')).toList(),
              quality: _int(root['quality']),
              codecDisplayName: 'MP4',
              bandwidth: _int(first['size']),
              sizeBytes: _int(first['size']) == 0 ? null : _int(first['size']),
              isCombined: true,
            ),
          ];
        }
      }
    }
    videos.sort((left, right) => right.bandwidth.compareTo(left.bandwidth));
    audios.sort((left, right) => right.bandwidth.compareTo(left.bandwidth));
    final accept = _list(
      root['accept_quality'],
    ).map((value) => _int(value)).toList();
    return StreamManifest(
      videoStreams: videos,
      audioStreams: audios,
      durationMs: _durationMs(dash['duration'], assumeMs: false),
      acceptQuality: accept,
    );
  }

  StreamVariant? _videoStream(Map<String, dynamic> data) {
    final url = _normalizeUrl(_string(data['baseUrl'] ?? data['base_url']));
    if (url.isEmpty) {
      return null;
    }
    final backups =
        (_list(data['backupUrl']).isEmpty
                ? _list(data['backup_url'])
                : _list(data['backupUrl']))
            .map((value) => _normalizeUrl('$value'))
            .where((value) => value.isNotEmpty)
            .toList();
    final codecId = _int(data['codecid']);
    return StreamVariant(
      url: url,
      backupUrls: backups,
      quality: _int(data['id']),
      codecId: codecId,
      codecDisplayName: codecDisplayName(codecId),
      bandwidth: _int(data['bandwidth']),
      width: _int(data['width']),
      height: _int(data['height']),
      sizeBytes: _int(data['size']) == 0 ? null : _int(data['size']),
      frameRate: _string(data['frameRate']).isEmpty
          ? null
          : double.tryParse(_string(data['frameRate'])),
    );
  }

  StreamVariant? _audioStream(Map<String, dynamic> data) {
    final url = _normalizeUrl(_string(data['baseUrl'] ?? data['base_url']));
    if (url.isEmpty) {
      return null;
    }
    final backups =
        (_list(data['backupUrl']).isEmpty
                ? _list(data['backup_url'])
                : _list(data['backupUrl']))
            .map((value) => _normalizeUrl('$value'))
            .where((value) => value.isNotEmpty)
            .toList();
    return StreamVariant(
      url: url,
      backupUrls: backups,
      quality: _int(data['id']),
      bandwidth: _int(data['bandwidth']),
      sizeBytes: _int(data['size']) == 0 ? null : _int(data['size']),
    );
  }

  Future<List<CaptionInfo>> captionTracks({
    required String bvid,
    required int cid,
    int? aid,
  }) async {
    await _ensureAnonymousCookie();
    final data = _map(
      await http.getJson(
        _query('https://api.bilibili.com/x/player/v2', {
          'bvid': bvid,
          'cid': cid,
          'aid': aid,
        }),
      ),
    );
    final captionBlock = _map(data['subtitle']);
    return _list(captionBlock['subtitles'])
        .map((entry) {
          final track = _map(entry);
          var url = _string(track['subtitle_url']);
          if (url.startsWith('//')) {
            url = 'https:$url';
          }
          return CaptionInfo(
            language: _string(track['lan']).isEmpty
                ? 'zh-CN'
                : _string(track['lan']),
            label: _string(track['lan_doc']).isEmpty
                ? '字幕'
                : _string(track['lan_doc']),
            url: url,
            isAi:
                _int(track['ai_status']) == 2 ||
                _string(track['ai_type']) == '1',
          );
        })
        .where((track) => track.url.isNotEmpty)
        .toList();
  }

  Future<SeasonDetail> bangumiSeason({int? epId, int? seasonId}) async {
    final data = _map(
      await http.getJson(
        _query('https://api.bilibili.com/pgc/view/web/season', {
          'ep_id': epId,
          'season_id': seasonId,
        }),
      ),
    );
    final episodes = _list(data['episodes']).asMap().entries.map((entry) {
      final episode = _map(entry.value);
      return _episode(episode, entry.key + 1, _int(data['season_id']));
    }).toList();
    return SeasonDetail(
      seasonId: _int(data['season_id']) == 0
          ? (seasonId ?? 0)
          : _int(data['season_id']),
      title: _string(data['title']).isEmpty
          ? _string(data['season_title'])
          : _string(data['title']),
      cover: _normalizeUrl(_string(data['cover'])),
      description: _string(data['evaluate']).isEmpty
          ? _string(data['subtitle'])
          : _string(data['evaluate']),
      episodes: episodes,
      kind: 'bangumi',
    );
  }

  Future<SeasonDetail> cheeseSeason({int? seasonId, int? epId}) async {
    final data = _map(
      await http.getJson(
        _query('https://api.bilibili.com/pugv/view/web/season', {
          'season_id': seasonId,
          'ep_id': epId,
        }),
      ),
    );
    final resolvedSeasonId = _int(data['season_id']) == 0
        ? (seasonId ?? 0)
        : _int(data['season_id']);
    final episodes = _list(data['episodes']).asMap().entries.map((entry) {
      final episode = _map(entry.value);
      return EpisodeInfo(
        epId: _int(episode['id']),
        seasonId: _int(episode['season_id']) == 0
            ? resolvedSeasonId
            : _int(episode['season_id']),
        aid: _int(episode['aid']),
        bvid: _string(episode['bvid']),
        cid: _int(episode['cid']),
        title: _string(episode['title']),
        longTitle: _string(episode['title']),
        cover: _normalizeUrl(_string(episode['cover'])),
        index: _int(episode['index']) == 0
            ? entry.key + 1
            : _int(episode['index']),
        durationMs: _durationMs(episode['duration'], assumeMs: true),
        pubDate: _parseDate(episode['release_date']),
      );
    }).toList();
    return SeasonDetail(
      seasonId: resolvedSeasonId,
      title: _string(data['title']),
      cover: _normalizeUrl(_string(data['cover'])),
      description: _string(data['subtitle']).isEmpty
          ? _string(data['evaluate'])
          : _string(data['subtitle']),
      episodes: episodes,
      kind: 'cheese',
    );
  }

  EpisodeInfo _episode(
    Map<String, dynamic> data,
    int fallbackIndex,
    int fallbackSeason,
  ) {
    final title = _string(data['long_title']).isEmpty
        ? _string(data['title'])
        : _string(data['long_title']);
    return EpisodeInfo(
      epId: _int(data['id']),
      seasonId: _int(data['season_id']) == 0
          ? fallbackSeason
          : _int(data['season_id']),
      aid: _int(data['aid']),
      bvid: _string(data['bvid']),
      cid: _int(data['cid']),
      title: title,
      longTitle: title,
      cover: _normalizeUrl(_string(data['cover'])),
      index: _int(data['index']) == 0 ? fallbackIndex : _int(data['index']),
      durationMs: _durationMs(data['duration'], assumeMs: true),
      pubDate:
          _dateFromSeconds(data['pubdate']) ?? _parseDate(data['pub_time']),
    );
  }

  Future<FavoriteFolder> favoriteFolder(int mediaId) async {
    final data = _map(
      await http.getJson(
        _query('https://api.bilibili.com/x/v3/fav/folder/info', {
          'media_id': mediaId,
        }),
      ),
    );
    final upper = _map(data['upper']);
    final cover = _map(data['cover']);
    return FavoriteFolder(
      id: _int(data['id']) == 0 ? mediaId : _int(data['id']),
      title: _string(data['title']),
      mediaCount: _int(data['media_count']),
      cover: _normalizeUrl(_string(cover['url'])),
      creator: _string(upper['name']),
      creatorId: _int(upper['mid']),
    );
  }

  Future<PagedResult<VideoSummary>> favoriteItems(
    int mediaId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = _map(
      await http.getJson(
        _query('https://api.bilibili.com/x/v3/fav/asset/list', {
          'media_id': mediaId,
          'pn': page,
          'ps': pageSize,
          'platform': 'web',
          'order': 'mtime',
          'type': 0,
          'tid': 0,
        }),
      ),
    );
    final items = _list(data['medias'])
        .map((entry) {
          final media = _map(entry);
          final upper = _map(media['upper']);
          return VideoSummary(
            bvid: _string(media['bvid']),
            aid: _int(media['id']),
            title: _string(media['title']),
            cover: _normalizeUrl(_string(media['cover'])),
            durationMs: _durationMs(media['duration'], assumeMs: false),
            creator: _string(upper['name']),
            creatorId: _int(upper['mid']),
            summary: _string(media['intro']),
          );
        })
        .where((item) => item.bvid.isNotEmpty || item.aid > 0)
        .toList();
    return PagedResult(items: items, hasMore: data['has_more'] == true);
  }

  Future<List<FavoriteFolder>> ownFavoriteFolders(int mid) async {
    final data = await http.getJson(
      _query('https://api.bilibili.com/x/v3/fav/folder/created/list-all', {
        'up_mid': mid,
        'jsonp': 'jsonp',
      }),
    );
    final entries = data is List ? data : _list(_map(data)['list']);
    final folders = <FavoriteFolder>[];
    for (final entry in entries) {
      final folder = _map(entry);
      folders.add(
        FavoriteFolder(
          id: _int(folder['id']) == 0
              ? _int(folder['fid'])
              : _int(folder['id']),
          title: _string(folder['title']),
          mediaCount: _int(folder['media_count']),
          creator: _string(_map(folder['upper'])['name']),
          creatorId: _int(_map(folder['upper'])['mid']),
        ),
      );
    }
    return folders.where((folder) => folder.id > 0).toList();
  }

  Future<PagedResult<FavoriteFolder>> collectedFolders(
    int mid, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = _map(
      await http.getJson(
        _query('https://api.bilibili.com/x/v3/fav/folder/collected/list', {
          'up_mid': mid,
          'pn': page,
          'ps': pageSize,
          'platform': 'web',
        }),
      ),
    );
    final items = _list(data['list']).map((entry) {
      final folder = _map(entry);
      final upper = _map(folder['upper']);
      final cover = _map(folder['cover']);
      return FavoriteFolder(
        id: _int(folder['id']),
        title: _string(folder['title']),
        mediaCount: _int(folder['media_count']),
        cover: _normalizeUrl(_string(cover['url'])),
        creator: _string(upper['name']),
        creatorId: _int(upper['mid']),
      );
    }).toList();
    return PagedResult(items: items, hasMore: data['has_more'] == true);
  }

  Future<PagedResult<VideoSummary>> uploaderVideos(
    int mid, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final data = await _signedJson(
      'https://api.bilibili.com/x/space/wbi/arc/search',
      {
        'mid': mid,
        'pn': page,
        'ps': pageSize,
        'order': 'pubdate',
        'tid': 0,
        'keyword': '',
      },
    );
    final list = _map(_map(data)['list']);
    final items = _list(list['vlist']).map((entry) {
      final video = _map(entry);
      return VideoSummary(
        bvid: _string(video['bvid']),
        aid: _int(video['aid']),
        title: _string(video['title']),
        cover: _normalizeUrl(_string(video['pic'])),
        durationMs: _durationMs(video['duration'], assumeMs: false),
        creator: _string(video['author']),
        creatorId: _int(video['mid']),
        pubDate: _dateFromSeconds(video['created']),
        summary: _string(video['description']),
      );
    }).toList();
    final pageInfo = _map(data['page']);
    final count = _int(pageInfo['count']);
    return PagedResult(
      items: items,
      hasMore: page * pageSize < count,
      total: count,
    );
  }

  Future<List<SpaceCollection>> spaceCollections(int mid) async {
    final data = _map(
      await http.getJson(
        _query(
          'https://api.bilibili.com/x/polymer/web-space/seasons_series_list',
          {'mid': mid, 'page_num': 1, 'page_size': 20},
        ),
      ),
    );
    final lists = _map(data['items_lists']);
    final result = <SpaceCollection>[];
    for (final entry in _list(lists['seasons_list'])) {
      final meta = _map(_map(entry)['meta']);
      result.add(
        SpaceCollection(
          id: _int(meta['season_id']),
          kind: 'season',
          title: _string(meta['title']),
          count: _int(meta['total']),
          cover: _normalizeUrl(_string(meta['cover'])),
          description: _string(meta['description']),
        ),
      );
    }
    for (final entry in _list(lists['series_list'])) {
      final meta = _map(_map(entry)['meta']);
      result.add(
        SpaceCollection(
          id: _int(meta['series_id']),
          kind: 'series',
          title: _string(meta['title']),
          count: _int(meta['total']),
          cover: _normalizeUrl(_string(meta['cover'])),
          description: _string(meta['description']),
        ),
      );
    }
    return result.where((collection) => collection.id > 0).toList();
  }

  Future<PagedResult<VideoSummary>> collectionArchives({
    required int mid,
    required int id,
    required String kind,
    int page = 1,
    int pageSize = 30,
  }) async {
    final base = kind == 'season'
        ? 'https://api.bilibili.com/x/polymer/web-space/seasons_archives_list'
        : 'https://api.bilibili.com/x/polymer/web-space/series_archives_list';
    final data = _map(
      await http.getJson(
        _query(base, {
          'mid': mid,
          (kind == 'season' ? 'season_id' : 'series_id'): id,
          'page_num': page,
          'page_size': pageSize,
          'sort_reverse': false,
        }),
      ),
    );
    final entries = _list(data['archives']).isEmpty
        ? _list(data['items'])
        : _list(data['archives']);
    final items = entries.map((entry) {
      final video = _map(entry);
      return VideoSummary(
        bvid: _string(video['bvid']),
        aid: _int(video['aid']),
        title: _string(video['title']),
        cover: _normalizeUrl(_string(video['pic'])),
        durationMs: _durationMs(video['duration'], assumeMs: false),
        pubDate: _dateFromSeconds(video['pubdate']),
        summary: _string(video['description']),
      );
    }).toList();
    final pageInfo = _map(data['page']);
    final total = _int(pageInfo['total']);
    return PagedResult(
      items: items,
      hasMore: page * pageSize < total,
      total: total,
    );
  }

  Future<List<VideoSummary>> watchLater() async {
    final data = _map(
      await http.getJson(
        Uri.parse('https://api.bilibili.com/x/v2/history/toview'),
      ),
    );
    return _list(data['list']).map((entry) {
      final video = _map(entry);
      final owner = _map(video['owner']);
      return VideoSummary(
        bvid: _string(video['bvid']),
        aid: _int(video['aid']),
        cid: _int(video['cid']),
        title: _string(video['title']),
        cover: _normalizeUrl(_string(video['pic'])),
        durationMs: _durationMs(video['duration'], assumeMs: false),
        creator: _string(owner['name']),
        creatorId: _int(owner['mid']),
        pubDate: _dateFromSeconds(video['pubdate']),
      );
    }).toList();
  }

  Future<PagedResult<VideoSummary>> searchVideos(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _signedJson(
      'https://api.bilibili.com/x/web-interface/wbi/search/type',
      {
        'search_type': 'video',
        'keyword': keyword,
        'page': page,
        'page_size': pageSize,
      },
    );
    final result = _list(_map(data)['result'])
        .map((entry) {
          final video = _map(entry);
          var bvid = _string(video['bvid']);
          if (bvid.isEmpty) {
            final match = RegExp(
              r'/(BV[0-9A-Za-z]+)',
            ).firstMatch(_string(video['arcurl']));
            bvid = match?.group(1) ?? '';
          }
          return VideoSummary(
            bvid: bvid,
            aid: _int(video['aid']),
            title: _stripHtml(_string(video['title'])),
            cover: _normalizeUrl(_string(video['pic'])),
            durationMs: _durationMs(video['duration'], assumeMs: false),
            creator: _string(video['author']),
            creatorId: _int(video['mid']),
            pubDate: _dateFromSeconds(video['pubdate']),
            summary: _stripHtml(_string(video['description'])),
          );
        })
        .where((video) => video.bvid.isNotEmpty)
        .toList();
    final total = _int(_map(data)['numResults']);
    return PagedResult(
      items: result,
      hasMore: page * pageSize < total,
      total: total,
    );
  }

  Future<String> danmakuXml(int cid) async {
    final urls = [
      Uri.parse('https://api.bilibili.com/x/v1/dm/list.so?oid=$cid'),
      Uri.parse('https://comment.bilibili.com/$cid.xml'),
    ];
    Object? lastError;
    for (final uri in urls) {
      try {
        final bytes = await http.getBytes(
          uri,
          headers: {
            'Referer': 'https://www.bilibili.com/',
            'Accept-Encoding': 'identity',
          },
        );
        final text = utf8.decode(bytes, allowMalformed: true);
        if (text.contains('<d ') ||
            text.contains('<d>') ||
            text.contains('<i>')) {
          return text;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw ApiException('获取弹幕失败：${lastError ?? '响应格式异常'}');
  }

  Future<QrLoginTicket> qrGenerate() async {
    final data = _map(
      await http.getJson(
        Uri.parse(
          'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
        ),
        headers: {'Referer': 'https://passport.bilibili.com/'},
        withCookie: false,
      ),
    );
    return QrLoginTicket(
      url: _string(data['url']),
      key: _string(data['qrcode_key']),
    );
  }

  Future<QrPollResult> qrPoll(String key) async {
    final response = await http.getResponse(
      _query('https://passport.bilibili.com/x/passport-login/web/qrcode/poll', {
        'qrcode_key': key,
      }),
      headers: {'Referer': 'https://passport.bilibili.com/'},
      withCookie: false,
    );
    final decoded = jsonDecode(response.text);
    if (decoded is! Map<String, dynamic> ||
        (decoded['code'] as num?)?.toInt() != 0) {
      return const QrPollResult(code: -1, message: '二维码状态查询失败');
    }
    final data = _map(decoded['data']);
    final code = _int(data['code']);
    final message = _string(data['message']);
    if (code != 0) {
      return QrPollResult(code: code, message: message);
    }
    final cookies = <String>[];
    for (final header in response.setCookies) {
      final first = header.split(';').first.trim();
      if (first.contains('=')) {
        cookies.add(first);
      }
    }
    return QrPollResult(
      code: 0,
      message: message.isEmpty ? '登录成功' : message,
      cookie: cookies.isEmpty ? null : cookies.join('; '),
    );
  }

  Future<Uri> expandShortUrl(Uri uri) async {
    var current = uri;
    for (var attempt = 0; attempt < 6; attempt += 1) {
      final request = await http.open('GET', current, withCookie: false);
      request.followRedirects = false;
      final response = await http.response(
        request,
        timeout: const Duration(seconds: 15),
      );
      final location = response.headers.value('location');
      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null &&
          location.isNotEmpty) {
        current = current.resolve(location);
        continue;
      }
      return current;
    }
    return current;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  static List<dynamic> _list(dynamic value) => value is List ? value : const [];

  static int _int(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value') ?? 0;
  }

  static String _string(dynamic value) => value == null ? '' : '$value';

  static String _normalizeUrl(String value) {
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    if (value.startsWith('http://')) {
      final host = Uri.tryParse(value)?.host.toLowerCase() ?? '';
      if (host.endsWith('hdslb.com') ||
          host.endsWith('bilibili.com') ||
          host.endsWith('bilivideo.com')) {
        return 'https://${value.substring(7)}';
      }
    }
    return value;
  }

  static String _stripHtml(String value) =>
      value.replaceAll(RegExp(r'<[^>]*>'), '');

  static DateTime? _dateFromSeconds(dynamic value) {
    final seconds = _int(value);
    if (seconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse('$value'.replaceFirst(' ', 'T'));
  }

  static int _durationMs(dynamic value, {required bool assumeMs}) {
    if (value == null) {
      return 0;
    }
    if (value is String && value.contains(':')) {
      final tracks = value.split(':').map(int.tryParse).toList();
      if (tracks.every((track) => track != null)) {
        var seconds = 0;
        for (final track in tracks) {
          seconds = seconds * 60 + track!;
        }
        return seconds * 1000;
      }
    }
    final number = _int(value);
    if (number <= 0) {
      return 0;
    }
    if (assumeMs || number > 1000000) {
      return number;
    }
    return number * 1000;
  }
}
