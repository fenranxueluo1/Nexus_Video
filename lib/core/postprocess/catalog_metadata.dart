import '../domain/catalog.dart';

class CatalogMetadata {
  const CatalogMetadata({
    required this.title,
    required this.trackTitle,
    required this.plot,
    this.bvid,
    this.aid,
    this.cid,
    this.creator,
    this.creatorId,
    this.publishDate,
    this.collection,
    this.series,
    this.quality,
    this.codec,
    this.url,
  });

  final String title;
  final String trackTitle;
  final String plot;
  final String? bvid;
  final int? aid;
  final int? cid;
  final String? creator;
  final int? creatorId;
  final DateTime? publishDate;
  final String? collection;
  final String? series;
  final String? quality;
  final String? codec;
  final String? url;

  Map<String, String> toVariables() => {
    'title': title,
    'track_title': trackTitle,
    'plot': plot,
    'bvid': bvid ?? '',
    'aid': aid?.toString() ?? '',
    'cid': cid?.toString() ?? '',
    'creator': creator ?? '',
    'creator_id': creatorId?.toString() ?? '',
    'publish_date': publishDate?.toIso8601String().split('T').first ?? '',
    'collection': collection ?? '',
    'series': series ?? '',
    'quality': quality ?? '',
    'codec': codec ?? '',
    'url': url ?? '',
  };
}

const String defaultCatalogTemplate =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<movie>
  <title>{title}</title>
  <originaltitle>{track_title}</originaltitle>
  <plot>{plot}</plot>
  <uniqueid type="bilibili" default="true">{bvid}</uniqueid>
  <studio>{creator}</studio>
  <premiered>{publish_date}</premiered>
  <set><name>{collection}</name></set>
  <tag>{quality}</tag>
  <tag>{codec}</tag>
</movie>
''';

String composeCatalogXml(CatalogMetadata context, {String? customTemplate}) {
  final template = (customTemplate ?? '').trim().isEmpty
      ? defaultCatalogTemplate
      : customTemplate!;
  final variables = context.toVariables().map(
    (key, value) => MapEntry(key, _escapeXml(value)),
  );
  var output = template;
  variables.forEach((key, value) {
    output = output.replaceAll('{$key}', value);
  });
  return output;
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

CatalogMetadata catalogMetadataFor({
  required CatalogEntry item,
  required CatalogTrack track,
  required String quality,
  required String codec,
  required String url,
}) {
  return CatalogMetadata(
    title: item.title,
    trackTitle: track.title,
    plot: item.summary ?? '',
    bvid: track.bvid,
    aid: track.aid,
    cid: track.cid,
    creator: track.creator ?? item.creator,
    creatorId: track.creatorId ?? item.creatorId,
    publishDate: DateTime.tryParse(track.pubDate ?? ''),
    collection: track.collection ?? item.title,
    series: track.series,
    quality: quality,
    codec: codec,
    url: url,
  );
}
