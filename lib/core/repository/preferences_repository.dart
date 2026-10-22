import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/preferences.dart';
import '../util/storage_paths.dart';
import '../util/durable_json.dart';

class PreferencesRepository {
  PreferencesRepository({File? file})
    : _file = file ?? StoragePaths.preferencesFile;

  final File _file;
  Preferences _settings = Preferences.defaults();

  Preferences get preferences => _settings;

  Future<Preferences> load() async {
    final json = await DurableJson.readMap(_file);
    if (json == null) {
      _settings = Preferences.defaults();
    } else {
      try {
        _settings = Preferences.fromJson(json);
      } on Object {
        _settings = Preferences.defaults();
      }
    }
    if (_settings.destinationRoot.trim().isEmpty) {
      _settings = _settings.copyWith(
        destinationRoot: StoragePaths.defaultDownloadDir,
      );
    }
    return _settings;
  }

  Future<void> save(Preferences preferences) async {
    _settings = preferences;
    await DurableJson.writeJson(_file, preferences.toJson());
  }

  Future<void> reset() async {
    _settings = Preferences.defaults().copyWith(
      destinationRoot: StoragePaths.defaultDownloadDir,
    );
    await save(_settings);
  }

  Future<String> ensureDownloadDirectory() async {
    final configured = _settings.destinationRoot.trim();
    final directory = Directory(
      configured.isEmpty ? StoragePaths.defaultDownloadDir : configured,
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }

  static Future<bool> directoryIsWritable(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final probe = File(p.join(path, '.nexus-write-probe'));
      await probe.writeAsString('probe');
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
