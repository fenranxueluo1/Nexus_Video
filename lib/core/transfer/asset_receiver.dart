import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../api/service_exception.dart';
import '../api/bili_transport.dart';
import '../domain/jobs.dart';
import '../util/task_token.dart';
import '../util/durable_json.dart';
import 'resume_ledger.dart';
import 'throughput_governor.dart';

typedef ReceiveProgress = void Function(int downloaded, int? total);

class ReceiveResult {
  const ReceiveResult({required this.bytes, required this.destinationPath});

  final int bytes;
  final String destinationPath;
}

class AssetReceiver {
  AssetReceiver(
    this.http, {
    required this.retryLimit,
    required this.parallelSegments,
    this.globalLimiter,
  });

  final BiliTransport http;
  int retryLimit;
  int parallelSegments;
  ThroughputGovernor? globalLimiter;

  static const Duration _idleTimeout = Duration(seconds: 35);
  static const Duration _connectTimeout = Duration(seconds: 20);

  Future<ReceiveResult> receive({
    required JobAsset asset,
    required TaskToken token,
    ReceiveProgress? onProgress,
    ThroughputGovernor? taskLimiter,
  }) async {
    final urls = asset.urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      throw const ApiException('资源没有可用资源地址，请重新解析后再试。');
    }
    ApiException? lastError;
    for (var attempt = 0; attempt <= retryLimit; attempt += 1) {
      token.throwIfCancelled();
      var retryable = false;
      for (final url in urls) {
        token.throwIfCancelled();
        try {
          return await _fetchOnce(
            asset: asset,
            url: url,
            token: token,
            onProgress: onProgress,
            taskLimiter: taskLimiter,
            allowRestart: true,
          );
        } on TaskAborted {
          rethrow;
        } on ApiException catch (error) {
          lastError = error;
          if (_isRetryable(error)) {
            retryable = true;
          }
        } on FileSystemException catch (error) {
          throw ApiException(
            '写入文件失败：${error.message}（${error.path ?? asset.destinationPath}）',
          );
        }
      }
      if (!retryable) {
        break;
      }
      if (attempt < retryLimit) {
        await _backoff(attempt);
      }
    }
    throw lastError ?? const ApiException('任务失败，请重试。');
  }

  Future<void> receiveSmall({
    required List<String> urls,
    required String destinationPath,
    required TaskToken token,
    Map<String, String> headers = const {},
    int maxBytes = 64 * 1024 * 1024,
  }) async {
    final candidates = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (candidates.isEmpty) {
      throw const ApiException('资源没有可用资源地址。');
    }
    ApiException? lastError;
    for (var attempt = 0; attempt <= retryLimit; attempt += 1) {
      token.throwIfCancelled();
      var retryable = false;
      for (final url in candidates) {
        try {
          final bytes = await http.getBytes(
            Uri.parse(url),
            headers: {
              'User-Agent': biliUserAgent,
              'Referer': 'https://www.bilibili.com/',
              'Accept-Encoding': 'identity',
              ...headers,
            },
            maxBytes: maxBytes,
          );
          token.throwIfCancelled();
          await ensureParentDirectory(destinationPath);
          final temp = File('$destinationPath.track');
          await temp.writeAsBytes(bytes, flush: true);
          final target = File(destinationPath);
          if (await target.exists()) {
            await target.delete();
          }
          await temp.rename(destinationPath);
          return;
        } on TaskAborted {
          rethrow;
        } on ApiException catch (error) {
          lastError = error;
          if (_isRetryable(error)) {
            retryable = true;
          }
        } on FileSystemException catch (error) {
          throw ApiException('写入文件失败：${error.message}');
        }
      }
      if (!retryable) {
        break;
      }
      if (attempt < retryLimit) {
        await _backoff(attempt);
      }
    }
    throw lastError ?? const ApiException('任务失败，请重试。');
  }

  Future<ReceiveResult> _fetchOnce({
    required JobAsset asset,
    required String url,
    required TaskToken token,
    required ReceiveProgress? onProgress,
    required ThroughputGovernor? taskLimiter,
    required bool allowRestart,
  }) async {
    token.throwIfCancelled();
    await ensureParentDirectory(asset.destinationPath);
    await ensureParentDirectory(asset.scratchPath);
    final headers = _mediaHeaders(asset);
    final uri = Uri.parse(url);

    final metadata = await _probe(uri, headers, token);
    final total = metadata.expectedBytes;
    final compressed =
        metadata.contentEncoding != null &&
        metadata.contentEncoding!.isNotEmpty &&
        metadata.contentEncoding != 'identity';
    final useSegments =
        !compressed &&
        total != null &&
        total > 1 &&
        parallelSegments > 1 &&
        metadata.acceptRanges;

    if (useSegments) {
      return _fetchSegmented(
        asset: asset,
        uri: uri,
        headers: headers,
        metadata: metadata,
        token: token,
        onProgress: onProgress,
        taskLimiter: taskLimiter,
      );
    }
    return _fetchSingle(
      asset: asset,
      uri: uri,
      headers: headers,
      metadata: metadata,
      token: token,
      onProgress: onProgress,
      taskLimiter: taskLimiter,
      allowRestart: allowRestart,
    );
  }

  Future<RemoteFacts> _probe(
    Uri uri,
    Map<String, String> headers,
    TaskToken token,
  ) async {
    try {
      final request = await http.open('HEAD', uri, headers: headers);
      request.followRedirects = true;
      token.onCancel(() {
        try {
          request.abort();
        } catch (_) {}
      });
      final response = await http.response(request, timeout: _connectTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _metadataFromHeaders(response.headers, null);
      }
    } on SocketException catch (error) {
      throw ApiException('连接资源服务器失败：${error.message}');
    }

    // 部分 CDN 节点（如 B 站 PCDN 镜像）对 HEAD 返回 404，但 GET 正常。
    token.throwIfCancelled();
    final request = await http.open(
      'GET',
      uri,
      headers: {...headers, 'Range': 'bytes=0-0'},
    );
    request.followRedirects = true;
    token.onCancel(() {
      try {
        request.abort();
      } catch (_) {}
    });
    final response = await http.response(request, timeout: _connectTimeout);
    if (response.statusCode == 206) {
      return _metadataFromHeaders(
        response.headers,
        response.headers.value('content-range'),
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _metadataFromHeaders(response.headers, null);
    }
    throw ApiException(
      '资源地址不可用：HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  RemoteFacts _metadataFromHeaders(HttpHeaders headers, String? contentRange) {
    final totalFromRange = _contentRangeTotal(contentRange);
    final contentLength = int.tryParse(headers.value('content-length') ?? '');
    final acceptRanges = (headers.value('accept-ranges') ?? '')
        .toLowerCase()
        .contains('bytes');
    return RemoteFacts(
      expectedBytes: totalFromRange ?? contentLength,
      etag: headers.value('etag'),
      lastModified: headers.value('last-modified'),
      contentEncoding: headers.value('content-encoding')?.toLowerCase(),
      acceptRanges: acceptRanges || contentRange != null,
    );
  }

  Future<ReceiveResult> _fetchSingle({
    required JobAsset asset,
    required Uri uri,
    required Map<String, String> headers,
    required RemoteFacts metadata,
    required TaskToken token,
    required ReceiveProgress? onProgress,
    required ThroughputGovernor? taskLimiter,
    required bool allowRestart,
  }) async {
    final statePath = statePathFor(asset.scratchPath);
    final tempFile = File(asset.scratchPath);
    final state = await readResumeLedger(statePath);
    final tempLength = await tempFile.exists() ? await tempFile.length() : 0;

    var resumeFrom = 0;
    if (state != null &&
        tempLength > 0 &&
        tempLength == state.receivedBytes &&
        (metadata.expectedBytes == null ||
            metadata.expectedBytes == state.expectedBytes) &&
        validatorsMatch(state.etag, metadata.etag) &&
        validatorsMatch(state.lastModified, metadata.lastModified)) {
      resumeFrom = tempLength;
    } else {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (await File(statePath).exists()) {
        await File(statePath).delete();
      }
    }

    token.throwIfCancelled();
    final request = await http.open(
      'GET',
      uri,
      headers: {...headers, if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-'},
    );
    request.followRedirects = true;
    token.onCancel(() {
      try {
        request.abort();
      } catch (_) {}
    });

    HttpClientResponse response;
    try {
      response = await request.close().timeout(_connectTimeout);
    } on TimeoutException {
      try {
        request.abort();
      } catch (_) {}
      throw const ApiException('连接资源服务器超时。');
    }

    if (resumeFrom > 0 &&
        (response.statusCode == 200 || response.statusCode == 416)) {
      await response.drain<void>();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (await File(statePath).exists()) {
        await File(statePath).delete();
      }
      if (allowRestart) {
        return _fetchSingle(
          asset: asset,
          uri: uri,
          headers: headers,
          metadata: metadata,
          token: token,
          onProgress: onProgress,
          taskLimiter: taskLimiter,
          allowRestart: false,
        );
      }
      throw ApiException(
        '服务器拒绝了断点续传：HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 206) {
      final rangeStart = _contentRangeStart(
        response.headers.value('content-range'),
      );
      if (rangeStart != null && rangeStart != resumeFrom) {
        await response.drain<void>();
        throw ApiException(
          '服务器返回了错误的分段起点（期望 $resumeFrom，实际 $rangeStart），已停止以保护文件。',
        );
      }
    } else if (response.statusCode >= 300 || response.statusCode < 200) {
      await response.drain<void>();
      throw ApiException(
        '任务失败：HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    var downloaded = resumeFrom;
    final throttler = RateGate(const Duration(milliseconds: 120));
    final stateWriter = _StateWriter(statePath);
    RandomAccessFile? file;
    try {
      file = await tempFile.open(
        mode: resumeFrom > 0 ? FileMode.append : FileMode.write,
      );
      await for (final chunk in response.timeout(_idleTimeout)) {
        token.throwIfCancelled();
        await _limit(chunk.length, token, taskLimiter);
        await file.writeFrom(chunk);
        downloaded += chunk.length;
        final total = metadata.expectedBytes;
        if (total != null && downloaded > total) {
          throw const ApiException('服务器返回的数据超过声明长度，已接收停止。');
        }
        await stateWriter.maybeWrite(
          ResumeLedger(
            expectedBytes: total ?? downloaded,
            receivedBytes: downloaded,
            parallelSegments: 1,
            ranges: total == null ? const [] : computeByteRanges(total, 1),
            etag: metadata.etag,
            lastModified: metadata.lastModified,
          ),
        );
        if (throttler.ready) {
          onProgress?.call(downloaded, total);
        }
      }
      await file.flush();
    } on TaskAborted {
      rethrow;
    } on TimeoutException {
      throw const ApiException('接收长时间没有数据，请检查网络后重试。');
    } on Object catch (error) {
      if (token.isCancelled) {
        throw const TaskAborted();
      }
      if (error is ApiException || error is FileSystemException) {
        rethrow;
      }
      throw ApiException('进行中断：$error');
    } finally {
      await file?.close();
    }

    final expected = metadata.expectedBytes;
    if (expected != null && downloaded != expected) {
      await stateWriter.flush(
        ResumeLedger(
          expectedBytes: expected,
          receivedBytes: downloaded,
          parallelSegments: 1,
          ranges: computeByteRanges(expected, 1),
          etag: metadata.etag,
          lastModified: metadata.lastModified,
        ),
      );
      throw ApiException('任务长度不完整：期望 $expected 字节，实际 $downloaded 字节。');
    }

    await _publish(asset.scratchPath, asset.destinationPath);
    if (await File(statePath).exists()) {
      await File(statePath).delete();
    }
    onProgress?.call(downloaded, expected ?? downloaded);
    return ReceiveResult(
      bytes: downloaded,
      destinationPath: asset.destinationPath,
    );
  }

  Future<ReceiveResult> _fetchSegmented({
    required JobAsset asset,
    required Uri uri,
    required Map<String, String> headers,
    required RemoteFacts metadata,
    required TaskToken token,
    required ReceiveProgress? onProgress,
    required ThroughputGovernor? taskLimiter,
  }) async {
    final total = metadata.expectedBytes!;
    final ranges = computeByteRanges(total, parallelSegments);
    final statePath = statePathFor(asset.scratchPath);
    final state = await readResumeLedger(statePath);
    final canResume =
        state != null &&
        stateMatches(state, metadata, parallelSegments, ranges);

    if (!canResume) {
      for (var index = 0; index < 8; index += 1) {
        final segment = File(segmentPathFor(asset.scratchPath, index));
        if (await segment.exists()) {
          await segment.delete();
        }
      }
      if (await File(asset.scratchPath).exists()) {
        await File(asset.scratchPath).delete();
      }
      if (await File(statePath).exists()) {
        await File(statePath).delete();
      }
    }

    final lengths = <int>[];
    for (var index = 0; index < ranges.length; index += 1) {
      final segment = File(segmentPathFor(asset.scratchPath, index));
      var length = await segment.exists() ? await segment.length() : 0;
      if (length > ranges[index].length) {
        await segment.delete();
        length = 0;
      }
      lengths.add(length);
    }

    final writer = _StateWriter(statePath);
    final progressRateGate = RateGate(const Duration(milliseconds: 120));
    var lastProgressAt = DateTime.now();

    Future<void> reportProgress() async {
      if (!progressRateGate.ready &&
          DateTime.now().difference(lastProgressAt) <
              const Duration(milliseconds: 250)) {
        return;
      }
      lastProgressAt = DateTime.now();
      onProgress?.call(lengths.fold(0, (sum, value) => sum + value), total);
    }

    await writer.flush(
      ResumeLedger(
        expectedBytes: total,
        receivedBytes: lengths.fold(0, (sum, value) => sum + value),
        parallelSegments: parallelSegments,
        ranges: ranges,
        etag: metadata.etag,
        lastModified: metadata.lastModified,
      ),
    );
    unawaited(reportProgress());

    await Future.wait(
      ranges.asMap().entries.map((entry) async {
        final index = entry.key;
        final range = entry.value;
        final segmentPath = segmentPathFor(asset.scratchPath, index);
        var existing = lengths[index];
        while (existing < range.length) {
          token.throwIfCancelled();
          final requestStart = range.start + existing;
          final request = await http.open(
            'GET',
            uri,
            headers: {...headers, 'Range': 'bytes=$requestStart-${range.end}'},
          );
          request.followRedirects = true;
          token.onCancel(() {
            try {
              request.abort();
            } catch (_) {}
          });
          HttpClientResponse response;
          try {
            response = await request.close().timeout(_connectTimeout);
          } on TimeoutException {
            try {
              request.abort();
            } catch (_) {}
            throw const ApiException('连接资源服务器超时。');
          }
          if (response.statusCode != 206) {
            await response.drain<void>();
            throw ApiException(
              '分段任务失败：HTTP ${response.statusCode}',
              statusCode: response.statusCode,
            );
          }
          final rangeStart = _contentRangeStart(
            response.headers.value('content-range'),
          );
          if (rangeStart != null && rangeStart != requestStart) {
            await response.drain<void>();
            throw ApiException(
              '服务器返回的分段起点错误（期望 $requestStart，实际 $rangeStart）。',
            );
          }
          final segmentFile = File(segmentPath);
          final file = await segmentFile.open(
            mode: existing > 0 ? FileMode.append : FileMode.write,
          );
          try {
            await for (final chunk in response.timeout(_idleTimeout)) {
              token.throwIfCancelled();
              await _limit(chunk.length, token, taskLimiter);
              await file.writeFrom(chunk);
              existing += chunk.length;
              if (existing > range.length) {
                throw const ApiException('服务器返回的分段数据超过期望长度，已接收停止。');
              }
              lengths[index] = existing;
              await writer.maybeWrite(
                ResumeLedger(
                  expectedBytes: total,
                  receivedBytes: lengths.fold(0, (sum, value) => sum + value),
                  parallelSegments: parallelSegments,
                  ranges: ranges,
                  etag: metadata.etag,
                  lastModified: metadata.lastModified,
                ),
              );
              if (progressRateGate.ready) {
                await reportProgress();
              }
            }
            await file.flush();
          } on TaskAborted {
            rethrow;
          } on TimeoutException {
            throw const ApiException('分段任务长时间没有数据，请检查网络后重试。');
          } on Object catch (error) {
            if (token.isCancelled) {
              throw const TaskAborted();
            }
            if (error is ApiException || error is FileSystemException) {
              rethrow;
            }
            throw ApiException('分段进行中断：$error');
          } finally {
            await file.close();
          }
        }
        lengths[index] = range.length;
      }),
    );

    token.throwIfCancelled();
    final actualTotal = lengths.fold(0, (sum, value) => sum + value);
    if (actualTotal != total) {
      throw ApiException('分段任务未完成：期望 $total 字节，实际 $actualTotal 字节。');
    }

    final concat = File('${asset.scratchPath}.concat');
    if (await concat.exists()) {
      await concat.delete();
    }
    final output = await concat.open(mode: FileMode.write);
    try {
      for (var index = 0; index < ranges.length; index += 1) {
        final segment = File(segmentPathFor(asset.scratchPath, index));
        final input = await segment.open();
        try {
          var copied = 0;
          while (true) {
            final chunk = await input.read(1024 * 1024);
            if (chunk.isEmpty) {
              break;
            }
            copied += chunk.length;
            await output.writeFrom(chunk);
          }
          if (copied != ranges[index].length) {
            throw ApiException(
              '分段文件长度异常：第 ${index + 1} 段期望 ${ranges[index].length} 字节，实际 $copied 字节。',
            );
          }
        } finally {
          await input.close();
        }
      }
      await output.flush();
    } finally {
      await output.close();
    }

    final tempFile = File(asset.scratchPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await concat.rename(asset.scratchPath);
    await _publish(asset.scratchPath, asset.destinationPath);
    for (var index = 0; index < ranges.length; index += 1) {
      final segment = File(segmentPathFor(asset.scratchPath, index));
      if (await segment.exists()) {
        await segment.delete();
      }
    }
    if (await File(statePath).exists()) {
      await File(statePath).delete();
    }
    onProgress?.call(total, total);
    return ReceiveResult(bytes: total, destinationPath: asset.destinationPath);
  }

  Map<String, String> _mediaHeaders(JobAsset asset) {
    return {
      'User-Agent': biliUserAgent,
      'Referer': 'https://www.bilibili.com/',
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      ...asset.headers,
    };
  }

  Future<void> _limit(
    int bytes,
    TaskToken token,
    ThroughputGovernor? taskLimiter,
  ) async {
    final limiters = <ThroughputGovernor>[];
    final global = globalLimiter;
    final job = taskLimiter;
    if (global != null && global.enabled) {
      limiters.add(global);
    }
    if (job != null && job.enabled && !identical(job, global)) {
      limiters.add(job);
    }
    if (limiters.isEmpty) {
      return;
    }
    token.throwIfCancelled();
    await Future.wait(limiters.map((limiter) => limiter.acquire(bytes, token)));
  }

  Future<void> _publish(String scratchPath, String destinationPath) async {
    final target = File(destinationPath);
    if (await target.exists()) {
      await target.delete();
    }
    await File(scratchPath).rename(destinationPath);
  }

  Future<void> _backoff(int attempt) async {
    final base = (300 * pow(2, attempt)).toInt().clamp(300, 8000);
    final jitter = Random().nextInt(250);
    await Future<void>.delayed(Duration(milliseconds: base + jitter));
  }

  bool _isRetryable(ApiException error) {
    final state = error.statusCode;
    if (state != null) {
      return state == 408 || state == 425 || state == 429 || state >= 500;
    }
    return true;
  }

  int? _contentRangeStart(String? value) {
    if (value == null) {
      return null;
    }
    final match = RegExp(r'bytes\s+(\d+)-(\d+)/').firstMatch(value);
    return int.tryParse(match?.group(1) ?? '');
  }

  int? _contentRangeTotal(String? value) {
    if (value == null) {
      return null;
    }
    final match = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(value);
    return int.tryParse(match?.group(1) ?? '');
  }
}

class _StateWriter {
  _StateWriter(this.path);

  final String path;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _tail = Future.value();

  Future<void> maybeWrite(ResumeLedger state) async {
    final now = DateTime.now();
    if (now.difference(_lastWrite) < const Duration(seconds: 1)) {
      return;
    }
    _lastWrite = now;
    await flush(state);
  }

  Future<void> flush(ResumeLedger state) {
    _tail = _tail
        .then((_) => writeResumeLedger(path, state))
        .catchError((_) {});
    return _tail;
  }
}
