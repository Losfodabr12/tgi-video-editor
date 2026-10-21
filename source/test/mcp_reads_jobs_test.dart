import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/editor_command.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/editor_jobs.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'command_engine_test.dart' show commandFixture;

void main() {
  test(
    'compact pagination is revision-bound and paths are not exposed',
    () async {
      final c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: commandFixture(),
      );
      final reads = EditorReadService(c);
      addTearDown(c.dispose);
      addTearDown(reads.dispose);
      final first = reads.getProject(limit: 1);
      expect(first['clip_count'], 2);
      expect((first['clips'] as List).length, 1);
      final cursor = first['next_cursor'] as String;
      expect(
        (reads.getProject(cursor: cursor, limit: 1)['clips'] as List).length,
        1,
      );
      expect(reads.listMedia().toString(), isNot(contains('filePath')));
      expect(
        reads.getClip(
          c.project.tracks.expand((t) => t.clips).first.id,
        )['source_duration'],
        10,
      );
      c.addMarkerAtPlayhead();
      expect(
        () => reads.getProject(cursor: cursor),
        throwsA(isA<CommandError>()),
      );
      expect(
        () => reads.getTranscript(mediaId: 'media'),
        throwsA(
          isA<CommandError>().having(
            (e) => e.code,
            'code',
            'transcript_unavailable',
          ),
        ),
      );
    },
  );
  test(
    'jobs queue, cancellation prevents results and failures are structured',
    () async {
      final jobs = EditorJobs();
      addTearDown(jobs.close);
      final started = Completer<void>(), release = Completer<void>();
      var cancelled = false, queuedExecuted = false;
      final first = jobs.start('analysis', 2, 'project', (ctx) async {
        ctx.onCancel = () {
          cancelled = true;
          release.complete();
        };
        started.complete();
        await release.future;
        return {'value': 1};
      });
      final queued = jobs.start('analysis', 2, 'project', (ctx) async {
        queuedExecuted = true;
        return 2;
      });
      await started.future;
      await jobs.cancel(queued.id);
      await jobs.cancel(first.id);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      expect(queuedExecuted, isFalse);
      expect(first.status, 'cancelled');
      expect(first.result, isNull);
      final failed = jobs.start('analysis', 2, 'project', (ctx) async {
        throw const CommandError('test_error', 'Falhou');
      });
      await Future<void>.delayed(Duration.zero);
      expect(failed.status, 'failed');
      expect(failed.error!['code'], 'test_error');
      expect(() => jobs.get('unknown'), throwsA(isA<CommandError>()));
    },
  );
}
