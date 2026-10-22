class RemoteClip {
  const RemoteClip({
    required this.id,
    required this.title,
    required this.author,
    this.authorId,
    this.description,
    this.coverUrl,
    this.duration = Duration.zero,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String author;
  final String? authorId;
  final String? description;
  final String? coverUrl;
  final Duration duration;
  final DateTime? publishedAt;
}

class RemoteCollection {
  const RemoteCollection({
    required this.id,
    required this.title,
    required this.author,
    required this.clips,
    this.description,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String author;
  final List<RemoteClip> clips;
  final String? description;
  final String? coverUrl;
}

class RemoteStream {
  const RemoteStream({
    required this.url,
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.height,
    required this.bitrate,
    this.sizeBytes,
    this.isMuxed = false,
    this.headers = const {},
  });

  final String url;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int height;
  final int bitrate;
  final int? sizeBytes;
  final bool isMuxed;
  final Map<String, String> headers;

  String get qualityLabel => height > 0 ? '${height}P' : '未知';

  String get videoCodecKey {
    final value = videoCodec.toLowerCase();
    if (value.contains('avc') || value.contains('h264')) {
      return 'avc';
    }
    if (value.contains('hev') ||
        value.contains('hvc') ||
        value.contains('h265')) {
      return 'hevc';
    }
    if (value.contains('av01') || value.contains('av1')) {
      return 'av1';
    }
    if (value.contains('vp9')) {
      return 'vp9';
    }
    if (value.contains('vp8')) {
      return 'vp8';
    }
    return 'other';
  }

  String get codecLabel {
    return switch (videoCodecKey) {
      'avc' => 'AVC',
      'hevc' => 'HEVC',
      'av1' => 'AV1',
      'vp9' => 'VP9',
      'vp8' => 'VP8',
      _ => videoCodec.isEmpty ? '未知' : videoCodec,
    };
  }
}

class RemoteStreams {
  const RemoteStreams({
    this.videos = const [],
    this.audios = const [],
    this.muxed = const [],
  });

  final List<RemoteStream> videos;
  final List<RemoteStream> audios;
  final List<RemoteStream> muxed;
}
