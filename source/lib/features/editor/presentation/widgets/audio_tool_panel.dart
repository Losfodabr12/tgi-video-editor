import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';
import '../../../../domain/models/track.dart';

typedef TrackBoolChanged = void Function(String trackId, bool value);
typedef TrackVolumeChanged = void Function(String trackId, double value);

class AudioToolPanel extends StatefulWidget {
  const AudioToolPanel({
    required this.clip,
    required this.mediaName,
    required this.audioTracks,
    required this.canUnlink,
    required this.onClipVolumeChanged,
    required this.onNoiseReductionChanged,
    required this.onFadeInChanged,
    required this.onFadeOutChanged,
    required this.onUnlink,
    required this.onTrackVolumeChanged,
    required this.onTrackMutedChanged,
    required this.onTrackSoloChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    this.peak = 0,
    this.meterReady = false,
    this.isAnalyzing = false,
    this.onAnalyzeLevels,
    this.onLevelVoice,
    this.onDuckMusic,
    super.key,
  });

  final double peak;
  final bool meterReady, isAnalyzing;
  final VoidCallback? onAnalyzeLevels, onLevelVoice;
  final void Function(String voiceTrackId, double reductionDb)? onDuckMusic;
  final Clip? clip;
  final String? mediaName;
  final List<Track> audioTracks;
  final bool canUnlink;
  final ValueChanged<double> onClipVolumeChanged;
  final ValueChanged<double> onNoiseReductionChanged;
  final ValueChanged<Duration> onFadeInChanged;
  final ValueChanged<Duration> onFadeOutChanged;
  final VoidCallback onUnlink;
  final TrackVolumeChanged onTrackVolumeChanged;
  final TrackBoolChanged onTrackMutedChanged;
  final TrackBoolChanged onTrackSoloChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  State<AudioToolPanel> createState() => _AudioToolPanelState();
}

class _AudioToolPanelState extends State<AudioToolPanel> {
  String? _voiceTrackId;
  double _duckDb = 12;
  double _volume = 1;
  double _noise = 0;
  double _fadeInMs = 0;
  double _fadeOutMs = 0;
  final Map<String, double> _trackVolumes = {};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AudioToolPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip?.id != widget.clip?.id ||
        oldWidget.clip?.volume != widget.clip?.volume ||
        oldWidget.clip?.audioNoiseReductionDb !=
            widget.clip?.audioNoiseReductionDb ||
        oldWidget.clip?.fadeIn != widget.clip?.fadeIn ||
        oldWidget.clip?.fadeOut != widget.clip?.fadeOut) {
      _sync();
    }
    for (final track in widget.audioTracks) {
      _trackVolumes.putIfAbsent(track.id, () => track.volume);
      if (oldWidget.audioTracks
              .where((candidate) => candidate.id == track.id)
              .firstOrNull
              ?.volume !=
          track.volume) {
        _trackVolumes[track.id] = track.volume;
      }
    }
  }

  void _sync() {
    final clip = widget.clip;
    _volume = clip?.volume ?? 1;
    _noise = clip?.audioNoiseReductionDb ?? 0;
    _fadeInMs = clip?.fadeIn.inMilliseconds.toDouble() ?? 0;
    _fadeOutMs = clip?.fadeOut.inMilliseconds.toDouble() ?? 0;
    for (final track in widget.audioTracks) {
      _trackVolumes[track.id] = track.volume;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    return ListView(
      padding: const EdgeInsets.all(TgiSpacing.md),
      children: [
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Níveis, voz e música'),
          subtitle: widget.meterReady
              ? Text(
                  widget.peak >= 1
                      ? 'Possível estouro de áudio'
                      : 'Medição de áudio disponível',
                )
              : null,
          children: [_audioEnhancements()],
        ),
        const Divider(),
        if (clip == null)
          const _NoAudioClip()
        else ...[
          _AudioClipCard(name: widget.mediaName ?? 'Áudio selecionado'),
          const SizedBox(height: TgiSpacing.md),
          _AudioSlider(
            label: 'Volume do clipe',
            value: _volume,
            min: 0,
            max: 2,
            divisions: 200,
            valueText: '${(_volume * 100).round()}%',
            onChangeStart: (_) => widget.onInteractionStart(),
            onChanged: (value) {
              setState(() => _volume = value);
              widget.onClipVolumeChanged(value);
            },
            onChangeEnd: (_) => widget.onInteractionEnd(),
          ),
          Row(
            children: [
              for (final preset in const [0.0, 0.5, 1.0, 1.5]) ...[
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      setState(() => _volume = preset);
                      widget.onClipVolumeChanged(preset);
                    },
                    child: Text('${(preset * 100).round()}%'),
                  ),
                ),
              ],
            ],
          ),
          const Divider(),
          _AudioSlider(
            label: 'Redução de ruído',
            value: _noise,
            min: 0,
            max: 30,
            divisions: 60,
            valueText: _noise <= 0.1
                ? 'Desligada'
                : '${_noise.toStringAsFixed(1)} dB',
            onChangeStart: (_) => widget.onInteractionStart(),
            onChanged: (value) {
              setState(() => _noise = value);
              widget.onNoiseReductionChanged(value);
            },
            onChangeEnd: (_) => widget.onInteractionEnd(),
          ),
          Text(
            'A redução é processada no áudio exportado; use valores altos apenas em gravações muito ruidosas.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
          ),
          const SizedBox(height: TgiSpacing.md),
          const _AudioSectionTitle('Fades do clipe'),
          _FadeEditor(
            clip: clip,
            fadeInMs: _fadeInMs,
            fadeOutMs: _fadeOutMs,
            onFadeInDraft: (value) => setState(() => _fadeInMs = value),
            onFadeOutDraft: (value) => setState(() => _fadeOutMs = value),
            onFadeInChanged: widget.onFadeInChanged,
            onFadeOutChanged: widget.onFadeOutChanged,
            onInteractionStart: widget.onInteractionStart,
            onInteractionEnd: widget.onInteractionEnd,
          ),
          const SizedBox(height: TgiSpacing.sm),
          OutlinedButton.icon(
            onPressed: widget.canUnlink ? widget.onUnlink : null,
            icon: const Icon(Icons.link_off_outlined),
            label: const Text('Separar áudio do vídeo'),
          ),
          if (!widget.canUnlink)
            Text(
              'O áudio já está independente ou a trilha está bloqueada.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
            ),
        ],
        const SizedBox(height: TgiSpacing.lg),
        const Divider(),
        const SizedBox(height: TgiSpacing.sm),
        const _AudioSectionTitle('Mixer de trilhas'),
        Text(
          'O volume da trilha multiplica o volume de cada clipe e é aplicado no preview e na exportação.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
        ),
        const SizedBox(height: TgiSpacing.sm),
        if (widget.audioTracks.isEmpty)
          const Text('Nenhuma trilha de áudio criada.')
        else
          for (final track in widget.audioTracks)
            _TrackMixerStrip(
              track: track,
              volume: _trackVolumes[track.id] ?? track.volume,
              onVolumeDraft: (value) =>
                  setState(() => _trackVolumes[track.id] = value),
              onVolumeChanged: (value) =>
                  widget.onTrackVolumeChanged(track.id, value),
              onInteractionStart: widget.onInteractionStart,
              onInteractionEnd: widget.onInteractionEnd,
              onMutedChanged: (value) =>
                  widget.onTrackMutedChanged(track.id, value),
              onSoloChanged: (value) =>
                  widget.onTrackSoloChanged(track.id, value),
            ),
      ],
    );
  }

  Widget _audioEnhancements() {
    final choices = widget.audioTracks
        .where(
          (track) =>
              !track.isHidden &&
              !track.clips.any((clip) => clip.id == widget.clip?.id),
        )
        .toList();
    final selectedVoice = choices.any((t) => t.id == _voiceTrackId)
        ? _voiceTrackId
        : null;
    final db = widget.peak > 0 ? 20 * math.log(widget.peak) / math.ln10 : -60.0;
    final clipping = widget.peak >= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AudioSectionTitle('Níveis e voz'),
        const SizedBox(height: 8),
        if (widget.isAnalyzing) const LinearProgressIndicator(),
        if (widget.meterReady) ...[
          Semantics(
            label: 'Pico estimado da mixagem ${db.toStringAsFixed(1)} dB',
            child: LinearProgressIndicator(
              value: ((db + 60) / 60).clamp(0.0, 1.0),
              minHeight: 10,
              color: clipping
                  ? Colors.redAccent
                  : db > -6
                  ? Colors.amber
                  : TgiColors.accentGreen,
            ),
          ),
          Text(
            'Pico estimado: ${widget.peak == 0 ? '−∞' : db.toStringAsFixed(1)} dB${clipping ? ' · Possível estouro' : ''}',
          ),
        ],
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('audio_analyze_levels'),
              onPressed: widget.isAnalyzing ? null : widget.onAnalyzeLevels,
              icon: const Icon(Icons.graphic_eq),
              label: const Text('Analisar níveis'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('audio_level_voice'),
              onPressed: widget.isAnalyzing || widget.clip == null
                  ? null
                  : widget.onLevelVoice,
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Ajustar voz'),
            ),
          ],
        ),
        const Text(
          'Ajustar voz define o ganho do clipe e substitui sua automação de volume. Você pode desfazer.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        const _AudioSectionTitle('Abaixar música durante a fala'),
        const Text(
          'Selecione a música na timeline e escolha a trilha que contém a voz.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('duck_voice_${widget.clip?.id}_$selectedVoice'),
          initialValue: selectedVoice,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Trilha de voz'),
          items: [
            for (final track in choices)
              DropdownMenuItem(
                value: track.id,
                child: Text(track.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: widget.isAnalyzing
              ? null
              : (value) => setState(() => _voiceTrackId = value),
        ),
        Text('Redução: ${_duckDb.round()} dB'),
        Slider(
          value: _duckDb,
          min: 6,
          max: 30,
          divisions: 24,
          onChanged: widget.isAnalyzing
              ? null
              : (value) => setState(() => _duckDb = value),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('audio_duck_music'),
          onPressed:
              widget.isAnalyzing ||
                  selectedVoice == null ||
                  widget.clip == null ||
                  widget.onDuckMusic == null
              ? null
              : () => widget.onDuckMusic!(selectedVoice, _duckDb),
          icon: const Icon(Icons.volume_down),
          label: const Text('Aplicar na música'),
        ),
      ],
    );
  }
}

class _FadeEditor extends StatelessWidget {
  const _FadeEditor({
    required this.clip,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.onFadeInDraft,
    required this.onFadeOutDraft,
    required this.onFadeInChanged,
    required this.onFadeOutChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final Clip clip;
  final double fadeInMs;
  final double fadeOutMs;
  final ValueChanged<double> onFadeInDraft;
  final ValueChanged<double> onFadeOutDraft;
  final ValueChanged<Duration> onFadeInChanged;
  final ValueChanged<Duration> onFadeOutChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(
      1.0,
      math.min(5000.0, clip.duration.inMilliseconds / 2),
    );
    return Column(
      children: [
        _AudioSlider(
          label: 'Entrada',
          value: fadeInMs.clamp(0.0, maximum),
          min: 0,
          max: maximum,
          divisions: math.max(1, (maximum / 50).round()),
          valueText: _durationLabel(fadeInMs),
          onChangeStart: (_) => onInteractionStart(),
          onChanged: (value) {
            onFadeInDraft(value);
            onFadeInChanged(Duration(milliseconds: value.round()));
          },
          onChangeEnd: (_) => onInteractionEnd(),
        ),
        _AudioSlider(
          label: 'Saída',
          value: fadeOutMs.clamp(0.0, maximum),
          min: 0,
          max: maximum,
          divisions: math.max(1, (maximum / 50).round()),
          valueText: _durationLabel(fadeOutMs),
          onChangeStart: (_) => onInteractionStart(),
          onChanged: (value) {
            onFadeOutDraft(value);
            onFadeOutChanged(Duration(milliseconds: value.round()));
          },
          onChangeEnd: (_) => onInteractionEnd(),
        ),
        Wrap(
          spacing: TgiSpacing.xs,
          children: [
            for (final ms in const [0, 250, 500, 1000])
              ActionChip(
                label: Text(ms == 0 ? 'Sem fade' : '${ms / 1000}s'),
                onPressed: () {
                  final safe = math.min(ms.toDouble(), maximum);
                  onInteractionStart();
                  onFadeInDraft(safe);
                  onFadeOutDraft(safe);
                  onFadeInChanged(Duration(milliseconds: safe.round()));
                  onFadeOutChanged(Duration(milliseconds: safe.round()));
                  onInteractionEnd();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _TrackMixerStrip extends StatelessWidget {
  const _TrackMixerStrip({
    required this.track,
    required this.volume,
    required this.onVolumeDraft,
    required this.onVolumeChanged,
    required this.onMutedChanged,
    required this.onSoloChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final Track track;
  final double volume;
  final ValueChanged<double> onVolumeDraft;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<bool> onMutedChanged;
  final ValueChanged<bool> onSoloChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: TgiSpacing.sm),
    child: Padding(
      padding: const EdgeInsets.all(TgiSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_outlined, size: 18),
              const SizedBox(width: TgiSpacing.xs),
              Expanded(
                child: Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Tooltip(
                message: 'Silenciar trilha',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onMutedChanged(!track.isMuted),
                  style: IconButton.styleFrom(
                    backgroundColor: track.isMuted
                        ? TgiColors.surfaceHover
                        : TgiColors.transparent,
                  ),
                  icon: Icon(
                    track.isMuted
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    color: TgiColors.textPrimary,
                  ),
                ),
              ),
              Tooltip(
                message: 'Ouvir somente esta trilha',
                child: FilterChip(
                  selected: track.isSolo,
                  label: const Text('S'),
                  onSelected: onSoloChanged,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: volume.clamp(0.0, 2.0),
                  min: 0,
                  max: 2,
                  divisions: 200,
                  onChangeStart: (_) => onInteractionStart(),
                  onChanged: (value) {
                    onVolumeDraft(value);
                    onVolumeChanged(value);
                  },
                  onChangeEnd: (_) => onInteractionEnd(),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(volume * 100).round()}%',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AudioSlider extends StatelessWidget {
  const _AudioSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
    required this.onChangeEnd,
    this.onChangeStart,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueText;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final ValueChanged<double>? onChangeStart;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            valueText,
            style: TextStyle(
              color: TgiColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChangeStart: onChangeStart,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    ],
  );
}

class _AudioClipCard extends StatelessWidget {
  const _AudioClipCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      dense: true,
      leading: const Icon(Icons.audiotrack_outlined),
      title: const Text('Clipe de áudio'),
      subtitle: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

class _AudioSectionTitle extends StatelessWidget {
  const _AudioSectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _NoAudioClip extends StatelessWidget {
  const _NoAudioClip();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: TgiSpacing.lg),
    child: Text(
      'Selecione um clipe com áudio para editar volume, ruído e fades. O mixer continua disponível abaixo.',
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
    ),
  );
}

String _durationLabel(double milliseconds) {
  if (milliseconds <= 0.5) return 'Desligado';
  return '${(milliseconds / 1000).toStringAsFixed(2)}s';
}
