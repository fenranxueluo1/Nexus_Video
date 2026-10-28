import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../api/service_exception.dart';
import '../domain/output_profile.dart';
import '../util/platform_support.dart';
import '../util/task_token.dart';

class PackagerProbe {
  const PackagerProbe({
    required this.available,
    required this.path,
    this.version = '',
    this.error,
  });

  final bool available;
  final String path;
  final String version;
  final String? error;
}

class MediaPackager {
  MediaPackager({String packagerPath = ''}) {
    _ffmpegPath = packagerPath.trim();
  }

  static const MethodChannel _systemMuxChannel = MethodChannel(
    'nexus/media_packager',
  );

  String _ffmpegPath = '';

  String get packagerPath => _ffmpegPath;

  set packagerPath(String value) => _ffmpegPath = value.trim();

  Future<PackagerProbe> probe() async {
    if (isHarmony) {
      return const PackagerProbe(
        available: false,
        path: 'HarmonyOS',
        error: '鸿蒙端暂不支持独立音视频合并，请使用可直接下载的合并流。',
      );
    }
    if (Platform.isIOS || Platform.isAndroid) {
      final label = Platform.isIOS ? 'AVFoundation' : 'Android MediaMuxer';
      return PackagerProbe(available: true, path: label, version: label);
    }
    final executable = await _resolveExecutable();
    try {
      final process = await Process.start(executable, [
        '-version',
      ], runInShell: false);
      final output = StringBuffer();
      final errors = StringBuffer();
      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .forEach(output.write);
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .forEach(errors.write);
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await Future.wait([stdoutDone, stderrDone]);
      if (exitCode != 0) {
        return PackagerProbe(
          available: false,
          path: executable,
          error: errors.toString().trim().isEmpty
              ? 'FFmpeg 退出码 $exitCode'
              : errors.toString().trim(),
        );
      }
      final firstLine = output
          .toString()
          .split(RegExp(r'\r?\n'))
          .firstWhere(
            (line) => line.trim().isNotEmpty,
            orElse: () => 'ffmpeg version unknown',
          );
      return PackagerProbe(
        available: true,
        path: executable,
        version: firstLine.trim(),
      );
    } on ProcessException catch (error) {
      return PackagerProbe(
        available: false,
        path: executable,
        error: '无法启动 FFmpeg：${error.message}。请安装 FFmpeg 或在设置中指定路径。',
      );
    } on TimeoutException {
      return PackagerProbe(
        available: false,
        path: executable,
        error: 'FFmpeg 响应超时。',
      );
    }
  }

  Future<void> assemble({
    required String destination,
    required OutputContainer container,
    String? videoPath,
    String? audioPath,
    List<String> captionFiles = const [],
    String? artworkPath,
    bool embedArtwork = false,
    bool embedCaptions = false,
    bool dropAudio = false,
    TaskToken? token,
    void Function(String line)? onLog,
  }) async {
    token?.throwIfCancelled();
    if (videoPath == null && audioPath == null) {
      throw const ApiException('没有可合并的音视频流。');
    }
    if (isHarmony) {
      throw const ApiException(
        '鸿蒙端暂不支持独立音视频合并，请使用可直接下载的合并流。',
      );
    }
    if (Platform.isIOS || Platform.isAndroid) {
      if (embedArtwork || embedCaptions) {
        throw const ApiException('当前移动平台暂不支持封面或字幕嵌入。');
      }
      await _assembleWithSystemMuxer(
        destination: destination,
        container: container,
        videoPath: videoPath,
        audioPath: audioPath,
        dropAudio: dropAudio,
        token: token,
        onLog: onLog,
      );
      return;
    }
    final executable = await _resolveExecutable();
    final outputDirectory = p.dirname(destination);
    await Directory(outputDirectory).create(recursive: true);
    final tempOutput = p.join(
      outputDirectory,
      '.nexus-assemble-${DateTime.now().microsecondsSinceEpoch}${p.extension(destination)}',
    );

    final args = <String>[
      '-y',
      '-nostdin',
      '-hide_banner',
      '-loglevel',
      'error',
      '-progress',
      'pipe:1',
    ];
    final inputs = <String>[];
    int? videoIndex;
    int? audioIndex;
    final captionIndices = <int>[];

    if (videoPath != null) {
      videoIndex = inputs.length;
      inputs.add(videoPath);
    }
    if (audioPath != null) {
      audioIndex = inputs.length;
      inputs.add(audioPath);
    }
    final embedSubs =
        embedCaptions &&
        container == OutputContainer.mkv &&
        captionFiles.isNotEmpty;
    if (embedSubs) {
      for (final caption in captionFiles) {
        captionIndices.add(inputs.length);
        inputs.add(caption);
      }
    }
    for (final input in inputs) {
      args.addAll(['-i', input]);
    }

    final mkv = container == OutputContainer.mkv;
    if (videoIndex != null) {
      args.addAll(['-map', '$videoIndex:v:0']);
    }
    if (audioIndex != null) {
      args.addAll(['-map', '$audioIndex:a:0']);
    } else if (videoIndex != null && !dropAudio) {
      args.addAll(['-map', '$videoIndex:a?']);
    }
    for (var index = 0; index < captionIndices.length; index += 1) {
      args.addAll(['-map', '${captionIndices[index]}:s:0']);
      args.addAll(['-metadata:s:s:$index', 'language=chi']);
    }
    if (embedArtwork && mkv && artworkPath != null) {
      args.addAll([
        '-attach',
        artworkPath,
        '-metadata:s:t',
        'mimetype=image/jpeg',
        '-metadata:s:t',
        'filename=cover.jpg',
      ]);
    }

    if (videoIndex != null && audioIndex != null) {
      args.addAll(['-c', 'copy']);
      if (embedSubs) {
        args.addAll(['-c:s', 'srt']);
      }
    } else if (audioIndex != null) {
      if (container == OutputContainer.mp3) {
        args.addAll(['-vn', '-c:a', 'libmp3lame', '-b:a', '192k']);
      } else if (container == OutputContainer.flac) {
        args.addAll(['-vn', '-c:a', 'flac']);
      } else {
        args.addAll(['-vn', '-c:a', 'copy']);
      }
    } else {
      if (dropAudio) {
        args.add('-an');
      }
      args.addAll(['-c', 'copy']);
    }

    args.add(tempOutput);

    onLog?.call('FFmpeg ${args.join(' ')}');
    final process = await Process.start(executable, args, runInShell: false);
    final stderrLines = <String>[];
    var cancelled = false;
    Timer? watchdog;
    void resetWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 120), () {
        process.kill(ProcessSignal.sigkill);
      });
    }

    resetWatchdog();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.trim().isEmpty) {
            return;
          }
          stderrLines.add(line);
          if (stderrLines.length > 60) {
            stderrLines.removeAt(0);
          }
          onLog?.call(line);
          resetWatchdog();
        });
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.trim().isNotEmpty) {
            resetWatchdog();
          }
        });
    token?.onCancel(() {
      cancelled = true;
      process.kill(ProcessSignal.sigkill);
    });

    int exitCode;
    try {
      exitCode = await process.exitCode;
    } finally {
      watchdog?.cancel();
      await Future.wait([stderrDone, stdoutDone]);
    }

    if (cancelled || (token?.isCancelled ?? false)) {
      if (await File(tempOutput).exists()) {
        await File(tempOutput).delete();
      }
      throw const TaskAborted();
    }
    if (exitCode != 0) {
      if (await File(tempOutput).exists()) {
        await File(tempOutput).delete();
      }
      final detail = stderrLines.isEmpty ? '未知错误' : stderrLines.join('\n');
      throw ApiException('FFmpeg 合并失败（退出码 $exitCode）：$detail');
    }
    final tempFile = File(tempOutput);
    if (!await tempFile.exists() || await tempFile.length() == 0) {
      throw const ApiException('FFmpeg 没有生成输出文件，请检查视频流是否完整。');
    }
    final target = File(destination);
    if (await target.exists()) {
      await target.delete();
    }
    await tempFile.rename(destination);
  }

  Future<void> _assembleWithSystemMuxer({
    required String destination,
    required OutputContainer container,
    String? videoPath,
    String? audioPath,
    bool dropAudio = false,
    TaskToken? token,
    void Function(String line)? onLog,
  }) async {
    if (container != OutputContainer.mp4 && container != OutputContainer.m4a) {
      throw ApiException('移动端目前只支持合并为 MP4 或 M4A，当前为 ${container.label}。');
    }
    final outputDirectory = p.dirname(destination);
    await Directory(outputDirectory).create(recursive: true);
    final tempOutput = p.join(
      outputDirectory,
      '.nexus-assemble-${DateTime.now().microsecondsSinceEpoch}${p.extension(destination)}',
    );
    final muxerName = Platform.isIOS ? 'AVFoundation' : 'MediaMuxer';
    onLog?.call('$muxerName 合并音视频');
    try {
      await _systemMuxChannel.invokeMethod<void>('mux', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': tempOutput,
        'dropAudio': dropAudio,
      });
    } on PlatformException catch (error) {
      await _deleteIfExists(tempOutput);
      throw ApiException('系统媒体合并失败：${error.message ?? error.code}');
    } on MissingPluginException {
      await _deleteIfExists(tempOutput);
      throw const ApiException('当前移动端构建未注册系统媒体合并通道，请重新构建应用。');
    } on Object catch (error) {
      await _deleteIfExists(tempOutput);
      throw ApiException('系统媒体合并失败：$error');
    }
    if (token?.isCancelled ?? false) {
      await _deleteIfExists(tempOutput);
      throw const TaskAborted();
    }
    token?.throwIfCancelled();
    final tempFile = File(tempOutput);
    if (!await tempFile.exists() || await tempFile.length() == 0) {
      await _deleteIfExists(tempOutput);
      throw const ApiException('系统媒体框架没有生成输出文件，请检查输入流是否完整。');
    }
    final target = File(destination);
    if (await target.exists()) {
      await target.delete();
    }
    await tempFile.rename(destination);
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> _resolveExecutable() async {
    final configured = _ffmpegPath.trim();
    if (configured.isNotEmpty) {
      final file = File(configured);
      if (await file.exists()) {
        if (Platform.isWindows && !configured.toLowerCase().endsWith('.exe')) {
          throw ApiException('Windows 上只能使用 ffmpeg.exe，已拒绝执行 `$configured`。');
        }
        return configured;
      }
      if (!configured.contains('/') && !configured.contains('\\')) {
        return configured;
      }
      throw ApiException('找不到 FFmpeg 可执行文件：$configured');
    }
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final bundled = await findBundledFfmpeg(Platform.resolvedExecutable);
      if (bundled != null) {
        return bundled;
      }
    }
    try {
      final result = Platform.isWindows
          ? await Process.run('where', ['ffmpeg'])
          : await Process.run('which', ['ffmpeg']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        for (final line in lines) {
          if (Platform.isWindows) {
            if (line.toLowerCase().endsWith('.exe')) {
              return line;
            }
          } else {
            return line;
          }
        }
      }
    } on ProcessException {
      // Fall through to common install locations and the bare command name.
    }
    final candidates = <String>[
      if (Platform.isMacOS) ...[
        '/opt/homebrew/bin/ffmpeg',
        '/usr/local/bin/ffmpeg',
        '/usr/bin/ffmpeg',
      ],
      if (Platform.isLinux) ...[
        '/usr/bin/ffmpeg',
        '/usr/local/bin/ffmpeg',
        '/snap/bin/ffmpeg',
      ],
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return 'ffmpeg';
  }
}

Future<String?> findBundledFfmpeg(String executablePath) async {
  final base = File(executablePath).parent.path;
  final names = Platform.isWindows ? const ['ffmpeg.exe'] : const ['ffmpeg'];
  for (final name in names) {
    final candidates = <String>[
      p.join(base, 'ffmpeg', name),
      p.join(base, name),
      p.join(base, 'ffmpeg', 'bin', name),
      p.join(base, 'bin', name),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
  }
  return null;
}
