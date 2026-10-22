Map<String, String> parseCookie(String raw) {
  final result = <String, String>{};
  for (final track in raw.split(';')) {
    final trimmed = track.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final index = trimmed.indexOf('=');
    if (index <= 0) {
      continue;
    }
    result[trimmed.substring(0, index).trim()] = trimmed
        .substring(index + 1)
        .trim();
  }
  return result;
}

String sanitizeCookieInput(String raw) {
  var value = raw.trim();
  if (value.toLowerCase().startsWith('cookie:')) {
    value = value.substring(7).trim();
  }
  return value
      .replaceAll(RegExp(r'[\r\n]'), '; ')
      .replaceAll(RegExp(r';\s*;'), ';');
}

bool looksLikeCookie(String raw) {
  final parsed = parseCookie(sanitizeCookieInput(raw));
  return parsed.containsKey('SESSDATA') || parsed.containsKey('bili_jct');
}
