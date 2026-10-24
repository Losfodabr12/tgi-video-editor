import 'editor_command.dart';
import 'prepared_media_import.dart';

/// Resolved only from the app's fixed library, never caller-supplied URLs or metadata.
class PreparedLibraryInsert extends PreparedMediaImport {
  PreparedLibraryInsert(
    Map<String, Object?> arguments, {
    PreparedMediaImport? imported,
    this.preset,
    required Map<String, Object?> credit,
  }) : credit = Map.unmodifiable(credit),
       super(
         (imported?.arguments['paths'] as List?)?.cast<String>() ?? const [],
         imported?.media ?? const [],
         verify: imported?.verify ?? (() async {}),
         commandName: 'add_library_asset',
         commandArguments: arguments,
       );

  final EditorCommand? preset;
  final Map<String, Object?> credit;
  @override
  List<Map<String, Object?>> get summary => [
    for (final item in super.summary) {...item, ...credit},
  ];
}
