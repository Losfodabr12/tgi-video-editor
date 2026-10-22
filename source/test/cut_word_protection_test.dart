import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/cut_range_policy.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/services/auto_caption_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'support/silence_project.dart';

class _Words implements AutoCaptionService {
  _Words(this.cues);
  final List<CaptionCue> cues;
  @override
  Future<List<CaptionCue>> generateCaptionsForMedia(
    MediaItem mediaItem, {
    String? languageCode,
    String modelName = '',
    String vocabulary = '',
    bool vad = true,
    int maxCharsPerCue = 44,
    AutoCaptionProgressCallback? onProgress,
  }) async => cues;
}

void main() {
  test(
    'words touching or crossing silence borders retain their full margins',
    () {
      final ranges = protectCutRanges(
        [(2, 5)],
        [(1.8, 2.1), (4.8, 5.2), (3, 3.2)],
      );
      expect(ranges, hasLength(2));
      expect(ranges[0].$1, closeTo(2.15, 1e-9));
      expect(ranges[0].$2, closeTo(2.95, 1e-9));
      expect(ranges[1].$1, closeTo(3.25, 1e-9));
      expect(ranges[1].$2, closeTo(4.75, 1e-9));
      expect(protectCutRanges([(2, 3)], [(1, 4)]), isEmpty);
    },
  );
  test(
    'Whisper word and subword timestamps survive parsing, offset and cue segmentation',
    () {
      final cues = parseWhisperCaptionCues(
        jsonEncode({
          'transcription': [
            {
              'offsets': {'from': 100, 'to': 2200},
              'text': 'Uma palavra importante perto do corte',
              'tokens': [
                {
                  'text': ' Uma',
                  'offsets': {'from': 100, 'to': 400},
                },
                {
                  'text': ' pala',
                  'offsets': {'from': 500, 'to': 700},
                },
                {
                  'text': 'vra',
                  'offsets': {'from': 700, 'to': 900},
                },
                {
                  'text': ' importante',
                  'offsets': {'from': 1000, 'to': 2200},
                },
              ],
            },
          ],
        }),
        offset: const Duration(seconds: 5),
      );
      expect(cues.single.words.map((w) => w.text), [
        'Uma',
        'palavra',
        'importante',
      ]);
      expect(cues.single.words[1].start.inMilliseconds, 5500);
      expect(cues.single.words[1].end.inMilliseconds, 5900);
      final split = segmentCaptionCues(cues, maxCharsPerCue: 24);
      expect(
        split.expand((c) => c.words).any((w) => w.text == 'palavra'),
        true,
      );
    },
  );
  for (final transcript in [false, true]) {
    test(
      'macro word protection and dry-run warning with transcript=$transcript',
      () async {
        final c = EditorController(
          mediaImportService: MediaImportService(
            ffmpegService: FfmpegService(),
          ),
          initialProject: silenceProject(),
        );
        final reads = EditorReadService(
          c,
          checkMedia: (m) async => m.filePath,
          captions: _Words([
            CaptionCue(
              start: silenceTime(1.8),
              end: silenceTime(5.2),
              text: 'palavras',
              words: [
                CaptionWord(
                  start: silenceTime(1.8),
                  end: silenceTime(2.1),
                  text: 'primeira',
                ),
                CaptionWord(
                  start: silenceTime(4.8),
                  end: silenceTime(5.2),
                  text: 'segunda',
                ),
              ],
            ),
          ]),
        );
        addTearDown(c.dispose);
        addTearDown(reads.dispose);
        if (transcript) {
          final job = reads.transcribe('speech');
          while (!job.finished) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(job.status, 'completed');
        }
        final job = reads.jobs.start(
          'detect_silence',
          c.projectRevision,
          c.project.id,
          (_) async => {
            'media_id': 'speech',
            'intervals': [
              {'start': 2, 'end': 5},
            ],
          },
        );
        while (!job.finished) {
          await Future<void>.delayed(Duration.zero);
        }
        final plans = EditorPlans(c, reads);
        final plan = plans.previewMacro('remove_silences', {
          'clip_id': 'video',
          'job_id': job.id,
          'padding': 0,
        }, baseRevision: c.projectRevision);
        expect(
          plan.effects['word_protection'],
          containsPair('active', transcript),
        );
        expect(
          plan.after.timelineDuration.inMicroseconds,
          transcript ? 7400000 : 7000000,
        );
        expect(c.project.timelineDuration.inSeconds, 10);
        if (!transcript) {
          expect(
            plan.effects['warnings'].toString(),
            contains('não há transcrição'),
          );
        }
        if (transcript) {
          final off = plans.previewMacro('remove_silences', {
            'clip_id': 'video',
            'job_id': job.id,
            'padding': 0,
            'protect_words': false,
          }, baseRevision: c.projectRevision);
          expect(off.after.timelineDuration.inSeconds, 7);
          final cut = plans.previewMacro('cut_by_transcript', {
            'clip_id': 'video',
            'keep_cue_indices': [0],
          }, baseRevision: c.projectRevision);
          expect(cut.after.timelineDuration.inMicroseconds, 3500000);
          expect(cut.effects['word_protection'], containsPair('active', true));
        }
      },
    );
  }
}
