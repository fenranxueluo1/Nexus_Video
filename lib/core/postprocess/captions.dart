import 'dart:convert';

class CaptionCue {
  const CaptionCue({
    required this.from,
    required this.to,
    required this.content,
  });

  final double from;
  final double to;
  final String content;
}

List<CaptionCue> readCaptionJson(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }
    final body = decoded['body'];
    if (body is! List) {
      return const [];
    }
    final cues = <CaptionCue>[];
    for (final entry in body) {
      if (entry is! Map) {
        continue;
      }
      final from = (entry['from'] as num?)?.toDouble();
      final to = (entry['to'] as num?)?.toDouble();
      final content = entry['content']?.toString().trim() ?? '';
      if (from == null || to == null || content.isEmpty) {
        continue;
      }
      cues.add(CaptionCue(from: from, to: to, content: content));
    }
    cues.sort((left, right) => left.from.compareTo(right.from));
    return cues;
  } on FormatException {
    return const [];
  }
}

String _srtTime(double seconds) {
  final totalMs = (seconds * 1000).round().clamp(0, 1 << 31);
  final hours = totalMs ~/ 3600000;
  final minutes = (totalMs % 3600000) ~/ 60000;
  final secs = (totalMs % 60000) ~/ 1000;
  final millis = totalMs % 1000;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(hours)}:${two(minutes)}:${two(secs)},${millis.toString().padLeft(3, '0')}';
}

String captionsToSrt(List<CaptionCue> cues) {
  final buffer = StringBuffer();
  for (var index = 0; index < cues.length; index += 1) {
    final cue = cues[index];
    buffer.writeln(index + 1);
    buffer.writeln('${_srtTime(cue.from)} --> ${_srtTime(cue.to)}');
    buffer.writeln(cue.content.replaceAll(RegExp(r'[\r\n]+'), ' '));
    buffer.writeln();
  }
  return buffer.toString();
}
