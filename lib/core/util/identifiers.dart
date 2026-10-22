import 'dart:math';

String makeId([String prefix = '']) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final random = Random.secure().nextInt(0x7fffffff);
  final body = '${now.toRadixString(36)}${random.toRadixString(36)}';
  return prefix.isEmpty ? body : '$prefix-$body';
}
