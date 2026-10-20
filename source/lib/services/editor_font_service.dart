import 'dart:io';

import 'package:flutter/services.dart';

import 'app_component_paths.dart';
import '../domain/text_style_profile.dart';

/// A single catalog for the text inspector, captions and FFmpeg.
class EditorFontService {
  static const bundled = <String, String>{
    NewTextStyle.fontFamily: 'Lato-Bold.ttf',
    'Anton': 'Anton-Regular.ttf',
    'Bebas Neue': 'BebasNeue-Regular.ttf',
    'Poppins': 'Poppins-Bold.ttf',
    'Lato': 'Lato-Bold.ttf',
    'Lobster': 'Lobster-Regular.ttf',
    'Pacifico': 'Pacifico-Regular.ttf',
    'Righteous': 'Righteous-Regular.ttf',
    'Bangers': 'Bangers-Regular.ttf',
    'Bungee': 'Bungee-Regular.ttf',
    'Audiowide': 'Audiowide-Regular.ttf',
    'Caveat Brush': 'CaveatBrush-Regular.ttf',
    'Rajdhani': 'Rajdhani-Bold.ttf',
    'Russo One': 'RussoOne-Regular.ttf',
  };
  static const systemFonts = <String, String>{
    'Arial': 'arialbd.ttf',
    'Segoe UI': 'segoeuib.ttf',
    'Times New Roman': 'timesbd.ttf',
    'Georgia': 'georgiab.ttf',
    'Courier New': 'courbd.ttf',
    'Impact': 'impact.ttf',
  };
  static const families = [
    'Arial',
    'Segoe UI',
    'Times New Roman',
    'Georgia',
    'Courier New',
    'Impact',
    'Anton',
    'Bebas Neue',
    'Poppins',
    'Lato',
    'Lobster',
    'Pacifico',
    'Righteous',
    'Bangers',
    'Bungee',
    'Audiowide',
    'Caveat Brush',
    'Rajdhani',
    'Russo One',
    NewTextStyle.fontFamily,
  ];
  static final _prepared = <String, Future<String>>{};

  static String _canonical(String family) => families.firstWhere(
    (name) => name.toLowerCase() == family.trim().toLowerCase(),
    orElse: () => 'Arial',
  );

  static String filePath(String family) {
    final name = _canonical(family);
    if (systemFonts.containsKey(name) && Platform.isWindows) {
      final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
      final file = File(
        joinPlatformPath([windows, 'Fonts', systemFonts[name]!]),
      );
      if (file.existsSync()) return file.path;
    }
    // Old Windows-only families get a bundled fallback on mobile.
    final asset = bundled[name] ?? bundled['Lato']!;
    return joinPlatformPath([tgiAppLocalDataRoot(), 'editor_fonts', asset]);
  }

  static Future<void> prepare(Iterable<String> families) async {
    for (final family in families.toSet()) {
      final path = filePath(family);
      if (File(path).existsSync()) continue;
      final name = _canonical(family);
      final asset = bundled[name] ?? bundled['Lato']!;
      await (_prepared[path] ??= _extract(asset, path).catchError((Object e) {
        _prepared.remove(path);
        throw e;
      }));
    }
  }

  static Future<String> _extract(String asset, String path) async {
    final data = await rootBundle.load('assets/fonts/$asset');
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File(
      '$path.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await temporary.rename(path);
    return path;
  }
}
