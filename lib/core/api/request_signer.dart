import 'dart:convert';

import 'package:crypto/crypto.dart';

const List<int> _mixinKeyEncTab = [
  46,
  47,
  18,
  2,
  53,
  8,
  23,
  32,
  15,
  50,
  10,
  31,
  58,
  3,
  45,
  35,
  27,
  43,
  5,
  49,
  33,
  9,
  42,
  19,
  29,
  28,
  14,
  39,
  12,
  38,
  41,
  13,
  37,
  48,
  7,
  16,
  24,
  55,
  40,
  61,
  26,
  17,
  0,
  1,
  60,
  51,
  30,
  4,
  22,
  25,
  54,
  21,
  56,
  59,
  6,
  63,
  57,
  62,
  11,
  36,
  20,
  34,
  44,
  52,
];

class SigningKeys {
  SigningKeys({
    required this.imgKey,
    required this.subKey,
    required this.fetchedAt,
  }) : mixinKey = RequestSigner.mixinKey(imgKey, subKey);

  final String imgKey;
  final String subKey;
  final DateTime fetchedAt;
  final String mixinKey;

  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < const Duration(minutes: 10);
}

class RequestSigner {
  static String mixinKey(String imgKey, String subKey) {
    final raw = '$imgKey$subKey';
    final buffer = StringBuffer();
    for (final index in _mixinKeyEncTab) {
      if (index < raw.length) {
        buffer.write(raw[index]);
      }
    }
    final value = buffer.toString();
    return value.length <= 32 ? value : value.substring(0, 32);
  }

  static Map<String, String> sign(
    Map<String, Object?> params,
    String mixinKey,
  ) {
    final signed = <String, String>{};
    params.forEach((key, value) {
      if (value == null) {
        return;
      }
      signed[key] = '$value'.replaceAll(RegExp(r"[!'()*]"), '');
    });
    signed['wts'] = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final keys = signed.keys.toList()..sort();
    final query = keys
        .map(
          (key) =>
              '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(signed[key]!)}',
        )
        .join('&');
    signed['w_rid'] = md5.convert(utf8.encode('$query$mixinKey')).toString();
    return signed;
  }

  static String queryString(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    return keys
        .map(
          (key) =>
              '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(params[key]!)}',
        )
        .join('&');
  }
}

String fileNameFromUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
