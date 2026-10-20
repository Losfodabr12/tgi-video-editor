import '../../../domain/models/audio_waveform.dart';
import '../../../services/auto_caption_service.dart';

const _captionMinDuration = Duration(milliseconds: 1200);
const _captionMaxDuration = Duration(milliseconds: 3500);
const _captionAudioSearchPadding = Duration(milliseconds: 900);
const _captionAudioLead = Duration(milliseconds: 80);
const _captionAudioTail = Duration(milliseconds: 260);
const _captionAudioMinDuration = Duration(milliseconds: 600);
const _captionAudioMaxDuration = Duration(milliseconds: 2600);
const _captionTimelineGap = Duration(milliseconds: 80);
const _captionAudioThresholdFloor = 0.08;
const _captionAudioThresholdRatio = 0.24;

/// Caption timing without widget state, IO or controller mutation.
class EditorCaptionTiming {
  const EditorCaptionTiming();
  Duration _maxDuration(Duration a, Duration b) => a > b ? a : b;
  double _maxDouble(double a, double b) => a > b ? a : b;
  CaptionCue alignCaptionCueToWaveform(CaptionCue cue, AudioWaveform waveform) {
    if (cue.end <= cue.start ||
        waveform.samples.isEmpty ||
        waveform.sampleInterval <= Duration.zero) {
      return cue;
    }

    final intervalUs = waveform.sampleInterval.inMicroseconds;
    final searchStart = _maxDuration(
      Duration.zero,
      cue.start - _captionAudioSearchPadding,
    );
    final searchEnd = cue.end + _captionAudioSearchPadding;
    final startIndex = (searchStart.inMicroseconds ~/ intervalUs).clamp(
      0,
      waveform.samples.length,
    );
    final endIndex = ((searchEnd.inMicroseconds + intervalUs - 1) ~/ intervalUs)
        .clamp(startIndex, waveform.samples.length);
    if (endIndex <= startIndex) {
      return cue;
    }

    var localPeak = 0.0;
    for (var index = startIndex; index < endIndex; index++) {
      final sample = waveform.samples[index];
      if (sample > localPeak) {
        localPeak = sample;
      }
    }
    if (localPeak <= 0) {
      return cue;
    }

    final threshold = _maxDouble(
      _captionAudioThresholdFloor,
      localPeak * _captionAudioThresholdRatio,
    );
    var firstAudible = -1;
    for (var index = startIndex; index < endIndex; index++) {
      if (_waveformHasActivityAt(waveform.samples, index, threshold)) {
        firstAudible = index;
        break;
      }
    }
    if (firstAudible < 0) {
      return cue;
    }

    var lastAudible = firstAudible;
    for (var index = endIndex - 1; index >= firstAudible; index--) {
      if (_waveformHasActivityAt(waveform.samples, index, threshold)) {
        lastAudible = index;
        break;
      }
    }

    var start = Duration(microseconds: firstAudible * intervalUs);
    start = _maxDuration(Duration.zero, start - _captionAudioLead);
    var end = Duration(microseconds: (lastAudible + 1) * intervalUs);
    end += _captionAudioTail;
    final maxEnd = start + _captionAudioMaxDuration;
    if (end > maxEnd) {
      end = maxEnd;
    }
    final minEnd = start + _captionAudioMinDuration;
    if (end < minEnd) {
      end = minEnd;
    }
    if (end <= start) {
      return cue;
    }
    return CaptionCue(start: start, end: end, text: cue.text);
  }

  bool _waveformHasActivityAt(
    List<double> samples,
    int index,
    double threshold,
  ) {
    if (samples[index] >= threshold) {
      return true;
    }
    var nearbyActive = 0;
    for (var offset = -1; offset <= 1; offset++) {
      final nearbyIndex = index + offset;
      if (nearbyIndex < 0 || nearbyIndex >= samples.length) {
        continue;
      }
      if (samples[nearbyIndex] >= threshold) {
        nearbyActive++;
      }
    }
    return nearbyActive >= 2;
  }

  List<CaptionCue> resolveCaptionCueOverlaps(
    List<CaptionCue> cues, {
    Duration? timelineLimit,
  }) {
    if (cues.isEmpty) {
      return const [];
    }

    final sorted = [...cues]
      ..sort((a, b) {
        final startCompare = a.start.compareTo(b.start);
        if (startCompare != 0) {
          return startCompare;
        }
        return a.end.compareTo(b.end);
      });
    final normalized = <CaptionCue>[];
    var previousEnd = Duration.zero;

    for (final cue in sorted) {
      var start = cue.start;
      if (normalized.isNotEmpty && start < previousEnd + _captionTimelineGap) {
        start = previousEnd + _captionTimelineGap;
      }
      final limit = timelineLimit;
      if (limit != null && start >= limit) {
        continue;
      }

      var end = cue.end;
      final minimumEnd = start + _captionAudioMinDuration;
      if (end < minimumEnd) {
        end = minimumEnd;
      }
      if (limit != null && end > limit) {
        end = limit;
      }
      if (end <= start || cue.text.trim().isEmpty) {
        continue;
      }

      normalized.add(CaptionCue(start: start, end: end, text: cue.text));
      previousEnd = end;
    }

    return normalized;
  }

  List<String> captionChunks(String transcript, int wordsPerCaption) {
    final normalized = transcript.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return const [];
    }
    final targetWords = wordsPerCaption.clamp(3, 8).toInt();
    final sentences = normalized
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty);
    final chunks = <String>[];
    for (final sentence in sentences) {
      final words = sentence.split(' ');
      for (var index = 0; index < words.length; index += targetWords) {
        final end = (index + targetWords).clamp(0, words.length);
        chunks.add(words.sublist(index, end).join(' '));
      }
    }
    return chunks;
  }

  Duration clampCaptionDuration(Duration duration) {
    if (duration < _captionMinDuration) {
      return _captionMinDuration;
    }
    if (duration > _captionMaxDuration) {
      return _captionMaxDuration;
    }
    return duration;
  }
}
