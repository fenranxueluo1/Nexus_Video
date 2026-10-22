import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/api/service_exception.dart';
import 'package:nexus_video/core/api/bili_transport.dart';
import 'package:nexus_video/core/transfer/resume_ledger.dart';
import 'package:nexus_video/core/transfer/asset_receiver.dart';
import 'package:nexus_video/core/domain/jobs.dart';
import 'package:nexus_video/core/util/task_token.dart';

class _RangeServer {
  _RangeServer._(this.server, this.data);

  final HttpServer server;
  final Uint8List data;
  final List<String?> ranges = [];
  bool ignoreRange = false;
  bool corruptRange = false;
  String etag = '"etag-1"';

  static Future<_RangeServer> start(Uint8List data) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _RangeServer._(server, data);
    server.listen(instance._handle);
    return instance;
  }

  String get url => 'http://127.0.0.1:${server.port}/media.bin';

  void _handle(HttpRequest request) {
    final response = request.response;
    response.headers.set('etag', etag);
    response.headers.set('accept-ranges', 'bytes');
    if (request.method == 'HEAD') {
      response.contentLength = data.length;
      response.close();
      return;
    }
    final range = request.headers.value('range');
    ranges.add(range);
    if (ignoreRange || range == null) {
      response.statusCode = 200;
      response.contentLength = data.length;
      response.add(data);
      response.close();
      return;
    }
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
    if (match == null) {
      response.statusCode = 416;
      response.close();
      return;
    }
    final start = int.parse(match.group(1)!);
    if (start >= data.length) {
      response.statusCode = 416;
      response.close();
      return;
    }
    final requestedEnd = match.group(2)!.isEmpty
        ? data.length - 1
        : int.parse(match.group(2)!);
    final end = requestedEnd.clamp(start, data.length - 1);
    final slice = data.sublist(start, end + 1);
    final reportedStart = corruptRange ? start + 1 : start;
    response.statusCode = 206;
    response.headers.set(
      'content-range',
      'bytes $reportedStart-$end/${data.length}',
    );
    response.contentLength = slice.length;
    response.add(slice);
    response.close();
  }

  Future<void> close() => server.close(force: true);
}

JobAsset _resource(Directory dir, String url) {
  return JobAsset(
    id: 'asset',
    role: AssetRole.video,
    urls: [url],
    destinationPath: '${dir.path}${Platform.pathSeparator}output.bin',
    scratchPath: '${dir.path}${Platform.pathSeparator}output.bin.track',
  );
}

Uint8List _sampleData(int length) {
  return Uint8List.fromList(List<int>.generate(length, (index) => index % 251));
}

void main() {
  test('downloads multiple segments and assembles exact bytes', () async {
    final data = _sampleData(220000);
    final server = await _RangeServer.start(data);
    final dir = Directory.systemTemp.createTempSync('nexus-receive-');
    final http = BiliTransport();
    addTearDown(() async {
      http.close();
      await server.close();
      dir.deleteSync(recursive: true);
    });

    final receiver = AssetReceiver(http, retryLimit: 0, parallelSegments: 4);
    final asset = _resource(dir, server.url);
    final outcome = await receiver.receive(asset: asset, token: TaskToken());

    expect(outcome.bytes, data.length);
    expect(
      await File(asset.destinationPath).readAsBytes(),
      orderedEquals(data),
    );
    expect(
      server.ranges.where((range) => range != null).length,
      greaterThanOrEqualTo(4),
    );
  });

  test('resumes a single stream from an existing partial file', () async {
    final data = _sampleData(120000);
    final server = await _RangeServer.start(data);
    final dir = Directory.systemTemp.createTempSync('nexus-resume-');
    final http = BiliTransport();
    addTearDown(() async {
      http.close();
      await server.close();
      dir.deleteSync(recursive: true);
    });

    final asset = _resource(dir, server.url);
    const partial = 4096;
    await File(asset.scratchPath).writeAsBytes(data.sublist(0, partial));
    await writeResumeLedger(
      statePathFor(asset.scratchPath),
      ResumeLedger(
        expectedBytes: data.length,
        receivedBytes: partial,
        parallelSegments: 1,
        ranges: computeByteRanges(data.length, 1),
        etag: server.etag,
      ),
    );

    final receiver = AssetReceiver(http, retryLimit: 0, parallelSegments: 1);
    final outcome = await receiver.receive(asset: asset, token: TaskToken());

    expect(outcome.bytes, data.length);
    expect(
      await File(asset.destinationPath).readAsBytes(),
      orderedEquals(data),
    );
    expect(server.ranges, contains('bytes=$partial-'));
    expect(File(statePathFor(asset.scratchPath)).existsSync(), isFalse);
  });

  test(
    'discards an incompatible segment layout instead of corrupting output',
    () async {
      final data = _sampleData(200000);
      final server = await _RangeServer.start(data);
      final dir = Directory.systemTemp.createTempSync('nexus-segments-');
      final http = BiliTransport();
      addTearDown(() async {
        http.close();
        await server.close();
        dir.deleteSync(recursive: true);
      });

      final asset = _resource(dir, server.url);
      final oldRanges = computeByteRanges(data.length, 2);
      await File(
        segmentPathFor(asset.scratchPath, 0),
      ).writeAsBytes(data.sublist(0, 1000));
      await writeResumeLedger(
        statePathFor(asset.scratchPath),
        ResumeLedger(
          expectedBytes: data.length,
          receivedBytes: 1000,
          parallelSegments: 2,
          ranges: oldRanges,
          etag: server.etag,
        ),
      );

      final receiver = AssetReceiver(http, retryLimit: 0, parallelSegments: 4);
      await receiver.receive(asset: asset, token: TaskToken());

      expect(
        await File(asset.destinationPath).readAsBytes(),
        orderedEquals(data),
      );
    },
  );

  test('restarts from zero when the server ignores a Range request', () async {
    final data = _sampleData(90000);
    final server = await _RangeServer.start(data);
    server.ignoreRange = true;
    final dir = Directory.systemTemp.createTempSync('nexus-range-');
    final http = BiliTransport();
    addTearDown(() async {
      http.close();
      await server.close();
      dir.deleteSync(recursive: true);
    });

    final asset = _resource(dir, server.url);
    const partial = 2048;
    await File(asset.scratchPath).writeAsBytes(data.sublist(0, partial));
    await writeResumeLedger(
      statePathFor(asset.scratchPath),
      ResumeLedger(
        expectedBytes: data.length,
        receivedBytes: partial,
        parallelSegments: 1,
        ranges: computeByteRanges(data.length, 1),
        etag: server.etag,
      ),
    );

    final receiver = AssetReceiver(http, retryLimit: 0, parallelSegments: 1);
    await receiver.receive(asset: asset, token: TaskToken());

    expect(
      await File(asset.destinationPath).readAsBytes(),
      orderedEquals(data),
    );
  });

  test(
    'rejects a mismatched Content-Range instead of accepting corruption',
    () async {
      final data = _sampleData(70000);
      final server = await _RangeServer.start(data);
      server.corruptRange = true;
      final dir = Directory.systemTemp.createTempSync('nexus-range-bad-');
      final http = BiliTransport();
      addTearDown(() async {
        http.close();
        await server.close();
        dir.deleteSync(recursive: true);
      });

      final asset = _resource(dir, server.url);
      const partial = 1024;
      await File(asset.scratchPath).writeAsBytes(data.sublist(0, partial));
      await writeResumeLedger(
        statePathFor(asset.scratchPath),
        ResumeLedger(
          expectedBytes: data.length,
          receivedBytes: partial,
          parallelSegments: 1,
          ranges: computeByteRanges(data.length, 1),
          etag: server.etag,
        ),
      );

      final receiver = AssetReceiver(http, retryLimit: 0, parallelSegments: 1);
      await expectLater(
        receiver.receive(asset: asset, token: TaskToken()),
        throwsA(isA<ApiException>()),
      );
      expect(File(asset.destinationPath).existsSync(), isFalse);
    },
  );
}
