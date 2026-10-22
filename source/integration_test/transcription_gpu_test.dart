import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_screen.dart';
import 'package:tgi_video_editor/services/app_component_paths.dart';
import 'package:tgi_video_editor/services/app_preferences_service.dart';
import 'package:tgi_video_editor/services/auto_caption_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'package:tgi_video_editor/services/whisper_runtime.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import '../test/support/mcp_test_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('TGI_RUN_GPU_APP_VALIDATION');
  testWidgets(
    'real Windows UI and HTTP MCP transcribe 60 seconds; Vulkan and CPU',
    (tester) async {
      final root = Directory(Platform.environment['TGI_GPU_VALIDATION_ROOT']!);
      final output = Directory('${root.path}/native-results')
        ..createSync(recursive: true);
      final repo = Directory(Platform.environment['TGI_GPU_VALIDATION_REPO']!);
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      debugPrint('native_validation: window initialized');
      await initializeAppComponentPaths();
      final io = ProjectIOService();
      final loaded = io.deserializeProject(
        Map<String, dynamic>.from(
          jsonDecode(File('${root.path}/projeto.json').readAsStringSync())
              as Map,
        ),
      );
      final project = loaded.project;
      expect(project.mediaPool.single.duration, const Duration(seconds: 60));
      final controller = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: project,
      );
      final service =
          controller.autoCaptionService as LocalWhisperAutoCaptionService;
      final reads = EditorReadService(controller);
      final plans = EditorPlans(controller, reads)..requireApproval = false;
      final token = randomMcpToken();
      final server = EditorMcpServer(
        McpToolRouter(reads, plans),
        token: token,
        port: 0,
      );
      await tester.runAsync(() => server.start());
      final client = McpTestClient(server.boundPort, token);
      await tester.runAsync(() => client.initialize());
      addTearDown(() async {
        client.close();
        await server.stop();
        reads.dispose();
      });
      final prefs = AppPreferencesService.instance;
      await tester.runAsync(
        () async =>
            prefs.save((await prefs.load()).copyWith(whisperDevice: 'auto')),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(
            controller: controller,
            initialProject: project,
            initialProjectPath: '${root.path}/projeto.json',
            workspaceLayoutPath: '${root.path}/native-layout.json',
          ),
        ),
      );
      Future<void> tick([int milliseconds = 100]) async {
        await tester.runAsync(
          () => Future<void>.delayed(Duration(milliseconds: milliseconds)),
        );
        await tester.pump();
      }

      await tick(500);
      await tester.tap(find.text('Legendas').first);
      await tick();
      final measurementsFile = File('${output.path}/measurements.json');
      final resume = Platform.environment['TGI_GPU_VALIDATION_RESUME'] == '1';
      final rows = resume && measurementsFile.existsSync()
          ? (jsonDecode(measurementsFile.readAsStringSync()) as List)
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList()
          : <Map<String, dynamic>>[];
      Future<Map<String, dynamic>> call(
        String tool,
        Map<String, Object?> args,
      ) async {
        final response = (await tester.runAsync(
          () => client.call(tool, args),
        ))!;
        expect(response['isError'], isFalse, reason: 'MCP $tool');
        return Map<String, dynamic>.from(response['structuredContent'] as Map);
      }

      Future<void> resetProject() async {
        controller.loadProjectFromData(loaded);
        await tester.runAsync(
          () => controller.transcripts.open(
            project,
            path: '${root.path}/projeto.json',
          ),
        );
        controller.transcripts.modelName = 'large-v3-turbo-q5_0';
        await tick();
      }

      Future<void> measure(
        String mode,
        String expectedBackend,
        int run, {
        bool fallback = false,
      }) async {
        if (resume &&
            rows.any(
              (row) =>
                  row['mode'] == mode &&
                  row['backend'] == expectedBackend &&
                  row['run'] == run &&
                  row['fallback'] == fallback,
            )) {
          return;
        }
        await resetProject();
        if (mode == 'UI') {
          await tester.tap(
            find.byKey(const ValueKey('captions_generate_button')),
          );
          await tester.pump();
          // Manual Turbo must already be selected while model discovery is pending.
          expect(find.text('Preciso (turbo)'), findsWidgets);
          await tick(500);
          await tester.ensureVisible(find.text('Gerar legendas'));
        }
        final label =
            '${mode.toLowerCase()}-${expectedBackend.toLowerCase()}-${fallback ? 'missing-runtime-' : ''}$run';
        final metrics = File('${output.path}/$label.memory.json');
        final stop = File('${output.path}/$label.stop');
        final ready = File('${output.path}/$label.memory.ready');
        if (stop.existsSync()) stop.deleteSync();
        if (ready.existsSync()) ready.deleteSync();
        final monitor = (await tester.runAsync(
          () => Process.start(
            Platform.environment['TGI_VALIDATION_PYTHON'] ?? 'python',
            [
              '${repo.path}/tool/measure_windows_process_tree.py',
              '--pid',
              pid.toString(),
              '--output',
              metrics.path,
              '--stop-file',
              stop.path,
            ],
          ),
        ))!;
        final monitorErrors = monitor.stderr.drain<void>();
        final monitorOutput = monitor.stdout.drain<void>();
        for (var i = 0; i < 200 && !ready.existsSync(); i++) {
          await tick(25);
        }
        expect(ready.existsSync(), isTrue, reason: 'Memory sampler readiness');
        Map<String, dynamic>? jobExecution;
        final watch = Stopwatch()..start();
        try {
          if (mode == 'UI') {
            await tester.tap(find.text('Gerar legendas'));
            await tester.pump();
            while (controller.isGeneratingCaptions ||
                controller.generatedCaptionClips.isEmpty) {
              await tick();
              expect(
                controller.errorMessage,
                isNull,
                reason: 'UI transcription',
              );
              expect(watch.elapsed, lessThan(const Duration(minutes: 5)));
            }
          } else {
            var job = await call('transcribe', {
              'media_id': project.mediaPool.single.id,
              'language': 'pt',
              'model': 'large-v3-turbo-q5_0',
              'vad': true,
            });
            while (job['status'] == 'running' || job['status'] == 'queued') {
              await tick(750);
              job = await call('get_job', {'job_id': job['job_id']});
              expect(watch.elapsed, lessThan(const Duration(minutes: 5)));
            }
            expect(job['status'], 'completed', reason: 'MCP transcription');
            File(
              '${output.path}/$label.job.json',
            ).writeAsStringSync(jsonEncode(job));
            final result = job['result'] as Map;
            expect(result['backend'], expectedBackend);
            expect(result['device'], WhisperRuntime.activeDevice);
            jobExecution = Map<String, dynamic>.from(result);
          }
        } finally {
          watch.stop();
          stop.writeAsStringSync('stop');
          final code = await tester.runAsync(
            () => monitor.exitCode.timeout(const Duration(seconds: 10)),
          );
          expect(code, 0);
          await tester.runAsync(
            () => Future.wait([monitorErrors, monitorOutput]),
          );
        }
        final execution = jobExecution ?? service.lastExecution!.toJson();
        await tester.pump();
        expect(WhisperRuntime.backend.value, startsWith(expectedBackend));
        expect(
          find.textContaining('Transcritor: $expectedBackend'),
          findsWidgets,
        );
        expect(execution['backend'], expectedBackend);
        expect(execution['model'], 'large-v3-turbo-q5_0');
        if (fallback) expect(execution['fallback'], isTrue);
        final memory = Map<String, dynamic>.from(
          jsonDecode(metrics.readAsStringSync()) as Map,
        );
        expect(memory['engine_pids'], isNotEmpty);
        if (expectedBackend == 'Vulkan') {
          expect(memory['engine_peak_dedicated_gpu_bytes'], greaterThan(0));
        }
        rows.add({
          'mode': mode,
          'run': run,
          'seconds': watch.elapsedMicroseconds / 1e6,
          ...execution,
          ...memory,
          'transcription_seconds': watch.elapsedMicroseconds / 1e6,
        });
        File(
          '${output.path}/measurements.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
        File('${output.path}/$label.hypothesis.json').writeAsStringSync(
          jsonEncode(
            controller.transcripts
                .cues(project.id, project.mediaPool.single.id)
                .map((c) => c.toJson())
                .toList(),
          ),
        );
        // Only execution metadata reaches the test log; speech stays under .work.
        debugPrint(
          '$mode $expectedBackend run=$run seconds=${watch.elapsedMicroseconds / 1e6} device=${execution['device']}',
        );
      }

      for (var i = 1; i <= 3; i++) {
        await measure('UI', 'Vulkan', i);
      }
      for (var i = 1; i <= 3; i++) {
        await measure('MCP', 'Vulkan', i);
      }
      // Exercise the same settings dialog that ships in the app.
      await tester.tap(find.text('Arquivo').first);
      await tick(400);
      await tester.tap(find.text('Transcrição (GPU)'));
      await tick(1000);
      for (
        var i = 0;
        i < 100 &&
            find.byType(DropdownButtonFormField<String>).evaluate().isEmpty;
        i++
      ) {
        await tick();
      }
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tick(400);
      await tester.tap(find.text('CPU').last);
      await tick(400);
      await tester.tap(find.text('Salvar').last);
      await tick(400);
      expect((await tester.runAsync(() => prefs.load()))!.whisperDevice, 'cpu');
      await measure('UI', 'CPU', 1);
      for (var i = 1; i <= 3; i++) {
        await measure('MCP', 'CPU', i);
      }
      // Missing GPU dependency: verify graceful recovery, retaining the manual model.
      await tester.runAsync(
        () async =>
            prefs.save((await prefs.load()).copyWith(whisperDevice: 'auto')),
      );
      final cpu = File(Platform.environment['TGI_WHISPER_CPP_PATH']!);
      final dll = File('${cpu.parent.parent.path}/vulkan/bin/ggml-vulkan.dll');
      final resolved = dll.resolveSymbolicLinksSync();
      expect(
        resolved.toLowerCase().startsWith(
          '${root.absolute.path}/app/'
              .replaceAll('/', Platform.pathSeparator)
              .toLowerCase(),
        ),
        isTrue,
      );
      final disabled = dll.renameSync('${dll.path}.disabled');
      try {
        await measure('MCP', 'CPU', 1, fallback: true);
      } finally {
        disabled.renameSync(dll.path);
      }
      final catalog = await tester.runAsync(
        () => client.request('tools/list', {}),
      );
      File(
        '${output.path}/tools-list.json',
      ).writeAsStringSync(jsonEncode(catalog!.$2));
      await tester.pumpWidget(const SizedBox());
      await tick();
    },
    skip: !enabled || !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
