enum MediaType { video, audio, image, text }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.filePath,
    required this.name,
    required this.type,
    required this.duration,
    required this.importedAt,
    this.hasAudio = true,
    this.thumbnailPath,
    this.previewProxyPath,
    this.width,
    this.height,
  });

  final String id;
  final String filePath;
  final String name;
  final MediaType type;
  final Duration duration;
  final DateTime importedAt;
  final bool hasAudio;
  final String? thumbnailPath;
  final String? previewProxyPath;
  final int? width;
  final int? height;

  MediaItem copyWith({
    String? id,
    String? filePath,
    String? name,
    MediaType? type,
    Duration? duration,
    DateTime? importedAt,
    bool? hasAudio,
    String? thumbnailPath,
    String? previewProxyPath,
    int? width,
    int? height,
  }) {
    return MediaItem(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      name: name ?? this.name,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      importedAt: importedAt ?? this.importedAt,
      hasAudio: hasAudio ?? this.hasAudio,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      previewProxyPath: previewProxyPath ?? this.previewProxyPath,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
