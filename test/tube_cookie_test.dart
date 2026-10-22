import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/remote/tube_cookie.dart';

void main() {
  test('读取 YouTube Netscape Cookie 并忽略其他域名', () async {
    final directory = await Directory.systemTemp.createTemp('tube-cookie-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cookies.txt');
    await file.writeAsString(
      [
        '# Netscape HTTP Cookie File',
        '.youtube.com\tTRUE\t/\tTRUE\t1999999999\tSID\tabc123',
        '#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1999999999\tHSID\tdef456',
        '.googlevideo.com\tTRUE\t/\tTRUE\t1999999999\tTEST\tghi789',
        '.example.com\tTRUE\t/\tTRUE\t1999999999\tOTHER\tignored',
        '',
      ].join('\n'),
    );

    final header = readTubeCookieHeader(file.path);
    expect(header, contains('SID=abc123'));
    expect(header, contains('HSID=def456'));
    expect(header, contains('TEST=ghi789'));
    expect(header, isNot(contains('OTHER')));
  });

  test('空路径和不存在文件返回空 Cookie', () {
    expect(readTubeCookieHeader(''), isEmpty);
    expect(readTubeCookieHeader('does-not-exist.txt'), isEmpty);
  });

  test('生成 Netscape Cookie 文件并去重', () {
    final text = buildTubeCookieFile([
      const TubeCookieEntry(
        name: 'SID',
        value: 'abc',
        domain: '.youtube.com',
        path: '/',
        secure: true,
        httpOnly: true,
        expires: 1999999999,
      ),
      const TubeCookieEntry(
        name: 'SID',
        value: 'duplicate',
        domain: '.youtube.com',
        path: '/',
        secure: true,
        httpOnly: true,
        expires: 1999999999,
      ),
      const TubeCookieEntry(
        name: 'OTHER',
        value: 'ignored',
        domain: '.example.com',
        path: '/',
        secure: true,
        httpOnly: false,
        expires: 0,
      ),
    ]);

    expect(
      text,
      contains('#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1999999999\tSID\tabc'),
    );
    expect(text, isNot(contains('duplicate')));
    expect(text, isNot(contains('OTHER')));
  });

  test('没有 Cookie 时生成空文件', () {
    expect(buildTubeCookieFile(const []), isEmpty);
  });
}
