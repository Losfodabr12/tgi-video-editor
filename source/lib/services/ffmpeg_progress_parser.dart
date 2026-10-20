class FfmpegProgressParser {
  const FfmpegProgressParser();
  Duration? parse(String output) {
    final matches = RegExp(
      r'time=(\d+):(\d+):(\d+(?:\.\d+)?)',
    ).allMatches(output).toList();
    if (matches.isEmpty) {
      return null;
    }

    final match = matches.last;
    final hours = int.tryParse(match.group(1) ?? '');
    final minutes = int.tryParse(match.group(2) ?? '');
    final seconds = double.tryParse(match.group(3) ?? '');
    if (hours == null || minutes == null || seconds == null) {
      return null;
    }

    return Duration(
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }
}
