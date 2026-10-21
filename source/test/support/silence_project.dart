import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';

Duration silenceTime(num seconds) =>
    Duration(microseconds: (seconds * 1e6).round());

Clip silenceCaption(String id, num start, num duration) => Clip(
  id: id,
  mediaItemId: id,
  timelineGroupId: 'group_$id',
  trackType: TrackType.text,
  timelineStart: silenceTime(start),
  sourceStart: Duration.zero,
  duration: silenceTime(duration),
  textContent: 'palavra $id',
  isCaption: true,
);

TgiProject silenceProject({bool audio = true, double duration = 10}) {
  final media = MediaItem(
    id: 'speech',
    name: 'speech.mp4',
    filePath: 'speech.mp4',
    importedAt: DateTime.utc(2026),
    type: MediaType.video,
    duration: silenceTime(duration),
    width: 160,
    height: 90,
    hasAudio: audio,
  );
  final video = Clip(
    id: 'video',
    mediaItemId: media.id,
    timelineGroupId: 'av',
    trackType: TrackType.video,
    timelineStart: Duration.zero,
    sourceStart: Duration.zero,
    sourceDuration: media.duration,
    duration: media.duration,
  );
  return TgiProject(
    id: 'silence-fixture',
    name: 'Silence fixture',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    mediaPool: [media],
    tracks: [
      Track(id: 'main', name: 'Video', type: TrackType.video, clips: [video]),
      if (audio)
        Track(
          id: 'audio',
          name: 'Audio',
          type: TrackType.audio,
          clips: [video.copyWith(id: 'audio-clip', trackType: TrackType.audio)],
        ),
    ],
  );
}

/// Public synthetic analogue: 1 video + 1 linked audio + 129 captions + title.
TgiProject layeredSilenceProject() {
  final base = silenceProject(duration: 293.547);
  final captions = [
    for (var i = 0; i < 129; i++)
      silenceCaption('caption_$i', .2 + i * 2.25, 1.5),
  ];
  return base.copyWith(
    tracks: [
      Track(
        id: 'title',
        name: 'Visual 4',
        type: TrackType.text,
        clips: [silenceCaption('title', 11.066, 5).copyWith(isCaption: false)],
      ),
      Track(
        id: 'captions_upper',
        name: 'Visual 3',
        type: TrackType.text,
        clips: captions.skip(22).toList(),
      ),
      Track(
        id: 'captions_lower',
        name: 'Visual 2',
        type: TrackType.text,
        clips: captions.take(22).toList(),
      ),
      ...base.tracks,
    ],
  );
}

List<(int, int)> get fixtureSilences => [
  for (var i = 0; i < 45; i++)
    (
      silenceTime(1 + i * 6.1).inMicroseconds,
      silenceTime(2.2 + i * 6.1).inMicroseconds,
    ),
];
