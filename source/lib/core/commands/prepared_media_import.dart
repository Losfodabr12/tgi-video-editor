import '../../domain/models/media_item.dart';
import 'editor_command.dart';

/// Only the trusted import preflight can attach probed media to a command.
/// JSON requests cannot construct this subtype or supply their own metadata.
class PreparedMediaImport extends EditorCommand {
  PreparedMediaImport(
    List<String> paths,
    List<MediaItem> media, {
    required this.verify,
    super.baseRevision,
    String commandName = 'import_media',
    Map<String, Object?>? commandArguments,
  }) : media = List.unmodifiable(media),
       super(commandName, commandArguments ?? {'paths': paths});

  final List<MediaItem> media;
  final Future<void> Function() verify;

  List<Map<String, Object?>> get summary => [
    for (final item in media)
      {
        'media_id': item.id,
        'duration': item.duration.inMicroseconds / 1e6,
        'type': item.type.name,
      },
  ];
}
