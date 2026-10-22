import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/transfer/resume_ledger.dart';

void main() {
  test('segment ranges are contiguous and cover the whole file', () {
    final ranges = computeByteRanges(103, 4);
    expect(ranges, hasLength(4));
    expect(ranges.first.start, 0);
    expect(ranges.last.end, 102);
    var expectedStart = 0;
    var total = 0;
    for (final range in ranges) {
      expect(range.start, expectedStart);
      total += range.length;
      expectedStart = range.end + 1;
    }
    expect(total, 103);
  });

  test('segment count is clamped between 1 and 8', () {
    expect(computeByteRanges(1024, 0), hasLength(1));
    expect(computeByteRanges(1024, 99), hasLength(8));
    expect(computeByteRanges(3, 8), hasLength(3));
  });

  test('state rejects a different segment layout', () {
    const metadata = RemoteFacts(expectedBytes: 100, etag: 'a');
    final oldRanges = computeByteRanges(100, 2);
    final state = ResumeLedger(
      expectedBytes: 100,
      receivedBytes: 50,
      parallelSegments: 2,
      ranges: oldRanges,
      etag: 'a',
    );
    expect(
      stateMatches(state, metadata, 4, computeByteRanges(100, 4)),
      isFalse,
    );
    expect(stateMatches(state, metadata, 2, oldRanges), isTrue);
  });

  test('state rejects a changed validator', () {
    final ranges = computeByteRanges(100, 2);
    final state = ResumeLedger(
      expectedBytes: 100,
      receivedBytes: 50,
      parallelSegments: 2,
      ranges: ranges,
      etag: 'old',
    );
    expect(
      stateMatches(
        state,
        const RemoteFacts(expectedBytes: 100, etag: 'new'),
        2,
        ranges,
      ),
      isFalse,
    );
  });

  test('missing validators do not invalidate a resumable state', () {
    final ranges = computeByteRanges(100, 2);
    final state = ResumeLedger(
      expectedBytes: 100,
      receivedBytes: 10,
      parallelSegments: 2,
      ranges: ranges,
    );
    expect(
      stateMatches(
        state,
        const RemoteFacts(expectedBytes: 100, etag: 'new'),
        2,
        ranges,
      ),
      isTrue,
    );
  });
}
