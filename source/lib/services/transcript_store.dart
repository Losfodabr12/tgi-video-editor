import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../domain/models/media_item.dart';
import '../domain/models/project.dart';
import 'app_component_paths.dart';
import 'auto_caption_service.dart';
import 'project_file_storage.dart';

/// Private companion data. The project JSON remains v14.
class TranscriptStore {
  TranscriptStore({this.directoryOverride});
  final String? directoryOverride;
  String language = 'pt';
  String? projectPath;
  String? _projectId;
  bool _bound = false;
  final Map<String, Map<String, dynamic>> _entries = {};
  Future<void> ready = Future<void>.value();
  List<CaptionCue> cues(String projectId, String mediaId) {
    if (_projectId != projectId) return const [];
    final rows = _entries[mediaId]?['cues'] as List? ?? const [];
    return [
      for (final row in rows)
        cueFromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  String usedLanguage(String mediaId) =>
      _entries[mediaId]?['language'] as String? ?? language;
  String _path(TgiProject project, String? path) => path == null
      ? joinPlatformPath([
          directoryOverride ??
              joinPlatformPath([tgiAppLocalDataRoot(), 'transcripts']),
          '${sha256.convert(utf8.encode(project.id))}.words.json',
        ])
      : '$path.words.json';
  Future<void> open(TgiProject project, {String? path}) {
    return ready = _open(project, path);
  }

  Future<void> _open(TgiProject project, String? path) async {
    _bound = true;
    _projectId = project.id;
    projectPath = path;
    language = 'pt';
    _entries.clear();
    final file = File(_path(project, path));
    if (!file.existsSync()) return;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['schema'] != 1 || data['project_id'] != project.id) return;
      language = data['language'] as String? ?? 'pt';
      for (final row in (data['media'] as List? ?? const [])) {
        final entry = Map<String, dynamic>.from(row as Map);
        final item = project.mediaItemById(entry['id'] as String);
        if (item == null || !await File(item.filePath).exists()) continue;
        if (await mediaHash(item.filePath) != entry['sha256']) continue;
        // Validate before exposing private, potentially corrupt companion data.
        final cues = (entry['cues'] as List)
            .map((e) => cueFromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (cues.any((c) => c.end <= c.start)) continue;
        _entries[item.id] = entry;
      }
    } catch (_) {
      _entries.clear(); // Corrupt/missing sidecar never prevents opening v14.
    }
  }

  static Future<String> mediaHash(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
  Future<void> put(
    TgiProject project,
    MediaItem media,
    List<CaptionCue> cues, {
    required String language,
  }) async {
    await ready;
    if (_projectId != project.id) {
      _entries.clear();
      _projectId = project.id;
      projectPath = null;
    }
    final file = File(media.filePath);
    _entries[media.id] = {
      'id': media.id,
      'sha256': await file.exists() ? await mediaHash(media.filePath) : null,
      'language': language,
      'cues': cues.map((c) => c.toJson()).toList(),
    };
    // Synthetic/test media remain ephemeral.
    if (_bound && await file.exists()) await save(project);
  }

  Future<void> save(TgiProject project, {String? path}) async {
    await ready;
    if (_projectId != null && _projectId != project.id) return;
    // No sidecar is needed for an untouched project using built-in defaults.
    // In particular, ordinary v14 saves must not add an unnecessary disk write.
    if (_entries.isEmpty &&
        language == 'pt' &&
        !File(_path(project, path ?? projectPath)).existsSync()) {
      if (path != null) projectPath = path;
      return;
    }
    _projectId = project.id;
    if (path != null) projectPath = path;
    await ProjectFileStorage.write(
      _path(project, projectPath),
      () => jsonEncode({
        'schema': 1,
        'project_id': project.id,
        'language': language,
        'media': _entries.values.toList(),
      }),
    );
  }

  static CaptionCue cueFromJson(Map<String, dynamic> row) {
    Duration time(Object? v) =>
        Duration(microseconds: ((v as num).toDouble() * 1e6).round());
    return CaptionCue(
      start: time(row['start']),
      end: time(row['end']),
      text: row['text'] as String,
      words: [
        for (final w in row['words'] as List? ?? const [])
          CaptionWord(
            start: time(w['start']),
            end: time(w['end']),
            text: w['text'] as String,
          ),
      ],
    );
  }
}
