import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/service_exception.dart';
import '../api/bili_gateway.dart';
import '../domain/streams.dart';
import '../domain/output_profile.dart';
import '../domain/preferences.dart';
import '../domain/catalog.dart';
import '../domain/jobs.dart';
import '../pathing/path_template.dart';
import '../util/identifiers.dart';

class PickedTrack {
  const PickedTrack({required this.item, required this.track});

  final CatalogEntry item;
  final CatalogTrack track;
}

class BuildOptions {
  const BuildOptions({
    required this.profile,
    required this.preferences,
    this.quality,
    this.codec,
    this.qualityOverride,
    this.codecOverride,
    this.existingDuplicateKeys = const {},
    this.reservedPaths = const {},
  });

  final OutputProfile profile;
  final Preferences preferences;
  final String? quality;
  final String? codec;
  final String? qualityOverride;
  final String? codecOverride;
  final Set<String> existingDuplicateKeys;
  final Set<String> reservedPaths;

  String get effectiveQuality => qualityOverride ?? quality ?? profile.quality;
  String get effectiveCodec => codecOverride ?? codec ?? profile.codec;
}

class BuildSkip {
  const BuildSkip({required this.title, required this.reason});

  final String title;
  final String reason;
}

class BuildFailure {
  const BuildFailure({required this.title, required this.message});

  final String title;
  final String message;
}

class BuildReport {
  const BuildReport({
    required this.jobs,
    required this.skipped,
    required this.failures,
  });

  final List<TransferJob> jobs;
  final List<BuildSkip> skipped;
  final List<BuildFailure> failures;
}

class JobComposer {
  JobComposer(this.client);

  final BiliGateway client;

  Future<BuildReport> compose({
    required CatalogKind catalogKind,
    required List<PickedTrack> tracks,
    required BuildOptions options,
    void Function(int completed, int total)? onProgress,
  }) async {
    final jobs = <TransferJob>[];
    final skipped = <BuildSkip>[];
    final failures = <BuildFailure>[];
    final duplicateKeys = {...options.existingDuplicateKeys};
    final reserved = {...options.reservedPaths};

    for (var index = 0; index < tracks.length; index += 1) {
      onProgress?.call(index, tracks.length);
      final selected = tracks[index];
      final title = _displayTitle(selected);
      try {
        final job = await _planOne(
          catalogKind: catalogKind,
          selected: selected,
          options: options,
          duplicateKeys: duplicateKeys,
          reserved: reserved,
          skipped: skipped,
        );
        if (job != null) {
          jobs.add(job);
          duplicateKeys.add(_duplicateKey(selected.track, options));
        }
      } on ApiException catch (error) {
        failures.add(BuildFailure(title: title, message: error.message));
      } on Object catch (error) {
        failures.add(BuildFailure(title: title, message: '$error'));
      }
    }
    onProgress?.call(tracks.length, tracks.length);
    return BuildReport(jobs: jobs, skipped: skipped, failures: failures);
  }

  Future<TransferJob?> _planOne({
    required CatalogKind catalogKind,
    required PickedTrack selected,
    required BuildOptions options,
    required Set<String> duplicateKeys,
    required Set<String> reserved,
    required List<BuildSkip> skipped,
  }) async {
    final profile = options.profile;
    if ((Platform.isIOS || Platform.isAndroid) && profile.producesMedia) {
      final supportedContainer =
          profile.container == OutputContainer.mp4 ||
          profile.container == OutputContainer.m4a;
      if (!supportedContainer ||
          profile.embedCaptions ||
          profile.embedArtwork) {
        throw const ApiException(
          '移动端目前只支持合并为 MP4/M4A，暂不支持 MKV、MP3、FLAC、字幕嵌入或封面嵌入。',
        );
      }
    }
    final track = selected.track;
    final item = selected.item;
    final key = _duplicateKey(track, options);
    if (duplicateKeys.contains(key)) {
      skipped.add(
        BuildSkip(title: _displayTitle(selected), reason: '已存在相同质量与编码的任务'),
      );
      return null;
    }

    final resolved = await _resolveCid(catalogKind, track);
    final playInfo = await _loadStreamManifest(catalogKind, resolved, options);
    var videoStream = profile.includeVideo
        ? _selectVideo(playInfo.videoStreams, options)
        : null;
    var audioStream = profile.includeAudio
        ? _selectAudio(playInfo.audioStreams)
        : null;
    if (audioStream == null && profile.includeAudio) {
      final muxed = playInfo.videoStreams
          .where((stream) => stream.isCombined)
          .toList();
      if (muxed.isNotEmpty) {
        final combined = _selectVideo(muxed, options) ?? muxed.first;
        if (profile.includeVideo) {
          videoStream = combined;
        } else {
          audioStream = combined;
        }
      }
    }
    final missingAudio =
        profile.includeAudio &&
        audioStream == null &&
        !(videoStream?.isCombined ?? false);

    if (profile.includeVideo && videoStream == null) {
      throw const ApiException('没有获取到可用的视频流，可能需要登录、大会员权限或稍后重试。');
    }
    if (profile.includeAudio && audioStream == null && videoStream == null) {
      throw const ApiException('没有获取到可用的音频流。');
    }
    if (videoStream == null && audioStream == null && !profile.producesExtras) {
      throw const ApiException('当前方案没有选择任何要保存的内容。');
    }

    final container = _effectiveContainer(
      profile,
      hasVideo: videoStream != null,
      hasAudio: audioStream != null,
    );
    final extension = container.extension;
    final selectedQuality = videoStream?.quality ?? audioStream?.quality ?? 0;
    final selectedCodec = videoStream?.codecDisplayName ?? 'AUDIO';
    final namingContext = PathFields(
      title: track.series?.isNotEmpty == true ? track.series! : item.title,
      trackTitle: track.title,
      trackNo: track.index,
      ext: extension,
      bvid: resolved.bvid,
      aid: resolved.aid,
      cid: resolved.cid,
      creator: track.creator ?? item.creator,
      creatorId: track.creatorId ?? item.creatorId,
      series: track.series,
      seasonNo: track.seasonNo,
      episodeNo: track.episodeNo,
      collection: track.collection,
      index: track.index,
      quality: selectedQuality == 0 ? null : '$selectedQuality',
      codec: selectedCodec,
      date: DateTime.now(),
      publishDate: track.pubDate,
    );

    final relative = composeRelativePath(
      options.preferences.pathTemplate,
      namingContext,
    );
    final absolute = limitPathLength(
      p.join(options.preferences.destinationRoot, relative),
    );
    if (!isPathInside(absolute, options.preferences.destinationRoot)) {
      throw const ApiException('生成的输出路径超出了保存位置，已停止。');
    }
    final exists = File(absolute).existsSync();
    if (options.preferences.collisionPolicy == CollisionPolicy.skip &&
        (exists || reserved.contains(absolute))) {
      skipped.add(BuildSkip(title: _displayTitle(selected), reason: '目标文件已存在'));
      return null;
    }
    final destination = resolveDuplicatePath(
      absolute,
      reserved,
      options.preferences.collisionPolicy,
      exists: exists,
    );
    reserved.add(destination);

    final jobId = makeId('job');
    final workRoot = p.join(
      options.preferences.destinationRoot,
      '.nexus-work',
      jobId,
    );
    final assets = <JobAsset>[];
    final headers = {
      'Referer': catalogKind == CatalogKind.bangumi
          ? 'https://www.bilibili.com/bangumi/'
          : catalogKind == CatalogKind.cheese
          ? 'https://www.bilibili.com/cheese/'
          : 'https://www.bilibili.com/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    };

    if (videoStream != null) {
      final targetName = videoStream.isCombined ? 'combined.mp4' : 'video.m4s';
      assets.add(
        JobAsset(
          id: '$jobId:video',
          role: AssetRole.video,
          urls: videoStream.urls,
          headers: headers,
          destinationPath: p.join(workRoot, targetName),
          scratchPath: p.join(workRoot, '$targetName.nxpart'),
          expectedBytes: videoStream.sizeBytes,
          label:
              '${videoStream.qualityLabel} ${videoStream.codecDisplayName}${videoStream.isCombined ? '（音视频合并流）' : ''}',
        ),
      );
    }
    if (audioStream != null) {
      final targetName = audioStream.isCombined ? 'combined.mp4' : 'audio.m4s';
      assets.add(
        JobAsset(
          id: '$jobId:audio',
          role: AssetRole.audio,
          urls: audioStream.urls,
          headers: headers,
          destinationPath: p.join(workRoot, targetName),
          scratchPath: p.join(workRoot, '$targetName.nxpart'),
          expectedBytes: audioStream.sizeBytes,
          label: audioStream.isCombined
              ? '${audioStream.qualityLabel} 合并流音轨'
              : '音频 ${audioStream.bandwidth ~/ 1000} kbps',
        ),
      );
    }

    final coverUrl = (track.coverUrl ?? item.coverUrl ?? '').trim();
    if ((profile.includeArtwork || profile.embedArtwork) &&
        coverUrl.isNotEmpty) {
      assets.add(
        JobAsset(
          id: '$jobId:cover',
          role: AssetRole.artwork,
          kind: AssetKind.image,
          urls: [coverUrl],
          headers: headers,
          destinationPath: p.join(workRoot, 'cover.jpg'),
          scratchPath: p.join(workRoot, 'cover.jpg.nxpart'),
          label: '封面',
        ),
      );
    }

    if (profile.includeCaptions || profile.embedCaptions) {
      try {
        final captions = await client.captionTracks(
          bvid: resolved.bvid ?? '',
          cid: resolved.cid ?? 0,
          aid: resolved.aid,
        );
        final caption = _selectCaption(captions, profile.captionLanguage);
        if (caption != null) {
          assets.add(
            JobAsset(
              id: '$jobId:caption',
              role: AssetRole.caption,
              kind: AssetKind.text,
              urls: [caption.url],
              headers: headers,
              destinationPath: p.join(workRoot, 'caption.json'),
              scratchPath: p.join(workRoot, 'caption.json.nxpart'),
              label: caption.language,
            ),
          );
        }
      } on Object {
        // Captions are auxiliary; an unavailable track must not block media.
      }
    }

    final overlayFormats = profile.overlayFormatSet;
    if (overlayFormats.isNotEmpty && resolved.cid != null) {
      assets.add(
        JobAsset(
          id: '$jobId:danmaku',
          role: AssetRole.overlay,
          kind: AssetKind.text,
          urls: [
            'https://api.bilibili.com/x/v1/dm/list.so?oid=${resolved.cid}',
            'https://comment.bilibili.com/${resolved.cid}.xml',
          ],
          headers: headers,
          destinationPath: p.join(workRoot, 'danmaku.xml'),
          scratchPath: p.join(workRoot, 'danmaku.xml.nxpart'),
          label: overlayFormats.map((format) => format.label).join('/'),
        ),
      );
    }

    final taskTitle = item.tracks.length <= 1
        ? item.title
        : '${item.title} - ${track.title}';
    return TransferJob(
      id: jobId,
      title: taskTitle,
      catalogId: item.id,
      catalogKind: catalogKind,
      state: JobState.queued,
      track: resolved,
      recipe: OutputRecipe.fromPreset(
        profile,
        quality: options.effectiveQuality,
        codec: options.effectiveCodec,
      ),
      destination: destination,
      scratchDirectory: workRoot,
      plot: item.summary ?? '',
      assets: assets,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      journal: [
        JournalEntry(
          at: DateTime.now(),
          level: missingAudio ? JournalLevel.warning : JournalLevel.info,
          message: missingAudio
              ? '该视频没有独立音频流，输出将只包含视频。'
              : '已创建任务：${namingContextExtras(namingContext)}',
        ),
      ],
    );
  }

  String namingContextExtras(PathFields context) {
    final quality = context.quality == null
        ? ''
        : ' ${qualityNameFor(context.quality!)}';
    final codec = context.codec == null ? '' : ' ${context.codec}';
    return '${context.title} / ${context.trackTitle}$quality$codec';
  }

  Future<CatalogTrack> _resolveCid(
    CatalogKind catalogKind,
    CatalogTrack track,
  ) async {
    if (track.cid != null && track.cid! > 0) {
      return track;
    }
    if ((track.bvid != null && track.bvid!.isNotEmpty) ||
        (track.aid != null && track.aid! > 0)) {
      final detail = await client.videoDetail(bvid: track.bvid, aid: track.aid);
      if (detail.pages.isEmpty) {
        throw const ApiException('无法获取视频分段 信息。');
      }
      final first = detail.pages.firstWhere(
        (page) => page.page == track.index,
        orElse: () => detail.pages.first,
      );
      return track.copyWith(cid: first.cid, bvid: detail.bvid, aid: detail.aid);
    }
    throw const ApiException('缺少 CID，无法获取播放地址。');
  }

  Future<StreamManifest> _loadStreamManifest(
    CatalogKind catalogKind,
    CatalogTrack track,
    BuildOptions options,
  ) async {
    final qn = _qnForPreference(options.effectiveQuality);
    switch (catalogKind) {
      case CatalogKind.bangumi:
        if (track.epId == null || track.cid == null) {
          throw const ApiException('缺少剧集信息，无法获取播放地址。');
        }
        return client.bangumiPlayUrl(
          epId: track.epId!,
          cid: track.cid!,
          qn: qn,
        );
      case CatalogKind.cheese:
        if (track.epId == null || track.cid == null) {
          throw const ApiException('缺少课程剧集信息，无法获取播放地址。');
        }
        return client.cheesePlayUrl(epId: track.epId!, cid: track.cid!, qn: qn);
      default:
        if (track.bvid == null || track.cid == null) {
          throw const ApiException('缺少 BV 号或 CID，无法获取播放地址。');
        }
        return client.playUrl(bvid: track.bvid!, cid: track.cid!, qn: qn);
    }
  }

  int _qnForPreference(String preference) {
    final numeric = int.tryParse(preference);
    if (numeric != null && numeric > 0) {
      return numeric.clamp(6, 127);
    }
    if (preference == 'worst') {
      return 6;
    }
    return 127;
  }

  StreamVariant? _selectVideo(
    List<StreamVariant> streams,
    BuildOptions options,
  ) {
    if (streams.isEmpty) {
      return null;
    }
    final preference = options.effectiveQuality;
    final codecPreference = options.effectiveCodec;
    final sorted = List<StreamVariant>.of(streams)
      ..sort((left, right) {
        final height = right.height.compareTo(left.height);
        if (height != 0) {
          return height;
        }
        return right.bandwidth.compareTo(left.bandwidth);
      });

    final numeric = int.tryParse(preference);
    StreamVariant? target;
    if (preference == 'worst') {
      target = sorted.last;
    } else if (numeric != null) {
      final exact = sorted
          .where((stream) => stream.quality == numeric)
          .toList();
      if (exact.isNotEmpty) {
        target = exact.first;
      } else {
        final below = sorted
            .where((stream) => stream.quality < numeric)
            .toList();
        target = below.isNotEmpty ? below.first : sorted.first;
      }
    } else {
      target = sorted.first;
    }

    final sameQuality = streams
        .where((stream) => stream.quality == target!.quality)
        .toList();
    final codecId = switch (codecPreference) {
      'avc' => 7,
      'hevc' => 12,
      'av1' => 13,
      _ => null,
    };
    if (codecId != null) {
      final match = sameQuality
          .where((stream) => stream.codecId == codecId)
          .toList();
      if (match.isNotEmpty) {
        return match.first;
      }
    }
    if (sameQuality.isNotEmpty) {
      const preferenceOrder = [7, 12, 13];
      for (final codec in preferenceOrder) {
        final match = sameQuality
            .where((stream) => stream.codecId == codec)
            .toList();
        if (match.isNotEmpty) {
          return match.first;
        }
      }
      return sameQuality.first;
    }
    return target;
  }

  StreamVariant? _selectAudio(List<StreamVariant> streams) {
    if (streams.isEmpty) {
      return null;
    }
    final sorted = List<StreamVariant>.of(streams)
      ..sort((left, right) => right.bandwidth.compareTo(left.bandwidth));
    return sorted.first;
  }

  CaptionInfo? _selectCaption(
    List<CaptionInfo> tracks,
    String preferredLanguage,
  ) {
    if (tracks.isEmpty) {
      return null;
    }
    if (preferredLanguage.trim().isNotEmpty) {
      final preferred = preferredLanguage.toLowerCase();
      for (final track in tracks) {
        if (track.language.toLowerCase() == preferred ||
            track.label.toLowerCase().contains(preferred)) {
          return track;
        }
      }
    }
    for (final track in tracks) {
      if (!track.isAi) {
        return track;
      }
    }
    return tracks.first;
  }

  OutputContainer _effectiveContainer(
    OutputProfile profile, {
    required bool hasVideo,
    required bool hasAudio,
  }) {
    if (hasVideo && hasAudio) {
      return profile.container == OutputContainer.mkv
          ? OutputContainer.mkv
          : OutputContainer.mp4;
    }
    if (hasVideo) {
      return profile.container == OutputContainer.mkv
          ? OutputContainer.mkv
          : OutputContainer.mp4;
    }
    if (hasAudio) {
      return switch (profile.container) {
        OutputContainer.mp3 => OutputContainer.mp3,
        OutputContainer.flac => OutputContainer.flac,
        _ => OutputContainer.m4a,
      };
    }
    return profile.container;
  }

  String _duplicateKey(CatalogTrack track, BuildOptions options) {
    return '${track.id}|${options.effectiveQuality}|${options.effectiveCodec}';
  }

  String _displayTitle(PickedTrack selected) {
    return selected.item.tracks.length <= 1
        ? selected.item.title
        : '${selected.item.title} - ${selected.track.title}';
  }
}
