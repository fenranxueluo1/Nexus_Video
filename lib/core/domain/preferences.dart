import 'dart:convert';

import 'output_profile.dart';

enum CollisionPolicy {
  skip('skip'),
  overwrite('overwrite'),
  append('append');

  const CollisionPolicy(this.wire);
  final String wire;

  static CollisionPolicy fromWire(String? value) =>
      CollisionPolicy.values.firstWhere(
        (item) => item.wire == value,
        orElse: () => CollisionPolicy.skip,
      );

  String get label => switch (this) {
    CollisionPolicy.skip => '跳过已存在',
    CollisionPolicy.overwrite => '覆盖已存在',
    CollisionPolicy.append => '保留并追加序号',
  };
}

class Preferences {
  Preferences({
    this.schemaVersion = 1,
    this.destinationRoot = '',
    this.packagerPath = '',
    this.tubeCookiePath = '',
    this.chirpCookiePath = '',
    this.douyinCookiePath = '',
    this.parallelJobs = 3,
    this.parallelSegments = 4,
    this.retryLimit = 3,
    this.rateLimitBytesPerSecond = 0,
    this.proxy = '',
    this.qualityPreference = 'best',
    this.codecPreference = 'auto',
    this.collisionPolicy = CollisionPolicy.skip,
    this.pathTemplate = '{title}/{track_no} - {track_title}',
    this.appearance = 'system',
    this.defaultProfileId = 'standard',
    this.profiles = const [],
    this.resumeOnLaunch = true,
    this.catalogTemplate = '',
    this.keepRawOverlay = true,
    this.revealAfterSave = false,
    this.notifyWhenSettled = true,
  });

  final int schemaVersion;
  final String destinationRoot;
  final String packagerPath;
  final String tubeCookiePath;
  final String chirpCookiePath;
  final String douyinCookiePath;
  final int parallelJobs;
  final int parallelSegments;
  final int retryLimit;
  final int rateLimitBytesPerSecond;
  final String proxy;
  final String qualityPreference;
  final String codecPreference;
  final CollisionPolicy collisionPolicy;
  final String pathTemplate;
  final String appearance;
  final String defaultProfileId;
  final List<OutputProfile> profiles;
  final bool resumeOnLaunch;
  final String catalogTemplate;
  final bool keepRawOverlay;
  final bool revealAfterSave;
  final bool notifyWhenSettled;

  List<OutputProfile> get allProfiles => [
    ...OutputProfile.builtins,
    ...profiles.where((profile) => !profile.builtIn),
  ];

  OutputProfile profileById(String id) {
    for (final profile in allProfiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return OutputProfile.builtinProfile(defaultProfileId);
  }

  OutputProfile get defaultProfile => profileById(defaultProfileId);

  int get normalizedConcurrency => parallelJobs.clamp(1, 5);
  int get normalizedSegments =>
      const {1, 2, 4, 8}.contains(parallelSegments) ? parallelSegments : 4;

  Preferences copyWith({
    int? schemaVersion,
    String? destinationRoot,
    String? packagerPath,
    String? tubeCookiePath,
    String? chirpCookiePath,
    String? douyinCookiePath,
    int? parallelJobs,
    int? parallelSegments,
    int? retryLimit,
    int? rateLimitBytesPerSecond,
    String? proxy,
    String? qualityPreference,
    String? codecPreference,
    CollisionPolicy? collisionPolicy,
    String? pathTemplate,
    String? appearance,
    String? defaultProfileId,
    List<OutputProfile>? profiles,
    bool? resumeOnLaunch,
    String? catalogTemplate,
    bool? keepRawOverlay,
    bool? revealAfterSave,
    bool? notifyWhenSettled,
  }) {
    return Preferences(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      destinationRoot: destinationRoot ?? this.destinationRoot,
      packagerPath: packagerPath ?? this.packagerPath,
      tubeCookiePath: tubeCookiePath ?? this.tubeCookiePath,
      chirpCookiePath: chirpCookiePath ?? this.chirpCookiePath,
      douyinCookiePath: douyinCookiePath ?? this.douyinCookiePath,
      parallelJobs: parallelJobs ?? this.parallelJobs,
      parallelSegments: parallelSegments ?? this.parallelSegments,
      retryLimit: retryLimit ?? this.retryLimit,
      rateLimitBytesPerSecond:
          rateLimitBytesPerSecond ?? this.rateLimitBytesPerSecond,
      proxy: proxy ?? this.proxy,
      qualityPreference: qualityPreference ?? this.qualityPreference,
      codecPreference: codecPreference ?? this.codecPreference,
      collisionPolicy: collisionPolicy ?? this.collisionPolicy,
      pathTemplate: pathTemplate ?? this.pathTemplate,
      appearance: appearance ?? this.appearance,
      defaultProfileId: defaultProfileId ?? this.defaultProfileId,
      profiles: profiles ?? this.profiles,
      resumeOnLaunch: resumeOnLaunch ?? this.resumeOnLaunch,
      catalogTemplate: catalogTemplate ?? this.catalogTemplate,
      keepRawOverlay: keepRawOverlay ?? this.keepRawOverlay,
      revealAfterSave: revealAfterSave ?? this.revealAfterSave,
      notifyWhenSettled: notifyWhenSettled ?? this.notifyWhenSettled,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'destinationRoot': destinationRoot,
    'packagerPath': packagerPath,
    'tubeCookiePath': tubeCookiePath,
    'chirpCookiePath': chirpCookiePath,
    'douyinCookiePath': douyinCookiePath,
    'parallelJobs': parallelJobs,
    'parallelSegments': parallelSegments,
    'retryLimit': retryLimit,
    'rateLimitBytesPerSecond': rateLimitBytesPerSecond,
    'proxy': proxy,
    'qualityPreference': qualityPreference,
    'codecPreference': codecPreference,
    'collisionPolicy': collisionPolicy.wire,
    'pathTemplate': pathTemplate,
    'appearance': appearance,
    'defaultProfileId': defaultProfileId,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
    'resumeOnLaunch': resumeOnLaunch,
    'catalogTemplate': catalogTemplate,
    'keepRawOverlay': keepRawOverlay,
    'revealAfterSave': revealAfterSave,
    'notifyWhenSettled': notifyWhenSettled,
  };

  factory Preferences.fromJson(Map<String, dynamic> json) {
    return Preferences(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      destinationRoot: json['destinationRoot'] as String? ?? '',
      packagerPath: json['packagerPath'] as String? ?? '',
      tubeCookiePath: json['tubeCookiePath'] as String? ?? '',
      chirpCookiePath: json['chirpCookiePath'] as String? ?? '',
      douyinCookiePath: json['douyinCookiePath'] as String? ?? '',
      parallelJobs: ((json['parallelJobs'] as num?)?.toInt() ?? 3).clamp(1, 5),
      parallelSegments: (json['parallelSegments'] as num?)?.toInt() ?? 4,
      retryLimit: ((json['retryLimit'] as num?)?.toInt() ?? 3).clamp(0, 10),
      rateLimitBytesPerSecond:
          (json['rateLimitBytesPerSecond'] as num?)?.toInt() ?? 0,
      proxy: json['proxy'] as String? ?? '',
      qualityPreference: json['qualityPreference'] as String? ?? 'best',
      codecPreference: json['codecPreference'] as String? ?? 'auto',
      collisionPolicy: CollisionPolicy.fromWire(
        json['collisionPolicy'] as String?,
      ),
      pathTemplate:
          json['pathTemplate'] as String? ??
          '{title}/{track_no} - {track_title}',
      appearance: json['appearance'] as String? ?? 'system',
      defaultProfileId: json['defaultProfileId'] as String? ?? 'standard',
      profiles: ((json['profiles'] as List?) ?? const [])
          .map(
            (profile) =>
                OutputProfile.fromJson(profile as Map<String, dynamic>),
          )
          .toList(),
      resumeOnLaunch: json['resumeOnLaunch'] as bool? ?? true,
      catalogTemplate: json['catalogTemplate'] as String? ?? '',
      keepRawOverlay: json['keepRawOverlay'] as bool? ?? true,
      revealAfterSave: json['revealAfterSave'] as bool? ?? false,
      notifyWhenSettled: json['notifyWhenSettled'] as bool? ?? true,
    );
  }

  static Preferences defaults() => Preferences();
}

bool preferencesEqual(Preferences a, Preferences b) {
  return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
}
