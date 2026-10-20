import 'clip.dart';
import 'timeline_clip_index.dart';

enum TrackType { video, audio, image, text }

/// Content identity, kept compatible with the names used by projects 1–13.
typedef ClipKind = TrackType;

enum TrackKind { visual, audio }

class Track {
  Track({
    required this.id,
    required this.name,
    TrackType? type,
    TrackKind? kind,
    double height = 64,
    List<Clip> clips = const [],
    this.isLocked = false,
    this.isHidden = false,
    this.isMuted = false,
    this.isSolo = false,
    this.volume = 1,
  }) : height = height.isFinite ? height.clamp(44.0, 180.0) : 64,
       type =
           type ??
           (kind == TrackKind.audio ? TrackType.audio : TrackType.video),
       kind =
           kind ??
           (type == TrackType.audio ? TrackKind.audio : TrackKind.visual),
       clips = List.unmodifiable(clips);

  final String id;
  final String name;
  final TrackType type;
  final TrackKind kind;
  final double height;

  bool accepts(ClipKind content) => kind == TrackKind.audio
      ? content == ClipKind.audio
      : content != ClipKind.audio;
  final List<Clip> clips;
  late final TimelineClipIndex clipIndex = TimelineClipIndex(clips);
  final bool isLocked;
  final bool isHidden;
  final bool isMuted;
  final bool isSolo;
  final double volume;

  Track copyWith({
    String? id,
    String? name,
    TrackType? type,
    TrackKind? kind,
    double? height,
    List<Clip>? clips,
    bool? isLocked,
    bool? isHidden,
    bool? isMuted,
    bool? isSolo,
    double? volume,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      kind: kind ?? this.kind,
      height: height == null || !height.isFinite
          ? this.height
          : height.clamp(44.0, 180.0),
      clips: clips ?? this.clips,
      isLocked: isLocked ?? this.isLocked,
      isHidden: isHidden ?? this.isHidden,
      isMuted: isMuted ?? this.isMuted,
      isSolo: isSolo ?? this.isSolo,
      volume: volume ?? this.volume,
    );
  }
}
