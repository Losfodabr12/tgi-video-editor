import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';

MediaItem media(String id, MediaType type, {bool audio = false}) => MediaItem(
  id: id,
  filePath: '$id.mp4',
  name: id,
  type: type,
  duration: const Duration(seconds: 2),
  importedAt: DateTime(2026),
  hasAudio: audio,
);

TgiProject projectWith(MediaItem item) =>
    TgiProject.empty(name: 'Teste').addMediaItem(item);
Clip content(TgiProject project, TrackType type) => project.tracks
    .expand((track) => track.clips)
    .firstWhere((clip) => clip.trackType == type);

void main() {
  test(
    'paste over occupied linked clips creates compatible lanes and one undo entry',
    () {
      final video = media('clipboard', MediaType.video, audio: true);
      final project = projectWith(
        video,
      ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
      final source = content(project, TrackType.video);
      final controller = EditorController(
        initialProject: project,
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      );
      addTearDown(controller.dispose);
      controller.selectTimelineClipGroup(source.timelineGroupId);
      controller.copySelectedTimelineClips();
      controller.pasteCopiedTimelineClips();
      expect(controller.project.tracks, hasLength(4));
      final pastedGroup = controller.selectedTimelineGroupId;
      expect(pastedGroup, isNot(source.timelineGroupId));
      final copies = controller.project.tracks
          .expand((track) => track.clips)
          .where((clip) => clip.timelineGroupId == pastedGroup)
          .toList();
      expect(copies.map((clip) => clip.kind).toSet(), {
        TrackType.video,
        TrackType.audio,
      });
      expect(
        copies.map((clip) => clip.timelineStart),
        everyElement(Duration.zero),
      );
      expect(controller.project.clipById(source.id), same(source));
      controller.undo();
      expect(controller.project, same(project));
      controller.redo();
      expect(controller.project.tracks, hasLength(4));
    },
  );

  test(
    'clipboard survives deleting its source lane without dropping linked content',
    () {
      final video = media('deleted_clipboard', MediaType.video, audio: true);
      final project = projectWith(
        video,
      ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
      final source = content(project, TrackType.video);
      final controller = EditorController(
        initialProject: project,
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      );
      addTearDown(controller.dispose);
      controller.selectTimelineClipGroup(source.timelineGroupId);
      controller.copySelectedTimelineClips();
      controller.deleteTimelineTrack(project.trackForClip(source.id)!.id);
      controller.setPlayheadPosition(const Duration(seconds: 3));
      controller.pasteCopiedTimelineClips();
      final pasted = controller.project.tracks
          .expand((track) => track.clips)
          .where(
            (clip) =>
                clip.timelineGroupId == controller.selectedTimelineGroupId,
          )
          .toList();
      expect(pasted.map((clip) => clip.kind).toSet(), {
        TrackType.video,
        TrackType.audio,
      });
      expect(
        pasted.map((clip) => clip.timelineStart),
        everyElement(const Duration(seconds: 3)),
      );
    },
  );

  test('duplicate creates a layer when later content occupies its target', () {
    final video = media('duplicate', MediaType.video);
    final project = projectWith(video)
        .addMediaItemToTimeline(video, timelineStart: Duration.zero)
        .addMediaItemToTimeline(
          video,
          timelineStart: const Duration(seconds: 2),
        );
    final clip = content(project, TrackType.video);
    final duplicated = project.duplicateTimelineClipGroups({
      clip.timelineGroupId,
    }, timelineStart: const Duration(seconds: 2));
    expect(duplicated.tracks, hasLength(2));
    expect(duplicated.tracks.first.clips.single.id, isNot(clip.id));
    expect(duplicated.tracks.last.clips, project.tracks.single.clips);
  });
  test(
    'legacy video overlaps are preserved but never silently concatenated on export',
    () {
      final video = media('overlap', MediaType.video);
      final original = projectWith(
        video,
      ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
      final first = content(original, TrackType.video);
      final overlap = original.copyWith(
        tracks: [
          original.tracks.single.copyWith(
            clips: [
              first,
              first.copyWith(
                id: 'overlapping',
                timelineGroupId: 'overlapping',
                timelineStart: const Duration(seconds: 1),
              ),
            ],
          ),
        ],
      );
      final loaded = ProjectIOService()
          .deserializeProject(ProjectIOService().serializeProject(overlap))
          .project;
      expect(loaded.tracks.single.clips.length, 2);
      expect(
        () => FfmpegService().buildExportCommand(loaded, 'not-written.mp4'),
        throwsA(
          isA<FfmpegProcessException>().having(
            (error) => error.message,
            'message',
            contains('outra camada'),
          ),
        ),
      );
    },
  );
  test('an empty project has no predefined lanes', () {
    expect(TgiProject.empty(name: 'Vazio').tracks, isEmpty);
  });

  test('silent video creates one visual lane and no audio clip', () {
    final video = media('silent', MediaType.video);
    final project = projectWith(
      video,
    ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
    expect(project.tracks, hasLength(1));
    expect(project.tracks.single.kind, TrackKind.visual);
    expect(project.tracks.single.clips.single.trackType, TrackType.video);
  });

  test('video with audio creates linked clips only when audio exists', () {
    final video = media('sound', MediaType.video, audio: true);
    final project = projectWith(
      video,
    ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
    final image = content(project, TrackType.video);
    final audio = content(project, TrackType.audio);
    expect(project.tracks, hasLength(2));
    expect(audio.timelineGroupId, image.timelineGroupId);
    final moved = project.moveClipToNewTrack(
      image.id,
      timelineStart: const Duration(seconds: 3),
    );
    expect(
      content(moved, TrackType.audio).timelineStart,
      const Duration(seconds: 3),
    );
    expect(
      content(moved, TrackType.video).timelineStart,
      const Duration(seconds: 3),
    );
    final cut = moved.splitTimelineClipGroupAt(
      image.id,
      timelinePosition: const Duration(seconds: 4),
    );
    expect(cut.tracks.expand((track) => track.clips), hasLength(4));
    for (final clip in cut.tracks.expand((track) => track.clips)) {
      expect(clip.duration, const Duration(seconds: 1));
    }
  });

  test('one visual lane accepts video, image and title without conversion', () {
    final video = media('video', MediaType.video);
    final image = media('image', MediaType.image);
    var project = projectWith(video)
        .addMediaItem(image)
        .addMediaItemToTimeline(video, timelineStart: Duration.zero);
    final lane = project.tracks.single.id;
    project = project.addMediaItemToTimeline(
      image,
      targetTrackId: lane,
      timelineStart: const Duration(seconds: 2),
      clipDurationOverride: const Duration(seconds: 2),
    );
    project = project.addTextClipToTimeline(
      text: 'Título',
      targetTrackId: lane,
      timelineStart: const Duration(seconds: 4),
    );
    expect(project.tracks, hasLength(1));
    expect(project.tracks.single.clips.map((clip) => clip.trackType), [
      TrackType.video,
      TrackType.image,
      TrackType.text,
    ]);
    expect(
      project
          .clipAt(const Duration(seconds: 5), trackType: TrackType.text)
          ?.textContent,
      'Título',
    );
  });

  test('image over video and title over image create lanes only as needed', () {
    final video = media('video', MediaType.video);
    final image = media('image', MediaType.image);
    var project = projectWith(video)
        .addMediaItem(image)
        .addMediaItemToTimeline(video, timelineStart: Duration.zero)
        .addMediaItemToTimeline(image, timelineStart: Duration.zero)
        .addTextClipToTimeline(text: 'Título', timelineStart: Duration.zero);
    expect(project.tracks, hasLength(3));
    expect(project.visualClipsAt(Duration.zero).map((clip) => clip.trackType), [
      TrackType.video,
      TrackType.image,
      TrackType.text,
    ]);
    project = project.addMediaItemToTimeline(
      image,
      timelineStart: const Duration(seconds: 8),
    );
    expect(project.tracks, hasLength(3));
  });

  test('video moves vertically into a compatible visual lane', () {
    final video = media('video', MediaType.video);
    var project = projectWith(
      video,
    ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
    final clip = content(project, TrackType.video);
    project = project.addTimelineTrack(TrackType.text);
    final target = project.tracks.first;
    final moved = project.moveClipToTrack(
      clip.id,
      targetTrackId: target.id,
      timelineStart: const Duration(seconds: 1),
    );
    expect(moved.trackForClip(clip.id)?.id, target.id);
    expect(
      content(moved, TrackType.video).timelineStart,
      const Duration(seconds: 1),
    );
  });

  test(
    'moving a linked group onto a locked companion is rejected atomically',
    () {
      final video = media('video', MediaType.video, audio: true);
      var project = projectWith(
        video,
      ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
      final clip = content(project, TrackType.video);
      project = project.setTimelineTrackLocked(project.tracks.last.id, true);
      expect(
        project.moveClipToNewTrack(
          clip.id,
          timelineStart: const Duration(seconds: 3),
        ),
        same(project),
      );
      expect(content(project, TrackType.video).timelineStart, Duration.zero);
    },
  );

  test('collisions and incompatible drops preserve the original snapshot', () {
    final video = media('video', MediaType.video);
    var project = projectWith(
      video,
    ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
    final first = content(project, TrackType.video);
    project = project.addMediaItemToTimeline(
      video,
      timelineStart: Duration.zero,
      forceNewVideoTrack: true,
    );
    expect(
      project.moveClipToTrack(
        first.id,
        targetTrackId: project.tracks.first.id,
        timelineStart: Duration.zero,
      ),
      same(project),
    );
    project = project.addTimelineTrack(TrackType.audio);
    expect(
      project.moveClipToTrack(
        first.id,
        targetTrackId: project.tracks.last.id,
        timelineStart: Duration.zero,
      ),
      same(project),
    );
  });

  test('multiple selected clips move vertically and keep temporal spacing', () {
    final video = media('video', MediaType.video);
    var project = projectWith(video)
        .addTimelineTrack(TrackType.video)
        .addTimelineTrack(TrackType.video)
        .addTimelineTrack(TrackType.video);
    final ids = project.tracks.map((track) => track.id).toList();
    project = project
        .addMediaItemToTimeline(
          video,
          targetTrackId: ids[0],
          timelineStart: Duration.zero,
        )
        .addMediaItemToTimeline(
          video,
          targetTrackId: ids[1],
          timelineStart: const Duration(seconds: 3),
        );
    final clips = project.tracks.expand((track) => track.clips).toList();
    final moved = project.placeClipGroups(
      clips[0].id,
      targetTrackId: ids[1],
      timelineStart: const Duration(seconds: 2),
      selectedGroups: clips.map((clip) => clip.timelineGroupId).toSet(),
    );
    expect(moved.trackForClip(clips[0].id)?.id, ids[1]);
    expect(moved.trackForClip(clips[1].id)?.id, ids[2]);
    expect(
      moved.tracks
          .expand((track) => track.clips)
          .map((clip) => clip.timelineStart),
      [const Duration(seconds: 2), const Duration(seconds: 5)],
    );
  });

  test('unlinking and removing only audio preserve the video', () {
    final video = media('video', MediaType.video, audio: true);
    final project = projectWith(
      video,
    ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
    final clip = content(project, TrackType.video);
    final unlinked = project.unlinkAudioFromTimelineGroup(clip.timelineGroupId);
    expect(
      content(unlinked, TrackType.audio).timelineGroupId,
      isNot(clip.timelineGroupId),
    );
    final withoutAudio = project.removeGroupAudio(clip.timelineGroupId);
    expect(withoutAudio.tracks.expand((track) => track.clips), [clip]);
  });

  test('deleting and reordering tracks preserve the other linked content', () {
    final video = media('video', MediaType.video, audio: true);
    final project = projectWith(
      video,
    ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
    final reordered = project.reorderTrack(project.tracks.first.id, 1);
    expect(reordered.tracks.last.id, project.tracks.first.id);
    final deleted = project.deleteTrack(project.tracks.first.id);
    expect(deleted.tracks.single.clips.single.trackType, TrackType.audio);
  });

  test('format 14 round trips mixed content, heights, keyframes and links', () {
    final video = media('video', MediaType.video, audio: true);
    var project = projectWith(video)
        .addMediaItemToTimeline(video, timelineStart: Duration.zero)
        .addTextClipToTimeline(
          text: 'Título',
          timelineStart: const Duration(seconds: 3),
        );
    project = project.setTrackHeight(project.tracks.first.id, 112);
    final io = ProjectIOService();
    final data = io.serializeProject(project);
    expect(data['version'], 14);
    final loaded = io.deserializeProject(jsonDecode(jsonEncode(data))).project;
    expect(loaded.tracks.first.height, 112);
    expect(io.serializeProject(loaded), data);
  });

  test(
    'legacy migration preserves payload, IDs, timing, effects and audio links',
    () {
      final video = media('video', MediaType.video, audio: true);
      var project = projectWith(video).addMediaItemToTimeline(
        video,
        timelineStart: const Duration(seconds: 2),
      );
      final clip = content(project, TrackType.video);
      project = project.upsertClipKeyframe(
        clip.id,
        property: ClipKeyframeProperty.opacity,
        time: .5,
        value: .4,
      );
      final io = ProjectIOService();
      final legacy = io.serializeProject(project)..['version'] = 13;
      for (final track in legacy['tracks'] as List) {
        track.remove('kind');
        track.remove('height');
      }
      final before = jsonEncode(legacy);
      final migrated = io.deserializeProject(legacy).project;
      expect(jsonEncode(legacy), before);
      expect(content(migrated, TrackType.video).id, clip.id);
      expect(content(migrated, TrackType.video).keyframes.single.value, .4);
      expect(
        content(migrated, TrackType.audio).timelineGroupId,
        clip.timelineGroupId,
      );
      expect(
        content(migrated, TrackType.audio).timelineStart,
        const Duration(seconds: 2),
      );
    },
  );

  test('structural edits participate in undo/redo and preserve selection', () {
    final controller = EditorController(
      mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
    );
    addTearDown(controller.dispose);
    controller.addTimelineTrack(TrackType.video);
    final id = controller.project.tracks.single.id;
    controller.resizeTimelineTrack(id, 100);
    controller.deleteTimelineTrack(id);
    expect(controller.project.tracks, isEmpty);
    controller.undo();
    expect(controller.project.tracks.single.height, 100);
    controller.undo();
    expect(controller.project.tracks.single.height, 64);
    controller.redo();
    expect(controller.project.tracks.single.height, 100);
  });

  test('shift-insert moves complete linked groups in a single transaction', () {
    final video = media('insert', MediaType.video, audio: true);
    var project = projectWith(
      video,
    ).addMediaItemToTimeline(video, timelineStart: Duration.zero);
    final original = content(project, TrackType.video);
    final lane = project.trackForClip(original.id)!.id;
    project = project.insertMedia(
      video,
      timelineStart: Duration.zero,
      targetTrackId: lane,
    );
    expect(project.tracks, hasLength(2));
    expect(
      project.clipById(original.id)!.timelineStart,
      const Duration(seconds: 2),
    );
    expect(
      project.tracks
          .expand((track) => track.clips)
          .where((clip) => clip.timelineGroupId == original.timelineGroupId)
          .map((clip) => clip.timelineStart),
      everyElement(const Duration(seconds: 2)),
    );
    expect(
      project.insertMedia(
        video,
        timelineStart: const Duration(seconds: 1),
        targetTrackId: lane,
      ),
      same(project),
    );
  });

  test(
    'ripple removes the union of disjoint selections, preserving intervening clips',
    () {
      final video = media('ripple', MediaType.video);
      var project = projectWith(video);
      for (final time in [0, 4, 8, 12]) {
        project = project.addMediaItemToTimeline(
          video,
          timelineStart: Duration(seconds: time),
        );
      }
      final clips = project.tracks.single.clips;
      final result = project.rippleDeleteTimelineClipGroups({
        clips[0].timelineGroupId,
        clips[2].timelineGroupId,
      });
      expect(result.tracks.single.clips.map((clip) => clip.timelineStart), [
        const Duration(seconds: 2),
        const Duration(seconds: 8),
      ]);
      expect(result.tracks.single.clips.map((clip) => clip.id), [
        clips[1].id,
        clips[3].id,
      ]);
    },
  );

  test('ripple cannot shift content on another locked lane', () {
    final video = media('locked_ripple', MediaType.video);
    var project = projectWith(video)
        .addMediaItemToTimeline(video, timelineStart: Duration.zero)
        .addTextClipToTimeline(
          text: 'Locked title',
          timelineStart: const Duration(seconds: 4),
        );
    final group = content(project, TrackType.video).timelineGroupId;
    project = project.setTimelineTrackLocked(project.tracks.first.id, true);
    expect(project.rippleDeleteTimelineClipGroups({group}), same(project));
  });

  test(
    'resizing cannot silently overlap a neighbour in the same visual lane',
    () {
      final image = media('resize', MediaType.image);
      final project = projectWith(image)
          .addMediaItemToTimeline(
            image,
            timelineStart: Duration.zero,
            clipDurationOverride: const Duration(seconds: 2),
          )
          .addMediaItemToTimeline(
            image,
            timelineStart: const Duration(seconds: 2),
          );
      final clip = content(project, TrackType.image);
      expect(
        project.resizeImageClip(
          clip.id,
          timelineStart: Duration.zero,
          duration: const Duration(seconds: 3),
        ),
        same(project),
      );
    },
  );

  test(
    'independent audio speed changes its duration without moving visual content',
    () {
      final audio = media('sound', MediaType.audio, audio: true);
      final video = media('picture', MediaType.video);
      final project = projectWith(audio)
          .addMediaItem(video)
          .addMediaItemToTimeline(audio, timelineStart: Duration.zero)
          .addMediaItemToTimeline(
            video,
            timelineStart: const Duration(seconds: 4),
          );
      final clip = content(project, TrackType.audio);
      final changed = project.changeAudioSpeed(clip.timelineGroupId, .5);
      expect(
        content(changed, TrackType.audio).duration,
        const Duration(seconds: 4),
      );
      expect(
        content(changed, TrackType.video).timelineStart,
        const Duration(seconds: 4),
      );
      expect(
        content(changed, TrackType.audio).effectiveSourceDuration,
        clip.effectiveSourceDuration,
      );
    },
  );
}
