import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/audio_waveform.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/timeline_transition.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/services/audio_waveform_service.dart';
import 'package:tgi_video_editor/services/auto_caption_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';

void main() {
  test('preview follows the timeline playhead once clips exist', () async {
    final mediaItem = _mediaItem();
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();

    expect(controller.selectedMediaItem, mediaItem);
    expect(controller.previewMediaItem, mediaItem);
    expect(controller.previewSourcePosition, Duration.zero);

    controller.addMediaItemToTimeline(mediaItem, const Duration(seconds: 5));

    expect(controller.playheadPosition, const Duration(seconds: 5));
    expect(controller.previewMediaItem, mediaItem);
    expect(controller.previewSourcePosition, Duration.zero);

    controller.setPlayheadPosition(const Duration(seconds: 8));

    expect(controller.previewMediaItem, mediaItem);
    expect(controller.previewSourcePosition, const Duration(seconds: 3));

    controller.updatePlayheadFromPreview(
      mediaItem.id,
      const Duration(seconds: 6),
    );

    expect(controller.playheadPosition, const Duration(seconds: 11));

    controller.setPlayheadPosition(const Duration(seconds: 20));

    expect(controller.previewMediaItem, isNull);
    expect(controller.previewSourcePosition, Duration.zero);
  });

  test('importVideo imports multiple files selected together', () async {
    final firstItem = _mediaItem(id: 'media_1', name: 'first.mp4');
    final secondItem = _mediaItem(id: 'media_2', name: 'second.mp4');
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService(
        const [],
        multiImportBatches: [
          [firstItem, secondItem],
        ],
      ),
    );

    await controller.importVideo();

    expect(controller.project.mediaPool.map((item) => item.id), [
      firstItem.id,
      secondItem.id,
    ]);
    expect(controller.selectedMediaItemId, secondItem.id);
    expect(controller.statusMessage, contains('2 arquivos'));
    expect(controller.canUndo, isTrue);

    controller.undo();

    expect(controller.project.mediaPool, isEmpty);
  });

  test(
    'first imported video is added to an empty timeline by the editor flow',
    () async {
      final mediaItem = _mediaItem(duration: 45);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideoAndAddToEmptyTimeline();

      final videoTrack = controller.project.tracks.singleWhere(
        (track) => track.type == TrackType.video,
      );
      final audioTrack = controller.project.tracks.singleWhere(
        (track) => track.type == TrackType.audio,
      );
      expect(videoTrack.clips, hasLength(1));
      expect(audioTrack.clips, hasLength(1));
      expect(videoTrack.clips.single.timelineStart, Duration.zero);
      expect(
        audioTrack.clips.single.timelineGroupId,
        videoTrack.clips.single.timelineGroupId,
      );
      expect(controller.selectedTimelineGroupId, isNotNull);
      expect(controller.statusMessage, contains('adicionado à timeline'));
    },
  );

  test('first imported image is added to an empty timeline', () async {
    final mediaItem = _mediaItem(
      id: 'image_1',
      type: MediaType.image,
      name: 'cover.png',
      duration: 5,
    );
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importMediaAndAddToEmptyTimeline();

    final imageTrack = controller.project.tracks.singleWhere(
      (track) => track.type == TrackType.image,
    );
    expect(imageTrack.clips, hasLength(1));
    expect(imageTrack.clips.single.timelineStart, Duration.zero);
    expect(controller.selectedTimelineGroupId, isNotNull);
    expect(controller.statusMessage, contains('Imagem adicionada à timeline'));
  });

  test(
    'preview advances across an adjacent clip at the timeline boundary',
    () async {
      final firstItem = _mediaItem(id: 'media_1', duration: 9);
      final secondItem = _mediaItem(id: 'media_2', duration: 7);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([firstItem, secondItem]),
      );

      await controller.importVideo();
      await controller.importVideo();
      controller.addMediaItemToTimeline(firstItem, Duration.zero);
      controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 9));

      controller.setPlayheadPosition(const Duration(milliseconds: 8980));
      expect(controller.previewMediaItem?.id, firstItem.id);

      controller.updatePlayheadFromPreview(
        firstItem.id,
        const Duration(seconds: 9),
      );

      expect(controller.playheadPosition, const Duration(seconds: 9));
      expect(controller.previewMediaItem?.id, secondItem.id);
      expect(controller.previewSourcePosition, Duration.zero);
    },
  );

  test(
    'stale completed position from previous media does not map to next clip',
    () async {
      final firstItem = _mediaItem(id: 'media_1', duration: 9);
      final secondItem = _mediaItem(id: 'media_2', duration: 12);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([firstItem, secondItem]),
      );

      await controller.importVideo();
      await controller.importVideo();
      controller.addMediaItemToTimeline(firstItem, Duration.zero);
      controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 9));

      controller.setPlayheadPosition(const Duration(seconds: 9));
      expect(controller.previewMediaItem?.id, secondItem.id);

      controller.updatePlayheadFromPreview(
        firstItem.id,
        const Duration(seconds: 9),
      );

      expect(controller.playheadPosition, const Duration(seconds: 9));
      expect(controller.previewMediaItem?.id, secondItem.id);
      expect(controller.previewSourcePosition, Duration.zero);
    },
  );
  test(
    'preview maps source position to the next same-source cut clip',
    () async {
      final mediaItem = _mediaItem(duration: 9);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);
      final targetClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .single;

      controller.cutTimelineClip(targetClip.id, const Duration(seconds: 3));
      controller.setPlayheadPosition(const Duration(milliseconds: 2980));
      controller.updatePlayheadFromPreview(
        mediaItem.id,
        const Duration(milliseconds: 3250),
      );

      expect(controller.playheadPosition, const Duration(milliseconds: 3250));
      expect(
        controller.previewSourcePosition,
        const Duration(milliseconds: 3250),
      );
    },
  );

  test(
    'preview does not skip an inserted cut video between same-source clips',
    () async {
      final mediaItem = _mediaItem(id: 'media_1', duration: 9);
      final cutVideoItem = _mediaItem(
        id: 'media_cut_video',
        name: 'meme depois.mp4',
        duration: 2,
      );
      final cutVideoFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}tgi_cut_video.mp4',
      )..writeAsBytesSync([0, 1, 2]);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem, cutVideoItem]),
      );

      addTearDown(() {
        if (cutVideoFile.existsSync()) {
          cutVideoFile.deleteSync();
        }
      });

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);
      final originalClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .single;

      controller.cutTimelineClip(originalClip.id, const Duration(seconds: 5));
      controller.setPlayheadPosition(const Duration(milliseconds: 4900));
      await controller.insertTransitionClipAtNearestEdit(
        filePath: cutVideoFile.path,
        name: 'meme depois',
      );

      controller.setTimelinePlaybackActive(true);
      controller.setPlayheadPosition(const Duration(milliseconds: 4933));
      controller.updatePlayheadFromPreview(
        mediaItem.id,
        const Duration(milliseconds: 5333),
      );

      expect(controller.playheadPosition, const Duration(seconds: 5));
      expect(controller.previewMediaItem?.id, cutVideoItem.id);
      expect(controller.previewSourcePosition, Duration.zero);
      expect(controller.timelinePlaybackActive, isTrue);
    },
  );

  test('preview shows an image clip after the video ends', () async {
    final videoItem = _mediaItem(id: 'video_1', duration: 5);
    final imageItem = _mediaItem(
      id: 'image_1',
      name: 'final.png',
      type: MediaType.image,
      duration: 5,
    );
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([videoItem, imageItem]),
    );

    await controller.importVideo();
    await controller.importMediaFileFromPath(imageItem.filePath);
    controller.addMediaItemToTimeline(videoItem, Duration.zero);
    controller.addMediaItemToTimeline(imageItem, const Duration(seconds: 5));
    controller.setPlayheadPosition(const Duration(seconds: 6));

    expect(controller.previewMediaItem, isNull);
    expect(controller.activeImageOverlayClip?.mediaItemId, imageItem.id);
    expect(controller.activeImageOverlayClip?.imageFit, ImageClipFit.cover);
    expect(controller.imageOverlayMediaItem?.id, imageItem.id);
    expect(controller.allImageOverlaysAtPlayhead, hasLength(1));
  });

  test('preview source position uses a cut clip source offset', () async {
    final mediaItem = _mediaItem(duration: 9);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    final targetClip = controller.project.tracks
        .firstWhere((track) => track.type == TrackType.video)
        .clips
        .single;

    controller.cutTimelineClip(targetClip.id, const Duration(seconds: 3));
    controller.setPlayheadPosition(const Duration(seconds: 4));

    expect(controller.previewMediaItem?.id, mediaItem.id);
    expect(controller.previewSourcePosition, const Duration(seconds: 4));
  });

  test(
    'deleteSelectedTimelineClip removes the selected synced clip group',
    () async {
      final mediaItem = _mediaItem(duration: 12);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);
      final targetClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .single;
      controller.cutTimelineClip(targetClip.id, const Duration(seconds: 5));
      final rightGroupId = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .last
          .timelineGroupId;

      controller.selectTimelineClipGroup(rightGroupId);
      controller.deleteSelectedTimelineClip();

      final videoClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips;
      final audioClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.audio)
          .clips;
      expect(controller.selectedTimelineGroupId, isNull);
      expect(videoClips, hasLength(1));
      expect(audioClips, hasLength(1));
      expect(
        videoClips.single.timelineGroupId,
        audioClips.single.timelineGroupId,
      );
      expect(videoClips.single.timelineGroupId, isNot(rightGroupId));
    },
  );

  test(
    'selectTimelineClipGroups supports marquee modifiers and multi delete',
    () async {
      final mediaItem = _mediaItem(duration: 12);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);
      final firstClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .single;
      controller.cutTimelineClip(firstClip.id, const Duration(seconds: 4));
      final secondClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .firstWhere(
            (clip) => clip.timelineStart == const Duration(seconds: 4),
          );
      controller.cutTimelineClip(secondClip.id, const Duration(seconds: 8));

      final groupIds = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .map((clip) => clip.timelineGroupId)
          .toList();
      expect(groupIds, hasLength(3));

      controller.selectTimelineClipGroups({groupIds[0], groupIds[1]});
      expect(controller.selectedTimelineGroupIds, {groupIds[0], groupIds[1]});

      controller.selectTimelineClipGroups({groupIds[2]}, additive: true);
      expect(controller.selectedTimelineGroupIds, {
        groupIds[0],
        groupIds[1],
        groupIds[2],
      });

      controller.selectTimelineClipGroups({
        groupIds[1],
        groupIds[2],
      }, toggle: true);
      expect(controller.selectedTimelineGroupIds, {groupIds[0]});

      controller.selectTimelineClipGroups({
        groupIds[1],
        groupIds[2],
      }, additive: true);
      controller.selectTimelineClipGroups({
        groupIds[0],
        groupIds[2],
      }, intersect: true);
      expect(controller.selectedTimelineGroupIds, {groupIds[0], groupIds[2]});

      controller.selectTimelineClipGroup(groupIds[0], toggle: true);
      expect(controller.selectedTimelineGroupIds, {groupIds[2]});

      controller.selectTimelineClipGroups(const <String>{});
      expect(controller.selectedTimelineGroupId, isNull);
      expect(controller.selectedTimelineGroupIds, isEmpty);

      controller.selectTimelineClipGroups(groupIds.toSet());
      controller.deleteSelectedTimelineClip();

      expect(
        controller.project.tracks
            .firstWhere((track) => track.type == TrackType.video)
            .clips,
        isEmpty,
      );
      expect(
        controller.project.tracks
            .firstWhere((track) => track.type == TrackType.audio)
            .clips,
        isEmpty,
      );
    },
  );

  test(
    'fade applies independently to every video selected by marquee',
    () async {
      final mediaItem = _mediaItem(duration: 12);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);
      final videoTrack = controller.project.tracks.firstWhere(
        (track) => track.type == TrackType.video,
      );
      controller.cutTimelineClip(
        videoTrack.clips.single.id,
        const Duration(seconds: 4),
      );
      final middleClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .firstWhere(
            (clip) => clip.timelineStart == const Duration(seconds: 4),
          );
      controller.cutTimelineClip(middleClip.id, const Duration(seconds: 8));

      final groupIds = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .map((clip) => clip.timelineGroupId)
          .toSet();
      controller.selectTimelineClipGroups(groupIds);
      controller.enableFadeForSelectedClips(TrackType.video);

      final fadedVideos = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips;
      expect(fadedVideos, hasLength(3));
      for (final clip in fadedVideos) {
        expect(clip.fadeIn, const Duration(milliseconds: 500));
        expect(clip.fadeOut, const Duration(milliseconds: 500));
      }
      final linkedAudio = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.audio)
          .clips;
      for (final clip in linkedAudio) {
        expect(clip.fadeIn, Duration.zero);
        expect(clip.fadeOut, Duration.zero);
      }

      controller.undo();

      final restoredVideos = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips;
      for (final clip in restoredVideos) {
        expect(clip.fadeIn, Duration.zero);
        expect(clip.fadeOut, Duration.zero);
      }
    },
  );

  test(
    'unlinkSelectedAudioFromVideo lets audio be cut and deleted separately',
    () async {
      final mediaItem = _mediaItem(duration: 12);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);
      final videoGroupId = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .single
          .timelineGroupId;

      controller.selectTimelineClipGroup(videoGroupId);
      expect(controller.canUnlinkSelectedAudio, isTrue);

      controller.unlinkSelectedAudioFromVideo();
      final detachedAudioGroupId = controller.selectedTimelineGroupId;
      expect(detachedAudioGroupId, isNotNull);
      expect(detachedAudioGroupId, isNot(videoGroupId));
      expect(controller.canRelinkSelectedAudio, isTrue);

      controller.toggleSelectedAudioVideoLink();
      expect(controller.selectedTimelineGroupId, videoGroupId);
      expect(controller.selectedAudioVideoLinked, isTrue);
      expect(controller.canUnlinkSelectedAudio, isTrue);

      controller.toggleSelectedAudioVideoLink();
      final detachedAgainGroupId = controller.selectedTimelineGroupId;
      expect(detachedAgainGroupId, isNotNull);
      expect(detachedAgainGroupId, isNot(videoGroupId));

      final detachedAudioClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.audio)
          .clips
          .single;
      controller.cutTimelineClip(
        detachedAudioClip.id,
        const Duration(seconds: 5),
      );
      controller.selectTimelineClipGroup(detachedAgainGroupId!);
      controller.deleteSelectedTimelineClip();

      final videoClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips;
      final audioClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.audio)
          .clips;

      expect(videoClips, hasLength(1));
      expect(videoClips.single.timelineGroupId, videoGroupId);
      expect(audioClips, hasLength(1));
      expect(audioClips.single.timelineStart, const Duration(seconds: 5));
      expect(audioClips.single.timelineGroupId, isNot(videoGroupId));
    },
  );

  test('cutting detached video leaves its audio untouched', () async {
    final mediaItem = _mediaItem(duration: 12);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    final videoClip = controller.project.tracks
        .firstWhere((track) => track.type == TrackType.video)
        .clips
        .single;
    controller.selectTimelineClipGroup(videoClip.timelineGroupId);
    controller.unlinkSelectedAudioFromVideo();
    controller.selectTimelineClipGroup(videoClip.timelineGroupId);

    controller.cutTimelineClip(videoClip.id, const Duration(seconds: 5));

    expect(
      controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips,
      hasLength(2),
    );
    expect(
      controller.project.tracks
          .firstWhere((track) => track.type == TrackType.audio)
          .clips,
      hasLength(1),
    );
  });

  test(
    'newly added overlapping image stays selected and renders on top',
    () async {
      final videoItem = _mediaItem(id: 'video_1', duration: 12);
      final firstImage = _mediaItem(
        id: 'image_1',
        name: 'logo.png',
        type: MediaType.image,
        duration: 5,
      );
      final secondImage = _mediaItem(
        id: 'image_2',
        name: 'badge.png',
        type: MediaType.image,
        duration: 5,
      );
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([
          videoItem,
          firstImage,
          secondImage,
        ]),
      );

      await controller.importVideo();
      await controller.importVideo();
      await controller.importVideo();

      controller.addMediaItemToTimeline(videoItem, Duration.zero);
      controller.addMediaItemToTimeline(firstImage, const Duration(seconds: 2));
      final firstImageGroupId = controller.selectedTimelineGroupId;

      controller.addMediaItemToTimeline(
        secondImage,
        const Duration(seconds: 2),
      );

      final imageTracks = controller.project.tracks
          .where((track) => track.type == TrackType.image)
          .toList();
      final overlays = controller.allImageOverlaysAtPlayhead;

      expect(imageTracks, hasLength(2));
      expect(controller.selectedTimelineGroupId, isNot(firstImageGroupId));
      expect(controller.activeImageOverlayClip?.mediaItemId, secondImage.id);
      expect(controller.activeImageOverlayClip?.imageFit, ImageClipFit.overlay);
      expect(overlays, hasLength(2));
      expect(overlays.last.mediaItemId, secondImage.id);
    },
  );
  test(
    'addTextToTimeline selects the new text overlay at the playhead',
    () async {
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService(const []),
      );

      controller.setPlayheadPosition(const Duration(seconds: 3));
      controller.addTextToTimeline('Titulo rapido');

      final textTrack = controller.project.tracks.singleWhere(
        (track) => track.type == TrackType.text,
      );
      final textClip = textTrack.clips.single;

      expect(textClip.textContent, 'Titulo rapido');
      expect(textClip.timelineStart, const Duration(seconds: 3));
      expect(controller.selectedTimelineGroupId, textClip.timelineGroupId);
      expect(controller.allTextOverlaysAtPlayhead, [textClip]);
    },
  );
  test('manual captions remain available for review and editing', () {
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService(const []),
    );

    controller.addTextToTimeline('Legenda do short', registerAsCaption: true);

    expect(controller.generatedCaptionClips, hasLength(1));
    expect(
      controller.generatedCaptionClips.single.textContent,
      'Legenda do short',
    );
    expect(controller.canExportGeneratedCaptions, isTrue);

    controller.updateTextClipText(
      controller.generatedCaptionClips.single.id,
      'Legenda revisada',
    );
    expect(
      controller.generatedCaptionClips.single.textContent,
      'Legenda revisada',
    );
  });
  test(
    'text overlay keeps video preview and can be edited and moved',
    () async {
      final videoItem = _mediaItem(id: 'video_1', duration: 12);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([videoItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(videoItem, Duration.zero);
      controller.addTextToTimeline('Titulo rapido');

      final textClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.text)
          .clips
          .single;

      expect(controller.previewMediaItem?.id, videoItem.id);
      expect(controller.selectedTimelineGroupId, textClip.timelineGroupId);

      controller.updateTextClipProperties(
        textClip.id,
        text: 'Titulo editado',
        fontFamily: 'Courier New',
        fontSize: 64,
        textColor: 0xFF66D28F,
        backgroundColor: 0x00000000,
        opacity: 0.8,
        textAnimation: TextClipAnimation.rise,
      );
      controller.updateTextOverlayPosition(textClip.id, 0.25, 0.4);

      final updatedTextClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.text)
          .clips
          .single;

      expect(updatedTextClip.textContent, 'Titulo editado');
      expect(updatedTextClip.fontFamily, 'Courier New');
      expect(updatedTextClip.fontSize, 64);
      expect(updatedTextClip.textColor, 0xFF66D28F);
      expect(updatedTextClip.backgroundColor, 0x00000000);
      expect(updatedTextClip.opacity, 0.8);
      expect(updatedTextClip.textAnimation, TextClipAnimation.rise);
      expect(updatedTextClip.overlayX, 0.25);
      expect(updatedTextClip.overlayY, 0.4);
      expect(controller.previewMediaItem?.id, videoItem.id);
    },
  );

  test(
    'selected text clip properties update every selected text overlay',
    () async {
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService(const []),
      );

      controller.addTextToTimeline('Primeira');
      controller.setPlayheadPosition(const Duration(seconds: 2));
      controller.addTextToTimeline('Segunda');
      controller.setPlayheadPosition(const Duration(seconds: 4));
      controller.addTextToTimeline('Terceira');

      final textClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.text)
          .clips;
      controller.selectTimelineClipGroups({
        for (final clip in textClips) clip.timelineGroupId,
      });

      controller.updateSelectedTextClipProperties(
        fontFamily: 'Impact',
        fontSize: 88,
        textColor: 0xFFFFD166,
        backgroundColor: 0x99000000,
        opacity: 0.6,
        textAnimation: TextClipAnimation.pop,
      );
      controller.updateSelectedTextOverlayPosition(overlayX: 0.22);

      final updatedTextClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.text)
          .clips;
      expect(updatedTextClips.map((clip) => clip.textContent), [
        'Primeira',
        'Segunda',
        'Terceira',
      ]);
      for (final clip in updatedTextClips) {
        expect(clip.fontFamily, 'Impact');
        expect(clip.fontSize, 88);
        expect(clip.textColor, 0xFFFFD166);
        expect(clip.backgroundColor, 0x99000000);
        expect(clip.opacity, 0.6);
        expect(clip.textAnimation, TextClipAnimation.pop);
        expect(clip.overlayX, 0.22);
      }

      final draggedClip = updatedTextClips.first;
      controller.selectTextOverlayFromPreview(draggedClip.timelineGroupId);
      controller.beginInteractiveEdit();
      controller.updateTextOverlayPositionForSelection(
        draggedClip.id,
        0.68,
        0.31,
      );
      controller.updateTextOverlayPositionForSelection(
        draggedClip.id,
        0.72,
        0.35,
      );
      controller.commitInteractiveEdit();

      expect(controller.selectedTimelineGroupIds, {
        for (final clip in updatedTextClips) clip.timelineGroupId,
      });
      final movedTextClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.text)
          .clips;
      for (final clip in movedTextClips) {
        expect(clip.overlayX, 0.72);
        expect(clip.overlayY, 0.35);
      }

      controller.undo();
      final textClipsAfterUndo = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.text)
          .clips;
      for (final clip in textClipsAfterUndo) {
        expect(clip.overlayX, 0.22);
      }
    },
  );

  test('automatic captions create timed text clips from transcript', () async {
    final mediaItem = _mediaItem(duration: 8);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    controller.addAutomaticCaptionsFromText(
      'essa e uma frase para testar legenda automatica no editor',
      wordsPerCaption: 4,
    );

    final textClips = controller.project.tracks
        .firstWhere((track) => track.type == TrackType.text)
        .clips;

    expect(textClips, hasLength(3));
    expect(textClips.first.textContent, 'ESSA E UMA FRASE');
    expect(textClips.first.textAnimation, TextClipAnimation.pop);
    expect(controller.selectedTimelineGroupId, textClips.last.timelineGroupId);
    expect(controller.statusMessage, contains('3 blocos'));
  });

  test('generateAutomaticCaptions transcribes video and exports srt', () async {
    final mediaItem = _mediaItem(duration: 12);
    final tempDir = await Directory.systemTemp.createTemp('tgi_caption_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final captionService = _FakeAutoCaptionService(const [
      CaptionCue(
        start: Duration(seconds: 1),
        end: Duration(seconds: 3),
        text: 'Primeira fala',
      ),
      CaptionCue(
        start: Duration(seconds: 4),
        end: Duration(seconds: 7),
        text: 'Segunda fala sincronizada',
      ),
    ]);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
      autoCaptionService: captionService,
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);

    await controller.generateAutomaticCaptions(
      captionFontFamily: 'Impact',
      captionFontSize: 64,
      captionTextColor: 0xFFFFD166,
      captionBackgroundColor: 0x99000000,
      captionOpacity: 0.75,
      captionAnimation: TextClipAnimation.pop,
    );

    final textClips = controller.project.tracks
        .firstWhere((track) => track.type == TrackType.text)
        .clips;

    expect(captionService.mediaItems.single.id, mediaItem.id);
    expect(textClips, hasLength(2));
    expect(textClips.first.timelineStart, const Duration(seconds: 1));
    expect(textClips.first.textContent, 'Primeira fala');
    expect(textClips.first.fontFamily, 'Impact');
    expect(textClips.first.fontSize, 64);
    expect(textClips.first.textColor, 0xFFFFD166);
    expect(textClips.first.backgroundColor, 0x99000000);
    expect(textClips.first.opacity, 0.75);
    expect(textClips.first.textAnimation, TextClipAnimation.pop);
    expect(controller.generatedCaptionCues, hasLength(2));
    expect(controller.canExportGeneratedCaptions, isTrue);
    expect(controller.statusMessage, contains('2 blocos'));

    final output = '${tempDir.path}${Platform.pathSeparator}captions.srt';
    await controller.exportGeneratedCaptions(output, SubtitleExportFormat.srt);

    final contents = await File(output).readAsString();
    expect(contents, contains('00:00:01,000 --> 00:00:03,000'));
    expect(contents, contains('Primeira fala'));
  });

  test(
    'generateAutomaticCaptions processes every box-selected video clip',
    () async {
      final firstItem = _mediaItem(
        id: 'caption_media_1',
        name: 'first.mp4',
        duration: 6,
      );
      final secondItem = _mediaItem(
        id: 'caption_media_2',
        name: 'second.mp4',
        duration: 6,
      );
      var project = TgiProject.empty(
        name: 'Legendas em selecao multipla',
      ).addMediaItem(firstItem).addMediaItem(secondItem);
      project = project
          .addMediaItemToTimeline(firstItem, timelineStart: Duration.zero)
          .addMediaItemToTimeline(
            secondItem,
            timelineStart: const Duration(seconds: 6),
          );
      final selectedGroupIds = project.tracks
          .where((track) => track.type == TrackType.video)
          .expand((track) => track.clips)
          .map((clip) => clip.timelineGroupId)
          .toSet();
      final captionService = _FakeAutoCaptionService(const [
        CaptionCue(
          start: Duration(seconds: 1),
          end: Duration(seconds: 2),
          text: 'Fala selecionada',
        ),
      ]);
      final controller = EditorController(
        initialProject: project,
        mediaImportService: _FakeMediaImportService(const []),
        autoCaptionService: captionService,
        audioWaveformService: _FakeAudioWaveformService(
          const AudioWaveform(
            samples: [],
            sampleInterval: Duration(milliseconds: 100),
          ),
        ),
      );

      controller.selectTimelineClipGroups(selectedGroupIds);
      await controller.generateAutomaticCaptions();

      expect(captionService.mediaItems.map((item) => item.id), [
        firstItem.id,
        secondItem.id,
      ]);
      final textClips = controller.project.tracks
          .where((track) => track.type == TrackType.text)
          .expand((track) => track.clips)
          .toList();
      expect(textClips, hasLength(2));
      expect(textClips.first.timelineStart, const Duration(seconds: 1));
      expect(textClips.last.timelineStart, const Duration(seconds: 7));
      expect(controller.statusMessage, contains('em 2 videos'));
    },
  );

  test(
    'generateAutomaticCaptions trims leading silence from caption cues',
    () async {
      final mediaItem = _mediaItem(duration: 8);
      final waveformSamples = List<double>.filled(80, 0.01);
      for (var index = 25; index <= 29; index++) {
        waveformSamples[index] = 1;
      }
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
        autoCaptionService: _FakeAutoCaptionService(const [
          CaptionCue(
            start: Duration.zero,
            end: Duration(seconds: 5),
            text: 'Fala depois do silencio',
          ),
        ]),
        audioWaveformService: _FakeAudioWaveformService(
          AudioWaveform(
            samples: waveformSamples,
            sampleInterval: const Duration(milliseconds: 100),
          ),
        ),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);

      await controller.generateAutomaticCaptions();

      final textClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.text)
          .clips
          .single;

      expect(textClip.timelineStart, const Duration(milliseconds: 2420));
      expect(textClip.timelineEnd, const Duration(milliseconds: 3420));
    },
  );

  test('generateAutomaticCaptions prevents overlapping text clips', () async {
    final mediaItem = _mediaItem(duration: 8);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
      autoCaptionService: _FakeAutoCaptionService(const [
        CaptionCue(
          start: Duration.zero,
          end: Duration(seconds: 3),
          text: 'Primeira legenda',
        ),
        CaptionCue(
          start: Duration(seconds: 2),
          end: Duration(seconds: 5),
          text: 'Segunda legenda',
        ),
      ]),
      audioWaveformService: _FakeAudioWaveformService(
        const AudioWaveform(
          samples: [],
          sampleInterval: Duration(milliseconds: 100),
        ),
      ),
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);

    await controller.generateAutomaticCaptions();

    final textClips = controller.project.tracks
        .firstWhere((track) => track.type == TrackType.text)
        .clips;

    expect(textClips, hasLength(2));
    expect(textClips.first.timelineStart, Duration.zero);
    expect(textClips.first.timelineEnd, const Duration(seconds: 3));
    expect(textClips.last.timelineStart, const Duration(milliseconds: 3080));
    expect(textClips.last.timelineEnd, const Duration(seconds: 5));
  });

  test('generateAutomaticCaptions follows paired audio clip timing', () async {
    final mediaItem = _mediaItem(id: 'media_1', duration: 12);
    final now = DateTime(2026, 7, 11);
    final project = TgiProject(
      id: 'project_1',
      name: 'Projeto com audio deslocado',
      createdAt: now,
      updatedAt: now,
      mediaPool: [mediaItem],
      tracks: [
        Track(
          id: TgiProject.defaultVideoTrackId,
          name: 'Video',
          type: TrackType.video,
          clips: const [
            Clip(
              id: 'clip_video',
              mediaItemId: 'media_1',
              timelineGroupId: 'group_1',
              trackType: TrackType.video,
              timelineStart: Duration.zero,
              sourceStart: Duration.zero,
              duration: Duration(seconds: 12),
              sourceDuration: Duration(seconds: 12),
            ),
          ],
        ),
        Track(
          id: TgiProject.defaultAudioTrackId,
          name: 'Audio',
          type: TrackType.audio,
          clips: const [
            Clip(
              id: 'clip_audio',
              mediaItemId: 'media_1',
              timelineGroupId: 'group_1',
              trackType: TrackType.audio,
              timelineStart: Duration(seconds: 5),
              sourceStart: Duration(seconds: 2),
              duration: Duration(seconds: 8),
              sourceDuration: Duration(seconds: 8),
            ),
          ],
        ),
      ],
    );
    final controller = EditorController(
      initialProject: project,
      mediaImportService: _FakeMediaImportService(const []),
      autoCaptionService: _FakeAutoCaptionService(const [
        CaptionCue(
          start: Duration(seconds: 3),
          end: Duration(seconds: 4),
          text: 'Fala alinhada ao audio',
        ),
      ]),
    );

    await controller.generateAutomaticCaptions();

    final textClip = controller.project.tracks
        .firstWhere((track) => track.type == TrackType.text)
        .clips
        .single;

    expect(textClip.timelineStart, const Duration(seconds: 6));
    expect(textClip.timelineEnd, const Duration(seconds: 7));
  });

  test('audio noise reduction can be updated on selected audio clip', () async {
    final mediaItem = _mediaItem();
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    final audioClip = controller.selectedTimelineAudioClip!;

    controller.updateClipAudioNoiseReduction(audioClip.id, 18);

    expect(controller.selectedTimelineAudioClip?.audioNoiseReductionDb, 18);
  });

  test(
    'preview fade can be adjusted independently for video and audio',
    () async {
      final mediaItem = _mediaItem(duration: 10);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);

      final videoClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .single;
      final audioClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.audio)
          .clips
          .single;
      controller.selectTimelineClipGroup(videoClip.timelineGroupId);
      controller.updateClipTransition(
        videoClip.id,
        fadeIn: const Duration(seconds: 2),
        fadeOut: const Duration(seconds: 3),
      );

      expect(controller.activeVideoPreviewOpacity, 0);
      expect(controller.activeAudioVolume, 1);

      controller.setPlayheadPosition(const Duration(seconds: 1));

      expect(controller.activeVideoPreviewOpacity, closeTo(0.5, 0.001));
      expect(controller.activeAudioVolume, 1);

      controller.updateClipTransition(
        audioClip.id,
        fadeIn: const Duration(seconds: 2),
        fadeOut: const Duration(seconds: 3),
      );

      expect(controller.activeVideoPreviewOpacity, closeTo(0.5, 0.001));
      expect(controller.activeAudioVolume, closeTo(0.5, 0.001));

      controller.setPlayheadPosition(const Duration(seconds: 5));

      expect(controller.activeVideoPreviewOpacity, 1);
      expect(controller.activeAudioVolume, 1);

      controller.setPlayheadPosition(const Duration(milliseconds: 8500));

      expect(controller.activeVideoPreviewOpacity, closeTo(0.5, 0.001));
      expect(controller.activeAudioVolume, closeTo(0.5, 0.001));
    },
  );
  test('optimizePreview creates a proxy and preview uses it', () async {
    final mediaItem = _mediaItem(filePath: 'C:\\videos\\heavy.mp4');
    final proxyDirectory = await Directory.systemTemp.createTemp(
      'tgi_editor_proxy_test_',
    );
    final ffmpegService = _FakeFfmpegService(
      proxyPath: '${proxyDirectory.path}${Platform.pathSeparator}preview.mp4',
    );
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
      ffmpegService: ffmpegService,
    );

    await controller.importVideo();

    expect(controller.canOptimizePreview, isTrue);

    await controller.optimizePreview();

    final storedItem = controller.project.mediaPool.single;
    expect(storedItem.filePath, mediaItem.filePath);
    expect(storedItem.previewProxyPath, ffmpegService.proxyPath);
    expect(controller.previewMediaItem?.id, mediaItem.id);
    expect(controller.previewMediaItem?.filePath, ffmpegService.proxyPath);
    expect(controller.previewOptimizationProgress, 1);
    expect(controller.statusMessage, contains('Preview otimizado'));
    expect(ffmpegService.optimizedItemIds, [mediaItem.id]);
    await proxyDirectory.delete(recursive: true);
  });

  test('heavy imported video receives an automatic preview proxy', () async {
    final proxyDirectory = await Directory.systemTemp.createTemp(
      'tgi_editor_auto_proxy_test_',
    );
    final mediaItem = _mediaItem(
      filePath: 'C:\\videos\\4k.mp4',
      width: 3840,
      height: 2160,
    );
    final ffmpegService = _FakeFfmpegService(
      proxyPath: '${proxyDirectory.path}${Platform.pathSeparator}preview.mp4',
    );
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
      ffmpegService: ffmpegService,
    );

    await controller.importVideo();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(ffmpegService.optimizedItemIds, [mediaItem.id]);
    expect(controller.project.mediaPool.single.previewProxyPath, isNotNull);
    expect(controller.previewMediaItem?.filePath, ffmpegService.proxyPath);
    expect(controller.statusMessage, contains('automatico pronto'));
    await proxyDirectory.delete(recursive: true);
  });

  test('automatic preview policy ignores ordinary Full HD clips', () {
    expect(
      shouldAutomaticallyOptimizePreview(
        _mediaItem(width: 1920, height: 1080, duration: 90),
      ),
      isFalse,
    );
    expect(
      shouldAutomaticallyOptimizePreview(
        _mediaItem(width: 2560, height: 1440, duration: 90),
      ),
      isTrue,
    );
    expect(
      shouldAutomaticallyOptimizePreview(
        _mediaItem(width: 1920, height: 1080, duration: 601),
      ),
      isTrue,
    );
  });

  test(
    'preview optimization can be cancelled without showing an error',
    () async {
      final mediaItem = _mediaItem();
      final ffmpegService = _CancelableFakeFfmpegService();
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
        ffmpegService: ffmpegService,
      );

      await controller.importVideo();
      final optimization = controller.optimizePreview();
      expect(controller.isOptimizingPreview, isTrue);

      controller.cancelPreviewOptimization();
      await optimization;

      expect(ffmpegService.cancelled, isTrue);
      expect(controller.isOptimizingPreview, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.statusMessage, contains('cancelada'));
    },
  );

  test('silent gap playback advances into the next timeline clip', () async {
    final firstItem = _mediaItem(id: 'media_1', duration: 9);
    final secondItem = _mediaItem(id: 'media_2', duration: 7);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([firstItem, secondItem]),
    );

    await controller.importVideo();
    await controller.importVideo();
    controller.addMediaItemToTimeline(firstItem, Duration.zero);
    controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 12));

    controller.setPlayheadPosition(const Duration(seconds: 9));
    expect(controller.previewMediaItem, isNull);

    controller.setTimelinePlaybackActive(true);
    controller.advanceGapPlaybackForTesting(const Duration(seconds: 2));

    expect(controller.playheadPosition, const Duration(seconds: 11));
    expect(controller.previewMediaItem, isNull);
    expect(controller.timelinePlaybackActive, isTrue);

    controller.advanceGapPlaybackForTesting(const Duration(seconds: 2));

    expect(controller.playheadPosition, const Duration(seconds: 12));
    expect(controller.previewMediaItem?.id, secondItem.id);
    expect(controller.previewSourcePosition, Duration.zero);
    expect(controller.timelinePlaybackActive, isTrue);
  });

  test('silent gap playback stops while paused', () async {
    final firstItem = _mediaItem(id: 'media_1', duration: 9);
    final secondItem = _mediaItem(id: 'media_2', duration: 7);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([firstItem, secondItem]),
    );

    await controller.importVideo();
    await controller.importVideo();
    controller.addMediaItemToTimeline(firstItem, Duration.zero);
    controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 12));
    controller.setPlayheadPosition(const Duration(seconds: 9));

    controller.setTimelinePlaybackActive(true);
    controller.setTimelinePlaybackActive(false);
    controller.advanceGapPlaybackForTesting(const Duration(seconds: 5));

    expect(controller.playheadPosition, const Duration(seconds: 9));
    expect(controller.previewMediaItem, isNull);
    expect(controller.timelinePlaybackActive, isFalse);
  });
  test('preview stops on a timeline gap after the current clip ends', () async {
    final firstItem = _mediaItem(id: 'media_1', duration: 9);
    final secondItem = _mediaItem(id: 'media_2', duration: 7);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([firstItem, secondItem]),
    );

    await controller.importVideo();
    await controller.importVideo();
    controller.addMediaItemToTimeline(firstItem, Duration.zero);
    controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 12));

    controller.setPlayheadPosition(const Duration(milliseconds: 8980));
    controller.updatePlayheadFromPreview(
      firstItem.id,
      const Duration(seconds: 9),
    );

    expect(controller.playheadPosition, const Duration(seconds: 9));
    expect(controller.previewMediaItem, isNull);
    expect(controller.previewSourcePosition, Duration.zero);
  });
  test(
    'changing speed after cutting only affects the selected segment',
    () async {
      final mediaItem = _mediaItem(duration: 9);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);
      final targetClip = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .single;

      controller.cutTimelineClip(targetClip.id, const Duration(seconds: 5));
      final rightGroupId = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .last
          .timelineGroupId;

      controller.selectTimelineClipGroup(rightGroupId);
      controller.updateSelectedVideoPlaybackSpeed(2);

      final videoClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips;
      expect(videoClips.first.playbackSpeed, 1);
      expect(videoClips.first.duration, const Duration(seconds: 5));
      expect(videoClips.last.playbackSpeed, 2);
      expect(videoClips.last.sourceStart, const Duration(seconds: 5));
      expect(
        videoClips.last.effectiveSourceDuration,
        const Duration(seconds: 4),
      );
      expect(videoClips.last.duration, const Duration(seconds: 2));
    },
  );

  test('preview source mapping honors playback speed', () async {
    final mediaItem = _mediaItem(duration: 12);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    controller.updateSelectedVideoPlaybackSpeed(2);

    controller.setPlayheadPosition(const Duration(seconds: 2));
    expect(controller.previewSourcePosition, const Duration(seconds: 4));

    controller.updatePlayheadFromPreview(
      mediaItem.id,
      const Duration(seconds: 6),
    );
    expect(controller.playheadPosition, const Duration(seconds: 3));
  });

  test('preview source mapping honors reversed video clips', () async {
    final mediaItem = _mediaItem(duration: 6);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    controller.updateSelectedVideoReverse(true);

    expect(
      controller.previewSourcePosition,
      const Duration(milliseconds: 5999),
    );

    controller.setPlayheadPosition(const Duration(seconds: 2));

    expect(
      controller.previewSourcePosition,
      const Duration(milliseconds: 3999),
    );
  });

  test(
    'preview player position does not drive reversed video playhead',
    () async {
      final mediaItem = _mediaItem(duration: 6);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);
      controller.updateSelectedVideoReverse(true);

      controller.updatePlayheadFromPreview(
        mediaItem.id,
        const Duration(milliseconds: 5999),
      );

      expect(controller.playheadPosition, Duration.zero);

      controller.setPlayheadPosition(const Duration(seconds: 2));
      controller.updatePlayheadFromPreview(mediaItem.id, Duration.zero);

      expect(controller.playheadPosition, const Duration(seconds: 2));
    },
  );

  test('freeze frame inserts a video clip between split video parts', () async {
    final mediaItem = _mediaItem(duration: 6);
    final ffmpegService = _FakeFfmpegService(proxyPath: '');
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
      ffmpegService: ffmpegService,
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    controller.setPlayheadPosition(const Duration(seconds: 2));

    await controller.insertFreezeFrameAtPlayhead();

    final videoTrack = controller.project.tracks.firstWhere(
      (track) => track.type == TrackType.video,
    );
    final audioTrack = controller.project.tracks.firstWhere(
      (track) => track.type == TrackType.audio,
    );
    final videoClips = videoTrack.clips;
    final audioClips = audioTrack.clips;
    final freezeClip = videoClips[1];
    final freezeItem = controller.project.mediaItemById(freezeClip.mediaItemId);

    expect(ffmpegService.extractedFrames, hasLength(1));
    expect(ffmpegService.freezeVideos, hasLength(1));
    expect(videoClips, hasLength(3));
    expect(audioClips, hasLength(3));
    expect(videoClips.map((clip) => clip.mediaItemId), [
      mediaItem.id,
      freezeClip.mediaItemId,
      mediaItem.id,
    ]);
    expect(videoClips.map((clip) => clip.timelineStart), [
      Duration.zero,
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
    expect(videoClips.map((clip) => clip.duration), [
      const Duration(seconds: 2),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
    expect(videoClips.last.sourceStart, const Duration(seconds: 2));
    expect(freezeItem?.type, MediaType.video);
    expect(freezeItem?.filePath, endsWith('.mp4'));
    expect(controller.selectedMediaItemId, freezeItem?.id);
    expect(controller.errorMessage, isNull);
  });

  test('undo and redo restore three project edits in order', () async {
    final mediaItem = _mediaItem(duration: 12);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    final importedProject = controller.project;

    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    final withClipProject = controller.project;

    controller.updateSelectedVideoPlaybackSpeed(2);
    final spedProject = controller.project;
    final spedClip = spedProject.tracks
        .firstWhere((track) => track.type == TrackType.video)
        .clips
        .single;

    controller.cutTimelineClip(spedClip.id, const Duration(seconds: 3));
    final splitProject = controller.project;
    expect(
      splitProject.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips,
      hasLength(2),
    );
    expect(controller.canUndo, isTrue);
    expect(controller.canRedo, isFalse);

    controller.undo();
    expect(controller.project, same(spedProject));
    expect(controller.canRedo, isTrue);

    controller.undo();
    expect(controller.project, same(withClipProject));

    controller.undo();
    expect(controller.project, same(importedProject));
    expect(controller.project.tracks, isEmpty);

    controller.redo();
    expect(controller.project, same(withClipProject));

    controller.redo();
    expect(controller.project, same(spedProject));

    controller.redo();
    expect(controller.project, same(splitProject));
    expect(controller.canRedo, isFalse);
  });

  test('trim preview commits as one undoable project edit', () async {
    final mediaItem = _mediaItem(duration: 12);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    controller.addMediaItemToTimeline(mediaItem, Duration.zero);
    final timelineProject = controller.project;
    final videoClip = timelineProject.tracks
        .firstWhere((track) => track.type == TrackType.video)
        .clips
        .single;

    controller.previewTimelineClipTrim(
      videoClip.id,
      sourceStart: const Duration(seconds: 2),
      sourceDuration: const Duration(seconds: 8),
      previewTimelinePosition: Duration.zero,
    );

    expect(controller.previewSourcePosition, const Duration(seconds: 2));
    expect(
      controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips
          .single
          .sourceStart,
      const Duration(seconds: 2),
    );

    controller.commitTimelineClipTrim(
      videoClip.id,
      sourceStart: const Duration(seconds: 2),
      sourceDuration: const Duration(seconds: 8),
      previewTimelinePosition: Duration.zero,
    );
    final trimmedProject = controller.project;
    final trimmedVideoClip = trimmedProject.tracks
        .firstWhere((track) => track.type == TrackType.video)
        .clips
        .single;

    expect(trimmedVideoClip.sourceStart, const Duration(seconds: 2));
    expect(trimmedVideoClip.duration, const Duration(seconds: 8));

    controller.undo();
    expect(controller.project, same(timelineProject));

    controller.redo();
    expect(controller.project, same(trimmedProject));
  });

  test('importMediaFileFromPath adds downloaded audio to media pool', () async {
    final audioItem = _mediaItem(
      id: 'media_audio_1',
      type: MediaType.audio,
      duration: 1,
      name: 'click1.wav',
      filePath: r'C:\cache\click1.wav',
    );
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([audioItem]),
    );

    final imported = await controller.importMediaFileFromPath(
      r'C:\cache\click1.wav',
      displayName: 'Click 1.wav',
    );

    expect(imported, isNotNull);
    expect(imported!.type, MediaType.audio);
    expect(imported.name, 'Click 1.wav');
    expect(controller.project.mediaPool.single.id, audioItem.id);
    expect(controller.project.mediaPool.single.name, 'Click 1.wav');
    expect(controller.selectedMediaItemId, audioItem.id);
    expect(controller.statusMessage, contains('Click 1.wav'));
  });

  test(
    'importAudioFileFromPathToNewTimelineTrack creates a new audio line',
    () async {
      final firstAudio = _mediaItem(
        id: 'media_audio_1',
        type: MediaType.audio,
        duration: 2,
        name: 'click1.wav',
        filePath: r'C:\cache\click1.wav',
      );
      final secondAudio = _mediaItem(
        id: 'media_audio_2',
        type: MediaType.audio,
        duration: 2,
        name: 'switch1.wav',
        filePath: r'C:\cache\switch1.wav',
      );
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([firstAudio, secondAudio]),
      );

      controller.setPlayheadPosition(const Duration(seconds: 4));
      final firstImported = await controller
          .importAudioFileFromPathToNewTimelineTrack(
            r'C:\cache\click1.wav',
            displayName: 'Click 1.wav',
          );
      final secondImported = await controller
          .importAudioFileFromPathToNewTimelineTrack(
            r'C:\cache\switch1.wav',
            displayName: 'Switch 1.wav',
          );

      expect(firstImported?.id, firstAudio.id);
      expect(secondImported?.id, secondAudio.id);
      final audioTracks = controller.project.tracks
          .where((track) => track.type == TrackType.audio)
          .toList();
      expect(audioTracks, hasLength(2));
      expect(audioTracks.every((track) => track.clips.length == 1), isTrue);
      expect(
        audioTracks.map((track) => track.clips.single.mediaItemId),
        containsAll([firstAudio.id, secondAudio.id]),
      );
      expect(
        audioTracks.map((track) => track.clips.single.timelineStart).toSet(),
        {const Duration(seconds: 4)},
      );
      expect(controller.activeStandaloneAudioPreviewClips, hasLength(2));
      expect(
        controller.activeStandaloneAudioPreviewClips.map(
          (entry) => entry.mediaItem.id,
        ),
        containsAll([firstAudio.id, secondAudio.id]),
      );
    },
  );

  test(
    'library audio remains selected and can be deleted from timeline',
    () async {
      final audioItem = _mediaItem(
        id: 'media_library_audio',
        type: MediaType.audio,
        duration: 4,
        name: 'trilha.wav',
        filePath: r'C:\cache\trilha.wav',
      );
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([audioItem]),
      );

      await controller.importAudioFileFromPathToNewTimelineTrack(
        audioItem.filePath,
        displayName: 'Trilha.wav',
      );

      expect(controller.selectedTimelineGroupIds, hasLength(1));
      expect(
        controller.project.tracks
            .where((track) => track.type == TrackType.audio)
            .expand((track) => track.clips),
        hasLength(1),
      );

      controller.deleteSelectedTimelineClip();

      expect(
        controller.project.tracks
            .where((track) => track.type == TrackType.audio)
            .expand((track) => track.clips),
        isEmpty,
      );
      expect(controller.project.mediaPool.single.id, audioItem.id);
    },
  );

  test(
    'moveTimelineClipToTrack moves standalone audio between audio lines',
    () async {
      final firstAudio = _mediaItem(
        id: 'media_audio_1',
        type: MediaType.audio,
        duration: 2,
        name: 'click1.wav',
        filePath: r'C:\cache\click1.wav',
      );
      final secondAudio = _mediaItem(
        id: 'media_audio_2',
        type: MediaType.audio,
        duration: 2,
        name: 'switch1.wav',
        filePath: r'C:\cache\switch1.wav',
      );
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([firstAudio, secondAudio]),
      );

      await controller.importAudioFileFromPathToNewTimelineTrack(
        r'C:\cache\click1.wav',
        displayName: 'Click 1.wav',
      );
      await controller.importAudioFileFromPathToNewTimelineTrack(
        r'C:\cache\switch1.wav',
        displayName: 'Switch 1.wav',
      );
      final audioTracks = controller.project.tracks
          .where((track) => track.type == TrackType.audio)
          .toList();
      final sourceTrack = audioTracks.first;
      final targetTrack = audioTracks.last;
      final movedClipId = sourceTrack.clips.single.id;

      controller.moveTimelineClipToTrack(
        movedClipId,
        targetTrack.id,
        const Duration(seconds: 5),
      );

      final updatedSourceTrack = controller.project.trackById(sourceTrack.id)!;
      final updatedTargetTrack = controller.project.trackById(targetTrack.id)!;
      expect(updatedSourceTrack.clips, isEmpty);
      expect(
        updatedTargetTrack.clips.map((clip) => clip.id),
        contains(movedClipId),
      );
      expect(
        updatedTargetTrack.clips
            .firstWhere((clip) => clip.id == movedClipId)
            .timelineStart,
        const Duration(seconds: 5),
      );
    },
  );

  test(
    'moveTimelineClipToNewTrack creates a new audio line for standalone audio',
    () async {
      final audioItem = _mediaItem(
        id: 'media_audio_1',
        type: MediaType.audio,
        duration: 2,
        name: 'click1.wav',
        filePath: r'C:\cache\click1.wav',
      );
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([audioItem]),
      );

      await controller.importAudioFileFromPathToNewTimelineTrack(
        r'C:\cache\click1.wav',
        displayName: 'Click 1.wav',
      );
      final sourceTrack = controller.project.tracks.single;
      final movedClipId = sourceTrack.clips.single.id;

      controller.moveTimelineClipToNewTrack(
        movedClipId,
        const Duration(seconds: 5),
      );

      final audioTracks = controller.project.tracks
          .where((track) => track.type == TrackType.audio)
          .toList();
      expect(audioTracks, hasLength(2));
      expect(audioTracks.first.id, sourceTrack.id);
      expect(audioTracks.first.clips, isEmpty);
      expect(audioTracks.last.clips.single.id, movedClipId);
      expect(
        audioTracks.last.clips.single.timelineStart,
        const Duration(seconds: 5),
      );
      expect(controller.playheadPosition, const Duration(seconds: 5));
    },
  );

  test(
    'standalone audio preview excludes the video paired audio clip',
    () async {
      final videoItem = _mediaItem(id: 'video_1', duration: 12);
      final soundEffect = _mediaItem(
        id: 'media_audio_1',
        type: MediaType.audio,
        duration: 2,
        name: 'click1.wav',
        filePath: r'C:\cache\click1.wav',
      );
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([videoItem, soundEffect]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(videoItem, Duration.zero);

      expect(controller.activeStandaloneAudioPreviewClips, isEmpty);

      await controller.importAudioFileFromPathToNewTimelineTrack(
        r'C:\cache\click1.wav',
        displayName: 'Click 1.wav',
      );

      expect(controller.activeStandaloneAudioPreviewClips, hasLength(1));
      expect(
        controller.activeStandaloneAudioPreviewClips.single.mediaItem.id,
        soundEffect.id,
      );
    },
  );
  test('removeMediaItem removes unused media and blocks used media', () async {
    final used = _mediaItem(id: 'used', name: 'used.mp4');
    final unused = _mediaItem(id: 'unused', name: 'unused.mp4');
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([used, unused]),
    );

    await controller.importVideo();
    await controller.importVideo();

    controller.removeMediaItem(unused.id);

    expect(controller.project.mediaPool.map((item) => item.id), [used.id]);
    expect(controller.selectedMediaItemId, isNull);
    expect(controller.statusMessage, contains('unused.mp4'));

    controller.addMediaItemToTimeline(used, Duration.zero);
    controller.removeMediaItem(used.id);

    expect(controller.project.mediaPool.map((item) => item.id), [used.id]);
    expect(controller.errorMessage, contains('Remova os clipes'));
  });

  test('relinkMedia updates the path and selects the relinked item', () async {
    final mediaItem = _mediaItem(filePath: r'C:\old\sample.mp4');
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([mediaItem]),
    );

    await controller.importVideo();
    controller.relinkMedia(const [
      MediaRelinkResult(
        mediaItemId: 'media_1',
        originalFilename: 'sample.mp4',
        newPath: r'D:\new\sample.mp4',
      ),
    ]);

    expect(
      controller.project.mediaItemById(mediaItem.id)?.filePath,
      r'D:\new\sample.mp4',
    );
    expect(controller.selectedMediaItemId, mediaItem.id);
    expect(controller.statusMessage, contains('sample.mp4'));
  });

  test(
    'applyTransitionAssetToNearestEdit stores transition at video edit',
    () async {
      final firstItem = _mediaItem(id: 'media_1', duration: 5);
      final secondItem = _mediaItem(id: 'media_2', duration: 5);
      final transitionFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}tgi_transition_test.mp4',
      )..writeAsBytesSync([0, 1, 2]);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([firstItem, secondItem]),
      );

      addTearDown(() {
        if (transitionFile.existsSync()) {
          transitionFile.deleteSync();
        }
      });

      await controller.importVideo();
      await controller.importVideo();
      controller.addMediaItemToTimeline(firstItem, Duration.zero);
      controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 5));
      controller.setPlayheadPosition(const Duration(milliseconds: 4800));

      controller.applyTransitionAssetToNearestEdit(
        filePath: transitionFile.path,
        name: 'Flash cut',
      );

      expect(controller.project.transitions, hasLength(1));
      expect(
        controller.project.transitions.single.timelinePosition,
        const Duration(seconds: 5),
      );
      expect(controller.project.transitions.single.name, 'Flash cut');
      expect(controller.playheadPosition, const Duration(seconds: 5));
      expect(controller.statusMessage, contains('00:05.000'));

      controller.applyTransitionAssetToNearestEdit(
        filePath: transitionFile.path,
        name: 'Flash cut atualizado',
      );

      expect(controller.project.transitions, hasLength(1));
      expect(
        controller.project.transitions.single.name,
        'Flash cut atualizado',
      );

      final transitionId = controller.project.transitions.single.id;
      controller.moveTimelineTransition(
        transitionId,
        const Duration(milliseconds: 4800),
      );

      expect(controller.project.transitions, hasLength(1));
      expect(
        controller.project.transitions.single.timelinePosition,
        const Duration(milliseconds: 4800),
      );
      expect(controller.playheadPosition, const Duration(milliseconds: 4800));
      expect(controller.statusMessage, contains('00:04.800'));
    },
  );

  test(
    'applyTransitionPresetToNearestEdit stores virtual transition at video edit',
    () async {
      final firstItem = _mediaItem(id: 'media_1', duration: 5);
      final secondItem = _mediaItem(id: 'media_2', duration: 5);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([firstItem, secondItem]),
      );

      await controller.importVideo();
      await controller.importVideo();
      controller.addMediaItemToTimeline(firstItem, Duration.zero);
      controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 5));
      controller.setPlayheadPosition(const Duration(milliseconds: 5100));

      controller.applyTransitionPresetToNearestEdit(
        preset: TimelineTransitionPreset.wipe,
        name: 'Wipe lateral',
        duration: const Duration(milliseconds: 1200),
        direction: TimelineTransitionDirection.rightToLeft,
        color: 0xFFFFFFFF,
        intensity: 0.75,
      );

      expect(controller.project.transitions, hasLength(1));
      final transition = controller.project.transitions.single;
      expect(transition.timelinePosition, const Duration(seconds: 5));
      expect(transition.filePath, isEmpty);
      expect(transition.preset, TimelineTransitionPreset.wipe);
      expect(transition.direction, TimelineTransitionDirection.rightToLeft);
      expect(transition.color, 0xFFFFFFFF);
      expect(transition.intensity, 0.75);
      expect(controller.playheadPosition, const Duration(seconds: 5));

      controller.updateTimelineTransitionProperties(
        transition.id,
        duration: const Duration(seconds: 3),
        intensity: 2,
      );

      final updated = controller.project.transitions.single;
      expect(updated.duration, const Duration(seconds: 2));
      expect(updated.intensity, 1);
    },
  );

  test(
    'applyTransitionAssetToNearestEdit accepts the beginning of a video',
    () async {
      final mediaItem = _mediaItem(id: 'media_1', duration: 5);
      final transitionFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}tgi_transition_empty.mp4',
      )..writeAsBytesSync([0, 1, 2]);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mediaItem]),
      );

      addTearDown(() {
        if (transitionFile.existsSync()) {
          transitionFile.deleteSync();
        }
      });

      await controller.importVideo();
      controller.addMediaItemToTimeline(mediaItem, Duration.zero);

      controller.applyTransitionAssetToNearestEdit(
        filePath: transitionFile.path,
        name: 'Flash cut',
      );

      expect(controller.project.transitions, hasLength(1));
      final transition = controller.project.transitions.single;
      expect(transition.timelinePosition, Duration.zero);
      expect(transition.timelineStart, Duration.zero);
      expect(transition.placement, TimelineTransitionPlacement.start);
      expect(controller.errorMessage, isNull);
    },
  );

  test('transition at a video start after a gap runs forward', () async {
    final firstItem = _mediaItem(id: 'media_1', duration: 2);
    final secondItem = _mediaItem(id: 'media_2', duration: 3);
    final controller = EditorController(
      mediaImportService: _FakeMediaImportService([firstItem, secondItem]),
    );

    await controller.importVideo();
    await controller.importVideo();
    controller.addMediaItemToTimeline(firstItem, Duration.zero);
    controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 5));

    controller.applyTransitionPresetToNearestEdit(
      preset: TimelineTransitionPreset.fade,
      name: 'Entrada',
      duration: const Duration(milliseconds: 800),
      timelinePosition: const Duration(milliseconds: 5100),
    );

    final transition = controller.project.transitions.single;
    expect(transition.timelinePosition, const Duration(seconds: 5));
    expect(transition.timelineStart, const Duration(seconds: 5));
    expect(transition.timelineEnd, const Duration(milliseconds: 5800));
    expect(transition.placement, TimelineTransitionPlacement.start);
  });

  test(
    'insertTransitionClipAtNearestEdit inserts a video between adjacent clips',
    () async {
      final firstItem = _mediaItem(id: 'media_1', duration: 5);
      final secondItem = _mediaItem(id: 'media_2', duration: 5);
      final transitionItem = _mediaItem(
        id: 'media_transition',
        name: '5 segundos depois.mp4',
        duration: 2,
      );
      final transitionFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}tgi_transition_clip.mp4',
      )..writeAsBytesSync([0, 1, 2]);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([
          firstItem,
          secondItem,
          transitionItem,
        ]),
      );

      addTearDown(() {
        if (transitionFile.existsSync()) {
          transitionFile.deleteSync();
        }
      });

      await controller.importVideo();
      await controller.importVideo();
      controller.addMediaItemToTimeline(firstItem, Duration.zero);
      controller.addMediaItemToTimeline(secondItem, const Duration(seconds: 5));
      controller.setPlayheadPosition(const Duration(milliseconds: 4900));
      controller.setTimelinePlaybackActive(true);

      await controller.insertTransitionClipAtNearestEdit(
        filePath: transitionFile.path,
        name: '5 segundos depois',
      );

      final videoClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips;
      final audioClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.audio)
          .clips;

      expect(videoClips.map((clip) => clip.mediaItemId), [
        'media_1',
        'media_transition',
        'media_2',
      ]);
      expect(videoClips.map((clip) => clip.timelineStart), [
        Duration.zero,
        const Duration(seconds: 5),
        const Duration(seconds: 7),
      ]);
      expect(audioClips.map((clip) => clip.timelineStart), [
        Duration.zero,
        const Duration(seconds: 5),
        const Duration(seconds: 7),
      ]);
      expect(controller.selectedMediaItemId, transitionItem.id);
      expect(controller.playheadPosition, const Duration(seconds: 5));
      expect(controller.timelinePlaybackActive, isFalse);
      expect(controller.previewMediaItem?.id, transitionItem.id);
      expect(controller.previewSourcePosition, Duration.zero);
      final nextAfterCutVideoStarts = controller.nextVideoPreviewClip;
      expect(nextAfterCutVideoStarts?.mediaItem.id, secondItem.id);
      expect(
        nextAfterCutVideoStarts?.timelineStart,
        const Duration(seconds: 7),
      );

      controller.setPlayheadPosition(const Duration(milliseconds: 4900));
      final nextBeforeEdit = controller.nextVideoPreviewClip;
      expect(nextBeforeEdit?.mediaItem.id, transitionItem.id);
      expect(nextBeforeEdit?.timelineStart, const Duration(seconds: 5));
      expect(nextBeforeEdit?.sourcePosition, Duration.zero);
      expect(controller.statusMessage, contains('Clipe de transicao inserido'));
    },
  );

  test(
    'insertTransitionClipAtNearestEdit inserts at playhead without edit',
    () async {
      final mainItem = _mediaItem(id: 'media_1', duration: 12);
      final cutItem = _mediaItem(
        id: 'media_cut',
        name: 'corte rapido.mp4',
        duration: 2,
      );
      final cutFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}tgi_cutaway_clip.mp4',
      )..writeAsBytesSync([0, 1, 2]);
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([mainItem, cutItem]),
      );

      addTearDown(() {
        if (cutFile.existsSync()) {
          cutFile.deleteSync();
        }
      });

      await controller.importVideo();
      controller.addMediaItemToTimeline(mainItem, Duration.zero);
      controller.setPlayheadPosition(const Duration(seconds: 3));

      await controller.insertTransitionClipAtNearestEdit(
        filePath: cutFile.path,
        name: 'corte rapido',
      );

      final videoClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.video)
          .clips;
      final audioClips = controller.project.tracks
          .firstWhere((track) => track.type == TrackType.audio)
          .clips;

      expect(videoClips.map((clip) => clip.mediaItemId), [
        mainItem.id,
        cutItem.id,
        mainItem.id,
      ]);
      expect(videoClips.map((clip) => clip.timelineStart), [
        Duration.zero,
        const Duration(seconds: 3),
        const Duration(seconds: 5),
      ]);
      expect(videoClips.map((clip) => clip.timelineEnd), [
        const Duration(seconds: 3),
        const Duration(seconds: 5),
        const Duration(seconds: 14),
      ]);
      expect(audioClips.map((clip) => clip.mediaItemId), [
        mainItem.id,
        cutItem.id,
        mainItem.id,
      ]);
      expect(audioClips.map((clip) => clip.timelineStart), [
        Duration.zero,
        const Duration(seconds: 3),
        const Duration(seconds: 5),
      ]);
      expect(audioClips.map((clip) => clip.timelineEnd), [
        const Duration(seconds: 3),
        const Duration(seconds: 5),
        const Duration(seconds: 14),
      ]);
      expect(controller.selectedMediaItemId, cutItem.id);
      expect(controller.errorMessage, isNull);
      expect(controller.statusMessage, contains('Video de corte inserido'));
    },
  );

  test(
    'tracked mask can create an image overlay that follows its path',
    () async {
      final videoItem = _mediaItem(id: 'tracked_video', duration: 12);
      final imageItem = _mediaItem(
        id: 'tracked_sticker',
        type: MediaType.image,
        name: 'sticker.png',
      );
      final controller = EditorController(
        mediaImportService: _FakeMediaImportService([videoItem, imageItem]),
      );

      await controller.importVideo();
      controller.addMediaItemToTimeline(videoItem, Duration.zero);
      controller.updateSelectedVideoMask(
        enabled: true,
        x: 0.2,
        y: 0.3,
        width: 0.28,
        height: 0.24,
      );
      controller.setSelectedVideoMaskAtPlayhead(x: 0.2, y: 0.3);
      controller.setPlayheadPosition(const Duration(seconds: 6));
      controller.setSelectedVideoMaskAtPlayhead(x: 0.8, y: 0.65);

      await controller.attachImageToSelectedMask(r'C:\images\sticker.png');

      final imageClip = controller.project.tracks
          .where((track) => track.type == TrackType.image)
          .expand((track) => track.clips)
          .single;
      expect(imageClip.mediaItemId, imageItem.id);
      expect(imageClip.timelineStart, Duration.zero);
      expect(imageClip.duration, const Duration(seconds: 12));
      expect(imageClip.imageFit, ImageClipFit.trackedOverlay);
      expect(imageClip.overlayX, 0.2);
      expect(imageClip.overlayY, 0.3);
      expect(imageClip.keyframedValue(ClipKeyframeProperty.overlayX, 0.5), 0.8);
      expect(
        imageClip.keyframedValue(ClipKeyframeProperty.overlayY, 0.5),
        0.65,
      );
      expect(controller.statusMessage, contains('Imagem seguindo o objeto'));
      expect(controller.errorMessage, isNull);
    },
  );
}

class _FakeFfmpegService extends FfmpegService {
  _FakeFfmpegService({required this.proxyPath});

  final String proxyPath;
  final optimizedItemIds = <String>[];
  final extractedFrames = <String>[];
  final freezeVideos = <String>[];

  @override
  Future<String> createPreviewProxy(
    MediaItem item, {
    FfmpegPreviewProxyProgressCallback? onProgress,
  }) async {
    optimizedItemIds.add(item.id);
    onProgress?.call(0.4);
    final file = File(proxyPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    onProgress?.call(1);
    return proxyPath;
  }

  @override
  Future<void> extractVideoFrame({
    required String inputPath,
    required Duration position,
    required String outputPath,
  }) async {
    extractedFrames.add(outputPath);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
  }

  @override
  Future<void> createFreezeFrameVideo({
    required String framePath,
    required Duration duration,
    required String outputPath,
    int width = 1280,
    int height = 720,
    int framesPerSecond = 30,
  }) async {
    freezeVideos.add(outputPath);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
  }
}

class _CancelableFakeFfmpegService extends FfmpegService {
  final Completer<String> _proxyCompleter = Completer<String>();
  bool cancelled = false;

  @override
  Future<String> createPreviewProxy(
    MediaItem item, {
    FfmpegPreviewProxyProgressCallback? onProgress,
  }) {
    onProgress?.call(0.2);
    return _proxyCompleter.future;
  }

  @override
  bool cancelActivePreviewProxy() {
    cancelled = true;
    if (!_proxyCompleter.isCompleted) {
      _proxyCompleter.completeError(
        const FfmpegProcessException('Otimizacao do preview cancelada.'),
      );
    }
    return true;
  }
}

class _FakeAudioWaveformService extends AudioWaveformService {
  _FakeAudioWaveformService(this.waveform)
    : super(ffmpegService: FfmpegService());

  final AudioWaveform waveform;

  @override
  Future<AudioWaveform> extractWaveform(MediaItem item) async {
    return waveform;
  }
}

class _FakeAutoCaptionService implements AutoCaptionService {
  _FakeAutoCaptionService(this.cues);

  final List<CaptionCue> cues;
  final mediaItems = <MediaItem>[];

  @override
  Future<List<CaptionCue>> generateCaptionsForMedia(
    MediaItem mediaItem, {
    String? languageCode,
    String modelName = '',
    int maxCharsPerCue = 44,
    AutoCaptionProgressCallback? onProgress,
  }) async {
    mediaItems.add(mediaItem);
    onProgress?.call(0.5, 'Transcrevendo');
    onProgress?.call(1, 'Legendas geradas');
    return cues;
  }
}

class _FakeMediaImportService extends MediaImportService {
  _FakeMediaImportService(
    List<MediaItem?> items, {
    List<List<MediaItem>> multiImportBatches = const [],
  }) : _items = [...items],
       _multiImportBatches = [
         for (final batch in multiImportBatches) [...batch],
       ],
       super(ffmpegService: FfmpegService());

  final List<MediaItem?> _items;
  final List<List<MediaItem>> _multiImportBatches;

  @override
  Future<MediaItem?> importVideo() async {
    if (_items.isEmpty) {
      return null;
    }
    return _items.removeAt(0);
  }

  @override
  Future<List<MediaItem>> importMediaFiles() async {
    if (_multiImportBatches.isNotEmpty) {
      return _multiImportBatches.removeAt(0);
    }
    final item = await importVideo();
    return item == null ? const [] : [item];
  }

  @override
  Future<MediaItem> importFile(String path) async {
    if (_items.isEmpty) {
      throw Exception('Nenhum item fake para importar.');
    }
    final item = _items.removeAt(0);
    if (item == null) {
      throw Exception('Importacao fake cancelada.');
    }
    return item;
  }
}

MediaItem _mediaItem({
  String id = 'media_1',
  int duration = 12,
  MediaType type = MediaType.video,
  String? name,
  String? filePath,
  int? width,
  int? height,
}) {
  final extension = type == MediaType.image ? 'png' : 'mp4';
  final itemName = name ?? 'sample.$extension';
  return MediaItem(
    id: id,
    filePath:
        filePath ??
        (type == MediaType.image
            ? r'C:\images\' + itemName
            : r'C:\videos\' + itemName),
    name: itemName,
    type: type,
    duration: Duration(seconds: duration),
    importedAt: DateTime(2026, 6, 26),
    width: width,
    height: height,
  );
}
