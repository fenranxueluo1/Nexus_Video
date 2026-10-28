import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/service_exception.dart';
import '../compose/job_composer.dart';
import '../domain/catalog.dart';
import '../domain/jobs.dart';
import '../domain/output_profile.dart';
import '../domain/preferences.dart';
import '../pathing/path_template.dart';
import '../util/identifiers.dart';
import '../util/platform_support.dart';
import 'chirp_gateway.dart';
import 'douyin_gateway.dart';
import 'remote_models.dart';
import 'tube_gateway.dart';

class RemoteJobPlanner {
  RemoteJobPlanner(this._tube, this._chirp, this._douyin);

  final TubeGateway _tube;
  final ChirpGateway _chirp;
  final DouyinGateway _douyin;

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
      final title = selected.item.tracks.length <= 1
          ? selected.item.title
          : '${selected.item.title} - ${selected.track.title}';
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
    if (isMobileLike && profile.producesMedia) {
      final supported =
          profile.container == OutputContainer.mp4 ||
          profile.container == OutputContainer.m4a ||
          (isHarmony && profile.container == OutputContainer.mkv);
      if (!supported || profile.embedCaptions || profile.embedArtwork) {
        throw const ApiException(
          '移动端目前只支持合并为 MP4/M4A，暂不支持 MKV、MP3、FLAC、字幕嵌入或封面嵌入。',
        );
      }
    }
    if (!profile.producesMedia &&
        (profile.includeCaptions ||
            profile.embedCaptions ||
            profile.overlayFormats.isNotEmpty)) {
      throw const ApiException('YouTube / X 暂不支持字幕或弹幕方案。');
    }

    final track = selected.track;
    final item = selected.item;
    final key = _duplicateKey(track, options);
    if (duplicateKeys.contains(key)) {
      skipped.add(
        BuildSkip(
          title: item.tracks.length <= 1
              ? item.title
              : '${item.title} - ${track.title}',
          reason: '已存在相同质量与编码的任务',
        ),
      );
      return null;
    }

    final remoteId = _remoteId(track);
    final streams = switch (catalogKind) {
      CatalogKind.tube => await _tube.streams(remoteId),
      CatalogKind.chirp => await _chirp.streams(remoteId),
      CatalogKind.douyin => await _douyin.streams(remoteId),
      _ => throw const ApiException('不支持的远程来源。'),
    };

    RemoteStream? video = profile.includeVideo
        ? _pickVideo(streams.videos, options)
        : null;
    RemoteStream? audio = profile.includeAudio
        ? _pickAudio(
            streams.audios,
            preferredContainer: video?.container == 'mp4' ? 'm4a' : null,
          )
        : null;
    var combined = false;

    if (profile.includeVideo && profile.includeAudio) {
      if (video == null || audio == null) {
        final fallback = _pickVideo(streams.muxed, options);
        if (fallback == null) {
          throw const ApiException('没有找到同时包含音视频的可下载流。');
        }
        video = fallback;
        audio = null;
        combined = true;
      }
    } else if (profile.includeVideo && video == null) {
      final fallback = _pickVideo(streams.muxed, options);
      if (fallback == null) {
        throw const ApiException('没有找到可用的 MP4 视频流，请更换清晰度或代理。');
      }
      video = fallback;
      combined = true;
    } else if (profile.includeAudio && audio == null) {
      final fallback = _pickAudio(streams.muxed);
      if (fallback == null) {
        throw const ApiException('没有找到可用的音频流。');
      }
      audio = fallback;
      combined = true;
    }

    if (isHarmony && profile.includeVideo && profile.includeAudio) {
      final fallback = _pickVideo(streams.muxed, options);
      if (fallback == null) {
        throw const ApiException(
          '该视频没有可直接下载的合并流，鸿蒙端暂不支持独立音视频合并。',
        );
      }
      video = fallback;
      audio = null;
      combined = true;
    }

    if (profile.includeVideo && video == null) {
      throw const ApiException('没有找到可用的 MP4 视频流，请更换清晰度或代理。');
    }
    if (profile.includeAudio && audio == null && video == null) {
      throw const ApiException('没有找到可用的音频流。');
    }
    if (video == null && audio == null && !profile.producesExtras) {
      throw const ApiException('当前方案没有选择任何要保存的内容。');
    }

    final container = _effectiveContainer(
      profile,
      video: video,
      audio: audio,
      hasVideo: video != null,
      hasAudio: audio != null,
    );
    if (isMobileLike && container == OutputContainer.mkv) {
      throw const ApiException('该视频只有 WebM/VP9 格式，移动端暂不支持，请在桌面端下载。');
    }
    final extension = container.extension;
    final selectedHeight = video?.height ?? audio?.height ?? 0;
    final qualityCode = _qualityCode(selectedHeight);
    final codec = video?.codecLabel ?? 'AUDIO';

    final naming = PathFields(
      title: track.series?.isNotEmpty == true ? track.series! : item.title,
      trackTitle: track.title,
      trackNo: track.index,
      ext: extension,
      creator: track.creator ?? item.creator,
      series: track.series,
      index: track.index,
      quality: qualityCode,
      codec: codec,
      date: DateTime.now(),
      publishDate: track.pubDate,
    );
    final relative = composeRelativePath(
      options.preferences.pathTemplate,
      naming,
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
      skipped.add(
        BuildSkip(
          title: item.tracks.length <= 1
              ? item.title
              : '${item.title} - ${track.title}',
          reason: '目标文件已存在',
        ),
      );
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
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/131.0.0.0 Safari/537.36',
      'Accept': '*/*',
      if (catalogKind == CatalogKind.tube)
        'Referer': 'https://www.youtube.com/',
      if (catalogKind == CatalogKind.chirp) 'Referer': 'https://x.com/',
      if (catalogKind == CatalogKind.douyin)
        'Referer': 'https://www.douyin.com/',
    };

    if (video != null) {
      final targetName = video.isMuxed ? 'combined.mp4' : 'video.mp4';
      assets.add(
        JobAsset(
          id: '$jobId:video',
          role: AssetRole.video,
          urls: [video.url],
          headers: {...headers, ...video.headers},
          destinationPath: p.join(workRoot, targetName),
          scratchPath: p.join(workRoot, '$targetName.nxpart'),
          expectedBytes: video.sizeBytes,
          label: video.isMuxed
              ? '音视频合并流 ${video.qualityLabel}'
              : '${video.qualityLabel} ${video.codecLabel}',
        ),
      );
    }
    if (audio != null) {
      final targetName = audio.isMuxed ? 'combined.mp4' : 'audio.m4a';
      assets.add(
        JobAsset(
          id: '$jobId:audio',
          role: AssetRole.audio,
          urls: [audio.url],
          headers: {...headers, ...audio.headers},
          destinationPath: p.join(workRoot, targetName),
          scratchPath: p.join(workRoot, '$targetName.nxpart'),
          expectedBytes: audio.sizeBytes,
          label: audio.isMuxed
              ? '${audio.qualityLabel} 合并流音轨'
              : '音频 ${audio.bitrate ~/ 1000} kbps',
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

    final taskTitle = item.tracks.length <= 1
        ? item.title
        : '${item.title} - ${track.title}';
    final missingAudio =
        profile.includeAudio &&
        audio == null &&
        video != null &&
        !video.isMuxed;
    return TransferJob(
      id: jobId,
      title: taskTitle,
      catalogId: item.id,
      catalogKind: catalogKind,
      state: JobState.queued,
      track: track,
      recipe: OutputRecipe.fromPreset(
        profile,
        quality: options.effectiveQuality,
        codec: options.effectiveCodec,
        container: container,
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
              ? '该来源没有独立音频流，输出将只包含视频。'
              : combined
              ? '已创建任务：${naming.title} / ${naming.trackTitle}（音视频合并流）'
              : '已创建任务：${naming.title} / ${naming.trackTitle}',
        ),
      ],
    );
  }

  RemoteStream? _pickVideo(List<RemoteStream> streams, BuildOptions options) {
    if (streams.isEmpty) {
      return null;
    }
    final target = _targetHeight(options.effectiveQuality);
    final sorted = List<RemoteStream>.of(streams)
      ..sort((left, right) {
        final height = right.height.compareTo(left.height);
        if (height != 0) {
          return height;
        }
        return right.bitrate.compareTo(left.bitrate);
      });
    final eligible = sorted.where((stream) => stream.height <= target).toList();
    final chosen = eligible.isNotEmpty ? eligible.first : sorted.last;
    final sameHeight = sorted
        .where((stream) => stream.height == chosen.height)
        .toList();
    final preference = switch (options.effectiveCodec) {
      'avc' => 'avc',
      'hevc' => 'hevc',
      'av1' => 'av1',
      _ => null,
    };
    if (preference != null) {
      final match = sameHeight
          .where((stream) => stream.videoCodecKey == preference)
          .toList();
      if (match.isNotEmpty) {
        return match.first;
      }
    }
    for (final codec in ['avc', 'hevc', 'av1', 'vp9', 'vp8']) {
      final match = sameHeight
          .where((stream) => stream.videoCodecKey == codec)
          .toList();
      if (match.isNotEmpty) {
        return match.first;
      }
    }
    return sameHeight.first;
  }

  RemoteStream? _pickAudio(
    List<RemoteStream> streams, {
    String? preferredContainer,
  }) {
    if (streams.isEmpty) {
      return null;
    }
    final sorted = List<RemoteStream>.of(streams)
      ..sort((left, right) => right.bitrate.compareTo(left.bitrate));
    if (preferredContainer != null) {
      final preferred = sorted
          .where((stream) => stream.container == preferredContainer)
          .toList();
      if (preferred.isNotEmpty) {
        return preferred.first;
      }
    }
    return sorted.first;
  }

  int _targetHeight(String preference) {
    if (preference == 'worst') {
      return 0;
    }
    final numeric = int.tryParse(preference);
    if (numeric == null) {
      return 1 << 30;
    }
    if (numeric >= 127) {
      return 1 << 30;
    }
    if (numeric >= 120) {
      return 2160;
    }
    if (numeric >= 80) {
      return 1080;
    }
    if (numeric >= 64) {
      return 720;
    }
    if (numeric >= 32) {
      return 480;
    }
    if (numeric >= 16) {
      return 360;
    }
    return 240;
  }

  String? _qualityCode(int height) {
    if (height >= 4320) {
      return '127';
    }
    if (height >= 2160) {
      return '120';
    }
    if (height >= 1440) {
      return '116';
    }
    if (height >= 1080) {
      return '80';
    }
    if (height >= 720) {
      return '64';
    }
    if (height >= 480) {
      return '32';
    }
    if (height >= 360) {
      return '16';
    }
    if (height > 0) {
      return '6';
    }
    return null;
  }

  OutputContainer _effectiveContainer(
    OutputProfile profile, {
    required RemoteStream? video,
    required RemoteStream? audio,
    required bool hasVideo,
    required bool hasAudio,
  }) {
    if (isHarmony) {
      return hasVideo ? OutputContainer.mp4 : OutputContainer.m4a;
    }
    final webmVideo =
        video != null &&
        (video.container == 'webm' ||
            video.videoCodecKey == 'vp9' ||
            video.videoCodecKey == 'vp8');
    final opusAudio =
        audio != null &&
        (audio.container == 'webm' ||
            audio.audioCodec.toLowerCase().contains('opus'));
    final needsMkv = webmVideo || opusAudio;
    if (hasVideo && hasAudio) {
      return profile.container == OutputContainer.mkv || needsMkv
          ? OutputContainer.mkv
          : OutputContainer.mp4;
    }
    if (hasVideo) {
      return profile.container == OutputContainer.mkv || needsMkv
          ? OutputContainer.mkv
          : OutputContainer.mp4;
    }
    if (hasAudio) {
      if (profile.container == OutputContainer.mp3) {
        return OutputContainer.mp3;
      }
      if (profile.container == OutputContainer.flac) {
        return OutputContainer.flac;
      }
      return needsMkv ? OutputContainer.mkv : OutputContainer.m4a;
    }
    return profile.container;
  }

  String _remoteId(CatalogTrack track) {
    final separator = track.id.indexOf(':');
    return separator < 0 ? track.id : track.id.substring(separator + 1);
  }

  String _duplicateKey(CatalogTrack track, BuildOptions options) {
    return '${track.id}|${options.effectiveQuality}|${options.effectiveCodec}';
  }
}
