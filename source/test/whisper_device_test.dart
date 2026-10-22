import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/services/whisper_runtime.dart';
import 'package:tgi_video_editor/services/app_preferences_service.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/whisper_device_settings.dart';

const integrated = WhisperGpuDevice(
  index: 0,
  id: 'igpu',
  name: 'Intel UHD',
  engine: 'Vulkan0',
  discrete: false,
  freeBytes: 16000000000,
  totalBytes: 16000000000,
);
const rtx = WhisperGpuDevice(
  index: 1,
  id: 'pci-rtx',
  name: 'NVIDIA RTX 3050',
  engine: 'Vulkan1',
  discrete: true,
  freeBytes: 5000000000,
  totalBytes: 6000000000,
);

class MemoryPreferences extends AppPreferencesService {
  AppPreferences value = const AppPreferences();
  @override
  Future<AppPreferences> load({bool refresh = false}) async => value;
  @override
  Future<void> save(AppPreferences preferences) async {
    value = preferences;
  }
}

void main() {
  test(
    'dedicated RTX wins auto; manual device, CPU and unavailable choice win',
    () {
      expect(WhisperRuntime.selectDevice([integrated, rtx], 'auto'), same(rtx));
      expect(
        WhisperRuntime.selectDevice([integrated, rtx], 'igpu'),
        same(integrated),
      );
      expect(
        WhisperRuntime.selectDevice([rtx, integrated], 'pci-rtx'),
        same(rtx),
      );
      expect(WhisperRuntime.selectDevice([rtx], 'cpu'), isNull);
      expect(WhisperRuntime.selectDevice([rtx], 'removed-gpu'), isNull);
      expect(WhisperRuntime.selectDevice([], 'auto'), isNull);
    },
  );
  test('device preference survives a fresh settings service', () async {
    final dir = await Directory.systemTemp.createTemp('device_pref_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/settings.json';
    final prefs = AppPreferencesService(settingsPath: path);
    await prefs.save((await prefs.load()).copyWith(whisperDevice: 'pci-rtx'));
    expect(
      (await AppPreferencesService(settingsPath: path).load()).whisperDevice,
      'pci-rtx',
    );
    expect(AppPreferences.fromJson({}).whisperDevice, 'auto');
  });
  testWidgets('settings enumerate Vulkan GPUs and persist CPU selection', (
    tester,
  ) async {
    final preferences = MemoryPreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => WhisperDeviceSettings(
                  preferences: preferences,
                  detect: () async => [integrated, rtx],
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vulkan · NVIDIA RTX 3050'), findsOneWidget);
    expect(find.textContaining('Vulkan · Intel UHD'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CPU').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(preferences.value.whisperDevice, 'cpu');
  });
}
