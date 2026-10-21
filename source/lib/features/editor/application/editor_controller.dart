import '../../../domain/text_style_profile.dart';
import '../../../services/subtitle_service.dart';
import 'dart:async';
import 'editor_caption_timing.dart';
import 'editor_history.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import '../../../core/commands/command_engine.dart';
import '../../../core/commands/command_transaction.dart';

import '../../../domain/models/audio_waveform.dart';
import '../../../domain/models/clip.dart' as domain;
import '../../../domain/models/media_item.dart';
import '../../../domain/models/project.dart';
import '../../../domain/models/timeline_transition.dart';
import '../../../domain/models/track.dart';
import '../../../services/audio_waveform_service.dart';
import '../../../services/auto_caption_service.dart';
import '../../../services/editor_debug_log.dart';
import '../../../services/ffmpeg_service.dart';
import '../../../services/media_import_service.dart';
import '../../../services/motion_mask_tracker.dart';
import '../../../services/project_io_service.dart';
import '../../../services/editor_preset_service.dart';
import '../../../services/audio_level_service.dart';
import '../../../services/audio_ducking.dart';
part 'editor_controller_preview_models.dart';
part 'editor_controller_internal_models.dart';
part 'editor_controller_tools.dart';
part 'editor_controller_timeline.dart';
part 'editor_controller_commands.dart';

const _gapPlaybackInterval = Duration(milliseconds: 100);
const _historyLimit = 50;
const _defaultAppliedTransitionDuration = Duration(milliseconds: 900);
const _clipBoundaryTolerance = Duration(milliseconds: 120);
const _captionMinDuration = Duration(milliseconds: 1200);
const _captionDefaultDuration = Duration(milliseconds: 2200);
const _defaultFreezeFrameDuration = Duration(seconds: 2);

bool shouldAutomaticallyOptimizePreview(MediaItem item) {
  if (item.type != MediaType.video ||
      (item.previewProxyPath?.isNotEmpty ?? false)) {
    return false;
  }
  final width = item.width;
  final height = item.height;
  if (width == null || height == null || width <= 0 || height <= 0) {
    return false;
  }
  final longestEdge = math.max(width, height);
  final pixels = width * height;
  return longestEdge >= 2560 ||
      pixels >= 3000000 ||
      (longestEdge >= 1920 && item.duration >= const Duration(minutes: 10));
}

enum SmartCutIntensity {
  light(
    label: 'Leve',
    description: 'Remove apenas pausas longas e mantém uma respiração maior.',
    threshold: 0.035,
    minimumSilence: Duration(milliseconds: 1200),
    edgePadding: Duration(milliseconds: 180),
  ),
  balanced(
    label: 'Normal',
    description: 'Equilíbrio para vídeos falados, aulas e podcasts.',
    threshold: 0.045,
    minimumSilence: Duration(milliseconds: 800),
    edgePadding: Duration(milliseconds: 120),
  ),
  fast(
    label: 'Rápido',
    description: 'Ritmo mais direto para Shorts e vídeos curtos.',
    threshold: 0.060,
    minimumSilence: Duration(milliseconds: 550),
    edgePadding: Duration(milliseconds: 90),
  );

  const SmartCutIntensity({
    required this.label,
    required this.description,
    required this.threshold,
    required this.minimumSilence,
    required this.edgePadding,
  });

  final String label;
  final String description;
  final double threshold;
  final Duration minimumSilence;
  final Duration edgePadding;
}

class SmartCutSegment {
  const SmartCutSegment({required this.start, required this.end});

  final Duration start;
  final Duration end;
  Duration get duration => end - start;
}

class SmartCutAnalysis {
  const SmartCutAnalysis({
    required this.intensity,
    required this.sourceTimelineGroupId,
    required this.sourceMediaItemId,
    required this.sourceVideoTrackId,
    required this.sourceName,
    required this.sourceTimelineStart,
    required this.originalTimelineDuration,
    required this.segments,
  });

  final SmartCutIntensity intensity;
  final String sourceTimelineGroupId;
  final String sourceMediaItemId;
  final String sourceVideoTrackId;
  final String sourceName;
  final Duration sourceTimelineStart;
  final Duration originalTimelineDuration;
  final List<SmartCutSegment> segments;

  Duration get removableDuration => segments.fold(
    Duration.zero,
    (total, segment) => total + segment.duration,
  );

  Duration get estimatedTimelineDuration {
    final result = originalTimelineDuration - removableDuration;
    return result < Duration.zero ? Duration.zero : result;
  }
}

class EditorController extends ChangeNotifier {
  EditorController({
    required this.mediaImportService,
    FfmpegService? ffmpegService,
    AudioWaveformService? audioWaveformService,
    AutoCaptionService? autoCaptionService,
    AudioLevelService? audioLevelService,
    TgiProject? initialProject,
  }) : ffmpegService = ffmpegService ?? mediaImportService.ffmpegService,
       audioWaveformService =
           audioWaveformService ??
           AudioWaveformService(
             ffmpegService: ffmpegService ?? mediaImportService.ffmpegService,
           ),
       autoCaptionService =
           autoCaptionService ??
           LocalWhisperAutoCaptionService(
             ffmpegService: ffmpegService ?? mediaImportService.ffmpegService,
           ),
       _audioLevelService =
           audioLevelService ??
           AudioLevelService(ffmpegService ?? mediaImportService.ffmpegService),
       _projectValue =
           initialProject ?? TgiProject.empty(name: 'Projeto sem t\u00EDtulo');

  final MediaImportService mediaImportService;
  final FfmpegService ffmpegService;
  final AudioWaveformService audioWaveformService;
  final AutoCaptionService autoCaptionService;
  final AudioLevelService _audioLevelService;
  final Map<String, AudioLevels> _audioLevels = {};
  bool _isAnalyzingAudio = false;
  TgiProject _projectValue;
  int _projectRevision = 0;
  int get projectRevision => _projectRevision;
  TgiProject get _project => _projectValue;
  set _project(TgiProject value) {
    if (!identical(value, _projectValue)) _projectRevision++;
    _projectValue = value;
  }

  TgiProject _commandProject(
    String name,
    Map<String, Object?> arguments, {
    TgiProject? base,
  }) {
    final project = base ?? _project;
    try {
      return const CommandEngine().apply(
        project,
        EditorCommand(name, arguments),
      );
    } on CommandError catch (error) {
      _errorMessage = error.message;
      return project;
    }
  }

  bool _isImporting = false;
  bool _isExporting = false;
  double _exportProgress = 0;
  DateTime? _exportStartedAt;
  Duration? _exportRemaining;
  bool _isGeneratingCaptions = false;
  double _captionProgress = 0;
  String? _captionProgressMessage;
  bool _isOptimizingPreview = false;
  double _previewOptimizationProgress = 0;
  DateTime? _previewOptimizationStartedAt;
  Duration? _previewOptimizationRemaining;
  bool _previewOptimizationAutomatic = false;
  bool _previewOptimizationCancellationRequested = false;
  String? _previewOptimizationTargetName;
  bool _isTrackingMask = false;
  double _maskTrackingProgress = 0;
  String? _errorMessage;
  String? _statusMessage;
  String? _selectedMediaItemId;
  String? _selectedTimelineGroupId;
  String? _selectedTimelineClipId;
  final Set<String> _selectedTimelineGroupIds = {};
  Duration _playheadPosition = Duration.zero;
  bool _isCutMode = false;
  bool _timelinePlaybackActive = false;
  Timer? _gapPlaybackTimer;
  DateTime? _lastGapPlaybackTickAt;
  final _history = EditorHistory(limit: _historyLimit);
  final _captionTiming = const EditorCaptionTiming();
  final List<_ClipboardClip> _clipClipboard = [];
  final Map<String, AudioWaveform> _audioWaveformsByMediaId = {};
  final Set<String> _audioWaveformLoadsInFlight = {};
  TgiProject? _trimPreviewBaseProject;
  TgiProject? _interactiveEditBaseProject;
  bool _isAnalyzingSmartCut = false;
  SmartCutAnalysis? _smartCutAnalysis;
  TgiProject? _smartCutProjectSnapshot;
  bool _disposed = false;
  bool _usePreviewProxies = true;

  bool get usePreviewProxies => _usePreviewProxies;

  void setUsePreviewProxies(bool value) {
    if (value == _usePreviewProxies) return;
    _usePreviewProxies = value;
    notifyListeners();
  }

  TgiProject get project => _project;
  bool get isImporting => _isImporting;
  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;
  Duration? get exportRemaining => _exportRemaining;
  bool get isGeneratingCaptions => _isGeneratingCaptions;
  double get captionProgress => _captionProgress;
  String? get captionProgressMessage => _captionProgressMessage;
  bool get isOptimizingPreview => _isOptimizingPreview;
  double get previewOptimizationProgress => _previewOptimizationProgress;
  Duration? get previewOptimizationRemaining => _previewOptimizationRemaining;
  bool get previewOptimizationAutomatic => _previewOptimizationAutomatic;
  String? get previewOptimizationTargetName => _previewOptimizationTargetName;
  bool get previewUsesProxy {
    if (!_usePreviewProxies) return false;
    final path = _previewOptimizationTarget?.previewProxyPath;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  bool get isTrackingMask => _isTrackingMask;
  double get maskTrackingProgress => _maskTrackingProgress;
  bool get isAnalyzingSmartCut => _isAnalyzingSmartCut;
  SmartCutAnalysis? get smartCutAnalysis =>
      identical(_smartCutProjectSnapshot, _project) ? _smartCutAnalysis : null;
  bool get canAnalyzeSmartCut {
    final clip = _selectedOrActiveVideoClip;
    if (_isAnalyzingSmartCut ||
        _isExporting ||
        _isImporting ||
        clip == null ||
        _timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      return false;
    }
    return _project.mediaItemById(clip.mediaItemId)?.hasAudio == true;
  }

  bool get canApplySmartCut =>
      !_isAnalyzingSmartCut && smartCutAnalysis?.segments.isNotEmpty == true;
  bool get canOptimizePreview =>
      !_isImporting &&
      !_isExporting &&
      !_isOptimizingPreview &&
      _previewOptimizationTarget != null;
  bool get canTrackSelectedMask =>
      !_isTrackingMask &&
      !_isExporting &&
      selectedTimelineVideoClip?.maskEnabled == true;
  bool get canExport => !_isExporting && _hasExportableTimelineClips;
  bool get canGenerateAutomaticCaptions =>
      !_isGeneratingCaptions &&
      !_isExporting &&
      !_isImporting &&
      _captionSourceVideoClips.isNotEmpty;
  bool get canExportGeneratedCaptions => generatedCaptionCues.isNotEmpty;
  List<CaptionCue> get generatedCaptionCues =>
      List.unmodifiable(_generatedCaptionCuesFromProject());
  List<domain.Clip> get generatedCaptionClips =>
      List.unmodifiable(_generatedCaptionClipsFromProject());
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  String? get selectedMediaItemId => _selectedMediaItemId;
  String? get selectedTimelineGroupId => _selectedTimelineGroupId;
  Set<String> get selectedTimelineGroupIds =>
      Set.unmodifiable(_selectedTimelineGroupIds);
  int get selectedTimelineGroupCount => _selectedTimelineGroupIds.length;
  Duration get playheadPosition => _playheadPosition;
  bool get isCutMode => _isCutMode;
  bool get timelinePlaybackActive => _timelinePlaybackActive;
  bool get canUndo => _history.undoStack.isNotEmpty;
  bool get canRedo => _history.redoStack.isNotEmpty;
  bool get canCopyClips => _selectedTimelineGroupIds.isNotEmpty;
  bool get canPasteClips => _clipClipboard.isNotEmpty;
  bool get canDuplicateClips => _selectedTimelineGroupIds.isNotEmpty;
  bool get canUnlinkSelectedAudio {
    final groupId = _selectedTimelineGroupId;
    return groupId != null &&
        _timelineGroupHasClipType(groupId, TrackType.video) &&
        _timelineGroupHasClipType(groupId, TrackType.audio) &&
        !_timelineGroupTouchesLockedTrack(groupId);
  }

  bool get selectedAudioVideoLinked {
    final groupId = _selectedTimelineGroupId;
    return groupId != null &&
        _timelineGroupHasClipType(groupId, TrackType.video) &&
        _timelineGroupHasClipType(groupId, TrackType.audio);
  }

  bool get canRelinkSelectedAudio {
    final candidate = _selectedAudioVideoRelinkCandidate;
    return candidate != null &&
        !_timelineGroupTouchesLockedTrack(candidate.audioTimelineGroupId) &&
        !_timelineGroupTouchesLockedTrack(candidate.videoTimelineGroupId);
  }

  bool get canToggleSelectedAudioVideoLink =>
      canUnlinkSelectedAudio || canRelinkSelectedAudio;

  Map<String, AudioWaveform> get audioWaveformsByMediaId =>
      Map.unmodifiable(_audioWaveformsByMediaId);

  List<TimelineAudioPreviewClip> get activeStandaloneAudioPreviewClips {
    final activeVideoGroupId = activeTimelineClip?.timelineGroupId;
    final clips = <TimelineAudioPreviewClip>[];

    for (final track in _project.tracks) {
      if (!_audioTrackIsAudible(track)) {
        continue;
      }
      for (final clip in track.clips) {
        final volume = _keyframedClipValueAtPlayhead(
          clip,
          domain.ClipKeyframeProperty.volume,
        );
        if (!_clipContainsTimelinePosition(clip, _playheadPosition) ||
            volume <= 0) {
          continue;
        }
        if (activeVideoGroupId != null &&
            clip.timelineGroupId == activeVideoGroupId) {
          continue;
        }
        final mediaItem = _project.mediaItemById(clip.mediaItemId);
        if (mediaItem == null ||
            (mediaItem.type != MediaType.audio &&
                mediaItem.type != MediaType.video)) {
          continue;
        }
        final timelineDelta = _playheadPosition - clip.timelineStart;
        final sourcePosition =
            clip.sourceStart +
            _sourceDurationForTimeline(timelineDelta, clip.playbackSpeed);
        clips.add(
          TimelineAudioPreviewClip(
            clipId: clip.id,
            mediaItem: mediaItem,
            sourcePosition: _clampDuration(
              sourcePosition,
              clip.sourceStart,
              clip.sourceEnd,
            ),
            volume: volume * track.volume * previewOpacityForClip(clip),
            playbackSpeed: clip.playbackSpeed,
          ),
        );
      }
    }

    return List.unmodifiable(clips);
  }

  domain.Clip? get selectedTimelineClip {
    final focused = _selectedTimelineClipId == null
        ? null
        : _findClipById(_selectedTimelineClipId!);
    if (focused != null &&
        _selectedTimelineGroupIds.contains(focused.timelineGroupId)) {
      return focused;
    }
    final selectedGroupId = _selectedTimelineGroupId;
    if (selectedGroupId == null) {
      return null;
    }
    return _clipForTimelineGroup(selectedGroupId, const [
      TrackType.text,
      TrackType.image,
      TrackType.video,
      TrackType.audio,
    ]);
  }

  domain.Clip? get selectedTimelineVideoClip {
    final selectedGroupId = _selectedTimelineGroupId;
    if (selectedGroupId == null) {
      return null;
    }
    return _videoClipForTimelineGroup(selectedGroupId);
  }

  domain.Clip? get selectedTimelineAudioClip {
    final selectedGroupId = _selectedTimelineGroupId;
    if (selectedGroupId == null) {
      return null;
    }
    return _clipForTimelineGroup(selectedGroupId, const [TrackType.audio]);
  }

  MediaItem? get selectedTimelineClipMediaItem {
    final clip = selectedTimelineClip;
    if (clip == null) {
      return null;
    }
    return _project.mediaItemById(clip.mediaItemId);
  }

  @override
  void dispose() {
    _disposed = true;
    _audioLevelService.dispose();
    if (_isExporting) {
      ffmpegService.cancelActiveExport();
    }
    if (_isOptimizingPreview) {
      ffmpegService.cancelActivePreviewProxy();
    }
    _stopGapPlaybackTimer();
    super.dispose();
  }

  @override
  void notifyListeners() {
    // Native work can complete after the editor route has been closed.
    if (!_disposed) super.notifyListeners();
  }

  void _pushHistory([TgiProject? snapshot]) =>
      _history.record(snapshot ?? _project);
  void _clearHistory() => _history.clear();

  void beginInteractiveEdit() {
    _interactiveEditBaseProject ??= _project;
  }

  void commitInteractiveEdit() {
    final base = _interactiveEditBaseProject;
    _interactiveEditBaseProject = null;
    if (base == null || identical(base, _project)) {
      return;
    }
    _pushHistory(base);
    notifyListeners();
  }

  void _clearTrimPreviewState() {
    _trimPreviewBaseProject = null;
  }

  void _restoreTrimPreviewBase() {
    final baseProject = _trimPreviewBaseProject;
    if (baseProject == null) {
      return;
    }
    _project = baseProject;
    _clearTrimPreviewState();
  }

  void undo() {
    _restoreTrimPreviewBase();
    if (_history.undoStack.isEmpty) {
      return;
    }

    _project = _history.undo(_project);
    _resetTransientTimelineState();
    notifyListeners();
  }

  void redo() {
    _restoreTrimPreviewBase();
    if (_history.redoStack.isEmpty) {
      return;
    }

    _project = _history.redo(_project);
    _resetTransientTimelineState();
    notifyListeners();
  }

  void _resetTransientTimelineState() {
    _clearTrimPreviewState();
    _selectedMediaItemId = null;
    _selectedTimelineGroupId = null;
    _selectedTimelineGroupIds.clear();
    _isCutMode = false;
    _timelinePlaybackActive = false;
    _stopGapPlaybackTimer();
    _errorMessage = null;
    _statusMessage = null;
    if (_playheadPosition > _project.timelineDuration) {
      _playheadPosition = _project.timelineDuration;
    }
  }

  MediaItem? get selectedMediaItem {
    final selectedId = _selectedMediaItemId;
    if (selectedId == null) {
      return null;
    }

    return _project.mediaItemById(selectedId);
  }

  domain.Clip? get activeTimelineClip {
    return _activeMainVideoClipAt(_playheadPosition);
  }

  MediaItem? get timelinePreviewMediaItem {
    final clip = activeTimelineClip;
    if (clip == null) {
      return null;
    }
    return _mediaItemForPreview(clip.mediaItemId);
  }

  MediaItem? get previewMediaItem {
    if (_project.hasTimelineClips) {
      final timelineItem = timelinePreviewMediaItem;
      if (timelineItem != null) {
        return timelineItem;
      }
      if (_hasExportableTimelineClips) {
        return null;
      }
    }
    final item = selectedMediaItem;
    return item == null ? null : _withPreviewProxy(item);
  }

  TimelineVideoPreviewClip? get nextVideoPreviewClip {
    final activeClip = activeTimelineClip;
    if (activeClip == null) {
      return null;
    }

    final nextClip = _nextVideoClipAfterActiveClip(activeClip);
    if (nextClip == null) {
      return null;
    }

    final mediaItem = _mediaItemForPreview(nextClip.mediaItemId);
    if (mediaItem == null || mediaItem.type != MediaType.video) {
      return null;
    }

    return TimelineVideoPreviewClip(
      clipId: nextClip.id,
      mediaItem: mediaItem,
      sourcePosition: nextClip.sourceStart,
      timelineStart: nextClip.timelineStart,
      playbackSpeed: nextClip.playbackSpeed,
    );
  }

  MediaItem? get _previewOptimizationTarget {
    final selected = selectedMediaItem;
    if (selected != null && selected.type == MediaType.video) {
      return selected;
    }

    final clip = activeTimelineClip;
    if (clip == null) {
      return null;
    }
    final item = _project.mediaItemById(clip.mediaItemId);
    return item?.type == MediaType.video ? item : null;
  }

  MediaItem? _mediaItemForPreview(String mediaItemId) {
    final item = _project.mediaItemById(mediaItemId);
    return item == null ? null : _withPreviewProxy(item);
  }

  MediaItem _withPreviewProxy(MediaItem item) {
    if (!_usePreviewProxies) return item;
    final proxyPath = item.previewProxyPath;
    if (item.type != MediaType.video ||
        proxyPath == null ||
        proxyPath.isEmpty ||
        !File(proxyPath).existsSync()) {
      return item;
    }
    return item.copyWith(filePath: proxyPath, width: 960, height: 540);
  }

  domain.Clip? get activeImageOverlayClip {
    final clip = _selectedImageOverlayClip ?? _playheadImageClip;
    if (clip == null) {
      return null;
    }

    final mediaItem = _project.mediaItemById(clip.mediaItemId);
    return mediaItem?.type == MediaType.image ? clip : null;
  }

  domain.Clip? get activeVideoOverlayClip {
    final clip = _selectedVideoOverlayClip ?? _playheadVideoOverlayClip;
    if (clip == null) {
      return null;
    }

    final mediaItem = _project.mediaItemById(clip.mediaItemId);
    return mediaItem?.type == MediaType.video ? clip : null;
  }

  List<TimelineVideoOverlayPreviewClip> get allVideoOverlaysAtPlayhead {
    final activeClipId =
        (_selectedVideoOverlayClip ?? _playheadVideoOverlayClip)?.id;
    final entries = <TimelineVideoOverlayPreviewClip>[];

    for (final clip in _pipVideoClipsAt(_playheadPosition)) {
      final mediaItem = _mediaItemForPreview(clip.mediaItemId);
      if (mediaItem == null || mediaItem.type != MediaType.video) {
        continue;
      }
      final entry = TimelineVideoOverlayPreviewClip(
        clip: clip,
        mediaItem: mediaItem,
        sourcePosition: _sourcePositionForTimelineClip(
          clip,
          _playheadPosition,
          reverseAware: true,
        ),
        opacity: keyframedOpacityForClip(clip),
        isActive: clip.id == activeClipId,
      );
      entries.add(entry);
    }
    return List.unmodifiable(entries);
  }

  domain.Clip? get _selectedVideoOverlayClip {
    final selectedGroupId = _selectedTimelineGroupId;
    if (selectedGroupId == null) {
      return null;
    }
    for (final clip in _pipVideoClipsAt(_playheadPosition)) {
      if (clip.timelineGroupId == selectedGroupId) {
        return clip;
      }
    }
    return null;
  }

  domain.Clip? get _playheadVideoOverlayClip {
    final clips = _pipVideoClipsAt(_playheadPosition);
    return clips.isEmpty ? null : clips.last;
  }

  domain.Clip? _activeMainVideoClipAt(Duration position) {
    final mainTrackId = _mainVideoTrackId();
    if (mainTrackId == null) {
      return null;
    }
    final track = _project.trackById(mainTrackId);
    if (track == null || track.isHidden) {
      return null;
    }
    for (final clip in track.clips.where(
      (clip) => clip.trackType == TrackType.video,
    )) {
      if (_clipContainsTimelinePosition(clip, position)) {
        return clip;
      }
    }
    return null;
  }

  List<domain.Clip> _pipVideoClipsAt(Duration position) {
    final base = activeTimelineClip?.id;
    return _project
        .visualClipsAt(position)
        .where((clip) => clip.trackType == TrackType.video && clip.id != base)
        .toList();
  }

  String? _mainVideoTrackId() {
    return _project.baseVideoTrack?.id;
  }

  domain.Clip? get _selectedImageOverlayClip {
    final selectedGroupId = _selectedTimelineGroupId;
    if (selectedGroupId == null) {
      return null;
    }
    for (final track in _project.tracks) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.image) continue;
        if (clip.timelineGroupId == selectedGroupId) {
          final mediaItem = _project.mediaItemById(clip.mediaItemId);
          if (mediaItem?.type == MediaType.image) {
            return clip;
          }
        }
      }
    }
    return null;
  }

  domain.Clip? get _playheadImageClip {
    return _project.clipAt(_playheadPosition, trackType: TrackType.image);
  }

  List<domain.Clip> get allImageOverlaysAtPlayhead {
    final activeClipId = (_selectedImageOverlayClip ?? _playheadImageClip)?.id;
    final inactive = <domain.Clip>[];
    final active = <domain.Clip>[];

    for (final track in _project.tracks.reversed) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.image) continue;
        if (!_clipContainsTimelinePosition(clip, _playheadPosition)) {
          continue;
        }
        if (clip.id == activeClipId) {
          active.add(clip);
        } else {
          inactive.add(clip);
        }
      }
    }

    return _project
        .visualClipsAt(_playheadPosition)
        .where((clip) => clip.trackType == TrackType.image)
        .toList();
  }

  MediaItem? get imageOverlayMediaItem {
    final clip = activeImageOverlayClip;
    if (clip == null) {
      return null;
    }
    return _project.mediaItemById(clip.mediaItemId);
  }

  List<domain.Clip> get allTextOverlaysAtPlayhead {
    final activeClipId = (_selectedTextOverlayClip ?? _playheadTextClip)?.id;
    final inactive = <domain.Clip>[];
    final active = <domain.Clip>[];

    for (final track in _project.tracks.reversed) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.text) continue;
        if (!_clipContainsTimelinePosition(clip, _playheadPosition)) {
          continue;
        }
        if (clip.id == activeClipId) {
          active.add(clip);
        } else {
          inactive.add(clip);
        }
      }
    }

    return _project
        .visualClipsAt(_playheadPosition)
        .where((clip) => clip.trackType == TrackType.text)
        .toList();
  }

  domain.Clip? get _selectedTextOverlayClip {
    final selectedGroupId = _selectedTimelineGroupId;
    if (selectedGroupId == null) {
      return null;
    }
    for (final track in _project.tracks) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.text) continue;
        if (clip.timelineGroupId == selectedGroupId) {
          return clip;
        }
      }
    }
    return null;
  }

  domain.Clip? get _playheadTextClip {
    return _project.clipAt(_playheadPosition, trackType: TrackType.text);
  }

  double get activeAudioVolume {
    final activeGroupId = activeTimelineClip?.timelineGroupId;
    if (activeGroupId == null) {
      return 1;
    }
    for (final track in _project.tracks) {
      if (!_audioTrackIsAudible(track)) {
        continue;
      }
      for (final clip in track.clips) {
        if (clip.timelineGroupId == activeGroupId &&
            _clipContainsTimelinePosition(clip, _playheadPosition)) {
          return _keyframedClipValueAtPlayhead(
                clip,
                domain.ClipKeyframeProperty.volume,
              ) *
              track.volume *
              previewOpacityForClip(clip);
        }
      }
    }
    return 0;
  }

  double get activeVideoPlaybackSpeed {
    return _selectedOrActiveVideoClip?.playbackSpeed ?? 1;
  }

  double get activeVideoPreviewOpacity {
    final clip = activeTimelineClip;
    return clip == null ? 1 : keyframedOpacityForClip(clip);
  }

  double get previewPlaybackSpeed {
    return activeTimelineClip?.playbackSpeed ?? 1;
  }

  double previewOpacityForClip(domain.Clip clip) {
    return _clipFadeOpacityAt(clip, _playheadPosition);
  }

  double keyframedOpacityForClip(domain.Clip clip) {
    return _keyframedClipValueAtPlayhead(
          clip,
          domain.ClipKeyframeProperty.opacity,
        ) *
        previewOpacityForClip(clip);
  }

  double textAnimationProgressForClip(domain.Clip clip) {
    if (clip.trackType != TrackType.text ||
        clip.duration <= Duration.zero ||
        !_clipContainsTimelinePosition(clip, _playheadPosition)) {
      return 1;
    }
    final elapsed = _playheadPosition - clip.timelineStart;
    final introDuration = clip.duration < const Duration(milliseconds: 600)
        ? clip.duration
        : const Duration(milliseconds: 600);
    if (introDuration <= Duration.zero) {
      return 1;
    }
    return (elapsed.inMicroseconds / introDuration.inMicroseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  bool get canChangeVideoPlaybackSpeed {
    return _selectedOrActiveVideoClip != null;
  }

  Duration get previewSourcePosition {
    final clip = activeTimelineClip;
    if (clip == null) {
      return Duration.zero;
    }

    return _sourcePositionForTimelineClip(
      clip,
      _playheadPosition,
      reverseAware: true,
    );
  }

  Future<void> importVideo() =>
      _importVideo(autoInsertWhenTimelineEmpty: false);

  Future<void> importVideoAndAddToEmptyTimeline() =>
      _importVideo(autoInsertWhenTimelineEmpty: true);

  Future<void> importMediaAndAddToEmptyTimeline() =>
      _importVideo(autoInsertWhenTimelineEmpty: true);

  Future<void> _importVideo({required bool autoInsertWhenTimelineEmpty}) async {
    if (_isImporting) {
      return;
    }

    _isImporting = true;
    _errorMessage = null;
    _statusMessage = 'Preparando midia para edicao...';
    notifyListeners();

    var importedMediaItems = const <MediaItem>[];
    try {
      final mediaItems = await mediaImportService.importMediaFiles();
      importedMediaItems = mediaItems;
      if (mediaItems.isNotEmpty) {
        final timelineWasEmpty = !_project.tracks.any(
          (track) => track.clips.isNotEmpty,
        );
        final previousClipIds = _timelineClipIds(_project);
        var nextProject = _project;
        for (final mediaItem in mediaItems) {
          nextProject = nextProject.addMediaItem(mediaItem);
        }
        MediaItem? autoInsertedItem;
        if (autoInsertWhenTimelineEmpty && timelineWasEmpty) {
          for (final mediaItem in mediaItems) {
            if (mediaItem.type == MediaType.video ||
                mediaItem.type == MediaType.image) {
              autoInsertedItem = mediaItem;
              nextProject = nextProject.addMediaItemToTimeline(
                mediaItem,
                timelineStart: Duration.zero,
              );
              break;
            }
          }
        }
        _commitProjectMutation(nextProject);
        final selectedItem = autoInsertedItem ?? mediaItems.last;
        _selectedMediaItemId = selectedItem.id;
        for (final mediaItem in mediaItems) {
          _ensureAudioWaveform(mediaItem);
        }
        if (autoInsertedItem != null) {
          final addedClip = _addedClipForItem(
            _project,
            previousClipIds,
            autoInsertedItem.id,
            autoInsertedItem.type == MediaType.image
                ? TrackType.image
                : TrackType.video,
          );
          _selectedTimelineGroupId = addedClip?.timelineGroupId;
          _setSelectedTimelineGroups(
            _selectedTimelineGroupId == null
                ? const {}
                : {_selectedTimelineGroupId!},
          );
          _playheadPosition = Duration.zero;
          final importedLabel = autoInsertedItem.type == MediaType.image
              ? 'Imagem adicionada'
              : 'Vídeo adicionado';
          _statusMessage =
              '$importedLabel à timeline: ${autoInsertedItem.name}';
        } else {
          _statusMessage = mediaItems.length == 1
              ? 'Importado no Media Pool: ${selectedItem.name}'
              : 'Importados no Media Pool: ${mediaItems.length} arquivos';
        }
      }
    } catch (error) {
      _errorMessage = _cleanError(error);
    } finally {
      _isImporting = false;
      notifyListeners();
    }
    _scheduleAutomaticPreviewOptimization(importedMediaItems);
  }

  Future<MediaItem?> importMediaFileFromPath(
    String path, {
    String? displayName,
  }) async {
    if (_isImporting) {
      return null;
    }

    _isImporting = true;
    _errorMessage = null;
    _statusMessage = 'Preparando midia para edicao...';
    notifyListeners();

    MediaItem? result;
    try {
      final importedItem = await mediaImportService.importFile(path);
      final cleanDisplayName = displayName?.trim();
      final mediaItem = cleanDisplayName == null || cleanDisplayName.isEmpty
          ? importedItem
          : importedItem.copyWith(name: cleanDisplayName);
      final nextProject = _project.addMediaItem(mediaItem);
      if (!identical(nextProject, _project)) {
        _pushHistory();
        _project = nextProject;
      }
      _selectedMediaItemId = mediaItem.id;
      _ensureAudioWaveform(mediaItem);
      _statusMessage = 'Importado no Media Pool: ${mediaItem.name}';
      result = mediaItem;
    } catch (error) {
      _errorMessage = _cleanError(error);
    } finally {
      _isImporting = false;
      notifyListeners();
    }
    if (result != null) {
      _scheduleAutomaticPreviewOptimization([result]);
    }
    return result;
  }

  Future<MediaItem?> importAudioFileFromPathToNewTimelineTrack(
    String path, {
    String? displayName,
    String statusPrefix = 'Efeito sonoro adicionado',
  }) async {
    if (_isImporting) {
      return null;
    }

    _isImporting = true;
    _errorMessage = null;
    _statusMessage = 'Preparando audio para edicao...';
    notifyListeners();

    try {
      final importedItem = await mediaImportService.importFile(path);
      final cleanDisplayName = displayName?.trim();
      final mediaItem = cleanDisplayName == null || cleanDisplayName.isEmpty
          ? importedItem
          : importedItem.copyWith(name: cleanDisplayName);
      if (mediaItem.type != MediaType.audio) {
        throw Exception('O arquivo importado nao e um audio.');
      }

      final start = _normalizeTimelinePosition(_playheadPosition);
      final previousClipIds = _timelineClipIds(_project);
      var nextProject = _project.addMediaItem(mediaItem);
      nextProject = nextProject.addMediaItemToTimeline(
        mediaItem,
        timelineStart: start,
        forceNewAudioTrack: true,
      );
      if (!identical(nextProject, _project)) {
        _pushHistory();
        _project = nextProject;
      }

      _selectedMediaItemId = mediaItem.id;
      _ensureAudioWaveform(mediaItem);
      _playheadPosition = start;
      final addedClip = _addedClipForItem(
        _project,
        previousClipIds,
        mediaItem.id,
        TrackType.audio,
      );
      _selectedTimelineGroupId =
          addedClip?.timelineGroupId ??
          _project.clipAt(start, trackType: TrackType.audio)?.timelineGroupId;
      _setSelectedTimelineGroups(
        _selectedTimelineGroupId == null
            ? const {}
            : {_selectedTimelineGroupId!},
      );
      _statusMessage = '$statusPrefix: ${mediaItem.name}';
      return mediaItem;
    } catch (error) {
      _errorMessage = _cleanError(error);
      return null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> optimizePreview() async {
    if (_isImporting || _isExporting || _isOptimizingPreview) {
      return;
    }

    final target = _previewOptimizationTarget;
    if (target == null) {
      _errorMessage = 'Selecione um video para otimizar o preview.';
      _statusMessage = null;
      notifyListeners();
      return;
    }
    await _optimizePreviewTarget(target, automatic: false);
  }

  Future<void> _optimizePreviewTarget(
    MediaItem target, {
    required bool automatic,
  }) async {
    if (_isImporting || _isExporting || _isOptimizingPreview || _disposed) {
      return;
    }
    _isOptimizingPreview = true;
    _previewOptimizationProgress = 0;
    _previewOptimizationStartedAt = DateTime.now();
    _previewOptimizationRemaining = null;
    _previewOptimizationAutomatic = automatic;
    _previewOptimizationCancellationRequested = false;
    _previewOptimizationTargetName = target.name;
    _errorMessage = null;
    _statusMessage = automatic
        ? 'Criando proxy automatico: ${target.name}'
        : 'Otimizando preview: ${target.name}';
    notifyListeners();

    try {
      final proxyPath = await ffmpegService.createPreviewProxy(
        target,
        onProgress: (progress) {
          _previewOptimizationProgress = progress.clamp(0.0, 1.0);
          final startedAt = _previewOptimizationStartedAt;
          if (startedAt != null && _previewOptimizationProgress >= 0.03) {
            final elapsed = DateTime.now().difference(startedAt);
            final remainingMicros =
                elapsed.inMicroseconds *
                (1 - _previewOptimizationProgress) /
                _previewOptimizationProgress;
            _previewOptimizationRemaining = Duration(
              microseconds: remainingMicros
                  .round()
                  .clamp(0, const Duration(hours: 12).inMicroseconds)
                  .toInt(),
            );
          }
          notifyListeners();
        },
      );
      final nextProject = _project.updateMediaItemPreviewProxy(
        target.id,
        previewProxyPath: proxyPath,
      );
      if (!identical(nextProject, _project)) {
        if (!automatic) {
          _pushHistory();
        }
        _project = nextProject;
      }
      if (!automatic) {
        _selectedMediaItemId = target.id;
      }
      _previewOptimizationProgress = 1;
      _previewOptimizationRemaining = Duration.zero;
      _statusMessage = automatic
          ? 'Proxy automatico pronto: ${target.name}'
          : 'Preview otimizado: ${target.name}';
    } catch (error) {
      if (_previewOptimizationCancellationRequested) {
        _errorMessage = null;
        _statusMessage = 'Otimizacao do preview cancelada.';
      } else {
        _errorMessage = _cleanError(error);
        _statusMessage = null;
      }
    } finally {
      _isOptimizingPreview = false;
      _previewOptimizationStartedAt = null;
      _previewOptimizationAutomatic = false;
      _previewOptimizationCancellationRequested = false;
      _previewOptimizationTargetName = null;
      notifyListeners();
    }
  }

  void cancelPreviewOptimization() {
    if (!_isOptimizingPreview || _previewOptimizationCancellationRequested) {
      return;
    }
    _previewOptimizationCancellationRequested = true;
    _statusMessage = 'Cancelando otimizacao do preview...';
    ffmpegService.cancelActivePreviewProxy();
    notifyListeners();
  }

  void optimizeHeavyPreviewMedia() {
    _scheduleAutomaticPreviewOptimization(_project.mediaPool);
  }

  void _scheduleAutomaticPreviewOptimization(Iterable<MediaItem> items) {
    final targets = items.where(shouldAutomaticallyOptimizePreview).toList();
    if (targets.isEmpty || _disposed) {
      return;
    }
    unawaited(_runAutomaticPreviewOptimization(targets));
  }

  Future<void> _runAutomaticPreviewOptimization(List<MediaItem> targets) async {
    await Future<void>.delayed(Duration.zero);
    for (final target in targets) {
      if (_disposed || _isImporting || _isExporting) {
        return;
      }
      final current = _project.mediaItemById(target.id);
      if (current == null || !shouldAutomaticallyOptimizePreview(current)) {
        continue;
      }
      await _optimizePreviewTarget(current, automatic: true);
    }
  }

  void selectMediaItem(MediaItem item) {
    if (_selectedMediaItemId == item.id) {
      return;
    }

    _selectedMediaItemId = item.id;
    notifyListeners();
  }

  void removeMediaItem(String mediaItemId) {
    final item = _project.mediaItemById(mediaItemId);
    if (item == null) {
      return;
    }
    if (_project.mediaItemIsUsed(mediaItemId)) {
      _errorMessage =
          'Remova os clipes que usam este arquivo antes de remove-lo do Media Pool.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    final nextProject = _project.removeMediaItem(mediaItemId);
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    if (_selectedMediaItemId == mediaItemId) {
      _selectedMediaItemId = null;
    }
    _audioWaveformsByMediaId.remove(mediaItemId);
    _audioWaveformLoadsInFlight.remove(mediaItemId);
    _errorMessage = null;
    _statusMessage = 'Removido do Media Pool: ${item.name}';
    notifyListeners();
  }

  void relinkMedia(List<MediaRelinkResult> relinked) {
    final validRelinks = [
      for (final result in relinked)
        if (_project.mediaItemById(result.mediaItemId) != null &&
            _project.mediaItemById(result.mediaItemId)!.filePath !=
                result.newPath)
          result,
    ];
    if (validRelinks.isEmpty) {
      return;
    }

    _pushHistory();
    _project = ProjectIOService().applyRelinkedMedia(_project, validRelinks);
    for (final result in validRelinks) {
      _audioWaveformsByMediaId.remove(result.mediaItemId);
      _audioWaveformLoadsInFlight.remove(result.mediaItemId);
      final item = _project.mediaItemById(result.mediaItemId);
      if (item != null) {
        _ensureAudioWaveform(item);
      }
    }
    _selectedMediaItemId = validRelinks.first.mediaItemId;
    _errorMessage = null;
    _statusMessage = validRelinks.length == 1
        ? 'Midia religada: ${validRelinks.single.originalFilename}'
        : 'Midias religadas: ${validRelinks.length} arquivos';
    notifyListeners();
  }

  void addTimelineTrack(TrackType type) {
    final nextProject = _project.addTimelineTrack(type);
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void appendMediaItemToTimeline(MediaItem item) {
    final mainTrackId = _mainVideoTrackId();
    var end = Duration.zero;
    for (final track in _project.tracks) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.timelineEnd > end) end = clip.timelineEnd;
      }
    }
    addMediaItemToTimeline(
      item,
      end,
      targetTrackId: item.type == MediaType.video ? mainTrackId : null,
    );
  }

  void addMediaItemToTimeline(
    MediaItem item,
    Duration timelineStart, {
    String? targetTrackId,
    bool forceNewVideoTrack = false,
    bool forceNewAudioTrack = false,
    bool insert = false,
  }) {
    if (!_project.mediaPool.any((mediaItem) => mediaItem.id == item.id)) {
      _errorMessage = 'O item n\u00E3o existe no Media Pool deste projeto.';
      notifyListeners();
      return;
    }

    final start = _normalizeTimelinePosition(timelineStart);
    final targetTrack = targetTrackId == null
        ? null
        : _project.trackById(targetTrackId);
    if (targetTrack?.isLocked ?? false) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final previousClipIds = _timelineClipIds(_project);
    final imageFit = item.type == MediaType.image && !_hasVisibleVideoAt(start)
        ? domain.ImageClipFit.cover
        : domain.ImageClipFit.overlay;
    final nextProject = insert && targetTrackId != null
        ? _project.insertMedia(
            item,
            timelineStart: start,
            targetTrackId: targetTrackId,
            imageFit: imageFit,
            overlayX: imageFit == domain.ImageClipFit.cover ? .5 : 1,
            overlayY: imageFit == domain.ImageClipFit.cover ? .5 : 0,
            overlayScale: imageFit == domain.ImageClipFit.cover ? 4 : 1,
          )
        : _project.addMediaItemToTimeline(
            item,
            timelineStart: start,
            targetTrackId: targetTrackId,
            forceNewVideoTrack: forceNewVideoTrack,
            forceNewAudioTrack: forceNewAudioTrack,
            imageFit: imageFit,
            overlayX: imageFit == domain.ImageClipFit.cover ? 0.5 : 1,
            overlayY: imageFit == domain.ImageClipFit.cover ? 0.5 : 0,
            overlayScale: imageFit == domain.ImageClipFit.cover ? 4 : 1,
          );
    if (identical(nextProject, _project)) {
      _errorMessage = insert
          ? 'Inserção cancelada. Solte em uma borda livre e destrave as pistas vinculadas.'
          : 'Destino ocupado ou incompatível. Use outra camada ou segure Shift para inserir entre clipes.';
      notifyListeners();
      return;
    }

    _pushHistory();
    _project = nextProject;
    _ensureAudioWaveform(item);
    _selectedMediaItemId = item.id;
    _playheadPosition = start;
    final selectedTrackType = switch (item.type) {
      MediaType.image => TrackType.image,
      MediaType.audio => TrackType.audio,
      MediaType.text => TrackType.text,
      MediaType.video => TrackType.video,
    };
    final addedClip = _addedClipForItem(
      _project,
      previousClipIds,
      item.id,
      selectedTrackType,
    );
    _selectedTimelineGroupId =
        addedClip?.timelineGroupId ??
        _project.clipAt(start, trackType: selectedTrackType)?.timelineGroupId;
    _setSelectedTimelineGroups(
      _selectedTimelineGroupId == null ? const {} : {_selectedTimelineGroupId!},
    );
    _errorMessage = null;
    notifyListeners();
  }

  void addTextToTimeline(
    String text, {
    Duration duration = const Duration(seconds: 5),
    String fontFamily = NewTextStyle.fontFamily,
    double fontSize = 48,
    int textColor = 0xFFFFFFFF,
    int backgroundColor = NewTextStyle.backgroundColor,
    double opacity = 1,
    domain.TextClipAnimation textAnimation = domain.TextClipAnimation.none,
    bool registerAsCaption = false,
  }) {
    final content = text.trim();
    if (content.isEmpty) {
      _errorMessage = 'Digite um texto para adicionar.';
      notifyListeners();
      return;
    }

    final start = _normalizeTimelinePosition(_playheadPosition);
    final previousClipIds = _timelineClipIds(_project);
    final nextProject = _commandProject('add_text', {
      'text': content,
      'is_caption': registerAsCaption,
      'timeline_start': start.inMicroseconds / 1e6,
      'duration': duration.inMicroseconds / 1e6,
      'font_family': fontFamily,
      'font_size': fontSize,
      'text_color': textColor,
      'background_color': backgroundColor,
      'opacity': opacity,
      'animation': textAnimation.name,
    });
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    final addedClip = _addedClipForTrackType(
      _project,
      previousClipIds,
      TrackType.text,
    );
    _selectedMediaItemId = null;
    _selectedTimelineGroupId = addedClip?.timelineGroupId;
    _setSelectedTimelineGroups(
      _selectedTimelineGroupId == null ? const {} : {_selectedTimelineGroupId!},
    );
    _playheadPosition = start;
    _errorMessage = null;
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void addAutomaticCaptionsFromText(
    String transcript, {
    int wordsPerCaption = 5,
  }) {
    final captions = _captionTiming.captionChunks(transcript, wordsPerCaption);
    if (captions.isEmpty) {
      _errorMessage = 'Cole uma transcricao para gerar legendas.';
      notifyListeners();
      return;
    }

    final start = _normalizeTimelinePosition(_playheadPosition);
    final remainingTimeline = _project.timelineDuration > start
        ? _project.timelineDuration - start
        : Duration.zero;
    final preferredTotal = _captionDefaultDuration * captions.length;
    final usableTotal = remainingTimeline >= _captionMinDuration
        ? remainingTimeline
        : preferredTotal;
    final captionDuration = _captionTiming.clampCaptionDuration(
      Duration(
        milliseconds: (usableTotal.inMilliseconds / captions.length).round(),
      ),
    );
    final previousClipIds = _timelineClipIds(_project);
    var nextProject = _project;
    for (var index = 0; index < captions.length; index++) {
      nextProject = nextProject.addTextClipToTimeline(
        text: captions[index].toUpperCase(),
        isCaption: true,
        timelineStart: start + captionDuration * index,
        duration: captionDuration,
        fontFamily: NewTextStyle.fontFamily,
        fontSize: 68,
        textColor: 0xFFFFFFFF,
        backgroundColor: NewTextStyle.backgroundColor,
        opacity: 1,
        textAnimation: domain.TextClipAnimation.pop,
      );
    }
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    final addedTextClips = _addedClipsForTrackType(
      _project,
      previousClipIds,
      TrackType.text,
    );
    final selectedClip = addedTextClips.isEmpty ? null : addedTextClips.last;
    _selectedMediaItemId = null;
    _selectedTimelineGroupId = selectedClip?.timelineGroupId;
    _setSelectedTimelineGroups(
      _selectedTimelineGroupId == null ? const {} : {_selectedTimelineGroupId!},
    );
    _playheadPosition = start;
    _errorMessage = null;
    _statusMessage = 'Legendas automaticas criadas: ${captions.length} blocos';
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  Future<void> generateAutomaticCaptions({
    String? languageCode,
    String modelName = '',
    int maxCharsPerCue = 44,
    String captionFontFamily = NewTextStyle.fontFamily,
    double captionFontSize = 52,
    int captionTextColor = 0xFFFFFFFF,
    int captionBackgroundColor = NewTextStyle.backgroundColor,
    double captionOpacity = 1,
    domain.TextClipAnimation captionAnimation = domain.TextClipAnimation.fade,
  }) async {
    if (_isGeneratingCaptions) {
      return;
    }

    final sourceClips = _captionSourceVideoClips;
    if (sourceClips.isEmpty) {
      _errorMessage =
          'Selecione um clipe de video na timeline para gerar legendas.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    final captionSources = <({domain.Clip clip, MediaItem mediaItem})>[];
    var skippedWithoutAudio = 0;
    for (final clip in sourceClips) {
      final mediaItem = _project.mediaItemById(clip.mediaItemId);
      if (mediaItem == null || mediaItem.type != MediaType.video) {
        continue;
      }
      if (!mediaItem.hasAudio) {
        skippedWithoutAudio++;
        continue;
      }
      captionSources.add((clip: clip, mediaItem: mediaItem));
    }
    if (captionSources.isEmpty) {
      _errorMessage = sourceClips.length == 1
          ? 'O video selecionado nao tem trilha de audio.'
          : 'Os videos selecionados nao tem trilha de audio.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    _isGeneratingCaptions = true;
    _captionProgress = 0;
    _captionProgressMessage = 'Preparando audio';
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      final mediaItemsById = <String, MediaItem>{
        for (final source in captionSources)
          source.mediaItem.id: source.mediaItem,
      };
      final alignedCuesByMediaId = <String, List<CaptionCue>>{};
      final uniqueMediaItems = mediaItemsById.values.toList(growable: false);
      for (var index = 0; index < uniqueMediaItems.length; index++) {
        final mediaItem = uniqueMediaItems[index];
        final sourceCues = await autoCaptionService.generateCaptionsForMedia(
          mediaItem,
          languageCode: languageCode,
          modelName: modelName,
          maxCharsPerCue: maxCharsPerCue,
          onProgress: (progress, message) {
            _captionProgress =
                ((index + progress.clamp(0.0, 1.0)) / uniqueMediaItems.length)
                    .clamp(0.0, 0.97)
                    .toDouble();
            _captionProgressMessage = uniqueMediaItems.length == 1
                ? message
                : 'Video ${index + 1}/${uniqueMediaItems.length}: $message';
            notifyListeners();
          },
        );
        _captionProgressMessage = uniqueMediaItems.length == 1
            ? 'Alinhando legendas ao audio'
            : 'Video ${index + 1}/${uniqueMediaItems.length}: alinhando legendas';
        notifyListeners();
        alignedCuesByMediaId[mediaItem.id] = await _alignCaptionCuesToAudio(
          sourceCues,
          mediaItem,
        );
      }

      final mappedTimelineCues = <CaptionCue>[];
      for (final source in captionSources) {
        mappedTimelineCues.addAll(
          _timelineCaptionCuesForClip(
            alignedCuesByMediaId[source.mediaItem.id] ?? const [],
            source.clip,
          ),
        );
      }
      final timelineCues = _captionTiming.resolveCaptionCueOverlaps(
        mappedTimelineCues,
        timelineLimit: _project.timelineDuration,
      );
      if (timelineCues.isEmpty) {
        _errorMessage =
            'A transcricao nao encontrou falas nos trechos selecionados.';
        _statusMessage = null;
        return;
      }

      _addCaptionCuesToTimeline(
        timelineCues,
        fontFamily: captionFontFamily,
        fontSize: captionFontSize,
        textColor: captionTextColor,
        backgroundColor: captionBackgroundColor,
        opacity: captionOpacity,
        textAnimation: captionAnimation,
      );
      _captionProgress = 1;
      _captionProgressMessage = null;
      _statusMessage =
          'Legendas automaticas criadas: ${timelineCues.length} blocos em '
          '${captionSources.length} video${captionSources.length == 1 ? '' : 's'}'
          '${skippedWithoutAudio == 0 ? '' : ' ($skippedWithoutAudio sem audio ignorado${skippedWithoutAudio == 1 ? '' : 's'})'}';
    } catch (error) {
      _errorMessage = _cleanError(error);
      _statusMessage = null;
      _captionProgressMessage = null;
    } finally {
      _isGeneratingCaptions = false;
      notifyListeners();
    }
  }

  Future<void> exportGeneratedCaptions(
    String outputPath,
    SubtitleExportFormat format,
  ) async {
    final cues = generatedCaptionCues;
    if (cues.isEmpty) {
      _errorMessage = 'Gere legendas antes de exportar SRT ou VTT.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    try {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(formatSubtitleCues(cues, format));
      _errorMessage = null;
      _statusMessage = 'Legendas exportadas: $outputPath';
    } catch (error) {
      _errorMessage = _cleanError(error);
      _statusMessage = null;
    }
    notifyListeners();
  }

  void moveTimelineClipGroup(String timelineGroupId, Duration timelineStart) {
    final start = _normalizeTimelinePosition(timelineStart);
    final groupsToMove =
        _selectedTimelineGroupIds.contains(timelineGroupId) &&
            _selectedTimelineGroupIds.length > 1
        ? Set<String>.from(_selectedTimelineGroupIds)
        : {timelineGroupId};
    if (_timelineGroupsTouchLockedTracks(groupsToMove)) {
      _errorMessage = 'Uma das trilhas selecionadas esta travada.';
      notifyListeners();
      return;
    }
    final referenceClip = _clipForTimelineGroup(timelineGroupId, const [
      TrackType.text,
      TrackType.image,
      TrackType.video,
      TrackType.audio,
    ]);
    if (referenceClip == null) {
      return;
    }
    final delta = start - referenceClip.timelineStart;
    final activeGroupId = activeTimelineClip?.timelineGroupId;
    final nextProject = groupsToMove.length > 1
        ? _project.moveTimelineClipGroupsByDelta(groupsToMove, delta: delta)
        : _commandProject('move_clip', {
            'clip_id': referenceClip.id,
            'timeline_start': start.inMicroseconds / 1e6,
          });
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = timelineGroupId;
    _setSelectedTimelineGroups(groupsToMove);
    if (activeGroupId == timelineGroupId || activeGroupId == null) {
      _playheadPosition = start;
    }
    _errorMessage = null;
    notifyListeners();
  }

  void moveTimelineClipToTrack(
    String clipId,
    String targetTrackId,
    Duration timelineStart,
  ) {
    if (_clipIsOnLockedTrack(clipId) ||
        (_project.trackById(targetTrackId)?.isLocked ?? false)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final start = _normalizeTimelinePosition(timelineStart);
    final groups =
        _selectedTimelineGroupIds.contains(
          _findClipById(clipId)?.timelineGroupId,
        )
        ? Set<String>.from(_selectedTimelineGroupIds)
        : null;
    final nextProject = _project.placeClipGroups(
      clipId,
      targetTrackId: targetTrackId,
      timelineStart: start,
      selectedGroups: groups,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _playheadPosition = start;
    _selectedTimelineGroupId = _findClipById(clipId)?.timelineGroupId;
    _setSelectedTimelineGroups(
      groups ??
          (_selectedTimelineGroupId == null
              ? const {}
              : {_selectedTimelineGroupId!}),
    );
    _errorMessage = null;
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void moveTimelineClipToNewTrack(String clipId, Duration timelineStart) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final start = _normalizeTimelinePosition(timelineStart);
    final groups =
        _selectedTimelineGroupIds.contains(
          _findClipById(clipId)?.timelineGroupId,
        )
        ? Set<String>.from(_selectedTimelineGroupIds)
        : null;
    final nextProject = _project.placeClipOnNewTrack(
      clipId,
      start,
      selectedGroups: groups,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _playheadPosition = start;
    _selectedTimelineGroupId = _findClipById(clipId)?.timelineGroupId;
    _setSelectedTimelineGroups(
      groups ??
          (_selectedTimelineGroupId == null
              ? const {}
              : {_selectedTimelineGroupId!}),
    );
    _errorMessage = null;
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void moveImageClipToTrack(
    String clipId,
    String targetTrackId,
    Duration timelineStart,
  ) {
    moveTimelineClipToTrack(clipId, targetTrackId, timelineStart);
  }

  void updateImageOverlayPosition(
    String clipId,
    double overlayX,
    double overlayY,
  ) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateImageClipOverlayPosition(
      clipId,
      overlayX: overlayX,
      overlayY: overlayY,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateVideoOverlayPosition(
    String clipId,
    double overlayX,
    double overlayY,
  ) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateImageClipOverlayPosition(
      clipId,
      overlayX: overlayX,
      overlayY: overlayY,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateVideoOverlayScale(String clipId, double overlayScale) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateImageClipOverlayScale(
      clipId,
      overlayScale: overlayScale,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateImageOverlayScale(String clipId, double overlayScale) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateImageClipOverlayScale(
      clipId,
      overlayScale: overlayScale,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void setImageClipCover(String clipId) {
    _updateImageClipFit(
      clipId,
      imageFit: domain.ImageClipFit.cover,
      overlayX: 0.5,
      overlayY: 0.5,
      overlayScale: 4,
    );
  }

  void setImageClipContain(String clipId) {
    _updateImageClipFit(
      clipId,
      imageFit: domain.ImageClipFit.contain,
      overlayX: 0.5,
      overlayY: 0.5,
      overlayScale: 4,
    );
  }

  void centerImageClip(String clipId) {
    final clip = _findClipById(clipId);
    _updateImageClipFit(
      clipId,
      imageFit: clip?.imageFit ?? domain.ImageClipFit.overlay,
      overlayX: 0.5,
      overlayY: 0.5,
    );
  }

  void resetImageClipLayout(String clipId) {
    _updateImageClipFit(
      clipId,
      imageFit: domain.ImageClipFit.overlay,
      overlayX: 1,
      overlayY: 0,
      overlayScale: 1,
    );
  }

  void _updateImageClipFit(
    String clipId, {
    required domain.ImageClipFit imageFit,
    double? overlayX,
    double? overlayY,
    double? overlayScale,
  }) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateImageClipFit(
      clipId,
      imageFit: imageFit,
      overlayX: overlayX,
      overlayY: overlayY,
      overlayScale: overlayScale,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateTextClipText(String clipId, String text) {
    updateTextClipProperties(clipId, text: text);
  }

  void updateSelectedTextClipProperties({
    String? fontFamily,
    double? fontSize,
    int? textColor,
    int? backgroundColor,
    double? opacity,
    domain.TextClipAnimation? textAnimation,
  }) {
    final clips = _selectedTimelineClipsForType(TrackType.text);
    if (clips.isEmpty) {
      return;
    }
    if (clips.any((clip) => _clipIsOnLockedTrack(clip.id))) {
      _errorMessage = 'Uma das trilhas selecionadas esta travada.';
      notifyListeners();
      return;
    }

    var nextProject = _project;
    for (final clip in clips) {
      nextProject = nextProject.updateTextClipProperties(
        clip.id,
        text: clip.textContent,
        fontFamily: fontFamily,
        fontSize: fontSize,
        textColor: textColor,
        backgroundColor: backgroundColor,
        opacity: opacity,
        textAnimation: textAnimation,
      );
    }
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateTextClipProperties(
    String clipId, {
    required String text,
    String? fontFamily,
    double? fontSize,
    int? textColor,
    int? backgroundColor,
    double? opacity,
    domain.TextClipAnimation? textAnimation,
  }) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final content = text.trim();
    if (content.isEmpty) {
      _errorMessage = 'Digite um texto para adicionar.';
      notifyListeners();
      return;
    }

    final nextProject = _commandProject('set_caption_style', {
      'clip_id': clipId,
      'text': content,
      'font_family': ?fontFamily,
      'font_size': ?fontSize,
      'text_color': ?textColor,
      'background_color': ?backgroundColor,
      'opacity': ?opacity,
      if (textAnimation != null) 'animation': textAnimation.name,
    });
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    final clip = _findClipById(clipId);
    _selectedTimelineGroupId =
        clip?.timelineGroupId ?? _selectedTimelineGroupId;
    _errorMessage = null;
    notifyListeners();
  }

  void updateSelectedTextOverlayPosition({double? overlayX, double? overlayY}) {
    if (overlayX == null && overlayY == null) {
      return;
    }
    final clips = _selectedTimelineClipsForType(TrackType.text);
    if (clips.isEmpty) {
      return;
    }
    if (clips.any((clip) => _clipIsOnLockedTrack(clip.id))) {
      _errorMessage = 'Uma das trilhas selecionadas esta travada.';
      notifyListeners();
      return;
    }

    var nextProject = _project;
    for (final clip in clips) {
      nextProject = nextProject.updateTextClipOverlayPosition(
        clip.id,
        overlayX: (overlayX ?? clip.overlayX).clamp(0.0, 1.0).toDouble(),
        overlayY: (overlayY ?? clip.overlayY).clamp(0.0, 1.0).toDouble(),
      );
    }
    if (identical(nextProject, _project)) {
      return;
    }

    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateTextOverlayPositionForSelection(
    String clipId,
    double overlayX,
    double overlayY,
  ) {
    final clip = _findClipById(clipId);
    if (clip == null || clip.trackType != TrackType.text) {
      return;
    }
    final selectedGroups = _effectiveSelectedTimelineGroupIds();
    if (selectedGroups.length > 1 &&
        selectedGroups.contains(clip.timelineGroupId)) {
      updateSelectedTextOverlayPosition(overlayX: overlayX, overlayY: overlayY);
      return;
    }
    updateTextOverlayPosition(clipId, overlayX, overlayY);
  }

  void updateTextOverlayPosition(
    String clipId,
    double overlayX,
    double overlayY,
  ) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateTextClipOverlayPosition(
      clipId,
      overlayX: overlayX.clamp(0.0, 1.0).toDouble(),
      overlayY: overlayY.clamp(0.0, 1.0).toDouble(),
    );
    if (identical(nextProject, _project)) {
      return;
    }

    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    final clip = _findClipById(clipId);
    _selectedTimelineGroupId =
        clip?.timelineGroupId ?? _selectedTimelineGroupId;
    _errorMessage = null;
    notifyListeners();
  }

  void resizeImageClip(
    String clipId,
    Duration timelineStart,
    Duration duration,
  ) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.resizeImageClip(
      clipId,
      timelineStart: _normalizeTimelinePosition(timelineStart),
      duration: duration,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void previewTimelineClipTrim(
    String clipId, {
    required Duration sourceStart,
    required Duration sourceDuration,
    required Duration previewTimelinePosition,
  }) {
    _logController(
      'trim-preview clip=$clipId '
      'sourceStart=${_formatControllerTime(sourceStart)} '
      'sourceDuration=${_formatControllerTime(sourceDuration)} '
      'previewTimelinePosition=${_formatControllerTime(previewTimelinePosition)}',
    );
    final baseProject = _trimPreviewBaseProject ?? _project;
    final baseClip = _findClipByIdInProject(baseProject, clipId);
    if (baseClip == null) {
      _logController('trim-preview clip=$clipId baseClip=null cancel');
      cancelTimelineClipTrimPreview();
      return;
    }
    if (_clipIsOnLockedTrackInProject(baseProject, clipId)) {
      _logController('trim-preview clip=$clipId blocked=locked-track');
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    _trimPreviewBaseProject ??= _project;
    final nextProject = _commandProject('trim_clip', {
      'clip_id': clipId,
      'source_start': sourceStart.inMicroseconds / 1e6,
      'source_duration': sourceDuration.inMicroseconds / 1e6,
    }, base: baseProject);
    _project = nextProject;
    final updatedClip =
        _findClipByIdInProject(nextProject, clipId) ??
        _clipForTimelineGroupInProject(
          nextProject,
          baseClip.timelineGroupId,
          const [TrackType.video, TrackType.audio],
        );
    _selectedTimelineGroupId =
        updatedClip?.timelineGroupId ?? baseClip.timelineGroupId;
    _setSelectedTimelineGroups({_selectedTimelineGroupId!});
    _playheadPosition = _normalizeTimelinePosition(previewTimelinePosition);
    if (_playheadPosition > _project.timelineDuration) {
      _playheadPosition = _project.timelineDuration;
    }
    _timelinePlaybackActive = false;
    _errorMessage = null;
    _syncGapPlaybackTimer();
    _logController(
      'trim-preview applied clip=$clipId '
      'timelineDuration=${_formatControllerTime(_project.timelineDuration)} '
      'playhead=${_formatControllerTime(_playheadPosition)} '
      'clips=${_videoClipDebugSummary()}',
    );
    notifyListeners();
  }

  void commitTimelineClipTrim(
    String clipId, {
    required Duration sourceStart,
    required Duration sourceDuration,
    required Duration previewTimelinePosition,
  }) {
    _logController(
      'trim-commit clip=$clipId '
      'sourceStart=${_formatControllerTime(sourceStart)} '
      'sourceDuration=${_formatControllerTime(sourceDuration)} '
      'previewTimelinePosition=${_formatControllerTime(previewTimelinePosition)}',
    );
    final baseProject = _trimPreviewBaseProject ?? _project;
    final baseClip = _findClipByIdInProject(baseProject, clipId);
    if (baseClip == null) {
      _logController('trim-commit clip=$clipId baseClip=null clear-preview');
      _clearTrimPreviewState();
      return;
    }
    if (_clipIsOnLockedTrackInProject(baseProject, clipId)) {
      _logController('trim-commit clip=$clipId blocked=locked-track');
      _project = baseProject;
      _clearTrimPreviewState();
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final nextProject = _commandProject('trim_clip', {
      'clip_id': clipId,
      'source_start': sourceStart.inMicroseconds / 1e6,
      'source_duration': sourceDuration.inMicroseconds / 1e6,
    }, base: baseProject);
    _clearTrimPreviewState();
    if (identical(nextProject, baseProject)) {
      _logController('trim-commit clip=$clipId no-op');
      _project = baseProject;
      notifyListeners();
      return;
    }

    _pushHistory(baseProject);
    _project = nextProject;
    final updatedClip =
        _findClipByIdInProject(_project, clipId) ??
        _clipForTimelineGroupInProject(
          _project,
          baseClip.timelineGroupId,
          const [TrackType.video, TrackType.audio],
        );
    _selectedTimelineGroupId =
        updatedClip?.timelineGroupId ?? baseClip.timelineGroupId;
    _setSelectedTimelineGroups({_selectedTimelineGroupId!});
    _playheadPosition = _normalizeTimelinePosition(previewTimelinePosition);
    if (_playheadPosition > _project.timelineDuration) {
      _playheadPosition = _project.timelineDuration;
    }
    _timelinePlaybackActive = false;
    _errorMessage = null;
    _syncGapPlaybackTimer();
    _logController(
      'trim-commit applied clip=$clipId '
      'timelineDuration=${_formatControllerTime(_project.timelineDuration)} '
      'playhead=${_formatControllerTime(_playheadPosition)} '
      'clips=${_videoClipDebugSummary()}',
    );
    notifyListeners();
  }

  void cancelTimelineClipTrimPreview() {
    if (_disposed) {
      return;
    }
    final baseProject = _trimPreviewBaseProject;
    if (baseProject == null) {
      _logController('trim-cancel ignored baseProject=null');
      return;
    }
    _logController(
      'trim-cancel restore timelineDuration=${_formatControllerTime(baseProject.timelineDuration)}',
    );
    _project = baseProject;
    _clearTrimPreviewState();
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void updateClipVolume(String clipId, double volume) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _commandProject('set_volume', {
      'clip_id': clipId,
      'volume': volume.clamp(0, 2).toDouble(),
    });
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void setTimelineTrackVolume(String trackId, double volume) {
    final nextProject = _project.setTimelineTrackVolume(trackId, volume);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateClipAudioNoiseReduction(String clipId, double noiseReductionDb) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateClipAudioNoiseReduction(
      clipId,
      noiseReductionDb: noiseReductionDb,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void unlinkSelectedAudioFromVideo() {
    final groupId = _selectedTimelineGroupId;
    if (groupId == null) {
      _errorMessage = 'Selecione um clipe de video com audio.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(groupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final audioBefore = _clipForTimelineGroup(groupId, const [TrackType.audio]);
    final nextProject = _project.unlinkAudioFromTimelineGroup(groupId);
    if (identical(nextProject, _project)) {
      _errorMessage = 'Este clipe nao tem audio pareado para desvincular.';
      notifyListeners();
      return;
    }

    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    final detachedAudio = audioBefore == null
        ? null
        : _findClipByIdInProject(_project, audioBefore.id);
    _setSelectedTimelineGroups(
      detachedAudio == null ? {groupId} : {detachedAudio.timelineGroupId},
    );
    _errorMessage = null;
    _statusMessage = 'Audio desvinculado do video.';
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void relinkSelectedAudioToVideo() {
    final candidate = _selectedAudioVideoRelinkCandidate;
    if (candidate == null) {
      _errorMessage =
          'Selecione um video e audio separados que ainda estejam alinhados.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(candidate.audioTimelineGroupId) ||
        _timelineGroupTouchesLockedTrack(candidate.videoTimelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final nextProject = _project.linkAudioTimelineGroupToVideoGroup(
      audioTimelineGroupId: candidate.audioTimelineGroupId,
      videoTimelineGroupId: candidate.videoTimelineGroupId,
    );
    if (identical(nextProject, _project)) {
      _errorMessage = 'Nao foi possivel vincular estas faixas.';
      notifyListeners();
      return;
    }

    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = candidate.videoTimelineGroupId;
    _setSelectedTimelineGroups({candidate.videoTimelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Audio vinculado ao video.';
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void toggleSelectedAudioVideoLink() {
    if (selectedAudioVideoLinked) {
      unlinkSelectedAudioFromVideo();
      return;
    }
    relinkSelectedAudioToVideo();
  }

  void updateSelectedVideoPlaybackSpeed(double playbackSpeed) {
    final clip = _selectedOrActiveVideoClip;
    if (clip == null) {
      _errorMessage = 'Selecione um clipe de video para mudar a velocidade.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final safeSpeed = playbackSpeed.isFinite && playbackSpeed > 0
        ? playbackSpeed.clamp(0.1, 8.0).toDouble()
        : 1.0;
    final nextDuration = Duration(
      microseconds: (clip.effectiveSourceDuration.inMicroseconds / safeSpeed)
          .round(),
    );
    if (nextDuration != clip.duration &&
        _lockedTimelineContentAtOrAfter(clip.timelineEnd)) {
      _errorMessage =
          'Destrave as trilhas com conteudo posterior para aplicar o ripple.';
      notifyListeners();
      return;
    }

    final nextProject = _commandProject('set_clip_speed', {
      'clip_id': clip.id,
      'speed': playbackSpeed.clamp(0.25, 4).toDouble(),
    });
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    final updatedClip = _videoClipForTimelineGroup(clip.timelineGroupId);
    _selectedTimelineGroupId =
        updatedClip?.timelineGroupId ?? clip.timelineGroupId;
    if (updatedClip != null &&
        !_clipContainsTimelinePosition(updatedClip, _playheadPosition)) {
      _playheadPosition = updatedClip.timelineStart;
    }
    _errorMessage = null;
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void slipTimelineClip(String clipId, Duration sourceDelta) {
    final clip = _findClipByIdInProject(_project, clipId);
    if (clip == null || sourceDelta == Duration.zero) return;
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.slipTimelineClipGroup(
      clip.timelineGroupId,
      sourceDelta: sourceDelta,
    );
    if (identical(nextProject, _project)) {
      _errorMessage =
          'Nao ha mais midia disponivel nessa direcao para fazer Slip.';
      notifyListeners();
      return;
    }
    _pushHistory();
    _project = nextProject;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Slip aplicado sem alterar a posicao do clipe.';
    notifyListeners();
  }

  void slideTimelineClip(String clipId, Duration timelineDelta) {
    final clip = _findClipByIdInProject(_project, clipId);
    if (clip == null || timelineDelta == Duration.zero) return;
    final touchingGroups = <String>{clip.timelineGroupId};
    for (final track in _project.tracks) {
      if (track.kind != TrackKind.visual) continue;
      for (final candidate in track.clips) {
        if (candidate.kind != TrackType.video) continue;
        if (candidate.timelineEnd == clip.timelineStart ||
            candidate.timelineStart == clip.timelineEnd) {
          touchingGroups.add(candidate.timelineGroupId);
        }
      }
    }
    if (_timelineGroupsTouchLockedTracks(touchingGroups)) {
      _errorMessage = 'Destrave os clipes vizinhos para fazer Slide.';
      notifyListeners();
      return;
    }
    final nextProject = _project.slideTimelineClipGroup(
      clip.timelineGroupId,
      timelineDelta: timelineDelta,
    );
    if (identical(nextProject, _project)) {
      _errorMessage =
          'Slide precisa de um clipe encostado antes e outro depois.';
      notifyListeners();
      return;
    }
    _pushHistory();
    _project = nextProject;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Slide aplicado ajustando os clipes vizinhos.';
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void applySelectedVideoSpeedRamp(
    List<double> speedMultipliers, {
    required String label,
  }) {
    final clip = _selectedOrActiveVideoClip;
    if (clip == null) {
      _errorMessage = 'Selecione um clipe de video para aplicar a rampa.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    if (clip.duration < const Duration(milliseconds: 900)) {
      _errorMessage = 'A rampa precisa de um clipe com pelo menos 0,9 segundo.';
      notifyListeners();
      return;
    }
    final nextProject = _project.applyClipGroupSpeedRamp(
      clip.timelineGroupId,
      speedMultipliers: speedMultipliers,
    );
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = clip.timelineGroupId;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _playheadPosition = clip.timelineStart;
    _timelinePlaybackActive = false;
    _stopGapPlaybackTimer();
    _errorMessage = null;
    _statusMessage = '$label aplicada em segmentos sincronizados.';
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void updateSelectedVideoBrightness(double brightness) {
    _updateSelectedVideoLook(brightness: brightness);
  }

  void updateSelectedVideoContrast(double contrast) {
    _updateSelectedVideoLook(contrast: contrast);
  }

  void updateSelectedVideoSaturation(double saturation) {
    _updateSelectedVideoLook(saturation: saturation);
  }

  void updateSelectedVideoExposure(double exposure) {
    _updateSelectedVideoLook(exposure: exposure);
  }

  void updateSelectedVideoHue(double hue) {
    _updateSelectedVideoLook(hue: hue);
  }

  void updateSelectedVideoProfessionalColor({
    double? temperature,
    double? tint,
    double? shadows,
    double? highlights,
    double? curveShadows,
    double? curveMidtones,
    double? curveHighlights,
  }) {
    _updateSelectedVideoLook(
      temperature: temperature,
      tint: tint,
      shadows: shadows,
      highlights: highlights,
      curveShadows: curveShadows,
      curveMidtones: curveMidtones,
      curveHighlights: curveHighlights,
    );
  }

  void resetSelectedVideoProfessionalColor() {
    _updateSelectedVideoLook(
      brightness: 0,
      contrast: 1,
      saturation: 1,
      exposure: 0,
      hue: 0,
      temperature: 0,
      tint: 0,
      shadows: 0,
      highlights: 0,
      curveShadows: 0,
      curveMidtones: 0,
      curveHighlights: 0,
      filterPreset: domain.VideoFilterPreset.none,
    );
  }

  void updateSelectedVideoFilterPreset(domain.VideoFilterPreset preset) {
    _updateSelectedVideoLook(filterPreset: preset);
  }

  void updateSelectedVideoReverse(bool reverseVideo) {
    _updateSelectedVideoLook(reverseVideo: reverseVideo);
    _syncGapPlaybackTimer();
  }

  void updateSelectedVideoChromaKeyEnabled(bool enabled) {
    _updateSelectedVideoLook(chromaKeyEnabled: enabled);
  }

  void updateSelectedVideoChromaKeyColor(int color) {
    _updateSelectedVideoLook(chromaKeyColor: color);
  }

  void updateSelectedVideoChromaKeySimilarity(double similarity) {
    _updateSelectedVideoLook(chromaKeySimilarity: similarity);
  }

  void updateSelectedVideoChromaKeyBlend(double blend) {
    _updateSelectedVideoLook(chromaKeyBlend: blend);
  }

  void updateSelectedVideoStabilization(bool enabled) {
    _updateSelectedVideoLook(stabilizationEnabled: enabled);
  }

  void updateSelectedVideoMask({
    bool? enabled,
    domain.VideoMaskShape? shape,
    domain.VideoMaskEffect? effect,
    double? x,
    double? y,
    double? width,
    double? height,
    double? feather,
    double? intensity,
    bool? inverted,
  }) {
    final clip = _selectedOrActiveVideoClip;
    if (clip == null) {
      _errorMessage = 'Selecione um clipe de video para criar a mascara.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateVideoClipMask(
      clip.id,
      enabled: enabled,
      shape: shape,
      effect: effect,
      x: x,
      y: y,
      width: width,
      height: height,
      feather: feather,
      intensity: intensity,
      inverted: inverted,
    );
    if (identical(nextProject, _project)) return;
    _pushHistory();
    _project = nextProject;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = enabled == true
        ? 'Mascara ativada. Arraste e redimensione no preview.'
        : 'Mascara atualizada.';
    notifyListeners();
  }

  void setSelectedVideoMaskAtPlayhead({required double x, required double y}) {
    final clip = _selectedOrActiveVideoClip;
    if (clip == null ||
        !_clipContainsTimelinePosition(clip, _playheadPosition)) {
      return;
    }
    var nextProject = _project.updateVideoClipMask(
      clip.id,
      enabled: true,
      x: x,
      y: y,
    );
    final time = _normalizedClipTimeAtPlayhead(clip);
    nextProject = nextProject
        .upsertClipKeyframe(
          clip.id,
          property: domain.ClipKeyframeProperty.maskX,
          time: time,
          value: x,
        )
        .upsertClipKeyframe(
          clip.id,
          property: domain.ClipKeyframeProperty.maskY,
          time: time,
          value: y,
        );
    if (identical(nextProject, _project)) return;
    _pushHistory();
    _project = nextProject;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Ponto da mascara salvo no playhead.';
    notifyListeners();
  }

  Future<void> trackSelectedVideoMask() async {
    final clip = _selectedOrActiveVideoClip;
    if (clip == null || !clip.maskEnabled || _isTrackingMask) {
      _errorMessage = 'Ative uma mascara em um clipe de video primeiro.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final media = _project.mediaItemById(clip.mediaItemId);
    if (media == null || media.type != MediaType.video) {
      _errorMessage = 'A midia do clipe nao esta disponivel para rastrear.';
      notifyListeners();
      return;
    }
    _isTrackingMask = true;
    _maskTrackingProgress = 0;
    _errorMessage = null;
    _statusMessage = 'Extraindo quadros para rastreamento...';
    notifyListeners();
    try {
      var batch = await ffmpegService.extractGrayTrackingFrames(
        media.filePath,
        sourceStart: clip.sourceStart,
        sourceDuration: clip.effectiveSourceDuration,
      );
      if (clip.reverseVideo) {
        batch = FfmpegGrayFrameBatch(
          width: batch.width,
          height: batch.height,
          framesPerSecond: batch.framesPerSecond,
          frames: batch.frames.reversed.toList(),
        );
      }
      _maskTrackingProgress = 0.12;
      _statusMessage = 'Rastreando o movimento do alvo...';
      notifyListeners();
      const tracker = MotionMaskTracker();
      final rawPoints = tracker.track(
        batch: batch,
        seedTime: _normalizedClipTimeAtPlayhead(clip),
        seedX: clip.keyframedValue(
          domain.ClipKeyframeProperty.maskX,
          _normalizedClipTimeAtPlayhead(clip),
        ),
        seedY: clip.keyframedValue(
          domain.ClipKeyframeProperty.maskY,
          _normalizedClipTimeAtPlayhead(clip),
        ),
        maskWidth: clip.maskWidth,
        maskHeight: clip.maskHeight,
        onProgress: (progress) {
          _maskTrackingProgress = 0.12 + progress * 0.86;
        },
      );
      final points = tracker.simplify(rawPoints);
      var nextProject = _project
          .clearClipKeyframes(
            clip.id,
            property: domain.ClipKeyframeProperty.maskX,
          )
          .clearClipKeyframes(
            clip.id,
            property: domain.ClipKeyframeProperty.maskY,
          );
      for (final point in points) {
        nextProject = nextProject
            .upsertClipKeyframe(
              clip.id,
              property: domain.ClipKeyframeProperty.maskX,
              time: point.time,
              value: point.x,
            )
            .upsertClipKeyframe(
              clip.id,
              property: domain.ClipKeyframeProperty.maskY,
              time: point.time,
              value: point.y,
            );
      }
      if (!identical(nextProject, _project)) {
        _pushHistory();
        _project = nextProject;
      }
      final confidence = rawPoints.isEmpty
          ? 0.0
          : rawPoints.fold<double>(0, (sum, point) => sum + point.confidence) /
                rawPoints.length;
      _maskTrackingProgress = 1;
      _errorMessage = null;
      _statusMessage =
          'Rastreamento concluido com ${points.length} pontos (${(confidence * 100).round()}% de confianca).';
    } catch (error) {
      _errorMessage = _cleanError(error);
      _statusMessage = null;
    } finally {
      _isTrackingMask = false;
      notifyListeners();
    }
  }

  void clearSelectedMaskTracking() {
    final clip = _selectedOrActiveVideoClip;
    if (clip == null) return;
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project
        .clearClipKeyframes(
          clip.id,
          property: domain.ClipKeyframeProperty.maskX,
        )
        .clearClipKeyframes(
          clip.id,
          property: domain.ClipKeyframeProperty.maskY,
        );
    if (identical(nextProject, _project)) return;
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    _statusMessage = 'Rastreamento da mascara removido.';
    notifyListeners();
  }

  Future<void> attachImageToSelectedMask(String path) async {
    final clip = _selectedOrActiveVideoClip;
    if (clip == null || !clip.maskEnabled) {
      _errorMessage = 'Ative uma mascara em um clipe de video primeiro.';
      _statusMessage = null;
      notifyListeners();
      return;
    }
    final trackingX = clip.keyframesFor(domain.ClipKeyframeProperty.maskX);
    final trackingY = clip.keyframesFor(domain.ClipKeyframeProperty.maskY);
    if (trackingX.isEmpty || trackingY.isEmpty) {
      _errorMessage =
          'Rastreie o objeto antes de adicionar uma imagem seguidora.';
      _statusMessage = null;
      notifyListeners();
      return;
    }
    if (_isImporting ||
        _timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
        _errorMessage = 'A trilha esta travada.';
        notifyListeners();
      }
      return;
    }

    _isImporting = true;
    _errorMessage = null;
    _statusMessage = 'Adicionando imagem ao rastreamento...';
    notifyListeners();
    try {
      final imageItem = await mediaImportService.importFile(path);
      if (imageItem.type != MediaType.image) {
        throw Exception('O arquivo escolhido nao e uma imagem valida.');
      }
      final previousClipIds = _timelineClipIds(_project);
      final startX = clip.keyframedValue(domain.ClipKeyframeProperty.maskX, 0);
      final startY = clip.keyframedValue(domain.ClipKeyframeProperty.maskY, 0);
      final followerScale = math.max(clip.maskWidth, clip.maskHeight) * 3.0;
      var nextProject = _project.addMediaItem(imageItem);
      nextProject = nextProject.addMediaItemToTimeline(
        imageItem,
        timelineStart: clip.timelineStart,
        imageFit: domain.ImageClipFit.trackedOverlay,
        overlayX: startX,
        overlayY: startY,
        overlayScale: followerScale,
        clipDurationOverride: clip.duration,
      );
      final imageClip = _addedClipForItem(
        nextProject,
        previousClipIds,
        imageItem.id,
        TrackType.image,
      );
      if (imageClip == null) {
        throw Exception('Nao foi possivel criar a imagem na timeline.');
      }
      for (final point in trackingX) {
        nextProject = nextProject.upsertClipKeyframe(
          imageClip.id,
          property: domain.ClipKeyframeProperty.overlayX,
          time: point.time,
          value: point.value,
        );
      }
      for (final point in trackingY) {
        nextProject = nextProject.upsertClipKeyframe(
          imageClip.id,
          property: domain.ClipKeyframeProperty.overlayY,
          time: point.time,
          value: point.value,
        );
      }

      _pushHistory();
      _project = nextProject;
      _selectedMediaItemId = imageItem.id;
      _setSelectedTimelineGroups({clip.timelineGroupId});
      _errorMessage = null;
      _statusMessage =
          'Imagem seguindo o objeto com ${math.min(trackingX.length, trackingY.length)} pontos. Selecione a imagem na timeline para ajustar o tamanho.';
    } catch (error) {
      _errorMessage = _cleanError(error);
      _statusMessage = null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  void updateSelectedClipCrop({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null ||
        (clip.trackType != TrackType.video &&
            clip.trackType != TrackType.image)) {
      _errorMessage = 'Selecione um clipe de video ou imagem para recortar.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final nextProject = _project.updateClipCrop(
      clip.id,
      cropLeft: left,
      cropTop: top,
      cropRight: right,
      cropBottom: bottom,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    _selectedTimelineGroupId = clip.timelineGroupId;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Crop atualizado.';
    notifyListeners();
  }

  void updateSelectedClipTransform({
    double? offsetX,
    double? offsetY,
    double? scale,
    double? rotationDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
  }) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null ||
        (clip.trackType != TrackType.video &&
            clip.trackType != TrackType.image) ||
        _timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      return;
    }
    final nextProject = _project.updateClipTransform(
      clip.id,
      offsetX: offsetX,
      offsetY: offsetY,
      scale: scale,
      rotationDegrees: rotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );
    if (identical(nextProject, _project)) {
      return;
    }
    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void rotateSelectedClipBy(double degrees) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null) return;
    updateSelectedClipTransform(
      rotationDegrees: clip.rotationDegrees + degrees,
    );
  }

  void resetSelectedClipTransformAndCrop() {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null ||
        (clip.trackType != TrackType.video &&
            clip.trackType != TrackType.image) ||
        _timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      return;
    }
    var nextProject = _project.updateClipTransform(
      clip.id,
      offsetX: 0,
      offsetY: 0,
      scale: 1,
      rotationDegrees: 0,
      flipHorizontal: false,
      flipVertical: false,
    );
    nextProject = nextProject.updateClipCrop(
      clip.id,
      cropLeft: 0,
      cropTop: 0,
      cropRight: 0,
      cropBottom: 0,
    );
    if (identical(nextProject, _project)) return;
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    _statusMessage = 'Transformação e recorte restaurados.';
    notifyListeners();
  }

  void applySelectedClipCropAspectRatio(double targetAspectRatio) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null ||
        (clip.trackType != TrackType.video &&
            clip.trackType != TrackType.image) ||
        !targetAspectRatio.isFinite ||
        targetAspectRatio <= 0 ||
        _timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      return;
    }
    final item = _project.mediaItemById(clip.mediaItemId);
    final width = item?.width;
    final height = item?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      _errorMessage = 'Não foi possível ler a proporção desta mídia.';
      notifyListeners();
      return;
    }
    final quarterTurn = (clip.rotationDegrees.abs() % 180 - 90).abs() < 0.01;
    final sourceAspect = quarterTurn ? height / width : width / height;
    var left = 0.0;
    var top = 0.0;
    var right = 0.0;
    var bottom = 0.0;
    if (sourceAspect > targetAspectRatio) {
      final horizontalCrop = (1 - targetAspectRatio / sourceAspect) / 2;
      left = horizontalCrop;
      right = horizontalCrop;
    } else if (sourceAspect < targetAspectRatio) {
      final verticalCrop = (1 - sourceAspect / targetAspectRatio) / 2;
      top = verticalCrop;
      bottom = verticalCrop;
    }
    final nextProject = _project.updateClipCrop(
      clip.id,
      cropLeft: left,
      cropTop: top,
      cropRight: right,
      cropBottom: bottom,
    );
    if (identical(nextProject, _project)) return;
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    _statusMessage = 'Recorte proporcional aplicado.';
    notifyListeners();
  }

  void updateSelectedClipKenBurnsEnabled(bool enabled) {
    _updateSelectedClipKenBurns(enabled: enabled);
  }

  void captureSelectedClipKenBurnsStart() {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null) {
      return;
    }
    _updateSelectedClipKenBurns(
      enabled: true,
      startOverlayX: clip.overlayX,
      startOverlayY: clip.overlayY,
      startOverlayScale: clip.overlayScale,
    );
  }

  void captureSelectedClipKenBurnsEnd() {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null) {
      return;
    }
    _updateSelectedClipKenBurns(
      enabled: true,
      endOverlayX: clip.overlayX,
      endOverlayY: clip.overlayY,
      endOverlayScale: clip.overlayScale,
    );
  }

  void setSelectedClipKenBurnsStartPoint(double x, double y) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    final defaultEndScale =
        clip != null &&
            !clip.kenBurnsEnabled &&
            (clip.overlayScale - 1).abs() < 0.001
        ? 1.35
        : null;
    _updateSelectedClipKenBurns(
      enabled: true,
      startOverlayX: x,
      startOverlayY: y,
      startOverlayScale: clip == null || clip.startOverlayScale < 1
          ? 1
          : clip.startOverlayScale,
      endOverlayScale: defaultEndScale,
    );
  }

  void setSelectedClipKenBurnsEndPoint(double x, double y) {
    _updateSelectedClipKenBurns(enabled: true, endOverlayX: x, endOverlayY: y);
  }

  void updateSelectedClipKenBurnsStartScale(double scale) {
    _updateSelectedClipKenBurns(enabled: true, startOverlayScale: scale);
  }

  void updateSelectedClipKenBurnsEndScale(double scale) {
    _updateSelectedClipKenBurns(enabled: true, endOverlayScale: scale);
  }

  void updateSelectedClipKenBurnsStartTime(double normalizedTime) {
    _updateSelectedClipKenBurns(enabled: true, kenBurnsStart: normalizedTime);
  }

  void updateSelectedClipKenBurnsEndTime(double normalizedTime) {
    _updateSelectedClipKenBurns(enabled: true, kenBurnsEnd: normalizedTime);
  }

  void updateSelectedClipAnimationTiming(double start, double end) {
    _updateSelectedClipKenBurns(
      enabled: true,
      kenBurnsStart: start,
      kenBurnsEnd: end,
    );
  }

  void applySelectedClipAnimationPreset({
    required double startX,
    required double startY,
    required double startScale,
    required double endX,
    required double endY,
    required double endScale,
  }) {
    _updateSelectedClipKenBurns(
      enabled: true,
      startOverlayX: startX,
      startOverlayY: startY,
      startOverlayScale: startScale,
      endOverlayX: endX,
      endOverlayY: endY,
      endOverlayScale: endScale,
      kenBurnsStart: 0,
      kenBurnsEnd: 1,
    );
  }

  void swapSelectedClipAnimationDirection() {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null) return;
    _updateSelectedClipKenBurns(
      enabled: true,
      startOverlayX: clip.overlayX,
      startOverlayY: clip.overlayY,
      startOverlayScale: clip.overlayScale,
      endOverlayX: clip.startOverlayX,
      endOverlayY: clip.startOverlayY,
      endOverlayScale: clip.startOverlayScale,
      kenBurnsStart: 1 - clip.kenBurnsEnd,
      kenBurnsEnd: 1 - clip.kenBurnsStart,
    );
  }

  void resetSelectedClipAnimation() {
    _updateSelectedClipKenBurns(
      enabled: false,
      startOverlayX: 0.5,
      startOverlayY: 0.5,
      startOverlayScale: 1,
      endOverlayX: 0.5,
      endOverlayY: 0.5,
      endOverlayScale: 1,
      kenBurnsStart: 0,
      kenBurnsEnd: 1,
    );
  }

  void upsertSelectedClipKeyframe(
    domain.ClipKeyframeProperty property,
    double value,
  ) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null) {
      _errorMessage = 'Selecione um clipe para criar keyframe.';
      notifyListeners();
      return;
    }
    if (!_clipContainsTimelinePosition(clip, _playheadPosition)) {
      _errorMessage = 'Posicione o playhead dentro do clipe selecionado.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final range = keyframeRange(property);
    final nextProject = _commandProject('set_keyframe', {
      'clip_id': clip.id,
      'property': property.name,
      'time': _normalizedClipTimeAtPlayhead(clip),
      'value': value.clamp(range.$1, range.$2).toDouble(),
    });
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = clip.timelineGroupId;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Keyframe salvo.';
    notifyListeners();
  }

  void removeSelectedClipKeyframeNear(domain.ClipKeyframeProperty property) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null) {
      _errorMessage = 'Selecione um clipe para remover keyframe.';
      notifyListeners();
      return;
    }
    if (!_clipContainsTimelinePosition(clip, _playheadPosition)) {
      _errorMessage = 'Posicione o playhead dentro do clipe selecionado.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final nextProject = _project.removeClipKeyframeNear(
      clip.id,
      property: property,
      time: _normalizedClipTimeAtPlayhead(clip),
    );
    if (identical(nextProject, _project)) {
      _statusMessage = 'Nenhum keyframe perto do playhead.';
      _errorMessage = null;
      notifyListeners();
      return;
    }

    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = clip.timelineGroupId;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Keyframe removido.';
    notifyListeners();
  }

  void clearSelectedClipKeyframes(domain.ClipKeyframeProperty property) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null) {
      _errorMessage = 'Selecione um clipe para limpar keyframes.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final nextProject = _project.clearClipKeyframes(
      clip.id,
      property: property,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = clip.timelineGroupId;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Keyframes limpos.';
    notifyListeners();
  }

  void updateWatermark({
    bool? enabled,
    String? imagePath,
    WatermarkPosition? position,
    double? x,
    double? y,
    double? scale,
    double? opacity,
  }) {
    final nextProject = _project.updateWatermark(
      (watermark) => watermark.copyWith(
        enabled: enabled,
        imagePath: imagePath,
        position: position,
        x: x,
        y: y,
        scale: scale,
        opacity: opacity,
      ),
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    _statusMessage = 'Marca dagua atualizada.';
    notifyListeners();
  }

  Future<void> insertFreezeFrameAtPlayhead() async {
    if (_isImporting) {
      return;
    }
    final clip = _selectedOrActiveVideoClip;
    if (clip == null) {
      _errorMessage = 'Selecione um clipe de video para congelar o quadro.';
      _statusMessage = null;
      notifyListeners();
      return;
    }
    if (!_clipContainsTimelinePosition(clip, _playheadPosition)) {
      _errorMessage = 'Posicione o playhead dentro do clipe selecionado.';
      _statusMessage = null;
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId) ||
        _timelineInsertTouchesLockedTrack(_playheadPosition)) {
      _errorMessage = 'Destrave as trilhas afetadas para congelar o quadro.';
      _statusMessage = null;
      notifyListeners();
      return;
    }
    final mediaItem = _project.mediaItemById(clip.mediaItemId);
    if (mediaItem == null || mediaItem.type != MediaType.video) {
      _errorMessage = 'Midia de video nao encontrada para congelar o quadro.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    _timelinePlaybackActive = false;
    _stopGapPlaybackTimer();
    _isImporting = true;
    _errorMessage = null;
    _statusMessage = 'Congelando quadro...';
    notifyListeners();

    try {
      final insertPosition = _playheadPosition;
      final sourcePosition = _sourcePositionForTimelineClip(
        clip,
        insertPosition,
        reverseAware: true,
      );
      final freezeDir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}tgi_editor_freeze_frames',
      );
      await freezeDir.create(recursive: true);
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final framePath =
          '${freezeDir.path}${Platform.pathSeparator}freeze_$timestamp.png';
      final freezeVideoPath =
          '${freezeDir.path}${Platform.pathSeparator}freeze_$timestamp.mp4';
      await ffmpegService.extractVideoFrame(
        inputPath: mediaItem.filePath,
        position: sourcePosition,
        outputPath: framePath,
      );
      await ffmpegService.createFreezeFrameVideo(
        framePath: framePath,
        duration: _defaultFreezeFrameDuration,
        outputPath: freezeVideoPath,
        width: mediaItem.width ?? 1280,
        height: mediaItem.height ?? 720,
      );

      final freezeItem = MediaItem(
        id: 'freeze_$timestamp',
        filePath: freezeVideoPath,
        name: 'Quadro congelado.mp4',
        type: MediaType.video,
        duration: _defaultFreezeFrameDuration,
        importedAt: DateTime.now(),
        hasAudio: true,
        width: mediaItem.width,
        height: mediaItem.height,
      );

      final targetTrackId = _trackForClipId(clip.id)?.id;
      final previousClipIds = _timelineClipIds(_project);
      var nextProject = _project.addMediaItem(freezeItem);
      if (insertPosition > clip.timelineStart &&
          insertPosition < clip.timelineEnd) {
        nextProject = nextProject.splitTimelineClipGroupAt(
          clip.id,
          timelinePosition: insertPosition,
        );
      }
      nextProject = nextProject.insertTimelineSpace(
        timelineStart: insertPosition,
        duration: _defaultFreezeFrameDuration,
      );
      nextProject = nextProject.addMediaItemToTimeline(
        freezeItem,
        timelineStart: insertPosition,
        targetTrackId: targetTrackId,
      );

      if (!identical(nextProject, _project)) {
        _pushHistory();
        _project = nextProject;
      }
      final addedClip = _addedClipForItem(
        _project,
        previousClipIds,
        freezeItem.id,
        TrackType.video,
      );
      _selectedMediaItemId = freezeItem.id;
      _selectedTimelineGroupId = addedClip?.timelineGroupId;
      _setSelectedTimelineGroups(
        _selectedTimelineGroupId == null
            ? const {}
            : {_selectedTimelineGroupId!},
      );
      _playheadPosition = insertPosition;
      _errorMessage = null;
      _statusMessage =
          'Quadro congelado inserido em ${_formatControllerTime(insertPosition)}.';
      _syncGapPlaybackTimer();
    } catch (error) {
      _errorMessage = _cleanError(error);
      _statusMessage = null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  void _updateSelectedVideoLook({
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? hue,
    double? temperature,
    double? tint,
    double? shadows,
    double? highlights,
    double? curveShadows,
    double? curveMidtones,
    double? curveHighlights,
    domain.VideoFilterPreset? filterPreset,
    bool? reverseVideo,
    bool? chromaKeyEnabled,
    int? chromaKeyColor,
    double? chromaKeySimilarity,
    double? chromaKeyBlend,
    bool? stabilizationEnabled,
  }) {
    final clip = _selectedOrActiveVideoClip;
    if (clip == null) {
      _errorMessage = 'Selecione um clipe de video para ajustar.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final nextProject = _commandProject('apply_effect', {
      'clip_id': clip.id,
      'brightness': ?brightness,
      'contrast': ?contrast,
      'saturation': ?saturation,
      'exposure': ?exposure,
      'hue': ?hue,
      'temperature': ?temperature,
      'tint': ?tint,
      'shadows': ?shadows,
      'highlights': ?highlights,
      'curve_shadows': ?curveShadows,
      'curve_midtones': ?curveMidtones,
      'curve_highlights': ?curveHighlights,
      'reverse': ?reverseVideo,
      'chroma_key_enabled': ?chromaKeyEnabled,
      'chroma_key_color': ?chromaKeyColor,
      'chroma_key_similarity': ?chromaKeySimilarity,
      'chroma_key_blend': ?chromaKeyBlend,
      'stabilization': ?stabilizationEnabled,
      'filter': ?filterPreset?.name,
    });
    if (identical(nextProject, _project)) {
      return;
    }

    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    _selectedTimelineGroupId = clip.timelineGroupId;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = reverseVideo == true
        ? 'Reverso ativado no preview e na exportacao.'
        : 'Clipe de video atualizado.';
    notifyListeners();
  }

  void _updateSelectedClipKenBurns({
    bool? enabled,
    double? startOverlayX,
    double? startOverlayY,
    double? startOverlayScale,
    double? endOverlayX,
    double? endOverlayY,
    double? endOverlayScale,
    double? kenBurnsStart,
    double? kenBurnsEnd,
  }) {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null ||
        (clip.trackType != TrackType.image &&
            clip.trackType != TrackType.video)) {
      _errorMessage = 'Selecione um overlay de imagem ou video.';
      notifyListeners();
      return;
    }
    if (_timelineGroupTouchesLockedTrack(clip.timelineGroupId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }

    final nextProject = _project.updateClipKenBurns(
      clip.id,
      enabled: enabled,
      startOverlayX: startOverlayX,
      startOverlayY: startOverlayY,
      startOverlayScale: startOverlayScale,
      endOverlayX: endOverlayX,
      endOverlayY: endOverlayY,
      endOverlayScale: endOverlayScale,
      kenBurnsStart: kenBurnsStart,
      kenBurnsEnd: kenBurnsEnd,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    _selectedTimelineGroupId = clip.timelineGroupId;
    _setSelectedTimelineGroups({clip.timelineGroupId});
    _errorMessage = null;
    _statusMessage = 'Animacao Ken Burns atualizada.';
    notifyListeners();
  }

  void cutTimelineClip(String clipId, Duration timelinePosition) {
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final position = _normalizeTimelinePosition(timelinePosition);
    final referenceClip = _findClipById(clipId);
    final nextProject = _commandProject('split_clip', {
      'clip_id': clipId,
      'at': position.inMicroseconds / 1e6,
    });
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _playheadPosition = position;
    _selectedTimelineGroupId =
        _project
            .clipAt(position, trackType: referenceClip?.trackType)
            ?.timelineGroupId ??
        activeTimelineClip?.timelineGroupId;
    _setSelectedTimelineGroups(
      _selectedTimelineGroupId == null ? const {} : {_selectedTimelineGroupId!},
    );
    _errorMessage = null;
    notifyListeners();
  }

  void selectTimelineClipGroup(
    String timelineGroupId, {
    bool additive = false,
    bool toggle = false,
    String? clipId,
  }) {
    final focusChanged = clipId != null && clipId != _selectedTimelineClipId;
    if (clipId != null) _selectedTimelineClipId = clipId;
    if (!additive &&
        !toggle &&
        _selectedTimelineGroupIds.length > 1 &&
        _selectedTimelineGroupIds.contains(timelineGroupId)) {
      _selectedTimelineGroupId = timelineGroupId;
      notifyListeners();
      return;
    }
    final overlayClip = _overlayClipForTimelineGroup(timelineGroupId);
    final shouldMovePlayheadToOverlay =
        overlayClip != null &&
        !_clipContainsTimelinePosition(overlayClip, _playheadPosition);
    if (!focusChanged &&
        !additive &&
        !toggle &&
        _selectedTimelineGroupId == timelineGroupId &&
        _selectedTimelineGroupIds.length == 1 &&
        !shouldMovePlayheadToOverlay) {
      return;
    }

    final nextSelection = Set<String>.from(_selectedTimelineGroupIds);
    if (nextSelection.isEmpty && _selectedTimelineGroupId != null) {
      nextSelection.add(_selectedTimelineGroupId!);
    }
    final wasSelected = nextSelection.contains(timelineGroupId);
    final willSelect = !toggle || !wasSelected;
    if (toggle) {
      if (wasSelected) {
        nextSelection.remove(timelineGroupId);
      } else {
        nextSelection.add(timelineGroupId);
      }
      _setSelectedTimelineGroups(nextSelection);
    } else if (additive) {
      nextSelection.add(timelineGroupId);
      _setSelectedTimelineGroups(nextSelection);
    } else {
      _setSelectedTimelineGroups({timelineGroupId});
    }
    if (willSelect && shouldMovePlayheadToOverlay) {
      _playheadPosition = overlayClip.timelineStart;
    }
    _errorMessage = null;
    notifyListeners();
  }

  void selectTextOverlayFromPreview(String timelineGroupId) {
    final selectedGroups = _effectiveSelectedTimelineGroupIds();
    if (selectedGroups.length > 1 && selectedGroups.contains(timelineGroupId)) {
      _selectedTimelineGroupId = timelineGroupId;
      _errorMessage = null;
      notifyListeners();
      return;
    }
    selectTimelineClipGroup(timelineGroupId);
  }

  void selectTimelineClipGroups(
    Set<String> timelineGroupIds, {
    bool additive = false,
    bool toggle = false,
    bool intersect = false,
  }) {
    final existingGroupIds = <String>{
      for (final track in _project.tracks)
        for (final clip in track.clips) clip.timelineGroupId,
    };
    final incoming = timelineGroupIds.intersection(existingGroupIds);
    final current = Set<String>.from(_selectedTimelineGroupIds);
    if (current.isEmpty && _selectedTimelineGroupId != null) {
      current.add(_selectedTimelineGroupId!);
    }

    late final Set<String> nextSelection;
    if (incoming.isEmpty) {
      nextSelection = <String>{};
    } else if (intersect) {
      nextSelection = current.intersection(incoming);
    } else if (toggle) {
      nextSelection = Set<String>.from(current);
      for (final timelineGroupId in incoming) {
        if (!nextSelection.remove(timelineGroupId)) {
          nextSelection.add(timelineGroupId);
        }
      }
    } else if (additive) {
      nextSelection = {...current, ...incoming};
    } else {
      nextSelection = incoming;
    }

    _setSelectedTimelineGroups(nextSelection);
    _errorMessage = null;
    notifyListeners();
  }

  void deleteSelectedTimelineClip() {
    final groupsToDelete = _selectedTimelineGroupIds.isEmpty
        ? (_selectedTimelineGroupId == null
              ? <String>{}
              : {_selectedTimelineGroupId!})
        : Set<String>.from(_selectedTimelineGroupIds);
    if (groupsToDelete.isEmpty) {
      return;
    }
    if (_timelineGroupsTouchLockedTracks(groupsToDelete)) {
      _errorMessage = 'Uma das trilhas selecionadas esta travada.';
      notifyListeners();
      return;
    }

    final nextProject = const CommandEngine().deleteGroups(
      _project,
      groupsToDelete,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = null;
    _selectedTimelineGroupIds.clear();
    _errorMessage = null;
    notifyListeners();
  }

  void rippleDeleteSelectedTimelineClip() {
    final groupsToDelete = _selectedTimelineGroupIds.isEmpty
        ? (_selectedTimelineGroupId == null
              ? <String>{}
              : {_selectedTimelineGroupId!})
        : Set<String>.from(_selectedTimelineGroupIds);
    if (groupsToDelete.isEmpty) return;
    if (_timelineGroupsTouchLockedTracks(groupsToDelete)) {
      _errorMessage = 'Uma das trilhas selecionadas esta travada.';
      notifyListeners();
      return;
    }
    Duration? rippleEnd;
    for (final track in _project.tracks) {
      for (final clip in track.clips) {
        if (!groupsToDelete.contains(clip.timelineGroupId)) continue;
        if (rippleEnd == null || clip.timelineEnd > rippleEnd) {
          rippleEnd = clip.timelineEnd;
        }
      }
    }
    if (rippleEnd != null && _lockedTimelineContentAtOrAfter(rippleEnd)) {
      _errorMessage =
          'Destrave as trilhas com conteudo posterior para fechar o espaco.';
      notifyListeners();
      return;
    }
    final nextProject = const CommandEngine().deleteGroups(
      _project,
      groupsToDelete,
      ripple: true,
    );
    if (identical(nextProject, _project)) return;
    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = null;
    _selectedTimelineGroupIds.clear();
    _errorMessage = null;
    _statusMessage = 'Clipe removido e espaco fechado.';
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  Future<SmartCutAnalysis?> analyzeSmartCut({
    SmartCutIntensity intensity = SmartCutIntensity.balanced,
  }) {
    return _analyzeSmartCut(
      intensity: intensity,
      threshold: intensity.threshold,
      minimumSilence: intensity.minimumSilence,
      edgePadding: intensity.edgePadding,
    );
  }

  Future<SmartCutAnalysis?> _analyzeSmartCut({
    required SmartCutIntensity intensity,
    required double threshold,
    required Duration minimumSilence,
    required Duration edgePadding,
  }) async {
    final sourceClip = _selectedOrActiveVideoClip;
    if (sourceClip == null) {
      _errorMessage = 'Selecione um clipe de vídeo para analisar.';
      notifyListeners();
      return null;
    }
    if (_timelineGroupTouchesLockedTrack(sourceClip.timelineGroupId)) {
      _errorMessage = 'A trilha está travada.';
      notifyListeners();
      return null;
    }
    final mediaItem = _project.mediaItemById(sourceClip.mediaItemId);
    if (mediaItem == null || !mediaItem.hasAudio) {
      _errorMessage = 'O clipe selecionado não possui áudio para analisar.';
      notifyListeners();
      return null;
    }
    final sourceTrack = _trackForClipId(sourceClip.id);
    if (sourceTrack == null) {
      _errorMessage = 'Não foi possível localizar a trilha do clipe.';
      notifyListeners();
      return null;
    }
    final projectSnapshot = _project;
    _isAnalyzingSmartCut = true;
    _smartCutAnalysis = null;
    _smartCutProjectSnapshot = null;
    _statusMessage = 'Analisando pausas do clipe...';
    _errorMessage = null;
    notifyListeners();
    try {
      final waveform = await audioWaveformService.extractWaveform(mediaItem);
      if (!identical(projectSnapshot, _project)) {
        _errorMessage = 'O projeto mudou durante a análise. Analise novamente.';
        _statusMessage = null;
        return null;
      }
      final samples = waveform.samplesFor(
        sourceStart: sourceClip.sourceStart,
        duration: sourceClip.effectiveSourceDuration,
      );
      if (samples.isEmpty || waveform.sampleInterval <= Duration.zero) {
        _errorMessage = 'Não foi possível analisar o áudio deste clipe.';
        _statusMessage = null;
        return null;
      }
      final safeThreshold = threshold.clamp(0.01, 0.20).toDouble();
      final minimumSamples = math.max(
        1,
        (minimumSilence.inMicroseconds / waveform.sampleInterval.inMicroseconds)
            .ceil(),
      );
      final ranges = <SmartCutSegment>[];
      var silentStart = -1;
      for (var index = 0; index <= samples.length; index++) {
        final silent =
            index < samples.length && samples[index] <= safeThreshold;
        if (silent && silentStart < 0) {
          silentStart = index;
        }
        if (silent || silentStart < 0) continue;
        final silentLength = index - silentStart;
        if (silentLength >= minimumSamples) {
          final sourceStartOffset = waveform.sampleInterval * silentStart;
          final sourceEndOffset = waveform.sampleInterval * index;
          final timelineStartOffset = Duration(
            microseconds:
                (sourceStartOffset.inMicroseconds / sourceClip.playbackSpeed)
                    .round(),
          );
          final timelineEndOffset = Duration(
            microseconds:
                (sourceEndOffset.inMicroseconds / sourceClip.playbackSpeed)
                    .round(),
          );
          final start = _clampDuration(
            sourceClip.timelineStart + timelineStartOffset + edgePadding,
            sourceClip.timelineStart,
            sourceClip.timelineEnd,
          );
          final end = _clampDuration(
            sourceClip.timelineStart + timelineEndOffset - edgePadding,
            sourceClip.timelineStart,
            sourceClip.timelineEnd,
          );
          if (end - start >= const Duration(milliseconds: 350)) {
            ranges.add(SmartCutSegment(start: start, end: end));
          }
        }
        silentStart = -1;
      }
      final analysis = SmartCutAnalysis(
        intensity: intensity,
        sourceTimelineGroupId: sourceClip.timelineGroupId,
        sourceMediaItemId: sourceClip.mediaItemId,
        sourceVideoTrackId: sourceTrack.id,
        sourceName: mediaItem.name,
        sourceTimelineStart: sourceClip.timelineStart,
        originalTimelineDuration: _project.timelineDuration,
        segments: List.unmodifiable(ranges.take(30)),
      );
      _smartCutAnalysis = analysis;
      _smartCutProjectSnapshot = _project;
      _statusMessage = ranges.isEmpty
          ? 'Nenhuma pausa longa foi encontrada.'
          : '${analysis.segments.length} cortes prontos para revisar.';
      return analysis;
    } catch (error) {
      _errorMessage = _cleanError(error);
      _statusMessage = null;
      return null;
    } finally {
      _isAnalyzingSmartCut = false;
      notifyListeners();
    }
  }

  void clearSmartCutAnalysis() {
    if (_smartCutAnalysis == null && _smartCutProjectSnapshot == null) return;
    _smartCutAnalysis = null;
    _smartCutProjectSnapshot = null;
    _statusMessage = 'Prévia do Corte Inteligente descartada.';
    notifyListeners();
  }

  int applySmartCutAnalysis() {
    final analysis = smartCutAnalysis;
    if (analysis == null) {
      _errorMessage = _smartCutAnalysis == null
          ? 'Analise o clipe antes de aplicar os cortes.'
          : 'O projeto mudou. Analise o clipe novamente.';
      notifyListeners();
      return 0;
    }
    if (analysis.segments.isEmpty) {
      _statusMessage = 'Não há pausas para remover.';
      notifyListeners();
      return 0;
    }
    if (_timelineGroupTouchesLockedTrack(analysis.sourceTimelineGroupId) ||
        _lockedTimelineContentAtOrAfter(analysis.segments.first.start)) {
      _errorMessage =
          'Destrave as trilhas afetadas para aplicar o Corte Inteligente.';
      notifyListeners();
      return 0;
    }

    var nextProject = _project;
    var removed = 0;
    for (final range in analysis.segments.reversed) {
      domain.Clip? clipAt(Duration position) {
        for (final track in nextProject.tracks) {
          if (track.id != analysis.sourceVideoTrackId) continue;
          for (final clip in track.clips) {
            if (clip.mediaItemId == analysis.sourceMediaItemId &&
                position > clip.timelineStart &&
                position < clip.timelineEnd) {
              return clip;
            }
          }
        }
        return null;
      }

      final beforeEnd = clipAt(range.end - const Duration(microseconds: 1));
      if (beforeEnd == null) continue;
      nextProject = nextProject.splitTimelineClipGroupAt(
        beforeEnd.id,
        timelinePosition: range.end,
      );
      final beforeStart = clipAt(range.start + const Duration(microseconds: 1));
      if (beforeStart == null) continue;
      nextProject = nextProject.splitTimelineClipGroupAt(
        beforeStart.id,
        timelinePosition: range.start,
      );
      final middle = clipAt(
        range.start +
            Duration(
              microseconds: (range.end - range.start).inMicroseconds ~/ 2,
            ),
      );
      if (middle == null) continue;
      nextProject = nextProject.rippleDeleteTimelineClipGroups({
        middle.timelineGroupId,
      });
      removed++;
    }
    if (removed == 0 || identical(nextProject, _project)) {
      _statusMessage = 'Nenhuma pausa pôde ser removida com segurança.';
      notifyListeners();
      return 0;
    }
    _pushHistory();
    _project = nextProject;
    _selectedTimelineGroupId = null;
    _selectedTimelineGroupIds.clear();
    _playheadPosition = analysis.sourceTimelineStart;
    _smartCutAnalysis = null;
    _smartCutProjectSnapshot = null;
    _errorMessage = null;
    _statusMessage = '$removed pausas removidas e espaços fechados.';
    _syncGapPlaybackTimer();
    notifyListeners();
    return removed;
  }

  void copySelectedTimelineClips() {
    final groups = _selectedTimelineGroupIds.isEmpty
        ? (_selectedTimelineGroupId == null
              ? <String>{}
              : {_selectedTimelineGroupId!})
        : Set<String>.from(_selectedTimelineGroupIds);
    if (groups.isEmpty) {
      return;
    }

    _clipClipboard
      ..clear()
      ..addAll(_clipboardEntriesForGroups(groups));
    _statusMessage = _clipClipboard.length == 1
        ? 'Clipe copiado.'
        : '${_clipClipboard.length} clipes copiados.';
    _errorMessage = null;
    notifyListeners();
  }

  void pasteCopiedTimelineClips() {
    if (_clipClipboard.isEmpty) {
      return;
    }
    if (_clipClipboard.any(
      (entry) => _project.trackById(entry.trackId)?.isLocked ?? false,
    )) {
      _errorMessage = 'A trilha de destino esta travada.';
      notifyListeners();
      return;
    }

    final result = _projectWithPastedClipboard(
      _clipClipboard,
      timelineStart: _normalizeTimelinePosition(_playheadPosition),
    );
    if (identical(result.project, _project)) {
      return;
    }

    _pushHistory();
    _project = result.project;
    _setSelectedTimelineGroups(result.timelineGroupIds);
    _selectedMediaItemId = null;
    _playheadPosition = _normalizeTimelinePosition(_playheadPosition);
    _errorMessage = null;
    _statusMessage = result.timelineGroupIds.length == 1
        ? 'Clipe colado.'
        : 'Grupo colado.';
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void duplicateSelectedTimelineClips() {
    final groups = _selectedTimelineGroupIds.isEmpty
        ? (_selectedTimelineGroupId == null
              ? <String>{}
              : {_selectedTimelineGroupId!})
        : Set<String>.from(_selectedTimelineGroupIds);
    if (groups.isEmpty) {
      return;
    }
    if (_timelineGroupsTouchLockedTracks(groups)) {
      _errorMessage = 'Uma das trilhas selecionadas esta travada.';
      notifyListeners();
      return;
    }

    final entries = _clipboardEntriesForGroups(groups);
    if (entries.isEmpty) {
      return;
    }
    final latestEnd = entries.fold<Duration>(
      Duration.zero,
      (latest, entry) =>
          entry.clip.timelineEnd > latest ? entry.clip.timelineEnd : latest,
    );
    final result = _projectWithPastedClipboard(
      entries,
      timelineStart: latestEnd + const Duration(milliseconds: 200),
    );
    if (identical(result.project, _project)) {
      return;
    }

    _pushHistory();
    _project = result.project;
    _setSelectedTimelineGroups(result.timelineGroupIds);
    _selectedMediaItemId = null;
    _playheadPosition = latestEnd + const Duration(milliseconds: 200);
    _errorMessage = null;
    _statusMessage = result.timelineGroupIds.length == 1
        ? 'Clipe duplicado.'
        : 'Grupo duplicado.';
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void renameTimelineTrack(String trackId, String name) {
    final nextProject = _project.renameTimelineTrack(trackId, name);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void setTimelineTrackLocked(String trackId, bool isLocked) {
    final nextProject = _project.setTimelineTrackLocked(trackId, isLocked);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void setTimelineTrackHidden(String trackId, bool isHidden) {
    final nextProject = _project.setTimelineTrackHidden(trackId, isHidden);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void setTimelineTrackMuted(String trackId, bool isMuted) {
    final nextProject = _project.setTimelineTrackMuted(trackId, isMuted);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void setTimelineTrackSolo(String trackId, bool isSolo) {
    final nextProject = _project.setTimelineTrackSolo(trackId, isSolo);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateSelectedClipTransition({
    required Duration fadeIn,
    required Duration fadeOut,
  }) {
    final clip = selectedTimelineClip;
    if (clip == null) {
      return;
    }
    updateClipTransition(clip.id, fadeIn: fadeIn, fadeOut: fadeOut);
  }

  void updateSelectedClipTransitionsForType(
    TrackType trackType, {
    Duration? fadeIn,
    Duration? fadeOut,
  }) {
    if (fadeIn == null && fadeOut == null) {
      return;
    }
    final clips = _selectedTimelineClipsForType(trackType);
    if (clips.isEmpty) {
      return;
    }
    if (clips.any((clip) => _clipIsOnLockedTrack(clip.id))) {
      _errorMessage = 'Uma das trilhas selecionadas esta travada.';
      notifyListeners();
      return;
    }

    var nextProject = _project;
    for (final clip in clips) {
      nextProject = nextProject.updateClipTransition(
        clip.id,
        fadeIn: fadeIn ?? clip.fadeIn,
        fadeOut: fadeOut ?? clip.fadeOut,
      );
    }
    if (identical(nextProject, _project)) {
      return;
    }
    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void enableFadeForSelectedClips(
    TrackType trackType, {
    Duration preferredDuration = const Duration(milliseconds: 500),
  }) {
    final clips = _selectedTimelineClipsForType(trackType);
    if (clips.isEmpty) {
      return;
    }
    if (clips.any((clip) => _clipIsOnLockedTrack(clip.id))) {
      _errorMessage = 'Uma das trilhas selecionadas esta travada.';
      notifyListeners();
      return;
    }

    var nextProject = _project;
    for (final clip in clips) {
      final maxFade = Duration(
        microseconds: (clip.duration.inMicroseconds / 2).floor(),
      );
      final fade = preferredDuration > maxFade ? maxFade : preferredDuration;
      nextProject = nextProject.updateClipTransition(
        clip.id,
        fadeIn: fade,
        fadeOut: fade,
      );
    }
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateClipTransition(
    String clipId, {
    required Duration fadeIn,
    required Duration fadeOut,
  }) {
    final clip = _findClipById(clipId);
    if (clip == null) {
      return;
    }
    if (_clipIsOnLockedTrack(clipId)) {
      _errorMessage = 'A trilha esta travada.';
      notifyListeners();
      return;
    }
    final nextProject = _project.updateClipTransition(
      clipId,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
    );
    if (identical(nextProject, _project)) {
      return;
    }
    if (_interactiveEditBaseProject == null) {
      _pushHistory();
    }
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void addMarkerAtPlayhead() {
    final nextProject = _commandProject('add_marker', {
      'at': _playheadPosition.inMicroseconds / 1e6,
      'name': 'Marcador ${_project.markers.length + 1}',
    });
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void updateTimelineMarkerName(String markerId, String name) {
    final nextProject = _project.updateTimelineMarker(markerId, name: name);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void deleteTimelineMarker(String markerId) {
    final nextProject = _project.deleteTimelineMarker(markerId);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    notifyListeners();
  }

  void applyTransitionAssetToNearestEdit({
    required String filePath,
    required String name,
    Duration duration = _defaultAppliedTransitionDuration,
    Duration? timelinePosition,
  }) {
    final cleanPath = filePath.trim();
    if (cleanPath.isEmpty || !File(cleanPath).existsSync()) {
      _errorMessage = 'Arquivo de transicao nao encontrado.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    final targetPosition = _normalizeTimelinePosition(
      timelinePosition ?? _playheadPosition,
    );
    final target = _nearestVideoTransitionTarget(targetPosition);
    if (target == null) {
      _errorMessage =
          'Nao encontrei o inicio de um video ou uma emenda na timeline.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    final nextProject = _project.upsertTimelineTransition(
      filePath: cleanPath,
      name: name,
      timelinePosition: target.position,
      duration: duration,
      placement: target.placement,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _playheadPosition = target.position;
    _errorMessage = null;
    _statusMessage =
        'Transicao aplicada em ${_formatControllerTime(target.position)}.';
    notifyListeners();
  }

  void applyTransitionPresetToNearestEdit({
    required TimelineTransitionPreset preset,
    required String name,
    Duration duration = _defaultAppliedTransitionDuration,
    Duration? timelinePosition,
    TimelineTransitionDirection direction =
        TimelineTransitionDirection.leftToRight,
    int color = 0xFF000000,
    double intensity = 1,
  }) {
    final targetPosition = _normalizeTimelinePosition(
      timelinePosition ?? _playheadPosition,
    );
    final target = _nearestVideoTransitionTarget(targetPosition);
    if (target == null) {
      _errorMessage =
          'Nao encontrei o inicio de um video ou uma emenda na timeline.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    final nextProject = _commandProject('add_transition', {
      'name': name,
      'at': target.position.inMicroseconds / 1e6,
      'duration': duration.inMicroseconds / 1e6,
      'placement': target.placement.name,
      'preset': preset.name,
      'direction': direction.name,
      'color': color,
      'intensity': intensity,
    });
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _playheadPosition = target.position;
    _errorMessage = null;
    _statusMessage =
        'Transicao aplicada em ${_formatControllerTime(target.position)}.';
    notifyListeners();
  }

  Future<void> insertTransitionClipAtNearestEdit({
    required String filePath,
    required String name,
    Duration? timelinePosition,
  }) async {
    final requestedTargetLabel = timelinePosition == null
        ? 'playhead'
        : _formatControllerTime(timelinePosition);
    _logController(
      'insert-cut-video request name="$name" path="$filePath" '
      'playhead=${_formatControllerTime(_playheadPosition)} '
      'target=$requestedTargetLabel '
      'playing=$_timelinePlaybackActive clips=${_videoClipDebugSummary()}',
    );
    if (_isImporting) {
      _logController('insert-cut-video ignored: already importing');
      return;
    }

    final cleanPath = filePath.trim();
    if (cleanPath.isEmpty || !File(cleanPath).existsSync()) {
      _logController('insert-cut-video failed: missing file "$cleanPath"');
      _errorMessage = 'Arquivo de transicao nao encontrado.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    final targetPosition = _normalizeTimelinePosition(
      timelinePosition ?? _playheadPosition,
    );
    final editPoint = _nearestVideoEdit(targetPosition);
    final insertPosition = editPoint?.position ?? targetPosition;
    final splitTargetClip = editPoint == null
        ? _project.clipAt(insertPosition, trackType: TrackType.video)
        : null;
    final insertTrackId =
        editPoint?.trackId ??
        (splitTargetClip == null
            ? null
            : _trackForClipId(splitTargetClip.id)?.id);
    if (editPoint == null) {
      _logController(
        'insert-cut-video no edit near ${_formatControllerTime(targetPosition)}; '
        'falling back to split/insert at playhead',
      );
    }
    final blockedByLockedTrack =
        _timelineInsertTouchesLockedTrack(insertPosition) ||
        (splitTargetClip != null &&
            _timelineGroupTouchesLockedTrack(splitTargetClip.timelineGroupId));
    if (blockedByLockedTrack) {
      _logController(
        'insert-cut-video failed: locked track at ${_formatControllerTime(insertPosition)}',
      );
      _errorMessage = 'Destrave as trilhas afetadas para inserir o clipe.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    _timelinePlaybackActive = false;
    _stopGapPlaybackTimer();
    _isImporting = true;
    _errorMessage = null;
    _statusMessage = editPoint == null
        ? 'Inserindo video de corte no playhead...'
        : 'Inserindo clipe de transicao...';
    notifyListeners();

    try {
      final importedItem = await mediaImportService.importFile(cleanPath);
      final cleanName = name.trim();
      final mediaItem = cleanName.isEmpty
          ? importedItem
          : importedItem.copyWith(name: cleanName);
      _logController(
        'insert-cut-video imported id=${mediaItem.id} name="${mediaItem.name}" '
        'duration=${_formatControllerTime(mediaItem.duration)} '
        'hasAudio=${mediaItem.hasAudio} type=${mediaItem.type.name} '
        'insert=${_formatControllerTime(insertPosition)} track=$insertTrackId',
      );
      if (mediaItem.type != MediaType.video) {
        throw Exception('A transicao precisa ser um arquivo de video.');
      }
      if (mediaItem.duration <= Duration.zero) {
        throw Exception('A transicao nao tem duracao valida.');
      }

      final previousClipIds = _timelineClipIds(_project);
      var nextProject = _project.addMediaItem(mediaItem);
      if (editPoint == null &&
          splitTargetClip != null &&
          insertPosition > splitTargetClip.timelineStart &&
          insertPosition < splitTargetClip.timelineEnd) {
        nextProject = nextProject.splitTimelineClipGroupAt(
          splitTargetClip.id,
          timelinePosition: insertPosition,
        );
      }
      nextProject = nextProject.insertTimelineSpace(
        timelineStart: insertPosition,
        duration: mediaItem.duration,
      );
      nextProject = nextProject.addMediaItemToTimeline(
        mediaItem,
        timelineStart: insertPosition,
        targetTrackId: insertTrackId,
      );
      _logController(
        'insert-cut-video timeline prepared beforeCommit clips=${_videoClipDebugSummary(project: nextProject)}',
      );

      if (!identical(nextProject, _project)) {
        _pushHistory();
        _project = nextProject;
      }
      _ensureAudioWaveform(mediaItem);
      _selectedMediaItemId = mediaItem.id;
      final addedClip = _addedClipForItem(
        _project,
        previousClipIds,
        mediaItem.id,
        TrackType.video,
      );
      _selectedTimelineGroupId =
          addedClip?.timelineGroupId ??
          _project
              .clipAt(insertPosition, trackType: TrackType.video)
              ?.timelineGroupId;
      _setSelectedTimelineGroups(
        _selectedTimelineGroupId == null
            ? const {}
            : {_selectedTimelineGroupId!},
      );
      _playheadPosition = addedClip?.timelineStart ?? insertPosition;
      final preview = previewMediaItem;
      final addedClipLabel = addedClip == null
          ? 'null'
          : _clipDebugLabel(addedClip);
      final previewLabel = preview == null
          ? 'null'
          : '${preview.id}/${preview.name}';
      _logController(
        'insert-cut-video committed added=$addedClipLabel '
        'selectedGroup=$_selectedTimelineGroupId '
        'playhead=${_formatControllerTime(_playheadPosition)} '
        'preview=$previewLabel '
        'previewSource=${_formatControllerTime(previewSourcePosition)} '
        'playing=$_timelinePlaybackActive clips=${_videoClipDebugSummary()}',
      );
      _errorMessage = null;
      _statusMessage = editPoint == null
          ? 'Video de corte inserido em ${_formatControllerTime(_playheadPosition)}.'
          : 'Clipe de transicao inserido em ${_formatControllerTime(_playheadPosition)}.';
    } catch (error) {
      _logController('insert-cut-video error: ${_cleanError(error)}');
      _errorMessage = _cleanError(error);
      _statusMessage = null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  void deleteTimelineTransition(String transitionId) {
    final nextProject = _project.deleteTimelineTransition(transitionId);
    if (identical(nextProject, _project)) {
      return;
    }
    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    _statusMessage = 'Transicao removida.';
    notifyListeners();
  }

  void moveTimelineTransition(String transitionId, Duration timelinePosition) {
    final position = _normalizeTimelinePosition(timelinePosition);
    final nextProject = _project.updateTimelineTransition(
      transitionId,
      timelinePosition: position,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _playheadPosition = position;
    _errorMessage = null;
    _statusMessage =
        'Transicao movida para ${_formatControllerTime(position)}.';
    notifyListeners();
  }

  void updateTimelineTransitionProperties(
    String transitionId, {
    Duration? duration,
    TimelineTransitionBlendMode? blendMode,
    TimelineTransitionDirection? direction,
    int? color,
    double? intensity,
  }) {
    final nextProject = _project.updateTimelineTransition(
      transitionId,
      duration: duration,
      blendMode: blendMode,
      direction: direction,
      color: color,
      intensity: intensity,
    );
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    _errorMessage = null;
    _statusMessage = 'Transicao atualizada.';
    notifyListeners();
  }

  void toggleCutMode() {
    setCutMode(!_isCutMode);
  }

  void setCutMode(bool enabled) {
    if (_isCutMode == enabled) {
      return;
    }

    _isCutMode = enabled;
    notifyListeners();
  }

  void setTimelinePlaybackActive(bool active) {
    if (_timelinePlaybackActive == active) {
      _syncGapPlaybackTimer();
      return;
    }

    final activeClip = activeTimelineClip;
    final activeClipLabel = activeClip == null
        ? 'null'
        : _clipDebugLabel(activeClip);
    _logController(
      'timeline-playback $_timelinePlaybackActive -> $active '
      'playhead=${_formatControllerTime(_playheadPosition)} '
      'active=$activeClipLabel',
    );
    _timelinePlaybackActive = active;
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void toggleTimelinePlayback() {
    setTimelinePlaybackActive(!_timelinePlaybackActive);
  }

  void splitSelectedOrActiveClipAtPlayhead() {
    final clip = selectedTimelineClip ?? activeTimelineClip;
    if (clip == null) {
      return;
    }
    cutTimelineClip(clip.id, _playheadPosition);
  }

  @visibleForTesting
  void advanceGapPlaybackForTesting(Duration elapsed) {
    _advanceGapPlaybackBy(elapsed);
  }

  void setPlayheadPosition(Duration timelinePosition) {
    final next = _normalizeTimelinePosition(timelinePosition);
    final currentClip = activeTimelineClip;
    final nextClip = _activeMainVideoClipAt(next);
    final deltaMs = (next - _playheadPosition).inMilliseconds;
    // Explicit seeks must preserve sub-50 ms edits and frame stepping. Playback
    // echoes are throttled separately in updatePlayheadFromPreview.
    if (next == _playheadPosition) {
      return;
    }

    final currentClipLabel = currentClip == null
        ? 'null'
        : _clipDebugLabel(currentClip);
    final nextClipLabel = nextClip == null ? 'null' : _clipDebugLabel(nextClip);
    _logController(
      'set-playhead ${_formatControllerTime(_playheadPosition)} -> '
      '${_formatControllerTime(next)} delta=${deltaMs}ms '
      'from=$currentClipLabel '
      'to=$nextClipLabel '
      'playing=$_timelinePlaybackActive',
    );
    _playheadPosition = next;
    _errorMessage = null;
    _syncGapPlaybackTimer();
    notifyListeners();
  }

  void updatePlayheadFromPreview(String mediaItemId, Duration sourcePosition) {
    final activeClip = activeTimelineClip;
    if (activeClip != null &&
        activeClip.reverseVideo &&
        activeClip.mediaItemId == mediaItemId) {
      _logController(
        'preview-position ignored for reverse clip media=$mediaItemId '
        'source=${_formatControllerTime(sourcePosition)} '
        'active=${_clipDebugLabel(activeClip)}',
      );
      return;
    }

    final boundaryPosition = _timelineBoundaryForPreviewSourceOverflow(
      mediaItemId,
      sourcePosition,
    );
    if (boundaryPosition != null) {
      setPlayheadPosition(boundaryPosition);
      return;
    }

    final clip = _clipForPreviewSourcePosition(mediaItemId, sourcePosition);
    if (clip == null) {
      _logController(
        'preview-position ignored media=$mediaItemId source=${_formatControllerTime(sourcePosition)} no matching clip '
        'playhead=${_formatControllerTime(_playheadPosition)} preview=${previewMediaItem?.id}',
      );
      return;
    }

    final sourceDelta = sourcePosition - clip.sourceStart;
    final clampedDelta = _clampDuration(
      sourceDelta,
      Duration.zero,
      clip.effectiveSourceDuration,
    );
    final timelineDelta = _timelineDurationForSource(
      clampedDelta,
      clip.playbackSpeed,
    );
    final nextTimelinePosition = clip.timelineStart + timelineDelta;

    _logController(
      'preview-position media=$mediaItemId source=${_formatControllerTime(sourcePosition)} '
      'clip=${_clipDebugLabel(clip)} nextTimeline=${_formatControllerTime(nextTimelinePosition)}',
    );
    setPlayheadPosition(nextTimelinePosition);
  }

  Future<void> exportTimeline(
    String outputPath, {
    FfmpegExportSettings settings = FfmpegExportSettings.defaultSettings,
  }) async {
    if (_isExporting || _disposed) {
      return;
    }
    if (!_hasExportableTimelineClips) {
      _errorMessage = 'A timeline nao tem conteudo exportavel.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    _isExporting = true;
    _exportProgress = 0;
    _exportStartedAt = DateTime.now();
    _exportRemaining = null;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      await ffmpegService.exportProject(
        _project,
        outputPath,
        settings: settings,
        onProgress: (progress) {
          _exportProgress = progress.clamp(0.0, 1.0);
          final startedAt = _exportStartedAt;
          if (startedAt != null && _exportProgress >= 0.03) {
            final elapsed = DateTime.now().difference(startedAt);
            final remainingMicros =
                (elapsed.inMicroseconds *
                        (1 - _exportProgress) /
                        _exportProgress)
                    .round();
            _exportRemaining = Duration(
              microseconds: remainingMicros.clamp(
                0,
                const Duration(hours: 24).inMicroseconds,
              ),
            );
          }
          notifyListeners();
        },
      );
      _exportProgress = 1;
      _statusMessage =
          'Exportado com sucesso: $outputPath'
          '${ffmpegService.lastExportNotice == null ? '' : '\n${ffmpegService.lastExportNotice}'}';
    } on FfmpegExportCancelledException {
      _exportProgress = 0;
      _statusMessage = 'Exportacao cancelada.';
      _errorMessage = null;
    } catch (error) {
      _errorMessage = _cleanError(error);
      _statusMessage = null;
    } finally {
      _isExporting = false;
      _exportStartedAt = null;
      _exportRemaining = null;
      notifyListeners();
    }
  }

  void cancelExport() {
    if (!_isExporting) return;
    ffmpegService.cancelActiveExport();
    _statusMessage = 'Cancelando exportacao...';
    _errorMessage = null;
    notifyListeners();
  }

  void loadProjectFromData(ProjectLoadResult result) {
    _audioLevels.clear();
    _project = result.project;
    _clearTrimPreviewState();
    _clearHistory();
    _playheadPosition = Duration.zero;
    _selectedMediaItemId = null;
    _selectedTimelineGroupId = null;
    _selectedTimelineGroupIds.clear();
    _clipClipboard.clear();
    _isCutMode = false;
    _timelinePlaybackActive = false;
    _stopGapPlaybackTimer();
    _errorMessage = null;
    _statusMessage = null;
    _primeAudioWaveformCache();
    notifyListeners();
  }

  void dismissError() {
    _errorMessage = null;
    notifyListeners();
  }

  void dismissStatus() {
    _statusMessage = null;
    notifyListeners();
  }

  void _setSelectedTimelineGroups(Set<String> timelineGroupIds) {
    _selectedTimelineGroupIds
      ..clear()
      ..addAll(timelineGroupIds);
    _selectedTimelineGroupId = _selectedTimelineGroupIds.isEmpty
        ? null
        : _selectedTimelineGroupIds.last;
  }

  Set<String> _effectiveSelectedTimelineGroupIds() {
    if (_selectedTimelineGroupIds.isNotEmpty) {
      return Set<String>.from(_selectedTimelineGroupIds);
    }
    final selectedGroupId = _selectedTimelineGroupId;
    return selectedGroupId == null ? <String>{} : {selectedGroupId};
  }

  List<domain.Clip> _selectedTimelineClipsForType(TrackType trackType) {
    final selectedGroups = _effectiveSelectedTimelineGroupIds();
    if (selectedGroups.isEmpty) {
      return const [];
    }
    final clips = <domain.Clip>[];
    for (final track in _project.tracks) {
      for (final clip in track.clips) {
        if (clip.trackType != trackType) continue;
        if (selectedGroups.contains(clip.timelineGroupId)) {
          clips.add(clip);
        }
      }
    }
    clips.sort((a, b) {
      final startCompare = a.timelineStart.compareTo(b.timelineStart);
      if (startCompare != 0) {
        return startCompare;
      }
      return a.id.compareTo(b.id);
    });
    return clips;
  }

  void _commitProjectMutation(
    TgiProject nextProject, {
    Set<String>? selectedTimelineGroupIds,
    String? selectedTimelineGroupId,
    Duration? playheadPosition,
    bool syncGapPlaybackTimer = false,
  }) {
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    if (selectedTimelineGroupIds != null) {
      _setSelectedTimelineGroups(selectedTimelineGroupIds);
    }
    if (selectedTimelineGroupId != null) {
      _selectedTimelineGroupId = selectedTimelineGroupId;
      _selectedTimelineGroupIds.clear();
      _selectedTimelineGroupIds.add(selectedTimelineGroupId);
    }
    if (playheadPosition != null) {
      _playheadPosition = playheadPosition;
    }
    if (syncGapPlaybackTimer) {
      _syncGapPlaybackTimer();
    }
  }

  List<_ClipboardClip> _clipboardEntriesForGroups(Set<String> groups) {
    final entries = <_ClipboardClip>[];
    for (final track in _project.tracks) {
      for (final clip in track.clips) {
        if (groups.contains(clip.timelineGroupId)) {
          entries.add(_ClipboardClip(trackId: track.id, clip: clip));
        }
      }
    }
    entries.sort((a, b) {
      final timeCompare = a.clip.timelineStart.compareTo(b.clip.timelineStart);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return a.clip.id.compareTo(b.clip.id);
    });
    return entries;
  }

  _PasteClipboardResult _projectWithPastedClipboard(
    List<_ClipboardClip> entries, {
    required Duration timelineStart,
  }) {
    final copied = <String, List<domain.Clip>>{};
    final orderedIds = <String>{
      ..._project.tracks.map((track) => track.id),
      ...entries.map((entry) => entry.trackId),
    };
    for (final id in orderedIds) {
      final clips = entries
          .where((entry) => entry.trackId == id)
          .map((entry) => entry.clip)
          .toList();
      if (clips.isNotEmpty) copied[id] = clips;
    }
    final next = _project.pasteClips(copied, timelineStart: timelineStart);
    final existingGroups = {
      for (final track in _project.tracks)
        for (final clip in track.clips) clip.timelineGroupId,
    };
    return _PasteClipboardResult(next, {
      for (final track in next.tracks)
        for (final clip in track.clips)
          if (!existingGroups.contains(clip.timelineGroupId))
            clip.timelineGroupId,
    });
  }

  Track? _trackForClipId(String clipId) {
    return _trackForClipIdInProject(_project, clipId);
  }

  Track? _trackForClipIdInProject(TgiProject project, String clipId) {
    for (final track in project.tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) {
          return track;
        }
      }
    }
    return null;
  }

  bool _clipIsOnLockedTrack(String clipId) {
    return _trackForClipId(clipId)?.isLocked ?? false;
  }

  bool _clipIsOnLockedTrackInProject(TgiProject project, String clipId) {
    return _trackForClipIdInProject(project, clipId)?.isLocked ?? false;
  }

  bool _timelineGroupTouchesLockedTrack(String timelineGroupId) {
    for (final track in _project.tracks) {
      if (!track.isLocked) {
        continue;
      }
      if (track.clips.any((clip) => clip.timelineGroupId == timelineGroupId)) {
        return true;
      }
    }
    return false;
  }

  bool _timelineGroupsTouchLockedTracks(Set<String> timelineGroupIds) {
    if (timelineGroupIds.isEmpty) {
      return false;
    }
    for (final track in _project.tracks) {
      if (!track.isLocked) {
        continue;
      }
      if (track.clips.any(
        (clip) => timelineGroupIds.contains(clip.timelineGroupId),
      )) {
        return true;
      }
    }
    return false;
  }

  bool _lockedTimelineContentAtOrAfter(Duration position) {
    for (final track in _project.tracks) {
      if (!track.isLocked) continue;
      if (track.clips.any((clip) => clip.timelineStart >= position)) {
        return true;
      }
    }
    return false;
  }

  bool _audioTrackIsAudible(Track track) {
    if (track.type != TrackType.audio || track.isHidden || track.isMuted) {
      return false;
    }
    final hasSoloAudioTrack = _project.tracks.any(
      (candidate) =>
          candidate.type == TrackType.audio &&
          candidate.isSolo &&
          !candidate.isHidden,
    );
    return !hasSoloAudioTrack || track.isSolo;
  }

  Set<String> _timelineClipIds(TgiProject project) {
    return {
      for (final track in project.tracks)
        for (final clip in track.clips) clip.id,
    };
  }

  domain.Clip? _addedClipForItem(
    TgiProject project,
    Set<String> previousClipIds,
    String mediaItemId,
    TrackType trackType,
  ) {
    for (final track in project.tracks) {
      for (final clip in track.clips) {
        if (clip.trackType != trackType) continue;
        if (!previousClipIds.contains(clip.id) &&
            clip.mediaItemId == mediaItemId) {
          return clip;
        }
      }
    }
    return null;
  }

  domain.Clip? _addedClipForTrackType(
    TgiProject project,
    Set<String> previousClipIds,
    TrackType trackType,
  ) {
    for (final track in project.tracks) {
      for (final clip in track.clips) {
        if (clip.trackType != trackType) continue;
        if (!previousClipIds.contains(clip.id)) {
          return clip;
        }
      }
    }
    return null;
  }

  List<domain.Clip> _addedClipsForTrackType(
    TgiProject project,
    Set<String> previousClipIds,
    TrackType trackType,
  ) {
    final clips = <domain.Clip>[];
    for (final track in project.tracks) {
      for (final clip in track.clips) {
        if (clip.trackType != trackType) continue;
        if (!previousClipIds.contains(clip.id)) {
          clips.add(clip);
        }
      }
    }
    clips.sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    return clips;
  }

  void _addCaptionCuesToTimeline(
    List<CaptionCue> cues, {
    required String fontFamily,
    required double fontSize,
    required int textColor,
    required int backgroundColor,
    required double opacity,
    required domain.TextClipAnimation textAnimation,
  }) {
    final previousClipIds = _timelineClipIds(_project);
    var nextProject = _project;
    for (final cue in cues) {
      if (cue.end <= cue.start || cue.text.trim().isEmpty) {
        continue;
      }
      nextProject = nextProject.addTextClipToTimeline(
        text: cue.text,
        isCaption: true,
        timelineStart: cue.start,
        duration: cue.duration,
        fontFamily: fontFamily,
        fontSize: fontSize,
        textColor: textColor,
        backgroundColor: backgroundColor,
        opacity: opacity,
        textAnimation: textAnimation,
      );
    }
    if (identical(nextProject, _project)) {
      return;
    }

    _pushHistory();
    _project = nextProject;
    final addedTextClips = _addedClipsForTrackType(
      _project,
      previousClipIds,
      TrackType.text,
    );
    final selectedClip = addedTextClips.isEmpty ? null : addedTextClips.last;
    _selectedMediaItemId = null;
    _selectedTimelineGroupId = selectedClip?.timelineGroupId;
    _setSelectedTimelineGroups(
      _selectedTimelineGroupId == null ? const {} : {_selectedTimelineGroupId!},
    );
    _playheadPosition = cues.first.start;
    _syncGapPlaybackTimer();
  }

  Future<List<CaptionCue>> _alignCaptionCuesToAudio(
    List<CaptionCue> cues,
    MediaItem mediaItem,
  ) async {
    if (cues.isEmpty) {
      return cues;
    }
    try {
      final waveform = await audioWaveformService.extractWaveform(mediaItem);
      if (waveform.samples.isEmpty ||
          waveform.sampleInterval <= Duration.zero) {
        return cues;
      }
      return [
        for (final cue in cues)
          _captionTiming.alignCaptionCueToWaveform(cue, waveform),
      ];
    } catch (_) {
      return cues;
    }
  }

  List<CaptionCue> _timelineCaptionCuesForClip(
    List<CaptionCue> sourceCues,
    domain.Clip clip,
  ) {
    final timingClip = _audioClipForTimelineGroup(clip.timelineGroupId) ?? clip;
    final clipSourceStart = timingClip.sourceStart;
    final clipSourceEnd = timingClip.sourceEnd;
    final cues = <CaptionCue>[];
    for (final cue in sourceCues) {
      final overlapStart = _maxDuration(cue.start, clipSourceStart);
      final overlapEnd = _minDuration(cue.end, clipSourceEnd);
      if (overlapEnd <= overlapStart) {
        continue;
      }

      final timelineStart =
          timingClip.timelineStart +
          _timelineDurationForSource(
            overlapStart - clipSourceStart,
            timingClip.playbackSpeed,
          );
      final timelineEnd =
          timingClip.timelineStart +
          _timelineDurationForSource(
            overlapEnd - clipSourceStart,
            timingClip.playbackSpeed,
          );
      if (timelineEnd <= timelineStart) {
        continue;
      }
      cues.add(
        CaptionCue(start: timelineStart, end: timelineEnd, text: cue.text),
      );
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return _captionTiming.resolveCaptionCueOverlaps(
      cues,
      timelineLimit: timingClip.timelineEnd,
    );
  }

  List<CaptionCue> _generatedCaptionCuesFromProject() {
    return _generatedCaptionClipsFromProject()
        .map(
          (clip) => CaptionCue(
            start: clip.timelineStart,
            end: clip.timelineEnd,
            text: clip.textContent.trim(),
          ),
        )
        .toList(growable: false);
  }

  List<domain.Clip> _generatedCaptionClipsFromProject() {
    final clips = <domain.Clip>[];
    for (final track in _project.tracks) {
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.text) continue;
        if (!clip.isCaption ||
            clip.textContent.trim().isEmpty ||
            clip.duration <= Duration.zero) {
          continue;
        }
        clips.add(clip);
      }
    }
    clips.sort((a, b) {
      final time = a.timelineStart.compareTo(b.timelineStart);
      if (time != 0) return time;
      int number(String id) =>
          int.tryParse(RegExp(r'\d+').firstMatch(id)?.group(0) ?? '') ?? 0;
      return number(a.id).compareTo(number(b.id));
    });
    return clips;
  }

  domain.Clip? _findClipById(String clipId) {
    return _findClipByIdInProject(_project, clipId);
  }

  domain.Clip? _findClipByIdInProject(TgiProject project, String clipId) =>
      project.clipById(clipId);

  domain.Clip? _clipForTimelineGroupInProject(
    TgiProject project,
    String timelineGroupId,
    List<TrackType> preferredTypes,
  ) {
    for (final type in preferredTypes) {
      for (final track in project.tracks) {
        for (final clip in track.clips) {
          if (clip.trackType != type) continue;
          if (clip.timelineGroupId == timelineGroupId) {
            return clip;
          }
        }
      }
    }
    return null;
  }

  bool _timelineGroupHasClipType(String timelineGroupId, TrackType type) {
    for (final track in _project.tracks) {
      if (track.clips.any(
        (clip) =>
            clip.trackType == type && clip.timelineGroupId == timelineGroupId,
      )) {
        return true;
      }
    }
    return false;
  }

  ({String audioTimelineGroupId, String videoTimelineGroupId})?
  get _selectedAudioVideoRelinkCandidate {
    final selected = selectedTimelineClip;
    if (selected == null ||
        (selected.trackType != TrackType.video &&
            selected.trackType != TrackType.audio) ||
        selectedAudioVideoLinked) {
      return null;
    }

    final targetType = selected.trackType == TrackType.video
        ? TrackType.audio
        : TrackType.video;
    for (final track in _project.tracks) {
      for (final candidate in track.clips) {
        if (candidate.trackType != targetType) continue;
        if (candidate.timelineGroupId == selected.timelineGroupId ||
            !_clipsRemainAlignedForRelink(selected, candidate)) {
          continue;
        }
        final audio = selected.trackType == TrackType.audio
            ? selected
            : candidate;
        final video = selected.trackType == TrackType.video
            ? selected
            : candidate;
        return (
          audioTimelineGroupId: audio.timelineGroupId,
          videoTimelineGroupId: video.timelineGroupId,
        );
      }
    }
    return null;
  }

  bool _clipsRemainAlignedForRelink(domain.Clip first, domain.Clip second) {
    return first.mediaItemId == second.mediaItemId &&
        first.timelineStart == second.timelineStart &&
        first.sourceStart == second.sourceStart &&
        first.duration == second.duration &&
        first.sourceDuration == second.sourceDuration &&
        (first.playbackSpeed - second.playbackSpeed).abs() < 0.000001;
  }

  domain.Clip? get _selectedOrActiveVideoClip {
    return _selectedVideoClip ?? activeTimelineClip;
  }

  List<domain.Clip> get _captionSourceVideoClips {
    if (_selectedTimelineGroupIds.isNotEmpty) {
      final selectedClips = <domain.Clip>[];
      for (final track in _project.tracks) {
        if (track.isHidden) continue;
        for (final clip in track.clips) {
          if (clip.trackType != TrackType.video) continue;
          if (_selectedTimelineGroupIds.contains(clip.timelineGroupId) &&
              clip.duration > Duration.zero) {
            selectedClips.add(clip);
          }
        }
      }
      if (selectedClips.isNotEmpty) {
        selectedClips.sort(
          (first, second) =>
              first.timelineStart.compareTo(second.timelineStart),
        );
        return selectedClips;
      }
    }

    final active = activeTimelineClip;
    if (active != null) {
      return [active];
    }
    for (final track in _project.tracks) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.video) continue;
        if (clip.duration > Duration.zero) {
          return [clip];
        }
      }
    }
    return const [];
  }

  domain.Clip? get _selectedVideoClip {
    final selectedGroupId = _selectedTimelineGroupId;
    if (selectedGroupId == null) {
      return null;
    }
    return _videoClipForTimelineGroup(selectedGroupId);
  }

  domain.Clip? _videoClipForTimelineGroup(String timelineGroupId) {
    return _clipForTimelineGroup(timelineGroupId, const [TrackType.video]);
  }

  domain.Clip? _audioClipForTimelineGroup(String timelineGroupId) {
    return _clipForTimelineGroup(timelineGroupId, const [TrackType.audio]);
  }

  domain.Clip? _clipForTimelineGroup(
    String timelineGroupId,
    List<TrackType> preferredTypes,
  ) {
    for (final type in preferredTypes) {
      for (final track in _project.tracks) {
        for (final clip in track.clips) {
          if (clip.trackType != type) continue;
          if (clip.timelineGroupId == timelineGroupId) {
            return clip;
          }
        }
      }
    }
    return null;
  }

  domain.Clip? _overlayClipForTimelineGroup(String timelineGroupId) {
    return _clipForTimelineGroup(timelineGroupId, const [
      TrackType.image,
      TrackType.text,
    ]);
  }

  bool _clipContainsTimelinePosition(
    domain.Clip clip,
    Duration timelinePosition,
  ) {
    return clip.timelineStart <= timelinePosition &&
        timelinePosition < clip.timelineEnd;
  }

  double _normalizedClipTimeAtPlayhead(domain.Clip clip) {
    if (clip.duration <= Duration.zero) {
      return 0;
    }
    final value =
        (_playheadPosition - clip.timelineStart).inMicroseconds /
        clip.duration.inMicroseconds;
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _keyframedClipValueAtPlayhead(
    domain.Clip clip,
    domain.ClipKeyframeProperty property,
  ) {
    if (!_clipContainsTimelinePosition(clip, _playheadPosition)) {
      return clip.baseValueForKeyframeProperty(property);
    }
    return clip.keyframedValue(property, _normalizedClipTimeAtPlayhead(clip));
  }

  Duration _sourcePositionForTimelineClip(
    domain.Clip clip,
    Duration timelinePosition, {
    bool reverseAware = false,
  }) {
    final timelineDelta = _clampDuration(
      timelinePosition - clip.timelineStart,
      Duration.zero,
      clip.duration,
    );
    final sourceDelta = _sourceDurationForTimeline(
      timelineDelta,
      clip.playbackSpeed,
    );
    if (reverseAware && clip.reverseVideo) {
      final sourcePosition =
          clip.sourceEnd - sourceDelta - const Duration(milliseconds: 1);
      return _clampDuration(sourcePosition, clip.sourceStart, clip.sourceEnd);
    }
    final sourcePosition = clip.sourceStart + sourceDelta;
    return _clampDuration(sourcePosition, clip.sourceStart, clip.sourceEnd);
  }

  _TimelineVideoTransitionTarget? _nearestVideoTransitionTarget(
    Duration targetPosition,
  ) {
    final targets = _videoTransitionTargets(_project);
    if (targets.isEmpty) {
      return null;
    }
    _TimelineVideoTransitionTarget? nearest;
    var nearestDistanceUs = 0;
    for (final target in targets) {
      final distanceUs = (target.position - targetPosition).inMicroseconds
          .abs();
      if (nearest == null || distanceUs < nearestDistanceUs) {
        nearest = target;
        nearestDistanceUs = distanceUs;
      }
    }
    return nearest;
  }

  List<_TimelineVideoTransitionTarget> _videoTransitionTargets(
    TgiProject project,
  ) {
    final targets = <_TimelineVideoTransitionTarget>[];
    for (final track in project.tracks) {
      if (track.isHidden) continue;
      final clips =
          track.clips
              .where(
                (clip) =>
                    clip.trackType == TrackType.video &&
                    clip.duration > Duration.zero,
              )
              .toList()
            ..sort(
              (first, second) =>
                  first.timelineStart.compareTo(second.timelineStart),
            );
      final ends = {for (final clip in clips) clip.timelineEnd.inMilliseconds};
      for (final clip in clips) {
        if (!ends.contains(clip.timelineStart.inMilliseconds)) {
          targets.add(
            _TimelineVideoTransitionTarget(
              position: clip.timelineStart,
              trackId: track.id,
              placement: TimelineTransitionPlacement.start,
            ),
          );
        }
      }
    }
    for (final edit in _videoEdits(project)) {
      targets.add(
        _TimelineVideoTransitionTarget(
          position: edit.position,
          trackId: edit.trackId,
          placement: TimelineTransitionPlacement.centered,
        ),
      );
    }
    targets.sort((first, second) {
      final timeCompare = first.position.compareTo(second.position);
      if (timeCompare != 0) {
        return timeCompare;
      }
      final placementCompare = first.placement.index.compareTo(
        second.placement.index,
      );
      if (placementCompare != 0) {
        return placementCompare;
      }
      return first.trackId.compareTo(second.trackId);
    });
    return targets;
  }

  _TimelineVideoEdit? _nearestVideoEdit(Duration targetPosition) {
    final edits = _videoEdits(_project);
    if (edits.isEmpty) {
      return null;
    }

    _TimelineVideoEdit? nearest;
    var nearestDistanceUs = 0;
    for (final edit in edits) {
      final distanceUs = (edit.position - targetPosition).inMicroseconds.abs();
      if (nearest == null || distanceUs < nearestDistanceUs) {
        nearest = edit;
        nearestDistanceUs = distanceUs;
      }
    }
    return nearest;
  }

  List<_TimelineVideoEdit> _videoEdits(TgiProject project) {
    final edits = <_TimelineVideoEdit>[];
    for (final track in project.tracks) {
      if (track.isHidden) continue;
      final starts = <int>{};
      final ends = <int>{};
      for (final clip in track.clips.where(
        (clip) => clip.trackType == TrackType.video,
      )) {
        if (clip.duration <= Duration.zero) {
          continue;
        }
        starts.add(clip.timelineStart.inMilliseconds);
        ends.add(clip.timelineEnd.inMilliseconds);
      }
      for (final value in ends) {
        if (value > 0 && starts.contains(value)) {
          edits.add(
            _TimelineVideoEdit(
              position: Duration(milliseconds: value),
              trackId: track.id,
            ),
          );
        }
      }
    }

    edits.sort((a, b) {
      final timeCompare = a.position.compareTo(b.position);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return a.trackId.compareTo(b.trackId);
    });
    return edits;
  }

  bool _timelineInsertTouchesLockedTrack(Duration position) {
    for (final track in _project.tracks) {
      if (!track.isLocked) {
        continue;
      }
      if (track.clips.any((clip) => clip.timelineStart >= position)) {
        return true;
      }
    }
    return false;
  }

  double _clipFadeOpacityAt(domain.Clip clip, Duration timelinePosition) {
    if (clip.duration <= Duration.zero) {
      return 1;
    }
    if (!_clipContainsTimelinePosition(clip, timelinePosition)) {
      return 0;
    }

    var opacity = 1.0;
    final elapsed = timelinePosition - clip.timelineStart;
    final remaining = clip.timelineEnd - timelinePosition;

    if (clip.fadeIn > Duration.zero && elapsed < clip.fadeIn) {
      final fadeOpacity = elapsed.inMicroseconds / clip.fadeIn.inMicroseconds;
      opacity = opacity < fadeOpacity ? opacity : fadeOpacity;
    }

    if (clip.fadeOut > Duration.zero && remaining < clip.fadeOut) {
      final fadeOpacity =
          remaining.inMicroseconds / clip.fadeOut.inMicroseconds;
      opacity = opacity < fadeOpacity ? opacity : fadeOpacity;
    }

    if (opacity.isNaN || opacity.isInfinite) {
      return 1;
    }
    return opacity.clamp(0.0, 1.0).toDouble();
  }

  bool get _hasExportableTimelineClips {
    for (final track in _project.tracks) {
      if (track.isHidden || (track.type == TrackType.audio && track.isMuted)) {
        continue;
      }
      if ((track.type == TrackType.video ||
              track.type == TrackType.image ||
              track.type == TrackType.text ||
              track.type == TrackType.audio) &&
          track.clips.any((clip) => clip.duration > Duration.zero)) {
        return true;
      }
    }
    return false;
  }

  bool _hasVisibleVideoAt(Duration position) {
    return _project.clipAt(position, trackType: TrackType.video) != null;
  }

  void _primeAudioWaveformCache() {
    for (final item in _project.mediaPool) {
      _ensureAudioWaveform(item);
    }
  }

  void _ensureAudioWaveform(MediaItem item) {
    if (item.type != MediaType.video && item.type != MediaType.audio) {
      return;
    }
    if (_audioWaveformsByMediaId.containsKey(item.id) ||
        !_audioWaveformLoadsInFlight.add(item.id)) {
      return;
    }

    unawaited(
      audioWaveformService
          .extractWaveform(item)
          .then((waveform) {
            _audioWaveformsByMediaId[item.id] = waveform;
          })
          .catchError((Object _) {})
          .whenComplete(() {
            _audioWaveformLoadsInFlight.remove(item.id);
            if (!_disposed) {
              notifyListeners();
            }
          }),
    );
  }

  Duration _normalizeTimelinePosition(Duration position) {
    return position < Duration.zero ? Duration.zero : position;
  }

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  Duration _minDuration(Duration first, Duration second) {
    return first <= second ? first : second;
  }

  Duration _maxDuration(Duration first, Duration second) {
    return first >= second ? first : second;
  }

  double _clampPlaybackSpeed(double value) {
    if (value.isNaN || value.isInfinite || value <= 0) {
      return 1;
    }
    return value.clamp(0.25, 4.0).toDouble();
  }

  Duration _sourceDurationForTimeline(
    Duration timelineDuration,
    double playbackSpeed,
  ) {
    if (timelineDuration <= Duration.zero) {
      return Duration.zero;
    }
    return Duration(
      microseconds:
          (timelineDuration.inMicroseconds * _clampPlaybackSpeed(playbackSpeed))
              .round(),
    );
  }

  Duration _timelineDurationForSource(
    Duration sourceDuration,
    double playbackSpeed,
  ) {
    if (sourceDuration <= Duration.zero) {
      return Duration.zero;
    }
    final microseconds =
        (sourceDuration.inMicroseconds / _clampPlaybackSpeed(playbackSpeed))
            .round();
    return Duration(microseconds: microseconds <= 0 ? 1 : microseconds);
  }

  void _syncGapPlaybackTimer() {
    final activeClip = activeTimelineClip;
    final shouldRun =
        !_disposed &&
        _timelinePlaybackActive &&
        _project.hasTimelineClips &&
        (activeClip == null || activeClip.reverseVideo) &&
        _playheadPosition < _project.timelineDuration;
    if (!shouldRun) {
      _stopGapPlaybackTimer();
      return;
    }
    if (_gapPlaybackTimer != null) {
      return;
    }

    _lastGapPlaybackTickAt = DateTime.now();
    _gapPlaybackTimer = Timer.periodic(_gapPlaybackInterval, (_) {
      final now = DateTime.now();
      final previousTick = _lastGapPlaybackTickAt ?? now;
      _lastGapPlaybackTickAt = now;
      _advanceGapPlaybackBy(now.difference(previousTick));
    });
  }

  void _stopGapPlaybackTimer() {
    _gapPlaybackTimer?.cancel();
    _gapPlaybackTimer = null;
    _lastGapPlaybackTickAt = null;
  }

  void _advanceGapPlaybackBy(Duration elapsed) {
    if (_disposed || !_timelinePlaybackActive || elapsed <= Duration.zero) {
      return;
    }
    final activeClip = activeTimelineClip;
    if (activeClip != null && !activeClip.reverseVideo) {
      _syncGapPlaybackTimer();
      return;
    }

    final timelineDuration = _project.timelineDuration;
    if (!_project.hasTimelineClips || _playheadPosition >= timelineDuration) {
      setTimelinePlaybackActive(false);
      return;
    }

    final nextClip = activeClip == null
        ? _nextVideoClipAfter(_playheadPosition)
        : null;
    final rawNext = _playheadPosition + elapsed;
    var next = rawNext > timelineDuration ? timelineDuration : rawNext;
    if (activeClip != null && next >= activeClip.timelineEnd) {
      next = activeClip.timelineEnd;
    }
    if (nextClip != null && nextClip.timelineStart <= next) {
      next = nextClip.timelineStart;
    }

    setPlayheadPosition(next);
    if (_playheadPosition >= timelineDuration) {
      setTimelinePlaybackActive(false);
    }
  }

  domain.Clip? _nextVideoClipAfter(Duration position) {
    domain.Clip? nextClip;
    final mainTrackId = _mainVideoTrackId();
    for (final track in _project.tracks) {
      if (track.id != mainTrackId || track.isHidden) {
        continue;
      }
      for (final clip in track.clips) {
        if (clip.timelineStart <= position) {
          continue;
        }
        if (nextClip == null || clip.timelineStart < nextClip.timelineStart) {
          nextClip = clip;
        }
      }
    }
    return nextClip;
  }

  domain.Clip? _nextVideoClipAfterActiveClip(domain.Clip activeClip) {
    final earliestAllowed = activeClip.timelineEnd - _clipBoundaryTolerance;
    domain.Clip? nextClip;
    for (final track in _project.tracks) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.video) continue;
        if (clip.id == activeClip.id || clip.timelineStart < earliestAllowed) {
          continue;
        }
        if (nextClip == null || clip.timelineStart < nextClip.timelineStart) {
          nextClip = clip;
        }
      }
    }
    return nextClip;
  }

  domain.Clip? _clipForPreviewSourcePosition(
    String mediaItemId,
    Duration sourcePosition,
  ) {
    final timelineClip = activeTimelineClip;
    if (timelineClip != null &&
        timelineClip.mediaItemId == mediaItemId &&
        _sourcePositionBelongsToClip(timelineClip, sourcePosition)) {
      return timelineClip;
    }

    final matchingClip = _bestClipForPreviewSourcePosition(
      mediaItemId,
      sourcePosition,
      includeEnd: false,
    );
    if (matchingClip != null) {
      return matchingClip;
    }

    return _bestClipForPreviewSourcePosition(
      mediaItemId,
      sourcePosition,
      includeEnd: true,
    );
  }

  Duration? _timelineBoundaryForPreviewSourceOverflow(
    String mediaItemId,
    Duration sourcePosition,
  ) {
    final timelineClip = activeTimelineClip;
    if (timelineClip == null || timelineClip.mediaItemId != mediaItemId) {
      return null;
    }
    if (sourcePosition < timelineClip.sourceEnd) {
      return null;
    }

    final nextSameSourceClip =
        _bestClipForPreviewSourcePosition(
          mediaItemId,
          sourcePosition,
          includeEnd: false,
        ) ??
        _bestClipForPreviewSourcePosition(
          mediaItemId,
          sourcePosition,
          includeEnd: true,
        );
    if (nextSameSourceClip != null &&
        nextSameSourceClip.id != timelineClip.id &&
        _clipsAreAdjacentOnTimeline(timelineClip, nextSameSourceClip)) {
      return null;
    }

    _logController(
      'preview-position reached clip boundary media=$mediaItemId '
      'source=${_formatControllerTime(sourcePosition)} '
      'active=${_clipDebugLabel(timelineClip)} '
      'nextSameSource=${nextSameSourceClip == null ? 'null' : _clipDebugLabel(nextSameSourceClip)} '
      'boundary=${_formatControllerTime(timelineClip.timelineEnd)}',
    );
    return timelineClip.timelineEnd;
  }

  bool _clipsAreAdjacentOnTimeline(domain.Clip first, domain.Clip second) {
    return (second.timelineStart - first.timelineEnd).inMilliseconds.abs() <=
        _clipBoundaryTolerance.inMilliseconds;
  }

  domain.Clip? _bestClipForPreviewSourcePosition(
    String mediaItemId,
    Duration sourcePosition, {
    required bool includeEnd,
  }) {
    domain.Clip? bestClip;
    for (final track in _project.tracks) {
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.video) continue;
        if (clip.mediaItemId != mediaItemId ||
            !_sourcePositionBelongsToClip(
              clip,
              sourcePosition,
              includeEnd: includeEnd,
            )) {
          continue;
        }
        if (bestClip == null ||
            _distanceFromPlayheadMs(clip) < _distanceFromPlayheadMs(bestClip)) {
          bestClip = clip;
        }
      }
    }
    return bestClip;
  }

  bool _sourcePositionBelongsToClip(
    domain.Clip clip,
    Duration sourcePosition, {
    bool includeEnd = false,
  }) {
    final sourceEnd = clip.sourceEnd;
    if (sourcePosition < clip.sourceStart) {
      return false;
    }
    return includeEnd
        ? sourcePosition <= sourceEnd
        : sourcePosition < sourceEnd;
  }

  int _distanceFromPlayheadMs(domain.Clip clip) {
    return (clip.timelineStart - _playheadPosition).inMilliseconds.abs();
  }

  String _cleanError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  String _formatControllerTime(Duration duration) {
    final totalMilliseconds = duration.inMilliseconds;
    final totalSeconds = totalMilliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final millis = totalMilliseconds % 1000;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  void _logController(String message) {
    EditorDebugLog.write('controller', message);
  }

  String _videoClipDebugSummary({TgiProject? project}) {
    final targetProject = project ?? _project;
    final clips = <String>[];
    for (final track in targetProject.tracks) {
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.video) continue;
        clips.add('${track.id}:${_clipDebugLabel(clip)}');
      }
    }
    return clips.isEmpty ? '[]' : '[${clips.join(' | ')}]';
  }

  String _clipDebugLabel(domain.Clip clip) {
    return '${clip.id}/${clip.mediaItemId}/${clip.timelineGroupId}'
        '@${_formatControllerTime(clip.timelineStart)}'
        '+${_formatControllerTime(clip.duration)}';
  }
}
