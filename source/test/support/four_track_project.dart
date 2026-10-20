import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/domain/text_style_profile.dart';

TgiProject fourTrackProject() =>
    TgiProject.empty(name: 'Quatro trilhas').copyWith(
      tracks: [
        Track(id: 'titles', name: 'Títulos', type: TrackType.text),
        Track(
          id: 'main',
          name: 'Principal',
          clips: [
            const Clip(
              id: 'new-title',
              mediaItemId: 'new-title',
              timelineGroupId: 'new-title',
              trackType: TrackType.text,
              timelineStart: Duration.zero,
              sourceStart: Duration.zero,
              duration: Duration(seconds: 12),
              fontFamily: NewTextStyle.fontFamily,
              textContent: 'Uma história em camadas',
              overlayX: .5,
              overlayY: .78,
            ),
          ],
        ),
        Track(id: 'effects', name: 'Efeitos', type: TrackType.video),
        Track(id: 'audio', name: 'Áudio', kind: TrackKind.audio),
      ],
    );
