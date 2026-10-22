import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/preferences.dart';

const String defaultPathTemplate = '{title}/{track_no} - {track_title}';

const List<String> templateVariables = [
  'title',
  'track_title',
  'track_no',
  'bvid',
  'aid',
  'cid',
  'creator',
  'creator_id',
  'series',
  'season_no',
  'episode_no',
  'episode_name',
  'collection',
  'index',
  'quality',
  'quality_name',
  'codec',
  'date',
  'publish_date',
  'ext',
];

const Map<String, String> templateVariableHelp = {
  'title': '作品标题',
  'track_title': '分段 / 剧集标题',
  'track_no': '分段序号（从 1 开始）',
  'bvid': 'BV 号',
  'aid': 'AV 号',
  'cid': 'CID',
  'creator': '创作者名称',
  'creator_id': '创作者 ID',
  'series': '系列 / 剧集标题',
  'season_no': '季序号',
  'episode_no': '集序号',
  'episode_name': '剧集名称',
  'collection': '收藏夹 / 合集名称',
  'index': '列表序号',
  'quality': '清晰度代码（如 80）',
  'quality_name': '清晰度名称（如 1080P）',
  'codec': '编码（如 AVC）',
  'date': '生成日期，可写 {date:%Y-%m-%d}',
  'publish_date': '发布日期，可写 {publish_date:%Y%m%d}',
  'ext': '输出扩展名',
};

class PathFields {
  const PathFields({
    required this.title,
    required this.trackTitle,
    required this.trackNo,
    required this.ext,
    this.bvid,
    this.aid,
    this.cid,
    this.creator,
    this.creatorId,
    this.series,
    this.seasonNo,
    this.episodeNo,
    this.episodeName,
    this.collection,
    this.index,
    this.quality,
    this.codec,
    this.date,
    this.publishDate,
  });

  final String title;
  final String trackTitle;
  final int trackNo;
  final String ext;
  final String? bvid;
  final int? aid;
  final int? cid;
  final String? creator;
  final int? creatorId;
  final String? series;
  final int? seasonNo;
  final int? episodeNo;
  final String? episodeName;
  final String? collection;
  final int? index;
  final String? quality;
  final String? codec;
  final DateTime? date;
  final String? publishDate;

  Map<String, String> toVariables() => {
    'title': title,
    'track_title': trackTitle,
    'track_no': trackNo.toString(),
    'bvid': bvid ?? '',
    'aid': aid?.toString() ?? '',
    'cid': cid?.toString() ?? '',
    'creator': creator ?? '',
    'creator_id': creatorId?.toString() ?? '',
    'series': series ?? '',
    'season_no': seasonNo?.toString() ?? '',
    'episode_no': episodeNo?.toString() ?? '',
    'episode_name': episodeName ?? trackTitle,
    'collection': collection ?? '',
    'index': index?.toString() ?? '',
    'quality': quality ?? '',
    'quality_name': quality == null ? '' : qualityNameFor(quality!),
    'codec': codec ?? '',
    'date': formatNamingDate(date ?? DateTime.now(), '%Y-%m-%d'),
    'publish_date': publishDate ?? '',
    'ext': ext,
  };
}

String qualityNameFor(String quality) {
  final number = int.tryParse(quality);
  return switch (number) {
    6 => '240P',
    16 => '360P',
    32 => '480P',
    64 => '720P',
    74 => '720P60',
    80 => '1080P',
    112 => '1080P+',
    116 => '1080P60',
    120 => '4K',
    125 => 'HDR',
    126 => 'Dolby Vision',
    127 => '8K',
    _ => quality,
  };
}

String formatNamingDate(DateTime value, String format) {
  String two(int number) => number.toString().padLeft(2, '0');
  return format
      .replaceAll('%Y', value.year.toString().padLeft(4, '0'))
      .replaceAll('%m', two(value.month))
      .replaceAll('%d', two(value.day));
}

void validatePathTemplate(String template) {
  var index = 0;
  while (index < template.length) {
    final char = template[index];
    if (char == '}') {
      throw const FormatException('路径规则存在多余的 `}`。');
    }
    if (char != '{') {
      index += 1;
      continue;
    }
    final close = template.indexOf('}', index + 1);
    if (close < 0) {
      throw const FormatException('路径规则存在未闭合变量。');
    }
    final name = template.substring(index + 1, close).trim();
    validateVariableName(name);
    index = close + 1;
  }
}

void validateVariableName(String name) {
  if (name.isEmpty) {
    throw const FormatException('路径规则存在空变量。');
  }
  final chunks = name.split(':');
  if (chunks.length > 1) {
    final field = chunks.first;
    final format = chunks.sublist(1).join(':');
    if ((field == 'date' || field == 'publish_date') &&
        const {'%Y-%m-%d', '%Y.%m.%d', '%Y%m%d'}.contains(format)) {
      return;
    }
    throw FormatException('路径规则存在未知变量 `$name`。');
  }
  if (!templateVariables.contains(name)) {
    throw FormatException('路径规则存在未知变量 `$name`。');
  }
}

String renderPathTemplate(String template, PathFields context) {
  final variables = context.toVariables();
  final buffer = StringBuffer();
  var index = 0;
  while (index < template.length) {
    final char = template[index];
    if (char != '{') {
      buffer.write(char);
      index += 1;
      continue;
    }
    final close = template.indexOf('}', index + 1);
    if (close < 0) {
      throw const FormatException('路径规则存在未闭合变量。');
    }
    final name = template.substring(index + 1, close).trim();
    validateVariableName(name);
    final chunks = name.split(':');
    if (chunks.length > 1) {
      final field = chunks.first;
      final format = chunks.sublist(1).join(':');
      final raw = field == 'date' ? (context.date ?? DateTime.now()) : null;
      if (raw == null) {
        final parsed = DateTime.tryParse(context.publishDate ?? '');
        buffer.write(parsed == null ? '' : formatNamingDate(parsed, format));
      } else {
        buffer.write(formatNamingDate(raw, format));
      }
    } else {
      buffer.write(variables[name] ?? '');
    }
    index = close + 1;
  }
  return buffer.toString();
}

String cleanPathSegment(String value) {
  final sanitized = _sanitize(value);
  if (sanitized.isEmpty) {
    return 'untitled';
  }
  return _avoidReservedName(_truncateComponent(sanitized));
}

String cleanFileName(String value) {
  final sanitized = _sanitize(value);
  if (sanitized.isEmpty) {
    return 'untitled';
  }
  return _avoidReservedName(_truncateComponent(sanitized));
}

String _sanitize(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final code = rune;
    final illegal =
        code < 0x20 ||
        code == 0x7f ||
        const {'<', '>', ':', '"', '/', '\\', '|', '?', '*'}.contains(char);
    buffer.write(illegal ? '_' : char);
  }
  return buffer.toString().trim().replaceFirst(RegExp(r'[.\s]+$'), '');
}

String _truncateComponent(String value) {
  const maxBytes = 180;
  if (utf8.encode(value).length <= maxBytes) {
    return value;
  }
  final hash = md5.convert(utf8.encode(value)).toString().substring(0, 8);
  final suffix = '~$hash';
  final budget = maxBytes - utf8.encode(suffix).length;
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final size = utf8.encode(char).length;
    if (used + size > budget) {
      break;
    }
    buffer.write(char);
    used += size;
  }
  return '${buffer.toString()}$suffix';
}

const Set<String> _reservedWindowsNames = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

String _avoidReservedName(String value) {
  final base = value.split('.').first.toUpperCase();
  if (_reservedWindowsNames.contains(base)) {
    return '_$value';
  }
  return value;
}

String appendExtension(String path, String extension) {
  final normalizedExtension = extension.replaceAll('.', '').trim();
  if (normalizedExtension.isEmpty) {
    return path;
  }
  final current = p.extension(path).replaceFirst('.', '');
  if (current.toLowerCase() == normalizedExtension.toLowerCase()) {
    return path;
  }
  return '$path.$normalizedExtension';
}

String composeRelativePath(String template, PathFields context) {
  validatePathTemplate(template);
  final rendered = renderPathTemplate(template, context);
  final components = rendered
      .split(RegExp(r'[/\\]'))
      .map(cleanPathSegment)
      .where((component) => component.isNotEmpty)
      .toList();
  if (components.isEmpty) {
    throw const FormatException('路径规则渲染结果为空。');
  }
  var path = p.joinAll(components);
  path = appendExtension(path, context.ext);
  return path;
}

String resolveDuplicatePath(
  String path,
  Set<String> reserved,
  CollisionPolicy policy, {
  required bool exists,
}) {
  switch (policy) {
    case CollisionPolicy.skip:
      return path;
    case CollisionPolicy.overwrite:
      if (reserved.contains(path)) {
        return uniquePath(path, reserved);
      }
      reserved.add(path);
      return path;
    case CollisionPolicy.append:
      return uniquePath(path, reserved, alsoExists: exists);
  }
}

String uniquePath(
  String path,
  Set<String> reserved, {
  bool alsoExists = false,
}) {
  final directory = p.dirname(path);
  final extension = p.extension(path);
  final stem = p.basenameWithoutExtension(path);
  var suffix = 1;
  while (true) {
    final candidateName = '$stem ($suffix)$extension';
    final candidate = directory == '.'
        ? candidateName
        : p.join(directory, candidateName);
    if (!reserved.contains(candidate) &&
        !(alsoExists && File(candidate).existsSync())) {
      reserved.add(candidate);
      return candidate;
    }
    suffix += 1;
  }
}

String limitPathLength(String path, {int? maxLength}) {
  final limit =
      maxLength ??
      (Platform.isWindows
          ? 250
          : Platform.isIOS
          ? 300
          : 4000);
  if (path.length <= limit) {
    return path;
  }
  final directory = p.dirname(path);
  final extension = p.extension(path);
  final stem = p.basenameWithoutExtension(path);
  final available = limit - directory.length - extension.length - 10;
  if (available <= 8) {
    final hash = md5.convert(utf8.encode(path)).toString().substring(0, 8);
    return p.join(directory, 'file~$hash$extension');
  }
  final hash = md5.convert(utf8.encode(path)).toString().substring(0, 8);
  final keep = available - 9;
  final shortened = stem.length <= keep
      ? stem
      : '${stem.substring(0, keep)}~$hash';
  return p.join(directory, '$shortened$extension');
}

bool isPathInside(String child, String parent) {
  final normalizedChild = p.normalize(p.absolute(child));
  final normalizedParent = p.normalize(p.absolute(parent));
  return normalizedChild == normalizedParent ||
      p.isWithin(normalizedParent, normalizedChild);
}
