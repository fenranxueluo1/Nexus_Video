class StreamVariant {
  const StreamVariant({
    required this.url,
    this.backupUrls = const [],
    this.quality = 0,
    this.codecId = 0,
    this.codecDisplayName = 'unknown',
    this.bandwidth = 0,
    this.width = 0,
    this.height = 0,
    this.sizeBytes,
    this.frameRate,
    this.isCombined = false,
  });

  final String url;
  final List<String> backupUrls;
  final int quality;
  final int codecId;
  final String codecDisplayName;
  final int bandwidth;
  final int width;
  final int height;
  final int? sizeBytes;
  final double? frameRate;
  final bool isCombined;

  List<String> get urls => [
    url,
    ...backupUrls.where((value) => value.isNotEmpty),
  ];

  String get qualityLabel => qualityDisplayName(quality);

  Map<String, dynamic> toJson() => {
    'url': url,
    'backupUrls': backupUrls,
    'quality': quality,
    'codecId': codecId,
    'codecDisplayName': codecDisplayName,
    'bandwidth': bandwidth,
    'width': width,
    'height': height,
    'sizeBytes': sizeBytes,
    'frameRate': frameRate,
    'isCombined': isCombined,
  };

  factory StreamVariant.fromJson(Map<String, dynamic> json) => StreamVariant(
    url: json['url'] as String,
    backupUrls: ((json['backupUrls'] as List?) ?? const []).cast<String>(),
    quality: (json['quality'] as num?)?.toInt() ?? 0,
    codecId: (json['codecId'] as num?)?.toInt() ?? 0,
    codecDisplayName: json['codecDisplayName'] as String? ?? 'unknown',
    bandwidth: (json['bandwidth'] as num?)?.toInt() ?? 0,
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
    frameRate: (json['frameRate'] as num?)?.toDouble(),
    isCombined: json['isCombined'] as bool? ?? false,
  );
}

class CaptionSource {
  const CaptionSource({
    required this.language,
    required this.languageLabel,
    required this.url,
    this.isAiGenerated = false,
  });

  final String language;
  final String languageLabel;
  final String url;
  final bool isAiGenerated;

  Map<String, dynamic> toJson() => {
    'language': language,
    'languageLabel': languageLabel,
    'url': url,
    'isAiGenerated': isAiGenerated,
  };

  factory CaptionSource.fromJson(Map<String, dynamic> json) => CaptionSource(
    language: json['language'] as String? ?? 'zh-CN',
    languageLabel: json['languageLabel'] as String? ?? '中文',
    url: json['url'] as String? ?? '',
    isAiGenerated: json['isAiGenerated'] as bool? ?? false,
  );
}

class StreamManifest {
  const StreamManifest({
    this.videoStreams = const [],
    this.audioStreams = const [],
    this.captions = const [],
    this.durationMs = 0,
    this.acceptQuality = const [],
  });

  final List<StreamVariant> videoStreams;
  final List<StreamVariant> audioStreams;
  final List<CaptionSource> captions;
  final int durationMs;
  final List<int> acceptQuality;

  bool get hasVideo => videoStreams.isNotEmpty;
  bool get hasAudio => audioStreams.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'videoStreams': videoStreams.map((stream) => stream.toJson()).toList(),
    'audioStreams': audioStreams.map((stream) => stream.toJson()).toList(),
    'captions': captions.map((track) => track.toJson()).toList(),
    'durationMs': durationMs,
    'acceptQuality': acceptQuality,
  };

  factory StreamManifest.fromJson(Map<String, dynamic> json) => StreamManifest(
    videoStreams: ((json['videoStreams'] as List?) ?? const [])
        .map((stream) => StreamVariant.fromJson(stream as Map<String, dynamic>))
        .toList(),
    audioStreams: ((json['audioStreams'] as List?) ?? const [])
        .map((stream) => StreamVariant.fromJson(stream as Map<String, dynamic>))
        .toList(),
    captions: ((json['captions'] as List?) ?? const [])
        .map((track) => CaptionSource.fromJson(track as Map<String, dynamic>))
        .toList(),
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    acceptQuality: ((json['acceptQuality'] as List?) ?? const [])
        .map((value) => (value as num).toInt())
        .toList(),
  );
}

String qualityDisplayName(int quality) {
  return switch (quality) {
    6 => '240P',
    16 => '360P',
    32 => '480P',
    64 => '720P',
    74 => '720P60',
    80 => '1080P',
    112 => '1080P+',
    116 => '1080P60',
    120 => '4K',
    125 => 'HDR',
    126 => 'Dolby Vision',
    127 => '8K',
    _ => quality > 0 ? 'Q$quality' : '未知',
  };
}

String codecDisplayName(int codecId) {
  return switch (codecId) {
    7 => 'AVC',
    12 => 'HEVC',
    13 => 'AV1',
    _ => codecId > 0 ? 'C$codecId' : '未知',
  };
}
