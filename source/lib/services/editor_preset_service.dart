import 'dart:convert';
import 'dart:async';
import 'dart:io';

import '../domain/models/clip.dart';
import '../domain/models/project.dart';
import '../domain/models/track.dart';
import 'app_component_paths.dart';
import 'project_file_storage.dart';
import 'project_io_service.dart';

enum EditorPresetKind {
  text('Estilo de texto'),
  color('Cor do vídeo'),
  animation('Animação');

  const EditorPresetKind(this.label);
  final String label;
}

class EditorPreset {
  const EditorPreset({
    required this.id,
    required this.name,
    required this.kind,
    required this.values,
  });
  final String id;
  final String name;
  final EditorPresetKind kind;
  final Map<String, dynamic> values;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'values': values,
  };
}

class EditorPresetService {
  EditorPresetService({String? filePath})
    : filePath =
          filePath ??
          joinPlatformPath([tgiAppLocalDataRoot(), 'editor_presets.json']);
  final String filePath;
  static int _idSequence = 0;

  static String _newPresetId() {
    // DateTime can return the same microsecond for two captures made in the
    // same event-loop turn. Keep the timestamp readable while guaranteeing
    // distinct ids for concurrent saves.
    _idSequence = (_idSequence + 1) % 1000000;
    return '${DateTime.now().microsecondsSinceEpoch}_$_idSequence';
  }

  static const _fields = <EditorPresetKind, Set<String>>{
    EditorPresetKind.text: {
      'fontFamily',
      'fontSize',
      'textColor',
      'backgroundColor',
      'opacity',
      'textAnimation',
    },
    EditorPresetKind.color: {
      'brightness',
      'contrast',
      'saturation',
      'exposure',
      'hue',
      'temperature',
      'tint',
      'shadows',
      'highlights',
      'curveShadows',
      'curveMidtones',
      'curveHighlights',
      'filterPreset',
    },
    EditorPresetKind.animation: {
      'textAnimation',
      'startOverlayX',
      'startOverlayY',
      'startOverlayScale',
      'overlayX',
      'overlayY',
      'overlayScale',
      'opacity',
      'kenBurnsEnabled',
      'kenBurnsStart',
      'kenBurnsEnd',
    },
  };
  static const _animatedProperties = {
    'overlayX',
    'overlayY',
    'overlayScale',
    'opacity',
  };
  static const _colorProperties = {
    'brightness',
    'contrast',
    'saturation',
    'exposure',
    'hue',
  };

  static Map<String, dynamic> _clipData(Clip clip) {
    final data = ProjectIOService().serializeProject(
      TgiProject.empty(name: 'Modelo').copyWith(
        tracks: [
          Track(
            id: 'preset',
            name: 'Modelo',
            type: clip.trackType,
            clips: [clip],
          ),
        ],
      ),
    );
    return ((data['tracks'] as List).single['clips'] as List).single
        as Map<String, dynamic>;
  }

  static EditorPreset capture(String name, EditorPresetKind kind, Clip clip) {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw const FormatException('Digite um nome para o modelo.');
    }
    final data = _clipData(clip);
    return EditorPreset(
      id: _newPresetId(),
      name: clean,
      kind: kind,
      values: {
        for (final field in _fields[kind]!) field: data[field],
        if (kind == EditorPresetKind.animation)
          'keyframes': (data['keyframes'] as List)
              .where((k) => _animatedProperties.contains(k['property']))
              .toList(),
      },
    );
  }

  static bool accepts(EditorPresetKind kind, Clip clip) => switch (kind) {
    EditorPresetKind.text => clip.trackType == TrackType.text,
    EditorPresetKind.color => clip.trackType == TrackType.video,
    EditorPresetKind.animation => clip.trackType != TrackType.audio,
  };

  static Clip apply(EditorPreset preset, Clip clip) {
    if (!accepts(preset.kind, clip)) {
      throw const FormatException(
        'Selecione um clipe compatível com este modelo.',
      );
    }
    final data = _clipData(clip);
    for (final field in _fields[preset.kind]!) {
      if (preset.values.containsKey(field)) data[field] = preset.values[field];
    }
    final replacedProperties = switch (preset.kind) {
      EditorPresetKind.animation => _animatedProperties,
      EditorPresetKind.color => _colorProperties,
      EditorPresetKind.text => {'opacity'},
    };
    data['keyframes'] = [
      for (final key in (data['keyframes'] as List))
        if (!replacedProperties.contains(key['property'])) key,
      if (preset.kind == EditorPresetKind.animation)
        for (final key in (preset.values['keyframes'] as List? ?? []))
          if (_animatedProperties.contains(key['property']))
            {...key as Map, 'id': '${clip.id}_preset_${key['id']}'},
    ];
    final projectData = ProjectIOService().serializeProject(
      TgiProject.empty(name: 'Modelo').copyWith(
        tracks: [Track(id: 'preset', name: 'Modelo', type: clip.trackType)],
      ),
    );
    (projectData['tracks'] as List).single['clips'] = [data];
    return ProjectIOService()
        .deserializeProject(projectData)
        .project
        .tracks
        .single
        .clips
        .single;
  }

  Future<List<EditorPreset>> list() async {
    if (!await File(filePath).exists() &&
        !await File('$filePath.bak').exists()) {
      return [];
    }
    final text = await ProjectFileStorage.read(filePath);
    final list = jsonDecode(text);
    if (list is! List) {
      throw const FormatException('Arquivo de modelos inválido.');
    }
    return [
      for (final value in list)
        if (value is Map<String, dynamic> &&
            EditorPresetKind.values.any((k) => k.name == value['kind']))
          EditorPreset(
            id: value['id'] as String,
            name: value['name'] as String,
            kind: EditorPresetKind.values.firstWhere(
              (k) => k.name == value['kind'],
            ),
            values: Map<String, dynamic>.from(value['values'] as Map),
          ),
    ];
  }

  static final _mutations = <String, Future<void>>{};
  Future<void> _mutate(Future<void> Function() operation) {
    final key = File(filePath).absolute.path.toLowerCase();
    final result = (_mutations[key] ?? Future<void>.value()).then(
      (_) => operation(),
    );
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _mutations[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_mutations[key], tail)) _mutations.remove(key);
      }),
    );
    return result;
  }

  Future<void> save(EditorPreset preset) => _mutate(() async {
    final values = await list();
    values.removeWhere((p) => p.id == preset.id);
    values.add(preset);
    await ProjectFileStorage.write(
      filePath,
      () => jsonEncode(values.map((p) => p.toJson()).toList()),
    );
  });

  Future<void> remove(String id) => _mutate(() async {
    final values = await list();
    values.removeWhere((p) => p.id == id);
    await ProjectFileStorage.write(
      filePath,
      () => jsonEncode(values.map((p) => p.toJson()).toList()),
    );
  });
}
