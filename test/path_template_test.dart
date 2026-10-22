import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/domain/preferences.dart';
import 'package:nexus_video/core/pathing/path_template.dart';

void main() {
  final context = PathFields(
    title: '标题',
    trackTitle: '第一集',
    trackNo: 1,
    ext: 'mp4',
    bvid: 'BV1xx411c7mD',
    aid: 170001,
    cid: 123,
    creator: 'UP',
    creatorId: 42,
    series: '系列',
    episodeNo: 2,
    collection: '收藏夹',
    index: 3,
    quality: '80',
    codec: 'AVC',
    date: DateTime(2026, 10, 21),
    publishDate: '2024-05-06',
  );

  test('renders variables and dates', () {
    expect(
      renderPathTemplate('{title}-{bvid}-{quality_name}', context),
      '标题-BV1xx411c7mD-1080P',
    );
    expect(renderPathTemplate('{date:%Y%m%d}', context), '20261021');
    expect(
      renderPathTemplate('{publish_date:%Y.%m.%d}', context),
      '2024.05.06',
    );
  });

  test('renders a safe relative output path', () {
    final path = composeRelativePath(
      '{title}/{track_no} - {track_title}',
      context,
    );
    expect(path, contains('标题'));
    expect(path, endsWith('.mp4'));
    expect(path.split(RegExp(r'[/\\]')).length, greaterThanOrEqualTo(2));
  });

  test('rejects malformed templates', () {
    expect(() => validatePathTemplate('{title'), throwsFormatException);
    expect(() => validatePathTemplate('title}'), throwsFormatException);
    expect(() => validatePathTemplate('{unknown}'), throwsFormatException);
  });

  test('sanitizes illegal characters and windows reserved names', () {
    expect(cleanPathSegment('a:b*c?d'), 'a_b_c_d');
    expect(cleanPathSegment('CON'), '_CON');
    expect(cleanPathSegment('nul.txt'), '_nul.txt');
    expect(cleanPathSegment('   ...   '), 'untitled');
  });

  test('truncates very long names without exceeding byte budget', () {
    final long = '汉' * 400;
    final sanitized = cleanPathSegment(long);
    expect(utf8.encode(sanitized).length, lessThanOrEqualTo(180));
    expect(sanitized, contains('~'));
  });

  test('prevents traversal outside the download root', () {
    final path = composeRelativePath('../../{title}', context);
    expect(path.startsWith('..'), isFalse);
    expect(path.contains('..${Platform.pathSeparator}'), isFalse);
  });

  test('appends a counter for duplicate names', () {
    final dir = Directory.systemTemp.createTempSync('nexus-naming-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final original = File('${dir.path}${Platform.pathSeparator}video.mp4')
      ..writeAsStringSync('x');
    final reserved = <String>{};
    final resolved = resolveDuplicatePath(
      original.path,
      reserved,
      CollisionPolicy.append,
      exists: original.existsSync(),
    );
    expect(resolved, isNot(original.path));
    expect(resolved, contains('video (1)'));
  });

  test('skip policy keeps an existing path', () {
    final reserved = <String>{};
    const path = '/tmp/media/video.mp4';
    expect(
      resolveDuplicatePath(path, reserved, CollisionPolicy.skip, exists: true),
      path,
    );
  });
}
