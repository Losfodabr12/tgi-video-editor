import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_component_paths.dart';

enum AppOutputModule { video, audio, image, converter }

enum AppVisualStyle { clean, studio, highContrast }

class AppShortcutBinding {
  const AppShortcutBinding({
    required this.keyId,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  factory AppShortcutBinding.fromActivator(SingleActivator activator) {
    return AppShortcutBinding(
      keyId: activator.trigger.keyId,
      control: activator.control,
      shift: activator.shift,
      alt: activator.alt,
      meta: activator.meta,
    );
  }

  factory AppShortcutBinding.fromJson(Map<String, dynamic> json) {
    return AppShortcutBinding(
      keyId: (json['keyId'] as num?)?.toInt() ?? 0,
      control: json['control'] == true,
      shift: json['shift'] == true,
      alt: json['alt'] == true,
      meta: json['meta'] == true,
    );
  }

  final int keyId;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  SingleActivator? toActivator() {
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == null) {
      return null;
    }
    return SingleActivator(
      key,
      control: control,
      shift: shift,
      alt: alt,
      meta: meta,
    );
  }

  Map<String, dynamic> toJson() => {
    'keyId': keyId,
    'control': control,
    'shift': shift,
    'alt': alt,
    'meta': meta,
  };
}

Map<String, AppShortcutBinding> defaultEditorShortcutPreferences() => {
  'undo': AppShortcutBinding.fromActivator(
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
  ),
  'redo': AppShortcutBinding.fromActivator(
    const SingleActivator(LogicalKeyboardKey.keyY, control: true),
  ),
  'split': AppShortcutBinding.fromActivator(
    const SingleActivator(LogicalKeyboardKey.keyS),
  ),
  'copy': AppShortcutBinding.fromActivator(
    const SingleActivator(LogicalKeyboardKey.keyC, control: true),
  ),
  'paste': AppShortcutBinding.fromActivator(
    const SingleActivator(LogicalKeyboardKey.keyV, control: true),
  ),
  'duplicate': AppShortcutBinding.fromActivator(
    const SingleActivator(LogicalKeyboardKey.keyD, control: true),
  ),
  'playPause': AppShortcutBinding.fromActivator(
    const SingleActivator(LogicalKeyboardKey.space),
  ),
  'delete': AppShortcutBinding.fromActivator(
    const SingleActivator(LogicalKeyboardKey.delete),
  ),
};

class AppPreferences {
  const AppPreferences({
    this.outputDirectories = const {},
    this.editorShortcuts = const {},
    this.visualStyle = AppVisualStyle.clean,
  });

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    final rawDirectories = json['outputDirectories'];
    final rawShortcuts = json['editorShortcuts'];
    return AppPreferences(
      outputDirectories: {
        if (rawDirectories is Map)
          for (final module in AppOutputModule.values)
            if ((rawDirectories[module.name] as String?)?.trim().isNotEmpty ==
                true)
              module: (rawDirectories[module.name] as String).trim(),
      },
      editorShortcuts: {
        ...defaultEditorShortcutPreferences(),
        if (rawShortcuts is Map)
          for (final entry in rawShortcuts.entries)
            if (entry.value is Map)
              entry.key.toString(): AppShortcutBinding.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
      },
      visualStyle: AppVisualStyle.values.firstWhere(
        (style) => style.name == json['visualStyle'],
        orElse: () => AppVisualStyle.clean,
      ),
    );
  }

  final Map<AppOutputModule, String> outputDirectories;
  final Map<String, AppShortcutBinding> editorShortcuts;
  final AppVisualStyle visualStyle;

  String? outputDirectoryFor(AppOutputModule module) {
    final value = outputDirectories[module]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  AppPreferences copyWith({
    Map<AppOutputModule, String>? outputDirectories,
    Map<String, AppShortcutBinding>? editorShortcuts,
    AppVisualStyle? visualStyle,
  }) {
    return AppPreferences(
      outputDirectories: outputDirectories ?? this.outputDirectories,
      editorShortcuts: editorShortcuts ?? this.editorShortcuts,
      visualStyle: visualStyle ?? this.visualStyle,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'visualStyle': visualStyle.name,
    'outputDirectories': {
      for (final entry in outputDirectories.entries)
        entry.key.name: entry.value,
    },
    'editorShortcuts': {
      for (final entry in editorShortcuts.entries)
        entry.key: entry.value.toJson(),
    },
  };
}

class AppPreferencesService {
  AppPreferencesService({String? settingsPath})
    : settingsPath =
          settingsPath ??
          joinPlatformPath([tgiAppLocalDataRoot(), 'settings.json']);

  static final AppPreferencesService instance = AppPreferencesService();

  final String settingsPath;
  AppPreferences? _cache;
  final ValueNotifier<AppVisualStyle> visualStyleListenable = ValueNotifier(
    AppVisualStyle.clean,
  );

  Future<AppPreferences> load({bool refresh = false}) async {
    if (!refresh && _cache != null) {
      return _cache!;
    }
    try {
      final file = File(settingsPath);
      if (!await file.exists()) {
        return _remember(
          AppPreferences(editorShortcuts: defaultEditorShortcutPreferences()),
        );
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Configuracao invalida.');
      }
      return _remember(
        AppPreferences.fromJson(Map<String, dynamic>.from(decoded)),
      );
    } catch (_) {
      return _remember(
        AppPreferences(editorShortcuts: defaultEditorShortcutPreferences()),
      );
    }
  }

  Future<void> save(AppPreferences preferences) async {
    final file = File(settingsPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(preferences.toJson()),
      flush: true,
    );
    _remember(preferences);
  }

  AppPreferences _remember(AppPreferences preferences) {
    _cache = preferences;
    visualStyleListenable.value = preferences.visualStyle;
    return preferences;
  }
}
