import 'dart:io';

import '../util/durable_json.dart';

class ByteRange {
  const ByteRange({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start + 1;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory ByteRange.fromJson(Map<String, dynamic> json) => ByteRange(
    start: (json['start'] as num?)?.toInt() ?? 0,
    end: (json['end'] as num?)?.toInt() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is ByteRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class ResumeLedger {
  const ResumeLedger({
    required this.expectedBytes,
    required this.receivedBytes,
    required this.parallelSegments,
    required this.ranges,
    this.etag,
    this.lastModified,
  });

  final int expectedBytes;
  final int receivedBytes;
  final int parallelSegments;
  final List<ByteRange> ranges;
  final String? etag;
  final String? lastModified;

  Map<String, dynamic> toJson() => {
    'version': 2,
    'expectedBytes': expectedBytes,
    'receivedBytes': receivedBytes,
    'parallelSegments': parallelSegments,
    'ranges': ranges.map((range) => range.toJson()).toList(),
    'etag': etag,
    'lastModified': lastModified,
  };

  factory ResumeLedger.fromJson(Map<String, dynamic> json) => ResumeLedger(
    expectedBytes: (json['expectedBytes'] as num?)?.toInt() ?? 0,
    receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
    parallelSegments: (json['parallelSegments'] as num?)?.toInt() ?? 0,
    ranges: ((json['ranges'] as List?) ?? const [])
        .map((range) => ByteRange.fromJson(range as Map<String, dynamic>))
        .toList(),
    etag: json['etag'] as String?,
    lastModified: json['lastModified'] as String?,
  );
}

class RemoteFacts {
  const RemoteFacts({
    required this.expectedBytes,
    this.etag,
    this.lastModified,
    this.contentEncoding,
    this.acceptRanges = false,
  });

  final int? expectedBytes;
  final String? etag;
  final String? lastModified;
  final String? contentEncoding;
  final bool acceptRanges;
}

String statePathFor(String scratchPath) => '$scratchPath.state';

String segmentPathFor(String scratchPath, int index) =>
    '$scratchPath.seg$index';

Future<ResumeLedger?> readResumeLedger(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  try {
    final json = await DurableJson.readMap(file);
    return json == null ? null : ResumeLedger.fromJson(json);
  } on Object {
    return null;
  }
}

Future<void> writeResumeLedger(String path, ResumeLedger state) async {
  await DurableJson.writeJson(File(path), state.toJson(), pretty: false);
}

bool validatorsMatch(String? previous, String? current) {
  if (previous == null || current == null) {
    return true;
  }
  return previous == current;
}

bool stateMatches(
  ResumeLedger state,
  RemoteFacts metadata,
  int parallelSegments,
  List<ByteRange> ranges,
) {
  if (metadata.expectedBytes != null &&
      state.expectedBytes != metadata.expectedBytes) {
    return false;
  }
  if (state.parallelSegments != parallelSegments) {
    return false;
  }
  if (state.ranges.length != ranges.length) {
    return false;
  }
  for (var index = 0; index < ranges.length; index += 1) {
    if (state.ranges[index] != ranges[index]) {
      return false;
    }
  }
  if (metadata.etag != null &&
      state.etag != null &&
      metadata.etag != state.etag) {
    return false;
  }
  if (metadata.lastModified != null &&
      state.lastModified != null &&
      metadata.lastModified != state.lastModified) {
    return false;
  }
  return true;
}

List<ByteRange> computeByteRanges(int expectedBytes, int parallelSegments) {
  if (expectedBytes <= 0) {
    return const [];
  }
  final count = parallelSegments.clamp(1, 8).clamp(1, expectedBytes);
  final base = expectedBytes ~/ count;
  final remainder = expectedBytes % count;
  final ranges = <ByteRange>[];
  var start = 0;
  for (var index = 0; index < count; index += 1) {
    final size = base + (index < remainder ? 1 : 0);
    ranges.add(ByteRange(start: start, end: start + size - 1));
    start += size;
  }
  return ranges;
}
