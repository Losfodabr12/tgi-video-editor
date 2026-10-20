import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'ffmpeg_service_models.dart';

class FfmpegExecutor {
  const FfmpegExecutor();
  void writeTextInputs(Map<String, String> inputs) {
    for (final entry in inputs.entries) {
      final file = File(entry.key);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value, flush: true);
    }
  }

  bool get usesEmbeddedMobileFfmpeg => Platform.isAndroid || Platform.isIOS;

  Future<MediaProcessHandle> start(
    String executable,
    List<String> arguments,
  ) async {
    if (usesEmbeddedMobileFfmpeg) {
      return MobileMediaProcessHandle.start(arguments);
    }
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
    );
    return DesktopMediaProcessHandle(process);
  }

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (!usesEmbeddedMobileFfmpeg) {
      return Process.run(
        executable,
        arguments,
        runInShell: !_isAbsoluteWindowsPath(executable),
      );
    }

    final isProbe = executable.toLowerCase().contains('ffprobe');
    final session = isProbe
        ? await FFprobeKit.executeWithArguments(arguments)
        : await FFmpegKit.executeWithArguments(arguments);
    final returnCode = await session.getReturnCode();
    final output = await session.getOutput() ?? '';
    final exitCode = returnCode?.getValue() ?? -1;
    return ProcessResult(
      0,
      exitCode,
      isProbe ? output : '',
      isProbe && exitCode == 0 ? '' : output,
    );
  }

  bool _isAbsoluteWindowsPath(String value) =>
      value.startsWith(r'\\') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
}
