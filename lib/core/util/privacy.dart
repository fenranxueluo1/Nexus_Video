String scrubSecrets(String message) {
  var value = message;
  value = value.replaceAllMapped(
    RegExp(r'(https?://[^\s?]+)\?[^\s]*'),
    (match) => '${match.group(1)}?<redacted>',
  );
  value = value.replaceAllMapped(
    RegExp(
      r'(SESSDATA|bili_jct|access_key|refresh_token|token|sign|deadline|upsig|w_rid)=([^&\s;]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
  value = value.replaceAllMapped(
    RegExp(r'(https?://)[^/\s@:]+:[^/\s@]+@'),
    (match) => '${match.group(1)}<redacted>@',
  );
  return value;
}
