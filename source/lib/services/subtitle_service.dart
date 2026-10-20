import '../domain/models/clip.dart';
import 'auto_caption_service.dart';

class CaptionStyle {
  const CaptionStyle({
    this.fontFamily = 'Lato',
    this.fontSize = 36,
    this.textColor = 0xFFFFFFFF,
    this.backgroundColor = 0x99000000,
    this.opacity = 1,
    this.x = .5,
    this.y = .9,
  });
  factory CaptionStyle.fromClip(Clip clip) => CaptionStyle(
    fontFamily: clip.fontFamily,
    fontSize: clip.fontSize,
    textColor: clip.textColor,
    backgroundColor: clip.backgroundColor,
    opacity: clip.opacity,
    x: clip.overlayX,
    y: clip.overlayY,
  );
  final String fontFamily;
  final double fontSize, opacity, x, y;
  final int textColor, backgroundColor;
  Clip apply(Clip clip) => clip.copyWith(
    fontFamily: fontFamily,
    fontSize: fontSize,
    textColor: textColor,
    backgroundColor: backgroundColor,
    opacity: opacity,
    overlayX: x,
    overlayY: y,
  );
}

abstract final class SubtitleService {
  static List<CaptionCue> parseSrt(String source) {
    final normalized = source
        .replaceAll('\ufeff', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) throw const FormatException('SRT vazio.');
    final cues = <CaptionCue>[];
    final time = RegExp(r'^(\d{2,}):(\d{2}):(\d{2})[,.](\d{3})$');
    Duration parseTime(String value) {
      final match = time.firstMatch(value.trim());
      if (match == null) throw FormatException('Tempo SRT invalido: $value');
      final values = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
      if (values[1] >= 60 || values[2] >= 60) {
        throw FormatException('Tempo SRT invalido: $value');
      }
      return Duration(
        hours: values[0],
        minutes: values[1],
        seconds: values[2],
        milliseconds: values[3],
      );
    }

    for (final block in normalized.split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n');
      if (RegExp(r'^\d+$').hasMatch(lines.first.trim())) lines.removeAt(0);
      if (lines.length < 2) {
        throw const FormatException('Bloco SRT sem texto/tempo.');
      }
      final times = lines.removeAt(0).split('-->');
      if (times.length != 2) {
        throw const FormatException('Intervalo SRT invalido.');
      }
      final start = parseTime(times[0]),
          end = parseTime(times[1].trim().split(RegExp(r'\s+')).first);
      final text = lines.join('\n').trim();
      if (end <= start || text.isEmpty) {
        throw const FormatException('Legenda sem duracao ou texto.');
      }
      cues.add(CaptionCue(start: start, end: end, text: text));
    }
    return cues;
  }
}
