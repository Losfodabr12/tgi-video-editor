import 'whisper_runtime.dart';

class WhisperModelDecision {
  const WhisperModelDecision(this.model, {this.forceCpu = false});
  final String model;
  final bool forceCpu;
}

abstract final class WhisperModelPolicy {
  // Conservative headroom for weights, compute buffers and display usage.
  static const turboFreeBytes = 2 * 1024 * 1024 * 1024;
  static const turboTotalBytes = 3 * 1024 * 1024 * 1024;
  static WhisperModelDecision choose({
    String requested = '',
    WhisperGpuDevice? gpu,
  }) {
    if (requested.trim().isNotEmpty) {
      return WhisperModelDecision(requested.trim());
    }
    if (gpu != null &&
        gpu.freeBytes >= turboFreeBytes &&
        gpu.totalBytes >= turboTotalBytes) {
      return const WhisperModelDecision('large-v3-turbo-q5_0');
    }
    return const WhisperModelDecision('small', forceCpu: true);
  }
}
