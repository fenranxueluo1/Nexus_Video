import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/postprocess/catalog_metadata.dart';

void main() {
  test('renders default nfo and escapes xml values', () {
    final nfo = composeCatalogXml(
      const CatalogMetadata(
        title: 'A < B & C',
        trackTitle: '第一 P',
        plot: '<script>',
        bvid: 'BV1xx411c7mD',
        creator: 'UP & Co',
        quality: '80',
        codec: 'AVC',
      ),
    );
    expect(nfo, contains('<title>A &lt; B &amp; C</title>'));
    expect(nfo, contains('&lt;script&gt;'));
    expect(nfo, contains('BV1xx411c7mD'));
  });

  test('supports a custom template', () {
    final nfo = composeCatalogXml(
      const CatalogMetadata(title: '标题', trackTitle: 'P1', plot: '简介'),
      customTemplate:
          '<movie><title>{title}</title><plot>{plot}</plot></movie>',
    );
    expect(nfo, '<movie><title>标题</title><plot>简介</plot></movie>');
  });
}
