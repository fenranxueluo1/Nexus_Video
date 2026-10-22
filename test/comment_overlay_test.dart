import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/postprocess/comment_overlay.dart';

void main() {
  const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<i>
  <d p="1.5,1,25,16777215,1700000000,0,abc,1">Hello &amp; hi</d>
  <d p="2.0,5,25,16711680,1700000001,0,def,2">顶部弹幕</d>
  <d p="3.0,7,25,255,1700000002,0,ghi,3">高级弹幕</d>
  <d p="4.0,4,25,65280,1700000003,0,jkl,4">底部弹幕</d>
</i>''';

  test('parses xml entries and decodes entities', () {
    final items = readCommentOverlay(xml);
    expect(items, hasLength(4));
    expect(items.first.text, 'Hello & hi');
    expect(items.first.time, 1.5);
    expect(items[1].mode, 5);
  });

  test('converts supported danmaku to srt', () {
    final items = readCommentOverlay(xml);
    final srt = overlayToSrt(items);
    expect(srt, contains('00:00:01,500 --> 00:00:05,500'));
    expect(srt, contains('Hello & hi'));
    expect(srt, contains('顶部弹幕'));
    expect(srt, isNot(contains('高级弹幕')));
  });

  test('converts to ass with positioned dialogue', () {
    final items = readCommentOverlay(xml);
    final ass = overlayToAss(items);
    expect(ass, contains('[Script Info]'));
    expect(ass, contains('\\move(1920,'));
    expect(ass, contains('\\an8'));
    expect(ass, contains('\\an2'));
  });

  test('renders a standalone html replay', () {
    final items = readCommentOverlay(xml);
    final html = overlayToHtml(items, videoFileName: 'video.mp4', title: '示例');
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('video.mp4'));
    expect(html, contains('Hello & hi'));
    expect(html, contains('requestAnimationFrame'));
  });

  test('ignores malformed xml', () {
    expect(readCommentOverlay('<not xml'), isEmpty);
  });
}
