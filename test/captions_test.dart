import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/postprocess/captions.dart';

void main() {
  const json =
      '{"body":['
      '{"from":1.25,"to":3.5,"content":"第一句"},'
      '{"from":4.0,"to":6.0,"content":"第二句\\n换行"}'
      ']}';

  test('parses subtitle json cues', () {
    final cues = readCaptionJson(json);
    expect(cues, hasLength(2));
    expect(cues.first.content, '第一句');
    expect(cues.last.to, 6.0);
  });

  test('renders srt with correct timestamps', () {
    final srt = captionsToSrt(readCaptionJson(json));
    expect(srt, contains('00:00:01,250 --> 00:00:03,500'));
    expect(srt, contains('第二句 换行'));
  });

  test('returns empty for invalid data', () {
    expect(readCaptionJson('not json'), isEmpty);
    expect(readCaptionJson(jsonEncode({'body': 'nope'})), isEmpty);
  });
}
