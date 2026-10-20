part of 'video_preview_panel.dart';

class _PreviewPerformanceNotice extends StatelessWidget {
  const _PreviewPerformanceNotice({required this.rawPreviewFallback});

  final bool rawPreviewFallback;

  @override
  Widget build(BuildContext context) {
    final message = rawPreviewFallback
        ? 'Modo seguro de preview ativo; desempenho reduzido nesta maquina.'
        : 'Preview em resolucao reduzida para preservar FPS.';
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TgiColors.black.withValues(alpha: 0.68),
          border: Border.all(color: TgiColors.border),
          borderRadius: BorderRadius.circular(TgiRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.item,
    required this.player,
    required this.enabled,
    required this.timelinePosition,
    required this.timelineDuration,
    required this.timelinePlaybackActive,
    required this.onTimelineSeek,
    required this.onTimelinePlaybackChanged,
    required this.onFrameRefreshRequested,
    required this.leadingControl,
    required this.trailingControl,
  });

  final MediaItem? item;
  final Player? player;
  final bool enabled;
  final Duration timelinePosition;
  final Duration? timelineDuration;
  final bool timelinePlaybackActive;
  final ValueChanged<Duration>? onTimelineSeek;
  final ValueChanged<bool>? onTimelinePlaybackChanged;
  final void Function(String reason) onFrameRefreshRequested;
  final Widget? leadingControl;
  final Widget? trailingControl;

  @override
  Widget build(BuildContext context) {
    final currentPlayer = player;
    final timelineDuration = this.timelineDuration;
    final useTimelineControls =
        onTimelineSeek != null &&
        timelineDuration != null &&
        timelineDuration > Duration.zero;
    if (currentPlayer == null) {
      final duration = useTimelineControls
          ? timelineDuration
          : item?.duration ?? Duration.zero;
      return _TransportScaffold(
        position: useTimelineControls
            ? _clampPosition(timelinePosition, duration)
            : Duration.zero,
        duration: duration,
        playing: timelinePlaybackActive,
        enabled: useTimelineControls,
        onPlayPause: useTimelineControls && onTimelinePlaybackChanged != null
            ? () => onTimelinePlaybackChanged!(!timelinePlaybackActive)
            : null,
        onBackward: useTimelineControls
            ? () => _runPlayerCommand(
                'seek backward',
                () => _seekTimelineBy(
                  _clampPosition(timelinePosition, duration),
                  duration,
                  const Duration(seconds: -5),
                ),
              )
            : null,
        onForward: useTimelineControls
            ? () => _runPlayerCommand(
                'seek forward',
                () => _seekTimelineBy(
                  _clampPosition(timelinePosition, duration),
                  duration,
                  const Duration(seconds: 5),
                ),
              )
            : null,
        onSeek: useTimelineControls ? _seekTimeline : null,
        leadingControl: leadingControl,
        trailingControl: trailingControl,
      );
    }

    return StreamBuilder<bool>(
      stream: currentPlayer.stream.playing,
      initialData: currentPlayer.state.playing,
      builder: (context, playingSnapshot) {
        return StreamBuilder<Duration>(
          stream: currentPlayer.stream.duration,
          initialData: _initialDuration(currentPlayer),
          builder: (context, durationSnapshot) {
            return StreamBuilder<Duration>(
              stream: currentPlayer.stream.position,
              initialData: currentPlayer.state.position,
              builder: (context, positionSnapshot) {
                final duration = _effectiveDuration(durationSnapshot.data);
                final position = _clampPosition(
                  positionSnapshot.data ?? Duration.zero,
                  duration,
                );
                final displayDuration = useTimelineControls
                    ? timelineDuration
                    : duration;
                final displayPosition = useTimelineControls
                    ? _clampPosition(timelinePosition, displayDuration)
                    : position;
                final playing = playingSnapshot.data ?? false;

                return _TransportScaffold(
                  position: displayPosition,
                  duration: displayDuration,
                  playing: playing,
                  enabled: enabled,
                  onPlayPause: enabled
                      ? () => _runPlayerCommand(
                          'play/pause',
                          () {
                            _debugTransport(
                              'playOrPause() call source=transport '
                              'beforePlaying=${currentPlayer.state.playing} '
                              'sourcePos=${_durationMs(currentPlayer.state.position)} '
                              'displayPos=${_durationMs(displayPosition)} '
                              'displayDuration=${_durationMs(displayDuration)} '
                              'timelineControls=$useTimelineControls',
                            );
                            return currentPlayer.playOrPause();
                          },
                          onDone: () {
                            _debugTransport(
                              'playOrPause() done source=transport '
                              'afterPlaying=${currentPlayer.state.playing} '
                              'sourcePos=${_durationMs(currentPlayer.state.position)}',
                            );
                            onFrameRefreshRequested('play/pause');
                          },
                        )
                      : null,
                  onBackward: enabled
                      ? () => _runPlayerCommand(
                          'seek backward',
                          () => useTimelineControls
                              ? _seekTimelineBy(
                                  displayPosition,
                                  displayDuration,
                                  const Duration(seconds: -5),
                                )
                              : _seekBy(
                                  currentPlayer,
                                  position,
                                  duration,
                                  const Duration(seconds: -5),
                                ),
                          onDone: () =>
                              onFrameRefreshRequested('seek backward'),
                        )
                      : null,
                  onForward: enabled
                      ? () => _runPlayerCommand(
                          'seek forward',
                          () => useTimelineControls
                              ? _seekTimelineBy(
                                  displayPosition,
                                  displayDuration,
                                  const Duration(seconds: 5),
                                )
                              : _seekBy(
                                  currentPlayer,
                                  position,
                                  duration,
                                  const Duration(seconds: 5),
                                ),
                          onDone: () => onFrameRefreshRequested('seek forward'),
                        )
                      : null,
                  onSeek: enabled && displayDuration > Duration.zero
                      ? (value) => _runPlayerCommand(
                          'seek slider',
                          () => useTimelineControls
                              ? _seekTimeline(value)
                              : currentPlayer.seek(value),
                          onDone: () => onFrameRefreshRequested('seek slider'),
                        )
                      : null,
                  leadingControl: leadingControl,
                  trailingControl: trailingControl,
                );
              },
            );
          },
        );
      },
    );
  }

  Duration _initialDuration(Player player) {
    final duration = player.state.duration;
    if (duration > Duration.zero) {
      return duration;
    }
    return item?.duration ?? Duration.zero;
  }

  Duration _effectiveDuration(Duration? playerDuration) {
    final duration = playerDuration ?? Duration.zero;
    if (duration > Duration.zero) {
      return duration;
    }
    return item?.duration ?? Duration.zero;
  }

  Duration _clampPosition(Duration position, Duration duration) {
    if (position < Duration.zero) {
      return Duration.zero;
    }
    if (duration > Duration.zero && position > duration) {
      return duration;
    }
    return position;
  }

  Future<void> _seekBy(
    Player player,
    Duration position,
    Duration duration,
    Duration offset,
  ) {
    final next = _clampPosition(position + offset, duration);
    return player.seek(next);
  }

  Future<void> _seekTimeline(Duration position) {
    return Future<void>.sync(() {
      onTimelineSeek?.call(position);
    });
  }

  Future<void> _seekTimelineBy(
    Duration position,
    Duration duration,
    Duration offset,
  ) {
    final next = _clampPosition(position + offset, duration);
    return _seekTimeline(next);
  }

  void _debugTransport(String message) {
    if (!_enablePreviewTraceLogging) {
      return;
    }
    EditorDebugLog.write('transport', message);
  }

  String _durationMs(Duration duration) => '${duration.inMilliseconds}ms';
}

void _runPlayerCommand(
  String label,
  Future<void> Function() command, {
  VoidCallback? onDone,
}) {
  unawaited(() async {
    try {
      await command();
      onDone?.call();
    } catch (_) {
      // Player commands can race with media/session disposal.
    }
  }());
}

class _TransportScaffold extends StatelessWidget {
  const _TransportScaffold({
    required this.position,
    required this.duration,
    required this.playing,
    required this.enabled,
    required this.onPlayPause,
    required this.onBackward,
    required this.onForward,
    required this.onSeek,
    required this.leadingControl,
    required this.trailingControl,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool enabled;
  final VoidCallback? onPlayPause;
  final VoidCallback? onBackward;
  final VoidCallback? onForward;
  final ValueChanged<Duration>? onSeek;
  final Widget? leadingControl;
  final Widget? trailingControl;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final sliderMax = totalMs <= 0 ? 1.0 : totalMs.toDouble();
    final sliderValue = totalMs <= 0
        ? 0.0
        : position.inMilliseconds.clamp(0, totalMs).toDouble();

    return Padding(
      key: const ValueKey('video_preview_transport_controls'),
      padding: const EdgeInsets.fromLTRB(TgiSpacing.sm, 4, TgiSpacing.sm, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                _TimecodePill(value: formatDuration(position)),
                const SizedBox(width: TgiSpacing.sm),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: TgiColors.accentSoft,
                      inactiveTrackColor: TgiColors.borderStrong,
                      thumbColor: TgiColors.accent,
                      overlayColor: TgiColors.glowSoft,
                      trackHeight: 3,
                      trackShape: const TgiSliderTrackShape(),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                      tickMarkShape: SliderTickMarkShape.noTickMark,
                    ),
                    child: Slider(
                      value: sliderValue,
                      min: 0,
                      max: sliderMax,
                      onChanged: enabled && onSeek != null
                          ? (value) =>
                                onSeek!(Duration(milliseconds: value.round()))
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: TgiSpacing.sm),
                _TimecodePill(
                  value: formatDuration(duration),
                  alignRight: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingControl != null) ...[
                  leadingControl!,
                  const SizedBox(width: TgiSpacing.sm),
                ],
                DecoratedBox(
                  decoration: TgiDecorations.controlCluster(),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TransportButton(
                          tooltip: 'Retroceder 5 segundos',
                          icon: Icons.replay_5,
                          onPressed: onBackward,
                        ),
                        const SizedBox(width: 4),
                        _TransportButton(
                          tooltip: playing ? 'Pausar' : 'Reproduzir',
                          icon: playing ? Icons.pause : Icons.play_arrow,
                          onPressed: onPlayPause,
                          prominent: true,
                        ),
                        const SizedBox(width: 4),
                        _TransportButton(
                          tooltip: 'Avançar 5 segundos',
                          icon: Icons.forward_5,
                          onPressed: onForward,
                        ),
                      ],
                    ),
                  ),
                ),
                if (trailingControl != null) ...[
                  const SizedBox(width: TgiSpacing.sm),
                  trailingControl!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimecodePill extends StatelessWidget {
  const _TimecodePill({required this.value, this.alignRight = false});

  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TgiColors.background.withValues(alpha: 0.52),
          border: Border.all(color: TgiColors.borderSubtle),
          borderRadius: BorderRadius.circular(TgiRadii.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            value,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: TgiColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.prominent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox.square(
      dimension: prominent ? 32 : 28,
      child: Tooltip(
        message: tooltip,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: TgiColors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(TgiRadii.pill),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: prominent
                      ? TgiColors.accent
                      : TgiColors.surfaceRaised.withValues(alpha: 0.74),
                  border: Border.all(
                    color: prominent
                        ? TgiColors.accentMuted
                        : TgiColors.borderSubtle,
                  ),
                  borderRadius: BorderRadius.circular(TgiRadii.pill),
                ),
                child: Center(
                  child: prominent
                      ? Icon(icon, size: 20, color: TgiColors.backgroundDeep)
                      : Icon(
                          icon,
                          size: 17,
                          color: enabled
                              ? TgiColors.textPrimary
                              : TgiColors.textSecondary,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 240 || constraints.maxWidth < 300;
        return Center(
          child: Padding(
            padding: EdgeInsets.all(compact ? TgiSpacing.sm : TgiSpacing.xxl),
            child: compact
                ? Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: TgiSpacing.sm,
                    runSpacing: TgiSpacing.xs,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (onAction != null && actionLabel != null)
                        TextButton.icon(
                          key: const Key('preview_add_media_button'),
                          onPressed: onAction,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(actionLabel!),
                        ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 34, color: TgiColors.textSecondary),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (onAction != null && actionLabel != null) ...[
                        const SizedBox(height: TgiSpacing.lg),
                        FilledButton.icon(
                          key: const Key('preview_add_media_button'),
                          onPressed: onAction,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(actionLabel!),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}
