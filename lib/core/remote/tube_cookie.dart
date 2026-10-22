import 'dart:io';

String readTubeCookieHeader(String path) {
  return _readCookieHeader(path, _isTubeCookieDomain);
}

String readChirpCookieHeader(String path) {
  return _readCookieHeader(path, _isChirpCookieDomain);
}

String readDouyinCookieHeader(String path) {
  return _readCookieHeader(path, _isDouyinCookieDomain);
}

String _readCookieHeader(
  String path,
  bool Function(String domain) domainFilter,
) {
  final value = path.trim();
  if (value.isEmpty) {
    return '';
  }
  final file = File(value);
  if (!file.existsSync()) {
    return '';
  }
  String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException {
    return '';
  }
  final cookies = <String, String>{};
  for (var line in text.split(RegExp(r'\r?\n'))) {
    line = line.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('#HttpOnly_')) {
      line = line.substring('#HttpOnly_'.length);
    } else if (line.startsWith('#')) {
      continue;
    }
    final parts = line.split('\t');
    if (parts.length < 7) {
      continue;
    }
    final domain = parts[0].toLowerCase();
    if (!domainFilter(domain)) {
      continue;
    }
    final name = parts[5].trim();
    if (name.isEmpty) {
      continue;
    }
    cookies[name] = parts[6];
  }
  return cookies.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('; ');
}

bool _isTubeCookieDomain(String domain) {
  return domain == 'youtube.com' ||
      domain.endsWith('.youtube.com') ||
      domain == 'googlevideo.com' ||
      domain.endsWith('.googlevideo.com');
}

bool _isChirpCookieDomain(String domain) {
  return domain == 'x.com' ||
      domain.endsWith('.x.com') ||
      domain == 'twitter.com' ||
      domain.endsWith('.twitter.com') ||
      domain == 'twimg.com' ||
      domain.endsWith('.twimg.com');
}

bool _isDouyinCookieDomain(String domain) {
  return domain == 'douyin.com' ||
      domain.endsWith('.douyin.com') ||
      domain == 'iesdouyin.com' ||
      domain.endsWith('.iesdouyin.com') ||
      domain == 'amemv.com' ||
      domain.endsWith('.amemv.com') ||
      domain == 'douyinvod.com' ||
      domain.endsWith('.douyinvod.com');
}

class TubeCookieEntry {
  const TubeCookieEntry({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.secure,
    required this.httpOnly,
    required this.expires,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;
  final int expires;
}

bool isTubeLoginCookieDomain(String domain) {
  final value = domain.toLowerCase();
  return value == 'youtube.com' ||
      value.endsWith('.youtube.com') ||
      value == 'google.com' ||
      value.endsWith('.google.com') ||
      value == 'googlevideo.com' ||
      value.endsWith('.googlevideo.com');
}

bool isChirpLoginCookieDomain(String domain) {
  final value = domain.toLowerCase();
  return value == 'x.com' ||
      value.endsWith('.x.com') ||
      value == 'twitter.com' ||
      value.endsWith('.twitter.com') ||
      value == 'twimg.com' ||
      value.endsWith('.twimg.com');
}

bool isDouyinLoginCookieDomain(String domain) {
  final value = domain.toLowerCase();
  return value == 'douyin.com' ||
      value.endsWith('.douyin.com') ||
      value == 'iesdouyin.com' ||
      value.endsWith('.iesdouyin.com') ||
      value == 'amemv.com' ||
      value.endsWith('.amemv.com') ||
      value == 'douyinvod.com' ||
      value.endsWith('.douyinvod.com');
}

String buildTubeCookieFile(Iterable<TubeCookieEntry> entries) {
  return buildCookieFile(entries, domainFilter: isTubeLoginCookieDomain);
}

String buildChirpCookieFile(Iterable<TubeCookieEntry> entries) {
  return buildCookieFile(entries, domainFilter: isChirpLoginCookieDomain);
}

String buildDouyinCookieFile(Iterable<TubeCookieEntry> entries) {
  return buildCookieFile(entries, domainFilter: isDouyinLoginCookieDomain);
}

String buildCookieFile(
  Iterable<TubeCookieEntry> entries, {
  required bool Function(String domain) domainFilter,
}) {
  final lines = <String>['# Netscape HTTP Cookie File'];
  final seen = <String>{};
  for (final entry in entries) {
    final domain = entry.domain.trim();
    if (domain.isEmpty || entry.name.isEmpty || !domainFilter(domain)) {
      continue;
    }
    final path = entry.path.trim().isEmpty ? '/' : entry.path.trim();
    if (!seen.add('$domain|$path|${entry.name}')) {
      continue;
    }
    final prefix = entry.httpOnly ? '#HttpOnly_' : '';
    final includeSubdomains = domain.startsWith('.') ? 'TRUE' : 'FALSE';
    final secure = entry.secure ? 'TRUE' : 'FALSE';
    final expires = entry.expires > 0 ? entry.expires : 0;
    final value = entry.value.replaceAll(RegExp(r'[\r\n\t]'), ' ');
    lines.add(
      '$prefix$domain\t$includeSubdomains\t$path\t$secure\t$expires\t${entry.name}\t$value',
    );
  }
  return lines.length == 1 ? '' : '${lines.join('\n')}\n';
}
