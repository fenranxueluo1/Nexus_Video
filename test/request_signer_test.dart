import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/api/request_signer.dart';

void main() {
  test('mix-in key is deterministic and 32 characters', () {
    final key = RequestSigner.mixinKey(
      '7cd084941338484aae1ad9425b84077c',
      '4932caff0ff746eab6f01bf08b70ac45',
    );
    expect(key.length, 32);
    expect(key, 'ea1db124af3c7062474693fa704f4ff8');
    expect(
      key,
      RequestSigner.mixinKey(
        '7cd084941338484aae1ad9425b84077c',
        '4932caff0ff746eab6f01bf08b70ac45',
      ),
    );
  });

  test('removes forbidden characters from parameter values', () {
    final signed = RequestSigner.sign({'q': "a'b(c)d!'*"}, 'key');
    expect(signed['q'], 'abcd');
  });

  test('w_rid is the md5 of sorted query plus mixin key', () {
    const mixin = '0123456789abcdef0123456789abcdef';
    final signed = RequestSigner.sign({'z': 1, 'foo': 'bar'}, mixin);
    expect(signed.containsKey('wts'), isTrue);
    expect(signed['w_rid'], hasLength(32));
    final copy = Map<String, String>.of(signed)..remove('w_rid');
    final query = RequestSigner.queryString(copy);
    final expected = md5.convert(utf8.encode('$query$mixin')).toString();
    expect(signed['w_rid'], expected);
  });
}
