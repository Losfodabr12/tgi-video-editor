class AudioWaveform {
  const AudioWaveform({required this.samples, required this.sampleInterval});

  static const empty = AudioWaveform(
    samples: <double>[],
    sampleInterval: Duration(milliseconds: 100),
  );

  final List<double> samples;
  final Duration sampleInterval;

  List<double> samplesFor({
    required Duration sourceStart,
    required Duration duration,
  }) {
    if (samples.isEmpty ||
        duration <= Duration.zero ||
        sampleInterval <= Duration.zero) {
      return const <double>[];
    }

    final intervalUs = sampleInterval.inMicroseconds;
    final startUs = sourceStart.inMicroseconds;
    final endUs = startUs + duration.inMicroseconds;
    final startIndex = (startUs ~/ intervalUs).clamp(0, samples.length);
    final endIndex = ((endUs + intervalUs - 1) ~/ intervalUs).clamp(
      startIndex,
      samples.length,
    );
    if (endIndex <= startIndex) {
      return const <double>[];
    }
    return samples.sublist(startIndex, endIndex);
  }
}
