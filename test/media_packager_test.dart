import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/postprocess/media_packager.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexus-ffmpeg-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('优先查找 ffmpeg 子目录中的 ffmpeg.exe', () async {
    final app = Directory(p.join(root.path, 'app'))
      ..createSync(recursive: true);
    final bundled = Directory(p.join(app.path, 'ffmpeg'))
      ..createSync(recursive: true);
    final executable = File(p.join(bundled.path, 'ffmpeg.exe'))
      ..writeAsStringSync('');

    expect(
      await findBundledFfmpeg(p.join(app.path, 'nexus.exe')),
      executable.path,
    );
  });

  test('支持直接放在程序目录的 ffmpeg.exe', () async {
    final app = Directory(p.join(root.path, 'app'))
      ..createSync(recursive: true);
    final executable = File(p.join(app.path, 'ffmpeg.exe'))
      ..writeAsStringSync('');

    expect(
      await findBundledFfmpeg(p.join(app.path, 'nexus.exe')),
      executable.path,
    );
  });

  test('支持 bin 子目录布局', () async {
    final app = Directory(p.join(root.path, 'app'))
      ..createSync(recursive: true);
    final bundled = Directory(p.join(app.path, 'ffmpeg', 'bin'))
      ..createSync(recursive: true);
    final executable = File(p.join(bundled.path, 'ffmpeg.exe'))
      ..writeAsStringSync('');

    expect(
      await findBundledFfmpeg(p.join(app.path, 'nexus.exe')),
      executable.path,
    );
  });

  test('没有内置 FFmpeg 时返回 null', () async {
    final app = Directory(p.join(root.path, 'app'))
      ..createSync(recursive: true);

    expect(await findBundledFfmpeg(p.join(app.path, 'nexus.exe')), isNull);
  });
}
