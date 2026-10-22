import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class DurableJson {
  static Future<Map<String, dynamic>?> readMap(File file) async {
    final candidates = [file, File('${file.path}.bak')];
    for (final candidate in candidates) {
      try {
        if (!await candidate.exists()) {
          continue;
        }
        final text = await candidate.readAsString();
        if (text.trim().isEmpty) {
          continue;
        }
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  static Future<void> writeJson(
    File file,
    Object value, {
    bool pretty = true,
  }) async {
    await file.parent.create(recursive: true);
    final text = pretty
        ? const JsonEncoder.withIndent('  ').convert(value)
        : jsonEncode(value);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(text, flush: true);
    final backup = File('${file.path}.bak');
    if (await file.exists()) {
      try {
        if (await backup.exists()) {
          await backup.delete();
        }
        await file.rename(backup.path);
      } on FileSystemException {
        await file.delete();
      }
    }
    try {
      await temp.rename(file.path);
      if (await backup.exists()) {
        await backup.delete();
      }
    } on FileSystemException {
      await temp.copy(file.path);
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  static Future<void> appendLine(
    File file,
    Map<String, dynamic> entry, {
    int maxLines = 2000,
  }) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
      flush: true,
    );
    if (await _lineCountExceeds(file, maxLines)) {
      final lines = await file.readAsLines();
      final keep = lines.sublist(lines.length - maxLines);
      await file.writeAsString('${keep.join('\n')}\n', flush: true);
    }
  }

  static Future<List<Map<String, dynamic>>> readLines(
    File file, {
    int limit = 200,
  }) async {
    if (!await file.exists()) {
      return const [];
    }
    final lines = await file.readAsLines();
    final start = lines.length > limit ? lines.length - limit : 0;
    final result = <Map<String, dynamic>>[];
    for (final line in lines.sublist(start)) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          result.add(decoded);
        }
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  static Future<bool> _lineCountExceeds(File file, int maxLines) async {
    try {
      final length = await file.length();
      if (length < maxLines * 64) {
        return false;
      }
      final lines = await file.readAsLines();
      return lines.length > maxLines;
    } catch (_) {
      return false;
    }
  }
}

Future<void> ensureParentDirectory(String path) async {
  final parent = Directory(p.dirname(path));
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
}
