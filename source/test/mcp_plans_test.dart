import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_jobs.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/auto_caption_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'command_engine_test.dart' show commandFixture;

class _Captions implements AutoCaptionService {
  @override
  Future<List<CaptionCue>> generateCaptionsForMedia(
    MediaItem m, {
    String? languageCode,
    String modelName = '',
    String vocabulary = '',
    bool vad = true,
    int maxCharsPerCue = 44,
    AutoCaptionProgressCallback? onProgress,
  }) async => const [
    CaptionCue(
      start: Duration(seconds: 1),
      end: Duration(seconds: 3),
      text: 'Uma frase',
    ),
    CaptionCue(
      start: Duration(seconds: 5),
      end: Duration(seconds: 8),
      text: 'Outra frase',
    ),
  ];
}

Future<void> _done(EditorJob job) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!job.finished && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(job.status, 'completed', reason: job.error.toString());
}

void main() {
  late EditorController c;
  late EditorReadService reads;
  late EditorPlans plans;
  late String clipId;
  setUp(() {
    c = EditorController(
      mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      initialProject: commandFixture(),
    );
    reads = EditorReadService(
      c,
      captions: _Captions(),
      checkMedia: (m) async => m.filePath,
    );
    plans = EditorPlans(c, reads);
    clipId = c.project.tracks
        .expand((t) => t.clips)
        .firstWhere((c) => c.trackType == TrackType.video)
        .id;
  });
  tearDown(() async {
    await reads.dispose();
    c.dispose();
  });
  String snapshot() => jsonEncode(
    ProjectIOService().serializeProject(
      c.project,
      exportSettings: c.commandExportSettings,
    ),
  );
  test(
    'dry-run preserves project and approval is local; applying is exact and undoable',
    () {
      final before = snapshot();
      final plan = plans.previewCommands([
        EditorCommand('split_clip', {'clip_id': clipId, 'at': 5}),
      ], baseRevision: 0);
      expect(snapshot(), before);
      expect(c.canUndo, isFalse);
      expect(
        () => plans.apply(plan.id, baseRevision: 0),
        throwsA(
          isA<CommandError>().having(
            (e) => e.code,
            'code',
            'approval_required',
          ),
        ),
      );
      plans.approve(plan.id);
      plans.apply(plan.id, baseRevision: 0);
      expect(identical(c.project, plan.after), isTrue);
      c.undo();
      expect(snapshot(), before);
      expect(
        () => plans.apply(plan.id, baseRevision: c.projectRevision),
        throwsA(isA<CommandError>()),
      );
    },
  );
  test(
    'remove silences splits linked clips and removes only requested spans',
    () async {
      final before = snapshot();
      final job = reads.jobs.start(
        'detect_silence',
        0,
        c.project.id,
        (ctx) async => {
          'media_id': 'media',
          'intervals': [
            {'start': 2.0, 'end': 4.0},
            {'start': 7.0, 'end': 8.0},
          ],
        },
      );
      await _done(job);
      final plan = plans.previewMacro('remove_silences', {
        'clip_id': clipId,
        'job_id': job.id,
        'padding': 0,
      }, baseRevision: 0);
      expect(plan.after.timelineDuration, const Duration(seconds: 7));
      expect(snapshot(), before);
      plans.approve(plan.id);
      plans.apply(plan.id, baseRevision: 0);
      c.undo();
      expect(snapshot(), before);
    },
  );
  test(
    'transcript cuts, captions and vertical framing share primitive commands',
    () async {
      await _done(reads.transcribe('media'));
      final cut = plans.previewMacro('cut_by_transcript', {
        'clip_id': clipId,
        'keep_cue_indices': [0, 1],
      }, baseRevision: 0);
      expect(cut.after.timelineDuration, const Duration(seconds: 5));
      final captions = plans.previewMacro('auto_captions', {
        'clip_id': clipId,
      }, baseRevision: 0);
      expect(
        captions.after.tracks
            .expand((t) => t.clips)
            .where((c) => c.isCaption)
            .length,
        2,
      );
      final before = snapshot();
      final vertical = plans.previewMacro('reframe_9x16', {
        'clip_id': clipId,
      }, baseRevision: 0);
      plans.approve(vertical.id);
      plans.apply(vertical.id, baseRevision: 0);
      expect(
        c.commandExportSettings.resolution,
        FfmpegExportResolution.shorts1080,
      );
      expect(c.project.clipById(clipId)!.cropLeft, closeTo(0.341796875, 1e-8));
      c.undo();
      expect(snapshot(), before);
      c.redo();
      expect(
        c.commandExportSettings.resolution,
        FfmpegExportResolution.shorts1080,
      );
    },
  );
}
