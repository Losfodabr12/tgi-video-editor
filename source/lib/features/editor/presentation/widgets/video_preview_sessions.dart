part of 'video_preview_panel.dart';

class _PreviewOutputSize {
  const _PreviewOutputSize({
    required this.width,
    required this.height,
    required this.downscaled,
  });

  final int width;
  final int height;
  final bool downscaled;
}

class _PreloadVideoSurface extends StatelessWidget {
  const _PreloadVideoSurface({required this.session});

  final _PreloadedPreviewSession session;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: Video(
            controller: session.videoController,
            fit: BoxFit.cover,
            fill: TgiColors.transparent,
            filterQuality: FilterQuality.none,
            controls: NoVideoControls,
            wakelock: false,
          ),
        ),
      ),
    );
  }
}

_PreviewOutputSize _previewOutputSizeFor(MediaItem item) {
  final mediaWidth = item.width;
  final mediaHeight = item.height;
  if (mediaWidth == null ||
      mediaHeight == null ||
      mediaWidth <= 0 ||
      mediaHeight <= 0) {
    return const _PreviewOutputSize(
      width: _maxPreviewOutputWidth,
      height: _maxPreviewOutputHeight,
      downscaled: true,
    );
  }

  final scale = math.min(
    1.0,
    math.min(
      _maxPreviewOutputWidth / mediaWidth,
      _maxPreviewOutputHeight / mediaHeight,
    ),
  );
  final outputWidth = _evenDimension((mediaWidth * scale).round());
  final outputHeight = _evenDimension((mediaHeight * scale).round());
  return _PreviewOutputSize(
    width: outputWidth,
    height: outputHeight,
    downscaled: scale < 0.999,
  );
}

int _evenDimension(int value) {
  final clamped = math.max(2, value);
  return clamped.isEven ? clamped : clamped - 1;
}

class _TimelineTransitionPreviewLayer extends StatefulWidget {
  const _TimelineTransitionPreviewLayer({
    required this.entries,
    required this.playing,
  });

  final List<TransitionPreviewEntry> entries;
  final bool playing;

  @override
  State<_TimelineTransitionPreviewLayer> createState() =>
      _TimelineTransitionPreviewLayerState();
}

class _TimelineTransitionPreviewLayerState
    extends State<_TimelineTransitionPreviewLayer> {
  static const _resyncThreshold = Duration(milliseconds: 55);

  final Map<String, _TransitionPreviewSession> _sessions = {};
  int _syncRevision = 0;
  bool _syncInProgress = false;
  bool _syncPending = false;

  @override
  void initState() {
    super.initState();
    _scheduleSyncEntries();
  }

  @override
  void didUpdateWidget(covariant _TimelineTransitionPreviewLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadVideoTransition = oldWidget.entries.any(
      (entry) => !entry.isPreset,
    );
    final hasVideoTransition = widget.entries.any((entry) => !entry.isPreset);
    if (!hadVideoTransition && !hasVideoTransition) {
      return;
    }
    if (oldWidget.entries != widget.entries ||
        oldWidget.playing != widget.playing) {
      _scheduleSyncEntries();
    }
  }

  void _scheduleSyncEntries() {
    if (_syncInProgress) {
      _syncPending = true;
      return;
    }
    unawaited(_runScheduledSyncEntries());
  }

  Future<void> _runScheduledSyncEntries() async {
    _syncInProgress = true;
    try {
      do {
        _syncPending = false;
        await _syncEntries();
      } while (mounted && _syncPending);
    } finally {
      _syncInProgress = false;
    }
  }

  @override
  void dispose() {
    _syncRevision++;
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      unawaited(session.dispose());
    }
    super.dispose();
  }

  Future<void> _syncEntries() async {
    final revision = ++_syncRevision;
    final entriesById = {
      for (final entry in widget.entries)
        if (!entry.isPreset) entry.id: entry,
    };
    final removedIds = _sessions.keys
        .where((id) => !entriesById.containsKey(id))
        .toList(growable: false);
    for (final id in removedIds) {
      final session = _sessions.remove(id);
      if (session != null) {
        unawaited(session.dispose());
      }
    }

    for (final entry in entriesById.values) {
      if (!mounted || revision != _syncRevision) {
        return;
      }
      final session = _sessions.putIfAbsent(
        entry.id,
        () => _TransitionPreviewSession(Player()),
      );
      await _syncSession(session, entry, revision);
    }

    if (mounted && revision == _syncRevision) {
      setState(() {});
    }
  }

  Future<void> _syncSession(
    _TransitionPreviewSession session,
    TransitionPreviewEntry entry,
    int revision,
  ) async {
    if (session.disposed) {
      return;
    }
    try {
      if (!await File(entry.filePath).exists()) {
        return;
      }
      if (!mounted || revision != _syncRevision || session.disposed) {
        return;
      }

      if (session.openedPath != entry.filePath) {
        await session.player.open(
          Media(Uri.file(entry.filePath).toString()),
          play: false,
        );
        session.openedPath = entry.filePath;
        await session.player.setVolume(0);
      }
      if (!mounted || revision != _syncRevision || session.disposed) {
        return;
      }

      final current = session.player.state.position;
      final drift = (current - entry.sourcePosition).inMilliseconds.abs();
      if (!widget.playing || drift > _resyncThreshold.inMilliseconds) {
        await session.player.seek(entry.sourcePosition);
      }
      if (!mounted || revision != _syncRevision || session.disposed) {
        return;
      }

      if (widget.playing && !session.player.state.playing) {
        await session.player.play();
      } else if (!widget.playing && session.player.state.playing) {
        await session.player.pause();
      }
    } catch (_) {
      // Transition preview is best-effort. Export still uses FFmpeg data.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final entry in widget.entries)
            if (entry.isPreset)
              _TransitionPresetPreview(
                key: ValueKey('transition_preset_preview_${entry.id}'),
                entry: entry,
              )
            else
              _TransitionPreviewVideo(
                key: ValueKey('transition_preview_${entry.id}'),
                entry: entry,
                session: _sessions[entry.id],
              ),
        ],
      ),
    );
  }
}

class _TransitionPresetPreview extends StatelessWidget {
  const _TransitionPresetPreview({required this.entry, super.key});

  final TransitionPreviewEntry entry;

  @override
  Widget build(BuildContext context) {
    final preset = entry.preset;
    final progress = entry.duration <= Duration.zero
        ? 1.0
        : (entry.sourcePosition.inMicroseconds / entry.duration.inMicroseconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final effectStrength = entry.placement == TimelineTransitionPlacement.start
        ? 1 - progress
        : math.sin(progress * math.pi);
    final opacity = effectStrength * entry.intensity.clamp(0.0, 1.0).toDouble();
    final color = Color(entry.color).withValues(alpha: opacity);

    if (preset == TimelineTransitionPreset.wipe) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final offset = switch (entry.direction) {
            TimelineTransitionDirection.rightToLeft => Offset(
              width - progress * 2 * width,
              0,
            ),
            TimelineTransitionDirection.topToBottom => Offset(
              0,
              -height + progress * 2 * height,
            ),
            TimelineTransitionDirection.bottomToTop => Offset(
              0,
              height - progress * 2 * height,
            ),
            TimelineTransitionDirection.leftToRight => Offset(
              -width + progress * 2 * width,
              0,
            ),
          };
          return Transform.translate(
            offset: offset,
            child: SizedBox.expand(child: ColoredBox(color: color)),
          );
        },
      );
    }

    if (preset == TimelineTransitionPreset.blur) {
      return Positioned.fill(
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: 10 * opacity,
              sigmaY: 10 * opacity,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    if (preset == TimelineTransitionPreset.glitch ||
        preset == TimelineTransitionPreset.pixelate) {
      return Positioned.fill(
        child: CustomPaint(
          painter: _SyntheticTransitionPainter(
            preset: preset!,
            progress: progress,
            opacity: opacity,
          ),
        ),
      );
    }

    if (preset == TimelineTransitionPreset.spin) {
      return Positioned.fill(
        child: Transform.rotate(
          angle: math.sin(progress * math.pi * 2) * 0.16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: TgiColors.accentSoft.withValues(alpha: opacity * 0.7),
                width: 8,
              ),
            ),
          ),
        ),
      );
    }

    if (preset == TimelineTransitionPreset.zoom) {
      return Positioned.fill(
        child: Transform.scale(
          scale: 1 + math.sin(progress * math.pi) * 0.1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: TgiColors.black.withValues(alpha: opacity * 0.62),
                width: 18,
              ),
            ),
          ),
        ),
      );
    }

    if (preset == TimelineTransitionPreset.lightLeak) {
      return Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.8 + progress * 2.8, -0.3),
              end: Alignment(-0.4 + progress * 2.8, 0.4),
              colors: [
                TgiColors.transparent,
                const Color(0xFFFF6A2A).withValues(alpha: opacity * 0.72),
                const Color(0xFFFFF0B0).withValues(alpha: opacity * 0.88),
                TgiColors.transparent,
              ],
            ),
          ),
        ),
      );
    }

    if (preset == TimelineTransitionPreset.dissolve) {
      return Positioned.fill(
        child: ColoredBox(
          color: TgiColors.accentSoft.withValues(alpha: opacity * 0.12),
        ),
      );
    }

    final presetColor = preset == TimelineTransitionPreset.flash
        ? TgiColors.white.withValues(alpha: opacity)
        : color;
    return Positioned.fill(child: ColoredBox(color: presetColor));
  }
}

class _SyntheticTransitionPainter extends CustomPainter {
  const _SyntheticTransitionPainter({
    required this.preset,
    required this.progress,
    required this.opacity,
  });

  final TimelineTransitionPreset preset;
  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (preset == TimelineTransitionPreset.glitch) {
      final shift = math.sin(progress * math.pi * 8) * size.width * 0.035;
      final strips = <(double, double, Color)>[
        (0.12, 0.16, const Color(0xFFFF2A73)),
        (0.38, 0.12, const Color(0xFF2AC8FF)),
        (0.68, 0.18, const Color(0xFF55FF8A)),
      ];
      for (var index = 0; index < strips.length; index++) {
        final strip = strips[index];
        canvas.drawRect(
          Rect.fromLTWH(
            (index.isEven ? shift : -shift),
            size.height * strip.$1,
            size.width,
            size.height * strip.$2,
          ),
          Paint()..color = strip.$3.withValues(alpha: opacity * 0.34),
        );
      }
      return;
    }

    const blocks = 12;
    final blockWidth = size.width / blocks;
    final blockHeight = math.max(5.0, blockWidth * 0.7);
    for (var y = 0.0; y < size.height; y += blockHeight) {
      for (var x = 0.0; x < size.width; x += blockWidth) {
        final column = (x / blockWidth).floor();
        final row = (y / blockHeight).floor();
        if ((column + row).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, blockWidth + 0.5, blockHeight + 0.5),
            Paint()..color = TgiColors.black.withValues(alpha: opacity * 0.28),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SyntheticTransitionPainter oldDelegate) {
    return oldDelegate.preset != preset ||
        oldDelegate.progress != progress ||
        oldDelegate.opacity != opacity;
  }
}

class _TransitionPreviewVideo extends StatelessWidget {
  const _TransitionPreviewVideo({
    required this.entry,
    required this.session,
    super.key,
  });

  final TransitionPreviewEntry entry;
  final _TransitionPreviewSession? session;

  @override
  Widget build(BuildContext context) {
    final activeSession = session;
    if (activeSession == null || activeSession.openedPath != entry.filePath) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Opacity(
        opacity: _transitionPreviewOpacity(entry),
        child: Video(
          controller: activeSession.videoController,
          fit: BoxFit.cover,
          fill: TgiColors.transparent,
          filterQuality: FilterQuality.low,
          controls: NoVideoControls,
          wakelock: false,
        ),
      ),
    );
  }
}

class _TransitionPreviewSession {
  _TransitionPreviewSession(this.player)
    : videoController = VideoController(player);

  final Player player;
  final VideoController videoController;
  String? openedPath;
  bool disposed = false;

  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    try {
      await player.dispose();
    } catch (_) {
      // Disposal can race with an async open/seek command.
    }
  }
}

double _transitionPreviewOpacity(TransitionPreviewEntry entry) {
  final baseOpacity = switch (entry.blendMode) {
    TimelineTransitionBlendMode.normal => 1.0,
    TimelineTransitionBlendMode.screen => 0.78,
  };
  if (entry.duration <= Duration.zero) {
    return baseOpacity;
  }
  final progress =
      entry.sourcePosition.inMicroseconds / entry.duration.inMicroseconds;
  final eased = math.sin(progress.clamp(0.0, 1.0) * math.pi);
  final visibilityRamp = 0.55 + eased * 0.45;
  return (baseOpacity * visibilityRamp).clamp(0.0, 1.0).toDouble();
}

class _TimelineAudioPreviewMixer extends StatefulWidget {
  const _TimelineAudioPreviewMixer({
    required this.entries,
    required this.playing,
  });

  final List<AudioPreviewEntry> entries;
  final bool playing;

  @override
  State<_TimelineAudioPreviewMixer> createState() =>
      _TimelineAudioPreviewMixerState();
}

class _TimelineAudioPreviewMixerState
    extends State<_TimelineAudioPreviewMixer> {
  static const _resyncThreshold = Duration(milliseconds: 350);

  final Map<String, _AudioPreviewSession> _sessions = {};
  int _syncRevision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_syncSessions());
  }

  @override
  void didUpdateWidget(covariant _TimelineAudioPreviewMixer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries ||
        oldWidget.playing != widget.playing) {
      unawaited(_syncSessions());
    }
  }

  @override
  void dispose() {
    _syncRevision++;
    final sessions = List<_AudioPreviewSession>.from(_sessions.values);
    _sessions.clear();
    for (final session in sessions) {
      unawaited(session.dispose());
    }
    super.dispose();
  }

  Future<void> _syncSessions() async {
    final revision = ++_syncRevision;
    final entriesById = <String, AudioPreviewEntry>{
      for (final entry in widget.entries)
        if (entry.volume > 0) entry.clipId: entry,
    };

    for (final clipId in _sessions.keys.toList()) {
      if (entriesById.containsKey(clipId)) {
        continue;
      }
      final removed = _sessions.remove(clipId);
      if (removed != null) {
        unawaited(removed.dispose());
      }
    }

    for (final entry in entriesById.values) {
      if (!mounted || revision != _syncRevision) {
        return;
      }
      final session = _sessions.putIfAbsent(
        entry.clipId,
        () => _AudioPreviewSession(Player()),
      );
      await _syncSession(session, entry, revision);
    }
  }

  Future<void> _syncSession(
    _AudioPreviewSession session,
    AudioPreviewEntry entry,
    int revision,
  ) async {
    if (session.disposed) {
      return;
    }
    try {
      final path = entry.item.filePath;
      if (!await File(path).exists()) {
        return;
      }
      if (!mounted || revision != _syncRevision || session.disposed) {
        return;
      }

      if (session.openedPath != path) {
        await session.player.open(
          Media(Uri.file(path).toString()),
          play: false,
        );
        session.openedPath = path;
      }
      if (!mounted || revision != _syncRevision || session.disposed) {
        return;
      }

      await session.player.setVolume(entry.volume.clamp(0.0, 2.0) * 100.0);
      await session.player.setRate(_normalizedAudioPlaybackSpeed(entry));

      final current = session.player.state.position;
      final drift = (current - entry.sourcePosition).inMilliseconds.abs();
      if (!widget.playing || drift > _resyncThreshold.inMilliseconds) {
        await session.player.seek(entry.sourcePosition);
      }
      if (!mounted || revision != _syncRevision || session.disposed) {
        return;
      }

      if (widget.playing) {
        await session.player.play();
      } else {
        await session.player.pause();
      }
    } catch (_) {
      // Audio preview must not break editing if a cached file disappears or
      // media_kit rejects a standalone clip. Export still uses timeline data.
    }
  }

  double _normalizedAudioPlaybackSpeed(AudioPreviewEntry entry) {
    final speed = entry.playbackSpeed;
    if (speed.isNaN || speed.isInfinite || speed <= 0) {
      return 1;
    }
    return speed.clamp(0.25, 4.0).toDouble();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _AudioPreviewSession {
  _AudioPreviewSession(this.player);

  final Player player;
  String? openedPath;
  bool disposed = false;

  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    try {
      await player.dispose();
    } catch (_) {
      // Player disposal can race with an async open/seek command.
    }
  }
}

class _PreloadedPreviewSession {
  _PreloadedPreviewSession({
    required this.key,
    required this.item,
    required this.sourcePosition,
    required this.player,
    required this.videoController,
  });

  final String key;
  final MediaItem item;
  final Duration sourcePosition;
  final Player player;
  final VideoController videoController;
  bool ready = false;
  bool adopted = false;
  bool disposed = false;

  Future<void> dispose(String reason) async {
    if (disposed || adopted) {
      return;
    }
    disposed = true;
    try {
      await player.dispose();
    } catch (_) {
      // Player disposal can race with an async preload open/seek command.
    }
  }
}

class _PreviewPlayerSession {
  const _PreviewPlayerSession({
    required this.player,
    required this.videoController,
    required this.errorSubscription,
    required this.positionSubscription,
    required this.playingSubscription,
    required this.completedSubscription,
    required this.widthSubscription,
    required this.heightSubscription,
  });

  final Player player;
  final VideoController videoController;
  final StreamSubscription<String> errorSubscription;
  final StreamSubscription<Duration> positionSubscription;
  final StreamSubscription<bool> playingSubscription;
  final StreamSubscription<bool> completedSubscription;
  final StreamSubscription<int?> widthSubscription;
  final StreamSubscription<int?> heightSubscription;
}
