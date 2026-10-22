import 'output_profile.dart';
import 'catalog.dart';

enum JobState {
  queued('queued'),
  preparing('preparing'),
  transferring('transferring'),
  packaging('packaging'),
  finished('finished'),
  failed('failed'),
  held('held'),
  aborted('aborted');

  const JobState(this.wire);
  final String wire;

  static JobState fromWire(String? value) => JobState.values.firstWhere(
    (state) => state.wire == value,
    orElse: () => JobState.queued,
  );

  bool get isSettled =>
      this == JobState.finished ||
      this == JobState.failed ||
      this == JobState.aborted;
  bool get isRunning =>
      this == JobState.preparing ||
      this == JobState.transferring ||
      this == JobState.packaging;
  bool get canBegin => this == JobState.queued || this == JobState.held;

  String get label => switch (this) {
    JobState.queued => '待处理',
    JobState.preparing => '准备中',
    JobState.transferring => '进行中',
    JobState.packaging => '封装中',
    JobState.finished => '已完成',
    JobState.failed => '失败',
    JobState.held => '已暂停',
    JobState.aborted => '已取消',
  };
}

enum AssetRole {
  video('video'),
  audio('audio'),
  artwork('artwork'),
  caption('caption'),
  overlay('overlay'),
  catalog('catalog');

  const AssetRole(this.wire);
  final String wire;

  static AssetRole fromWire(String? value) => AssetRole.values.firstWhere(
    (role) => role.wire == value,
    orElse: () => AssetRole.video,
  );

  String get label => switch (this) {
    AssetRole.video => '视频',
    AssetRole.audio => '音频',
    AssetRole.artwork => '封面',
    AssetRole.caption => '字幕',
    AssetRole.overlay => '弹幕',
    AssetRole.catalog => 'NFO',
  };
}

enum AssetKind {
  media('media'),
  image('image'),
  text('text');

  const AssetKind(this.wire);
  final String wire;

  static AssetKind fromWire(String? value) => AssetKind.values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => AssetKind.media,
  );
}

enum AssetState {
  queued('queued'),
  transferring('transferring'),
  ready('ready'),
  failed('failed'),
  aborted('aborted'),
  held('held');

  const AssetState(this.wire);
  final String wire;

  static AssetState fromWire(String? value) => AssetState.values.firstWhere(
    (state) => state.wire == value,
    orElse: () => AssetState.queued,
  );

  bool get isReady => this == AssetState.ready;
}

class JobAsset {
  const JobAsset({
    required this.id,
    required this.role,
    required this.urls,
    required this.destinationPath,
    required this.scratchPath,
    this.kind = AssetKind.media,
    this.headers = const {},
    this.state = AssetState.queued,
    this.receivedBytes = 0,
    this.expectedBytes,
    this.error,
    this.label,
  });

  final String id;
  final AssetRole role;
  final AssetKind kind;
  final List<String> urls;
  final Map<String, String> headers;
  final String destinationPath;
  final String scratchPath;
  final AssetState state;
  final int receivedBytes;
  final int? expectedBytes;
  final String? error;
  final String? label;

  double get progress {
    final total = expectedBytes;
    if (total == null || total <= 0) {
      return 0;
    }
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  JobAsset copyWith({
    List<String>? urls,
    AssetState? state,
    int? receivedBytes,
    int? expectedBytes,
    String? error,
    bool clearError = false,
    String? destinationPath,
    String? scratchPath,
  }) {
    return JobAsset(
      id: id,
      role: role,
      kind: kind,
      urls: urls ?? this.urls,
      headers: headers,
      destinationPath: destinationPath ?? this.destinationPath,
      scratchPath: scratchPath ?? this.scratchPath,
      state: state ?? this.state,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      expectedBytes: expectedBytes ?? this.expectedBytes,
      error: clearError ? null : (error ?? this.error),
      label: label,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.wire,
    'kind': kind.wire,
    'urls': urls,
    'headers': headers,
    'destinationPath': destinationPath,
    'scratchPath': scratchPath,
    'state': state.wire,
    'receivedBytes': receivedBytes,
    'expectedBytes': expectedBytes,
    'error': error,
    'label': label,
  };

  factory JobAsset.fromJson(Map<String, dynamic> json) => JobAsset(
    id: json['id'] as String,
    role: AssetRole.fromWire(json['role'] as String?),
    kind: AssetKind.fromWire(json['kind'] as String?),
    urls: ((json['urls'] as List?) ?? const []).cast<String>(),
    headers: ((json['headers'] as Map?) ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    destinationPath: json['destinationPath'] as String? ?? '',
    scratchPath: json['scratchPath'] as String? ?? '',
    state: AssetState.fromWire(json['state'] as String?),
    receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
    expectedBytes: (json['expectedBytes'] as num?)?.toInt(),
    error: json['error'] as String?,
    label: json['label'] as String?,
  );
}

enum JournalLevel {
  info('info'),
  warning('warning'),
  error('error');

  const JournalLevel(this.wire);
  final String wire;

  static JournalLevel fromWire(String? value) => JournalLevel.values.firstWhere(
    (level) => level.wire == value,
    orElse: () => JournalLevel.info,
  );
}

class JournalEntry {
  const JournalEntry({
    required this.at,
    required this.level,
    required this.message,
  });

  final DateTime at;
  final JournalLevel level;
  final String message;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'level': level.wire,
    'message': message,
  };

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    level: JournalLevel.fromWire(json['level'] as String?),
    message: json['message'] as String? ?? '',
  );
}

class OutputRecipe {
  const OutputRecipe({
    required this.profileId,
    required this.quality,
    required this.codec,
    required this.container,
    required this.includeVideo,
    required this.includeAudio,
    required this.includeArtwork,
    required this.includeCaptions,
    required this.embedArtwork,
    required this.embedCaptions,
    required this.overlayFormats,
    required this.includeCatalog,
    required this.keepSourceStreams,
  });

  final String profileId;
  final String quality;
  final String codec;
  final OutputContainer container;
  final bool includeVideo;
  final bool includeAudio;
  final bool includeArtwork;
  final bool includeCaptions;
  final bool embedArtwork;
  final bool embedCaptions;
  final List<OverlayFormat> overlayFormats;
  final bool includeCatalog;
  final bool keepSourceStreams;

  factory OutputRecipe.fromPreset(
    OutputProfile profile, {
    String? quality,
    String? codec,
    OutputContainer? container,
  }) {
    return OutputRecipe(
      profileId: profile.id,
      quality: quality ?? profile.quality,
      codec: codec ?? profile.codec,
      container: container ?? profile.container,
      includeVideo: profile.includeVideo,
      includeAudio: profile.includeAudio,
      includeArtwork: profile.includeArtwork,
      includeCaptions: profile.includeCaptions,
      embedArtwork: profile.embedArtwork,
      embedCaptions: profile.embedCaptions,
      overlayFormats: profile.overlayFormatSet.toList(),
      includeCatalog: profile.includeCatalog,
      keepSourceStreams: profile.keepSourceStreams,
    );
  }

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'quality': quality,
    'codec': codec,
    'container': container.extension,
    'includeVideo': includeVideo,
    'includeAudio': includeAudio,
    'includeArtwork': includeArtwork,
    'includeCaptions': includeCaptions,
    'embedArtwork': embedArtwork,
    'embedCaptions': embedCaptions,
    'overlayFormats': overlayFormats.map((format) => format.extension).toList(),
    'includeCatalog': includeCatalog,
    'keepSourceStreams': keepSourceStreams,
  };

  factory OutputRecipe.fromJson(Map<String, dynamic> json) => OutputRecipe(
    profileId: json['profileId'] as String? ?? 'standard',
    quality: json['quality'] as String? ?? 'best',
    codec: json['codec'] as String? ?? 'auto',
    container: OutputContainer.fromWire(json['container'] as String?),
    includeVideo: json['includeVideo'] as bool? ?? true,
    includeAudio: json['includeAudio'] as bool? ?? true,
    includeArtwork: json['includeArtwork'] as bool? ?? false,
    includeCaptions: json['includeCaptions'] as bool? ?? false,
    embedArtwork: json['embedArtwork'] as bool? ?? false,
    embedCaptions: json['embedCaptions'] as bool? ?? false,
    overlayFormats: ((json['overlayFormats'] as List?) ?? const [])
        .map((value) => OverlayFormat.fromWire(value as String?))
        .toList(),
    includeCatalog: json['includeCatalog'] as bool? ?? false,
    keepSourceStreams: json['keepSourceStreams'] as bool? ?? false,
  );
}

class TransferJob {
  const TransferJob({
    required this.id,
    required this.title,
    required this.catalogId,
    required this.catalogKind,
    required this.state,
    required this.track,
    required this.recipe,
    required this.destination,
    this.scratchDirectory = '',
    this.plot = '',
    this.assets = const [],
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.scheduledAt,
    this.rateLimitBytesPerSecond,
    this.error,
    this.journal = const [],
    this.deliveredBytes,
    this.attemptCount = 0,
  });

  final String id;
  final String title;
  final String catalogId;
  final CatalogKind catalogKind;
  final JobState state;
  final CatalogTrack track;
  final OutputRecipe recipe;
  final String destination;
  final String scratchDirectory;
  final String plot;
  final List<JobAsset> assets;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final DateTime? scheduledAt;
  final int? rateLimitBytesPerSecond;
  final String? error;
  final List<JournalEntry> journal;
  final int? deliveredBytes;
  final int attemptCount;

  String get duplicateKey => '${track.id}|${recipe.quality}|${recipe.codec}';

  double get progress {
    final mediaResources = assets
        .where(
          (asset) =>
              asset.role == AssetRole.video || asset.role == AssetRole.audio,
        )
        .toList();
    if (mediaResources.isEmpty) {
      return state == JobState.finished ? 1.0 : 0.0;
    }
    var downloaded = 0.0;
    var total = 0.0;
    for (final asset in mediaResources) {
      final resourceTotal = asset.expectedBytes;
      if (resourceTotal != null && resourceTotal > 0) {
        total += resourceTotal;
        downloaded += asset.receivedBytes.clamp(0, resourceTotal).toDouble();
      }
    }
    if (total <= 0) {
      return state == JobState.finished ? 1.0 : 0.0;
    }
    return (downloaded / total).clamp(0.0, 1.0);
  }

  int get receivedBytes =>
      assets.fold(0, (sum, asset) => sum + asset.receivedBytes);
  int get expectedBytes =>
      assets.fold(0, (sum, asset) => sum + (asset.expectedBytes ?? 0));

  TransferJob copyWith({
    String? title,
    JobState? state,
    CatalogTrack? track,
    OutputRecipe? recipe,
    String? destination,
    String? scratchDirectory,
    String? plot,
    List<JobAsset>? assets,
    DateTime? updatedAt,
    DateTime? completedAt,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    int? rateLimitBytesPerSecond,
    bool clearSpeedLimit = false,
    String? error,
    bool clearError = false,
    List<JournalEntry>? journal,
    int? deliveredBytes,
    int? attemptCount,
  }) {
    return TransferJob(
      id: id,
      title: title ?? this.title,
      catalogId: catalogId,
      catalogKind: catalogKind,
      state: state ?? this.state,
      track: track ?? this.track,
      recipe: recipe ?? this.recipe,
      destination: destination ?? this.destination,
      scratchDirectory: scratchDirectory ?? this.scratchDirectory,
      plot: plot ?? this.plot,
      assets: assets ?? this.assets,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      scheduledAt: clearScheduledAt ? null : (scheduledAt ?? this.scheduledAt),
      rateLimitBytesPerSecond: clearSpeedLimit
          ? null
          : (rateLimitBytesPerSecond ?? this.rateLimitBytesPerSecond),
      error: clearError ? null : (error ?? this.error),
      journal: journal ?? this.journal,
      deliveredBytes: deliveredBytes ?? this.deliveredBytes,
      attemptCount: attemptCount ?? this.attemptCount,
    );
  }

  Map<String, dynamic> toJson({bool includeLogs = false}) => {
    'id': id,
    'title': title,
    'catalogId': catalogId,
    'catalogKind': catalogKind.wire,
    'state': state.wire,
    'track': track.toJson(),
    'recipe': recipe.toJson(),
    'destination': destination,
    'scratchDirectory': scratchDirectory,
    'plot': plot,
    'assets': assets.map((asset) => asset.toJson()).toList(),
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'scheduledAt': scheduledAt?.toIso8601String(),
    'rateLimitBytesPerSecond': rateLimitBytesPerSecond,
    'error': error,
    'deliveredBytes': deliveredBytes,
    'attemptCount': attemptCount,
    if (includeLogs) 'journal': journal.map((log) => log.toJson()).toList(),
  };

  factory TransferJob.fromJson(Map<String, dynamic> json) => TransferJob(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    catalogId: json['catalogId'] as String? ?? '',
    catalogKind: CatalogKind.fromWire(json['catalogKind'] as String?),
    state: JobState.fromWire(json['state'] as String?),
    track: CatalogTrack.fromJson(json['track'] as Map<String, dynamic>),
    recipe: OutputRecipe.fromJson(json['recipe'] as Map<String, dynamic>),
    destination: json['destination'] as String? ?? '',
    scratchDirectory: json['scratchDirectory'] as String? ?? '',
    plot: json['plot'] as String? ?? '',
    assets: ((json['assets'] as List?) ?? const [])
        .map((asset) => JobAsset.fromJson(asset as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
    scheduledAt: DateTime.tryParse(json['scheduledAt'] as String? ?? ''),
    rateLimitBytesPerSecond: (json['rateLimitBytesPerSecond'] as num?)?.toInt(),
    error: json['error'] as String?,
    journal: ((json['journal'] as List?) ?? const [])
        .map((log) => JournalEntry.fromJson(log as Map<String, dynamic>))
        .toList(),
    deliveredBytes: (json['deliveredBytes'] as num?)?.toInt(),
    attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
  );
}

class CompletionRecord {
  const CompletionRecord({
    required this.jobId,
    required this.title,
    required this.catalogId,
    required this.destination,
    required this.quality,
    required this.codec,
    required this.container,
    required this.completedAt,
    this.errorSummary,
  });

  final String jobId;
  final String title;
  final String catalogId;
  final String destination;
  final String quality;
  final String codec;
  final String container;
  final DateTime completedAt;
  final String? errorSummary;

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'title': title,
    'catalogId': catalogId,
    'destination': destination,
    'quality': quality,
    'codec': codec,
    'container': container,
    'completedAt': completedAt.toIso8601String(),
    'errorSummary': errorSummary,
  };

  factory CompletionRecord.fromJson(Map<String, dynamic> json) =>
      CompletionRecord(
        jobId: json['jobId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        catalogId: json['catalogId'] as String? ?? '',
        destination: json['destination'] as String? ?? '',
        quality: json['quality'] as String? ?? 'unknown',
        codec: json['codec'] as String? ?? 'unknown',
        container: json['container'] as String? ?? 'mp4',
        completedAt:
            DateTime.tryParse(json['completedAt'] as String? ?? '') ??
            DateTime.now(),
        errorSummary: json['errorSummary'] as String?,
      );
}
