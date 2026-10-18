class TimelineMarker {
  const TimelineMarker({
    required this.id,
    required this.name,
    required this.position,
    this.color = 0xFFFFD166,
  });

  final String id;
  final String name;
  final Duration position;
  final int color;

  TimelineMarker copyWith({
    String? id,
    String? name,
    Duration? position,
    int? color,
  }) {
    return TimelineMarker(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      color: color ?? this.color,
    );
  }
}
