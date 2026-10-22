import '../../../mcp/editor_automation.dart';
import 'widgets/mcp_settings_dialog.dart';
import '../../../services/subtitle_service.dart';
import 'caption_style_dialog.dart';
import '../../../domain/models/cross_dissolve.dart';
import '../../../app/app_identity.dart';
import 'dart:async';
import 'editor_keyboard.dart';
import 'editor_preview_values.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../domain/models/clip.dart' as domain;
import '../../../domain/text_style_profile.dart';
import 'widgets/styled_caption_text.dart';
import '../../../domain/models/media_item.dart';
import '../../../domain/models/project.dart';
import '../../../domain/models/timeline_transition.dart';
import '../../../domain/models/track.dart';
import '../../../services/app_preferences_service.dart';
import '../../../services/app_component_paths.dart';
import '../../../services/editor_debug_log.dart';
import '../../../services/editor_font_service.dart';
import '../../../services/project_history_service.dart';
import '../../../services/project_collection_service.dart';
import '../../../services/editor_preset_service.dart';
import '../../../services/export_destination_service.dart';
import '../../../services/auto_caption_service.dart';
import '../../../services/whisper_runtime.dart';
import '../../../services/ffmpeg_service.dart';
import '../../../services/media_import_service.dart';
import '../../../services/project_io_service.dart';
import '../../../services/project_recovery_service.dart';
import '../../../services/recent_project_service.dart';
import '../../../services/sound_effects_service.dart';
import '../../../services/visual_media_service.dart';
import '../../hub/presentation/premium_downloads_dialog.dart';
import '../application/editor_controller.dart';
import 'duration_formatter.dart';
import 'widgets/animation_tool_panel.dart';
import 'widgets/mascot_notification.dart';
import 'widgets/audio_tool_panel.dart';
import 'widgets/advanced_speed_panel.dart';
import 'widgets/captions_panel.dart';
import 'widgets/whisper_models_dialog.dart';
import '../../../services/whisper_model_service.dart';
import 'widgets/chroma_key_panel.dart';
import 'widgets/mask_tracking_panel.dart';
import 'widgets/media_pool_list.dart';
import 'widgets/preview_entries.dart';
import 'widgets/professional_color_panel.dart';
import 'widgets/sound_effects_library_panel.dart';
import 'widgets/smart_cut_panel.dart';
import 'widgets/timeline_panel.dart';
import 'widgets/transition_library_panel.dart';
import 'widgets/transform_crop_panel.dart';
import 'widgets/video_preview_panel.dart';
import 'widgets/visual_media_library_panel.dart';

part 'editor_caption_actions.dart';
part 'editor_workspace_layout.dart';
part 'editor_desktop_workspace.dart';
part 'editor_header.dart';
part 'editor_screen_support.dart';
part 'editor_clip_properties.dart';
part 'editor_dialogs.dart';
part 'editor_shell.dart';
part 'editor_project_actions.dart';

enum _LeftPanelMode {
  mediaPool,
  transformCrop,
  audioTools,
  smartCut,
  professionalColor,
  advancedSpeed,
  animations,
  captions,
  chromaKey,
  maskTracking,
  soundEffects,
  visualMedia,
  transitions,
}

enum EditorStartPreset { standard, quickCreator, square, feed45 }

enum _KenBurnsPickTarget { start, end }

const _workspaceDividerExtent = 8.0;
const _defaultLeftPanelFraction = 280 / 1440;
const _defaultPropertiesPanelFraction = _defaultLeftPanelFraction;
const _defaultPreviewPanelFraction = 0.55;
const _minLeftPanelFraction = 0.12;
const _maxLeftPanelFraction = 0.36;
const _minPropertiesPanelFraction = 0.12;
const _maxPropertiesPanelFraction = 0.29;
const _minCenterPanelFraction = 0.42;
const _workspaceLayoutSaveDelay = Duration(milliseconds: 450);
const _projectAutosaveDelay = Duration(seconds: 2);
const _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

TgiProject? _projectForStartPreset(EditorStartPreset preset) {
  switch (preset) {
    case EditorStartPreset.standard:
      return null;
    case EditorStartPreset.quickCreator:
      return TgiProject.empty(name: 'Shorts 9:16');
    case EditorStartPreset.square:
      return TgiProject.empty(name: 'Quadrado 1:1');
    case EditorStartPreset.feed45:
      return TgiProject.empty(name: 'Feed 4:5');
  }
}

FfmpegExportSettings _exportSettingsForStartPreset(EditorStartPreset preset) {
  switch (preset) {
    case EditorStartPreset.standard:
      return FfmpegExportSettings.uiDefault;
    case EditorStartPreset.quickCreator:
      return FfmpegExportSettings.quickCreator;
    case EditorStartPreset.square:
      return FfmpegExportSettings.squareSocial;
    case EditorStartPreset.feed45:
      return FfmpegExportSettings.feed45;
  }
}

EditorStartPreset editorStartPresetForProject(
  TgiProject project, {
  FfmpegExportSettings? exportSettings,
}) {
  final resolution = exportSettings?.resolution;
  if (resolution == FfmpegExportResolution.shorts1080) {
    return EditorStartPreset.quickCreator;
  }
  if (resolution == FfmpegExportResolution.square1080) {
    return EditorStartPreset.square;
  }
  if (resolution == FfmpegExportResolution.feed1080x1350) {
    return EditorStartPreset.feed45;
  }
  if (resolution != null) {
    return EditorStartPreset.standard;
  }
  return switch (project.name.trim().toLowerCase()) {
    'shorts 9:16' => EditorStartPreset.quickCreator,
    'quadrado 1:1' => EditorStartPreset.square,
    'feed 4:5' => EditorStartPreset.feed45,
    _ => EditorStartPreset.standard,
  };
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    this.startPreset = EditorStartPreset.standard,
    this.initialProject,
    this.initialProjectPath,
    this.initialExportSettings,
    this.initialMissingMediaItems = const [],
    this.initialMediaPath,
    this.hasPaidPlan = false,
    this.isRecoveredDraft = false,
    this.projectIOService,
    this.projectRecoveryService,
    this.recentProjectService,
    this.projectHistoryService,
    this.workspaceLayoutPath,
  });

  const EditorScreen.quickCreator({super.key})
    : startPreset = EditorStartPreset.quickCreator,
      initialProject = null,
      initialProjectPath = null,
      initialExportSettings = null,
      initialMissingMediaItems = const [],
      initialMediaPath = null,
      hasPaidPlan = false,
      isRecoveredDraft = false,
      projectIOService = null,
      projectRecoveryService = null,
      recentProjectService = null,
      projectHistoryService = null,
      workspaceLayoutPath = null;

  final EditorStartPreset startPreset;
  final TgiProject? initialProject;
  final String? initialProjectPath;
  final FfmpegExportSettings? initialExportSettings;
  final List<Map<String, dynamic>> initialMissingMediaItems;
  final String? initialMediaPath;
  final bool hasPaidPlan;
  final bool isRecoveredDraft;
  final ProjectIOService? projectIOService;
  final ProjectRecoveryService? projectRecoveryService;
  final RecentProjectService? recentProjectService;
  final ProjectHistoryService? projectHistoryService;

  /// Optional preference location for isolated workspaces and headless tests.
  final String? workspaceLayoutPath;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _UnsavedProjectChoice { save, discard, cancel }

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController _controller;
  late final EditorAutomation _automation;
  final _editorFocusNode = FocusNode(debugLabel: 'TGI editor shortcuts');
  late final _projectHistoryService =
      widget.projectHistoryService ?? ProjectHistoryService();
  final _editorPresetService = EditorPresetService();
  DateTime? _lastVersionAt;
  String? _lastVersionProjectId;
  bool _projectToolBusy = false;
  void _refreshEditor(VoidCallback action) {
    if (mounted) setState(action);
  }

  late final _projectIOService = widget.projectIOService ?? ProjectIOService();
  late final _projectRecoveryService =
      widget.projectRecoveryService ?? ProjectRecoveryService();
  late final _recentProjectService =
      widget.recentProjectService ?? const RecentProjectService();
  final _soundEffectsService = PublicSoundEffectsService();
  final _visualMediaService = PublicVisualMediaService();
  Player? _soundEffectPreviewPlayer;
  StreamSubscription<bool>? _soundEffectPreviewCompletedSubscription;
  StreamSubscription<Duration>? _soundEffectPreviewPositionSubscription;
  StreamSubscription<Duration>? _soundEffectPreviewDurationSubscription;
  late FfmpegExportSettings _exportSettings;
  _LeftPanelMode _leftPanelMode = _LeftPanelMode.mediaPool;
  SmartCutIntensity _smartCutIntensity = SmartCutIntensity.balanced;
  String? _addingSoundEffectId;
  String? _addingVisualMediaId;
  String? _previewingSoundEffectId;
  String? _loadingPreviewSoundEffectId;
  String? _lastControllerDebugSnapshot;
  String? _currentProjectPath;
  TgiProject? _lastSavedProjectSnapshot;
  TgiProject? _lastAutosaveObservedProject;
  FfmpegExportSettings? _lastSavedExportSettings;
  FfmpegExportSettings? _lastAutosaveObservedExportSettings;
  Timer? _projectAutosaveDebounce;
  bool _recoveredDraftPending = false;
  bool _autosaveNotificationShown = false;
  bool _ownsRecoveryDraft = false;
  bool _allowPopWithoutSave = false;
  bool _leavingEditor = false;
  int _projectSessionRevision = 0;
  int _recoveryRevision = 0;
  Future<bool>? _projectSaveOperation;
  bool _rewardedAccessGranted = false;
  Duration _soundEffectPreviewPosition = Duration.zero;
  Duration _soundEffectPreviewDuration = Duration.zero;
  int _soundEffectPreviewRevision = 0;
  final _timelineKey = GlobalKey<TimelinePanelState>();
  double _leftPanelFraction = _defaultLeftPanelFraction;
  double _propertiesPanelFraction = _defaultPropertiesPanelFraction;
  double _previewPanelFraction = _defaultPreviewPanelFraction;
  bool _timelineFocusMode = false;
  bool _inspectorVisible = true;
  bool _libraryVisible = true;
  _EditorLibraryTab _libraryTab = _EditorLibraryTab.media;
  String? _inspectedClipId;
  bool _kenBurnsToolActive = false;
  AnimationIntensity _animationIntensity = AnimationIntensity.normal;
  AnimationSpeed _animationSpeed = AnimationSpeed.normal;
  bool _transformCropModeActive = false;
  bool _chromaColorPickerActive = false;
  bool _chromaTransparencyPreview = true;
  bool _whiteBalancePickerActive = false;
  bool _colorCompareOriginal = false;
  bool _colorAnalysisLoading = false;
  int _colorAnalysisRequest = 0;
  VideoColorAnalysis? _colorAnalysis;
  _KenBurnsPickTarget _kenBurnsPickTarget = _KenBurnsPickTarget.start;
  bool _layoutChangedByUser = false;
  Timer? _layoutSaveDebounce;
  Timer? _statusAutoDismissTimer;
  Timer? _errorAutoDismissTimer;
  String? _statusAutoDismissMessage;
  String? _errorAutoDismissMessage;
  late Map<EditorShortcutAction, SingleActivator> _shortcutBindings =
      defaultEditorShortcutBindings();
  String? _preferredOutputDirectory;
  _AutoCaptionsDialogResult? _lastAutoCaptionsSettings;

  bool get _isQuickCreator =>
      widget.startPreset == EditorStartPreset.quickCreator;

  void _showEditorNotification(
    String message, {
    TgiNotificationTone tone = TgiNotificationTone.standard,
    Duration duration = const Duration(seconds: 2),
  }) {
    const maxDuration = Duration(seconds: 2);
    final effectiveDuration = duration > maxDuration ? maxDuration : duration;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: TgiColors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(
            TgiSpacing.xl,
            0,
            TgiSpacing.xl,
            TgiSpacing.xl,
          ),
          duration: effectiveDuration,
          content: TgiMascotNotification(
            message: message,
            tone: tone,
            compact: true,
          ),
        ),
      );
  }

  Future<void> _saveProject() async {
    await _saveProjectToDisk();
  }

  Future<bool> _saveProjectToDisk({bool forceSaveAs = false}) =>
      _projectSaveOperation ??= _performProjectSave(
        forceSaveAs: forceSaveAs,
      ).whenComplete(() => _projectSaveOperation = null);

  Future<bool> _performProjectSave({required bool forceSaveAs}) async {
    final sessionRevision = _projectSessionRevision;
    try {
      var p = forceSaveAs ? null : _currentProjectPath;
      p ??= await ExportDestinationService.pickPath(
        dialogTitle: 'Salvar projeto',
        initialDirectory: _preferredOutputDirectory,
        fileName: '${_controller.project.name}.json',
        allowedExtensions: ['json'],
        lockParentWindow: true,
      );
      if (p == null || !mounted || sessionRevision != _projectSessionRevision) {
        return false;
      }
      final path = p.toLowerCase().endsWith('.json') ? p : '$p.json';
      final savedProject = _controller.project;
      final savedSettings = _exportSettings;
      await _projectIOService.saveToFile(
        savedProject,
        path,
        exportSettings: savedSettings,
      );
      await _controller.transcripts.save(savedProject, path: path);
      await _recordVersion(savedProject, savedSettings, 'Salvamento manual');
      if (!mounted || sessionRevision != _projectSessionRevision) return false;
      _markProjectAsSaved(
        path,
        project: savedProject,
        exportSettings: savedSettings,
      );
      if (!_hasUnsavedProjectChanges) {
        await _clearOwnedRecoveryDraft();
      }
      await _recentProjectService.recordProject(
        project: savedProject,
        filePath: path,
      );
      if (mounted && sessionRevision == _projectSessionRevision) {
        _showEditorNotification(
          _hasUnsavedProjectChanges
              ? 'Projeto salvo. Novas alteracoes ainda precisam ser salvas.'
              : 'Projeto salvo!',
          duration: const Duration(seconds: 2),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        _showEditorNotification(e.toString(), tone: TgiNotificationTone.error);
      }
      return false;
    }
  }

  Future<void> _loadProject() async {
    try {
      if (!await _confirmDiscardUnsavedChanges()) {
        return;
      }
      final r = await FilePicker.pickFiles(
        dialogTitle: 'Carregar projeto',
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );
      if (r == null || r.files.isEmpty || !mounted) {
        return;
      }
      final path = r.files.single.path;
      if (path == null || path.isEmpty) {
        return;
      }
      final data = await _projectIOService.readFromFile(path);
      if (!mounted) return;
      final result = _projectIOService.deserializeProject(data);
      final missingMediaItems = result.missingMediaItems;
      _exportSettings =
          result.exportSettings ??
          _exportSettingsForStartPreset(
            editorStartPresetForProject(result.project),
          );
      _projectSessionRevision++;
      _controller.synchronizeCommandExportSettings(_exportSettings);
      _controller.loadProjectFromData(result);
      await _controller.transcripts.open(result.project, path: path);
      _markProjectAsSaved(path);
      await _clearOwnedRecoveryDraft();
      await _recentProjectService.recordProject(
        project: result.project,
        filePath: path,
      );
      if (!mounted) return;
      setState(() {});
      final msg = missingMediaItems.isEmpty
          ? 'Projeto carregado!'
          : 'Carregado (${missingMediaItems.length} arquivos ausentes)';
      if (mounted) {
        _showEditorNotification(msg, duration: const Duration(seconds: 2));
      }
      if (missingMediaItems.isNotEmpty && mounted) {
        await _promptRelinkMissingMedia(missingMediaItems);
      }
    } catch (e) {
      if (mounted) {
        _showEditorNotification(e.toString(), tone: TgiNotificationTone.error);
      }
    }
  }

  bool get _hasUnsavedProjectChanges {
    final snapshot = _lastSavedProjectSnapshot;
    return _recoveredDraftPending ||
        (snapshot != null && !identical(_controller.project, snapshot)) ||
        (_lastSavedExportSettings != null &&
            _exportSettings != _lastSavedExportSettings);
  }

  bool get _canPopEditor => _allowPopWithoutSave || !_hasUnsavedProjectChanges;

  void _markProjectAsSaved(
    String path, {
    TgiProject? project,
    FfmpegExportSettings? exportSettings,
  }) {
    _currentProjectPath = path;
    _lastSavedProjectSnapshot = project ?? _controller.project;
    _lastSavedExportSettings = exportSettings ?? _exportSettings;
    _recoveredDraftPending = false;
    _allowPopWithoutSave = false;
    _scheduleProjectAutosave(force: true);
    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _confirmDiscardUnsavedChanges() async {
    if (!_hasUnsavedProjectChanges) {
      return true;
    }
    final choice = await showDialog<_UnsavedProjectChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Alteracoes nao salvas'),
          content: const Text(
            'Salve o projeto antes de carregar outro ou sair.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_UnsavedProjectChoice.cancel),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_UnsavedProjectChoice.discard),
              child: const Text('Descartar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_UnsavedProjectChoice.save),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    switch (choice) {
      case _UnsavedProjectChoice.save:
        final saved = await _saveProjectToDisk();
        return saved && mounted && !_hasUnsavedProjectChanges;
      case _UnsavedProjectChoice.discard:
        return true;
      case _UnsavedProjectChoice.cancel:
      case null:
        return false;
    }
  }

  Future<void> _handleBlockedPop() async {
    final confirmed = await _confirmDiscardUnsavedChanges();
    if (!confirmed || !mounted) {
      return;
    }
    final leavingProject = _controller.project;
    final leavingSettings = _exportSettings;
    _leavingEditor = true;
    await _clearOwnedRecoveryDraft();
    if (!mounted) return;
    if (!identical(leavingProject, _controller.project) ||
        leavingSettings != _exportSettings) {
      _leavingEditor = false;
      _scheduleProjectAutosave(force: true);
      return;
    }
    _recoveredDraftPending = false;
    _allowPopWithoutSave = true;
    setState(() {});
    Navigator.of(context).pop();
  }

  Future<void> _leaveEditor() async {
    if (!_canPopEditor) {
      await _handleBlockedPop();
      return;
    }
    if (!mounted) {
      return;
    }
    _leavingEditor = true;
    await _clearOwnedRecoveryDraft();
    if (!mounted) return;
    if (_hasUnsavedProjectChanges) {
      _leavingEditor = false;
      _scheduleProjectAutosave(force: true);
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _leavingEditor = false;
    }
  }

  Future<void> _promptRelinkMissingMedia(
    List<Map<String, dynamic>> missingMediaItems,
  ) async {
    if (!mounted || missingMediaItems.isEmpty) {
      return;
    }
    final relinked = await showDialog<List<MediaRelinkResult>>(
      context: context,
      builder: (context) =>
          _RelinkMissingMediaDialog(missingMediaItems: missingMediaItems),
    );
    _restoreEditorShortcutFocus();
    if (relinked != null && relinked.isNotEmpty && mounted) {
      _controller.relinkMedia(relinked);
    }
  }

  Future<void> _importInitialMediaPath(String path) async {
    final mediaItem = await _controller.importMediaFileFromPath(path);
    if (!mounted || mediaItem == null) {
      return;
    }
    if (mediaItem.type == MediaType.video) {
      _addMediaItemToTimeline(mediaItem, Duration.zero);
      _showEditorNotification(
        'Video importado na timeline.',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    _showEditorNotification(
      'Arquivo importado no Media Pool.',
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _importDroppedMediaPoolFiles(List<String> paths) async {
    if (_controller.isImporting || paths.isEmpty) {
      return;
    }
    var importedCount = 0;
    for (final path in paths) {
      if (!FileSystemEntity.isFileSync(path)) {
        continue;
      }
      final mediaItem = await _controller.importMediaFileFromPath(path);
      if (!mounted) {
        return;
      }
      if (mediaItem != null) {
        importedCount++;
      }
    }
    if (!mounted) {
      return;
    }
    _showEditorNotification(
      importedCount == 0
          ? 'Nenhum arquivo valido foi solto no Media Pool.'
          : importedCount == 1
          ? 'Arquivo importado no Media Pool.'
          : '$importedCount arquivos importados no Media Pool.',
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      EditorDebugLog.clear().then(
        (_) => EditorDebugLog.write(
          'screen',
          'editor init log=${EditorDebugLog.path}',
        ),
      ),
    );
    _exportSettings =
        widget.initialExportSettings ??
        _exportSettingsForStartPreset(widget.startPreset);
    _controller = EditorController(
      mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      initialProject:
          widget.initialProject ?? _projectForStartPreset(widget.startPreset),
    );
    _controller.synchronizeCommandExportSettings(_exportSettings);
    _controller.addListener(_handleControllerChanged);
    _automation = EditorAutomation(_controller)
      ..addListener(_handleAutomationChanged);
    if (!_isFlutterTest) {
      unawaited(_automation.load());
    }
    _currentProjectPath = widget.initialProjectPath;
    unawaited(
      _controller.transcripts.open(
        _controller.project,
        path: _currentProjectPath,
      ),
    );
    _lastSavedProjectSnapshot = _controller.project;
    _lastAutosaveObservedProject = _controller.project;
    _lastSavedExportSettings = _exportSettings;
    _lastAutosaveObservedExportSettings = _exportSettings;
    _recoveredDraftPending = widget.isRecoveredDraft;
    _ownsRecoveryDraft = widget.isRecoveredDraft;
    unawaited(_restoreWorkspaceLayout());
    unawaited(_loadAppPreferences());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestEditorShortcutFocus();
      if (!_isFlutterTest) {
        _controller.optimizeHeavyPreviewMedia();
      }
      if (widget.startPreset == EditorStartPreset.quickCreator && mounted) {
        _showEditorNotification(
          'Preset Shorts 9:16 ativo.',
          duration: const Duration(seconds: 2),
        );
      }
      if (widget.startPreset == EditorStartPreset.square && mounted) {
        _showEditorNotification(
          'Preset Quadrado 1:1 ativo.',
          duration: const Duration(seconds: 2),
        );
      }
      if (widget.startPreset == EditorStartPreset.feed45 && mounted) {
        _showEditorNotification(
          'Preset Feed 4:5 ativo.',
          duration: const Duration(seconds: 2),
        );
      }
      if (widget.isRecoveredDraft && mounted) {
        _showEditorNotification(
          'Trabalho recuperado. Salve o projeto para confirmar.',
          duration: const Duration(seconds: 2),
        );
      }
      if (widget.initialMissingMediaItems.isNotEmpty && mounted) {
        unawaited(_promptRelinkMissingMedia(widget.initialMissingMediaItems));
      }
      final initialMediaPath = widget.initialMediaPath;
      if (initialMediaPath != null && initialMediaPath.trim().isNotEmpty) {
        unawaited(_importInitialMediaPath(initialMediaPath));
      }
    });
  }

  Future<void> _loadAppPreferences() async {
    final preferences = await AppPreferencesService.instance.load();
    if (!mounted) {
      return;
    }
    final defaults = defaultEditorShortcutBindings();
    final bindings = <EditorShortcutAction, SingleActivator>{};
    for (final action in EditorShortcutAction.values) {
      bindings[action] =
          preferences.editorShortcuts[action.name]?.toActivator() ??
          defaults[action]!;
    }
    setState(() {
      _preferredOutputDirectory = preferences.outputDirectoryFor(
        AppOutputModule.video,
      );
      _shortcutBindings = bindings;
    });
  }

  @override
  void dispose() {
    _leavingEditor = true;
    _recoveryRevision++;
    _editorFocusNode.dispose();
    _soundEffectsService.dispose();
    _visualMediaService.dispose();
    final previewSubscription = _soundEffectPreviewCompletedSubscription;
    if (previewSubscription != null) {
      unawaited(previewSubscription.cancel());
    }
    final previewPositionSubscription = _soundEffectPreviewPositionSubscription;
    if (previewPositionSubscription != null) {
      unawaited(previewPositionSubscription.cancel());
    }
    final previewDurationSubscription = _soundEffectPreviewDurationSubscription;
    if (previewDurationSubscription != null) {
      unawaited(previewDurationSubscription.cancel());
    }
    final previewPlayer = _soundEffectPreviewPlayer;
    if (previewPlayer != null) {
      unawaited(previewPlayer.dispose());
    }
    _statusAutoDismissTimer?.cancel();
    _errorAutoDismissTimer?.cancel();
    _layoutSaveDebounce?.cancel();
    _projectAutosaveDebounce?.cancel();
    if (_layoutChangedByUser) {
      unawaited(
        _EditorWorkspaceLayoutStore.save(
          _currentWorkspaceLayout(),
          path: widget.workspaceLayoutPath,
        ),
      );
    }
    _automation
      ..removeListener(_handleAutomationChanged)
      ..dispose();
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _handleAutomationChanged() {
    if (mounted && !_leavingEditor) {
      setState(() {});
    }
  }

  Future<void> _openMcpSettings() async {
    _automation.policy.projectDirectory = _currentProjectPath == null
        ? null
        : File(_currentProjectPath!).parent.path;
    await showDialog<void>(
      context: context,
      builder: (_) => McpSettingsDialog(automation: _automation),
    );
  }

  void _handleControllerChanged() {
    _exportSettings = _controller.commandExportSettings;
    final selectedId = _controller.selectedTimelineClip?.id;
    if (selectedId != _inspectedClipId) {
      _inspectedClipId = selectedId;
      if (selectedId != null) {
        _inspectorVisible = true;
        final kind = _controller.selectedTimelineClip?.kind;
        _leftPanelMode = kind == TrackType.video || kind == TrackType.image
            ? _LeftPanelMode.transformCrop
            : _LeftPanelMode.mediaPool;
        _kenBurnsToolActive = false;
      }
    }
    if (EditorDebugLog.enabled) {
      final snapshot = _controllerDebugSnapshot();
      if (snapshot != _lastControllerDebugSnapshot) {
        _lastControllerDebugSnapshot = snapshot;
        EditorDebugLog.write('screen', snapshot);
      }
    }
    _scheduleProjectAutosave();
    _syncAutoDismissBanners();
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleProjectAutosave({bool force = false}) {
    if (!mounted ||
        _leavingEditor ||
        (_isFlutterTest && widget.projectRecoveryService == null)) {
      return;
    }
    final project = _controller.project;
    final exportSettings = _exportSettings;
    if (!force &&
        identical(project, _lastAutosaveObservedProject) &&
        exportSettings == _lastAutosaveObservedExportSettings) {
      return;
    }
    _lastAutosaveObservedProject = project;
    _lastAutosaveObservedExportSettings = exportSettings;
    _projectAutosaveDebounce?.cancel();
    if (!_hasUnsavedProjectChanges) {
      return;
    }
    _projectAutosaveDebounce = Timer(_projectAutosaveDelay, () {
      unawaited(_writeProjectRecoveryDraft(project, exportSettings));
    });
  }

  Future<void> _writeProjectRecoveryDraft(
    TgiProject project,
    FfmpegExportSettings exportSettings,
  ) async {
    if (!mounted ||
        _leavingEditor ||
        !_hasUnsavedProjectChanges ||
        !identical(project, _controller.project) ||
        exportSettings != _exportSettings) {
      return;
    }
    final revision = ++_recoveryRevision;
    // Reserva a propriedade antes do await para que salvar/descartar espere
    // tambem por uma gravacao automatica que ainda nao terminou.
    _ownsRecoveryDraft = true;
    try {
      await _projectRecoveryService.saveDraft(
        project: project,
        originalProjectPath: _currentProjectPath,
        editorStartPreset: widget.startPreset.name,
        exportSettings: exportSettings,
      );
      if (_lastVersionProjectId != project.id ||
          _lastVersionAt == null ||
          DateTime.now().difference(_lastVersionAt!) >=
              const Duration(minutes: 5)) {
        await _recordVersion(project, exportSettings, 'Versão automática');
      }
    } catch (_) {
      if (mounted && revision == _recoveryRevision && !_leavingEditor) {
        _lastAutosaveObservedProject = null;
        _showEditorNotification(
          'Nao foi possivel salvar o rascunho automatico. Salve o projeto manualmente.',
          tone: TgiNotificationTone.error,
        );
      }
      return;
    }
    if (!mounted ||
        revision != _recoveryRevision ||
        _leavingEditor ||
        !identical(project, _controller.project) ||
        exportSettings != _exportSettings) {
      return;
    }
    if (!_autosaveNotificationShown) {
      _autosaveNotificationShown = true;
      _showEditorNotification('Rascunho salvo automaticamente.');
    }
  }

  Future<void> _clearOwnedRecoveryDraft() async {
    _projectAutosaveDebounce?.cancel();
    _projectAutosaveDebounce = null;
    final revision = ++_recoveryRevision;
    if (!_ownsRecoveryDraft) {
      return;
    }
    // Uma nova gravacao solicitada durante a limpeza fica depois dela na fila
    // e volta a ter a propriedade do rascunho, sem ser apagada por este await.
    _ownsRecoveryDraft = false;
    final cleared = await _projectRecoveryService.clearDraft();
    if (!cleared && revision == _recoveryRevision) _ownsRecoveryDraft = true;
  }

  void _syncAutoDismissBanners() {
    _syncAutoDismissBanner(
      message: _controller.statusMessage,
      previousMessage: _statusAutoDismissMessage,
      timer: _statusAutoDismissTimer,
      setTracking: (message, timer) {
        _statusAutoDismissMessage = message;
        _statusAutoDismissTimer = timer;
      },
      currentMessage: () => _controller.statusMessage,
      dismiss: _controller.dismissStatus,
      tone: TgiNotificationTone.standard,
    );
    _syncAutoDismissBanner(
      message: _controller.errorMessage,
      previousMessage: _errorAutoDismissMessage,
      timer: _errorAutoDismissTimer,
      setTracking: (message, timer) {
        _errorAutoDismissMessage = message;
        _errorAutoDismissTimer = timer;
      },
      currentMessage: () => _controller.errorMessage,
      dismiss: _controller.dismissError,
      tone: TgiNotificationTone.error,
    );
  }

  void _syncAutoDismissBanner({
    required String? message,
    required String? previousMessage,
    required Timer? timer,
    required void Function(String? message, Timer? timer) setTracking,
    required String? Function() currentMessage,
    required VoidCallback dismiss,
    required TgiNotificationTone tone,
  }) {
    if (message == null) {
      timer?.cancel();
      if (previousMessage != null || timer != null) {
        setTracking(null, null);
      }
      return;
    }
    if (message == previousMessage && timer?.isActive == true) {
      return;
    }
    timer?.cancel();
    final capturedMessage = message;
    if (mounted && capturedMessage != previousMessage) {
      _showEditorNotification(capturedMessage, tone: tone);
    }
    final nextTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      if (currentMessage() == capturedMessage) {
        dismiss();
      }
    });
    setTracking(capturedMessage, nextTimer);
  }

  Future<void> _restoreWorkspaceLayout() async {
    final layout = await _EditorWorkspaceLayoutStore.load(
      path: widget.workspaceLayoutPath,
    );
    if (!mounted || layout == null) {
      return;
    }
    setState(() {
      _leftPanelFraction = layout.leftPanelFraction;
      _propertiesPanelFraction = layout.propertiesPanelFraction;
      _previewPanelFraction = layout.previewPanelFraction;
      _timelineFocusMode = layout.timelineFocusMode;
      _inspectorVisible = layout.inspectorVisible;
      _libraryVisible = layout.libraryVisible;
    });
    // Persist repaired layout preferences; project v14 is untouched.
    await _EditorWorkspaceLayoutStore.save(
      layout,
      path: widget.workspaceLayoutPath,
    );
  }

  _EditorWorkspaceLayout _currentWorkspaceLayout() {
    return _EditorWorkspaceLayout(
      leftPanelFraction: _leftPanelFraction,
      propertiesPanelFraction: _propertiesPanelFraction,
      previewPanelFraction: _previewPanelFraction,
      timelineFocusMode: _timelineFocusMode,
      inspectorVisible: _inspectorVisible,
      libraryVisible: _libraryVisible,
    ).normalized();
  }

  void _scheduleWorkspaceLayoutSave() {
    _layoutChangedByUser = true;
    final layout = _currentWorkspaceLayout();
    _layoutSaveDebounce?.cancel();
    _layoutSaveDebounce = Timer(_workspaceLayoutSaveDelay, () {
      unawaited(
        _EditorWorkspaceLayoutStore.save(
          layout,
          path: widget.workspaceLayoutPath,
        ),
      );
    });
  }

  String _controllerDebugSnapshot() {
    final preview = _controller.previewMediaItem;
    final active = _controller.activeTimelineClip;
    final previewLabel = preview == null
        ? 'null'
        : '${preview.id}/${preview.name}';
    final activeLabel = active == null
        ? 'null'
        : '${active.id}/${active.mediaItemId}@${_formatDebugDuration(active.timelineStart)}';
    final statusLabel = _controller.statusMessage ?? 'null';
    final errorLabel = _controller.errorMessage ?? 'null';
    return 'state playhead=${_formatDebugDuration(_controller.playheadPosition)} '
        'playing=${_controller.timelinePlaybackActive} '
        'importing=${_controller.isImporting} '
        'preview=$previewLabel '
        'previewSource=${_formatDebugDuration(_controller.previewSourcePosition)} '
        'active=$activeLabel '
        'selected=${_controller.selectedTimelineGroupId} '
        'status=$statusLabel '
        'error=$errorLabel';
  }

  String _formatDebugDuration(Duration duration) {
    return '${duration.inMilliseconds}ms';
  }

  void _requestEditorShortcutFocus() {
    if (mounted && _editorFocusNode.canRequestFocus) {
      _editorFocusNode.requestFocus();
    }
  }

  void _restoreEditorShortcutFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestEditorShortcutFocus();
    });
  }

  KeyEventResult _handleEditorFocusKeyEvent(FocusNode node, KeyEvent event) {
    return _handleEditorKeyEvent(event)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  bool _handleEditorKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    final handled = EditorKeyboardDispatcher(
      context: context,
      controller: _controller,
      shortcutsAllowed: _canUseEditorShortcut(),
      bindings: _shortcutBindings,
      callbackFor: _shortcutCallbackFor,
      save: _saveProject,
      load: _loadProject,
      redo: _handleRedoShortcut,
      delete: _handleDeleteShortcut,
      markRange: _markExportRange,
      framesPerSecond: _exportSettings.framesPerSecond,
    ).handle(event);
    if (handled) return true;
    if (event is! KeyDownEvent ||
        !_canUseEditorShortcut() ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }
    return _timelineKey.currentState?.handleShortcut(
          event.logicalKey,
          shift: keyboard.isShiftPressed,
        ) ??
        false;
  }

  void _addMediaItemToTimeline(
    MediaItem item,
    Duration timelineStart, {
    String? targetTrackId,
    bool forceNewVideoTrack = false,
    bool forceNewAudioTrack = false,
  }) {
    _controller.addMediaItemToTimeline(
      item,
      timelineStart,
      targetTrackId: targetTrackId,
      forceNewVideoTrack: forceNewVideoTrack,
      forceNewAudioTrack: forceNewAudioTrack,
      insert: HardwareKeyboard.instance.isShiftPressed,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _exportTimeline() async {
    if (!_controller.canExport) {
      return;
    }

    final settings = await showDialog<FfmpegExportSettings>(
      context: context,
      builder: (context) => _ExportSettingsDialog(
        initial: _exportSettings,
        playheadPosition: _controller.playheadPosition,
        timelineDuration: _controller.project.timelineDuration,
        hasPaidPlan: _hasPaidPlan,
        onOpenDownloads: _openPlanDownloads,
      ),
    );
    if (settings == null || !mounted) {
      return;
    }
    if (!canExportResolution(settings.resolution, hasPaidPlan: _hasPaidPlan)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '4K requer um plano ativo. No plano gratuito voce pode exportar ate 2K.',
          ),
        ),
      );
      return;
    }
    _setExportSettings(settings);

    final selectedPath = await ExportDestinationService.pickPath(
      dialogTitle: settings.audioOnly ? 'Exportar áudio' : 'Exportar vídeo',
      initialDirectory: _preferredOutputDirectory,
      fileName:
          'export_${settings.resolution.id}.${settings.audioOnly ? 'wav' : 'mp4'}',
      allowedExtensions: settings.audioOnly ? const ['wav'] : const ['mp4'],
      lockParentWindow: true,
    );
    if (selectedPath == null) {
      return;
    }

    final outputPath = settings.audioOnly
        ? (selectedPath.toLowerCase().endsWith('.wav')
              ? selectedPath
              : '$selectedPath.wav')
        : _ensureMp4Extension(selectedPath);
    await _controller.exportTimeline(outputPath, settings: settings);
    if (_controller.exportProgress >= 1 && _controller.errorMessage == null) {
      await _revealExportedFile(outputPath);
    }
  }

  Future<void> _exportShortsTimeline() async {
    if (!_controller.canExport) {
      return;
    }

    const settings = FfmpegExportSettings.quickCreator;
    _setExportSettings(settings);
    final selectedPath = await ExportDestinationService.pickPath(
      dialogTitle: 'Exportar Shorts',
      initialDirectory: _preferredOutputDirectory,
      fileName: 'tgi_shorts_1080x1920_30fps.mp4',
      allowedExtensions: const ['mp4'],
      lockParentWindow: true,
    );
    if (selectedPath == null) {
      return;
    }

    final outputPath = _ensureMp4Extension(selectedPath);
    await _controller.exportTimeline(outputPath, settings: settings);
    if (_controller.exportProgress >= 1 && _controller.errorMessage == null) {
      await _revealExportedFile(outputPath);
    }
  }

  void _setExportSettings(FfmpegExportSettings settings) {
    if (_exportSettings == settings) {
      return;
    }
    setState(() => _exportSettings = settings);
    _controller.synchronizeCommandExportSettings(settings);
    _scheduleProjectAutosave();
  }

  Future<void> _revealExportedFile(String path) async {
    if (!Platform.isWindows) return;
    try {
      await Process.start('explorer.exe', ['/select,', path]);
    } catch (_) {
      // A exportacao continua concluida mesmo se o Explorer nao abrir.
    }
  }

  String _ensureMp4Extension(String path) {
    return path.toLowerCase().endsWith('.mp4') ? path : '$path.mp4';
  }

  String _ensureSubtitleExtension(String path, SubtitleExportFormat format) {
    final extension = '.${format.extension}';
    return path.toLowerCase().endsWith(extension) ? path : '$path$extension';
  }

  Future<void> _addQuickText() async {
    final result = await showDialog<_TextClipDialogResult>(
      context: context,
      builder: (context) => const _TextClipDialog(),
    );
    _restoreEditorShortcutFocus();
    if (result == null || !mounted) {
      return;
    }
    _controller.addTextToTimeline(
      result.text,
      fontFamily: result.fontFamily,
      fontSize: result.fontSize,
      textColor: result.textColor,
      backgroundColor: result.backgroundColor,
      opacity: result.opacity,
    );
  }

  Future<void> _addQuickCaption() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _QuickCaptionDialog(),
    );
    _restoreEditorShortcutFocus();
    final caption = text?.trim();
    if (caption == null || caption.isEmpty || !mounted) {
      return;
    }
    _controller.addTextToTimeline(
      caption.toUpperCase(),
      fontFamily: NewTextStyle.fontFamily,
      fontSize: 72,
      textColor: 0xFFFFFFFF,
      backgroundColor: NewTextStyle.backgroundColor,
      opacity: 1,
      textAnimation: domain.TextClipAnimation.pop,
      registerAsCaption: true,
    );
    setState(() => _leftPanelMode = _LeftPanelMode.captions);
  }

  Future<void> _addAutomaticCaptions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'As legendas automáticas locais usam o Whisper instalado no PC. '
            'No celular, importe um arquivo SRT/VTT ou adicione legendas manualmente.',
          ),
        ),
      );
      return;
    }
    final result = await showDialog<_AutoCaptionsDialogResult>(
      context: context,
      builder: (context) => _AutoCaptionsDialog(
        hasPaidPlan: _hasPaidPlan,
        onOpenDownloads: _openPlanDownloads,
        initialSettings: _lastAutoCaptionsSettings,
        defaultLanguage: _controller.transcripts.language,
        defaultVocabulary: _controller.transcripts.vocabulary,
        defaultVad: _controller.transcripts.vad,
      ),
    );
    _restoreEditorShortcutFocus();
    if (result == null || !mounted) {
      return;
    }
    _lastAutoCaptionsSettings = result;
    _controller.transcripts.language = result.languageCode ?? 'pt';
    _controller.transcripts.vocabulary = result.vocabulary;
    _controller.transcripts.vad = result.vad;
    await _controller.transcripts.save(_controller.project);
    if (!mounted) return;
    if (result.modelName == 'small' && !_hasPaidPlan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O modelo de legendas de alta qualidade requer um plano ativo.',
          ),
        ),
      );
      return;
    }
    await _controller.generateAutomaticCaptions(
      languageCode: result.languageCode,
      modelName: result.modelName,
      maxCharsPerCue: result.maxCharsPerCue,
      captionFontFamily: result.fontFamily,
      captionFontSize: result.fontSize,
      captionTextColor: result.textColor,
      captionBackgroundColor: result.backgroundColor,
      captionOpacity: result.opacity,
      captionAnimation: result.animation,
    );
  }

  void _showCaptionsPanel() {
    if (_leftPanelMode == _LeftPanelMode.captions) return;
    unawaited(_stopSoundEffectPreview());
    setState(() => _leftPanelMode = _LeftPanelMode.captions);
    _controller.setCutMode(false);
  }

  void _showChromaKeyPanel() {
    if (_leftPanelMode == _LeftPanelMode.chromaKey) return;
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _leftPanelMode = _LeftPanelMode.chromaKey;
      _chromaColorPickerActive = false;
    });
    _controller.setCutMode(false);
  }

  void _showMaskTrackingPanel() {
    if (_leftPanelMode == _LeftPanelMode.maskTracking) return;
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _leftPanelMode = _LeftPanelMode.maskTracking;
      _chromaColorPickerActive = false;
      _whiteBalancePickerActive = false;
    });
    _controller.setCutMode(false);
  }

  Future<void> _attachImageToMaskTracking() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Escolher imagem para seguir o objeto',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      allowMultiple: false,
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty || !mounted) return;
    await _controller.attachImageToSelectedMask(path);
  }

  void _setChromaColorPickerActive(bool active) {
    final clip = _controller.selectedTimelineVideoClip;
    if (active && clip == null) {
      _showEditorNotification(
        'Selecione um clipe de vídeo antes de usar o conta-gotas.',
        tone: TgiNotificationTone.error,
      );
      return;
    }
    if (active && clip != null) {
      _controller.setTimelinePlaybackActive(false);
      final playhead = _controller.playheadPosition;
      if (playhead < clip.timelineStart || playhead >= clip.timelineEnd) {
        _controller.setPlayheadPosition(clip.timelineStart);
      }
    }
    setState(() => _chromaColorPickerActive = active);
  }

  void _handleChromaColorPicked(int color) {
    _controller.updateSelectedVideoChromaKeyColor(color);
    if (!mounted) return;
    setState(() => _chromaColorPickerActive = false);
    final hex =
        '#${(color & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    _showEditorNotification('Cor $hex selecionada para o Chroma Key.');
  }

  void _handleChromaColorPickError(String message) {
    if (!mounted) return;
    _showEditorNotification(message, tone: TgiNotificationTone.error);
  }

  void _showTransformCropPanel() {
    if (_leftPanelMode == _LeftPanelMode.transformCrop) return;
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _leftPanelMode = _LeftPanelMode.transformCrop;
      _kenBurnsToolActive = false;
    });
    _controller.setCutMode(false);
  }

  void _showAudioToolsPanel() {
    if (_leftPanelMode == _LeftPanelMode.audioTools) return;
    unawaited(_stopSoundEffectPreview());
    setState(() => _leftPanelMode = _LeftPanelMode.audioTools);
    _controller.setCutMode(false);
  }

  void _showSmartCutPanel() {
    if (_leftPanelMode == _LeftPanelMode.smartCut) return;
    unawaited(_stopSoundEffectPreview());
    setState(() => _leftPanelMode = _LeftPanelMode.smartCut);
    _controller.setCutMode(false);
  }

  void _setSmartCutIntensity(SmartCutIntensity intensity) {
    if (_smartCutIntensity == intensity) return;
    if (_controller.smartCutAnalysis != null) {
      _controller.clearSmartCutAnalysis();
    }
    setState(() => _smartCutIntensity = intensity);
  }

  Future<void> _analyzeSmartCut() async {
    _controller.setTimelinePlaybackActive(false);
    await _controller.analyzeSmartCut(intensity: _smartCutIntensity);
  }

  void _previewSmartCutSegment(SmartCutSegment segment) {
    const lead = Duration(milliseconds: 350);
    final previewStart = segment.start > lead
        ? segment.start - lead
        : Duration.zero;
    _controller.setPlayheadPosition(previewStart);
    _controller.setTimelinePlaybackActive(true);
  }

  void _applySmartCut() {
    _controller.setTimelinePlaybackActive(false);
    final removed = _controller.applySmartCutAnalysis();
    if (removed > 0) {
      _showEditorNotification(
        '$removed ${removed == 1 ? 'pausa removida' : 'pausas removidas'}. '
        'Ctrl+Z desfaz tudo.',
      );
    }
  }

  void _showProfessionalColorPanel() {
    if (_leftPanelMode == _LeftPanelMode.professionalColor) return;
    final selectedClip = _controller.selectedTimelineVideoClip;
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _leftPanelMode = _LeftPanelMode.professionalColor;
      _whiteBalancePickerActive = false;
      _colorCompareOriginal = false;
      _colorAnalysisLoading = true;
      _colorAnalysisRequest++;
    });
    _controller.setCutMode(false);
    _controller.setTimelinePlaybackActive(false);
    if (selectedClip != null &&
        (_controller.playheadPosition < selectedClip.timelineStart ||
            _controller.playheadPosition >= selectedClip.timelineEnd)) {
      _controller.setPlayheadPosition(selectedClip.timelineStart);
    }
  }

  void _beginProfessionalColorInteraction() {
    if (_colorCompareOriginal && mounted) {
      setState(() => _colorCompareOriginal = false);
    }
    _controller.beginInteractiveEdit();
  }

  void _endProfessionalColorInteraction() {
    _controller.commitInteractiveEdit();
  }

  void _showAdvancedSpeedPanel() {
    if (_leftPanelMode == _LeftPanelMode.advancedSpeed) return;
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _leftPanelMode = _LeftPanelMode.advancedSpeed;
      _whiteBalancePickerActive = false;
      _colorCompareOriginal = false;
    });
    _controller.setCutMode(false);
  }

  void _requestColorAnalysis() {
    setState(() {
      _colorAnalysisLoading = true;
      _colorAnalysisRequest++;
    });
  }

  void _handleColorAnalysis(VideoColorAnalysis analysis) {
    if (!mounted) return;
    setState(() {
      _colorAnalysis = analysis;
      _colorAnalysisLoading = false;
    });
  }

  void _handleColorAnalysisError(String message) {
    if (!mounted) return;
    setState(() => _colorAnalysisLoading = false);
    _showEditorNotification(message, tone: TgiNotificationTone.error);
  }

  void _setWhiteBalancePickerActive(bool active) {
    final clip = _controller.selectedTimelineVideoClip;
    if (active && clip == null) {
      _showEditorNotification(
        'Selecione um clipe de vídeo para usar o balanço de branco.',
        tone: TgiNotificationTone.error,
      );
      return;
    }
    if (active && clip != null) {
      _controller.setTimelinePlaybackActive(false);
      final playhead = _controller.playheadPosition;
      if (playhead < clip.timelineStart || playhead >= clip.timelineEnd) {
        _controller.setPlayheadPosition(clip.timelineStart);
      }
    }
    setState(() => _whiteBalancePickerActive = active);
  }

  void _handleWhiteBalanceColorPicked(int color) {
    final red = (color >> 16) & 0xFF;
    final green = (color >> 8) & 0xFF;
    final blue = color & 0xFF;
    final temperature = ((blue - red) / 255 * 1.6).clamp(-1.0, 1.0).toDouble();
    final tint = ((green - (red + blue) / 2) / 255 * 1.8)
        .clamp(-1.0, 1.0)
        .toDouble();
    _controller.updateSelectedVideoProfessionalColor(
      temperature: temperature,
      tint: tint,
    );
    if (!mounted) return;
    setState(() => _whiteBalancePickerActive = false);
    _showEditorNotification('Balanço de branco calculado pelo ponto neutro.');
  }

  void _selectCaptionClip(domain.Clip clip) {
    _controller.selectTimelineClipGroup(clip.timelineGroupId);
    _controller.setPlayheadPosition(clip.timelineStart);
  }

  Future<void> _addTextAtTimelinePosition(Duration position) async {
    _controller.setPlayheadPosition(position);
    await _addQuickText();
  }

  Future<void> _addCaptionAtTimelinePosition(Duration position) async {
    _controller.setPlayheadPosition(position);
    await _addQuickCaption();
  }

  Future<void> _openPlanDownloads() {
    if (kStandalone) return Future<void>.value();
    return showPremiumDownloadsDialog(
      context,
      hasPaidPlan: _hasPaidPlan,
      onAccessGranted: () {
        if (mounted) setState(() => _rewardedAccessGranted = true);
      },
    );
  }

  bool get _hasPaidPlan =>
      kStandalone || widget.hasPaidPlan || _rewardedAccessGranted;

  Future<void> _exportGeneratedCaptions(SubtitleExportFormat format) async {
    if (!_controller.canExportGeneratedCaptions) {
      return;
    }
    final selectedPath = await ExportDestinationService.pickPath(
      dialogTitle: 'Exportar legendas ${format.extension.toUpperCase()}',
      initialDirectory: _preferredOutputDirectory,
      fileName: 'tgi_legendas.${format.extension}',
      allowedExtensions: [format.extension],
      lockParentWindow: true,
    );
    if (selectedPath == null) {
      return;
    }
    await _controller.exportGeneratedCaptions(
      _ensureSubtitleExtension(selectedPath, format),
      format,
    );
  }

  void _showMediaPool() {
    if (_leftPanelMode == _LeftPanelMode.mediaPool) {
      return;
    }
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _leftPanelMode = _LeftPanelMode.mediaPool;
    });
    _controller.setCutMode(false);
  }

  void _showSoundEffectsLibrary() {
    if (_leftPanelMode == _LeftPanelMode.soundEffects) {
      return;
    }
    setState(() {
      _leftPanelMode = _LeftPanelMode.soundEffects;
    });
    _controller.setCutMode(false);
  }

  void _showVisualMediaLibrary() {
    if (_leftPanelMode == _LeftPanelMode.visualMedia) {
      return;
    }
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _leftPanelMode = _LeftPanelMode.visualMedia;
    });
    _controller.setCutMode(false);
  }

  void _showTransitionLibrary() {
    if (_leftPanelMode == _LeftPanelMode.transitions) {
      return;
    }
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _leftPanelMode = _LeftPanelMode.transitions;
    });
    _controller.setCutMode(false);
  }

  void _insertTransitionPresetFromLibrary(TimelineTransitionAsset asset) {
    if (!asset.isPreset || asset.preset == null) {
      return;
    }
    _controller.applyTransitionPresetToNearestEdit(
      preset: asset.preset!,
      name: asset.name,
      duration: asset.duration,
      direction: asset.direction,
      color: asset.color,
      intensity: asset.intensity,
    );
  }

  void _insertDroppedTransitionClipFromTimeline(
    TimelineTransitionAsset asset,
    Duration timelinePosition,
  ) {
    if (asset.isPreset && asset.preset != null) {
      _controller.applyTransitionPresetToNearestEdit(
        preset: asset.preset!,
        name: asset.name,
        duration: asset.duration,
        timelinePosition: timelinePosition,
        direction: asset.direction,
        color: asset.color,
        intensity: asset.intensity,
      );
    }
  }

  void _editTimelineTransition(TimelineTransition transition) {
    unawaited(_showTimelineTransitionSettings(transition));
  }

  Future<void> _showTimelineTransitionSettings(
    TimelineTransition transition,
  ) async {
    final result = await showDialog<_TimelineTransitionSettingsResult>(
      context: context,
      builder: (context) =>
          _TimelineTransitionSettingsDialog(transition: transition),
    );
    _restoreEditorShortcutFocus();
    if (result == null || !mounted) {
      return;
    }
    _controller.updateTimelineTransitionProperties(
      transition.id,
      duration: result.duration,
      blendMode: result.blendMode,
      direction: result.direction,
      color: result.color,
      intensity: result.intensity,
    );
  }

  Future<void> _addVisualMediaFromLibrary(PublicVisualMediaItem item) async {
    if (_addingVisualMediaId != null) {
      return;
    }

    unawaited(_stopSoundEffectPreview());
    setState(() {
      _addingVisualMediaId = item.id;
    });
    try {
      final path = await _visualMediaService.downloadToCache(item);
      final mediaItem = await _controller.importMediaFileFromPath(
        path,
        displayName: item.fileName,
      );
      if (mediaItem != null && mounted) {
        setState(() {
          _leftPanelMode = _LeftPanelMode.mediaPool;
        });
        _restoreEditorShortcutFocus();
      }
    } catch (error) {
      if (mounted) {
        _showEditorNotification(
          error.toString(),
          tone: TgiNotificationTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _addingVisualMediaId = null;
        });
      }
    }
  }

  Future<void> _addSoundEffectFromLibrary(PublicSoundEffect effect) async {
    if (_addingSoundEffectId != null) {
      return;
    }

    unawaited(_stopSoundEffectPreview());
    setState(() {
      _addingSoundEffectId = effect.id;
    });
    try {
      final path = await _soundEffectsService.downloadToCache(effect);
      final mediaItem = await _controller
          .importAudioFileFromPathToNewTimelineTrack(
            path,
            displayName: '${effect.name}.wav',
          );
      if (mediaItem != null && mounted) {
        setState(() {
          _leftPanelMode = _LeftPanelMode.mediaPool;
        });
      }
    } catch (error) {
      if (mounted) {
        _showEditorNotification(
          error.toString(),
          tone: TgiNotificationTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _addingSoundEffectId = null;
        });
      }
    }
  }

  Future<void> _previewSoundEffectFromLibrary(PublicSoundEffect effect) async {
    if (_loadingPreviewSoundEffectId != null) {
      return;
    }
    if (_previewingSoundEffectId == effect.id) {
      await _stopSoundEffectPreview();
      return;
    }

    final revision = ++_soundEffectPreviewRevision;
    setState(() {
      _loadingPreviewSoundEffectId = effect.id;
      _previewingSoundEffectId = null;
    });

    try {
      final path = await _soundEffectsService.downloadToCache(effect);
      if (!mounted || revision != _soundEffectPreviewRevision) {
        return;
      }
      final player = _ensureSoundEffectPreviewPlayer();
      await player.open(Media(Uri.file(path).toString()), play: true);
      if (!mounted || revision != _soundEffectPreviewRevision) {
        return;
      }
      setState(() {
        _previewingSoundEffectId = effect.id;
        _soundEffectPreviewPosition = Duration.zero;
        _soundEffectPreviewDuration = effect.duration;
      });
    } catch (error) {
      if (mounted) {
        _showEditorNotification(
          error.toString(),
          tone: TgiNotificationTone.error,
        );
      }
    } finally {
      if (mounted && revision == _soundEffectPreviewRevision) {
        setState(() {
          _loadingPreviewSoundEffectId = null;
        });
      }
    }
  }

  Player _ensureSoundEffectPreviewPlayer() {
    final existing = _soundEffectPreviewPlayer;
    if (existing != null) {
      return existing;
    }

    final player = Player();
    _soundEffectPreviewPlayer = player;
    _soundEffectPreviewCompletedSubscription = player.stream.completed.listen((
      completed,
    ) {
      if (!completed || !mounted) {
        return;
      }
      setState(() {
        _previewingSoundEffectId = null;
        _soundEffectPreviewPosition = Duration.zero;
        _soundEffectPreviewDuration = Duration.zero;
      });
    });
    _soundEffectPreviewPositionSubscription = player.stream.position.listen((
      position,
    ) {
      if (!mounted || _previewingSoundEffectId == null) {
        return;
      }
      setState(() {
        _soundEffectPreviewPosition = position;
      });
    });
    _soundEffectPreviewDurationSubscription = player.stream.duration.listen((
      duration,
    ) {
      if (!mounted || _previewingSoundEffectId == null) {
        return;
      }
      setState(() {
        _soundEffectPreviewDuration = duration;
      });
    });
    return player;
  }

  Future<void> _stopSoundEffectPreview() async {
    _soundEffectPreviewRevision++;
    if (mounted) {
      setState(() {
        _previewingSoundEffectId = null;
        _loadingPreviewSoundEffectId = null;
        _soundEffectPreviewPosition = Duration.zero;
        _soundEffectPreviewDuration = Duration.zero;
      });
    }

    final player = _soundEffectPreviewPlayer;
    if (player == null) {
      return;
    }
    try {
      await player.pause();
      await player.seek(Duration.zero);
    } catch (_) {
      // Preview commands can race with media_kit session disposal.
    }
  }

  Future<void> _editTextClip(domain.Clip clip) async {
    final result = await showDialog<_TextClipDialogResult>(
      context: context,
      builder: (context) => _TextClipDialog(
        initialText: clip.textContent,
        initialFontFamily: clip.fontFamily,
        initialFontSize: clip.fontSize,
        initialTextColor: clip.textColor,
        initialBackgroundColor: clip.backgroundColor,
        initialOpacity: clip.opacity,
        title: 'Editar texto',
        actionLabel: 'Salvar',
      ),
    );
    _restoreEditorShortcutFocus();
    if (result == null || !mounted) {
      return;
    }
    _controller.updateTextClipProperties(
      clip.id,
      text: result.text,
      fontFamily: result.fontFamily,
      fontSize: result.fontSize,
      textColor: result.textColor,
      backgroundColor: result.backgroundColor,
      opacity: result.opacity,
    );
  }

  void _editTextClipById(String clipId) {
    final clip = _clipById(clipId);
    if (clip == null) {
      return;
    }
    unawaited(_editTextClip(clip));
  }

  domain.Clip? _clipById(String clipId) {
    for (final track in _controller.project.tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) {
          return clip;
        }
      }
    }
    return null;
  }

  List<TransitionPreviewEntry> _activeTransitionPreviewEntries() {
    final playhead = _controller.playheadPosition;
    final dissolves = CrossDissolve.forProject(_controller.project);
    Duration sourceAt(domain.Clip clip) {
      final elapsed =
          (playhead - clip.timelineStart).inMicroseconds * clip.playbackSpeed;
      final offset = elapsed.round().clamp(
        0,
        (clip.effectiveSourceDuration.inMicroseconds - 50000).clamp(0, 1 << 60),
      );
      return clip.sourceStart +
          Duration(
            microseconds: clip.reverseVideo
                ? clip.effectiveSourceDuration.inMicroseconds - offset - 1
                : offset,
          );
    }

    return [
      for (final dissolve in dissolves)
        if (playhead >= dissolve.start && playhead < dissolve.end)
          for (final side in [dissolve.left, dissolve.right])
            if (_controller.project.mediaItemById(side.mediaItemId)
                case final media?)
              TransitionPreviewEntry(
                id: '${dissolve.transition.id}:${side.id}',
                name: dissolve.transition.name,
                filePath: media.previewProxyPath ?? media.filePath,
                sourcePosition: sourceAt(side),
                timelinePosition: playhead,
                duration: dissolve.duration,
                blendMode: TimelineTransitionBlendMode.normal,
                placement: dissolve.transition.placement,
                opacityOverride: side.id == dissolve.left.id
                    ? 1
                    : dissolve.progressAt(playhead),
              ),
      for (final transition in _controller.project.transitions)
        if (!dissolves.any((d) => d.transition.id == transition.id))
          if (transition.timelineStart <= playhead &&
              playhead < transition.timelineEnd)
            TransitionPreviewEntry(
              id: transition.id,
              name: transition.name,
              filePath: transition.filePath,
              sourcePosition: playhead - transition.timelineStart,
              timelinePosition: playhead,
              duration: transition.duration,
              blendMode: transition.blendMode,
              placement: transition.placement,
              preset: transition.preset,
              direction: transition.direction,
              color: transition.color,
              intensity: transition.intensity,
            ),
    ];
  }

  EditorPreviewValues get _previewValues => EditorPreviewValues(
    position: _controller.playheadPosition,
    fadeOpacity: _controller.previewOpacityForClip,
  );
  VideoPreviewVisualAdjustments _visualAdjustmentsForClip(domain.Clip? clip) =>
      _previewValues.visualAdjustmentsForClip(clip);
  double _previewClipTime(domain.Clip clip) =>
      _previewValues.previewClipTime(clip);
  double _previewOpacityForClip(domain.Clip clip) =>
      _previewValues.previewOpacityForClip(clip);
  double _previewOverlayX(domain.Clip clip) =>
      _previewValues.previewOverlayX(clip);
  double _previewOverlayY(domain.Clip clip) =>
      _previewValues.previewOverlayY(clip);
  double _previewOverlayScale(domain.Clip clip) =>
      _previewValues.previewOverlayScale(clip);

  void _handleUndoShortcut() {
    if (!_canUseEditorShortcut() || !_controller.canUndo) {
      return;
    }
    _controller.undo();
  }

  void _handleRedoShortcut() {
    if (!_canUseEditorShortcut() || !_controller.canRedo) {
      return;
    }
    _controller.redo();
  }

  void _handleDeleteShortcut() {
    if (!_canUseEditorShortcut()) {
      return;
    }
    _controller.deleteSelectedTimelineClip();
  }

  void _handleCopyShortcut() {
    if (!_canUseEditorShortcut() || !_controller.canCopyClips) {
      return;
    }
    _controller.copySelectedTimelineClips();
  }

  void _handlePasteShortcut() {
    if (!_canUseEditorShortcut() || !_controller.canPasteClips) {
      return;
    }
    _controller.pasteCopiedTimelineClips();
  }

  void _handleDuplicateShortcut() {
    if (!_canUseEditorShortcut() || !_controller.canDuplicateClips) {
      return;
    }
    _controller.duplicateSelectedTimelineClips();
  }

  void _handleSplitShortcut() {
    if (!_canUseEditorShortcut()) {
      return;
    }
    _controller.splitSelectedOrActiveClipAtPlayhead();
  }

  void _handlePlaybackShortcut() {
    if (!_canUseEditorShortcut()) {
      return;
    }
    _controller.toggleTimelinePlayback();
  }

  Future<void> _openKeyboardSettings() async {
    final result = await showDialog<Map<EditorShortcutAction, SingleActivator>>(
      context: context,
      builder: (context) =>
          KeyboardShortcutsDialog(initialBindings: _shortcutBindings),
    );
    _restoreEditorShortcutFocus();
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _shortcutBindings = result;
    });
    final preferences = await AppPreferencesService.instance.load();
    await AppPreferencesService.instance.save(
      preferences.copyWith(
        editorShortcuts: {
          for (final entry in result.entries)
            entry.key.name: AppShortcutBinding.fromActivator(entry.value),
        },
      ),
    );
  }

  Future<void> _openWatermarkSettings() async {
    final result = await showDialog<ProjectWatermark>(
      context: context,
      builder: (context) =>
          _WatermarkSettingsDialog(initial: _controller.project.watermark),
    );
    if (result == null || !mounted) {
      return;
    }
    _controller.updateWatermark(
      enabled: result.enabled,
      imagePath: result.imagePath,
      position: result.position,
      x: result.x,
      y: result.y,
      scale: result.scale,
      opacity: result.opacity,
    );
  }

  VoidCallback _shortcutCallbackFor(EditorShortcutAction action) {
    return switch (action) {
      EditorShortcutAction.undo => _handleUndoShortcut,
      EditorShortcutAction.redo => _handleRedoShortcut,
      EditorShortcutAction.split => _handleSplitShortcut,
      EditorShortcutAction.copy => _handleCopyShortcut,
      EditorShortcutAction.paste => _handlePasteShortcut,
      EditorShortcutAction.duplicate => _handleDuplicateShortcut,
      EditorShortcutAction.playPause => _handlePlaybackShortcut,
      EditorShortcutAction.delete => _handleDeleteShortcut,
    };
  }

  bool _canUseEditorShortcut() {
    if (_controller.isImporting || _controller.isExporting) {
      return false;
    }

    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null || !focusedContext.mounted) {
      return true;
    }
    if (focusedContext.widget is EditableText) {
      return false;
    }

    var hasEditableTextAncestor = false;
    focusedContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        hasEditableTextAncestor = true;
        return false;
      }
      return true;
    });
    return !hasEditableTextAncestor;
  }

  void _updateSelectedClipStart(Duration timelineStart) {
    final clip = _controller.selectedTimelineClip;
    if (clip == null) {
      return;
    }
    _controller.moveTimelineClipGroup(clip.timelineGroupId, timelineStart);
  }

  void _updateSelectedClipDuration(Duration duration) {
    final clip = _controller.selectedTimelineClip;
    if (clip == null ||
        (clip.trackType != TrackType.image &&
            clip.trackType != TrackType.text)) {
      return;
    }
    _controller.resizeImageClip(clip.id, clip.timelineStart, duration);
  }

  void _updateSelectedClipVolume(double volume) {
    final audioClip = _controller.selectedTimelineAudioClip;
    if (audioClip == null) {
      return;
    }
    _controller.updateClipVolume(audioClip.id, volume);
  }

  void _updateSelectedAudioNoiseReduction(double noiseReductionDb) {
    final audioClip = _controller.selectedTimelineAudioClip;
    if (audioClip == null) {
      return;
    }
    _controller.updateClipAudioNoiseReduction(audioClip.id, noiseReductionDb);
  }

  void _updateSelectedClipFadeIn(Duration fadeIn) {
    final clip = _controller.selectedTimelineClip;
    if (clip == null) {
      return;
    }
    _controller.updateSelectedClipTransitionsForType(
      clip.trackType,
      fadeIn: fadeIn,
    );
  }

  void _updateSelectedClipFadeOut(Duration fadeOut) {
    final clip = _controller.selectedTimelineClip;
    if (clip == null) {
      return;
    }
    _controller.updateSelectedClipTransitionsForType(
      clip.trackType,
      fadeOut: fadeOut,
    );
  }

  void _updateSelectedAudioClipFadeIn(Duration fadeIn) {
    _controller.updateSelectedClipTransitionsForType(
      TrackType.audio,
      fadeIn: fadeIn,
    );
  }

  void _updateSelectedAudioClipFadeOut(Duration fadeOut) {
    _controller.updateSelectedClipTransitionsForType(
      TrackType.audio,
      fadeOut: fadeOut,
    );
  }

  void _enableClipFade(domain.Clip clip) {
    _controller.enableFadeForSelectedClips(clip.trackType);
  }

  void _updateTextClipPanelProperties(
    domain.Clip clip, {
    String? text,
    String? fontFamily,
    double? fontSize,
    int? textColor,
    int? backgroundColor,
    double? opacity,
    domain.TextClipAnimation? textAnimation,
  }) {
    if (clip.trackType != TrackType.text) {
      return;
    }
    if (text == null) {
      _controller.updateSelectedTextClipProperties(
        fontFamily: fontFamily,
        fontSize: fontSize,
        textColor: textColor,
        backgroundColor: backgroundColor,
        opacity: opacity,
        textAnimation: textAnimation,
      );
      return;
    }
    _controller.updateTextClipProperties(
      clip.id,
      text: text,
      fontFamily: fontFamily,
      fontSize: fontSize,
      textColor: textColor,
      backgroundColor: backgroundColor,
      opacity: opacity,
      textAnimation: textAnimation,
    );
  }

  void _applyTextStylePreset(domain.Clip clip, _TextStylePreset preset) {
    if (clip.trackType != TrackType.text) {
      return;
    }
    _controller.updateSelectedTextClipProperties(
      fontFamily: preset.fontFamily,
      fontSize: preset.fontSize,
      textColor: preset.textColor,
      backgroundColor: preset.backgroundColor,
      opacity: preset.opacity,
      textAnimation: preset.animation,
    );
  }

  void _resizeLeftWorkspacePanel(DragUpdateDetails details, double width) {
    if (width <= 0) {
      return;
    }
    setState(() {
      final maxLeft = math.min(
        _maxLeftPanelFraction,
        1 - _minCenterPanelFraction - _propertiesPanelFraction,
      );
      _leftPanelFraction =
          ((_sidePanelWidth(_leftPanelFraction, width, 200, 360) +
                      details.delta.dx) /
                  width)
              .clamp(_minLeftPanelFraction, maxLeft)
              .toDouble();
    });
    _scheduleWorkspaceLayoutSave();
  }

  void _resizePropertiesWorkspacePanel(
    DragUpdateDetails details,
    double width,
  ) {
    if (width <= 0) {
      return;
    }
    setState(() {
      final maxProperties = math.min(
        _maxPropertiesPanelFraction,
        1 - _minCenterPanelFraction - _leftPanelFraction,
      );
      _propertiesPanelFraction =
          ((_sidePanelWidth(_propertiesPanelFraction, width, 220, 340) -
                      details.delta.dx) /
                  width)
              .clamp(_minPropertiesPanelFraction, maxProperties)
              .toDouble();
    });
    _scheduleWorkspaceLayoutSave();
  }

  void _resizePreviewWorkspacePanel(DragUpdateDetails details, double height) {
    if (height <= 0) {
      return;
    }
    setState(() {
      _previewPanelFraction =
          (_previewPanelFraction + details.delta.dy / height)
              .clamp(0.28, 0.68)
              .toDouble();
    });
    _scheduleWorkspaceLayoutSave();
  }

  void _resetWorkspaceLayout() {
    setState(() {
      _leftPanelFraction = _defaultLeftPanelFraction;
      _propertiesPanelFraction = _defaultPropertiesPanelFraction;
      _previewPanelFraction = _defaultPreviewPanelFraction;
      _timelineFocusMode = false;
      _inspectorVisible = true;
      _libraryVisible = true;
    });
    _scheduleWorkspaceLayoutSave();
  }

  bool _clipSupportsKenBurnsTool(domain.Clip? clip) {
    return clip != null &&
        (clip.trackType == TrackType.image ||
            clip.trackType == TrackType.video);
  }

  domain.Clip? get _kenBurnsToolClip {
    final selected = _controller.selectedTimelineClip;
    if (_clipSupportsKenBurnsTool(selected)) {
      return selected;
    }
    final active = _controller.activeTimelineClip;
    return _clipSupportsKenBurnsTool(active) ? active : null;
  }

  void _toggleKenBurnsTool() {
    final selectedClip = _controller.selectedTimelineClip;
    final nextActive =
        !_kenBurnsToolActive || _leftPanelMode != _LeftPanelMode.animations;
    unawaited(_stopSoundEffectPreview());
    setState(() {
      _kenBurnsToolActive = nextActive;
      _kenBurnsPickTarget = _KenBurnsPickTarget.start;
      if (nextActive) {
        _leftPanelMode = _LeftPanelMode.animations;
        _chromaColorPickerActive = false;
        _whiteBalancePickerActive = false;
      } else {
        _leftPanelMode = _LeftPanelMode.mediaPool;
      }
    });
    _controller.setCutMode(false);
    _controller.setTimelinePlaybackActive(false);
    if (selectedClip != null &&
        (_controller.playheadPosition < selectedClip.timelineStart ||
            _controller.playheadPosition >= selectedClip.timelineEnd)) {
      _controller.setPlayheadPosition(selectedClip.timelineStart);
    }
    if (nextActive && _kenBurnsToolClip == null) {
      _showEditorNotification(
        'Selecione um clipe de video ou imagem para animar.',
        tone: TgiNotificationTone.standard,
      );
    }
  }

  void _handleKenBurnsPreviewPointSelected(double x, double y) {
    final clip = _kenBurnsToolClip;
    if (clip == null) {
      _showEditorNotification(
        'Selecione um clipe de video ou imagem para animar.',
        tone: TgiNotificationTone.error,
      );
      return;
    }
    final safeX = x.clamp(0.0, 1.0).toDouble();
    final safeY = y.clamp(0.0, 1.0).toDouble();
    if (_kenBurnsPickTarget == _KenBurnsPickTarget.start) {
      _controller.setSelectedClipKenBurnsStartPoint(safeX, safeY);
      setState(() => _kenBurnsPickTarget = _KenBurnsPickTarget.end);
      _showEditorNotification('Inicio marcado. Clique no destino final.');
      return;
    }
    _controller.setSelectedClipKenBurnsEndPoint(safeX, safeY);
    setState(() => _kenBurnsPickTarget = _KenBurnsPickTarget.start);
    _showEditorNotification('Fim marcado. Ajuste zoom e tempo se precisar.');
  }

  void _selectAnimationEditTarget(bool editingStart) {
    setState(() {
      _kenBurnsToolActive = true;
      _kenBurnsPickTarget = editingStart
          ? _KenBurnsPickTarget.start
          : _KenBurnsPickTarget.end;
    });
  }

  void _applyAnimationPreset(AnimationMotionPreset preset) {
    if (_kenBurnsToolClip == null) {
      _showEditorNotification(
        'Selecione um video ou uma imagem na timeline.',
        tone: TgiNotificationTone.error,
      );
      return;
    }
    final intensity = switch (_animationIntensity) {
      AnimationIntensity.subtle => 0.65,
      AnimationIntensity.normal => 1.0,
      AnimationIntensity.strong => 1.4,
    };
    final zoom = 1 + 0.4 * intensity;
    final panZoom = 1.15 + 0.15 * intensity;
    final travel = (0.22 * intensity).clamp(0.12, 0.38);
    final low = 0.5 - travel;
    final high = 0.5 + travel;
    final values = switch (preset) {
      AnimationMotionPreset.zoomIn => [0.5, 0.5, 1.0, 0.5, 0.5, zoom],
      AnimationMotionPreset.zoomOut => [0.5, 0.5, zoom, 0.5, 0.5, 1.0],
      AnimationMotionPreset.leftToRight => [
        low,
        0.5,
        panZoom,
        high,
        0.5,
        panZoom,
      ],
      AnimationMotionPreset.rightToLeft => [
        high,
        0.5,
        panZoom,
        low,
        0.5,
        panZoom,
      ],
      AnimationMotionPreset.topToBottom => [
        0.5,
        low,
        panZoom,
        0.5,
        high,
        panZoom,
      ],
      AnimationMotionPreset.bottomToTop => [
        0.5,
        high,
        panZoom,
        0.5,
        low,
        panZoom,
      ],
    };
    _controller.applySelectedClipAnimationPreset(
      startX: values[0],
      startY: values[1],
      startScale: values[2],
      endX: values[3],
      endY: values[4],
      endScale: values[5],
    );
    final timing = switch (_animationSpeed) {
      AnimationSpeed.slow => const (0.0, 1.0),
      AnimationSpeed.normal => const (0.1, 0.9),
      AnimationSpeed.fast => const (0.25, 0.75),
    };
    _controller.updateSelectedClipAnimationTiming(timing.$1, timing.$2);
    _showEditorNotification('Animacao aplicada. Clique em Testar animacao.');
  }

  void _previewSelectedAnimation() {
    final clip = _kenBurnsToolClip;
    if (clip == null) return;
    _controller.setPlayheadPosition(clip.timelineStart);
    _controller.setTimelinePlaybackActive(true);
  }

  @override
  Widget build(BuildContext context) {
    final kenBurnsToolClip = _kenBurnsToolClip;
    return Focus(
      focusNode: _editorFocusNode,
      autofocus: true,
      onKeyEvent: _handleEditorFocusKeyEvent,
      child: PopScope<void>(
        canPop: _canPopEditor,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            return;
          }
          unawaited(_handleBlockedPop());
        },
        child: Scaffold(
          body: SafeArea(
            child: DecoratedBox(
              decoration: BoxDecoration(color: TgiColors.background),
              child: Padding(
                padding: const EdgeInsets.all(TgiSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EditorHeader(
                      projectName: _controller.project.name,
                      onToggleLibrary: () => setState(() {
                        _libraryVisible = !_libraryVisible;
                        _scheduleWorkspaceLayoutSave();
                      }),
                      onToggleInspector: () => setState(() {
                        _inspectorVisible = !_inspectorVisible;
                        _scheduleWorkspaceLayoutSave();
                      }),
                      isImporting: _controller.isImporting,
                      isExporting: _controller.isExporting,
                      exportProgress: _controller.exportProgress,
                      exportRemaining: _controller.exportRemaining,
                      isGeneratingCaptions: _controller.isGeneratingCaptions,
                      captionProgress: _controller.captionProgress,
                      captionProgressMessage:
                          _controller.captionProgressMessage,
                      isOptimizingPreview: _controller.isOptimizingPreview,
                      previewOptimizationProgress:
                          _controller.previewOptimizationProgress,
                      previewOptimizationRemaining:
                          _controller.previewOptimizationRemaining,
                      previewOptimizationAutomatic:
                          _controller.previewOptimizationAutomatic,
                      onCancelPreviewOptimization:
                          _controller.cancelPreviewOptimization,
                      canExport: _controller.canExport,
                      canUndo: _controller.canUndo,
                      canRedo: _controller.canRedo,
                      canCopy: _controller.canCopyClips,
                      canPaste: _controller.canPasteClips,
                      canDuplicate: _controller.canDuplicateClips,
                      onBack: () => unawaited(_leaveEditor()),
                      onSaveProject: _saveProject,
                      onProjectTools: _showProjectTools,
                      onLoadProject: _loadProject,
                      onUndo: _controller.undo,
                      onRedo: _controller.redo,
                      onCopy: _controller.copySelectedTimelineClips,
                      onPaste: _controller.pasteCopiedTimelineClips,
                      onDuplicate: _controller.duplicateSelectedTimelineClips,
                      onImportVideo: _controller.importVideo,
                      onOpenKeyboardSettings: _openKeyboardSettings,
                      onOpenMcpSettings: () => unawaited(_openMcpSettings()),
                      aiRunning: _automation.running,
                      aiConnected: _automation.connectedClients > 0,
                      onEmergencyStop: () => unawaited(_automation.stop()),
                      onResetWorkspaceLayout: _resetWorkspaceLayout,
                      onWatermarkSettings: _openWatermarkSettings,
                      exportLabel: _isQuickCreator
                          ? 'Exportar Shorts'
                          : 'Exportar',
                      onExport: _isQuickCreator
                          ? _exportShortsTimeline
                          : _exportTimeline,
                      onCancelExport: _controller.cancelExport,
                    ),
                    Expanded(
                      child: _ResponsiveEditorWorkspace(
                        workspace: LayoutBuilder(
                          builder: (context, constraints) {
                            final smartCutClip =
                                _controller.selectedTimelineVideoClip ??
                                _controller.activeTimelineClip;
                            Widget panelForMode(
                              _LeftPanelMode mode,
                            ) => switch (mode) {
                              _LeftPanelMode.professionalColor => _Panel(
                                title: 'Correção de cor',
                                icon: Icons.gradient_outlined,
                                glow: true,
                                accentColor: TgiColors.textSecondary,
                                child: ProfessionalColorPanel(
                                  clip: _controller.selectedTimelineVideoClip,
                                  mediaName: _controller
                                      .selectedTimelineClipMediaItem
                                      ?.name,
                                  analysis: _colorAnalysis,
                                  analysisLoading: _colorAnalysisLoading,
                                  compareOriginal: _colorCompareOriginal,
                                  whiteBalancePickerActive:
                                      _whiteBalancePickerActive,
                                  onRefreshAnalysis: _requestColorAnalysis,
                                  onCompareOriginalChanged: (value) => setState(
                                    () => _colorCompareOriginal = value,
                                  ),
                                  onWhiteBalancePickerChanged:
                                      _setWhiteBalancePickerActive,
                                  onBrightnessChanged:
                                      _controller.updateSelectedVideoBrightness,
                                  onContrastChanged:
                                      _controller.updateSelectedVideoContrast,
                                  onSaturationChanged:
                                      _controller.updateSelectedVideoSaturation,
                                  onExposureChanged:
                                      _controller.updateSelectedVideoExposure,
                                  onHueChanged:
                                      _controller.updateSelectedVideoHue,
                                  onTemperatureChanged: (value) => _controller
                                      .updateSelectedVideoProfessionalColor(
                                        temperature: value,
                                      ),
                                  onTintChanged: (value) => _controller
                                      .updateSelectedVideoProfessionalColor(
                                        tint: value,
                                      ),
                                  onShadowsChanged: (value) => _controller
                                      .updateSelectedVideoProfessionalColor(
                                        shadows: value,
                                      ),
                                  onHighlightsChanged: (value) => _controller
                                      .updateSelectedVideoProfessionalColor(
                                        highlights: value,
                                      ),
                                  onCurvesChanged:
                                      (
                                        shadows,
                                        midtones,
                                        highlights,
                                      ) => _controller
                                          .updateSelectedVideoProfessionalColor(
                                            curveShadows: shadows,
                                            curveMidtones: midtones,
                                            curveHighlights: highlights,
                                          ),
                                  onInteractionStart:
                                      _beginProfessionalColorInteraction,
                                  onInteractionEnd:
                                      _endProfessionalColorInteraction,
                                  onReset: _controller
                                      .resetSelectedVideoProfessionalColor,
                                ),
                              ),
                              _LeftPanelMode.advancedSpeed => _Panel(
                                title: 'Velocidade avançada',
                                icon: Icons.speed_outlined,
                                glow: true,
                                accentColor: TgiColors.accentRose,
                                child: AdvancedSpeedPanel(
                                  clip: _controller.selectedTimelineVideoClip,
                                  mediaName: _controller
                                      .selectedTimelineClipMediaItem
                                      ?.name,
                                  onConstantSpeedChanged: _controller
                                      .updateSelectedVideoPlaybackSpeed,
                                  onRampSelected: (multipliers, label) =>
                                      _controller.applySelectedVideoSpeedRamp(
                                        multipliers,
                                        label: label,
                                      ),
                                  onSlowMotion: () => _controller
                                      .updateSelectedVideoPlaybackSpeed(0.5),
                                  onFreezeFrame: () => unawaited(
                                    _controller.insertFreezeFrameAtPlayhead(),
                                  ),
                                  onReverseChanged:
                                      _controller.updateSelectedVideoReverse,
                                ),
                              ),
                              _LeftPanelMode.transformCrop => _Panel(
                                title: 'Transformar e recortar',
                                icon: Icons.crop_rotate_outlined,
                                glow: true,
                                accentColor: TgiColors.textSecondary,
                                child: TransformCropPanel(
                                  clip: switch (_controller
                                      .selectedTimelineClip) {
                                    final clip?
                                        when clip.trackType ==
                                                TrackType.video ||
                                            clip.trackType == TrackType.image =>
                                      clip,
                                    _ => null,
                                  },
                                  mediaName: _controller
                                      .selectedTimelineClipMediaItem
                                      ?.name,
                                  cropModeActive: _transformCropModeActive,
                                  onCropModeChanged: (value) => setState(
                                    () => _transformCropModeActive = value,
                                  ),
                                  onTransformChanged:
                                      ({
                                        offsetX,
                                        offsetY,
                                        scale,
                                        rotationDegrees,
                                        flipHorizontal,
                                        flipVertical,
                                      }) => _controller
                                          .updateSelectedClipTransform(
                                            offsetX: offsetX,
                                            offsetY: offsetY,
                                            scale: scale,
                                            rotationDegrees: rotationDegrees,
                                            flipHorizontal: flipHorizontal,
                                            flipVertical: flipVertical,
                                          ),
                                  onCropChanged: ({left, top, right, bottom}) =>
                                      _controller.updateSelectedClipCrop(
                                        left: left,
                                        top: top,
                                        right: right,
                                        bottom: bottom,
                                      ),
                                  onRotateLeft: () =>
                                      _controller.rotateSelectedClipBy(-90),
                                  onRotateRight: () =>
                                      _controller.rotateSelectedClipBy(90),
                                  onAspectRatioSelected: _controller
                                      .applySelectedClipCropAspectRatio,
                                  onReset: _controller
                                      .resetSelectedClipTransformAndCrop,
                                  onInteractionStart:
                                      _controller.beginInteractiveEdit,
                                  onInteractionEnd:
                                      _controller.commitInteractiveEdit,
                                ),
                              ),
                              _LeftPanelMode.audioTools => _Panel(
                                title: 'Ferramentas de áudio',
                                icon: Icons.tune_outlined,
                                glow: true,
                                accentColor: TgiColors.accentGreen,
                                child: AudioToolPanel(
                                  peak: _controller.audioPeakAtPlayhead,
                                  meterReady: _controller.audioMeterReady,
                                  isAnalyzing: _controller.isAnalyzingAudio,
                                  onAnalyzeLevels:
                                      _controller.analyzeAudioLevels,
                                  onLevelVoice: _controller.levelSelectedVoice,
                                  onDuckMusic: (track, db) =>
                                      _controller.duckSelectedMusic(
                                        track,
                                        reductionDb: db,
                                      ),
                                  clip: _controller.selectedTimelineAudioClip,
                                  mediaName: _controller
                                      .selectedTimelineClipMediaItem
                                      ?.name,
                                  audioTracks: _controller.project.tracks
                                      .where(
                                        (track) =>
                                            track.type == TrackType.audio,
                                      )
                                      .toList(),
                                  canUnlink: _controller.canUnlinkSelectedAudio,
                                  onClipVolumeChanged:
                                      _updateSelectedClipVolume,
                                  onNoiseReductionChanged:
                                      _updateSelectedAudioNoiseReduction,
                                  onFadeInChanged:
                                      _updateSelectedAudioClipFadeIn,
                                  onFadeOutChanged:
                                      _updateSelectedAudioClipFadeOut,
                                  onUnlink:
                                      _controller.unlinkSelectedAudioFromVideo,
                                  onTrackVolumeChanged:
                                      _controller.setTimelineTrackVolume,
                                  onTrackMutedChanged:
                                      _controller.setTimelineTrackMuted,
                                  onTrackSoloChanged:
                                      _controller.setTimelineTrackSolo,
                                  onInteractionStart:
                                      _controller.beginInteractiveEdit,
                                  onInteractionEnd:
                                      _controller.commitInteractiveEdit,
                                ),
                              ),
                              _LeftPanelMode.smartCut => _Panel(
                                title: 'Corte Inteligente',
                                icon: Icons.auto_fix_high_rounded,
                                glow: true,
                                accentColor: TgiColors.textSecondary,
                                child: SmartCutPanel(
                                  clip: smartCutClip,
                                  mediaName: smartCutClip == null
                                      ? null
                                      : _controller.project
                                            .mediaItemById(
                                              smartCutClip.mediaItemId,
                                            )
                                            ?.name,
                                  intensity: _smartCutIntensity,
                                  analysis: _controller.smartCutAnalysis,
                                  isAnalyzing: _controller.isAnalyzingSmartCut,
                                  canAnalyze: _controller.canAnalyzeSmartCut,
                                  canApply: _controller.canApplySmartCut,
                                  onIntensityChanged: _setSmartCutIntensity,
                                  onAnalyze: () =>
                                      unawaited(_analyzeSmartCut()),
                                  onApply: _applySmartCut,
                                  onDiscard: _controller.clearSmartCutAnalysis,
                                  onPreviewSegment: _previewSmartCutSegment,
                                ),
                              ),
                              _LeftPanelMode.animations => _Panel(
                                title: 'Animacao',
                                icon: Icons.animation_outlined,
                                glow: true,
                                accentColor: TgiColors.accentRose,
                                child: AnimationToolPanel(
                                  clip: kenBurnsToolClip,
                                  mediaName: _controller
                                      .selectedTimelineClipMediaItem
                                      ?.name,
                                  editingStart:
                                      _kenBurnsPickTarget ==
                                      _KenBurnsPickTarget.start,
                                  onEditingStartChanged:
                                      _selectAnimationEditTarget,
                                  onEnabledChanged: _controller
                                      .updateSelectedClipKenBurnsEnabled,
                                  onPresetSelected: _applyAnimationPreset,
                                  intensity: _animationIntensity,
                                  onIntensityChanged: (value) => setState(
                                    () => _animationIntensity = value,
                                  ),
                                  speed: _animationSpeed,
                                  onSpeedChanged: (value) =>
                                      setState(() => _animationSpeed = value),
                                  onFocusPointSelected:
                                      _handleKenBurnsPreviewPointSelected,
                                  onStartScaleChanged: _controller
                                      .updateSelectedClipKenBurnsStartScale,
                                  onEndScaleChanged: _controller
                                      .updateSelectedClipKenBurnsEndScale,
                                  onTimingChanged: _controller
                                      .updateSelectedClipAnimationTiming,
                                  onSwap: _controller
                                      .swapSelectedClipAnimationDirection,
                                  onReset:
                                      _controller.resetSelectedClipAnimation,
                                  onPreview: _previewSelectedAnimation,
                                  onInteractionStart:
                                      _controller.beginInteractiveEdit,
                                  onInteractionEnd:
                                      _controller.commitInteractiveEdit,
                                ),
                              ),
                              _LeftPanelMode.chromaKey => _Panel(
                                title: 'Chroma Key',
                                icon: Icons.colorize_outlined,
                                glow: true,
                                accentColor: TgiColors.accentGreen,
                                child: ChromaKeyPanel(
                                  videoClip:
                                      _controller.selectedTimelineVideoClip,
                                  mediaName: _controller
                                      .selectedTimelineClipMediaItem
                                      ?.name,
                                  onEnabledChanged: (enabled) {
                                    if (!enabled) {
                                      _setChromaColorPickerActive(false);
                                    }
                                    _controller
                                        .updateSelectedVideoChromaKeyEnabled(
                                          enabled,
                                        );
                                  },
                                  onColorChanged: (color) {
                                    if (_chromaColorPickerActive) {
                                      _setChromaColorPickerActive(false);
                                    }
                                    _controller
                                        .updateSelectedVideoChromaKeyColor(
                                          color,
                                        );
                                  },
                                  colorPickerActive: _chromaColorPickerActive,
                                  onColorPickerActiveChanged:
                                      _setChromaColorPickerActive,
                                  onSimilarityChanged: _controller
                                      .updateSelectedVideoChromaKeySimilarity,
                                  onBlendChanged: _controller
                                      .updateSelectedVideoChromaKeyBlend,
                                  transparencyPreview:
                                      _chromaTransparencyPreview,
                                  onTransparencyPreviewChanged: (value) {
                                    setState(() {
                                      _chromaTransparencyPreview = value;
                                    });
                                  },
                                ),
                              ),
                              _LeftPanelMode.maskTracking => _Panel(
                                title: 'Mascara e tracking',
                                icon: Icons.track_changes,
                                glow: true,
                                accentColor: TgiColors.accentRose,
                                child: Builder(
                                  builder: (context) {
                                    final clip =
                                        _controller.selectedTimelineVideoClip;
                                    final time = clip == null
                                        ? 0.0
                                        : _previewClipTime(clip);
                                    final maskX =
                                        clip?.keyframedValue(
                                          domain.ClipKeyframeProperty.maskX,
                                          time,
                                        ) ??
                                        0.5;
                                    final maskY =
                                        clip?.keyframedValue(
                                          domain.ClipKeyframeProperty.maskY,
                                          time,
                                        ) ??
                                        0.5;
                                    return MaskTrackingPanel(
                                      clip: clip,
                                      mediaName: _controller
                                          .selectedTimelineClipMediaItem
                                          ?.name,
                                      currentX: maskX,
                                      currentY: maskY,
                                      isTracking: _controller.isTrackingMask,
                                      trackingProgress:
                                          _controller.maskTrackingProgress,
                                      onEnabledChanged: (value) =>
                                          _controller.updateSelectedVideoMask(
                                            enabled: value,
                                          ),
                                      onShapeChanged: (value) =>
                                          _controller.updateSelectedVideoMask(
                                            shape: value,
                                          ),
                                      onEffectChanged: (value) =>
                                          _controller.updateSelectedVideoMask(
                                            effect: value,
                                          ),
                                      onGeometryChanged:
                                          ({x, y, width, height}) => _controller
                                              .updateSelectedVideoMask(
                                                x: x,
                                                y: y,
                                                width: width,
                                                height: height,
                                              ),
                                      onFeatherChanged: (value) =>
                                          _controller.updateSelectedVideoMask(
                                            feather: value,
                                          ),
                                      onIntensityChanged: (value) =>
                                          _controller.updateSelectedVideoMask(
                                            intensity: value,
                                          ),
                                      onInvertedChanged: (value) =>
                                          _controller.updateSelectedVideoMask(
                                            inverted: value,
                                          ),
                                      onSavePoint: () => _controller
                                          .setSelectedVideoMaskAtPlayhead(
                                            x: maskX,
                                            y: maskY,
                                          ),
                                      onTrack: () => unawaited(
                                        _controller.trackSelectedVideoMask(),
                                      ),
                                      onAttachImage: () => unawaited(
                                        _attachImageToMaskTracking(),
                                      ),
                                      onClearTracking:
                                          _controller.clearSelectedMaskTracking,
                                    );
                                  },
                                ),
                              ),
                              _LeftPanelMode.captions => _Panel(
                                title: 'Legendas',
                                icon: Icons.subtitles_outlined,
                                glow: true,
                                accentColor: TgiColors.accentRose,
                                child: CaptionsPanel(
                                  onImportSrt: () => unawaited(_importSrt()),
                                  onEditStyle: () =>
                                      unawaited(_editCaptionStyle()),
                                  captions: _controller.generatedCaptionClips,
                                  selectedTimelineGroupId:
                                      _controller.selectedTimelineGroupId,
                                  canGenerate:
                                      _controller.canGenerateAutomaticCaptions,
                                  canExport:
                                      _controller.canExportGeneratedCaptions,
                                  isGenerating:
                                      _controller.isGeneratingCaptions,
                                  onGenerate: () =>
                                      unawaited(_addAutomaticCaptions()),
                                  onAddQuickCaption: () =>
                                      unawaited(_addQuickCaption()),
                                  onExportSrt: () => unawaited(
                                    _exportGeneratedCaptions(
                                      SubtitleExportFormat.srt,
                                    ),
                                  ),
                                  onExportVtt: () => unawaited(
                                    _exportGeneratedCaptions(
                                      SubtitleExportFormat.vtt,
                                    ),
                                  ),
                                  onCaptionSelected: _selectCaptionClip,
                                  onCaptionChanged:
                                      _controller.updateTextClipText,
                                ),
                              ),
                              _LeftPanelMode.soundEffects => _Panel(
                                title: 'Audio Pick',
                                icon: Icons.library_music_outlined,
                                glow: true,
                                accentColor: TgiColors.accentGreen,
                                child: SoundEffectsLibraryPanel(
                                  effects: PublicSoundEffectsService.catalog,
                                  addingEffectId: _addingSoundEffectId,
                                  previewingEffectId: _previewingSoundEffectId,
                                  loadingPreviewEffectId:
                                      _loadingPreviewSoundEffectId,
                                  previewPosition: _soundEffectPreviewPosition,
                                  previewDuration: _soundEffectPreviewDuration,
                                  onAddEffect: _addSoundEffectFromLibrary,
                                  onPreviewEffect:
                                      _previewSoundEffectFromLibrary,
                                ),
                              ),
                              _LeftPanelMode.visualMedia => _Panel(
                                title: 'Biblioteca visual',
                                icon: Icons.collections_outlined,
                                glow: true,
                                accentColor: TgiColors.textSecondary,
                                child: VisualMediaLibraryPanel(
                                  items: PublicVisualMediaService.catalog,
                                  addingItemId: _addingVisualMediaId,
                                  onAddItem: _addVisualMediaFromLibrary,
                                ),
                              ),
                              _LeftPanelMode.transitions => _Panel(
                                title: 'Transicoes',
                                icon: Icons.movie_filter_outlined,
                                glow: true,
                                accentColor: TgiColors.accentRose,
                                child: TransitionLibraryPanel(
                                  onInsertTransitionPreset:
                                      _insertTransitionPresetFromLibrary,
                                ),
                              ),
                              _LeftPanelMode.mediaPool => _Panel(
                                title: 'Media Pool',
                                icon: Icons.video_library_outlined,
                                glow: true,
                                accentColor: TgiColors.textSecondary,
                                child: MediaPoolList(
                                  items: _controller.project.mediaPool,
                                  selectedItemId:
                                      _controller.selectedMediaItemId,
                                  onItemSelected: _controller.selectMediaItem,
                                  onItemAppended:
                                      _controller.appendMediaItemToTimeline,
                                  onItemRemoved: (item) =>
                                      _controller.removeMediaItem(item.id),
                                  onImportRequested: _controller
                                      .importMediaAndAddToEmptyTimeline,
                                  onExternalFilesDropped:
                                      _importDroppedMediaPoolFiles,
                                ),
                              ),
                            };
                            final videoPreload =
                                _controller.nextVideoPreviewClip;
                            final activeVisualAdjustments =
                                _visualAdjustmentsForClip(
                                  _controller.activeTimelineClip,
                                );
                            final activeMaskClip =
                                _controller.activeTimelineClip?.trackType ==
                                    TrackType.video
                                ? _controller.activeTimelineClip
                                : null;
                            final activeMaskTime = activeMaskClip == null
                                ? 0.0
                                : _previewClipTime(activeMaskClip);
                            final previewMask =
                                activeMaskClip?.maskEnabled == true
                                ? VideoPreviewMask(
                                    shape: activeMaskClip!.maskShape,
                                    effect: activeMaskClip.maskEffect,
                                    x: activeMaskClip.keyframedValue(
                                      domain.ClipKeyframeProperty.maskX,
                                      activeMaskTime,
                                    ),
                                    y: activeMaskClip.keyframedValue(
                                      domain.ClipKeyframeProperty.maskY,
                                      activeMaskTime,
                                    ),
                                    width: activeMaskClip.keyframedValue(
                                      domain.ClipKeyframeProperty.maskWidth,
                                      activeMaskTime,
                                    ),
                                    height: activeMaskClip.keyframedValue(
                                      domain.ClipKeyframeProperty.maskHeight,
                                      activeMaskTime,
                                    ),
                                    feather: activeMaskClip.maskFeather,
                                    intensity: activeMaskClip.maskIntensity,
                                    inverted: activeMaskClip.maskInverted,
                                  )
                                : null;
                            final previewVisualAdjustments =
                                _leftPanelMode ==
                                        _LeftPanelMode.professionalColor &&
                                    _colorCompareOriginal
                                ? activeVisualAdjustments.copyWith(
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
                                  )
                                : activeVisualAdjustments;
                            final preview = _Panel(
                              title: 'Preview',
                              icon: Icons.smart_display_outlined,
                              glow: true,
                              accentColor: TgiColors.textSecondary,
                              trailing: PopupMenuButton<String>(
                                key: const ValueKey('preview-proxy-menu'),
                                tooltip: 'Qualidade da prévia',
                                onSelected: (value) {
                                  if (value == 'prepare') {
                                    unawaited(_controller.optimizePreview());
                                  } else {
                                    _controller.setUsePreviewProxies(
                                      value == 'auto',
                                    );
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'auto',
                                    child: Text(
                                      'Automática · usar proxy disponível',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'original',
                                    child: Text('Qualidade original'),
                                  ),
                                  PopupMenuItem(
                                    value: 'prepare',
                                    enabled: _controller.canOptimizePreview,
                                    child: const Text(
                                      'Preparar proxy de edição',
                                    ),
                                  ),
                                ],
                                child: Container(
                                  height: 28,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TgiColors.surfaceRaised,
                                    border: Border.all(color: TgiColors.border),
                                    borderRadius: BorderRadius.circular(
                                      TgiRadii.sm,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _controller.previewUsesProxy
                                            ? 'Proxy'
                                            : 'Original',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: TgiColors.textPrimary,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_drop_down,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              child: VideoPreviewPanel(
                                visualLayerOrder:
                                    _controller.project.layerOrderByClipId,
                                baseVideoClipId:
                                    _controller.activeTimelineClip?.id,
                                item: _controller.previewMediaItem,
                                onImportRequested: _controller
                                    .importMediaAndAddToEmptyTimeline,
                                outputAspectRatio:
                                    _exportSettings.resolution.width /
                                    _exportSettings.resolution.height,
                                cropMainVideoToFill:
                                    _exportSettings.resolution ==
                                    FfmpegExportResolution.shorts1080,
                                requestedPosition:
                                    _controller.previewSourcePosition,
                                videoPreloadEntry: videoPreload == null
                                    ? null
                                    : VideoPreviewPreloadEntry(
                                        clipId: videoPreload.clipId,
                                        item: videoPreload.mediaItem,
                                        sourcePosition:
                                            videoPreload.sourcePosition,
                                        timelineStart:
                                            videoPreload.timelineStart,
                                        playbackSpeed:
                                            videoPreload.playbackSpeed,
                                      ),
                                videoOpacity:
                                    _controller.activeTimelineClip == null
                                    ? 1
                                    : _previewOpacityForClip(
                                        _controller.activeTimelineClip!,
                                      ),
                                visualAdjustments: previewVisualAdjustments,
                                mask: previewMask,
                                maskToolActive:
                                    _leftPanelMode ==
                                        _LeftPanelMode.maskTracking &&
                                    _controller.selectedTimelineVideoClip?.id ==
                                        activeMaskClip?.id,
                                onMaskGeometryChanged:
                                    ({x, y, width, height}) =>
                                        _controller.updateSelectedVideoMask(
                                          x: x,
                                          y: y,
                                          width: width,
                                          height: height,
                                        ),
                                transformToolActive:
                                    _leftPanelMode ==
                                        _LeftPanelMode.transformCrop &&
                                    _controller.selectedTimelineClip?.id ==
                                        _controller.activeTimelineClip?.id,
                                transformCropMode: _transformCropModeActive,
                                onTransformPositionChanged: (x, y) =>
                                    _controller.updateSelectedClipTransform(
                                      offsetX: x,
                                      offsetY: y,
                                    ),
                                onTransformScaleChanged: (scale) => _controller
                                    .updateSelectedClipTransform(scale: scale),
                                onTransformCropChanged:
                                    ({left, top, right, bottom}) =>
                                        _controller.updateSelectedClipCrop(
                                          left: left,
                                          top: top,
                                          right: right,
                                          bottom: bottom,
                                        ),
                                onTransformInteractionStart:
                                    _controller.beginInteractiveEdit,
                                onTransformInteractionEnd:
                                    _controller.commitInteractiveEdit,
                                chromaColorPickerActive:
                                    _leftPanelMode ==
                                        _LeftPanelMode.chromaKey &&
                                    _chromaColorPickerActive &&
                                    _controller.selectedTimelineVideoClip?.id ==
                                        _controller.activeTimelineClip?.id,
                                chromaTransparencyPreview:
                                    _chromaTransparencyPreview,
                                onChromaColorPicked: _handleChromaColorPicked,
                                onChromaColorPickError:
                                    _handleChromaColorPickError,
                                whiteBalanceColorPickerActive:
                                    _leftPanelMode ==
                                        _LeftPanelMode.professionalColor &&
                                    _whiteBalancePickerActive &&
                                    _controller.selectedTimelineVideoClip?.id ==
                                        _controller.activeTimelineClip?.id,
                                onWhiteBalanceColorPicked:
                                    _handleWhiteBalanceColorPicked,
                                onWhiteBalancePickError:
                                    _handleColorAnalysisError,
                                colorAnalysisRequest: _colorAnalysisRequest,
                                onColorAnalysis: _handleColorAnalysis,
                                onColorAnalysisError: _handleColorAnalysisError,
                                kenBurnsToolActive:
                                    _kenBurnsToolActive &&
                                    _leftPanelMode == _LeftPanelMode.animations,
                                kenBurnsPickStart:
                                    _kenBurnsPickTarget ==
                                    _KenBurnsPickTarget.start,
                                kenBurnsStartX: kenBurnsToolClip?.startOverlayX,
                                kenBurnsStartY: kenBurnsToolClip?.startOverlayY,
                                kenBurnsEndX: kenBurnsToolClip?.overlayX,
                                kenBurnsEndY: kenBurnsToolClip?.overlayY,
                                onKenBurnsPointSelected:
                                    _handleKenBurnsPreviewPointSelected,
                                videoOverlayEntries: _controller
                                    .allVideoOverlaysAtPlayhead
                                    .map(
                                      (entry) => VideoOverlayEntry(
                                        item: entry.mediaItem,
                                        clipId: entry.clip.id,
                                        timelineGroupId:
                                            entry.clip.timelineGroupId,
                                        sourcePosition: entry.sourcePosition,
                                        playbackSpeed: entry.clip.playbackSpeed,
                                        overlayX: _previewOverlayX(entry.clip),
                                        overlayY: _previewOverlayY(entry.clip),
                                        overlayScale: _previewOverlayScale(
                                          entry.clip,
                                        ),
                                        opacity: entry.opacity,
                                        isActive: entry.isActive,
                                        visualAdjustments:
                                            _visualAdjustmentsForClip(
                                              entry.clip,
                                            ),
                                        maskEnabled: entry.clip.maskEnabled,
                                        maskShape: entry.clip.maskShape,
                                        maskEffect: entry.clip.maskEffect,
                                        maskX: entry.clip.keyframedValue(
                                          domain.ClipKeyframeProperty.maskX,
                                          _previewClipTime(entry.clip),
                                        ),
                                        maskY: entry.clip.keyframedValue(
                                          domain.ClipKeyframeProperty.maskY,
                                          _previewClipTime(entry.clip),
                                        ),
                                        maskWidth: entry.clip.keyframedValue(
                                          domain.ClipKeyframeProperty.maskWidth,
                                          _previewClipTime(entry.clip),
                                        ),
                                        maskHeight: entry.clip.keyframedValue(
                                          domain
                                              .ClipKeyframeProperty
                                              .maskHeight,
                                          _previewClipTime(entry.clip),
                                        ),
                                        maskFeather: entry.clip.maskFeather,
                                        maskIntensity: entry.clip.maskIntensity,
                                        maskInverted: entry.clip.maskInverted,
                                        maskToolActive:
                                            _leftPanelMode ==
                                                _LeftPanelMode.maskTracking &&
                                            _controller
                                                    .selectedTimelineVideoClip
                                                    ?.id ==
                                                entry.clip.id,
                                      ),
                                    )
                                    .toList(),
                                imageOverlayItem:
                                    _controller.imageOverlayMediaItem,
                                imageOverlayEntries: _controller
                                    .allImageOverlaysAtPlayhead
                                    .map(
                                      (clip) => ImageOverlayEntry(
                                        item: _controller.project.mediaItemById(
                                          clip.mediaItemId,
                                        )!,
                                        clipId: clip.id,
                                        overlayX: _previewOverlayX(clip),
                                        overlayY: _previewOverlayY(clip),
                                        overlayScale: _previewOverlayScale(
                                          clip,
                                        ),
                                        imageFit: clip.imageFit,
                                        opacity: _controller
                                            .keyframedOpacityForClip(clip),
                                        cropLeft: clip.cropLeft,
                                        cropTop: clip.cropTop,
                                        cropRight: clip.cropRight,
                                        cropBottom: clip.cropBottom,
                                        transformOffsetX: clip.transformOffsetX,
                                        transformOffsetY: clip.transformOffsetY,
                                        transformScale: clip.transformScale,
                                        rotationDegrees: clip.rotationDegrees,
                                        flipHorizontal: clip.flipHorizontal,
                                        flipVertical: clip.flipVertical,
                                        isActive:
                                            clip.id ==
                                            _controller
                                                .activeImageOverlayClip
                                                ?.id,
                                        timelineGroupId: clip.timelineGroupId,
                                      ),
                                    )
                                    .toList(),
                                textOverlayEntries: _controller
                                    .allTextOverlaysAtPlayhead
                                    .map(
                                      (clip) => TextOverlayEntry(
                                        clipId: clip.id,
                                        timelineGroupId: clip.timelineGroupId,
                                        text: clip.textContent,
                                        fontFamily: clip.fontFamily,
                                        overlayX: _previewOverlayX(clip),
                                        overlayY: _previewOverlayY(clip),
                                        fontSize: clip.fontSize,
                                        textColor: clip.textColor,
                                        backgroundColor: clip.backgroundColor,
                                        opacity: _previewOpacityForClip(clip),
                                        animation: clip.textAnimation,
                                        animationProgress: _controller
                                            .textAnimationProgressForClip(clip),
                                        isActive:
                                            clip.timelineGroupId ==
                                            _controller.selectedTimelineGroupId,
                                      ),
                                    )
                                    .toList(),
                                transitionPreviewEntries:
                                    _activeTransitionPreviewEntries(),
                                audioPreviewEntries: _controller
                                    .activeStandaloneAudioPreviewClips
                                    .map(
                                      (clip) => AudioPreviewEntry(
                                        clipId: clip.clipId,
                                        item: clip.mediaItem,
                                        sourcePosition: clip.sourcePosition,
                                        volume: clip.volume,
                                        playbackSpeed: clip.playbackSpeed,
                                      ),
                                    )
                                    .toList(),
                                imageOverlayClipId:
                                    _controller.activeImageOverlayClip?.id,
                                imageOverlayX:
                                    _controller
                                        .activeImageOverlayClip
                                        ?.overlayX ??
                                    1,
                                imageOverlayY:
                                    _controller
                                        .activeImageOverlayClip
                                        ?.overlayY ??
                                    0,
                                imageOverlayScale:
                                    _controller
                                        .activeImageOverlayClip
                                        ?.overlayScale ??
                                    1,
                                onImageOverlayMoved:
                                    _controller.updateImageOverlayPosition,
                                onImageOverlayResized:
                                    _controller.updateImageOverlayScale,
                                onImageOverlayTap: (groupId) => _controller
                                    .selectTimelineClipGroup(groupId),
                                onVideoOverlayMoved:
                                    _controller.updateVideoOverlayPosition,
                                onVideoOverlayResized:
                                    _controller.updateVideoOverlayScale,
                                onVideoOverlayTap: (groupId) => _controller
                                    .selectTimelineClipGroup(groupId),
                                onTextOverlayMoved: _controller
                                    .updateTextOverlayPositionForSelection,
                                onTextOverlayTap:
                                    _controller.selectTextOverlayFromPreview,
                                onTextOverlayEdit: _editTextClipById,
                                onTextOverlayInteractionStart:
                                    _controller.beginInteractiveEdit,
                                onTextOverlayInteractionEnd:
                                    _controller.commitInteractiveEdit,
                                timelinePosition: _controller.playheadPosition,
                                timelineDuration:
                                    _controller.project.hasTimelineClips
                                    ? _controller.project.timelineDuration
                                    : null,
                                onPositionChanged:
                                    _controller.updatePlayheadFromPreview,
                                onTimelineSeek: _controller.setPlayheadPosition,
                                timelinePlaybackActive:
                                    _controller.timelinePlaybackActive,
                                onTimelinePlaybackChanged:
                                    _controller.setTimelinePlaybackActive,
                                continuePlaybackOnItemChange: true,
                                audioVolume: _controller.activeAudioVolume,
                                playbackSpeed: _controller.previewPlaybackSpeed,
                                transportLeadingControl: _PreviewEditingActions(
                                  cutActive: _controller.isCutMode,
                                  enabled: !_controller.isExporting,
                                  deleteEnabled:
                                      !_controller.isExporting &&
                                      _controller
                                          .selectedTimelineGroupIds
                                          .isNotEmpty,
                                  onCutPressed: () {
                                    if (_kenBurnsToolActive) {
                                      setState(
                                        () => _kenBurnsToolActive = false,
                                      );
                                    }
                                    _controller.toggleCutMode();
                                  },
                                  onDeletePressed:
                                      _controller.deleteSelectedTimelineClip,
                                  onTextPressed: () =>
                                      unawaited(_addQuickText()),
                                ),
                                transportTrailingControl: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _PlaybackSpeedMenu(
                                      speed:
                                          _controller.activeVideoPlaybackSpeed,
                                      enabled:
                                          !_controller.isExporting &&
                                          _controller
                                              .canChangeVideoPlaybackSpeed,
                                      onChanged: _controller
                                          .updateSelectedVideoPlaybackSpeed,
                                    ),
                                    const SizedBox(width: 4),
                                    _PreviewOptimizeButton(
                                      isImporting: _controller.isImporting,
                                      isExporting: _controller.isExporting,
                                      isOptimizingPreview:
                                          _controller.isOptimizingPreview,
                                      progress: _controller
                                          .previewOptimizationProgress,
                                      remaining: _controller
                                          .previewOptimizationRemaining,
                                      isAutomatic: _controller
                                          .previewOptimizationAutomatic,
                                      usesProxy: _controller.previewUsesProxy,
                                      canOptimizePreview:
                                          _controller.canOptimizePreview,
                                      onPressed: _controller.optimizePreview,
                                      onCancel:
                                          _controller.cancelPreviewOptimization,
                                    ),
                                  ],
                                ),
                              ),
                            );
                            final timeline = _Panel(
                              title: 'Timeline',
                              icon: Icons.view_timeline_outlined,
                              glow: true,
                              accentColor: TgiColors.textSecondary,
                              showHeader: false,
                              child: TimelinePanel(
                                key: _timelineKey,
                                rangeStart: _exportSettings.rangeStart,
                                rangeEnd: _exportSettings.rangeEnd,
                                onMarkRangeStart: () => _markExportRange(true),
                                onMarkRangeEnd: () => _markExportRange(false),
                                onClearRange: () => _setExportSettings(
                                  _exportSettings.copyWith(clearRange: true),
                                ),
                                project: _controller.project,
                                playheadPosition: _controller.playheadPosition,
                                audioWaveforms:
                                    _controller.audioWaveformsByMediaId,
                                cutMode: _controller.isCutMode,
                                selectedTimelineGroupId:
                                    _controller.selectedTimelineGroupId,
                                selectedTimelineGroupIds:
                                    _controller.selectedTimelineGroupIds,
                                audioVideoLinked:
                                    _controller.selectedAudioVideoLinked,
                                onAudioVideoLinkToggle:
                                    _controller.canToggleSelectedAudioVideoLink
                                    ? _controller.toggleSelectedAudioVideoLink
                                    : null,
                                onMediaDropped: _addMediaItemToTimeline,
                                onClipMoved: _controller.moveTimelineClipGroup,
                                onClipResized: _controller.resizeImageClip,
                                onClipCut: _controller.cutTimelineClip,
                                onClipSelected:
                                    (
                                      group, {
                                      bool additive = false,
                                      bool toggle = false,
                                      String? clipId,
                                    }) {
                                      _requestEditorShortcutFocus();
                                      _controller.selectTimelineClipGroup(
                                        group,
                                        additive: additive,
                                        toggle: toggle,
                                        clipId: clipId,
                                      );
                                    },
                                onBoxSelection:
                                    (
                                      groups, {
                                      bool additive = false,
                                      bool toggle = false,
                                      bool intersect = false,
                                    }) {
                                      _requestEditorShortcutFocus();
                                      _controller.selectTimelineClipGroups(
                                        groups,
                                        additive: additive,
                                        toggle: toggle,
                                        intersect: intersect,
                                      );
                                    },
                                onTextClipEdit: (clip) =>
                                    unawaited(_editTextClip(clip)),
                                onTextInsertRequested: (position) => unawaited(
                                  _addTextAtTimelinePosition(position),
                                ),
                                onQuickCaptionInsertRequested: (position) =>
                                    unawaited(
                                      _addCaptionAtTimelinePosition(position),
                                    ),
                                onPlayheadChanged: (position) {
                                  _requestEditorShortcutFocus();
                                  _controller.setPlayheadPosition(position);
                                },
                                onClipVolumeChanged:
                                    _controller.updateClipVolume,
                                onClipFadeChanged:
                                    _controller.updateClipTransition,
                                onClipTrimPreview:
                                    _controller.previewTimelineClipTrim,
                                onClipTrimmed:
                                    _controller.commitTimelineClipTrim,
                                onClipTrimCanceled:
                                    _controller.cancelTimelineClipTrimPreview,
                                onClipMovedToTrack:
                                    _controller.moveTimelineClipToTrack,
                                onClipMovedToNewTrack:
                                    _controller.moveTimelineClipToNewTrack,
                                onAddTrack: _controller.addTimelineTrack,
                                onTrackDeleted: _controller.deleteTimelineTrack,
                                onTrackReordered:
                                    _controller.reorderTimelineTrack,
                                onTrackHeightChanged:
                                    _controller.resizeTimelineTrack,
                                onTrackResizeStart:
                                    _controller.beginInteractiveEdit,
                                onTrackResizeEnd:
                                    _controller.commitInteractiveEdit,
                                onAudioInventoryOpen: _showSoundEffectsLibrary,
                                onTrackRenamed: _controller.renameTimelineTrack,
                                onTrackLockedChanged:
                                    _controller.setTimelineTrackLocked,
                                onTrackHiddenChanged:
                                    _controller.setTimelineTrackHidden,
                                onTrackMutedChanged:
                                    _controller.setTimelineTrackMuted,
                                onTrackSoloChanged:
                                    _controller.setTimelineTrackSolo,
                                onMarkerAdd: _controller.addMarkerAtPlayhead,
                                onMarkerRenamed:
                                    _controller.updateTimelineMarkerName,
                                onMarkerDeleted:
                                    _controller.deleteTimelineMarker,
                                onTransitionDropped:
                                    _insertDroppedTransitionClipFromTimeline,
                                onTransitionMoved:
                                    _controller.moveTimelineTransition,
                                onTransitionEdit: _editTimelineTransition,
                                onTransitionDeleted:
                                    _controller.deleteTimelineTransition,
                                onRippleDelete: _controller
                                    .rippleDeleteSelectedTimelineClip,
                                onClipSlipped: _controller.slipTimelineClip,
                                onClipSlid: _controller.slideTimelineClip,
                              ),
                            );
                            final clipProperties = _Panel(
                              title: 'Propriedades',
                              icon: Icons.tune_outlined,
                              accentColor: TgiColors.accentRose,
                              child: _ClipPropertiesPanel(
                                clip: _controller.selectedTimelineClip,
                                selectedClipCount:
                                    _controller.selectedTimelineGroupCount,
                                mediaItem:
                                    _controller.selectedTimelineClipMediaItem,
                                audioClip:
                                    _controller.selectedTimelineAudioClip,
                                videoClip:
                                    _controller
                                            .selectedTimelineClip
                                            ?.trackType ==
                                        TrackType.video
                                    ? _controller.selectedTimelineVideoClip
                                    : null,
                                canUnlinkAudio:
                                    _controller.canUnlinkSelectedAudio,
                                canRelinkAudio:
                                    _controller.canRelinkSelectedAudio,
                                timelineDuration:
                                    _controller.project.timelineDuration,
                                onStartChanged: _updateSelectedClipStart,
                                onDurationChanged: _updateSelectedClipDuration,
                                onVolumeChanged: _updateSelectedClipVolume,
                                onAudioNoiseReductionChanged:
                                    _updateSelectedAudioNoiseReduction,
                                onAudioSpeedChanged: _controller
                                    .updateSelectedAudioPlaybackSpeed,
                                onUnlinkAudio:
                                    _controller.toggleSelectedAudioVideoLink,
                                onFadeInChanged: _updateSelectedClipFadeIn,
                                onFadeOutChanged: _updateSelectedClipFadeOut,
                                onFadeEnabled: _enableClipFade,
                                onAudioFadeInChanged:
                                    _updateSelectedAudioClipFadeIn,
                                onAudioFadeOutChanged:
                                    _updateSelectedAudioClipFadeOut,
                                onAudioFadeEnabled: _enableClipFade,
                                onVideoStabilizationChanged: _controller
                                    .updateSelectedVideoStabilization,
                                onTextChanged: (clip, value) =>
                                    _updateTextClipPanelProperties(
                                      clip,
                                      text: value,
                                    ),
                                onTextFontFamilyChanged: (clip, value) =>
                                    _updateTextClipPanelProperties(
                                      clip,
                                      fontFamily: value,
                                    ),
                                onTextFontSizeChanged: (clip, value) =>
                                    _updateTextClipPanelProperties(
                                      clip,
                                      fontSize: value,
                                    ),
                                onTextColorChanged: (clip, value) =>
                                    _updateTextClipPanelProperties(
                                      clip,
                                      textColor: value,
                                    ),
                                onTextBackgroundColorChanged: (clip, value) =>
                                    _updateTextClipPanelProperties(
                                      clip,
                                      backgroundColor: value,
                                    ),
                                onTextOpacityChanged: (clip, value) =>
                                    _updateTextClipPanelProperties(
                                      clip,
                                      opacity: value,
                                    ),
                                onTextAnimationChanged: (clip, value) =>
                                    _updateTextClipPanelProperties(
                                      clip,
                                      textAnimation: value,
                                    ),
                                onTextPresetSelected: _applyTextStylePreset,
                              ),
                            );

                            return _desktopLayout(
                              constraints,
                              library: _library(panelForMode),
                              preview: preview,
                              inspector: _inspector(
                                clipProperties,
                                panelForMode,
                              ),
                              timeline: timeline,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
