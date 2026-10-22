import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/intake/link_recognizer.dart';

void main() {
  test('classifies video identifiers', () {
    final bvid = recognizeLink('BV1xx411c7mD');
    expect(bvid.kind, LinkKind.video);
    expect(bvid.bvid, 'BV1xx411c7mD');

    final av = recognizeLink('av170001');
    expect(av.kind, LinkKind.video);
    expect(av.aid, 170001);

    final numeric = recognizeLink('170001');
    expect(numeric.kind, LinkKind.video);
    expect(numeric.aid, 170001);
  });

  test('classifies video urls', () {
    final input = recognizeLink(
      'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
    );
    expect(input.kind, LinkKind.video);
    expect(input.bvid, 'BV1xx411c7mD');
  });

  test('classifies bangumi and cheese urls', () {
    final bangumi = recognizeLink(
      'https://www.bilibili.com/bangumi/play/ep123456',
    );
    expect(bangumi.kind, LinkKind.bangumi);
    expect(bangumi.epId, 123456);

    final season = recognizeLink('https://www.bilibili.com/bangumi/play/ss789');
    expect(season.kind, LinkKind.bangumi);
    expect(season.seasonId, 789);

    final cheese = recognizeLink('https://www.bilibili.com/cheese/play/ss55');
    expect(cheese.kind, LinkKind.cheese);
    expect(cheese.seasonId, 55);
  });

  test('classifies favorites, uploaders and collections', () {
    final medialist = recognizeLink(
      'https://www.bilibili.com/medialist/play/ml9988',
    );
    expect(medialist.kind, LinkKind.favorite);
    expect(medialist.mediaId, 9988);

    final uploader = recognizeLink('https://space.bilibili.com/12345');
    expect(uploader.kind, LinkKind.uploader);
    expect(uploader.mid, 12345);

    final season = recognizeLink(
      'https://space.bilibili.com/12345/channel/collectiondetail?sid=66',
    );
    expect(season.kind, LinkKind.season);
    expect(season.mid, 12345);
    expect(season.collectionId, 66);

    final series = recognizeLink(
      'https://space.bilibili.com/12345/channel/seriesdetail?sid=77',
    );
    expect(series.kind, LinkKind.series);
    expect(series.collectionId, 77);
  });

  test('classifies watch later and short links', () {
    final watchLater = recognizeLink(
      'https://www.bilibili.com/list/watchlater',
    );
    expect(watchLater.kind, LinkKind.watchLater);

    final short = recognizeLink('https://b23.tv/abcd');
    expect(short.kind, LinkKind.shortLink);
  });

  test('rejects unknown input', () {
    expect(recognizeLink('hello world').kind, LinkKind.unknown);
    expect(
      recognizeLink('https://example.com/video/BV1xx411c7mD').kind,
      LinkKind.unknown,
    );
  });
}
