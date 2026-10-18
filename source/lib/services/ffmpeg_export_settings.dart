class FfmpegExportResolution {
  const FfmpegExportResolution({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
  });

  static const p450 = FfmpegExportResolution(
    id: '450p',
    label: '450p',
    width: 800,
    height: 450,
  );
  static const p720 = FfmpegExportResolution(
    id: '720p',
    label: '720p HD',
    width: 1280,
    height: 720,
  );
  static const p750 = FfmpegExportResolution(
    id: '750p',
    label: '750p',
    width: 1334,
    height: 750,
  );
  static const p1080 = FfmpegExportResolution(
    id: '1080p',
    label: '1080p Full HD',
    width: 1920,
    height: 1080,
  );
  static const shorts1080 = FfmpegExportResolution(
    id: 'shorts_1080x1920',
    label: 'Shorts 9:16',
    width: 1080,
    height: 1920,
  );
  static const square1080 = FfmpegExportResolution(
    id: 'square_1080x1080',
    label: 'Quadrado 1:1',
    width: 1080,
    height: 1080,
  );
  static const feed1080x1350 = FfmpegExportResolution(
    id: 'feed_1080x1350',
    label: 'Feed 4:5',
    width: 1080,
    height: 1350,
  );
  static const p2k = FfmpegExportResolution(
    id: '2k',
    label: '2K 1440p',
    width: 2560,
    height: 1440,
  );
  static const p4k = FfmpegExportResolution(
    id: '4k',
    label: '4K 2160p',
    width: 3840,
    height: 2160,
  );

  static const all = [
    p450,
    p720,
    p750,
    p1080,
    shorts1080,
    square1080,
    feed1080x1350,
    p2k,
    p4k,
  ];

  final String id;
  final String label;
  final int width;
  final int height;

  String get dimensionsLabel => '${width}x$height';

  bool get requiresPaidPlan => this == p4k;

  @override
  bool operator ==(Object other) {
    return other is FfmpegExportResolution && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

bool canExportResolution(
  FfmpegExportResolution resolution, {
  required bool hasPaidPlan,
}) {
  return hasPaidPlan || !resolution.requiresPaidPlan;
}

class FfmpegExportQuality {
  const FfmpegExportQuality({
    required this.id,
    required this.label,
    required this.crf,
    required this.encoderPreset,
  });

  static const light = FfmpegExportQuality(
    id: 'light',
    label: 'Leve',
    crf: 26,
    encoderPreset: 'veryfast',
  );
  static const standard = FfmpegExportQuality(
    id: 'standard',
    label: 'Boa',
    crf: 20,
    encoderPreset: 'veryfast',
  );
  static const high = FfmpegExportQuality(
    id: 'high',
    label: 'Alta',
    crf: 18,
    encoderPreset: 'medium',
  );
  static const maximum = FfmpegExportQuality(
    id: 'maximum',
    label: 'Maxima',
    crf: 16,
    encoderPreset: 'slow',
  );

  static const all = [light, standard, high, maximum];

  final String id;
  final String label;
  final int crf;
  final String encoderPreset;

  @override
  bool operator ==(Object other) {
    return other is FfmpegExportQuality && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum FfmpegVideoEncoder {
  software('CPU (compatível)', 'libx264'),
  automatic('GPU automática', 'auto'),
  nvidia('NVIDIA NVENC', 'h264_nvenc'),
  intel('Intel Quick Sync', 'h264_qsv'),
  amd('AMD AMF', 'h264_amf');

  const FfmpegVideoEncoder(this.label, this.codec);
  final String label;
  final String codec;
}

class FfmpegExportSettings {
  const FfmpegExportSettings({
    required this.resolution,
    required this.framesPerSecond,
    required this.quality,
    this.rangeStart,
    this.rangeEnd,
    this.encoder = FfmpegVideoEncoder.software,
  });

  static const frameRateOptions = [24, 30, 60];
  static const defaultSettings = FfmpegExportSettings(
    resolution: FfmpegExportResolution.p720,
    framesPerSecond: 30,
    quality: FfmpegExportQuality.standard,
  );
  static const uiDefault = FfmpegExportSettings(
    resolution: FfmpegExportResolution.p1080,
    framesPerSecond: 30,
    quality: FfmpegExportQuality.standard,
  );

  static const quickCreator = FfmpegExportSettings(
    resolution: FfmpegExportResolution.shorts1080,
    framesPerSecond: 30,
    quality: FfmpegExportQuality.standard,
  );
  static const squareSocial = FfmpegExportSettings(
    resolution: FfmpegExportResolution.square1080,
    framesPerSecond: 30,
    quality: FfmpegExportQuality.standard,
  );
  static const feed45 = FfmpegExportSettings(
    resolution: FfmpegExportResolution.feed1080x1350,
    framesPerSecond: 30,
    quality: FfmpegExportQuality.standard,
  );

  final FfmpegExportResolution resolution;
  final int framesPerSecond;
  final FfmpegExportQuality quality;
  final Duration? rangeStart;
  final Duration? rangeEnd;
  final FfmpegVideoEncoder encoder;
  bool get hasRange => rangeStart != null || rangeEnd != null;

  FfmpegExportSettings copyWith({
    FfmpegVideoEncoder? encoder,
    Duration? rangeStart,
    Duration? rangeEnd,
    bool clearRange = false,
  }) => FfmpegExportSettings(
    resolution: resolution,
    framesPerSecond: framesPerSecond,
    quality: quality,
    encoder: encoder ?? this.encoder,
    rangeStart: clearRange ? null : rangeStart ?? this.rangeStart,
    rangeEnd: clearRange ? null : rangeEnd ?? this.rangeEnd,
  );

  Duration exportDuration(Duration fullDuration) {
    if (!hasRange) return fullDuration;
    final start = rangeStart ?? Duration.zero;
    final end = rangeEnd ?? fullDuration;
    if (start < Duration.zero || start >= end || end > fullDuration) {
      throw const FormatException(
        'O trecho deve ter início menor que o fim e estar dentro da timeline.',
      );
    }
    return end - start;
  }

  Map<String, dynamic> toJson() => {
    'resolution': resolution.id,
    'framesPerSecond': framesPerSecond,
    'quality': quality.id,
    'encoder': encoder.name,
    if (rangeStart != null) 'rangeStartMs': rangeStart!.inMilliseconds,
    if (rangeEnd != null) 'rangeEndMs': rangeEnd!.inMilliseconds,
  };

  static FfmpegExportSettings? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final data = Map<String, dynamic>.from(value);
    final resolutionId = data['resolution'] as String?;
    final qualityId = data['quality'] as String?;
    final resolution = _firstWhereOrNull(
      FfmpegExportResolution.all,
      (candidate) => candidate.id == resolutionId,
    );
    final quality = _firstWhereOrNull(
      FfmpegExportQuality.all,
      (candidate) => candidate.id == qualityId,
    );
    if (resolution == null || quality == null) {
      return null;
    }
    final rawFrameRate = data['framesPerSecond'];
    final frameRate = rawFrameRate is num ? rawFrameRate.round() : 30;
    return FfmpegExportSettings(
      resolution: resolution,
      framesPerSecond: frameRateOptions.contains(frameRate) ? frameRate : 30,
      quality: quality,
      encoder:
          FfmpegVideoEncoder.values
              .where((e) => e.name == data['encoder'])
              .firstOrNull ??
          FfmpegVideoEncoder.software,
      rangeStart: data['rangeStartMs'] is num
          ? Duration(milliseconds: (data['rangeStartMs'] as num).round())
          : null,
      rangeEnd: data['rangeEndMs'] is num
          ? Duration(milliseconds: (data['rangeEndMs'] as num).round())
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FfmpegExportSettings &&
        other.resolution == resolution &&
        other.framesPerSecond == framesPerSecond &&
        other.quality == quality &&
        other.encoder == encoder &&
        other.rangeStart == rangeStart &&
        other.rangeEnd == rangeEnd;
  }

  @override
  int get hashCode => Object.hash(
    resolution,
    framesPerSecond,
    quality,
    encoder,
    rangeStart,
    rangeEnd,
  );
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) matches) {
  for (final value in values) {
    if (matches(value)) {
      return value;
    }
  }
  return null;
}
