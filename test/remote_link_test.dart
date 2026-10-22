import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/intake/link_recognizer.dart';

void main() {
  test('识别 YouTube watch 链接', () {
    final link = recognizeLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(link.kind, LinkKind.tubeClip);
    expect(link.tubeId, 'dQw4w9WgXcQ');
  });

  test('识别 youtu.be 短链接', () {
    final link = recognizeLink('https://youtu.be/dQw4w9WgXcQ?t=42');
    expect(link.kind, LinkKind.tubeClip);
    expect(link.tubeId, 'dQw4w9WgXcQ');
  });

  test('识别 YouTube Shorts 与直播链接', () {
    final shorts = recognizeLink('https://www.youtube.com/shorts/abc123XYZ_1');
    expect(shorts.kind, LinkKind.tubeClip);
    expect(shorts.tubeId, 'abc123XYZ_1');
    final live = recognizeLink('https://www.youtube.com/live/abc123XYZ_1');
    expect(live.kind, LinkKind.tubeClip);
    expect(live.tubeId, 'abc123XYZ_1');
  });

  test('识别 YouTube 播放列表', () {
    final link = recognizeLink(
      'https://www.youtube.com/playlist?list=PL1234567890',
    );
    expect(link.kind, LinkKind.tubeList);
    expect(link.tubeListId, 'PL1234567890');
  });

  test('识别 X 帖子', () {
    final link = recognizeLink('https://x.com/someone/status/1234567890123');
    expect(link.kind, LinkKind.chirpPost);
    expect(link.chirpId, '1234567890123');
  });

  test('识别 twitter.com 帖子', () {
    final link = recognizeLink(
      'https://twitter.com/someone/status/9876543210/video/1',
    );
    expect(link.kind, LinkKind.chirpPost);
    expect(link.chirpId, '9876543210');
  });

  test('B 站链接识别不受影响', () {
    final link = recognizeLink('https://www.bilibili.com/video/BV1xx411c7mD');
    expect(link.kind, LinkKind.video);
    expect(link.bvid, 'BV1xx411c7mD');
  });

  test('识别抖音视频链接', () {
    final link = recognizeLink(
      'https://www.douyin.com/video/6961737553342991651',
    );
    expect(link.kind, LinkKind.douyinClip);
    expect(link.douyinId, '6961737553342991651');
  });

  test('识别抖音短链和分享文本', () {
    final short = recognizeLink('https://v.douyin.com/AbCdEf/');
    expect(short.kind, LinkKind.douyinClip);
    expect(short.url, contains('v.douyin.com'));

    final shared = recognizeLink(
      '7.97 复制打开抖音 https://v.douyin.com/AbCdEf/ 看看这个视频',
    );
    expect(shared.kind, LinkKind.douyinClip);
    expect(shared.url, contains('v.douyin.com'));
  });

  test('识别抖音分享页和 modal_id', () {
    final share = recognizeLink(
      'https://www.iesdouyin.com/share/video/7586265149888105765/',
    );
    expect(share.kind, LinkKind.douyinClip);
    expect(share.douyinId, '7586265149888105765');

    final modal = recognizeLink(
      'https://www.douyin.com/discover?modal_id=7586265149888105765',
    );
    expect(modal.kind, LinkKind.douyinClip);
    expect(modal.douyinId, '7586265149888105765');
  });
}
