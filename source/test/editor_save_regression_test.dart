import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_screen.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/timeline_panel.dart';
import 'package:tgi_video_editor/services/ffmpeg_export_settings.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'package:tgi_video_editor/services/project_recovery_service.dart';
import 'package:tgi_video_editor/services/recent_project_service.dart';

void main() {
  testWidgets('Ctrl+S saves the current snapshot to its existing path', (
    tester,
  ) async {
    final io = _PausedProjectIO()..pending.complete();
    await _openEditor(tester, io, _MemoryRecovery());
    final snapshot = await _edit(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(io.written.single, same(snapshot));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed manual save keeps the draft and permits a later retry', (
    tester,
  ) async {
    final io = _PausedProjectIO()
      ..failNextSave = true
      ..pending.complete();
    final recovery = _MemoryRecovery();
    await _openEditor(tester, io, recovery);
    final snapshot = await _edit(tester);
    await tester.pump(const Duration(milliseconds: 2100));
    await _save(tester);
    await tester.pumpAndSettle();
    expect(io.written, isEmpty);
    expect(recovery.draft, same(snapshot));
    expect(recovery.clears, 0);
    await _back(tester);
    expect(find.text('Alteracoes nao salvas'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    await _save(tester);
    await tester.pumpAndSettle();
    expect(io.calls, 2);
    expect(io.written.single, same(snapshot));
    expect(recovery.draft, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'edits during saving stay dirty and keep their newer recovery draft',
    (tester) async {
      final io = _PausedProjectIO();
      final recovery = _MemoryRecovery();
      await _openEditor(tester, io, recovery);
      final savedSnapshot = await _edit(tester);
      await _save(tester);
      final newSnapshot = await _edit(tester);
      await tester.pump(const Duration(milliseconds: 2100));
      expect(recovery.draft, same(newSnapshot));
      io.pending.complete();
      await tester.pumpAndSettle();
      expect(io.written.single, same(savedSnapshot));
      expect(recovery.clears, 0);
      expect(recovery.draft, same(newSnapshot));
      expect(
        find.textContaining('Novas alteracoes ainda precisam ser salvas'),
        findsOneWidget,
      );
      await _back(tester);
      expect(find.text('Alteracoes nao salvas'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();
      await _save(tester);
      await tester.pumpAndSettle();
      expect(io.written.last, same(newSnapshot));
      expect(recovery.clears, 1);
      expect(recovery.draft, isNull);
      await _back(tester);
      expect(find.byType(EditorScreen), findsNothing);
    },
  );

  testWidgets('repeated save requests share one in-flight write', (
    tester,
  ) async {
    final io = _PausedProjectIO();
    await _openEditor(tester, io, _MemoryRecovery());
    await _edit(tester);
    await _save(tester);
    await _save(tester);
    expect(io.calls, 1);
    io.pending.complete();
    await tester.pumpAndSettle();
    expect(io.written, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('save-and-leave stays in the editor when new changes arrive', (
    tester,
  ) async {
    final io = _PausedProjectIO();
    await _openEditor(tester, io, _MemoryRecovery());
    await _edit(tester);
    await _back(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    expect(io.calls, 1);
    await _edit(tester);
    io.pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    await _back(tester);
    expect(find.text('Alteracoes nao salvas'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'manual save waits for an unfinished first autosave before clearing it',
    (tester) async {
      final io = _PausedProjectIO()..pending.complete();
      final recovery = _MemoryRecovery()..writeBarrier = Completer<void>();
      await _openEditor(tester, io, recovery);
      await _edit(tester);
      await tester.pump(const Duration(milliseconds: 2100));
      expect(recovery.writes, hasLength(1));
      await _save(tester);
      expect(recovery.clears, 1);
      recovery.writeBarrier!.complete();
      await tester.pumpAndSettle();
      expect(recovery.draft, isNull);
      expect(find.text('Rascunho salvo automaticamente.'), findsNothing);
      await _back(tester);
      expect(find.byType(EditorScreen), findsNothing);
    },
  );

  testWidgets(
    'discard cancels a pending debounce instead of resurrecting the draft',
    (tester) async {
      final recovery = _MemoryRecovery();
      await _openEditor(tester, _PausedProjectIO(), recovery);
      await _edit(tester);
      await _back(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Descartar'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(recovery.writes, isEmpty);
      expect(recovery.draft, isNull);
      expect(find.byType(EditorScreen), findsNothing);
    },
  );

  testWidgets(
    'discard waits for in-flight autosave and suppresses its late notification',
    (tester) async {
      final recovery = _MemoryRecovery()..writeBarrier = Completer<void>();
      await _openEditor(tester, _PausedProjectIO(), recovery);
      await _edit(tester);
      await tester.pump(const Duration(milliseconds: 2100));
      await _back(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Descartar'));
      await tester.pumpAndSettle();
      expect(recovery.clears, 1);
      recovery.writeBarrier!.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(recovery.draft, isNull);
      expect(find.byType(EditorScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a new autosave during cleanup retains ownership and remains recoverable',
    (tester) async {
      final io = _PausedProjectIO()..pending.complete();
      final recovery = _MemoryRecovery();
      await _openEditor(tester, io, recovery);
      await _edit(tester);
      await tester.pump(const Duration(milliseconds: 2100));
      recovery.clearBarrier = Completer<void>();
      await _save(tester);
      expect(recovery.clears, 1);
      final newer = await _edit(tester);
      await tester.pump(const Duration(milliseconds: 2100));
      recovery.clearBarrier!.complete();
      await tester.pumpAndSettle();
      expect(recovery.draft, same(newer));
      await _save(tester);
      await tester.pumpAndSettle();
      expect(recovery.clears, 2);
      expect(recovery.draft, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'autosave failure warns without an unhandled error and can recover',
    (tester) async {
      final recovery = _MemoryRecovery()..failNextWrite = true;
      await _openEditor(tester, _PausedProjectIO(), recovery);
      await _edit(tester);
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pump();
      expect(
        find.textContaining('Nao foi possivel salvar o rascunho automatico'),
        findsOneWidget,
      );
      expect(find.text('Rascunho salvo automaticamente.'), findsNothing);
      expect(tester.takeException(), isNull);
      final newer = await _edit(tester);
      await tester.pump(const Duration(milliseconds: 2100));
      expect(recovery.draft, same(newer));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late manual-save completion does not notify a disposed editor', (
    tester,
  ) async {
    final io = _PausedProjectIO();
    await _openEditor(tester, io, _MemoryRecovery());
    await _edit(tester);
    await _save(tester);
    await tester.pumpWidget(const SizedBox());
    io.pending.complete();
    await tester.pump();
    expect(io.written, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openEditor(
  WidgetTester tester,
  ProjectIOService io,
  ProjectRecoveryService recovery,
) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EditorScreen(
                initialProject: TgiProject.empty(name: 'Save regression'),
                initialProjectPath: r'C:\test-only\project.json',
                projectIOService: io,
                projectRecoveryService: recovery,
                recentProjectService: _MemoryRecentProjects(),
              ),
            ),
          ),
          child: const Text('Open editor'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

Future<TgiProject> _edit(WidgetTester tester) async {
  tester.widget<TimelinePanel>(find.byType(TimelinePanel)).onAddTrack!(
    TrackType.text,
  );
  await tester.pump();
  return tester.widget<TimelinePanel>(find.byType(TimelinePanel)).project;
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Salvar projeto'));
  await tester.pump();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Voltar'));
  await tester.pumpAndSettle();
}

class _PausedProjectIO extends ProjectIOService {
  final pending = Completer<void>();
  final written = <TgiProject>[];
  int calls = 0;
  bool failNextSave = false;

  @override
  Future<void> saveToFile(
    TgiProject project,
    String filePath, {
    FfmpegExportSettings? exportSettings,
  }) async {
    calls++;
    final fail = failNextSave;
    failNextSave = false;
    await pending.future;
    if (fail) throw StateError('write failed');
    written.add(project);
  }
}

class _MemoryRecentProjects extends RecentProjectService {
  @override
  Future<void> recordProject({
    required TgiProject project,
    required String filePath,
  }) async {}
}

class _MemoryRecovery extends ProjectRecoveryService {
  final writes = <TgiProject>[];
  TgiProject? draft;
  Completer<void>? writeBarrier;
  Completer<void>? clearBarrier;
  bool failNextWrite = false;
  int clears = 0;
  Future<void> _pending = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> saveDraft({
    required TgiProject project,
    String? originalProjectPath,
    String? editorStartPreset,
    FfmpegExportSettings? exportSettings,
    DateTime? savedAt,
  }) {
    writes.add(project);
    final barrier = writeBarrier;
    final fail = failNextWrite;
    failNextWrite = false;
    return _enqueue(() async {
      await barrier?.future;
      if (fail) throw StateError('disk unavailable');
      draft = project;
    });
  }

  @override
  Future<bool> clearDraft() {
    clears++;
    final barrier = clearBarrier;
    return _enqueue(() async {
      await barrier?.future;
      draft = null;
      return true;
    });
  }
}
