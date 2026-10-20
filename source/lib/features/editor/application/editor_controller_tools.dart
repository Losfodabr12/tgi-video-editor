part of 'editor_controller.dart';

extension EditorControllerTools on EditorController {
  void importSrt(String source) {
    try {
      final cues = SubtitleService.parseSrt(source);
      _addCaptionCuesToTimeline(
        cues,
        fontFamily: NewTextStyle.fontFamily,
        fontSize: 36,
        textColor: 0xFFFFFFFF,
        backgroundColor: NewTextStyle.backgroundColor,
        opacity: 1,
        textAnimation: domain.TextClipAnimation.none,
      );
      _errorMessage = null;
      _statusMessage = '${cues.length} legendas importadas.';
    } catch (error) {
      _errorMessage = _cleanError(error);
    }
    notifyListeners();
  }

  void applyCaptionStyle(CaptionStyle style) {
    final captions = generatedCaptionClips;
    if (captions.any((clip) => _clipIsOnLockedTrack(clip.id))) {
      _errorMessage =
          'Destrave as pistas de legenda antes de alterar o estilo.';
    } else if (captions.isNotEmpty) {
      _replaceToolClips({
        for (final clip in captions) clip.id: style.apply(clip),
      });
      _errorMessage = null;
      _statusMessage = 'Estilo aplicado a ${captions.length} legendas.';
    }
    notifyListeners();
  }

  void registerSelectedTextClipsAsCaptions() {
    final groups = _effectiveSelectedTimelineGroupIds();
    final selected = project.tracks
        .expand((t) => t.clips)
        .where(
          (c) =>
              groups.contains(c.timelineGroupId) &&
              c.trackType == TrackType.text,
        )
        .toList();
    if (selected.isEmpty) {
      _errorMessage = 'Selecione os textos que deseja incluir nas legendas.';
    } else if (selected.any((clip) => _clipIsOnLockedTrack(clip.id))) {
      _errorMessage =
          'Destrave a trilha de texto antes de alterar as legendas.';
    } else {
      _replaceToolClips({
        for (final clip in selected) clip.id: clip.copyWith(isCaption: true),
      });
      _statusMessage =
          '${selected.length} texto(s) incluído(s) nas legendas SRT/VTT.';
      _errorMessage = null;
    }
    notifyListeners();
  }

  void applyPersonalPreset(EditorPreset preset) {
    final clip = selectedTimelineClip;
    if (clip == null) return;
    if (_clipIsOnLockedTrack(clip.id)) {
      _errorMessage = 'A trilha está travada.';
    } else {
      try {
        _replaceToolClips({clip.id: EditorPresetService.apply(preset, clip)});
        _errorMessage = null;
        _statusMessage = 'Modelo aplicado: ${preset.name}';
      } catch (error) {
        _errorMessage = _cleanError(error);
      }
    }
    notifyListeners();
  }

  void _replaceToolClips(Map<String, domain.Clip> replacements) {
    if (replacements.isEmpty) return;
    _pushHistory();
    _project = _project.copyWith(
      updatedAt: DateTime.now(),
      tracks: [
        for (final track in _project.tracks)
          track.copyWith(
            clips: [
              for (final clip in track.clips) replacements[clip.id] ?? clip,
            ],
          ),
      ],
    );
  }

  bool get isAnalyzingAudio => _isAnalyzingAudio;
  bool get audioMeterReady => _audioLevels.isNotEmpty;

  Future<void> analyzeAudioLevels() async {
    if (_isAnalyzingAudio || _disposed) return;
    _isAnalyzingAudio = true;
    _errorMessage = null;
    notifyListeners();
    final snapshot = _project;
    try {
      final ids = snapshot.tracks
          .where((t) => t.type == TrackType.audio && !t.isHidden)
          .expand((t) => t.clips)
          .map((c) => c.mediaItemId)
          .toSet();
      for (final id in ids) {
        final item = snapshot.mediaItemById(id);
        if (item == null || !item.hasAudio) continue;
        final levels = await _audioLevelService.analyze(item.filePath);
        if (_disposed || _project.id != snapshot.id) return;
        _audioLevels[item.filePath] = levels;
      }
      _statusMessage =
          'Níveis analisados. Reproduza para acompanhar o pico estimado da mixagem.';
    } catch (error) {
      _errorMessage = _cleanError(error);
    } finally {
      _isAnalyzingAudio = false;
      notifyListeners();
    }
  }

  double get audioPeakAtPlayhead {
    var total = 0.0;
    for (final track in _project.tracks) {
      if (!_audioTrackIsAudible(track)) continue;
      for (final clip in track.clips) {
        if (!_clipContainsTimelinePosition(clip, _playheadPosition)) continue;
        final item = _project.mediaItemById(clip.mediaItemId);
        if (item == null) continue;
        final position = _sourcePositionForTimelineClip(
          clip,
          _playheadPosition,
        );
        final peak = _audioLevels[item.filePath]?.at(position).peak ?? 0;
        total +=
            peak *
            _keyframedClipValueAtPlayhead(
              clip,
              domain.ClipKeyframeProperty.volume,
            ) *
            track.volume *
            previewOpacityForClip(clip);
      }
    }
    return total;
  }

  Future<void> levelSelectedVoice() async {
    final clip = selectedTimelineAudioClip;
    if (clip == null || _isAnalyzingAudio || _disposed) return;
    if (_clipIsOnLockedTrack(clip.id)) {
      _errorMessage = 'A trilha está travada.';
      notifyListeners();
      return;
    }
    final item = _project.mediaItemById(clip.mediaItemId);
    if (item == null) return;
    final snapshot = _project;
    _isAnalyzingAudio = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final levels = await _audioLevelService.analyze(item.filePath);
      if (_disposed || !identical(snapshot, _project)) {
        if (!_disposed) {
          _statusMessage =
              'A edição mudou durante a análise. Aplique o ajuste novamente.';
        }
        return;
      }
      _audioLevels[item.filePath] = levels;
      final measured = levels.measure(
        clip.sourceStart,
        clip.effectiveSourceDuration,
      );
      if (measured.rms <= 0.000001) {
        throw const FormatException('O trecho selecionado está silencioso.');
      }
      final trackGain = _trackForClipId(clip.id)?.volume ?? 1;
      if (trackGain <= 0) {
        throw const FormatException(
          'Aumente o volume da trilha antes de ajustar a voz.',
        );
      }
      final target = math.pow(10, -18 / 20).toDouble();
      final ceiling = math.pow(10, -1 / 20).toDouble();
      final gain =
          math.min(target / measured.rms, ceiling / measured.peak) / trackGain;
      _replaceToolClips({
        clip.id: clip.copyWith(
          volume: gain.clamp(0.0, 2.0),
          keyframes: clip.keyframes
              .where((k) => k.property != domain.ClipKeyframeProperty.volume)
              .toList(),
        ),
      });
      _statusMessage =
          'Voz ajustada para ${((gain.clamp(0.0, 2.0)) * 100).round()}%. Meta: −18 dB RMS, pico até −1 dB.';
    } catch (error) {
      _errorMessage = _cleanError(error);
    } finally {
      _isAnalyzingAudio = false;
      notifyListeners();
    }
  }

  Future<void> duckSelectedMusic(
    String voiceTrackId, {
    double reductionDb = 12,
  }) async {
    final music = selectedTimelineAudioClip;
    if (music == null || _isAnalyzingAudio || _disposed) return;
    if (_clipIsOnLockedTrack(music.id)) {
      _errorMessage = 'A trilha está travada.';
      notifyListeners();
      return;
    }
    final voiceTrack = _project.tracks
        .where((t) => t.id == voiceTrackId && t.type == TrackType.audio)
        .firstOrNull;
    if (voiceTrack == null || voiceTrack.clips.any((c) => c.id == music.id)) {
      _errorMessage = 'Escolha outra trilha como voz.';
      notifyListeners();
      return;
    }
    if (!_audioTrackIsAudible(voiceTrack)) {
      _errorMessage = 'A trilha de voz precisa estar audível.';
      notifyListeners();
      return;
    }
    _isAnalyzingAudio = true;
    _errorMessage = null;
    final snapshot = _project;
    notifyListeners();
    try {
      final intervals = <SpeechInterval>[];
      for (final voice in voiceTrack.clips) {
        if (voice.timelineEnd <= music.timelineStart ||
            voice.timelineStart >= music.timelineEnd) {
          continue;
        }
        final item = snapshot.mediaItemById(voice.mediaItemId);
        if (item == null) continue;
        final levels = await _audioLevelService.analyze(item.filePath);
        if (_disposed || !identical(snapshot, _project)) {
          if (!_disposed) {
            _statusMessage =
                'A edição mudou durante a análise. Aplique novamente.';
          }
          return;
        }
        _audioLevels[item.filePath] = levels;
        final paired = snapshot.tracks
            .where((t) => t.type == TrackType.video)
            .expand((t) => t.clips)
            .where((c) => c.timelineGroupId == voice.timelineGroupId)
            .firstOrNull;
        const step = Duration(milliseconds: 100);
        for (
          var time = _maxDuration(voice.timelineStart, music.timelineStart);
          time < _minDuration(voice.timelineEnd, music.timelineEnd);
          time += step
        ) {
          final delta = time - voice.timelineStart;
          final offset = _sourceDurationForTimeline(delta, voice.playbackSpeed);
          final source = paired?.reverseVideo == true
              ? voice.sourceEnd - offset
              : voice.sourceStart + offset;
          final gain =
              voice.keyframedValue(
                domain.ClipKeyframeProperty.volume,
                delta.inMicroseconds / voice.duration.inMicroseconds,
              ) *
              voiceTrack.volume;
          if (levels.at(source).rms * gain >= 0.0178) {
            intervals.add(
              SpeechInterval(
                time,
                _minDuration(time + step, voice.timelineEnd),
              ),
            );
          }
        }
      }
      if (intervals.isEmpty) {
        throw const FormatException(
          'Não encontrei voz audível sobre este trecho de música.',
        );
      }
      _replaceToolClips({
        music.id: music.copyWith(
          keyframes: buildDuckingKeyframes(
            music,
            intervals,
            reductionDb: reductionDb,
          ),
        ),
      });
      _statusMessage =
          'Música reduzida durante a voz. A automação de volume é editável e pode ser desfeita.';
    } catch (error) {
      _errorMessage = _cleanError(error);
    } finally {
      _isAnalyzingAudio = false;
      notifyListeners();
    }
  }
}
