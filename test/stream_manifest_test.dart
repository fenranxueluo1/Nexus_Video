import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/api/bili_gateway.dart';

void main() {
  final client = BiliGateway();
  tearDownAll(client.close);

  test('legacy result string does not hide dash streams', () {
    final info = client.parseStreamManifest({
      'result': 'suee',
      'quality': 16,
      'accept_quality': [16],
      'dash': {
        'duration': 200,
        'video': [
          {
            'id': 16,
            'baseUrl': 'https://example.com/v.m4s',
            'bandwidth': 1000,
            'codecid': 7,
            'width': 512,
            'height': 288,
          },
        ],
        'audio': [
          {
            'id': 30216,
            'baseUrl': 'https://example.com/a.m4s',
            'bandwidth': 500,
          },
        ],
      },
    });
    expect(info.videoStreams, hasLength(1));
    expect(info.audioStreams, hasLength(1));
    expect(info.videoStreams.first.isCombined, isFalse);
    expect(info.durationMs, 200000);
  });

  test('durl responses are marked as muxed streams', () {
    final info = client.parseStreamManifest({
      'result': 'suee',
      'quality': 16,
      'accept_quality': [16],
      'durl': [
        {
          'url': 'https://example.com/a.mp4',
          'size': 12345,
          'backup_url': ['https://backup.example.com/a.mp4'],
        },
      ],
    });
    expect(info.videoStreams, hasLength(1));
    expect(info.videoStreams.first.isCombined, isTrue);
    expect(info.videoStreams.first.backupUrls, hasLength(1));
    expect(info.videoStreams.first.sizeBytes, 12345);
    expect(info.audioStreams, isEmpty);
  });

  test('nested pgc result maps are unwrapped', () {
    final info = client.parseStreamManifest({
      'result': {
        'dash': {
          'video': [
            {
              'id': 80,
              'baseUrl': 'https://example.com/v.m4s',
              'bandwidth': 100,
            },
          ],
        },
      },
    });
    expect(info.videoStreams, hasLength(1));
    expect(info.videoStreams.first.quality, 80);
  });
}
