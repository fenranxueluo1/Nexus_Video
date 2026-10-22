import 'dart:io';

import '../util/storage_paths.dart';
import '../util/cookie_codec.dart' as cookie_util;
import '../util/durable_json.dart';

class CredentialVault {
  CredentialVault({File? file}) : _file = file ?? StoragePaths.credentialFile;

  final File _file;
  String _cookie = '';

  String get cookie => _cookie;
  bool get hasCookie => _cookie.trim().isNotEmpty;

  Future<void> load() async {
    final json = await DurableJson.readMap(_file);
    _cookie = json?['cookie'] as String? ?? '';
  }

  Future<void> saveCookie(String cookie) async {
    _cookie = cookie.trim();
    await DurableJson.writeJson(_file, {
      'savedAt': DateTime.now().toIso8601String(),
      'cookie': _cookie,
    });
  }

  Future<void> clear() async {
    _cookie = '';
    if (await _file.exists()) {
      await _file.delete();
    }
  }

  static Map<String, String> parseCookie(String raw) =>
      cookie_util.parseCookie(raw);

  static String sanitizeCookieInput(String raw) =>
      cookie_util.sanitizeCookieInput(raw);

  static bool looksLikeCookie(String raw) => cookie_util.looksLikeCookie(raw);
}
