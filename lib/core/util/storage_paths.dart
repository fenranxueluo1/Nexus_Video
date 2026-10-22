import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StoragePaths {
  StoragePaths._();

  static late Directory dataDir;
  static late Directory credentialsDir;
  static late Directory journalDir;
  static late Directory workRoot;
  static String _defaultDownloadDir = '';

  static Future<void> init() async {
    Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } on Object {
      support = Directory(p.join(Directory.systemTemp.path, 'nexus_video'));
    }
    dataDir = support;
    credentialsDir = Directory(p.join(support.path, 'credentials'));
    journalDir = Directory(p.join(support.path, 'journal'));
    workRoot = Directory(p.join(support.path, 'work'));
    for (final dir in [dataDir, credentialsDir, journalDir, workRoot]) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
    _defaultDownloadDir = await _resolveDefaultDownloadDir();
  }

  static String get defaultDownloadDir => _defaultDownloadDir;

  static File get preferencesFile =>
      File(p.join(dataDir.path, 'preferences.json'));
  static File get jobsFile => File(p.join(dataDir.path, 'jobs.json'));
  static File get recordsFile => File(p.join(dataDir.path, 'records.json'));
  static File get credentialFile =>
      File(p.join(credentialsDir.path, 'credential.json'));

  static File journalFileFor(String jobId) =>
      File(p.join(journalDir.path, '${_safeName(jobId)}.jsonl'));

  static Future<String> _resolveDefaultDownloadDir() async {
    if (Platform.operatingSystem == 'ohos') {
      return p.join(dataDir.path, 'Nexus');
    }
    if (Platform.isIOS) {
      final documents = await getApplicationDocumentsDirectory();
      return p.join(documents.path, 'Nexus');
    }
    if (Platform.isAndroid) {
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) {
          return p.join(external.path, 'Nexus');
        }
      } catch (_) {}
      final documents = await getApplicationDocumentsDirectory();
      return p.join(documents.path, 'Nexus');
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return p.join(downloads.path, 'Nexus');
      }
    } catch (_) {
      // Fall through to platform-specific defaults.
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, 'Downloads', 'Nexus');
    }
    try {
      final documents = await getApplicationDocumentsDirectory();
      return p.join(documents.path, 'Nexus');
    } on Object {
      return p.join(Directory.systemTemp.path, 'Nexus');
    }
  }

  static String _safeName(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
