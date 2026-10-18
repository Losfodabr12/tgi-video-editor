import 'clip.dart';

enum TrackType { video, audio, image, text }

class Track {
  Track({
    required this.id,
    required this.name,
    required this.type,
    List<Clip> clips = const [],
    this.isLocked = false,
    this.isHidden = false,
    this.isMuted = false,
    this.isSolo = false,
    this.volume = 1,
  }) : clips = List.unmodifiable(clips);

  final String id;
  final String name;
  final TrackType type;
  final List<Clip> clips;
  final bool isLocked;
  final bool isHidden;
  final bool isMuted;
  final bool isSolo;
  final double volume;

  Track copyWith({
    String? id,
    String? name,
    TrackType? type,
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
      clips: clips ?? this.clips,
      isLocked: isLocked ?? this.isLocked,
      isHidden: isHidden ?? this.isHidden,
      isMuted: isMuted ?? this.isMuted,
      isSolo: isSolo ?? this.isSolo,
      volume: volume ?? this.volume,
    );
  }
}
