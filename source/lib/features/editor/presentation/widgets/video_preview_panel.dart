import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../app/theme/decorations.dart';
import '../../../../domain/models/clip.dart';
import '../../../../domain/models/media_item.dart';
import '../../../../domain/models/timeline_transition.dart';
import '../../../../services/editor_debug_log.dart';
import '../duration_formatter.dart';
import 'preview_entries.dart';
import 'chroma_key_preview.dart';
import '../../../../domain/text_style_profile.dart';
import 'styled_caption_text.dart';

part 'video_preview_sessions.dart';
part 'video_preview_stage.dart';
part 'video_preview_overlays.dart';
part 'video_preview_transport.dart';

// Preview uses media_kit_video's native texture as the primary path. The
// previous BGRA screenshot path is kept only as a safety fallback because raw
// 4K frame capture moves tens of MB per frame and makes playback look like low
// FPS. Final export still uses FFmpeg and original media quality.
const _maxPreviewOutputWidth = 1280;
const _maxPreviewOutputHeight = 720;
const _previewFrameInterval720p = Duration(milliseconds: 67);
const _previewPerformanceWarningThreshold = Duration(milliseconds: 250);
const _timelineClipEndAdvanceWindow = Duration(milliseconds: 700);
const _completedSourceResetThreshold = Duration(milliseconds: 250);
const _requestedSourceSeekTolerance = Duration(milliseconds: 350);
const _videoOverlaySeekResyncThreshold = Duration(milliseconds: 900);
const _requestedSourceSeekTimeout = Duration(seconds: 2);
const _videoPreloadBoundaryTolerance = Duration(milliseconds: 120);
const _videoPreloadLookAhead = Duration(milliseconds: 1800);
const _videoPreloadAdoptionTolerance = Duration(milliseconds: 900);
const _enablePreviewTraceLogging = false;
const _minImageOverlayScale = 0.35;
const _maxImageOverlayScale = 8.0;

typedef PreviewMaskGeometryChanged =
    void Function({double? x, double? y, double? width, double? height});

class VideoPreviewMask {
  const VideoPreviewMask({
    required this.shape,
    required this.effect,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.feather,
    required this.intensity,
    required this.inverted,
  });

  final VideoMaskShape shape;
  final VideoMaskEffect effect;
  final double x;
  final double y;
  final double width;
  final double height;
  final double feather;
  final double intensity;
  final bool inverted;
}

class VideoPreviewPanel extends StatefulWidget {
  const VideoPreviewPanel({
    required this.item,
    this.outputAspectRatio,
    this.cropMainVideoToFill = false,
    this.videoOpacity = 1,
    this.requestedPosition = Duration.zero,
    this.timelinePosition = Duration.zero,
    this.imageOverlayItem,
    this.imageOverlayClipId,
    this.imageOverlayX = 1,
    this.imageOverlayY = 0,
    this.imageOverlayScale = 1,
    this.videoOverlayEntries = const [],
    this.visualLayerOrder = const {},
    this.baseVideoClipId,
    this.imageOverlayEntries = const [],
    this.textOverlayEntries = const [],
    this.transitionPreviewEntries = const [],
    this.audioPreviewEntries = const [],
    this.videoPreloadEntry,
    this.onImageOverlayMoved,
    this.onImageOverlayResized,
    this.onImageOverlayTap,
    this.onVideoOverlayMoved,
    this.onVideoOverlayResized,
    this.onVideoOverlayTap,
    this.onTextOverlayMoved,
    this.onTextOverlayTap,
    this.onTextOverlayEdit,
    this.onTextOverlayInteractionStart,
    this.onTextOverlayInteractionEnd,
    this.timelineDuration,
    this.onPositionChanged,
    this.onTimelineSeek,
    this.timelinePlaybackActive = false,
    this.onTimelinePlaybackChanged,
    this.continuePlaybackOnItemChange = false,
    this.audioVolume = 1,
    this.playbackSpeed = 1,
    this.visualAdjustments = const VideoPreviewVisualAdjustments(),
    this.transportLeadingControl,
    this.transportTrailingControl,
    this.kenBurnsToolActive = false,
    this.kenBurnsPickStart = true,
    this.kenBurnsStartX,
    this.kenBurnsStartY,
    this.kenBurnsEndX,
    this.kenBurnsEndY,
    this.onKenBurnsPointSelected,
    this.transformToolActive = false,
    this.transformCropMode = false,
    this.onTransformPositionChanged,
    this.onTransformScaleChanged,
    this.onTransformCropChanged,
    this.onTransformInteractionStart,
    this.onTransformInteractionEnd,
    this.chromaColorPickerActive = false,
    this.chromaTransparencyPreview = true,
    this.onChromaColorPicked,
    this.onChromaColorPickError,
    this.whiteBalanceColorPickerActive = false,
    this.onWhiteBalanceColorPicked,
    this.onWhiteBalancePickError,
    this.colorAnalysisRequest = 0,
    this.onColorAnalysis,
    this.onColorAnalysisError,
    this.onImportRequested,
    this.mask,
    this.maskToolActive = false,
    this.onMaskGeometryChanged,
    super.key,
  });

  final MediaItem? item;
  final Map<String, int> visualLayerOrder;
  final String? baseVideoClipId;
  final double? outputAspectRatio;
  final bool cropMainVideoToFill;
  final double videoOpacity;
  final Duration requestedPosition;
  final Duration timelinePosition;
  final MediaItem? imageOverlayItem;
  final String? imageOverlayClipId;
  final double imageOverlayX;
  final double imageOverlayY;
  final double imageOverlayScale;
  final List<VideoOverlayEntry> videoOverlayEntries;
  final List<ImageOverlayEntry> imageOverlayEntries;
  final List<TextOverlayEntry> textOverlayEntries;
  final List<TransitionPreviewEntry> transitionPreviewEntries;
  final List<AudioPreviewEntry> audioPreviewEntries;
  final VideoPreviewPreloadEntry? videoPreloadEntry;
  final void Function(String clipId, double overlayX, double overlayY)?
  onImageOverlayMoved;
  final void Function(String clipId, double overlayScale)?
  onImageOverlayResized;
  final void Function(String clipId)? onImageOverlayTap;
  final void Function(String clipId, double overlayX, double overlayY)?
  onVideoOverlayMoved;
  final void Function(String clipId, double overlayScale)?
  onVideoOverlayResized;
  final void Function(String timelineGroupId)? onVideoOverlayTap;
  final void Function(String clipId, double overlayX, double overlayY)?
  onTextOverlayMoved;
  final void Function(String timelineGroupId)? onTextOverlayTap;
  final void Function(String clipId)? onTextOverlayEdit;
  final VoidCallback? onTextOverlayInteractionStart;
  final VoidCallback? onTextOverlayInteractionEnd;
  final Duration? timelineDuration;
  final void Function(String mediaItemId, Duration position)? onPositionChanged;
  final ValueChanged<Duration>? onTimelineSeek;
  final bool timelinePlaybackActive;
  final ValueChanged<bool>? onTimelinePlaybackChanged;
  final bool continuePlaybackOnItemChange;
  final double audioVolume;
  final double playbackSpeed;
  final VideoPreviewVisualAdjustments visualAdjustments;
  final Widget? transportLeadingControl;
  final Widget? transportTrailingControl;
  final bool kenBurnsToolActive;
  final bool kenBurnsPickStart;
  final double? kenBurnsStartX;
  final double? kenBurnsStartY;
  final double? kenBurnsEndX;
  final double? kenBurnsEndY;
  final void Function(double x, double y)? onKenBurnsPointSelected;
  final bool transformToolActive;
  final bool transformCropMode;
  final void Function(double x, double y)? onTransformPositionChanged;
  final ValueChanged<double>? onTransformScaleChanged;
  final void Function({
    double? left,
    double? top,
    double? right,
    double? bottom,
  })?
  onTransformCropChanged;
  final VoidCallback? onTransformInteractionStart;
  final VoidCallback? onTransformInteractionEnd;
  final bool chromaColorPickerActive;
  final bool chromaTransparencyPreview;
  final ValueChanged<int>? onChromaColorPicked;
  final ValueChanged<String>? onChromaColorPickError;
  final bool whiteBalanceColorPickerActive;
  final ValueChanged<int>? onWhiteBalanceColorPicked;
  final ValueChanged<String>? onWhiteBalancePickError;
  final int colorAnalysisRequest;
  final ValueChanged<VideoColorAnalysis>? onColorAnalysis;
  final ValueChanged<String>? onColorAnalysisError;
  final VoidCallback? onImportRequested;
  final VideoPreviewMask? mask;
  final bool maskToolActive;
  final PreviewMaskGeometryChanged? onMaskGeometryChanged;

  @override
  State<VideoPreviewPanel> createState() => _VideoPreviewPanelState();
}

class _VideoPreviewPanelState extends State<VideoPreviewPanel> {
  _PreviewPlayerSession? _session;
  _PreloadedPreviewSession? _preloadSession;
  bool _loading = false;
  bool _frameCaptureInProgress = false;
  bool _reverseSeekInProgress = false;
  bool _reverseSeekPending = false;
  ui.Image? _previewImage;
  int _previewFrameSerial = 0;
  Timer? _previewFrameTimer;
  DateTime? _lastPreviewFrameCapturedAt;
  bool _rawPreviewFallback = false;
  Duration _lastFrameCaptureCost = const Duration(milliseconds: 50);
  bool _lastKnownPlaying = false;
  bool _resumePlaybackAcrossTimelineClip = false;
  bool _timelineClipAdvanceRequested = false;
  bool _chromaColorSampling = false;
  bool _whiteBalanceColorSampling = false;
  bool _colorAnalysisInProgress = false;
  bool _initialTimelineSeekPending = false;
  Duration? _pendingRequestedSourcePosition;
  DateTime? _pendingRequestedSourceSeekStartedAt;
  Duration _lastObservedSourcePosition = Duration.zero;
  int _lastPositionDebugBucket = -1;
  Duration _previewFrameInterval = _previewFrameInterval720p;
  _PreviewOutputSize _previewOutputSize = const _PreviewOutputSize(
    width: _maxPreviewOutputWidth,
    height: _maxPreviewOutputHeight,
    downscaled: true,
  );
  String? _errorMessage;
  String? _loadedItemId;
  int _loadRevision = 0;
  int _preloadRevision = 0;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      unawaited(_loadItem(widget.item));
    }
    unawaited(_syncPreloadTarget());
  }

  @override
  void didUpdateWidget(covariant VideoPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.colorAnalysisRequest != widget.colorAnalysisRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_analyzeCurrentColorFrame());
      });
    }
    if (oldWidget.item?.id != widget.item?.id ||
        oldWidget.item?.filePath != widget.item?.filePath) {
      final playWhenReady =
          widget.continuePlaybackOnItemChange &&
          (_lastKnownPlaying ||
              _resumePlaybackAcrossTimelineClip ||
              widget.timelinePlaybackActive);
      if (widget.item == null) {
        widget.onTimelinePlaybackChanged?.call(playWhenReady);
      }
      _debugPlayback(
        'didUpdateWidget item changed old=${_itemLabel(oldWidget.item)} '
        'new=${_itemLabel(widget.item)} playWhenReady=$playWhenReady '
        'lastKnownPlaying=$_lastKnownPlaying '
        'resumeFlag=$_resumePlaybackAcrossTimelineClip',
      );
      _resumePlaybackAcrossTimelineClip = false;
      _timelineClipAdvanceRequested = false;
      _lastObservedSourcePosition = widget.requestedPosition;
      _lastPositionDebugBucket = -1;
      unawaited(
        _loadItem(widget.item, playWhenReady: playWhenReady).then((_) {
          if (mounted) {
            unawaited(_syncPreloadTarget());
          }
        }),
      );
      return;
    }

    if (oldWidget.requestedPosition != widget.requestedPosition) {
      final playWhenReady =
          widget.continuePlaybackOnItemChange &&
          !widget.visualAdjustments.reverseVideo &&
          (_lastKnownPlaying ||
              _resumePlaybackAcrossTimelineClip ||
              widget.timelinePlaybackActive);
      final playbackEcho =
          !widget.visualAdjustments.reverseVideo &&
          _isPlaybackEchoPosition(widget.requestedPosition);
      _debugPlayback(
        'didUpdateWidget requested position changed '
        'oldTimeline=${_durationMs(oldWidget.timelinePosition)} '
        'newTimeline=${_durationMs(widget.timelinePosition)} '
        'oldRequest=${_durationMs(oldWidget.requestedPosition)} '
        'newRequest=${_durationMs(widget.requestedPosition)} '
        'playWhenReady=$playWhenReady lastKnownPlaying=$_lastKnownPlaying '
        'resumeFlag=$_resumePlaybackAcrossTimelineClip '
        'playbackEcho=$playbackEcho',
      );
      _lastPositionDebugBucket = -1;
      if (playbackEcho) {
        _clearPendingRequestedSourceSeek('didUpdateWidget playback echo');
        unawaited(_syncPreloadTarget());
        return;
      }

      _resumePlaybackAcrossTimelineClip = false;
      _timelineClipAdvanceRequested = false;
      _lastObservedSourcePosition = widget.requestedPosition;
      if (_session != null) {
        _markRequestedSourceSeekPending(widget.requestedPosition);
      }
      unawaited(
        _seekToRequestedPosition(
          'requested source position',
          playWhenReady: playWhenReady,
        ),
      );
      unawaited(_syncPreloadTarget());
      return;
    }

    if (oldWidget.timelinePosition != widget.timelinePosition) {
      _debugPlayback(
        'didUpdateWidget timeline position changed without source seek '
        'oldTimeline=${_durationMs(oldWidget.timelinePosition)} '
        'newTimeline=${_durationMs(widget.timelinePosition)} '
        'request=${_durationMs(widget.requestedPosition)} '
        'lastKnownPlaying=$_lastKnownPlaying '
        'resumeFlag=$_resumePlaybackAcrossTimelineClip',
      );
      unawaited(_syncPreloadTarget());
    }

    if (oldWidget.timelinePlaybackActive != widget.timelinePlaybackActive) {
      _syncPlayerPlaybackWithTimeline(widget.timelinePlaybackActive);
      unawaited(_syncPreloadTarget());
    }

    if (oldWidget.visualAdjustments.reverseVideo !=
        widget.visualAdjustments.reverseVideo) {
      _lastObservedSourcePosition = widget.requestedPosition;
      if (_session != null) {
        _markRequestedSourceSeekPending(widget.requestedPosition);
      }
      unawaited(
        _seekToRequestedPosition(
          'reverse preview changed',
          playWhenReady:
              widget.timelinePlaybackActive &&
              !widget.visualAdjustments.reverseVideo,
        ),
      );
      _syncPlayerPlaybackWithTimeline(widget.timelinePlaybackActive);
    }

    if (oldWidget.audioVolume != widget.audioVolume) {
      final session = _session;
      if (session != null && mounted) {
        unawaited(
          session.player.setVolume(widget.audioVolume.clamp(0.0, 2.0) * 100.0),
        );
      }
    }

    if (oldWidget.playbackSpeed != widget.playbackSpeed) {
      final session = _session;
      if (session != null && mounted) {
        unawaited(session.player.setRate(_normalizedPlaybackSpeed()));
      }
    }

    if (_preloadEntryChanged(
      oldWidget.videoPreloadEntry,
      widget.videoPreloadEntry,
    )) {
      unawaited(_syncPreloadTarget());
    }
  }

  @override
  void dispose() {
    _loadRevision++;
    _preloadRevision++;
    _stopPreviewFrameTimer();
    _disposePreviewImage();
    final preloadSession = _preloadSession;
    _preloadSession = null;
    if (preloadSession != null) {
      unawaited(preloadSession.dispose('widget disposed'));
    }
    final session = _session;
    _session = null;
    if (session != null) {
      unawaited(_disposeSession(session, _loadRevision, 'widget disposed'));
    }
    super.dispose();
  }

  void _syncPlayerPlaybackWithTimeline(bool play) {
    final session = _session;
    if (session == null || !mounted) {
      return;
    }
    if (widget.visualAdjustments.reverseVideo) {
      if (session.player.state.playing) {
        _runPlayerCommand(
          'reverse preview pause',
          session.player.pause,
          onDone: () {
            if (mounted) {
              setState(() {});
            }
          },
        );
      }
      return;
    }
    if (session.player.state.playing == play) {
      return;
    }

    _runPlayerCommand(
      play ? 'timeline play' : 'timeline pause',
      () => play ? session.player.play() : session.player.pause(),
      onDone: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  _PreviewPlayerSession _createPreviewSession({
    required Player player,
    required VideoController videoController,
    required int revision,
  }) {
    _PreviewPlayerSession? activeSession;
    final errorSubscription = player.stream.error.listen((message) {
      _handlePlayerError(revision, message);
    });
    final positionSubscription = player.stream.position.listen((position) {
      if (!mounted || revision != _loadRevision) {
        return;
      }
      final currentItem = widget.item;
      _debugPlayback(
        'raw position event rev=$revision item=${_itemLabel(currentItem)} '
        'pos=${_durationMs(position)} requested=${_durationMs(widget.requestedPosition)} '
        'timeline=${_durationMs(widget.timelinePosition)} playing=${player.state.playing} '
        'initialSeekPending=$_initialTimelineSeekPending '
        'pendingSeek=${_pendingRequestedSourceSeekLabel()}',
      );
      if (_initialTimelineSeekPending) {
        _debugPlayback(
          'position event ignored while initial timeline seek pending '
          'rev=$revision item=${_itemLabel(currentItem)} '
          'pos=${_durationMs(position)} '
          'requested=${_durationMs(widget.requestedPosition)} '
          'timeline=${_durationMs(widget.timelinePosition)}',
        );
        _lastObservedSourcePosition = position;
        return;
      }
      if (_shouldIgnorePositionWhileRequestedSourceSeekPending(position)) {
        return;
      }
      if (widget.visualAdjustments.reverseVideo) {
        _lastObservedSourcePosition = widget.requestedPosition;
        if (player.state.playing) {
          unawaited(player.pause());
        }
        return;
      }
      if (widget.continuePlaybackOnItemChange &&
          currentItem != null &&
          currentItem.duration > Duration.zero) {
        final previousPosition = _lastObservedSourcePosition;
        final nearEnd =
            currentItem.duration - position <= _timelineClipEndAdvanceWindow;
        final resetAfterEnd =
            (previousPosition >=
                    currentItem.duration - _timelineClipEndAdvanceWindow ||
                _resumePlaybackAcrossTimelineClip) &&
            position <= _completedSourceResetThreshold;

        final positionBucket = position.inMilliseconds ~/ 250;
        final jumpedBack =
            position < previousPosition - const Duration(milliseconds: 500);
        if (positionBucket != _lastPositionDebugBucket ||
            nearEnd ||
            resetAfterEnd ||
            jumpedBack ||
            _timelineClipAdvanceRequested) {
          _lastPositionDebugBucket = positionBucket;
          _debugPlayback(
            'position event rev=$revision item=${_itemLabel(currentItem)} '
            'pos=${_durationMs(position)} prev=${_durationMs(previousPosition)} '
            'duration=${_durationMs(currentItem.duration)} '
            'playing=${player.state.playing} nearEnd=$nearEnd '
            'resetAfterEnd=$resetAfterEnd jumpedBack=$jumpedBack '
            'advanceRequested=$_timelineClipAdvanceRequested '
            'resumeFlag=$_resumePlaybackAcrossTimelineClip',
          );
        }

        _lastObservedSourcePosition = position;

        if (_timelineClipAdvanceRequested) {
          _debugPlayback(
            'position event ignored because timeline advance already requested '
            'pos=${_durationMs(position)} item=${_itemLabel(currentItem)}',
          );
          return;
        }
        if (resetAfterEnd) {
          _advanceTimelineFromFinishedSource(
            currentItem,
            'source reset after end',
          );
          return;
        }
        if (player.state.playing && nearEnd) {
          _resumePlaybackAcrossTimelineClip = true;
        }
      } else {
        _lastObservedSourcePosition = position;
      }
      if (currentItem != null) {
        widget.onPositionChanged?.call(currentItem.id, position);
      }
    });
    final playingSubscription = player.stream.playing.listen((playing) {
      if (!mounted || revision != _loadRevision) {
        return;
      }
      if (widget.visualAdjustments.reverseVideo) {
        _lastKnownPlaying = false;
        return;
      }
      _debugPlayback(
        'playing event rev=$revision playing=$playing '
        'advanceRequested=$_timelineClipAdvanceRequested '
        'initialSeekPending=$_initialTimelineSeekPending '
        'lastKnownPlaying=$_lastKnownPlaying',
      );
      if ((_timelineClipAdvanceRequested || _initialTimelineSeekPending) &&
          !playing) {
        _debugPlayback(
          'playing=false ignored while waiting for timeline continuation seek',
        );
        return;
      }
      if (!playing && _shouldAdvanceAfterNaturalPlayerStop(player)) {
        final currentItem = widget.item!;
        _debugPlayback(
          'playing=false converted to timeline continuation at source end',
        );
        _advanceTimelineFromFinishedSource(
          currentItem,
          'player stopped at source end',
        );
        return;
      }
      _lastKnownPlaying = playing;
      widget.onTimelinePlaybackChanged?.call(playing);
    });
    final completedSubscription = player.stream.completed.listen((completed) {
      final currentItem = widget.item;
      _debugPlayback(
        'completed event rev=$revision completed=$completed '
        'item=${_itemLabel(currentItem)} mounted=$mounted '
        'currentRevision=$_loadRevision '
        'playerPos=${_durationMs(player.state.position)} '
        'playerDuration=${_durationMs(player.state.duration)} '
        'playing=${player.state.playing} '
        'advanceRequested=$_timelineClipAdvanceRequested '
        'resumeFlag=$_resumePlaybackAcrossTimelineClip',
      );
      if (!mounted || revision != _loadRevision || !completed) {
        return;
      }
      if (widget.visualAdjustments.reverseVideo) {
        _debugPlayback('completed event ignored for reverse preview');
        return;
      }
      if (!widget.continuePlaybackOnItemChange ||
          currentItem == null ||
          currentItem.duration <= Duration.zero) {
        _debugPlayback(
          'completed event ignored: timeline continuation disabled or no item',
        );
        return;
      }
      _advanceTimelineFromFinishedSource(currentItem, 'completed event');
    });
    void enforcePreviewOutputSize(String reason) {
      final session = activeSession;
      if (session == null) {
        return;
      }
      unawaited(_enforcePreviewOutputSize(session, revision, reason));
    }

    final widthSubscription = player.stream.width.listen(
      (_) => enforcePreviewOutputSize('source width changed'),
    );
    final heightSubscription = player.stream.height.listen(
      (_) => enforcePreviewOutputSize('source height changed'),
    );
    final session = _PreviewPlayerSession(
      player: player,
      videoController: videoController,
      errorSubscription: errorSubscription,
      positionSubscription: positionSubscription,
      playingSubscription: playingSubscription,
      completedSubscription: completedSubscription,
      widthSubscription: widthSubscription,
      heightSubscription: heightSubscription,
    );
    activeSession = session;
    return session;
  }

  Future<bool> _activatePreloadedSession({
    required _PreloadedPreviewSession preloaded,
    required MediaItem item,
    required int revision,
    required _PreviewPlayerSession? previousSession,
    required bool playWhenReady,
  }) async {
    final player = preloaded.player;
    final session = _createPreviewSession(
      player: player,
      videoController: preloaded.videoController,
      revision: revision,
    );
    _previewOutputSize = _previewOutputSizeFor(item);
    _loadedItemId = item.id;
    _preloadSession = null;
    _preloadRevision++;
    preloaded.adopted = true;

    if (mounted && revision == _loadRevision) {
      setState(() {
        _session = session;
        _loading = false;
        _errorMessage = null;
      });
    }

    if (previousSession != null) {
      unawaited(
        _disposeSession(
          previousSession,
          revision,
          'replaced by preloaded media item',
        ),
      );
    }

    try {
      _logLoad(
        revision,
        'adopt preloaded ${item.name} from ${_durationMs(preloaded.sourcePosition)}',
      );
      await _enforcePreviewOutputSize(session, revision, 'adopted preloaded');
      await player.setRate(_normalizedPlaybackSpeed());
      await player.setVolume(widget.audioVolume.clamp(0.0, 2.0) * 100.0);
      await _seekSessionToRequestedPosition(
        session,
        revision,
        'adopted preloaded timeline playhead',
      );
      if (mounted &&
          revision == _loadRevision &&
          identical(session, _session)) {
        _initialTimelineSeekPending = false;
        _lastObservedSourcePosition = _normalizedRequestedPosition();
        _lastPositionDebugBucket = -1;
      }
      if (playWhenReady &&
          !widget.visualAdjustments.reverseVideo &&
          mounted &&
          revision == _loadRevision &&
          identical(session, _session)) {
        _debugPlayback(
          'play() call source=loadItem.adoptPreload rev=$revision '
          'item=${_itemLabel(item)} beforePlaying=${player.state.playing} '
          'pos=${_durationMs(player.state.position)}',
        );
        await player.play();
        _debugPlayback(
          'play() done source=loadItem.adoptPreload rev=$revision '
          'afterPlaying=${player.state.playing} '
          'pos=${_durationMs(player.state.position)}',
        );
        _lastKnownPlaying = true;
        _requestPreviewFrame('continue preloaded timeline playback');
      }
      return mounted &&
          revision == _loadRevision &&
          identical(session, _session);
    } catch (error) {
      _logLoad(revision, 'adopt preloaded failed: $error');
      if (mounted &&
          revision == _loadRevision &&
          identical(session, _session)) {
        setState(() {
          _errorMessage = _cleanError(error);
          _loadedItemId = null;
          _session = null;
        });
      }
      await _disposeSession(session, revision, 'adopt preloaded failed');
      return false;
    }
  }

  Future<void> _loadItem(MediaItem? item, {bool playWhenReady = false}) async {
    final revision = ++_loadRevision;
    _stopPreviewFrameTimer();
    _disposePreviewImage();
    _lastPreviewFrameCapturedAt = null;
    _rawPreviewFallback = false;
    _timelineClipAdvanceRequested = false;
    _initialTimelineSeekPending = item != null;
    _clearPendingRequestedSourceSeek('loadItem start');
    _lastObservedSourcePosition = Duration.zero;
    _lastPositionDebugBucket = -1;
    _debugPlayback(
      'loadItem start revision=$revision item=${_itemLabel(item)} '
      'playWhenReady=$playWhenReady',
    );
    if (item == null) {
      _previewOutputSize = const _PreviewOutputSize(
        width: _maxPreviewOutputWidth,
        height: _maxPreviewOutputHeight,
        downscaled: false,
      );
      _previewFrameInterval = _previewFrameInterval720p;
      _lastKnownPlaying = false;
      _resumePlaybackAcrossTimelineClip = false;
      _initialTimelineSeekPending = false;
    }
    final previousSession = _session;
    _session = null;
    _loadedItemId = item?.id;

    if (mounted) {
      setState(() {
        _loading = item != null;
        _errorMessage = null;
      });
    }

    if (item != null) {
      final preloaded = _takePreloadedSession(item, widget.requestedPosition);
      if (preloaded != null) {
        await _activatePreloadedSession(
          preloaded: preloaded,
          item: item,
          revision: revision,
          previousSession: previousSession,
          playWhenReady: playWhenReady,
        );
        return;
      } else {
        unawaited(_disposePreload('load item without adoption'));
      }
    }

    if (previousSession != null) {
      await _disposeSession(previousSession, revision, 'replaced media item');
      if (!mounted || revision != _loadRevision) {
        _logLoad(revision, 'ignored after previous session disposal');
        return;
      }
    }

    if (item == null) {
      if (mounted && revision == _loadRevision) {
        setState(() {
          _loading = false;
          _loadedItemId = null;
        });
      }
      return;
    }

    _logLoad(revision, 'start ${item.name} (${item.filePath})');
    _previewOutputSize = _previewOutputSizeFor(item);

    _PreviewPlayerSession? session;
    try {
      if (!await File(item.filePath).exists()) {
        throw const FileSystemException('Arquivo de video nao encontrado.');
      }

      final player = Player();
      final videoController = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          hwdec: 'auto',
          width: _previewOutputSize.width,
          height: _previewOutputSize.height,
          enableHardwareAcceleration: true,
        ),
      );
      final errorSubscription = player.stream.error.listen((message) {
        _handlePlayerError(revision, message);
      });
      final positionSubscription = player.stream.position.listen((position) {
        if (!mounted || revision != _loadRevision) {
          return;
        }
        final currentItem = widget.item;
        _debugPlayback(
          'raw position event rev=$revision item=${_itemLabel(currentItem)} '
          'pos=${_durationMs(position)} requested=${_durationMs(widget.requestedPosition)} '
          'timeline=${_durationMs(widget.timelinePosition)} playing=${player.state.playing} '
          'initialSeekPending=$_initialTimelineSeekPending '
          'pendingSeek=${_pendingRequestedSourceSeekLabel()}',
        );
        if (_initialTimelineSeekPending) {
          _debugPlayback(
            'position event ignored while initial timeline seek pending '
            'rev=$revision item=${_itemLabel(currentItem)} '
            'pos=${_durationMs(position)} '
            'requested=${_durationMs(widget.requestedPosition)} '
            'timeline=${_durationMs(widget.timelinePosition)}',
          );
          _lastObservedSourcePosition = position;
          return;
        }
        if (_shouldIgnorePositionWhileRequestedSourceSeekPending(position)) {
          return;
        }
        if (widget.visualAdjustments.reverseVideo) {
          _lastObservedSourcePosition = widget.requestedPosition;
          if (player.state.playing) {
            unawaited(player.pause());
          }
          return;
        }
        if (widget.continuePlaybackOnItemChange &&
            currentItem != null &&
            currentItem.duration > Duration.zero) {
          final previousPosition = _lastObservedSourcePosition;
          final nearEnd =
              currentItem.duration - position <= _timelineClipEndAdvanceWindow;
          final resetAfterEnd =
              (previousPosition >=
                      currentItem.duration - _timelineClipEndAdvanceWindow ||
                  _resumePlaybackAcrossTimelineClip) &&
              position <= _completedSourceResetThreshold;

          final positionBucket = position.inMilliseconds ~/ 250;
          final jumpedBack =
              position < previousPosition - const Duration(milliseconds: 500);
          if (positionBucket != _lastPositionDebugBucket ||
              nearEnd ||
              resetAfterEnd ||
              jumpedBack ||
              _timelineClipAdvanceRequested) {
            _lastPositionDebugBucket = positionBucket;
            _debugPlayback(
              'position event rev=$revision item=${_itemLabel(currentItem)} '
              'pos=${_durationMs(position)} prev=${_durationMs(previousPosition)} '
              'duration=${_durationMs(currentItem.duration)} '
              'playing=${player.state.playing} nearEnd=$nearEnd '
              'resetAfterEnd=$resetAfterEnd jumpedBack=$jumpedBack '
              'advanceRequested=$_timelineClipAdvanceRequested '
              'resumeFlag=$_resumePlaybackAcrossTimelineClip',
            );
          }

          _lastObservedSourcePosition = position;

          if (_timelineClipAdvanceRequested) {
            _debugPlayback(
              'position event ignored because timeline advance already requested '
              'pos=${_durationMs(position)} item=${_itemLabel(currentItem)}',
            );
            return;
          }
          if (resetAfterEnd) {
            _advanceTimelineFromFinishedSource(
              currentItem,
              'source reset after end',
            );
            return;
          }
          if (player.state.playing && nearEnd) {
            _resumePlaybackAcrossTimelineClip = true;
          }
        } else {
          _lastObservedSourcePosition = position;
        }
        if (currentItem != null) {
          widget.onPositionChanged?.call(currentItem.id, position);
        }
      });
      final playingSubscription = player.stream.playing.listen((playing) {
        if (!mounted || revision != _loadRevision) {
          return;
        }
        if (widget.visualAdjustments.reverseVideo) {
          _lastKnownPlaying = false;
          return;
        }
        _debugPlayback(
          'playing event rev=$revision playing=$playing '
          'advanceRequested=$_timelineClipAdvanceRequested '
          'initialSeekPending=$_initialTimelineSeekPending '
          'lastKnownPlaying=$_lastKnownPlaying',
        );
        if ((_timelineClipAdvanceRequested || _initialTimelineSeekPending) &&
            !playing) {
          _debugPlayback(
            'playing=false ignored while waiting for timeline continuation seek',
          );
          return;
        }
        if (!playing && _shouldAdvanceAfterNaturalPlayerStop(player)) {
          final currentItem = widget.item!;
          _debugPlayback(
            'playing=false converted to timeline continuation at source end',
          );
          _advanceTimelineFromFinishedSource(
            currentItem,
            'player stopped at source end',
          );
          return;
        }
        _lastKnownPlaying = playing;
        widget.onTimelinePlaybackChanged?.call(playing);
      });
      final completedSubscription = player.stream.completed.listen((completed) {
        final currentItem = widget.item;
        _debugPlayback(
          'completed event rev=$revision completed=$completed '
          'item=${_itemLabel(currentItem)} mounted=$mounted '
          'currentRevision=$_loadRevision '
          'playerPos=${_durationMs(player.state.position)} '
          'playerDuration=${_durationMs(player.state.duration)} '
          'playing=${player.state.playing} '
          'advanceRequested=$_timelineClipAdvanceRequested '
          'resumeFlag=$_resumePlaybackAcrossTimelineClip',
        );
        if (!mounted || revision != _loadRevision || !completed) {
          return;
        }
        if (widget.visualAdjustments.reverseVideo) {
          _debugPlayback('completed event ignored for reverse preview');
          return;
        }
        if (!widget.continuePlaybackOnItemChange ||
            currentItem == null ||
            currentItem.duration <= Duration.zero) {
          _debugPlayback(
            'completed event ignored: timeline continuation disabled or no item',
          );
          return;
        }
        _advanceTimelineFromFinishedSource(currentItem, 'completed event');
      });
      void enforcePreviewOutputSize(String reason) {
        final activeSession = session;
        if (activeSession == null) {
          return;
        }
        unawaited(_enforcePreviewOutputSize(activeSession, revision, reason));
      }

      final widthSubscription = player.stream.width.listen(
        (_) => enforcePreviewOutputSize('source width changed'),
      );
      final heightSubscription = player.stream.height.listen(
        (_) => enforcePreviewOutputSize('source height changed'),
      );
      session = _PreviewPlayerSession(
        player: player,
        videoController: videoController,
        errorSubscription: errorSubscription,
        positionSubscription: positionSubscription,
        playingSubscription: playingSubscription,
        completedSubscription: completedSubscription,
        widthSubscription: widthSubscription,
        heightSubscription: heightSubscription,
      );

      if (!mounted || revision != _loadRevision) {
        _logLoad(revision, 'discarded before open');
        await _disposeSession(session, revision, 'stale before open');
        return;
      }

      setState(() {
        _session = session;
      });

      await player.open(Media(Uri.file(item.filePath).toString()), play: false);
      _logLoad(revision, 'open completed ${item.name}');
      await _enforcePreviewOutputSize(session, revision, 'open completed');
      await player.setRate(_normalizedPlaybackSpeed());
      _logLoad(revision, 'player rate set to ${_normalizedPlaybackSpeed()}');
      await player.setVolume(widget.audioVolume.clamp(0.0, 2.0) * 100.0);
      _logLoad(revision, 'player volume set to ${widget.audioVolume}');
      await _seekSessionToRequestedPosition(
        session,
        revision,
        'initial timeline playhead before first frame',
        force: true,
      );
      await _waitForFirstPreviewFrame(session, revision, item.name);
      await _seekSessionToRequestedPosition(
        session,
        revision,
        'initial timeline playhead after first frame',
        force: true,
      );
      if (mounted &&
          revision == _loadRevision &&
          identical(session, _session)) {
        _initialTimelineSeekPending = false;
        _lastObservedSourcePosition = _normalizedRequestedPosition();
        _lastPositionDebugBucket = -1;
        _debugPlayback(
          'initial timeline seek completed rev=$revision '
          'item=${_itemLabel(item)} '
          'requested=${_durationMs(widget.requestedPosition)} '
          'statePos=${_durationMs(player.state.position)} '
          'playWhenReady=$playWhenReady',
        );
      }
      if (playWhenReady &&
          !widget.visualAdjustments.reverseVideo &&
          mounted &&
          revision == _loadRevision &&
          identical(session, _session)) {
        _debugPlayback(
          'play() call source=loadItem.autoContinue rev=$revision '
          'item=${_itemLabel(item)} beforePlaying=${player.state.playing} '
          'pos=${_durationMs(player.state.position)} '
          'pendingInitialSeek=$_initialTimelineSeekPending',
        );
        await player.play();
        _debugPlayback(
          'play() done source=loadItem.autoContinue rev=$revision '
          'afterPlaying=${player.state.playing} '
          'pos=${_durationMs(player.state.position)}',
        );
        _lastKnownPlaying = true;
        _requestPreviewFrame('continue timeline playback');
      }
    } catch (error) {
      _logLoad(revision, 'open failed: $error');
      if (session != null && revision == _loadRevision) {
        await _disposeSession(session, revision, 'open failed');
      }
      if (mounted && revision == _loadRevision) {
        setState(() {
          _errorMessage = _cleanError(error);
          _disposePreviewImage();
          _loadedItemId = null;
          _session = null;
        });
      }
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _syncPreloadTarget() async {
    final entry = widget.videoPreloadEntry;
    if (!_shouldPreload(entry)) {
      await _disposePreload('no preload target in range');
      return;
    }

    final key = _preloadKey(entry!);
    final existing = _preloadSession;
    if (existing != null && existing.key == key && !existing.disposed) {
      return;
    }

    await _disposePreload('preload target changed');

    final revision = ++_preloadRevision;
    final outputSize = _previewOutputSizeFor(entry.item);
    final player = Player();
    final videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        hwdec: 'auto',
        width: outputSize.width,
        height: outputSize.height,
        enableHardwareAcceleration: true,
      ),
    );
    final session = _PreloadedPreviewSession(
      key: key,
      item: entry.item,
      sourcePosition: _normalizedPreloadPosition(entry.sourcePosition),
      player: player,
      videoController: videoController,
    );

    if (!mounted || revision != _preloadRevision) {
      await session.dispose('preload stale before open');
      return;
    }

    setState(() {
      _preloadSession = session;
    });

    try {
      if (!await File(entry.item.filePath).exists()) {
        throw const FileSystemException('Arquivo de video nao encontrado.');
      }
      if (!mounted ||
          revision != _preloadRevision ||
          !identical(session, _preloadSession)) {
        await session.dispose('preload stale before media open');
        return;
      }

      _logPreload(
        'open start clip=${entry.clipId} item=${_itemLabel(entry.item)} '
        'source=${_durationMs(session.sourcePosition)} '
        'timeline=${_durationMs(entry.timelineStart)}',
      );
      await player.open(
        Media(Uri.file(entry.item.filePath).toString()),
        play: false,
      );
      if (!mounted ||
          revision != _preloadRevision ||
          !identical(session, _preloadSession)) {
        await session.dispose('preload stale after media open');
        return;
      }

      await player.setRate(_normalizedPreloadSpeed(entry.playbackSpeed));
      await player.setVolume(0);
      await player.seek(session.sourcePosition);
      if (!mounted ||
          revision != _preloadRevision ||
          !identical(session, _preloadSession)) {
        await session.dispose('preload stale after seek');
        return;
      }

      session.ready = true;
      _logPreload(
        'ready clip=${entry.clipId} item=${_itemLabel(entry.item)} '
        'source=${_durationMs(session.sourcePosition)} '
        'statePos=${_durationMs(player.state.position)}',
      );
      setState(() {});
    } catch (error) {
      _logPreload('failed clip=${entry.clipId}: $error');
      if (identical(session, _preloadSession)) {
        _preloadSession = null;
        if (mounted) {
          setState(() {});
        }
      }
      await session.dispose('preload failed');
    }
  }

  bool _shouldPreload(VideoPreviewPreloadEntry? entry) {
    if (entry == null || !mounted) {
      return false;
    }
    final currentItem = widget.item;
    if (currentItem == null ||
        !widget.timelinePlaybackActive ||
        entry.item.filePath.isEmpty) {
      return false;
    }
    if (currentItem.id == entry.item.id &&
        currentItem.filePath == entry.item.filePath) {
      return false;
    }

    final untilStart = entry.timelineStart - widget.timelinePosition;
    return untilStart >= -_videoPreloadBoundaryTolerance &&
        untilStart <= _videoPreloadLookAhead;
  }

  _PreloadedPreviewSession? _takePreloadedSession(
    MediaItem item,
    Duration requestedPosition,
  ) {
    final session = _preloadSession;
    if (session == null || session.disposed || !session.ready) {
      return null;
    }
    if (session.item.id != item.id || session.item.filePath != item.filePath) {
      return null;
    }

    final target = _normalizedPreloadPosition(requestedPosition);
    final driftMs = (session.sourcePosition - target).inMilliseconds.abs();
    if (driftMs > _videoPreloadAdoptionTolerance.inMilliseconds) {
      _logPreload(
        'adoption skipped drift=${driftMs}ms item=${_itemLabel(item)} '
        'preloaded=${_durationMs(session.sourcePosition)} '
        'requested=${_durationMs(target)}',
      );
      return null;
    }

    _preloadSession = null;
    _preloadRevision++;
    _logPreload(
      'adoption matched item=${_itemLabel(item)} '
      'preloaded=${_durationMs(session.sourcePosition)} '
      'requested=${_durationMs(target)}',
    );
    return session;
  }

  Future<void> _disposePreload(String reason) async {
    final session = _preloadSession;
    if (session == null) {
      return;
    }
    _preloadSession = null;
    _preloadRevision++;
    _logPreload('dispose ${_itemLabel(session.item)} reason=$reason');
    if (mounted) {
      setState(() {});
    }
    await session.dispose(reason);
  }

  bool _preloadEntryChanged(
    VideoPreviewPreloadEntry? previous,
    VideoPreviewPreloadEntry? next,
  ) {
    if (previous == null || next == null) {
      return previous != next;
    }
    return previous.clipId != next.clipId ||
        previous.item.id != next.item.id ||
        previous.item.filePath != next.item.filePath ||
        previous.sourcePosition != next.sourcePosition ||
        previous.timelineStart != next.timelineStart ||
        previous.playbackSpeed != next.playbackSpeed;
  }

  String _preloadKey(VideoPreviewPreloadEntry entry) {
    return '${entry.clipId}|${entry.item.id}|${entry.item.filePath}|'
        '${entry.sourcePosition.inMicroseconds}|'
        '${entry.timelineStart.inMicroseconds}|'
        '${_normalizedPreloadSpeed(entry.playbackSpeed)}';
  }

  Duration _normalizedPreloadPosition(Duration position) {
    return position < Duration.zero ? Duration.zero : position;
  }

  double _normalizedPreloadSpeed(double speed) {
    if (speed.isNaN || speed.isInfinite || speed <= 0) {
      return 1;
    }
    return speed.clamp(0.25, 4.0).toDouble();
  }

  void _logPreload(String message) {
    if (!_enablePreviewTraceLogging) {
      return;
    }
    EditorDebugLog.write('preview-preload', message);
  }

  Future<void> _waitForFirstPreviewFrame(
    _PreviewPlayerSession session,
    int revision,
    String mediaName,
  ) async {
    var nativeFrameRendered = false;
    try {
      await session.videoController.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 4),
      );
      _logLoad(revision, 'video output primed $mediaName');
      nativeFrameRendered = true;
    } on TimeoutException {
      _logLoad(revision, 'video output prime timeout $mediaName');
    }

    if (!mounted ||
        revision != _loadRevision ||
        !identical(session, _session)) {
      return;
    }

    if (nativeFrameRendered) {
      _rawPreviewFallback = false;
      await _enforcePreviewOutputSize(
        session,
        revision,
        'native first frame rendered',
      );
      _stopPreviewFrameTimer();
      return;
    }

    _rawPreviewFallback = true;
    // Scale inside the player before requesting BGRA pixels. Resizing only the
    // Flutter surface still transfers the original 4K frame over the CPU.
    final native = session.player.platform;
    if (native is NativePlayer) {
      try {
        await native.setProperty(
          'vf',
          'lavfi=[scale=w=1280:h=720:force_original_aspect_ratio=decrease:force_divisible_by=2]',
        );
      } catch (error) {
        _logLoad(revision, 'fallback scale unavailable: $error');
      }
    }
    if (!mounted || revision != _loadRevision) return;
    if (mounted) {
      setState(() {});
    }

    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted ||
          revision != _loadRevision ||
          !identical(session, _session)) {
        return;
      }

      final captured = await _capturePreviewFrame(
        session,
        revision,
        'fallback first frame',
        log: true,
      );
      if (captured) {
        _logLoad(revision, 'fallback preview frame captured $mediaName');
        _startPreviewFrameTimer(revision);
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    _logLoad(revision, 'first preview frame timeout $mediaName');
  }

  Future<void> _enforcePreviewOutputSize(
    _PreviewPlayerSession session,
    int revision,
    String reason,
  ) async {
    if (!mounted ||
        revision != _loadRevision ||
        !identical(session, _session)) {
      return;
    }

    final outputSize = _previewOutputSize;
    try {
      await session.videoController.setSize(
        width: outputSize.width,
        height: outputSize.height,
      );
      _logLoad(
        revision,
        'preview output size ${outputSize.width}x${outputSize.height} $reason',
      );
    } catch (error) {
      _logLoad(revision, 'preview output resize failed $reason: $error');
    }
  }

  void _startPreviewFrameTimer(int revision) {
    _previewFrameTimer?.cancel();
    final session = _session;
    if (session == null || revision != _loadRevision || !_rawPreviewFallback) {
      return;
    }
    final interval = Duration(
      milliseconds: (_lastFrameCaptureCost.inMilliseconds * 1.25).ceil().clamp(
        67,
        500,
      ),
    );
    if (_previewFrameInterval != interval) {
      _previewFrameInterval = interval;
      if (mounted) {
        setState(() {});
      }
    }
    _logLoad(
      revision,
      'preview frame timer ${session.player.state.width ?? 0}x${session.player.state.height ?? 0} every ${interval.inMilliseconds}ms',
    );
    _previewFrameTimer = Timer.periodic(interval, (_) {
      final session = _session;
      if (session == null || revision != _loadRevision) {
        return;
      }
      final playing = session.player.state.playing;
      if (playing || _previewImage == null) {
        unawaited(_capturePreviewFrame(session, revision, 'playback'));
      }
    });
  }

  void _stopPreviewFrameTimer() {
    _previewFrameTimer?.cancel();
    _previewFrameTimer = null;
    _frameCaptureInProgress = false;
  }

  void _advanceTimelineFromFinishedSource(MediaItem item, String reason) {
    if (_timelineClipAdvanceRequested) {
      _debugPlayback(
        'advance ignored duplicate reason=$reason item=${_itemLabel(item)}',
      );
      return;
    }

    _debugPlayback(
      'advance requested reason=$reason item=${_itemLabel(item)} '
      'duration=${_durationMs(item.duration)} '
      'lastObserved=${_durationMs(_lastObservedSourcePosition)} '
      'lastKnownPlaying=$_lastKnownPlaying',
    );
    _timelineClipAdvanceRequested = true;
    _resumePlaybackAcrossTimelineClip = true;
    _lastKnownPlaying = true;
    _lastObservedSourcePosition = item.duration;
    widget.onTimelinePlaybackChanged?.call(true);
    _logLoad(_loadRevision, 'timeline clip advance requested: $reason');
    widget.onPositionChanged?.call(item.id, item.duration);
  }

  bool _shouldAdvanceAfterNaturalPlayerStop(Player player) {
    final currentItem = widget.item;
    if (!widget.continuePlaybackOnItemChange ||
        !widget.timelinePlaybackActive ||
        widget.visualAdjustments.reverseVideo ||
        currentItem == null ||
        currentItem.duration <= Duration.zero) {
      return false;
    }
    final remaining = currentItem.duration - player.state.position;
    return _resumePlaybackAcrossTimelineClip ||
        remaining <= _timelineClipEndAdvanceWindow;
  }

  void _debugPlayback(String message) {
    if (!_enablePreviewTraceLogging) {
      return;
    }
    EditorDebugLog.write('preview', message);
  }

  String _itemLabel(MediaItem? item) {
    if (item == null) {
      return 'none';
    }
    return '${item.id}/${item.name} duration=${_durationMs(item.duration)}';
  }

  String _durationMs(Duration duration) => '${duration.inMilliseconds}ms';

  bool _isPlaybackEchoPosition(Duration position) {
    return (_lastObservedSourcePosition - position).inMilliseconds.abs() < 120;
  }

  void _markRequestedSourceSeekPending(Duration position) {
    _pendingRequestedSourcePosition = position < Duration.zero
        ? Duration.zero
        : position;
    _pendingRequestedSourceSeekStartedAt = DateTime.now();
    _debugPlayback(
      'pending seek set target=${_durationMs(_pendingRequestedSourcePosition!)} '
      'timeline=${_durationMs(widget.timelinePosition)} '
      'lastObserved=${_durationMs(_lastObservedSourcePosition)}',
    );
  }

  void _clearPendingRequestedSourceSeek(String reason) {
    final target = _pendingRequestedSourcePosition;
    final startedAt = _pendingRequestedSourceSeekStartedAt;
    if (target != null || startedAt != null) {
      _debugPlayback(
        'pending seek cleared reason=$reason '
        'target=${target == null ? 'none' : _durationMs(target)} '
        'ageMs=${startedAt == null ? 'none' : DateTime.now().difference(startedAt).inMilliseconds}',
      );
    }
    _pendingRequestedSourcePosition = null;
    _pendingRequestedSourceSeekStartedAt = null;
  }

  String _pendingRequestedSourceSeekLabel() {
    final target = _pendingRequestedSourcePosition;
    final startedAt = _pendingRequestedSourceSeekStartedAt;
    if (target == null || startedAt == null) {
      return 'none';
    }
    return 'target=${_durationMs(target)} ageMs=${DateTime.now().difference(startedAt).inMilliseconds}';
  }

  bool _shouldIgnorePositionWhileRequestedSourceSeekPending(Duration position) {
    final target = _pendingRequestedSourcePosition;
    final startedAt = _pendingRequestedSourceSeekStartedAt;
    if (target == null || startedAt == null) {
      return false;
    }

    final reachedTarget =
        (position - target).inMilliseconds.abs() <
        _requestedSourceSeekTolerance.inMilliseconds;
    final expired =
        DateTime.now().difference(startedAt) > _requestedSourceSeekTimeout;
    if (reachedTarget || expired) {
      _clearPendingRequestedSourceSeek(
        reachedTarget
            ? 'target reached at ${_durationMs(position)}'
            : 'timeout at ${_durationMs(position)}',
      );
      return false;
    }

    _debugPlayback(
      'position ignored while pending seek target=${_durationMs(target)} '
      'pos=${_durationMs(position)} ageMs=${DateTime.now().difference(startedAt).inMilliseconds}',
    );
    return true;
  }

  Future<void> _seekToRequestedPosition(
    String reason, {
    bool playWhenReady = false,
  }) async {
    final session = _session;
    if (session == null) {
      return;
    }
    if (widget.visualAdjustments.reverseVideo) {
      await _seekReversePreview(reason);
      return;
    }
    _debugPlayback(
      'seekToRequestedPosition reason=$reason playWhenReady=$playWhenReady '
      'item=${_itemLabel(widget.item)} requested=${_durationMs(widget.requestedPosition)} '
      'timeline=${_durationMs(widget.timelinePosition)} '
      'playerPos=${_durationMs(session.player.state.position)} '
      'playing=${session.player.state.playing}',
    );
    await _seekSessionToRequestedPosition(session, _loadRevision, reason);
    if (playWhenReady &&
        !widget.visualAdjustments.reverseVideo &&
        mounted &&
        identical(session, _session) &&
        !session.player.state.playing) {
      _debugPlayback(
        'play() call source=seekToRequestedPosition.autoContinue '
        'item=${_itemLabel(widget.item)} '
        'beforePlaying=${session.player.state.playing} '
        'pos=${_durationMs(session.player.state.position)} '
        'pendingInitialSeek=$_initialTimelineSeekPending',
      );
      await session.player.play();
      _debugPlayback(
        'play() done source=seekToRequestedPosition.autoContinue '
        'afterPlaying=${session.player.state.playing} '
        'pos=${_durationMs(session.player.state.position)}',
      );
      _lastKnownPlaying = true;
      _requestPreviewFrame('continue timeline playback');
    }
  }

  Future<void> _seekReversePreview(String reason) async {
    _reverseSeekPending = true;
    if (_reverseSeekInProgress) return;
    _reverseSeekInProgress = true;
    try {
      while (_reverseSeekPending &&
          mounted &&
          widget.visualAdjustments.reverseVideo) {
        _reverseSeekPending = false;
        final session = _session;
        if (session == null) break;
        if (session.player.state.playing) await session.player.pause();
        if (!mounted || !widget.visualAdjustments.reverseVideo) break;
        await _seekSessionToRequestedPosition(
          session,
          _loadRevision,
          reason,
          force: true,
        );
      }
    } finally {
      _reverseSeekPending = false;
      _reverseSeekInProgress = false;
    }
  }

  Future<void> _seekSessionToRequestedPosition(
    _PreviewPlayerSession session,
    int revision,
    String reason, {
    bool force = false,
  }) async {
    if (!mounted ||
        revision != _loadRevision ||
        !identical(session, _session)) {
      return;
    }

    final target = _normalizedRequestedPosition();
    final current = session.player.state.position;
    _debugPlayback(
      'seekSession request reason=$reason force=$force '
      'target=${_durationMs(target)} current=${_durationMs(current)} '
      'playing=${session.player.state.playing} item=${_itemLabel(widget.item)}',
    );
    if (!force && (current - target).inMilliseconds.abs() < 350) {
      _debugPlayback('seekSession skipped: target close to current');
      return;
    }

    try {
      await session.player.seek(target);
      _debugPlayback(
        'seekSession applied reason=$reason target=${_durationMs(target)} '
        'statePos=${_durationMs(session.player.state.position)} '
        'playing=${session.player.state.playing}',
      );
      if (!session.player.state.playing) {
        _requestPreviewFrame(reason);
      }
    } catch (error) {
      _logLoad(revision, 'seek failed $reason: $error');
    }
  }

  Duration _normalizedRequestedPosition() {
    return widget.requestedPosition < Duration.zero
        ? Duration.zero
        : widget.requestedPosition;
  }

  double _normalizedPlaybackSpeed() {
    final speed = widget.playbackSpeed;
    if (speed.isNaN || speed.isInfinite || speed <= 0) {
      return 1;
    }
    return speed.clamp(0.25, 4.0).toDouble();
  }

  void _requestPreviewFrame(String reason) {
    final session = _session;
    if (session == null || !_rawPreviewFallback) {
      return;
    }

    final lastCapturedAt = _lastPreviewFrameCapturedAt;
    if (_previewFrameInterval >= _previewPerformanceWarningThreshold &&
        lastCapturedAt != null &&
        DateTime.now().difference(lastCapturedAt) < _previewFrameInterval) {
      _logLoad(
        _loadRevision,
        'preview frame throttled $reason every ${_previewFrameInterval.inMilliseconds}ms',
      );
      return;
    }

    unawaited(_capturePreviewFrame(session, _loadRevision, reason, log: true));
  }

  Future<bool> _capturePreviewFrame(
    _PreviewPlayerSession session,
    int revision,
    String reason, {
    bool log = false,
  }) async {
    if (_frameCaptureInProgress) {
      return false;
    }

    _frameCaptureInProgress = true;
    final captureClock = Stopwatch()..start();
    try {
      var width = session.player.state.width;
      var height = session.player.state.height;
      final native = session.player.platform;
      if (_rawPreviewFallback && native is NativePlayer) {
        final outputWidth = int.tryParse(
          await native.getProperty('video-out-params/w'),
        );
        final outputHeight = int.tryParse(
          await native.getProperty('video-out-params/h'),
        );
        if (outputWidth != null && outputWidth > 0) width = outputWidth;
        if (outputHeight != null && outputHeight > 0) height = outputHeight;
      }
      if (width == null || height == null || width <= 0 || height <= 0) {
        if (log) {
          _logLoad(revision, 'preview frame missing dimensions $reason');
        }
        return false;
      }

      final bytes = await session.player.screenshot(format: null);
      if (bytes == null || bytes.isEmpty) {
        if (log) {
          _logLoad(revision, 'preview frame empty $reason');
        }
        return false;
      }

      final minimumRowBytes = width * 4;
      final rowBytes = bytes.length ~/ height;
      if (rowBytes < minimumRowBytes || rowBytes * height > bytes.length) {
        if (log) {
          _logLoad(
            revision,
            'preview frame invalid buffer $reason ${bytes.length} bytes ${width}x$height rowBytes=$rowBytes',
          );
        }
        return false;
      }

      final image = await _decodeBgraImage(bytes, width, height, rowBytes);
      if (!mounted ||
          revision != _loadRevision ||
          !identical(session, _session)) {
        image.dispose();
        return false;
      }

      _lastPreviewFrameCapturedAt = DateTime.now();
      final previousImage = _previewImage;
      setState(() {
        _previewImage = image;
        _previewFrameSerial++;
      });
      if (previousImage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          previousImage.dispose();
        });
      }

      if (log) {
        _logLoad(
          revision,
          'preview frame raw $reason ${width}x$height rowBytes=$rowBytes ${bytes.length} bytes',
        );
      }
      return true;
    } catch (error) {
      if (log) {
        _logLoad(revision, 'preview frame capture failed $reason: $error');
      }
      return false;
    } finally {
      _frameCaptureInProgress = false;
      _lastFrameCaptureCost = captureClock.elapsed;
      if (mounted &&
          revision == _loadRevision &&
          _rawPreviewFallback &&
          _previewFrameTimer != null) {
        final next = (_lastFrameCaptureCost.inMilliseconds * 1.25).ceil().clamp(
          67,
          500,
        );
        if ((next - _previewFrameInterval.inMilliseconds).abs() > 30) {
          _startPreviewFrameTimer(revision);
        }
      }
    }
  }

  Future<ui.Image> _decodeBgraImage(
    List<int> bytes,
    int width,
    int height,
    int rowBytes,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      width,
      height,
      ui.PixelFormat.bgra8888,
      completer.complete,
      rowBytes: rowBytes,
    );
    return completer.future;
  }

  void _disposePreviewImage() {
    final image = _previewImage;
    _previewImage = null;
    _previewFrameSerial = 0;
    image?.dispose();
  }

  Future<void> _disposeSession(
    _PreviewPlayerSession session,
    int revision,
    String reason,
  ) async {
    try {
      _logLoad(revision, 'dispose player session: $reason');
      await session.errorSubscription.cancel();
      await session.positionSubscription.cancel();
      await session.playingSubscription.cancel();
      await session.completedSubscription.cancel();
      await session.widthSubscription.cancel();
      await session.heightSubscription.cancel();
      await session.player.dispose();
    } catch (error) {
      _logLoad(revision, 'dispose failed: $error');
    }
  }

  void _handlePlayerError(int revision, String message) {
    _logLoad(revision, 'media_kit error: $message');
    if (!mounted || revision != _loadRevision) {
      return;
    }

    setState(() {
      _errorMessage = message;
      _loading = false;
      _loadedItemId = null;
    });
  }

  void _logLoad(int revision, String message) {
    if (!_enablePreviewTraceLogging) {
      return;
    }
    EditorDebugLog.write('preview-load', 'rev=$revision $message');
  }

  String _cleanError(Object error) {
    if (error is FileSystemException) {
      return error.message;
    }
    if (error is FormatException) {
      return error.message;
    }

    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  Future<void> _pickChromaColorAt(Offset previewPoint, Size previewSize) async {
    if (_chromaColorSampling || !widget.chromaColorPickerActive) {
      return;
    }
    final session = _session;
    final item = widget.item;
    if (session == null || item == null || previewSize.isEmpty) {
      widget.onChromaColorPickError?.call(
        'O vídeo ainda não está pronto para selecionar uma cor.',
      );
      return;
    }

    setState(() => _chromaColorSampling = true);
    try {
      final player = session.player;
      final width = player.state.width;
      final height = player.state.height;
      if (width == null || height == null || width <= 0 || height <= 0) {
        throw const FormatException(
          'O quadro do vídeo não tem dimensões válidas.',
        );
      }
      final sourcePoint = _previewPointToSourcePoint(
        previewPoint: previewPoint,
        previewSize: previewSize,
        sourceSize: Size(width.toDouble(), height.toDouble()),
        adjustments: widget.visualAdjustments,
        timelinePosition: widget.timelinePosition,
      );
      if (sourcePoint == null) {
        throw const FormatException(
          'Clique dentro da imagem do vídeo, evitando as faixas pretas.',
        );
      }

      final bytes = await player.screenshot(format: null);
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('Não foi possível ler o quadro atual.');
      }
      final rowBytes = bytes.length ~/ height;
      if (rowBytes < width * 4 || rowBytes * height > bytes.length) {
        throw const FormatException(
          'O quadro retornado pelo vídeo é inválido.',
        );
      }
      final color = _averageBgraColor(
        bytes,
        width: width,
        height: height,
        rowBytes: rowBytes,
        x: sourcePoint.dx.round(),
        y: sourcePoint.dy.round(),
      );
      if (!mounted || !identical(session, _session)) {
        return;
      }
      widget.onChromaColorPicked?.call(color);
    } catch (error) {
      if (mounted) {
        widget.onChromaColorPickError?.call(_cleanError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _chromaColorSampling = false);
      }
    }
  }

  Future<void> _pickWhiteBalanceColorAt(
    Offset previewPoint,
    Size previewSize,
  ) async {
    if (_whiteBalanceColorSampling || !widget.whiteBalanceColorPickerActive) {
      return;
    }
    final session = _session;
    if (session == null || widget.item == null || previewSize.isEmpty) {
      widget.onWhiteBalancePickError?.call(
        'O vídeo ainda não está pronto para o balanço de branco.',
      );
      return;
    }
    setState(() => _whiteBalanceColorSampling = true);
    try {
      final frame = await _readCurrentBgraFrame(session);
      final sourcePoint = _previewPointToSourcePoint(
        previewPoint: previewPoint,
        previewSize: previewSize,
        sourceSize: Size(frame.width.toDouble(), frame.height.toDouble()),
        adjustments: widget.visualAdjustments,
        timelinePosition: widget.timelinePosition,
      );
      if (sourcePoint == null) {
        throw const FormatException(
          'Clique dentro da imagem do vídeo, evitando as faixas pretas.',
        );
      }
      final color = _averageBgraColor(
        frame.bytes,
        width: frame.width,
        height: frame.height,
        rowBytes: frame.rowBytes,
        x: sourcePoint.dx.round(),
        y: sourcePoint.dy.round(),
      );
      if (mounted && identical(session, _session)) {
        widget.onWhiteBalanceColorPicked?.call(color);
      }
    } catch (error) {
      if (mounted) {
        widget.onWhiteBalancePickError?.call(_cleanError(error));
      }
    } finally {
      if (mounted) setState(() => _whiteBalanceColorSampling = false);
    }
  }

  Future<void> _analyzeCurrentColorFrame() async {
    if (_colorAnalysisInProgress || widget.onColorAnalysis == null) {
      return;
    }
    final session = _session;
    if (session == null || widget.item == null) {
      widget.onColorAnalysisError?.call(
        'O vídeo ainda não está pronto para gerar o histograma.',
      );
      return;
    }
    _colorAnalysisInProgress = true;
    try {
      final frame = await _readCurrentBgraFrame(session);
      final analysis = _analyzeBgraFrame(
        frame.bytes,
        width: frame.width,
        height: frame.height,
        rowBytes: frame.rowBytes,
      );
      if (mounted && identical(session, _session)) {
        widget.onColorAnalysis?.call(analysis);
      }
    } catch (error) {
      if (mounted) widget.onColorAnalysisError?.call(_cleanError(error));
    } finally {
      _colorAnalysisInProgress = false;
    }
  }

  Future<({List<int> bytes, int width, int height, int rowBytes})>
  _readCurrentBgraFrame(_PreviewPlayerSession session) async {
    final width = session.player.state.width;
    final height = session.player.state.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      throw const FormatException(
        'O quadro do vídeo não tem dimensões válidas.',
      );
    }
    final bytes = await session.player.screenshot(format: null);
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Não foi possível ler o quadro atual.');
    }
    final rowBytes = bytes.length ~/ height;
    if (rowBytes < width * 4 || rowBytes * height > bytes.length) {
      throw const FormatException('O quadro retornado pelo vídeo é inválido.');
    }
    return (bytes: bytes, width: width, height: height, rowBytes: rowBytes);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final session = _session;
    final player = session?.player;
    final canControl =
        item != null &&
        player != null &&
        _loadedItemId == item.id &&
        !_loading &&
        _errorMessage == null;
    final hasTimelineControls =
        widget.timelineDuration != null &&
        widget.timelineDuration! > Duration.zero;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(TgiSpacing.md),
                child: _PreviewStage(
                  aspectRatio:
                      widget.outputAspectRatio ??
                      _previewAspectRatio(item, _previewImage),
                  child: _PreviewFrame(
                    child: _PreviewViewport(
                      visualLayerOrder: widget.visualLayerOrder,
                      baseVideoClipId: widget.baseVideoClipId,
                      item: item,
                      cropMainVideoToFill: widget.cropMainVideoToFill,
                      player: player,
                      videoController: session?.videoController,
                      loading: _loading,
                      errorMessage: _errorMessage,
                      imageOverlayItem: widget.imageOverlayItem,
                      videoOverlayEntries: widget.videoOverlayEntries,
                      imageOverlayEntries: widget.imageOverlayEntries,
                      textOverlayEntries: widget.textOverlayEntries,
                      transitionPreviewEntries: widget.transitionPreviewEntries,
                      transitionPreviewPlaying: widget.timelinePlaybackActive,
                      onImageOverlayTap: widget.onImageOverlayTap,
                      onVideoOverlayMoved: widget.onVideoOverlayMoved,
                      onVideoOverlayResized: widget.onVideoOverlayResized,
                      onVideoOverlayTap: widget.onVideoOverlayTap,
                      onTextOverlayMoved: widget.onTextOverlayMoved,
                      onTextOverlayTap: widget.onTextOverlayTap,
                      onTextOverlayEdit: widget.onTextOverlayEdit,
                      onTextOverlayInteractionStart:
                          widget.onTextOverlayInteractionStart,
                      onTextOverlayInteractionEnd:
                          widget.onTextOverlayInteractionEnd,
                      imageOverlayClipId: widget.imageOverlayClipId,
                      imageOverlayX: widget.imageOverlayX,
                      imageOverlayY: widget.imageOverlayY,
                      imageOverlayScale: widget.imageOverlayScale,
                      onImageOverlayMoved: widget.onImageOverlayMoved,
                      onImageOverlayResized: widget.onImageOverlayResized,
                      loadedItemId: _loadedItemId,
                      previewImage: _previewImage,
                      previewFrameSerial: _previewFrameSerial,
                      rawPreviewFallback: _rawPreviewFallback,
                      previewDownscaled: _previewOutputSize.downscaled,
                      videoOpacity: widget.videoOpacity,
                      visualAdjustments: widget.visualAdjustments,
                      timelinePosition: widget.timelinePosition,
                      kenBurnsToolActive: widget.kenBurnsToolActive,
                      kenBurnsPickStart: widget.kenBurnsPickStart,
                      kenBurnsStartX: widget.kenBurnsStartX,
                      kenBurnsStartY: widget.kenBurnsStartY,
                      kenBurnsEndX: widget.kenBurnsEndX,
                      kenBurnsEndY: widget.kenBurnsEndY,
                      onKenBurnsPointSelected: widget.onKenBurnsPointSelected,
                      transformToolActive: widget.transformToolActive,
                      transformCropMode: widget.transformCropMode,
                      onTransformPositionChanged:
                          widget.onTransformPositionChanged,
                      onTransformScaleChanged: widget.onTransformScaleChanged,
                      onTransformCropChanged: widget.onTransformCropChanged,
                      onTransformInteractionStart:
                          widget.onTransformInteractionStart,
                      onTransformInteractionEnd:
                          widget.onTransformInteractionEnd,
                      chromaColorPickerActive: widget.chromaColorPickerActive,
                      chromaTransparencyPreview:
                          widget.chromaTransparencyPreview,
                      chromaColorSampling: _chromaColorSampling,
                      onChromaColorPointSelected: _pickChromaColorAt,
                      whiteBalanceColorPickerActive:
                          widget.whiteBalanceColorPickerActive,
                      whiteBalanceColorSampling: _whiteBalanceColorSampling,
                      onWhiteBalanceColorPointSelected:
                          _pickWhiteBalanceColorAt,
                      onImportRequested: widget.onImportRequested,
                      mask: widget.mask,
                      maskToolActive: widget.maskToolActive,
                      onMaskGeometryChanged: widget.onMaskGeometryChanged,
                    ),
                  ),
                ),
              ),
            ),
            if (item != null ||
                hasTimelineControls ||
                widget.transportLeadingControl != null ||
                widget.transportTrailingControl != null) ...[
              const Divider(height: 1),
              _TransportControls(
                item: item,
                player: player,
                enabled: canControl,
                timelinePosition: widget.timelinePosition,
                timelineDuration: widget.timelineDuration,
                timelinePlaybackActive: widget.timelinePlaybackActive,
                onTimelineSeek: widget.onTimelineSeek,
                onTimelinePlaybackChanged: widget.onTimelinePlaybackChanged,
                onFrameRefreshRequested: _requestPreviewFrame,
                leadingControl: widget.transportLeadingControl,
                trailingControl: widget.transportTrailingControl,
              ),
            ],
          ],
        ),
        if (_preloadSession != null)
          _PreloadVideoSurface(session: _preloadSession!),
        _TimelineAudioPreviewMixer(
          entries: widget.audioPreviewEntries,
          playing: widget.timelinePlaybackActive,
        ),
      ],
    );
  }
}

double _previewAspectRatio(MediaItem? item, ui.Image? image) {
  final mediaWidth = item?.width;
  final mediaHeight = item?.height;
  if (mediaWidth != null &&
      mediaHeight != null &&
      mediaWidth > 0 &&
      mediaHeight > 0) {
    return (mediaWidth / mediaHeight).clamp(0.45, 2.4).toDouble();
  }

  if (image == null || image.width <= 0 || image.height <= 0) {
    return 16 / 9;
  }
  return (image.width / image.height).clamp(0.45, 2.4).toDouble();
}
