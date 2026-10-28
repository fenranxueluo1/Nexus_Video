import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../api/service_exception.dart';
import '../api/bili_gateway.dart';
import '../compose/job_composer.dart';
import '../transfer/throughput_governor.dart';
import '../transfer/asset_receiver.dart';
import '../postprocess/comment_overlay.dart';
import '../postprocess/media_packager.dart';
import '../postprocess/catalog_metadata.dart';
import '../postprocess/captions.dart';
import '../domain/output_profile.dart';
import '../domain/preferences.dart';
import '../domain/catalog.dart';
import '../domain/jobs.dart';
import '../repository/job_repository.dart';
import '../repository/preferences_repository.dart';
import '../util/task_token.dart';
import '../util/privacy.dart';

class TransferCoordinator extends ChangeNotifier {
  TransferCoordinator({
    required this.client,
    required this.composer,
    required this.preferencesRepository,
    required this.jobRepository,
  });

  final BiliGateway client;
  final JobComposer composer;
  final PreferencesRepository preferencesRepository;
  final JobRepository jobRepository;

  final List<TransferJob> _jobs = [];
  final List<CompletionRecord> _records = [];
  final Map<String, TaskToken> _tokens = {};
  final Map<String, String> _cancelReasons = {};
  final Map<String, ThroughputGovernor> _taskLimiters = {};
  final Map<String, RateGate> _progressRateGates = {};

  late AssetReceiver _fetcher;
  late MediaPackager _muxer;
  ThroughputGovernor? _globalLimiter;
  Timer? _scheduler;
  Timer? _persistTimer;
  Timer? _notifyTimer;
  bool _initialized = false;
  bool _disposed = false;
  bool _persisting = false;
  bool _persistQueued = false;
  int _active = 0;

  Preferences get preferences => preferencesRepository.preferences;
  List<TransferJob> get jobs => List.unmodifiable(_jobs);
  List<CompletionRecord> get records => List.unmodifiable(_records);
  int get runningCount => _active;

  bool isRunning(String jobId) => _tokens.containsKey(jobId);

  Future<void> init(Preferences preferences) async {
    _configure(preferences);
    _jobs.addAll(await jobRepository.loadJobs());
    _records.addAll(await jobRepository.loadRecords());
    await _cleanupOrphanTempDirectories();
    _recover(preferences);
    _initialized = true;
    _scheduler = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pump(),
    );
    await _persistNow();
    _notify(true);
    _pump();
  }

  void updateSettings(Preferences preferences) {
    _configure(preferences);
    _pump();
    _notify(true);
  }

  void _configure(Preferences preferences) {
    try {
      client.proxy = preferences.proxy;
    } on ApiException {
      client.proxy = '';
    }
    if (_globalLimiter == null) {
      _globalLimiter = ThroughputGovernor(preferences.rateLimitBytesPerSecond);
    } else {
      _globalLimiter!.setLimit(preferences.rateLimitBytesPerSecond);
    }
    _fetcher = AssetReceiver(
      client.http,
      retryLimit: preferences.retryLimit,
      parallelSegments: preferences.normalizedSegments,
      globalLimiter: _globalLimiter,
    );
    _muxer = MediaPackager(packagerPath: preferences.packagerPath);
  }

  void _recover(Preferences preferences) {
    for (var index = 0; index < _jobs.length; index += 1) {
      var job = _jobs[index];
      var state = job.state;
      if (state == JobState.preparing ||
          state == JobState.transferring ||
          state == JobState.packaging) {
        state = preferences.resumeOnLaunch ? JobState.queued : JobState.held;
      }
      var assets = job.assets.map((asset) {
        if (asset.state == AssetState.transferring ||
            asset.state == AssetState.held) {
          return asset.copyWith(state: AssetState.queued);
        }
        return asset;
      }).toList();

      if (state == JobState.finished) {
        final needsMedia = job.recipe.includeVideo || job.recipe.includeAudio;
        if (needsMedia &&
            job.destination.isNotEmpty &&
            !File(job.destination).existsSync()) {
          state = JobState.queued;
          assets = assets
              .map((asset) => asset.copyWith(state: AssetState.queued))
              .toList();
        }
      }

      job = job.copyWith(
        state: state,
        assets: assets,
        clearError: state == JobState.queued && job.error != null,
      );
      _jobs[index] = job;
    }
  }

  Future<void> _cleanupOrphanTempDirectories() async {
    try {
      final root = Directory(
        p.join(preferences.destinationRoot, '.nexus-work'),
      );
      if (!await root.exists()) {
        return;
      }
      final valid = _jobs
          .map((job) => job.scratchDirectory)
          .where((path) => path.isNotEmpty)
          .toSet();
      await for (final entry in root.list()) {
        if (entry is Directory && !valid.contains(entry.path)) {
          await entry.delete(recursive: true);
        }
      }
    } on FileSystemException {
      // Orphan cleanup is best-effort.
    }
  }

  int admitJobs(List<TransferJob> incoming) {
    final keys = _jobs
        .where((job) => job.state != JobState.aborted)
        .map((job) => job.duplicateKey)
        .toSet();
    var added = 0;
    for (final job in incoming) {
      if (keys.contains(job.duplicateKey)) {
        continue;
      }
      keys.add(job.duplicateKey);
      _jobs.add(job);
      added += 1;
    }
    _pump();
    _persistSoon();
    _notify(true);
    return added;
  }

  void holdJob(String jobId) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    if (job.state == JobState.queued || job.state == JobState.held) {
      _updateTask(
        job.copyWith(state: JobState.held, updatedAt: DateTime.now()),
      );
      _persistSoon();
      _notify(true);
      return;
    }
    if (job.state.isRunning) {
      _cancelReasons[jobId] = 'pause';
      _tokens[jobId]?.cancel();
      _updateTask(
        job.copyWith(state: JobState.held, updatedAt: DateTime.now()),
      );
      _notify(true);
    }
  }

  void releaseJob(String jobId) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    if (job.state != JobState.held &&
        job.state != JobState.failed &&
        job.state != JobState.aborted) {
      return;
    }
    final assets = job.assets.map((asset) {
      if (asset.state == AssetState.failed ||
          asset.state == AssetState.aborted ||
          asset.state == AssetState.held) {
        return asset.copyWith(state: AssetState.queued, clearError: true);
      }
      return asset;
    }).toList();
    _updateTask(
      job.copyWith(
        state: JobState.queued,
        assets: assets,
        clearError: true,
        updatedAt: DateTime.now(),
      ),
    );
    _log(jobId, '任务已重新加入队列');
    _pump();
    _persistSoon();
    _notify(true);
  }

  void retryJob(String jobId) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    _updateTask(job.copyWith(attemptCount: job.attemptCount + 1));
    releaseJob(jobId);
  }

  void abortJob(String jobId) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    if (job.state.isRunning) {
      _cancelReasons[jobId] = 'cancel';
      _tokens[jobId]?.cancel();
      _updateTask(
        job.copyWith(state: JobState.aborted, updatedAt: DateTime.now()),
      );
    } else if (job.state == JobState.queued || job.state == JobState.held) {
      _updateTask(
        job.copyWith(state: JobState.aborted, updatedAt: DateTime.now()),
      );
    }
    _persistSoon();
    _notify(true);
  }

  Future<void> discardJob(String jobId, {bool deleteFiles = false}) async {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    if (job.state.isRunning) {
      _cancelReasons[jobId] = 'cancel';
      _tokens[jobId]?.cancel();
    }
    _jobs.removeWhere((candidate) => candidate.id == jobId);
    _records.removeWhere((record) => record.jobId == jobId);
    _taskLimiters.remove(jobId);
    _progressRateGates.remove(jobId);
    await jobRepository.deleteJournal(jobId);
    if (deleteFiles) {
      await _deleteTaskFiles(job);
    }
    await _persistNow();
    _notify(true);
  }

  Future<void> purgeSettled({bool deleteFiles = false}) async {
    final finished = _jobs
        .where(
          (job) =>
              job.state == JobState.finished ||
              job.state == JobState.failed ||
              job.state == JobState.aborted,
        )
        .map((job) => job.id)
        .toList();
    for (final id in finished) {
      await discardJob(id, deleteFiles: deleteFiles);
    }
  }

  void limitJob(String jobId, int? bytesPerSecond) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    _updateTask(
      job.copyWith(
        rateLimitBytesPerSecond: bytesPerSecond,
        clearSpeedLimit: bytesPerSecond == null || bytesPerSecond <= 0,
      ),
    );
    final limiter = _taskLimiters[jobId];
    if (limiter != null) {
      limiter.setLimit(bytesPerSecond ?? 0);
    }
    _persistSoon();
    _notify(true);
  }

  void scheduleJob(String jobId, DateTime? scheduledAt) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    _updateTask(
      job.copyWith(
        scheduledAt: scheduledAt,
        clearScheduledAt: scheduledAt == null,
      ),
    );
    _pump();
    _persistSoon();
    _notify(true);
  }

  Future<void> shutdown() async {
    _scheduler?.cancel();
    _scheduler = null;
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    await _persistNow();
  }

  void _pump() {
    if (!_initialized || _disposed) {
      return;
    }
    final now = DateTime.now();
    final limit = preferences.normalizedConcurrency;
    while (_active < limit) {
      final index = _jobs.indexWhere((job) {
        if (job.state != JobState.queued) {
          return false;
        }
        final scheduled = job.scheduledAt;
        return scheduled == null || !scheduled.isAfter(now);
      });
      if (index < 0) {
        break;
      }
      final job = _jobs[index];
      if (_tokens.containsKey(job.id)) {
        break;
      }
      _active += 1;
      _updateTask(job.copyWith(state: JobState.transferring, updatedAt: now));
      unawaited(_runTask(job.id));
    }
  }

  Future<void> _runTask(String jobId) async {
    final token = TaskToken();
    _tokens[jobId] = token;
    var current = _taskById(jobId);
    if (current == null) {
      _tokens.remove(jobId);
      _active = (_active - 1).clamp(0, 999);
      return;
    }
    final speedLimit = current.rateLimitBytesPerSecond;
    final taskLimiter = speedLimit != null && speedLimit > 0
        ? ThroughputGovernor(speedLimit)
        : null;
    if (taskLimiter != null) {
      _taskLimiters[jobId] = taskLimiter;
    }

    try {
      _log(jobId, '开始处理');
      final assets = List<JobAsset>.of(current.assets);
      for (final asset in assets) {
        token.throwIfCancelled();
        current = _taskById(jobId);
        if (current == null) {
          return;
        }
        final latest = current.assets.firstWhere(
          (candidate) => candidate.id == asset.id,
          orElse: () => asset,
        );
        if (latest.state == AssetState.ready) {
          continue;
        }
        await _downloadResource(jobId, latest, token, taskLimiter);
      }

      token.throwIfCancelled();
      current = _taskById(jobId);
      if (current == null) {
        return;
      }
      _updateTask(
        current.copyWith(state: JobState.packaging, updatedAt: DateTime.now()),
      );
      _notify(true);

      await _postProcess(jobId, token);
      token.throwIfCancelled();

      final finished = _taskById(jobId);
      if (finished == null) {
        return;
      }
      final needsMedia =
          finished.recipe.includeVideo || finished.recipe.includeAudio;
      if (needsMedia) {
        final output = File(finished.destination);
        if (!await output.exists() || await output.length() == 0) {
          throw const ApiException('输出文件未生成，请检查 封装工具设置或重试。');
        }
      } else {
        final produced = await _auxiliaryFileCount(finished);
        if (produced == 0) {
          throw const ApiException('没有生成任何输出文件，请检查方案与字幕/弹幕设置。');
        }
      }

      final size = await _outputSize(finished);
      final completed = finished.copyWith(
        state: JobState.finished,
        completedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        deliveredBytes: size,
        clearError: true,
      );
      _updateTask(completed);
      _log(jobId, '处理完成：${completed.destination}');
      _recordCompletion(completed);
      await _cleanupTemp(completed);
      if (preferences.revealAfterSave) {
        _revealFolder(completed.destination);
      }
    } on TaskAborted {
      final reason = _cancelReasons.remove(jobId) ?? 'cancel';
      final job = _taskById(jobId);
      if (job != null) {
        final assets = job.assets.map((asset) {
          if (asset.state == AssetState.transferring) {
            return asset.copyWith(
              state: reason == 'pause' ? AssetState.held : AssetState.aborted,
            );
          }
          return asset;
        }).toList();
        _updateTask(
          job.copyWith(
            state: reason == 'pause' ? JobState.held : JobState.aborted,
            assets: assets,
            updatedAt: DateTime.now(),
          ),
        );
        _log(
          jobId,
          reason == 'pause' ? '任务已暂停' : '任务已取消',
          JournalLevel.warning,
        );
      }
    } on ApiException catch (error) {
      _failTask(jobId, error.message);
    } on Object catch (error) {
      _failTask(jobId, '$error');
    } finally {
      _cancelReasons.remove(jobId);
      _tokens.remove(jobId);
      _taskLimiters.remove(jobId);
      _active = (_active - 1).clamp(0, 999);
      _persistSoon();
      _notify(true);
      _pump();
    }
  }

  Future<void> _downloadResource(
    String jobId,
    JobAsset asset,
    TaskToken token,
    ThroughputGovernor? taskLimiter,
  ) async {
    final isMedia =
        asset.role == AssetRole.video || asset.role == AssetRole.audio;
    _updateResource(
      jobId,
      asset.id,
      (current) =>
          current.copyWith(state: AssetState.transferring, clearError: true),
    );
    _notify(true);
    try {
      if (isMedia) {
        final throttler = _progressRateGates.putIfAbsent(
          jobId,
          () => RateGate(const Duration(milliseconds: 150)),
        );
        Future<ReceiveResult> fetch(JobAsset target) {
          return _fetcher.receive(
            asset: target,
            token: token,
            taskLimiter: taskLimiter,
            onProgress: (downloaded, total) {
              if (!throttler.ready) {
                return;
              }
              _updateResource(
                jobId,
                target.id,
                (current) => current.copyWith(
                  receivedBytes: downloaded,
                  expectedBytes: total ?? current.expectedBytes,
                ),
              );
              _notify();
            },
          );
        }

        ReceiveResult outcome;
        try {
          outcome = await fetch(asset);
        } on ApiException catch (error) {
          if (!_isDeadUrlError(error)) {
            rethrow;
          }
          JobAsset? refreshed;
          try {
            await _refreshMediaUrls(jobId);
            refreshed = _assetById(jobId, asset.id);
          } on ApiException {
            refreshed = null;
          }
          if (refreshed == null) {
            rethrow;
          }
          _log(jobId, '资源地址已失效，已重新解析播放地址');
          outcome = await fetch(refreshed);
        }
        _updateResource(
          jobId,
          asset.id,
          (current) => current.copyWith(
            state: AssetState.ready,
            receivedBytes: outcome.bytes,
            expectedBytes: outcome.bytes,
            clearError: true,
          ),
        );
        _log(jobId, '${asset.role.label}处理完成');
      } else {
        await _fetcher.receiveSmall(
          urls: asset.urls,
          destinationPath: asset.destinationPath,
          token: token,
          headers: asset.headers,
          maxBytes: asset.role == AssetRole.artwork
              ? 32 * 1024 * 1024
              : 64 * 1024 * 1024,
        );
        final length = await File(asset.destinationPath).length();
        _updateResource(
          jobId,
          asset.id,
          (current) => current.copyWith(
            state: AssetState.ready,
            receivedBytes: length,
            expectedBytes: length,
            clearError: true,
          ),
        );
        _log(jobId, '${asset.role.label}处理完成');
      }
    } on TaskAborted {
      rethrow;
    } on ApiException catch (error) {
      _updateResource(
        jobId,
        asset.id,
        (current) => current.copyWith(
          state: AssetState.failed,
          error: scrubSecrets(error.message),
        ),
      );
      if (isMedia) {
        rethrow;
      }
      _log(
        jobId,
        '${asset.role.label}获取失败：${scrubSecrets(error.message)}',
        JournalLevel.warning,
      );
    }
  }

  Future<void> _postProcess(String jobId, TaskToken token) async {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    final workRoot = job.scratchDirectory.isEmpty
        ? p.join(preferences.destinationRoot, '.nexus-work', job.id)
        : job.scratchDirectory;
    final stem = p.join(
      p.dirname(job.destination),
      p.basenameWithoutExtension(job.destination),
    );

    String? artworkPath;
    final cover = _completedResource(job, AssetRole.artwork);
    if (cover != null && await File(cover.destinationPath).exists()) {
      artworkPath = cover.destinationPath;
      if (job.recipe.includeArtwork) {
        token.throwIfCancelled();
        final sidecar = '$stem.jpg';
        await ensureParent(sidecar);
        await File(cover.destinationPath).copy(sidecar);
        _log(jobId, '封面已保存：$sidecar');
      }
    }

    String? embedCaptionPath;
    final captionAsset = _completedResource(job, AssetRole.caption);
    if (captionAsset != null &&
        await File(captionAsset.destinationPath).exists()) {
      final text = await File(captionAsset.destinationPath).readAsString();
      final cues = readCaptionJson(text);
      if (cues.isEmpty) {
        _log(jobId, '字幕内容为空，已跳过', JournalLevel.warning);
      } else {
        final srt = captionsToSrt(cues);
        await ensureParent('$workRoot/caption.srt');
        embedCaptionPath = '$workRoot/caption.srt';
        await File(embedCaptionPath).writeAsString(srt, flush: true);
        if (job.recipe.includeCaptions) {
          final language = (captionAsset.label ?? 'zh-CN').replaceAll(
            RegExp(r'[^A-Za-z0-9_-]'),
            '',
          );
          final sidecar = '$stem.${language.isEmpty ? 'zh-CN' : language}.srt';
          await ensureParent(sidecar);
          await File(sidecar).writeAsString(srt, flush: true);
          _log(jobId, '字幕已保存：$sidecar');
        }
      }
    }

    final danmakuResource = _completedResource(job, AssetRole.overlay);
    if (danmakuResource != null &&
        await File(danmakuResource.destinationPath).exists()) {
      token.throwIfCancelled();
      final xml = await File(danmakuResource.destinationPath).readAsString();
      final items = readCommentOverlay(xml);
      if (items.isEmpty) {
        _log(jobId, '弹幕内容为空，已跳过', JournalLevel.warning);
      } else {
        final formats = job.recipe.overlayFormats.toSet();
        final mediaSaved =
            (job.recipe.includeVideo || job.recipe.includeAudio) &&
            (job.recipe.container == OutputContainer.mp4 ||
                job.recipe.container == OutputContainer.mkv);
        final videoFileName = mediaSaved ? p.basename(job.destination) : null;
        for (final format in formats) {
          token.throwIfCancelled();
          final path = '$stem.danmaku.${format.extension}';
          await ensureParent(path);
          switch (format) {
            case OverlayFormat.xml:
              await File(path).writeAsString(xml, flush: true);
            case OverlayFormat.html:
              await File(path).writeAsString(
                overlayToHtml(
                  items,
                  videoFileName: videoFileName,
                  title: job.title,
                ),
                flush: true,
              );
            case OverlayFormat.srt:
              await File(path).writeAsString(overlayToSrt(items), flush: true);
            case OverlayFormat.ass:
              await File(path).writeAsString(overlayToAss(items), flush: true);
          }
          _log(jobId, '弹幕已保存：$path（${items.length} 条）');
        }
      }
    }

    if (job.recipe.includeCatalog) {
      token.throwIfCancelled();
      final nfoPath = '$stem.nfo';
      await ensureParent(nfoPath);
      final item = CatalogEntry(
        id: job.catalogId,
        title: job.track.series?.isNotEmpty == true
            ? job.track.series!
            : job.title,
        summary: job.plot,
        creator: job.track.creator,
        creatorId: job.track.creatorId,
      );
      final nfo = composeCatalogXml(
        catalogMetadataFor(
          item: item,
          track: job.track,
          quality: job.recipe.quality,
          codec: job.recipe.codec,
          url: _sourceUrl(job),
        ),
        customTemplate: preferences.catalogTemplate,
      );
      await File(nfoPath).writeAsString(nfo, flush: true);
      _log(jobId, 'NFO 已保存：$nfoPath');
    }

    final video = _completedResource(job, AssetRole.video);
    final audio = _completedResource(job, AssetRole.audio);
    final videoPath = video?.destinationPath;
    final audioPath = audio?.destinationPath;
    if (videoPath != null || audioPath != null) {
      token.throwIfCancelled();
      _log(jobId, '开始合并输出');
      await _muxer.assemble(
        destination: job.destination,
        container: job.recipe.container,
        videoPath: videoPath,
        audioPath: audioPath,
        dropAudio:
            videoPath != null && audioPath == null && !job.recipe.includeAudio,
        captionFiles: [
          if (embedCaptionPath != null &&
              job.recipe.embedCaptions &&
              job.recipe.container == OutputContainer.mkv)
            embedCaptionPath,
        ],
        artworkPath: artworkPath,
        embedArtwork:
            job.recipe.embedArtwork &&
            job.recipe.container == OutputContainer.mkv,
        embedCaptions:
            job.recipe.embedCaptions &&
            job.recipe.container == OutputContainer.mkv,
        token: token,
        onLog: (line) => _log(jobId, scrubSecrets(line)),
      );
      _log(jobId, '合并完成：${job.destination}');
    }
  }

  void _failTask(String jobId, String message) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    final safeMessage = scrubSecrets(message);
    _updateTask(
      job.copyWith(
        state: JobState.failed,
        error: safeMessage,
        updatedAt: DateTime.now(),
      ),
    );
    _log(jobId, '任务失败：$safeMessage', JournalLevel.error);
  }

  Future<int> _outputSize(TransferJob job) async {
    var total = 0;
    final paths = <String>[job.destination, ..._sidecarPaths(job)];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  Future<int> _auxiliaryFileCount(TransferJob job) async {
    var count = 0;
    for (final path in _sidecarPaths(job)) {
      if (await File(path).exists()) {
        count += 1;
      }
    }
    return count;
  }

  List<String> _sidecarPaths(TransferJob job) {
    final stem = p.join(
      p.dirname(job.destination),
      p.basenameWithoutExtension(job.destination),
    );
    final caption = job.assets.firstWhere(
      (asset) => asset.role == AssetRole.caption,
      orElse: () => const JobAsset(
        id: '',
        role: AssetRole.caption,
        urls: [],
        destinationPath: '',
        scratchPath: '',
      ),
    );
    final language = (caption.label ?? '').replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '',
    );
    return [
      '$stem.jpg',
      '$stem.nfo',
      if (language.isNotEmpty) '$stem.$language.srt',
      for (final format in job.recipe.overlayFormats)
        '$stem.danmaku.${format.extension}',
    ];
  }

  String _sourceUrl(TransferJob job) {
    if (job.track.epId != null && job.catalogKind == CatalogKind.bangumi) {
      return 'https://www.bilibili.com/bangumi/play/ep${job.track.epId}';
    }
    if (job.track.epId != null && job.catalogKind == CatalogKind.cheese) {
      return 'https://www.bilibili.com/cheese/play/ep${job.track.epId}';
    }
    if (job.track.bvid != null && job.track.bvid!.isNotEmpty) {
      return 'https://www.bilibili.com/video/${job.track.bvid}';
    }
    return '';
  }

  Future<void> _cleanupTemp(TransferJob job) async {
    if (job.recipe.keepSourceStreams || job.scratchDirectory.isEmpty) {
      return;
    }
    try {
      final directory = Directory(job.scratchDirectory);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      final parent = directory.parent;
      if (await parent.exists()) {
        final remains = await parent.list().take(1).toList();
        if (remains.isEmpty) {
          await parent.delete();
        }
      }
    } on FileSystemException {
      // Temporary cleanup must never fail a completed download.
    }
  }

  Future<void> _deleteTaskFiles(TransferJob job) async {
    final paths = <String>[job.destination, ..._sidecarPaths(job)];
    for (final path in paths) {
      if (path.isEmpty) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException {
        // Best effort.
      }
    }
    if (job.scratchDirectory.isNotEmpty) {
      try {
        final directory = Directory(job.scratchDirectory);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } on FileSystemException {
        // Best effort.
      }
    }
  }

  void _recordCompletion(TransferJob job) {
    _records.removeWhere((record) => record.jobId == job.id);
    _records.insert(
      0,
      CompletionRecord(
        jobId: job.id,
        title: job.title,
        catalogId: job.catalogId,
        destination: job.destination,
        quality: job.recipe.quality,
        codec: job.recipe.codec,
        container: job.recipe.container.extension,
        completedAt: job.completedAt ?? DateTime.now(),
        errorSummary: _errorSummary(job),
      ),
    );
    if (_records.length > 500) {
      _records.removeRange(500, _records.length);
    }
  }

  String? _errorSummary(TransferJob job) {
    final messages = job.journal
        .where(
          (log) =>
              log.level == JournalLevel.warning ||
              log.level == JournalLevel.error,
        )
        .map((log) => log.message)
        .toList();
    if (messages.isEmpty) {
      return null;
    }
    final summary = messages.join('\n');
    return summary.length <= 2000
        ? summary
        : '${summary.substring(0, 1997)}...';
  }

  JobAsset? _completedResource(TransferJob job, AssetRole role) {
    for (final asset in job.assets) {
      if (asset.role == role && asset.state == AssetState.ready) {
        return asset;
      }
    }
    return null;
  }

  bool _isDeadUrlError(ApiException error) {
    final status = error.statusCode;
    return status == 403 || status == 404 || status == 410;
  }

  Future<void> _refreshMediaUrls(String jobId) async {
    final job = _taskById(jobId);
    if (job == null) {
      throw const ApiException('任务已不存在，无法重新解析播放地址。');
    }
    final refreshed = await composer.refreshMediaUrls(job);
    if (refreshed == null) {
      throw const ApiException('无法重新解析播放地址。');
    }
    final latest = _taskById(jobId);
    if (latest == null) {
      return;
    }
    final freshUrls = {for (final asset in refreshed) asset.id: asset.urls};
    final assets = latest.assets.map((asset) {
      final urls = freshUrls[asset.id];
      if (urls == null || urls.isEmpty) {
        return asset;
      }
      return asset.copyWith(urls: urls);
    }).toList();
    _updateTask(latest.copyWith(assets: assets, updatedAt: DateTime.now()));
    _notify(true);
  }

  JobAsset? _assetById(String jobId, String assetId) {
    final job = _taskById(jobId);
    if (job == null) {
      return null;
    }
    for (final asset in job.assets) {
      if (asset.id == assetId) {
        return asset;
      }
    }
    return null;
  }

  void _updateResource(
    String jobId,
    String assetId,
    JobAsset Function(JobAsset) update,
  ) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    final index = job.assets.indexWhere((asset) => asset.id == assetId);
    if (index < 0) {
      return;
    }
    final assets = List<JobAsset>.of(job.assets);
    assets[index] = update(assets[index]);
    _updateTask(job.copyWith(assets: assets, updatedAt: DateTime.now()));
  }

  void _updateTask(TransferJob job) {
    final index = _jobs.indexWhere((candidate) => candidate.id == job.id);
    if (index < 0) {
      return;
    }
    _jobs[index] = job;
  }

  TransferJob? _taskById(String jobId) {
    for (final job in _jobs) {
      if (job.id == jobId) {
        return job;
      }
    }
    return null;
  }

  void _log(
    String jobId,
    String message, [
    JournalLevel level = JournalLevel.info,
  ]) {
    final job = _taskById(jobId);
    if (job == null) {
      return;
    }
    final entry = JournalEntry(
      at: DateTime.now(),
      level: level,
      message: scrubSecrets(message),
    );
    final journal = [...job.journal, entry];
    if (journal.length > 200) {
      journal.removeRange(0, journal.length - 200);
    }
    _updateTask(job.copyWith(journal: journal));
    unawaited(jobRepository.appendJournal(jobId, entry));
    _notify();
  }

  void _persistSoon() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() async {
    if (_persisting) {
      _persistQueued = true;
      return;
    }
    _persisting = true;
    try {
      await jobRepository.saveJobs(_jobs);
      await jobRepository.saveRecords(_records);
    } finally {
      _persisting = false;
      if (_persistQueued) {
        _persistQueued = false;
        unawaited(_persistNow());
      }
    }
  }

  void _notify([bool immediate = false]) {
    if (_disposed) {
      return;
    }
    if (immediate) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      notifyListeners();
      return;
    }
    if (_notifyTimer?.isActive ?? false) {
      return;
    }
    _notifyTimer = Timer(const Duration(milliseconds: 120), () {
      _notifyTimer = null;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduler?.cancel();
    _persistTimer?.cancel();
    _notifyTimer?.cancel();
    for (final token in _tokens.values) {
      token.cancel();
    }
    super.dispose();
  }
}

Future<void> ensureParent(String path) async {
  final directory = Directory(p.dirname(path));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
}

void _revealFolder(String path) {
  try {
    if (Platform.isWindows) {
      Process.run('explorer', ['/select,$path']);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [p.dirname(path)]);
    }
  } on ProcessException {
    // Opening a folder must never fail a completed download.
  }
}
