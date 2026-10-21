import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/core/commands/timeline_time_map.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/timeline_marker.dart';
import 'package:tgi_video_editor/domain/models/timeline_transition.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'support/mcp_test_client.dart';
import 'support/silence_project.dart';

const remapper = TimelineRemapper();
TimelineTimeMap mapFor(TgiProject p) => TimelineTimeMap([
  (2000000, 4000000),
  (7000000, 8000000),
], end: p.timelineDuration.inMicroseconds);

void expectNoOverlaps(TgiProject project) {
  for (final track in project.tracks) {
    final clips = [...track.clips]
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    for (var i = 1; i < clips.length; i++) {
      expect(
        clips[i].timelineStart,
        greaterThanOrEqualTo(clips[i - 1].timelineEnd),
        reason: '${track.id}: ${clips[i - 1].id}/${clips[i].id}',
      );
    }
  }
}

void main() {
  test(
    'empty locked destination still identifies the attempted clip and time range',
    () {
      final base = silenceProject();
      final project = base.copyWith(
        tracks: [
          ...base.tracks,
          Track(id: 'locked', name: 'Locked', isLocked: true),
        ],
      );
      expect(
        () => const CommandEngine().apply(
          project,
          EditorCommand('move_clip', {
            'clip_id': 'video',
            'track_id': 'locked',
            'timeline_start': 2,
          }),
        ),
        throwsA(
          isA<CommandError>()
              .having((e) => e.details['cause'], 'cause', 'locked_track')
              .having(
                (e) => e.details['clip_ids'],
                'attempted clip',
                contains('video'),
              ),
        ),
      );
    },
  );
  test(
    'a: video alone keeps exact source spans, unique IDs and original minus removed duration',
    () {
      final before = silenceProject(audio: false), map = mapFor(before);
      final after = remapper
          .apply(before, before.clipById('video')!, map)
          .project;
      expect(
        after.timelineDuration.inMicroseconds,
        before.timelineDuration.inMicroseconds - map.removedDuration,
      );
      final clips = after.trackById('main')!.clips;
      expect(clips.map((c) => c.sourceStart.inSeconds), [0, 4, 8]);
      expect(clips.map((c) => c.duration.inSeconds), [2, 3, 2]);
      expect(clips.map((c) => c.timelineStart.inSeconds), [0, 2, 5]);
      expect(clips.map((c) => c.id).toSet(), hasLength(3));
      expectNoOverlaps(after);
    },
  );
  test(
    'b: captions inside silence disappear, crossings trim, multi-cut overlays shorten once',
    () {
      final base = silenceProject();
      final before = base.copyWith(
        tracks: [
          Track(
            id: 'captions',
            name: 'Captions',
            clips: [
              silenceCaption('left', 1, 2),
              silenceCaption('gone', 3, 1),
              silenceCaption('after', 4, 2),
            ],
          ),
          Track(
            id: 'cross',
            name: 'Crossing',
            clips: [silenceCaption('right', 3, 2)],
          ),
          Track(
            id: 'effect',
            name: 'Long overlay',
            clips: [silenceCaption('spanning', 0, 10)],
          ),
          ...base.tracks,
        ],
      );
      final after = remapper
          .apply(before, before.clipById('video')!, mapFor(before))
          .project;
      expect(after.clipById('gone'), isNull);
      expect(after.clipById('left')!.duration, silenceTime(1));
      expect(after.clipById('right')!.timelineStart, silenceTime(2));
      expect(after.clipById('right')!.duration, silenceTime(1));
      expect(after.clipById('spanning')!.duration, silenceTime(7));
      expect(after.trackById('effect')!.clips, hasLength(1));
      expectNoOverlaps(after);
    },
  );
  test(
    'c: all locked layers are listed before edits; skip preserves them and unlock is explicit',
    () {
      final base = silenceProject();
      final locked = base.copyWith(
        tracks: [
          Track(
            id: 'captions',
            name: 'Locked captions',
            isLocked: true,
            clips: [silenceCaption('caption', 0, 10)],
          ),
          Track(id: 'empty', name: 'Locked empty layer', isLocked: true),
          ...base.tracks,
        ],
      );
      final snapshot = jsonEncode(ProjectIOService().serializeProject(locked));
      expect(
        () => remapper.apply(locked, locked.clipById('video')!, mapFor(locked)),
        throwsA(
          isA<CommandError>()
              .having((e) => e.details['cause'], 'cause', 'locked_track')
              .having(
                (e) => e.details['locked_track_ids'],
                'all locked lanes',
                ['captions', 'empty'],
              ),
        ),
      );
      expect(jsonEncode(ProjectIOService().serializeProject(locked)), snapshot);
      final skipped = remapper.apply(
        locked,
        locked.clipById('video')!,
        mapFor(locked),
        lockedTracks: 'skip',
      );
      expect(
        identical(
          skipped.project.trackById('captions'),
          locked.trackById('captions'),
        ),
        true,
      );
      expect(
        skipped.toJson()['skipped_track_ids'],
        containsAll(['captions', 'empty']),
      );
      final unlocked = remapper.apply(
        locked,
        locked.clipById('video')!,
        mapFor(locked),
        lockedTracks: 'unlock',
      );
      expect(unlocked.project.tracks.any((t) => t.isLocked), false);
      expect(unlocked.project.clipById('caption')!.duration, silenceTime(7));
      expectNoOverlaps(unlocked.project);
    },
  );
  test(
    'd: every A/V piece retains matching source offsets, timing and linked group',
    () {
      final before = silenceProject();
      final after = remapper
          .apply(before, before.clipById('video')!, mapFor(before))
          .project;
      final video = after.trackById('main')!.clips,
          audio = after.trackById('audio')!.clips;
      expect(video, hasLength(3));
      expect(audio, hasLength(3));
      for (var i = 0; i < video.length; i++) {
        expect(audio[i].timelineGroupId, video[i].timelineGroupId);
        expect(audio[i].sourceStart, video[i].sourceStart);
        expect(audio[i].sourceDuration, video[i].sourceDuration);
        expect(audio[i].timelineStart, video[i].timelineStart);
        expect(audio[i].duration, video[i].duration);
      }
      final locked = before.copyWith(
        tracks: [
          before.tracks.first,
          before.tracks.last.copyWith(isLocked: true),
        ],
      );
      expect(
        () => remapper.apply(
          locked,
          locked.clipById('video')!,
          mapFor(locked),
          lockedTracks: 'skip',
        ),
        throwsA(
          isA<CommandError>().having(
            (e) => e.details['cause'],
            'cause',
            'linked_group',
          ),
        ),
      );
      expectNoOverlaps(after);
    },
  );
  test(
    'e: normalized keyframes preserve interpolated values and map markers and effect intervals',
    () {
      final base = silenceProject(audio: false);
      final keys = [
        for (final time in [0.0, .3, .6, 1.0])
          ClipKeyframe(
            id: 'key_$time',
            property: ClipKeyframeProperty.opacity,
            time: time,
            value: time,
          ),
      ];
      final video = base.clipById('video')!.copyWith(keyframes: keys);
      final overlay = silenceCaption('overlay', 0, 10).copyWith(
        keyframes: keys.map((k) => k.copyWith(id: 'overlay_${k.id}')).toList(),
      );
      final before = base.copyWith(
        tracks: [
          Track(id: 'overlay', name: 'Overlay', clips: [overlay]),
          base.tracks.single.copyWith(clips: [video]),
        ],
        markers: [
          for (final at in [1, 3, 6, 9])
            TimelineMarker(id: 'm$at', name: 'm$at', position: silenceTime(at)),
        ],
        transitions: [
          TimelineTransition(
            id: 'effect',
            name: 'Fade',
            preset: TimelineTransitionPreset.fade,
            placement: TimelineTransitionPlacement.start,
            timelinePosition: silenceTime(5),
            duration: silenceTime(4),
          ),
        ],
      );
      final map = mapFor(before),
          after = remapper.apply(before, video, map).project;
      expect(after.markers.map((m) => m.position.inSeconds), [1, 2, 4, 6]);
      expect(after.transitions.single.timelineStart, silenceTime(3));
      expect(after.transitions.single.duration, silenceTime(3));
      final keyIds = after.tracks
          .expand((t) => t.clips)
          .expand((c) => c.keyframes)
          .map((k) => k.id)
          .toList();
      expect(keyIds.toSet(), hasLength(keyIds.length));
      for (final segment in after.trackById('main')!.clips) {
        for (final local in [.1, .5, .9]) {
          final old =
              (segment.sourceStart.inMicroseconds +
                  segment.effectiveSourceDuration.inMicroseconds * local) /
              1e7;
          expect(
            segment.keyframedValue(ClipKeyframeProperty.opacity, local),
            closeTo(old, 1e-6),
          );
        }
      }
      for (final oldSeconds in [.5, 1.5, 4.5, 6.5, 8.5, 9.5]) {
        final newSeconds =
            map.map(silenceTime(oldSeconds).inMicroseconds) / 1e6;
        expect(
          after
              .clipById('overlay')!
              .keyframedValue(ClipKeyframeProperty.opacity, newSeconds / 7),
          closeTo(oldSeconds / 10, 1e-5),
        );
      }
      expectNoOverlaps(after);
    },
  );
  test(
    'f: 132-clip layered fixture preserves caption/word sync within one frame',
    () {
      final before = layeredSilenceProject();
      expect(before.tracks.expand((t) => t.clips), hasLength(132));
      final map = TimelineTimeMap(
        fixtureSilences,
        end: before.timelineDuration.inMicroseconds,
      );
      final after = remapper
          .apply(before, before.clipById('video')!, map)
          .project;
      expect(
        after.timelineDuration.inMicroseconds,
        before.timelineDuration.inMicroseconds - map.removedDuration,
      );
      for (final cue
          in before.tracks.expand((t) => t.clips).where((c) => c.isCaption)) {
        final oldWord = cue.timelineStart.inMicroseconds + 200000;
        if (map.removed.any((r) => oldWord >= r.$1 && oldWord < r.$2)) continue;
        final newWord = map.map(oldWord), caption = after.clipById(cue.id)!;
        expect(
          newWord,
          greaterThanOrEqualTo(caption.timelineStart.inMicroseconds),
        );
        expect(newWord, lessThan(caption.timelineEnd.inMicroseconds));
        final spoken = after
            .trackById('main')!
            .clips
            .firstWhere(
              (c) =>
                  oldWord >= c.sourceStart.inMicroseconds &&
                  oldWord < c.sourceEnd.inMicroseconds,
            );
        final audioTime =
            spoken.timelineStart.inMicroseconds +
            (oldWord - spoken.sourceStart.inMicroseconds) /
                spoken.playbackSpeed;
        expect((audioTime - newWord).abs(), lessThanOrEqualTo(1e6 / 30));
      }
      expectNoOverlaps(after);
      final serialized = ProjectIOService().serializeProject(after);
      expect(serialized['version'], 14);
      final restored = ProjectIOService()
          .deserializeProject(serialized)
          .project;
      expect(
        (restored.timelineDuration.inMicroseconds -
                after.timelineDuration.inMicroseconds)
            .abs(),
        lessThanOrEqualTo(1000),
      );
    },
  );
  test(
    'main_track_only keeps external overlays unchanged and explicitly reports the sync tradeoff',
    () {
      final base = silenceProject();
      final before = base.copyWith(
        tracks: [
          Track(
            id: 'text',
            name: 'Text',
            clips: [silenceCaption('text', 0, 10)],
          ),
          ...base.tracks,
        ],
      );
      final result = remapper.apply(
        before,
        before.clipById('video')!,
        mapFor(before),
        scope: 'main_track_only',
      );
      expect(result.selection.tracks, {'main', 'audio'});
      expect(
        identical(result.project.trackById('text'), before.trackById('text')),
        true,
      );
      expect(
        result.project.trackById('main')!.clips.last.timelineEnd,
        silenceTime(7),
      );
      expect(result.toJson()['warning'], isNotEmpty);
    },
  );
  test(
    'trimmed reversed sources and speed preserve reversed audio linkage',
    () {
      final base = silenceProject();
      final before = base.copyWith(
        tracks: [
          for (final t in base.tracks)
            t.copyWith(
              clips: [
                t.clips.single.copyWith(
                  timelineStart: silenceTime(2),
                  sourceStart: silenceTime(1),
                  sourceDuration: silenceTime(8),
                  duration: silenceTime(4),
                  playbackSpeed: 2,
                  reverseVideo: t.id == 'main',
                ),
              ],
            ),
        ],
      );
      final after = remapper
          .apply(
            before,
            before.clipById('video')!,
            TimelineTimeMap([(4000000, 5000000)], end: 6000000),
          )
          .project;
      for (final track in after.tracks) {
        expect(track.clips.map((c) => c.sourceStart.inSeconds), [5, 1]);
        expect(track.clips.map((c) => c.sourceDuration!.inSeconds), [4, 2]);
        expect(track.clips.map((c) => c.timelineStart.inSeconds), [2, 4]);
      }
    },
  );

  group('MCP remapping contract', () {
    late EditorController c;
    late EditorReadService reads;
    late EditorPlans plans;
    late EditorMcpServer server;
    late McpTestClient client;
    setUp(() async {
      HttpOverrides.global = null;
      final initial = layeredSilenceProject();
      c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: initial.copyWith(
          tracks: [
            for (final track in initial.tracks)
              track.copyWith(
                clips: [
                  for (final clip in track.clips)
                    clip.id == 'caption_0'
                        ? clip.copyWith(textColor: 0xFF000000)
                        : clip,
                ],
              ),
          ],
        ),
      );
      reads = EditorReadService(c);
      plans = EditorPlans(c, reads)..requireApproval = false;
      server = EditorMcpServer(
        McpToolRouter(reads, plans),
        token: randomMcpToken(),
        port: 0,
      );
      await server.start();
      client = McpTestClient(server.boundPort, server.token);
      await client.initialize();
    });
    tearDown(() async {
      client.close();
      await server.stop();
      await reads.dispose();
      c.dispose();
    });
    String snapshot() => jsonEncode(
      ProjectIOService().serializeProject(
        c.project,
        exportSettings: c.commandExportSettings,
      ),
    );
    Future<String> analysis() async {
      final job = reads.jobs.start(
        'detect_silence',
        c.projectRevision,
        c.project.id,
        (_) async => {
          'media_id': 'speech',
          'threshold_db': -35.0,
          'minimum': .5,
          'intervals': [
            for (final r in fixtureSilences)
              {'start': r.$1 / 1e6, 'end': r.$2 / 1e6},
          ],
        },
      );
      while (!job.finished) {
        await Future<void>.delayed(Duration.zero);
      }
      return job.id;
    }

    test(
      'preview_plan macro -> apply_plan -> undo restores the entire v14 project exactly',
      () async {
        final before = snapshot(), job = await analysis();
        final draft = await client.call('preview_plan', {
          'macro': 'remove_silences',
          'arguments': {'clip_id': 'video', 'job_id': job, 'padding': 0},
          'base_revision': 0,
        });
        expect(draft['isError'], false, reason: draft.toString());
        expect(snapshot(), before);
        expect(c.canUndo, false);
        final plan = draft['structuredContent'];
        expect(plan['command_count'], 1);
        expect(plan['scope'], 'all_tracks');
        final applied = await client.call('apply_plan', {
          'plan_id': plan['plan_id'],
          'base_revision': 0,
        });
        expect(applied['isError'], false);
        expect(c.projectRevision, 1);
        expect(c.undoLabel, 'IA: remove_silences');
        expectNoOverlaps(c.project);
        final stale = await client.call('remove_silences', {
          'clip_id': 'video',
          'job_id': job,
          'base_revision': 0,
        });
        expect(
          stale['structuredContent']['error']['code'],
          'revision_conflict',
        );
        final undo = await client.call('undo', {'base_revision': 1});
        expect(undo['isError'], false);
        expect(c.canUndo, false);
        expect(snapshot(), before);
      },
    );
    test(
      'preview command batch combines remap and white caption style into one undo',
      () async {
        final before = snapshot();
        expect(c.project.clipById('caption_0')!.textColor, 0xFF000000);
        final preview = await client.call('preview_plan', {
          'base_revision': 0,
          'commands': [
            {
              'command': 'remap_timeline',
              'arguments': {
                'clip_id': 'video',
                'removed_ranges': [
                  {'start': 2, 'end': 4},
                ],
              },
            },
            {
              'command': 'set_caption_style',
              'arguments': {'clip_id': 'caption_0', 'text_color': 4294967295},
            },
          ],
        });
        expect(preview['isError'], false, reason: preview.toString());
        final apply = await client.call('apply_plan', {
          'base_revision': 0,
          'plan_id': preview['structuredContent']['plan_id'],
        });
        expect(apply['isError'], false);
        expect(c.project.clipById('caption_0')!.textColor, 0xFFFFFFFF);
        expect(c.projectRevision, 1);
        await client.call('undo', {'base_revision': 1});
        expect(snapshot(), before);
      },
    );
    test(
      'explicit analysis parameters cannot silently reuse a different threshold',
      () async {
        final job = await analysis();
        final result = await client.call('remove_silences', {
          'clip_id': 'video',
          'job_id': job,
          'threshold_db': -20,
          'base_revision': 0,
        });
        expect(
          result['structuredContent']['error']['code'],
          'analysis_mismatch',
        );
        expect(c.projectRevision, 0);
        expect(plans.all, isEmpty);
      },
    );
    test(
      'locked layers fail over MCP before any analysis job or plan is started',
      () async {
        final locked = c.project.copyWith(
          tracks: [
            for (final t in c.project.tracks)
              t.copyWith(isLocked: t.id == 'captions_upper'),
          ],
        );
        c.commitCommandProject(locked, baseRevision: 0, label: 'Lock fixture');
        final before = snapshot();
        final result = await client.call('preview_plan', {
          'macro': 'remove_silences',
          'arguments': {'clip_id': 'video'},
          'base_revision': c.projectRevision,
        });
        expect(
          result['structuredContent']['error']['details']['cause'],
          'locked_track',
        );
        expect(reads.jobs.all, isEmpty);
        expect(plans.all, isEmpty);
        expect(snapshot(), before);
      },
    );
    test(
      'padding is applied in source seconds before building the monotone map',
      () async {
        final job = reads.jobs.start(
          'detect_silence',
          0,
          c.project.id,
          (_) async => {
            'media_id': 'speech',
            'intervals': [
              {'start': 2.0, 'end': 4.0},
            ],
          },
        );
        while (!job.finished) {
          await Future<void>.delayed(Duration.zero);
        }
        final result = await client.call('remove_silences', {
          'clip_id': 'video',
          'job_id': job.id,
          'padding': .12,
          'base_revision': 0,
        });
        expect(result['isError'], false, reason: result.toString());
        expect(
          result['structuredContent']['time_map']['removed_duration'],
          closeTo(1.76, 1e-6),
        );
        expect(result['structuredContent']['time_map']['removed_ranges'], [
          {'start': 2.12, 'end': 3.88},
        ]);
        expect(c.projectRevision, 0);
      },
    );
  });
}
