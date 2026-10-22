enum LinkKind {
  video,
  bangumi,
  cheese,
  favorite,
  uploader,
  season,
  series,
  watchLater,
  shortLink,
  tubeClip,
  tubeList,
  chirpPost,
  douyinClip,
  unknown,
}

class RecognizedLink {
  const RecognizedLink({
    required this.kind,
    this.bvid,
    this.aid,
    this.epId,
    this.seasonId,
    this.mediaId,
    this.mid,
    this.collectionId,
    this.collectionKind,
    this.url,
    this.tubeId,
    this.tubeListId,
    this.chirpId,
    this.douyinId,
  });

  final LinkKind kind;
  final String? bvid;
  final int? aid;
  final int? epId;
  final int? seasonId;
  final int? mediaId;
  final int? mid;
  final int? collectionId;
  final String? collectionKind;
  final String? url;
  final String? tubeId;
  final String? tubeListId;
  final String? chirpId;
  final String? douyinId;

  bool get isKnown => kind != LinkKind.unknown;
}

final RegExp _bvidPattern = RegExp(r'BV[0-9A-Za-z]{10}', caseSensitive: false);
final RegExp _avPattern = RegExp(r'av(\d+)', caseSensitive: false);
final RegExp _epPattern = RegExp(r'(?:ep|EP)(\d+)');
final RegExp _ssPattern = RegExp(r'(?:ss|SS)(\d+)');
final RegExp _mlPattern = RegExp(r'ml(\d+)', caseSensitive: false);

RecognizedLink recognizeLink(String raw) {
  var input = raw.trim();
  if (input.isEmpty) {
    return const RecognizedLink(kind: LinkKind.unknown);
  }
  final firstLine = input.split(RegExp(r'[\r\n]')).first.trim();
  input = firstLine;
  final embeddedUrl = RegExp(r'https?://[^\s，。]+').firstMatch(input);
  if (embeddedUrl != null && !input.toLowerCase().startsWith('http')) {
    input = embeddedUrl.group(0)!;
  }

  final pureBv = _bvidPattern.firstMatch(input);
  if (pureBv != null && input.length <= 40 && !input.contains('http')) {
    return RecognizedLink(kind: LinkKind.video, bvid: pureBv.group(0));
  }
  final pureAv = _avPattern.firstMatch(input);
  if (pureAv != null && input.toLowerCase().startsWith('av')) {
    return RecognizedLink(
      kind: LinkKind.video,
      aid: int.tryParse(pureAv.group(1)!),
    );
  }
  if (RegExp(r'^\d+$').hasMatch(input)) {
    return RecognizedLink(kind: LinkKind.video, aid: int.tryParse(input));
  }

  Uri? uri = Uri.tryParse(input);
  if (uri == null) {
    return const RecognizedLink(kind: LinkKind.unknown);
  }
  if (!uri.hasScheme) {
    uri = Uri.tryParse('https://$input');
    if (uri == null) {
      return const RecognizedLink(kind: LinkKind.unknown);
    }
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty) {
    return const RecognizedLink(kind: LinkKind.unknown);
  }
  if (_isTubeHost(host)) {
    final params = uri.queryParameters;
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    final listId = params['list'];
    if (segments.isNotEmpty &&
        segments.first == 'playlist' &&
        listId != null &&
        listId.isNotEmpty) {
      return RecognizedLink(
        kind: LinkKind.tubeList,
        tubeListId: listId,
        url: uri.toString(),
      );
    }
    final videoId = params['v'] ?? _tubePathId(host, segments);
    if (videoId != null && videoId.isNotEmpty) {
      return RecognizedLink(
        kind: LinkKind.tubeClip,
        tubeId: videoId,
        url: uri.toString(),
      );
    }
    if (listId != null && listId.isNotEmpty) {
      return RecognizedLink(
        kind: LinkKind.tubeList,
        tubeListId: listId,
        url: uri.toString(),
      );
    }
    return const RecognizedLink(kind: LinkKind.unknown);
  }
  if (_isChirpHost(host)) {
    final chirpId = _chirpPathId(uri.pathSegments);
    if (chirpId != null) {
      return RecognizedLink(
        kind: LinkKind.chirpPost,
        chirpId: chirpId,
        url: uri.toString(),
      );
    }
    return const RecognizedLink(kind: LinkKind.unknown);
  }
  if (_isDouyinHost(host)) {
    return RecognizedLink(
      kind: LinkKind.douyinClip,
      douyinId: _douyinPathId(uri),
      url: uri.toString(),
    );
  }
  if (host == 'b23.tv' ||
      host.endsWith('.b23.tv') ||
      host == 'bili2233.cn' ||
      host.endsWith('.bili2233.cn')) {
    return RecognizedLink(kind: LinkKind.shortLink, url: uri.toString());
  }
  if (!host.endsWith('bilibili.com')) {
    return const RecognizedLink(kind: LinkKind.unknown);
  }

  final params = uri.queryParameters;
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();

  final pathBv = _bvidPattern.firstMatch(uri.path);
  if (segments.length >= 2 && segments[0] == 'video' && pathBv != null) {
    return RecognizedLink(kind: LinkKind.video, bvid: pathBv.group(0));
  }
  if (segments.length >= 2 &&
      segments[0] == 'video' &&
      _avPattern.hasMatch(segments[1])) {
    return RecognizedLink(
      kind: LinkKind.video,
      aid: int.tryParse(_avPattern.firstMatch(segments[1])!.group(1)!),
    );
  }

  if (segments.isNotEmpty && segments[0] == 'bangumi') {
    final text = uri.path;
    final ep = _epPattern.firstMatch(text);
    if (ep != null) {
      return RecognizedLink(
        kind: LinkKind.bangumi,
        epId: int.tryParse(ep.group(1)!),
      );
    }
    final ss = _ssPattern.firstMatch(text);
    if (ss != null) {
      return RecognizedLink(
        kind: LinkKind.bangumi,
        seasonId: int.tryParse(ss.group(1)!),
      );
    }
    if (params['ep_id'] != null) {
      return RecognizedLink(
        kind: LinkKind.bangumi,
        epId: int.tryParse(params['ep_id']!),
      );
    }
    if (params['season_id'] != null) {
      return RecognizedLink(
        kind: LinkKind.bangumi,
        seasonId: int.tryParse(params['season_id']!),
      );
    }
  }

  if (segments.isNotEmpty && segments[0] == 'cheese') {
    final text = uri.path;
    final ep = _epPattern.firstMatch(text);
    if (ep != null) {
      return RecognizedLink(
        kind: LinkKind.cheese,
        epId: int.tryParse(ep.group(1)!),
      );
    }
    final ss = _ssPattern.firstMatch(text);
    if (ss != null) {
      return RecognizedLink(
        kind: LinkKind.cheese,
        seasonId: int.tryParse(ss.group(1)!),
      );
    }
    if (params['season_id'] != null) {
      return RecognizedLink(
        kind: LinkKind.cheese,
        seasonId: int.tryParse(params['season_id']!),
      );
    }
  }

  if (segments.isNotEmpty && segments[0] == 'medialist') {
    final ml = _mlPattern.firstMatch(uri.path);
    if (ml != null) {
      return RecognizedLink(
        kind: LinkKind.favorite,
        mediaId: int.tryParse(ml.group(1)!),
      );
    }
    if (params['fid'] != null) {
      return RecognizedLink(
        kind: LinkKind.favorite,
        mediaId: int.tryParse(params['fid']!),
      );
    }
  }

  if (segments.isNotEmpty &&
      segments[0] == 'list' &&
      segments.length >= 2 &&
      segments[1] == 'watchlater') {
    return const RecognizedLink(kind: LinkKind.watchLater);
  }

  if (host.startsWith('space.')) {
    final mid = int.tryParse(segments.isNotEmpty ? segments.first : '');
    if (segments.length >= 3 && segments[1] == 'channel') {
      final detail = segments[2];
      final sid = int.tryParse(params['sid'] ?? '');
      if (detail == 'collectiondetail' && sid != null) {
        return RecognizedLink(
          kind: LinkKind.season,
          mid: mid,
          collectionId: sid,
          collectionKind: 'season',
        );
      }
      if (detail == 'seriesdetail' && sid != null) {
        return RecognizedLink(
          kind: LinkKind.series,
          mid: mid,
          collectionId: sid,
          collectionKind: 'series',
        );
      }
    }
    if (segments.length >= 3 && segments[1] == 'lists') {
      final type = params['type'] ?? '';
      final id = int.tryParse(segments[2]);
      if (id != null && (type == 'season' || type == 'series')) {
        return RecognizedLink(
          kind: type == 'season' ? LinkKind.season : LinkKind.series,
          mid: mid,
          collectionId: id,
          collectionKind: type,
        );
      }
    }
    if (params['fid'] != null) {
      return RecognizedLink(
        kind: LinkKind.favorite,
        mediaId: int.tryParse(params['fid']!),
        mid: mid,
      );
    }
    if (mid != null) {
      return RecognizedLink(kind: LinkKind.uploader, mid: mid);
    }
  }

  if (params['bvid'] != null) {
    return RecognizedLink(kind: LinkKind.video, bvid: params['bvid']);
  }
  if (params['aid'] != null) {
    return RecognizedLink(
      kind: LinkKind.video,
      aid: int.tryParse(params['aid']!),
    );
  }
  if (params['ep_id'] != null) {
    return RecognizedLink(
      kind: LinkKind.bangumi,
      epId: int.tryParse(params['ep_id']!),
    );
  }
  if (params['season_id'] != null && params['ep_id'] == null) {
    return RecognizedLink(
      kind: LinkKind.bangumi,
      seasonId: int.tryParse(params['season_id']!),
    );
  }
  if (params['media_id'] != null) {
    return RecognizedLink(
      kind: LinkKind.favorite,
      mediaId: int.tryParse(params['media_id']!),
    );
  }

  return const RecognizedLink(kind: LinkKind.unknown);
}

bool _isTubeHost(String host) {
  return host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');
}

bool _isChirpHost(String host) {
  return host == 'x.com' ||
      host.endsWith('.x.com') ||
      host == 'twitter.com' ||
      host.endsWith('.twitter.com');
}

bool _isDouyinHost(String host) {
  return host == 'douyin.com' ||
      host.endsWith('.douyin.com') ||
      host == 'iesdouyin.com' ||
      host.endsWith('.iesdouyin.com');
}

String? _douyinPathId(Uri uri) {
  final modalId = uri.queryParameters['modal_id'];
  if (modalId != null && RegExp(r'^\d+$').hasMatch(modalId)) {
    return modalId;
  }
  final match = RegExp(
    r'/(?:video|note|share/video)/(\d+)',
  ).firstMatch(uri.path);
  return match?.group(1);
}

String? _tubePathId(String host, List<String> segments) {
  if (host == 'youtu.be' && segments.isNotEmpty) {
    return segments.first;
  }
  if (segments.length >= 2 &&
      (segments.first == 'shorts' ||
          segments.first == 'live' ||
          segments.first == 'embed' ||
          segments.first == 'v')) {
    return segments[1];
  }
  return null;
}

String? _chirpPathId(List<String> segments) {
  for (var index = 0; index < segments.length - 1; index += 1) {
    if ((segments[index] == 'status' || segments[index] == 'statuses') &&
        RegExp(r'^\d+$').hasMatch(segments[index + 1])) {
      return segments[index + 1];
    }
  }
  return null;
}
