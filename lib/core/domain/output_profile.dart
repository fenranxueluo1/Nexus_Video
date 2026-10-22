enum OutputContainer {
  mp4('mp4'),
  mkv('mkv'),
  m4a('m4a'),
  mp3('mp3'),
  flac('flac');

  const OutputContainer(this.extension);
  final String extension;

  static OutputContainer fromWire(String? value) =>
      OutputContainer.values.firstWhere(
        (item) => item.extension == value,
        orElse: () => OutputContainer.mp4,
      );

  String get label => switch (this) {
    OutputContainer.mp4 => 'MP4',
    OutputContainer.mkv => 'MKV',
    OutputContainer.m4a => 'M4A',
    OutputContainer.mp3 => 'MP3',
    OutputContainer.flac => 'FLAC',
  };
}

enum OverlayFormat {
  xml('xml'),
  html('html'),
  srt('srt'),
  ass('ass');

  const OverlayFormat(this.extension);
  final String extension;

  static OverlayFormat fromWire(String? value) =>
      OverlayFormat.values.firstWhere(
        (item) => item.extension == value,
        orElse: () => OverlayFormat.xml,
      );

  String get label => switch (this) {
    OverlayFormat.xml => 'XML',
    OverlayFormat.html => 'HTML',
    OverlayFormat.srt => 'SRT',
    OverlayFormat.ass => 'ASS',
  };
}

enum CatalogMode {
  none('none'),
  nfo('nfo');

  const CatalogMode(this.wire);
  final String wire;

  static CatalogMode fromWire(String? value) => CatalogMode.values.firstWhere(
    (item) => item.wire == value,
    orElse: () => CatalogMode.none,
  );
}

class OutputProfile {
  const OutputProfile({
    required this.id,
    required this.name,
    this.builtIn = false,
    this.includeVideo = true,
    this.includeAudio = true,
    this.quality = 'best',
    this.codec = 'auto',
    this.container = OutputContainer.mp4,
    this.includeArtwork = false,
    this.embedArtwork = false,
    this.includeCaptions = false,
    this.embedCaptions = false,
    this.captionLanguage = '',
    this.overlayFormats = const [],
    this.keepRawOverlay = false,
    this.includeCatalog = false,
    this.keepSourceStreams = false,
    this.catalogMode = CatalogMode.none,
    this.pathTemplate,
  });

  final String id;
  final String name;
  final bool builtIn;
  final bool includeVideo;
  final bool includeAudio;
  final String quality;
  final String codec;
  final OutputContainer container;
  final bool includeArtwork;
  final bool embedArtwork;
  final bool includeCaptions;
  final bool embedCaptions;
  final String captionLanguage;
  final List<OverlayFormat> overlayFormats;
  final bool keepRawOverlay;
  final bool includeCatalog;
  final bool keepSourceStreams;
  final CatalogMode catalogMode;
  final String? pathTemplate;

  bool get producesMedia => includeVideo || includeAudio;
  bool get producesExtras =>
      includeArtwork ||
      includeCaptions ||
      overlayFormats.isNotEmpty ||
      keepRawOverlay ||
      includeCatalog;

  Set<OverlayFormat> get overlayFormatSet {
    final formats = {...overlayFormats};
    if (keepRawOverlay) {
      formats.add(OverlayFormat.xml);
    }
    return formats;
  }

  OutputProfile copyWith({
    String? id,
    String? name,
    bool? builtIn,
    bool? includeVideo,
    bool? includeAudio,
    String? quality,
    String? codec,
    OutputContainer? container,
    bool? includeArtwork,
    bool? embedArtwork,
    bool? includeCaptions,
    bool? embedCaptions,
    String? captionLanguage,
    List<OverlayFormat>? overlayFormats,
    bool? keepRawOverlay,
    bool? includeCatalog,
    bool? keepSourceStreams,
    CatalogMode? catalogMode,
    String? pathTemplate,
  }) {
    return OutputProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      builtIn: builtIn ?? this.builtIn,
      includeVideo: includeVideo ?? this.includeVideo,
      includeAudio: includeAudio ?? this.includeAudio,
      quality: quality ?? this.quality,
      codec: codec ?? this.codec,
      container: container ?? this.container,
      includeArtwork: includeArtwork ?? this.includeArtwork,
      embedArtwork: embedArtwork ?? this.embedArtwork,
      includeCaptions: includeCaptions ?? this.includeCaptions,
      embedCaptions: embedCaptions ?? this.embedCaptions,
      captionLanguage: captionLanguage ?? this.captionLanguage,
      overlayFormats: overlayFormats ?? this.overlayFormats,
      keepRawOverlay: keepRawOverlay ?? this.keepRawOverlay,
      includeCatalog: includeCatalog ?? this.includeCatalog,
      keepSourceStreams: keepSourceStreams ?? this.keepSourceStreams,
      catalogMode: catalogMode ?? this.catalogMode,
      pathTemplate: pathTemplate ?? this.pathTemplate,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'builtIn': builtIn,
    'includeVideo': includeVideo,
    'includeAudio': includeAudio,
    'quality': quality,
    'codec': codec,
    'container': container.extension,
    'includeArtwork': includeArtwork,
    'embedArtwork': embedArtwork,
    'includeCaptions': includeCaptions,
    'embedCaptions': embedCaptions,
    'captionLanguage': captionLanguage,
    'overlayFormats': overlayFormats.map((format) => format.extension).toList(),
    'keepRawOverlay': keepRawOverlay,
    'includeCatalog': includeCatalog,
    'keepSourceStreams': keepSourceStreams,
    'catalogMode': catalogMode.wire,
    'pathTemplate': pathTemplate,
  };

  factory OutputProfile.fromJson(Map<String, dynamic> json) => OutputProfile(
    id: json['id'] as String,
    name: json['name'] as String? ?? '未命名方案',
    builtIn: json['builtIn'] as bool? ?? false,
    includeVideo: json['includeVideo'] as bool? ?? true,
    includeAudio: json['includeAudio'] as bool? ?? true,
    quality: json['quality'] as String? ?? 'best',
    codec: json['codec'] as String? ?? 'auto',
    container: OutputContainer.fromWire(json['container'] as String?),
    includeArtwork: json['includeArtwork'] as bool? ?? false,
    embedArtwork: json['embedArtwork'] as bool? ?? false,
    includeCaptions: json['includeCaptions'] as bool? ?? false,
    embedCaptions: json['embedCaptions'] as bool? ?? false,
    captionLanguage: json['captionLanguage'] as String? ?? '',
    overlayFormats: ((json['overlayFormats'] as List?) ?? const [])
        .map((value) => OverlayFormat.fromWire(value as String?))
        .toList(),
    keepRawOverlay: json['keepRawOverlay'] as bool? ?? false,
    includeCatalog: json['includeCatalog'] as bool? ?? false,
    keepSourceStreams: json['keepSourceStreams'] as bool? ?? false,
    catalogMode: CatalogMode.fromWire(json['catalogMode'] as String?),
    pathTemplate: json['pathTemplate'] as String?,
  );

  static const List<OutputProfile> builtins = [
    OutputProfile(
      id: 'standard',
      name: '标准输出',
      builtIn: true,
      includeVideo: true,
      includeAudio: true,
      container: OutputContainer.mp4,
    ),
    OutputProfile(
      id: 'archive',
      name: '完整归档',
      builtIn: true,
      includeVideo: true,
      includeAudio: true,
      container: OutputContainer.mkv,
      includeArtwork: true,
      embedArtwork: true,
      includeCaptions: true,
      embedCaptions: true,
      overlayFormats: [
        OverlayFormat.xml,
        OverlayFormat.html,
        OverlayFormat.srt,
        OverlayFormat.ass,
      ],
      includeCatalog: true,
      catalogMode: CatalogMode.nfo,
    ),
    OutputProfile(
      id: 'cinema',
      name: '视频与字幕',
      builtIn: true,
      includeVideo: true,
      includeAudio: true,
      container: OutputContainer.mkv,
      includeCaptions: true,
      embedCaptions: true,
    ),
    OutputProfile(
      id: 'audio',
      name: '音频提取',
      builtIn: true,
      includeVideo: false,
      includeAudio: true,
      container: OutputContainer.m4a,
      includeArtwork: true,
    ),
    OutputProfile(
      id: 'text',
      name: '文字资料',
      builtIn: true,
      includeVideo: false,
      includeAudio: false,
      includeCaptions: true,
      overlayFormats: [OverlayFormat.srt, OverlayFormat.ass],
      includeCatalog: true,
    ),
  ];

  static OutputProfile builtinProfile(String id) {
    return builtins.firstWhere(
      (profile) => profile.id == id,
      orElse: () => builtins.first,
    );
  }
}
