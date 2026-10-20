import 'ffmpeg_audio_export.dart';
import '../domain/models/cross_dissolve.dart';
import 'cross_dissolve_graph.dart';
import 'dart:math' as math;
import '../domain/models/clip.dart';
import '../domain/models/media_item.dart';
import '../domain/models/project.dart';
import '../domain/models/track.dart';
import '../domain/models/timeline_transition.dart';
import 'ffmpeg_service_models.dart';
import 'ffmpeg_service_segments.dart';
import 'ffmpeg_export_settings.dart';

/// Deterministic command construction. No filesystem, process or platform access.
/// Text-file inputs are returned to the executor, never written by the builder.
class FfmpegFiltergraphBuilder {
  FfmpegFiltergraphBuilder({required this.fontPath, this.pathSeparator = '/'});
  final String Function(String family) fontPath;
  final String pathSeparator;
  final Map<String, String> textFiles = {};
  String _join(String a, String b) => '$a$pathSeparator$b';
  FfmpegExportCommand buildExportCommand(
    TgiProject project,
    String outputPath, {
    FfmpegExportSettings settings = FfmpegExportSettings.defaultSettings,
    String? drawTextDirectoryPath,
  }) {
    textFiles.clear();
    final cuts = CrossDissolve.forProject(project);
    final withoutDissolves = project.copyWith(
      transitions: project.transitions
          .where((t) => !cuts.any((c) => c.transition.id == t.id))
          .toList(),
    );
    final command = _applyEditorExportOptions(
      CrossDissolveGraph.apply(
        _buildFullExportCommand(
          withoutDissolves,
          outputPath,
          settings: settings,
          drawTextDirectoryPath: drawTextDirectoryPath,
        ),
        cuts,
        settings.framesPerSecond,
      ),
      settings,
    );
    return settings.audioOnly ? FfmpegAudioExport.apply(command) : command;
  }

  FfmpegExportCommand _buildFullExportCommand(
    TgiProject project,
    String outputPath, {
    FfmpegExportSettings settings = FfmpegExportSettings.defaultSettings,
    String? drawTextDirectoryPath,
  }) {
    final segments = _buildExportSegments(project);
    final mediaById = {
      for (final mediaItem in project.mediaPool) mediaItem.id: mediaItem,
    };
    if (segments.isEmpty) {
      return _buildVideoLessExportCommand(
        project,
        outputPath,
        mediaById,
        settings,
        drawTextDirectoryPath: drawTextDirectoryPath,
      );
    }

    final totalDuration = segments.fold<Duration>(
      Duration.zero,
      (duration, segment) => duration + segment.duration,
    );
    final mediaSegmentInputCount = segments
        .where((segment) => !segment.isGap)
        .length;
    final baseVideoGroupIds = {
      for (final segment in segments)
        if (!segment.isGap && segment.timelineGroupId != null)
          segment.timelineGroupId!,
    };
    final standaloneAudioSegments = _buildStandaloneAudioSegments(
      project,
      mediaById,
      includePairedVideoAudio: false,
      excludedPairedVideoGroupIds: baseVideoGroupIds,
    );
    final exportWindows = [
      ExportWindow(
        timelineStart: Duration.zero,
        outputStart: Duration.zero,
        duration: totalDuration,
      ),
    ];
    final videoOverlays = _buildVideoOverlays(
      project,
      exportWindows,
      mediaById,
    );
    final overlays = _buildImageOverlays(project, exportWindows, mediaById);
    final transitionOverlays = _buildTransitionOverlays(project, exportWindows);
    final textOverlays = _buildTextOverlays(project, exportWindows);
    final outputWidth = settings.resolution.width;
    final outputHeight = settings.resolution.height;

    final filters = <String>[];
    final concatInputs = StringBuffer();
    var mediaInputIndex = 0;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (segment.isGap) {
        final segmentSeconds = _seconds(segment.duration);
        filters
          ..add(
            'color=c=black:s=${outputWidth}x$outputHeight:'
            'r=${settings.framesPerSecond}:d=$segmentSeconds,'
            'format=rgba,setsar=1[segv$index]',
          )
          ..add(_silentAudioFilter(index, segment.duration));
        concatInputs.write('[segv$index][a$index]');
        continue;
      }

      final inputIndex = mediaInputIndex++;
      filters
        ..add(
          _segmentVideoFilter(
            segment,
            index,
            inputIndex,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            coverOutputFrame:
                settings.resolution == FfmpegExportResolution.shorts1080,
          ),
        )
        ..add(_segmentAudioFilter(segment, index, inputIndex));
      concatInputs.write('[segv$index][a$index]');
    }
    filters.add(
      '${concatInputs}concat=n=${segments.length}:v=1:a=1[basev][basea]',
    );
    final totalSeconds = _seconds(totalDuration);
    final audioMap = standaloneAudioSegments.isEmpty ? '[basea]' : '[a]';
    if (standaloneAudioSegments.isNotEmpty) {
      filters
        ..add(
          _buildStandaloneAudioFilter(
            standaloneAudioSegments,
            totalDuration,
            firstInputIndex: mediaSegmentInputCount,
            outputLabel: 'extraa',
          ),
        )
        ..add(
          '[basea][extraa]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,'
          'atrim=duration=$totalSeconds,asetpts=PTS-STARTPTS[a]',
        );
    }
    filters.add(
      'color=c=black:s=${outputWidth}x$outputHeight:'
      'r=${settings.framesPerSecond}:d=$totalSeconds,format=rgba[canvas]',
    );
    var currentVideoLabel = 'canvas';
    void renderBase() {
      final windows = segments
          .where((segment) => !segment.isGap)
          .map(
            (segment) =>
                'gte(t,${_seconds(segment.timelineStart)})*lt(t,${_seconds(segment.timelineEnd)})',
          )
          .join('+');
      filters.add(
        '[$currentVideoLabel][basev]overlay=0:0:'
        "enable='$windows':eof_action=pass[composedbase]",
      );
      currentVideoLabel = 'composedbase';
    }

    final videoOverlayInputStart =
        mediaSegmentInputCount + standaloneAudioSegments.length;
    void renderVideo(int index) {
      final overlay = videoOverlays[index];
      final videoInputIndex = videoOverlayInputStart + index;
      final videoLabel = 'pipv$index';
      final rawVideoLabel = overlay.maskEnabled
          ? 'pipmaskbase$index'
          : videoLabel;
      final nextVideoLabel = 'vpip$index';
      final sourceStart = _seconds(overlay.sourceStart);
      final sourceDuration = _seconds(overlay.sourceDuration);
      final start = _seconds(overlay.outputStart);
      final end = _seconds(overlay.outputStart + overlay.duration);
      final overlayX = _normalizedOverlayOffset(
        _transformOverlayOffset(overlay.overlayX, overlay.transformOffsetX),
      );
      final overlayY = _normalizedOverlayOffset(
        _transformOverlayOffset(overlay.overlayY, overlay.transformOffsetY),
      );
      final overlayPosition = _overlayPositionExpression(
        enabled: overlay.kenBurnsEnabled,
        outputStart: overlay.outputStart,
        duration: overlay.duration,
        startX: overlay.startOverlayX,
        startY: overlay.startOverlayY,
        endX: _transformOverlayOffset(
          overlay.overlayX,
          overlay.transformOffsetX,
        ),
        endY: _transformOverlayOffset(
          overlay.overlayY,
          overlay.transformOffsetY,
        ),
        startFraction: overlay.kenBurnsStart,
        endFraction: overlay.kenBurnsEnd,
        fallbackX: overlayX,
        fallbackY: overlayY,
        keyframes: overlay.keyframes,
      );
      filters.add(
        <String>[
          '[$videoInputIndex:v]trim=start=$sourceStart:duration=$sourceDuration',
          ..._cropFilters(
            left: overlay.cropLeft,
            top: overlay.cropTop,
            right: overlay.cropRight,
            bottom: overlay.cropBottom,
            keyframes: overlay.keyframes,
            outputStart: overlay.outputStart,
            duration: overlay.duration,
          ),
          if (_hasOrientation(
            rotationDegrees: overlay.rotationDegrees,
            flipHorizontal: overlay.flipHorizontal,
            flipVertical: overlay.flipVertical,
          ))
            'format=rgba',
          ..._orientationFilters(
            rotationDegrees: overlay.rotationDegrees,
            flipHorizontal: overlay.flipHorizontal,
            flipVertical: overlay.flipVertical,
          ),
          if (overlay.reverseVideo) 'reverse',
          _videoSetPtsFilterWithOffset(
            overlay.playbackSpeed,
            overlay.outputStart,
          ),
          ..._chromaKeyFilters(
            enabled: overlay.chromaKeyEnabled,
            color: overlay.chromaKeyColor,
            similarity: overlay.chromaKeySimilarity,
            blend: overlay.chromaKeyBlend,
          ),
          ..._videoLookFiltersFor(
            brightness: overlay.brightness,
            contrast: overlay.contrast,
            saturation: overlay.saturation,
            exposure: overlay.exposure,
            hue: overlay.hue,
            temperature: overlay.temperature,
            tint: overlay.tint,
            shadows: overlay.shadows,
            highlights: overlay.highlights,
            curveShadows: overlay.curveShadows,
            curveMidtones: overlay.curveMidtones,
            curveHighlights: overlay.curveHighlights,
            filterPreset: overlay.filterPreset,
            keyframes: overlay.keyframes,
            outputStart: overlay.outputStart,
            duration: overlay.duration,
          ),
          _videoOverlayScaleFilter(
            overlay,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
          ),
          ..._videoFadeFilters(
            alpha: true,
            outputStart: overlay.outputStart,
            fadeIn: overlay.fadeIn,
            fadeOut: overlay.fadeOut,
            duration: overlay.duration,
          ),
          ..._opacityFilters(
            opacity: overlay.opacity,
            keyframes: overlay.keyframes,
            outputStart: overlay.outputStart,
            duration: overlay.duration,
          ),
          'format=rgba[$rawVideoLabel]',
        ].join(','),
      );
      if (overlay.maskEnabled) {
        filters.addAll(
          _videoMaskGraph(
            baseLabel: rawVideoLabel,
            outputLabel: videoLabel,
            labelPrefix: 'pipmask$index',
            shape: overlay.maskShape,
            effect: overlay.maskEffect,
            x: overlay.maskX,
            y: overlay.maskY,
            width: overlay.maskWidth,
            height: overlay.maskHeight,
            feather: overlay.maskFeather,
            intensity: overlay.maskIntensity,
            inverted: overlay.maskInverted,
            keyframes: overlay.keyframes,
            outputStart: overlay.outputStart,
            duration: overlay.duration,
          ),
        );
      }
      filters.add(
        '[$currentVideoLabel][$videoLabel]overlay='
        '$overlayPosition:'
        "enable='between(t,$start,$end)':"
        'eof_action=pass[$nextVideoLabel]',
      );
      currentVideoLabel = nextVideoLabel;
    }

    void renderImage(int index) {
      final overlay = overlays[index];
      final imageInputIndex =
          videoOverlayInputStart + videoOverlays.length + index;
      final imageLabel = 'ov$index';
      final nextVideoLabel = 'vov$index';
      final start = _seconds(overlay.outputStart);
      final end = _seconds(overlay.outputStart + overlay.duration);
      final overlayX = _normalizedOverlayOffset(
        _transformOverlayOffset(overlay.overlayX, overlay.transformOffsetX),
      );
      final overlayY = _normalizedOverlayOffset(
        _transformOverlayOffset(overlay.overlayY, overlay.transformOffsetY),
      );
      final overlayFilter = _imageOverlayFilter(
        overlay,
        outputWidth: outputWidth,
        outputHeight: outputHeight,
      );
      final overlayPosition =
          overlay.imageFit == ImageClipFit.cover &&
              overlay.transformOffsetX.abs() < 0.000001 &&
              overlay.transformOffsetY.abs() < 0.000001 &&
              (overlay.transformScale - 1).abs() < 0.000001 &&
              overlay.rotationDegrees.abs() < 0.000001
          ? 'x=0:y=0'
          : _overlayPositionExpression(
              enabled: overlay.kenBurnsEnabled,
              outputStart: overlay.outputStart,
              duration: overlay.duration,
              startX: overlay.startOverlayX,
              startY: overlay.startOverlayY,
              endX: _transformOverlayOffset(
                overlay.overlayX,
                overlay.transformOffsetX,
              ),
              endY: _transformOverlayOffset(
                overlay.overlayY,
                overlay.transformOffsetY,
              ),
              startFraction: overlay.kenBurnsStart,
              endFraction: overlay.kenBurnsEnd,
              fallbackX: overlayX,
              fallbackY: overlayY,
              keyframes: overlay.keyframes,
              centered: overlay.imageFit == ImageClipFit.trackedOverlay,
            );
      filters
        ..add('[$imageInputIndex:v]$overlayFilter,format=rgba[$imageLabel]')
        ..add(
          '[$currentVideoLabel][$imageLabel]overlay='
          "$overlayPosition:enable='between(t,$start,$end)':"
          'eof_action=pass[$nextVideoLabel]',
        );
      currentVideoLabel = nextVideoLabel;
    }

    var transitionInputOffset = 0;
    void renderTransition(int index) {
      final transition = transitionOverlays[index];
      final transitionLabel = 'tr$index';
      final nextVideoLabel = 'vtr$index';
      final outputStart = _seconds(transition.outputStart);
      final outputEnd = _seconds(transition.outputStart + transition.duration);
      if (transition.preset != null) {
        filters.add(
          _presetTransitionFilter(
            baseLabel: currentVideoLabel,
            outputLabel: nextVideoLabel,
            transition: transition,
            startSeconds: outputStart,
            endSeconds: outputEnd,
          ),
        );
      } else {
        final transitionInputIndex =
            mediaSegmentInputCount +
            standaloneAudioSegments.length +
            videoOverlays.length +
            overlays.length +
            transitionInputOffset++;
        final sourceStart = _seconds(transition.sourceStart);
        final durationSeconds = _seconds(transition.duration);
        filters
          ..add(
            '[$transitionInputIndex:v]trim=start=$sourceStart:duration=$durationSeconds,'
            'setpts=PTS-STARTPTS+$outputStart/TB,'
            'scale=$outputWidth:$outputHeight:force_original_aspect_ratio=increase,'
            'crop=$outputWidth:$outputHeight,format=rgba[$transitionLabel]',
          )
          ..add(
            _transitionOverlayFilter(
              baseLabel: currentVideoLabel,
              transitionLabel: transitionLabel,
              outputLabel: nextVideoLabel,
              startSeconds: outputStart,
              endSeconds: outputEnd,
              blendMode: transition.blendMode,
            ),
          );
      }
      currentVideoLabel = nextVideoLabel;
    }

    void renderText(int index) {
      final overlay = textOverlays[index];
      final nextVideoLabel = 'vtxt$index';
      final start = _seconds(overlay.outputStart);
      final end = _seconds(overlay.outputStart + overlay.duration);
      final overlayX = _normalizedOverlayOffset(overlay.overlayX);
      final overlayY = _normalizedOverlayOffset(overlay.overlayY);
      final fontSize = _textFontSizePixels(
        overlay.fontSize,
        outputWidth,
        outputHeight,
      );
      final wrappedText = _wrapTextForExport(
        overlay.text,
        outputWidth: outputWidth,
        fontSizePixels: fontSize,
      );
      final textSource = _drawTextSource(
        wrappedText,
        index: index,
        directoryPath: drawTextDirectoryPath,
      );
      final textScale = _textScaleForOutput(outputWidth, outputHeight);
      final alphaExpression = _drawTextAlphaExpression(overlay, start);
      final xExpression = _drawTextXExpression(
        overlay,
        overlayX,
        start,
        slideDistancePixels: 90 * textScale,
      );
      final yExpression = _drawTextYExpression(
        overlay,
        overlayY,
        start,
        riseDistancePixels: 28 * textScale,
      );
      final fontSizeExpression = _drawTextFontSizeExpression(
        overlay,
        fontSize,
        start,
      );
      final textOpacity =
          _hasKeyframesFor(overlay.keyframes, ClipKeyframeProperty.opacity)
          ? 1.0
          : overlay.opacity;
      filters.add(
        '[$currentVideoLabel]drawtext='
        'fontfile=${_drawTextFontFile(overlay.fontFamily)}:'
        '$textSource:'
        'expansion=none:'
        'fontcolor=${_drawTextColor(overlay.textColor, textOpacity)}:'
        'fontsize=$fontSizeExpression:'
        'text_align=center:'
        'box=1:'
        'boxcolor=${_drawTextColor(overlay.backgroundColor, textOpacity)}:'
        'boxborderw=${_textBoxBorderPixels(outputWidth, outputHeight)}:'
        'shadowcolor=${_drawTextColor(0xB3000000, textOpacity)}:'
        'shadowx=${_textShadowOffsetPixels(outputWidth, outputHeight)}:'
        'shadowy=${_textShadowOffsetPixels(outputWidth, outputHeight)}:'
        "${alphaExpression == null ? '' : "alpha='$alphaExpression':"}"
        "x='$xExpression':y='$yExpression':"
        "enable='between(t,$start,$end)'[$nextVideoLabel]",
      );
      currentVideoLabel = nextVideoLabel;
    }

    final passes =
        <({int order, int sequence, void Function() render})>[
          (
            order:
                project.layerOrderByClipId[project.baseVideoTrack!.clips
                    .firstWhere((clip) => clip.trackType == TrackType.video)
                    .id] ??
                0,
            sequence: 0,
            render: renderBase,
          ),
          for (var index = 0; index < videoOverlays.length; index++)
            (
              order: videoOverlays[index].zOrder,
              sequence: index + 1,
              render: () => renderVideo(index),
            ),
          for (var index = 0; index < overlays.length; index++)
            (
              order: overlays[index].zOrder,
              sequence: index + 100000,
              render: () => renderImage(index),
            ),
          for (var index = 0; index < textOverlays.length; index++)
            (
              order: textOverlays[index].zOrder,
              sequence: index + 200000,
              render: () => renderText(index),
            ),
        ]..sort((a, b) {
          final layer = a.order.compareTo(b.order);
          return layer != 0 ? layer : a.sequence.compareTo(b.sequence);
        });
    for (final pass in passes) {
      pass.render();
    }
    // Existing timeline transitions are global effects, above visual layers.
    for (var index = 0; index < transitionOverlays.length; index++) {
      renderTransition(index);
    }

    currentVideoLabel = _appendWatermarkFilter(
      filters,
      project.watermark,
      currentVideoLabel,
      inputIndex:
          mediaSegmentInputCount +
          standaloneAudioSegments.length +
          videoOverlays.length +
          overlays.length +
          transitionOverlays
              .where((transition) => transition.preset == null)
              .length,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
    );

    filters.add('[$currentVideoLabel]fps=fps=${settings.framesPerSecond}[v]');

    const videoMap = '[v]';
    final arguments = <String>[
      '-y',
      '-hide_banner',
      '-nostdin',
      for (final segment in segments)
        if (!segment.isGap) ...['-i', segment.filePath!],
      for (final segment in standaloneAudioSegments) ...[
        '-i',
        segment.filePath,
      ],
      for (final overlay in videoOverlays) ...['-i', overlay.filePath],
      for (final overlay in overlays) ...[
        '-loop',
        '1',
        '-t',
        totalSeconds,
        '-i',
        overlay.filePath,
      ],
      for (final transition in transitionOverlays)
        if (transition.preset == null) ...['-i', transition.filePath],
      if (_watermarkIsExportable(project.watermark)) ...[
        '-loop',
        '1',
        '-t',
        totalSeconds,
        '-i',
        project.watermark.imagePath,
      ],
      '-filter_complex',
      filters.join(';'),
      '-map',
      videoMap,
      '-map',
      audioMap,
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-preset',
      settings.quality.encoderPreset,
      '-crf',
      settings.quality.crf.toString(),
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      outputPath,
    ];

    return FfmpegExportCommand(
      arguments: arguments,
      totalDuration: totalDuration,
      textFiles: Map.unmodifiable(textFiles),
      clipCount: mediaSegmentInputCount + videoOverlays.length,
    );
  }

  FfmpegExportCommand _buildVideoLessExportCommand(
    TgiProject project,
    String outputPath,
    Map<String, MediaItem> mediaById,
    FfmpegExportSettings settings, {
    String? drawTextDirectoryPath,
  }) {
    final totalDuration = _videoLessExportDuration(project);
    if (totalDuration <= Duration.zero) {
      throw const FfmpegProcessException(
        'A timeline nao tem conteudo exportavel.',
      );
    }

    final audioSegments = _buildStandaloneAudioSegments(project, mediaById);
    final exportWindows = [
      ExportWindow(
        timelineStart: Duration.zero,
        outputStart: Duration.zero,
        duration: totalDuration,
      ),
    ];
    final overlays = _buildImageOverlays(project, exportWindows, mediaById);
    final transitionOverlays = _buildTransitionOverlays(project, exportWindows);
    final textOverlays = _buildTextOverlays(project, exportWindows);
    final outputWidth = settings.resolution.width;
    final outputHeight = settings.resolution.height;
    final totalSeconds = _seconds(totalDuration);

    final filters = <String>['[0:v]setsar=1[basev]'];
    var currentVideoLabel = 'basev';
    void renderImage(int index) {
      final overlay = overlays[index];
      final imageInputIndex = 1 + audioSegments.length + index;
      final imageLabel = 'ov$index';
      final nextVideoLabel = 'vov$index';
      final start = _seconds(overlay.outputStart);
      final end = _seconds(overlay.outputStart + overlay.duration);
      final overlayX = _normalizedOverlayOffset(overlay.overlayX);
      final overlayY = _normalizedOverlayOffset(overlay.overlayY);
      final overlayFilter = _imageOverlayFilter(
        overlay,
        outputWidth: outputWidth,
        outputHeight: outputHeight,
      );
      final overlayPosition = overlay.imageFit == ImageClipFit.cover
          ? 'x=0:y=0'
          : _overlayPositionExpression(
              enabled: overlay.kenBurnsEnabled,
              outputStart: overlay.outputStart,
              duration: overlay.duration,
              startX: overlay.startOverlayX,
              startY: overlay.startOverlayY,
              endX: overlay.overlayX,
              endY: overlay.overlayY,
              startFraction: overlay.kenBurnsStart,
              endFraction: overlay.kenBurnsEnd,
              fallbackX: overlayX,
              fallbackY: overlayY,
              keyframes: overlay.keyframes,
              centered: overlay.imageFit == ImageClipFit.trackedOverlay,
            );
      filters
        ..add('[$imageInputIndex:v]$overlayFilter,format=rgba[$imageLabel]')
        ..add(
          '[$currentVideoLabel][$imageLabel]overlay='
          "$overlayPosition:enable='between(t,$start,$end)':"
          'eof_action=pass[$nextVideoLabel]',
        );
      currentVideoLabel = nextVideoLabel;
    }

    var transitionInputOffset = 0;
    void renderTransition(int index) {
      final transition = transitionOverlays[index];
      final transitionLabel = 'tr$index';
      final nextVideoLabel = 'vtr$index';
      final outputStart = _seconds(transition.outputStart);
      final outputEnd = _seconds(transition.outputStart + transition.duration);
      if (transition.preset != null) {
        filters.add(
          _presetTransitionFilter(
            baseLabel: currentVideoLabel,
            outputLabel: nextVideoLabel,
            transition: transition,
            startSeconds: outputStart,
            endSeconds: outputEnd,
          ),
        );
      } else {
        final transitionInputIndex =
            1 +
            audioSegments.length +
            overlays.length +
            transitionInputOffset++;
        final sourceStart = _seconds(transition.sourceStart);
        final durationSeconds = _seconds(transition.duration);
        filters
          ..add(
            '[$transitionInputIndex:v]trim=start=$sourceStart:duration=$durationSeconds,'
            'setpts=PTS-STARTPTS+$outputStart/TB,'
            'scale=$outputWidth:$outputHeight:force_original_aspect_ratio=increase,'
            'crop=$outputWidth:$outputHeight,format=rgba[$transitionLabel]',
          )
          ..add(
            _transitionOverlayFilter(
              baseLabel: currentVideoLabel,
              transitionLabel: transitionLabel,
              outputLabel: nextVideoLabel,
              startSeconds: outputStart,
              endSeconds: outputEnd,
              blendMode: transition.blendMode,
            ),
          );
      }
      currentVideoLabel = nextVideoLabel;
    }

    void renderText(int index) {
      final overlay = textOverlays[index];
      final nextVideoLabel = 'vtxt$index';
      final start = _seconds(overlay.outputStart);
      final end = _seconds(overlay.outputStart + overlay.duration);
      final overlayX = _normalizedOverlayOffset(overlay.overlayX);
      final overlayY = _normalizedOverlayOffset(overlay.overlayY);
      final fontSize = _textFontSizePixels(
        overlay.fontSize,
        outputWidth,
        outputHeight,
      );
      final wrappedText = _wrapTextForExport(
        overlay.text,
        outputWidth: outputWidth,
        fontSizePixels: fontSize,
      );
      final textSource = _drawTextSource(
        wrappedText,
        index: index,
        directoryPath: drawTextDirectoryPath,
      );
      final textScale = _textScaleForOutput(outputWidth, outputHeight);
      final alphaExpression = _drawTextAlphaExpression(overlay, start);
      final xExpression = _drawTextXExpression(
        overlay,
        overlayX,
        start,
        slideDistancePixels: 90 * textScale,
      );
      final yExpression = _drawTextYExpression(
        overlay,
        overlayY,
        start,
        riseDistancePixels: 28 * textScale,
      );
      final fontSizeExpression = _drawTextFontSizeExpression(
        overlay,
        fontSize,
        start,
      );
      final textOpacity =
          _hasKeyframesFor(overlay.keyframes, ClipKeyframeProperty.opacity)
          ? 1.0
          : overlay.opacity;
      filters.add(
        '[$currentVideoLabel]drawtext='
        'fontfile=${_drawTextFontFile(overlay.fontFamily)}:'
        '$textSource:'
        'expansion=none:'
        'fontcolor=${_drawTextColor(overlay.textColor, textOpacity)}:'
        'fontsize=$fontSizeExpression:'
        'text_align=center:'
        'box=1:'
        'boxcolor=${_drawTextColor(overlay.backgroundColor, textOpacity)}:'
        'boxborderw=${_textBoxBorderPixels(outputWidth, outputHeight)}:'
        'shadowcolor=${_drawTextColor(0xB3000000, textOpacity)}:'
        'shadowx=${_textShadowOffsetPixels(outputWidth, outputHeight)}:'
        'shadowy=${_textShadowOffsetPixels(outputWidth, outputHeight)}:'
        "${alphaExpression == null ? '' : "alpha='$alphaExpression':"}"
        "x='$xExpression':y='$yExpression':"
        "enable='between(t,$start,$end)'[$nextVideoLabel]",
      );
      currentVideoLabel = nextVideoLabel;
    }

    final passes =
        <({int order, int sequence, void Function() render})>[
          for (var index = 0; index < overlays.length; index++)
            (
              order: overlays[index].zOrder,
              sequence: index + 100000,
              render: () => renderImage(index),
            ),
          for (var index = 0; index < textOverlays.length; index++)
            (
              order: textOverlays[index].zOrder,
              sequence: index + 200000,
              render: () => renderText(index),
            ),
        ]..sort((a, b) {
          final layer = a.order.compareTo(b.order);
          return layer != 0 ? layer : a.sequence.compareTo(b.sequence);
        });
    for (final pass in passes) {
      pass.render();
    }
    // Existing timeline transitions are global effects, above visual layers.
    for (var index = 0; index < transitionOverlays.length; index++) {
      renderTransition(index);
    }

    currentVideoLabel = _appendWatermarkFilter(
      filters,
      project.watermark,
      currentVideoLabel,
      inputIndex:
          1 +
          audioSegments.length +
          overlays.length +
          transitionOverlays
              .where((transition) => transition.preset == null)
              .length,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
    );

    filters
      ..add('[$currentVideoLabel]fps=fps=${settings.framesPerSecond}[v]')
      ..add(_buildStandaloneAudioFilter(audioSegments, totalDuration));

    final arguments = <String>[
      '-y',
      '-hide_banner',
      '-nostdin',
      '-f',
      'lavfi',
      '-t',
      totalSeconds,
      '-i',
      'color=c=black:s=${outputWidth}x$outputHeight:r=${settings.framesPerSecond}:d=$totalSeconds',
      for (final segment in audioSegments) ...['-i', segment.filePath],
      for (final overlay in overlays) ...[
        '-loop',
        '1',
        '-t',
        totalSeconds,
        '-i',
        overlay.filePath,
      ],
      for (final transition in transitionOverlays)
        if (transition.preset == null) ...['-i', transition.filePath],
      if (_watermarkIsExportable(project.watermark)) ...[
        '-loop',
        '1',
        '-t',
        totalSeconds,
        '-i',
        project.watermark.imagePath,
      ],
      '-filter_complex',
      filters.join(';'),
      '-map',
      '[v]',
      '-map',
      '[a]',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-preset',
      settings.quality.encoderPreset,
      '-crf',
      settings.quality.crf.toString(),
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      outputPath,
    ];

    return FfmpegExportCommand(
      arguments: arguments,
      totalDuration: totalDuration,
      textFiles: Map.unmodifiable(textFiles),
      clipCount: 0,
    );
  }

  List<ExportSegment> _buildExportSegments(TgiProject project) {
    final mediaById = {
      for (final mediaItem in project.mediaPool) mediaItem.id: mediaItem,
    };
    final audioClipsByGroup = <String, Clip>{};
    final audioTrackVolumeByGroup = <String, double>{};
    final hasSoloAudioTrack = project.tracks.any(
      (track) =>
          track.type == TrackType.audio && track.isSolo && !track.isHidden,
    );
    for (final track in project.tracks) {
      if (track.type != TrackType.audio ||
          track.isHidden ||
          track.isMuted ||
          (hasSoloAudioTrack && !track.isSolo)) {
        continue;
      }
      for (final clip in track.clips) {
        audioClipsByGroup.putIfAbsent(clip.timelineGroupId, () => clip);
        audioTrackVolumeByGroup.putIfAbsent(
          clip.timelineGroupId,
          () => track.volume,
        );
      }
    }

    final mainVideoTrack = _mainVideoTrackForExport(project);
    final videoClips = mainVideoTrack == null
        ? <Clip>[]
        : mainVideoTrack.clips
              .where(
                (clip) =>
                    clip.trackType == TrackType.video &&
                    clip.duration > Duration.zero,
              )
              .toList();
    videoClips.sort(_compareClipsByTimeline);
    for (var index = 1; index < videoClips.length; index++) {
      if (videoClips[index].timelineStart < videoClips[index - 1].timelineEnd) {
        throw FfmpegProcessException(
          'Há vídeos sobrepostos na mesma pista (${mainVideoTrack!.name}). '
          'Mova um dos clipes para outra camada visual antes de exportar.',
        );
      }
    }
    if (videoClips.isEmpty) {
      return const [];
    }

    final exportDuration = _videoExportDuration(project);
    final segments = <ExportSegment>[];
    var outputStart = Duration.zero;

    void addGap(Duration timelineStart, Duration duration) {
      if (duration <= Duration.zero) {
        return;
      }
      segments.add(
        ExportSegment.gap(
          timelineStart: timelineStart,
          outputStart: outputStart,
          duration: duration,
        ),
      );
      outputStart += duration;
    }

    for (final videoClip in videoClips) {
      if (videoClip.timelineStart > outputStart) {
        addGap(outputStart, videoClip.timelineStart - outputStart);
      }

      final mediaItem = mediaById[videoClip.mediaItemId];
      if (mediaItem == null) {
        throw FfmpegProcessException(
          'Midia ausente para o clipe ${videoClip.id}.',
        );
      }

      final audioClip = audioClipsByGroup[videoClip.timelineGroupId];
      if (audioClip != null && audioClip.mediaItemId != videoClip.mediaItemId) {
        throw FfmpegProcessException(
          'O audio do clipe ${videoClip.id} aponta para outra midia.',
        );
      }
      if (audioClip != null && audioClip.duration != videoClip.duration) {
        throw FfmpegProcessException(
          'O audio do clipe ${videoClip.id} esta fora de sincronia.',
        );
      }

      segments.add(
        ExportSegment(
          filePath: mediaItem.filePath,
          timelineGroupId: videoClip.timelineGroupId,
          timelineStart: videoClip.timelineStart,
          outputStart: outputStart,
          videoSourceStart: videoClip.sourceStart,
          audioSourceStart: audioClip?.sourceStart ?? Duration.zero,
          videoSourceDuration: videoClip.effectiveSourceDuration,
          audioSourceDuration:
              audioClip?.effectiveSourceDuration ?? Duration.zero,
          duration: videoClip.duration,
          playbackSpeed: videoClip.playbackSpeed,
          volume:
              (audioClip?.volume ?? 0) *
              (audioTrackVolumeByGroup[videoClip.timelineGroupId] ?? 1),
          audioNoiseReductionDb: audioClip?.audioNoiseReductionDb ?? 0,
          hasSourceAudio: audioClip != null && mediaItem.hasAudio,
          videoFadeIn: videoClip.fadeIn,
          videoFadeOut: videoClip.fadeOut,
          audioFadeIn: audioClip?.fadeIn ?? Duration.zero,
          audioFadeOut: audioClip?.fadeOut ?? Duration.zero,
          brightness: videoClip.brightness,
          contrast: videoClip.contrast,
          saturation: videoClip.saturation,
          exposure: videoClip.exposure,
          hue: videoClip.hue,
          temperature: videoClip.temperature,
          tint: videoClip.tint,
          shadows: videoClip.shadows,
          highlights: videoClip.highlights,
          curveShadows: videoClip.curveShadows,
          curveMidtones: videoClip.curveMidtones,
          curveHighlights: videoClip.curveHighlights,
          filterPreset: videoClip.filterPreset,
          reverseVideo: videoClip.reverseVideo,
          overlayX: videoClip.overlayX,
          overlayY: videoClip.overlayY,
          overlayScale: videoClip.overlayScale,
          opacity: videoClip.opacity,
          startOverlayX: videoClip.startOverlayX,
          startOverlayY: videoClip.startOverlayY,
          startOverlayScale: videoClip.startOverlayScale,
          kenBurnsEnabled: videoClip.kenBurnsEnabled,
          kenBurnsStart: videoClip.kenBurnsStart,
          kenBurnsEnd: videoClip.kenBurnsEnd,
          chromaKeyEnabled: videoClip.chromaKeyEnabled,
          chromaKeyColor: videoClip.chromaKeyColor,
          chromaKeySimilarity: videoClip.chromaKeySimilarity,
          chromaKeyBlend: videoClip.chromaKeyBlend,
          maskEnabled: videoClip.maskEnabled,
          maskShape: videoClip.maskShape,
          maskEffect: videoClip.maskEffect,
          maskX: videoClip.maskX,
          maskY: videoClip.maskY,
          maskWidth: videoClip.maskWidth,
          maskHeight: videoClip.maskHeight,
          maskFeather: videoClip.maskFeather,
          maskIntensity: videoClip.maskIntensity,
          maskInverted: videoClip.maskInverted,
          cropLeft: videoClip.cropLeft,
          cropTop: videoClip.cropTop,
          cropRight: videoClip.cropRight,
          cropBottom: videoClip.cropBottom,
          transformOffsetX: videoClip.transformOffsetX,
          transformOffsetY: videoClip.transformOffsetY,
          transformScale: videoClip.transformScale,
          rotationDegrees: videoClip.rotationDegrees,
          flipHorizontal: videoClip.flipHorizontal,
          flipVertical: videoClip.flipVertical,
          videoKeyframes: videoClip.keyframes,
          audioKeyframes: audioClip?.keyframes ?? const [],
        ),
      );
      outputStart += videoClip.duration;
    }

    if (exportDuration > outputStart) {
      addGap(outputStart, exportDuration - outputStart);
    }
    return segments;
  }

  Track? _mainVideoTrackForExport(TgiProject project) => project.baseVideoTrack;

  Duration _videoExportDuration(TgiProject project) {
    final hasSoloAudioTrack = project.tracks.any(
      (track) =>
          track.type == TrackType.audio && track.isSolo && !track.isHidden,
    );
    var duration = Duration.zero;
    for (final track in project.tracks) {
      if (track.isHidden) {
        continue;
      }
      if (track.type == TrackType.audio &&
          (track.isMuted || (hasSoloAudioTrack && !track.isSolo))) {
        continue;
      }
      for (final clip in track.clips) {
        if (clip.duration <= Duration.zero) {
          continue;
        }
        if (clip.trackType == TrackType.text &&
            clip.textContent.trim().isEmpty) {
          continue;
        }
        if (clip.timelineEnd > duration) {
          duration = clip.timelineEnd;
        }
      }
    }
    return duration;
  }

  List<VideoOverlaySegment> _buildVideoOverlays(
    TgiProject project,
    List<ExportWindow> segments,
    Map<String, MediaItem> mediaById,
  ) {
    final mainVideoTrack = _mainVideoTrackForExport(project);
    if (mainVideoTrack == null) {
      return const [];
    }

    final overlays = <VideoOverlaySegment>[];
    for (final track in project.tracks.reversed) {
      if (track.kind != TrackKind.visual ||
          track.isHidden ||
          track.id == mainVideoTrack.id) {
        continue;
      }
      final trackVideoClips =
          track.clips
              .where(
                (clip) =>
                    clip.trackType == TrackType.video &&
                    clip.duration > Duration.zero,
              )
              .toList()
            ..sort(_compareClipsByTimeline);

      for (final videoClip in trackVideoClips) {
        final mediaItem = mediaById[videoClip.mediaItemId];
        if (mediaItem == null) {
          throw FfmpegProcessException(
            'Midia ausente para o clipe PIP ${videoClip.id}.',
          );
        }
        if (mediaItem.type != MediaType.video) {
          throw FfmpegProcessException(
            'O clipe PIP ${videoClip.id} nao aponta para um video.',
          );
        }

        for (final segment in segments) {
          final overlapStart = _maxDuration(
            videoClip.timelineStart,
            segment.timelineStart,
          );
          final overlapEnd = _minDuration(
            videoClip.timelineEnd,
            segment.timelineEnd,
          );
          if (overlapEnd <= overlapStart) {
            continue;
          }

          final overlapDuration = overlapEnd - overlapStart;
          final sourceOffset = _sourceDurationForTimeline(
            overlapStart - videoClip.timelineStart,
            videoClip.playbackSpeed,
          );
          final sourceDuration = _minDuration(
            _sourceDurationForTimeline(
              overlapDuration,
              videoClip.playbackSpeed,
            ),
            videoClip.effectiveSourceDuration,
          );
          if (sourceDuration <= Duration.zero) {
            continue;
          }
          final maxSourceStart = videoClip.sourceEnd - sourceDuration;
          final sourceStart = _clampDuration(
            videoClip.reverseVideo
                ? videoClip.sourceEnd - sourceOffset - sourceDuration
                : videoClip.sourceStart + sourceOffset,
            videoClip.sourceStart,
            maxSourceStart < videoClip.sourceStart
                ? videoClip.sourceStart
                : maxSourceStart,
          );

          overlays.add(
            VideoOverlaySegment(
              zOrder: project.layerOrderByClipId[videoClip.id] ?? 0,
              fadeIn: videoClip.fadeIn,
              fadeOut: videoClip.fadeOut,
              filePath: mediaItem.filePath,
              outputStart:
                  segment.outputStart + (overlapStart - segment.timelineStart),
              sourceStart: sourceStart,
              sourceDuration: sourceDuration,
              duration: overlapDuration,
              playbackSpeed: videoClip.playbackSpeed,
              overlayX: videoClip.overlayX,
              overlayY: videoClip.overlayY,
              overlayScale: videoClip.overlayScale,
              opacity: videoClip.opacity,
              brightness: videoClip.brightness,
              contrast: videoClip.contrast,
              saturation: videoClip.saturation,
              exposure: videoClip.exposure,
              hue: videoClip.hue,
              temperature: videoClip.temperature,
              tint: videoClip.tint,
              shadows: videoClip.shadows,
              highlights: videoClip.highlights,
              curveShadows: videoClip.curveShadows,
              curveMidtones: videoClip.curveMidtones,
              curveHighlights: videoClip.curveHighlights,
              filterPreset: videoClip.filterPreset,
              reverseVideo: videoClip.reverseVideo,
              chromaKeyEnabled: videoClip.chromaKeyEnabled,
              chromaKeyColor: videoClip.chromaKeyColor,
              chromaKeySimilarity: videoClip.chromaKeySimilarity,
              chromaKeyBlend: videoClip.chromaKeyBlend,
              maskEnabled: videoClip.maskEnabled,
              maskShape: videoClip.maskShape,
              maskEffect: videoClip.maskEffect,
              maskX: videoClip.maskX,
              maskY: videoClip.maskY,
              maskWidth: videoClip.maskWidth,
              maskHeight: videoClip.maskHeight,
              maskFeather: videoClip.maskFeather,
              maskIntensity: videoClip.maskIntensity,
              maskInverted: videoClip.maskInverted,
              cropLeft: videoClip.cropLeft,
              cropTop: videoClip.cropTop,
              cropRight: videoClip.cropRight,
              cropBottom: videoClip.cropBottom,
              transformOffsetX: videoClip.transformOffsetX,
              transformOffsetY: videoClip.transformOffsetY,
              transformScale: videoClip.transformScale,
              rotationDegrees: videoClip.rotationDegrees,
              flipHorizontal: videoClip.flipHorizontal,
              flipVertical: videoClip.flipVertical,
              startOverlayX: videoClip.startOverlayX,
              startOverlayY: videoClip.startOverlayY,
              startOverlayScale: videoClip.startOverlayScale,
              kenBurnsEnabled: videoClip.kenBurnsEnabled,
              kenBurnsStart: videoClip.kenBurnsStart,
              kenBurnsEnd: videoClip.kenBurnsEnd,
              keyframes: videoClip.keyframes,
            ),
          );
        }
      }
    }
    return overlays;
  }

  List<ImageOverlaySegment> _buildImageOverlays(
    TgiProject project,
    List<ExportWindow> segments,
    Map<String, MediaItem> mediaById,
  ) {
    final imageClips = <Clip>[];
    for (final track in project.tracks.reversed) {
      if (track.kind != TrackKind.visual || track.isHidden) {
        continue;
      }
      final trackImageClips =
          track.clips
              .where(
                (clip) =>
                    clip.trackType == TrackType.image &&
                    clip.duration > Duration.zero,
              )
              .toList()
            ..sort(_compareClipsByTimeline);
      imageClips.addAll(trackImageClips);
    }

    final overlays = <ImageOverlaySegment>[];
    for (final imageClip in imageClips) {
      final mediaItem = mediaById[imageClip.mediaItemId];
      if (mediaItem == null) {
        throw FfmpegProcessException(
          'Midia ausente para a imagem ${imageClip.id}.',
        );
      }
      if (mediaItem.type != MediaType.image) {
        throw FfmpegProcessException(
          'O clipe ${imageClip.id} nao aponta para uma imagem.',
        );
      }

      for (final segment in segments) {
        final overlapStart = _maxDuration(
          imageClip.timelineStart,
          segment.timelineStart,
        );
        final overlapEnd = _minDuration(
          imageClip.timelineEnd,
          segment.timelineEnd,
        );
        if (overlapEnd <= overlapStart) {
          continue;
        }

        overlays.add(
          ImageOverlaySegment(
            zOrder: project.layerOrderByClipId[imageClip.id] ?? 0,
            filePath: mediaItem.filePath,
            outputStart:
                segment.outputStart + (overlapStart - segment.timelineStart),
            duration: overlapEnd - overlapStart,
            overlayX: imageClip.overlayX,
            overlayY: imageClip.overlayY,
            overlayScale: imageClip.overlayScale,
            opacity: imageClip.opacity,
            fadeIn: imageClip.fadeIn,
            fadeOut: imageClip.fadeOut,
            imageFit: imageClip.imageFit,
            cropLeft: imageClip.cropLeft,
            cropTop: imageClip.cropTop,
            cropRight: imageClip.cropRight,
            cropBottom: imageClip.cropBottom,
            transformOffsetX: imageClip.transformOffsetX,
            transformOffsetY: imageClip.transformOffsetY,
            transformScale: imageClip.transformScale,
            rotationDegrees: imageClip.rotationDegrees,
            flipHorizontal: imageClip.flipHorizontal,
            flipVertical: imageClip.flipVertical,
            startOverlayX: imageClip.startOverlayX,
            startOverlayY: imageClip.startOverlayY,
            startOverlayScale: imageClip.startOverlayScale,
            kenBurnsEnabled: imageClip.kenBurnsEnabled,
            kenBurnsStart: imageClip.kenBurnsStart,
            kenBurnsEnd: imageClip.kenBurnsEnd,
            keyframes: imageClip.keyframes,
          ),
        );
      }
    }
    return overlays;
  }

  List<TextOverlaySegment> _buildTextOverlays(
    TgiProject project,
    List<ExportWindow> segments,
  ) {
    final textClips = <Clip>[];
    for (final track in project.tracks.reversed) {
      if (track.kind != TrackKind.visual || track.isHidden) {
        continue;
      }
      final trackTextClips =
          track.clips
              .where(
                (clip) =>
                    clip.trackType == TrackType.text &&
                    clip.duration > Duration.zero &&
                    clip.textContent.trim().isNotEmpty,
              )
              .toList()
            ..sort(_compareClipsByTimeline);
      textClips.addAll(trackTextClips);
    }

    final overlays = <TextOverlaySegment>[];
    for (final textClip in textClips) {
      for (final segment in segments) {
        final overlapStart = _maxDuration(
          textClip.timelineStart,
          segment.timelineStart,
        );
        final overlapEnd = _minDuration(
          textClip.timelineEnd,
          segment.timelineEnd,
        );
        if (overlapEnd <= overlapStart) {
          continue;
        }

        overlays.add(
          TextOverlaySegment(
            zOrder: project.layerOrderByClipId[textClip.id] ?? 0,
            fadeIn: textClip.fadeIn,
            fadeOut: textClip.fadeOut,
            text: textClip.textContent.trim(),
            outputStart:
                segment.outputStart + (overlapStart - segment.timelineStart),
            duration: overlapEnd - overlapStart,
            overlayX: textClip.overlayX,
            overlayY: textClip.overlayY,
            fontFamily: textClip.fontFamily,
            fontSize: textClip.fontSize,
            textColor: textClip.textColor,
            backgroundColor: textClip.backgroundColor,
            opacity: textClip.opacity,
            animation: textClip.textAnimation,
            keyframes: textClip.keyframes,
          ),
        );
      }
    }
    return overlays;
  }

  List<TransitionOverlaySegment> _buildTransitionOverlays(
    TgiProject project,
    List<ExportWindow> segments,
  ) {
    final overlays = <TransitionOverlaySegment>[];
    final transitions = [...project.transitions]
      ..sort((a, b) => a.timelinePosition.compareTo(b.timelinePosition));
    for (final transition in transitions) {
      if (transition.duration <= Duration.zero) {
        continue;
      }
      for (final segment in segments) {
        final overlapStart = _maxDuration(
          transition.timelineStart,
          segment.timelineStart,
        );
        final overlapEnd = _minDuration(
          transition.timelineEnd,
          segment.timelineEnd,
        );
        if (overlapEnd <= overlapStart) {
          continue;
        }

        overlays.add(
          TransitionOverlaySegment(
            filePath: transition.filePath,
            outputStart:
                segment.outputStart + (overlapStart - segment.timelineStart),
            sourceStart: overlapStart - transition.timelineStart,
            duration: overlapEnd - overlapStart,
            blendMode: transition.blendMode,
            placement: transition.placement,
            preset: transition.preset,
            direction: transition.direction,
            color: transition.color,
            intensity: transition.intensity,
          ),
        );
      }
    }
    return overlays;
  }

  Duration _videoLessExportDuration(TgiProject project) {
    final hasSoloAudioTrack = project.tracks.any(
      (track) =>
          track.type == TrackType.audio && track.isSolo && !track.isHidden,
    );
    var duration = Duration.zero;
    for (final track in project.tracks) {
      if (track.isHidden) {
        continue;
      }
      if (track.type == TrackType.audio &&
          (track.isMuted || (hasSoloAudioTrack && !track.isSolo))) {
        continue;
      }
      for (final clip in track.clips) {
        if (clip.trackType == TrackType.video ||
            clip.duration <= Duration.zero) {
          continue;
        }
        if (clip.trackType == TrackType.text &&
            clip.textContent.trim().isEmpty) {
          continue;
        }
        if (clip.timelineEnd > duration) {
          duration = clip.timelineEnd;
        }
      }
    }
    return duration;
  }

  List<AudioMixSegment> _buildStandaloneAudioSegments(
    TgiProject project,
    Map<String, MediaItem> mediaById, {
    bool includePairedVideoAudio = true,
    Set<String>? excludedPairedVideoGroupIds,
  }) {
    final hasSoloAudioTrack = project.tracks.any(
      (track) =>
          track.type == TrackType.audio && track.isSolo && !track.isHidden,
    );
    final videoClipsByGroup = <String, Clip>{};
    for (final track in project.tracks) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.video) continue;
        if (clip.duration > Duration.zero) {
          videoClipsByGroup.putIfAbsent(clip.timelineGroupId, () => clip);
        }
      }
    }
    final segments = <AudioMixSegment>[];
    for (final track in project.tracks) {
      if (track.type != TrackType.audio ||
          track.isHidden ||
          track.isMuted ||
          (hasSoloAudioTrack && !track.isSolo)) {
        continue;
      }
      for (final clip in track.clips) {
        if (clip.duration <= Duration.zero) {
          continue;
        }
        if (!includePairedVideoAudio) {
          final excludePairedAudio = excludedPairedVideoGroupIds == null
              ? _audioClipIsUsedByVisibleVideoSegment(project, clip)
              : excludedPairedVideoGroupIds.contains(clip.timelineGroupId);
          if (excludePairedAudio) {
            continue;
          }
        }
        final mediaItem = mediaById[clip.mediaItemId];
        if (mediaItem == null) {
          throw FfmpegProcessException(
            'Midia ausente para o audio ${clip.id}.',
          );
        }
        if (mediaItem.type != MediaType.video &&
            mediaItem.type != MediaType.audio) {
          throw FfmpegProcessException(
            'O clipe ${clip.id} nao aponta para uma midia com audio.',
          );
        }
        if (mediaItem.type == MediaType.video && !mediaItem.hasAudio) {
          continue;
        }
        final pairedVideoClip = videoClipsByGroup[clip.timelineGroupId];
        segments.add(
          AudioMixSegment(
            filePath: mediaItem.filePath,
            timelineStart: clip.timelineStart,
            sourceStart: clip.sourceStart,
            sourceDuration: clip.effectiveSourceDuration,
            duration: clip.duration,
            playbackSpeed: clip.playbackSpeed,
            volume: clip.volume * track.volume,
            noiseReductionDb: clip.audioNoiseReductionDb,
            fadeIn: clip.fadeIn,
            fadeOut: clip.fadeOut,
            reverseAudio: pairedVideoClip?.reverseVideo ?? false,
            keyframes: clip.keyframes,
          ),
        );
      }
    }
    segments.sort((first, second) {
      final byStart = first.timelineStart.compareTo(second.timelineStart);
      if (byStart != 0) {
        return byStart;
      }
      return first.filePath.compareTo(second.filePath);
    });
    return segments;
  }

  bool _audioClipIsUsedByVisibleVideoSegment(
    TgiProject project,
    Clip audioClip,
  ) {
    for (final track in project.tracks) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.video) continue;
        if (clip.timelineGroupId == audioClip.timelineGroupId &&
            clip.mediaItemId == audioClip.mediaItemId &&
            clip.duration == audioClip.duration &&
            clip.duration > Duration.zero) {
          return true;
        }
      }
    }
    return false;
  }

  String _buildStandaloneAudioFilter(
    List<AudioMixSegment> segments,
    Duration totalDuration, {
    int firstInputIndex = 1,
    String outputLabel = 'a',
  }) {
    final totalSeconds = _seconds(totalDuration);
    if (segments.isEmpty) {
      return 'anullsrc=channel_layout=stereo:sample_rate=48000,'
          'atrim=duration=$totalSeconds,asetpts=PTS-STARTPTS[$outputLabel]';
    }

    final filters = <String>[];
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final inputIndex = firstInputIndex + index;
      final audioStart = _seconds(segment.sourceStart);
      final audioEnd = _seconds(segment.sourceStart + segment.sourceDuration);
      final delayMs = math.max(0, segment.timelineStart.inMilliseconds);
      final audioFadeFilters = _audioFadeFilters(
        fadeIn: segment.fadeIn,
        fadeOut: segment.fadeOut,
        duration: segment.duration,
      );
      filters.add(
        <String>[
          '[$inputIndex:a]atrim=start=$audioStart:end=$audioEnd',
          if (segment.reverseAudio) 'areverse',
          'asetpts=PTS-STARTPTS',
          ..._audioTempoFilters(segment.playbackSpeed),
          ..._audioNoiseReductionFilters(segment.noiseReductionDb),
          _audioVolumeFilter(
            segment.volume,
            keyframes: segment.keyframes,
            outputStart: segment.timelineStart,
            duration: segment.duration,
          ),
          ...audioFadeFilters,
          if (delayMs > 0) 'adelay=$delayMs:all=1',
          // adelay can emit leading silence without timestamps after a source
          // trim. Rebuild its sample clock before atrim, or the silence is lost
          // and a late music clip is moved to the beginning of the export.
          'asetpts=N/SR/TB',
          'apad',
          'atrim=duration=$totalSeconds',
          'asetpts=PTS-STARTPTS[aud$index]',
        ].join(','),
      );
    }

    if (segments.length == 1) {
      filters.add('[aud0]anull[$outputLabel]');
    } else {
      final inputs = StringBuffer();
      for (var index = 0; index < segments.length; index++) {
        inputs.write('[aud$index]');
      }
      filters.add(
        '$inputs'
        'amix=inputs=${segments.length}:duration=longest:dropout_transition=0:normalize=0,'
        'atrim=duration=$totalSeconds,asetpts=PTS-STARTPTS[$outputLabel]',
      );
    }
    return filters.join(';');
  }

  String _segmentVideoFilter(
    ExportSegment segment,
    int segmentIndex,
    int inputIndex, {
    required int outputWidth,
    required int outputHeight,
    required bool coverOutputFrame,
  }) {
    final videoStart = _seconds(segment.videoSourceStart);
    final videoEnd = _seconds(
      segment.videoSourceStart + segment.videoSourceDuration,
    );
    final filters = <String>[
      '[$inputIndex:v]trim=start=$videoStart:end=$videoEnd',
      ..._cropFilters(
        left: segment.cropLeft,
        top: segment.cropTop,
        right: segment.cropRight,
        bottom: segment.cropBottom,
        keyframes: segment.videoKeyframes,
        outputStart: segment.outputStart,
        duration: segment.duration,
      ),
      ..._orientationFilters(
        rotationDegrees: segment.rotationDegrees,
        flipHorizontal: segment.flipHorizontal,
        flipVertical: segment.flipVertical,
      ),
      if (segment.reverseVideo) 'reverse',
      _videoSetPtsFilter(segment.playbackSpeed),
      ..._chromaKeyFilters(
        enabled: segment.chromaKeyEnabled,
        color: segment.chromaKeyColor,
        similarity: segment.chromaKeySimilarity,
        blend: segment.chromaKeyBlend,
      ),
      ..._videoLookFilters(segment),
      ..._mainVideoFrameFilters(
        segment,
        outputWidth: outputWidth,
        outputHeight: outputHeight,
        coverOutputFrame: coverOutputFrame,
      ),
      'format=rgba',
      ..._opacityFilters(
        opacity: segment.opacity,
        keyframes: segment.videoKeyframes,
        outputStart: Duration.zero,
        duration: segment.duration,
      ),
      ..._videoFadeFilters(
        alpha: true,
        fadeIn: segment.videoFadeIn,
        fadeOut: segment.videoFadeOut,
        duration: segment.duration,
      ),
    ];
    if (!segment.maskEnabled) {
      return '${filters.join(',')},setsar=1[segv$segmentIndex]';
    }
    final baseLabel = 'segmaskbase$segmentIndex';
    final cleanLabel = 'segmaskclean$segmentIndex';
    final effectSourceLabel = 'segmaskfxsrc$segmentIndex';
    final effectLabel = 'segmaskfx$segmentIndex';
    final maskLabel = 'segmaskalpha$segmentIndex';
    final x = _keyframedExpression(
      keyframes: segment.videoKeyframes,
      property: ClipKeyframeProperty.maskX,
      outputStart: Duration.zero,
      duration: segment.duration,
      fallback: segment.maskX,
      variable: 'T',
    );
    final y = _keyframedExpression(
      keyframes: segment.videoKeyframes,
      property: ClipKeyframeProperty.maskY,
      outputStart: Duration.zero,
      duration: segment.duration,
      fallback: segment.maskY,
      variable: 'T',
    );
    final width = _keyframedExpression(
      keyframes: segment.videoKeyframes,
      property: ClipKeyframeProperty.maskWidth,
      outputStart: Duration.zero,
      duration: segment.duration,
      fallback: segment.maskWidth,
      variable: 'T',
    );
    final height = _keyframedExpression(
      keyframes: segment.videoKeyframes,
      property: ClipKeyframeProperty.maskHeight,
      outputStart: Duration.zero,
      duration: segment.duration,
      fallback: segment.maskHeight,
      variable: 'T',
    );
    final feather = math.max(
      1.0,
      math.min(outputWidth, outputHeight) * segment.maskFeather,
    );
    final featherText = _filterNumber(feather);
    final shapeExpression = switch (segment.maskShape) {
      VideoMaskShape.rectangle =>
        '255*clip((min(min(X-(W*($x)-W*($width)/2),(W*($x)+W*($width)/2)-X),'
            'min(Y-(H*($y)-H*($height)/2),(H*($y)+H*($height)/2)-Y))'
            '+$featherText)/(2*$featherText),0,1)',
      VideoMaskShape.ellipse =>
        '255*clip(((1-sqrt(pow((X-W*($x))/(max(1,W*($width)/2)),2)'
            '+pow((Y-H*($y))/(max(1,H*($height)/2)),2)))'
            '+${_filterNumber(segment.maskFeather)})/'
            'max(0.001,${_filterNumber(segment.maskFeather * 2)}),0,1)',
    };
    final maskExpression = segment.maskInverted
        ? '255-($shapeExpression)'
        : shapeExpression;
    final effectFilter = switch (segment.maskEffect) {
      VideoMaskEffect.blur =>
        'gblur=sigma=${_filterNumber(2 + segment.maskIntensity * 22)}:steps=2',
      VideoMaskEffect.pixelate =>
        'pixelize=w=${(8 + segment.maskIntensity * 36).round()}:'
            'h=${(8 + segment.maskIntensity * 36).round()}:mode=avg',
      VideoMaskEffect.darken =>
        'eq=brightness=${_filterNumber(-0.78 * segment.maskIntensity)}',
    };
    return '${filters.join(',')},setsar=1[$baseLabel];'
        '[$baseLabel]split=2[$cleanLabel][$effectSourceLabel];'
        '[$effectSourceLabel]$effectFilter[$effectLabel];'
        'color=c=black:s=${outputWidth}x$outputHeight:r=30:'
        'd=${_seconds(segment.duration)},format=yuva444p,'
        "geq=lum='$maskExpression':cb='$maskExpression':cr='$maskExpression':a='$maskExpression'[$maskLabel];"
        '[$cleanLabel][$effectLabel][$maskLabel]maskedmerge[segv$segmentIndex]';
  }

  List<String> _videoLookFilters(ExportSegment segment) {
    return _videoLookFiltersFor(
      brightness: segment.brightness,
      contrast: segment.contrast,
      saturation: segment.saturation,
      exposure: segment.exposure,
      hue: segment.hue,
      temperature: segment.temperature,
      tint: segment.tint,
      shadows: segment.shadows,
      highlights: segment.highlights,
      curveShadows: segment.curveShadows,
      curveMidtones: segment.curveMidtones,
      curveHighlights: segment.curveHighlights,
      filterPreset: segment.filterPreset,
      keyframes: segment.videoKeyframes,
      outputStart: segment.outputStart,
      duration: segment.duration,
    );
  }

  List<String> _videoMaskGraph({
    required String baseLabel,
    required String outputLabel,
    required String labelPrefix,
    required VideoMaskShape shape,
    required VideoMaskEffect effect,
    required double x,
    required double y,
    required double width,
    required double height,
    required double feather,
    required double intensity,
    required bool inverted,
    required List<ClipKeyframe> keyframes,
    required Duration outputStart,
    required Duration duration,
  }) {
    final xExpression = _keyframedExpression(
      keyframes: keyframes,
      property: ClipKeyframeProperty.maskX,
      outputStart: outputStart,
      duration: duration,
      fallback: x,
      variable: 'T',
    );
    final yExpression = _keyframedExpression(
      keyframes: keyframes,
      property: ClipKeyframeProperty.maskY,
      outputStart: outputStart,
      duration: duration,
      fallback: y,
      variable: 'T',
    );
    final widthExpression = _keyframedExpression(
      keyframes: keyframes,
      property: ClipKeyframeProperty.maskWidth,
      outputStart: outputStart,
      duration: duration,
      fallback: width,
      variable: 'T',
    );
    final heightExpression = _keyframedExpression(
      keyframes: keyframes,
      property: ClipKeyframeProperty.maskHeight,
      outputStart: outputStart,
      duration: duration,
      fallback: height,
      variable: 'T',
    );
    final safeFeather = feather.clamp(0.0, 0.5).toDouble();
    final featherExpression = 'max(1,min(W,H)*${_filterNumber(safeFeather)})';
    final shapeExpression = switch (shape) {
      VideoMaskShape.rectangle =>
        '255*clip((min(min(X-(W*($xExpression)-W*($widthExpression)/2),'
            '(W*($xExpression)+W*($widthExpression)/2)-X),'
            'min(Y-(H*($yExpression)-H*($heightExpression)/2),'
            '(H*($yExpression)+H*($heightExpression)/2)-Y))'
            '+$featherExpression)/(2*$featherExpression),0,1)',
      VideoMaskShape.ellipse =>
        '255*clip(((1-sqrt(pow((X-W*($xExpression))/'
            '(max(1,W*($widthExpression)/2)),2)'
            '+pow((Y-H*($yExpression))/(max(1,H*($heightExpression)/2)),2)))'
            '+${_filterNumber(safeFeather)})/'
            'max(0.001,${_filterNumber(safeFeather * 2)}),0,1)',
    };
    final maskExpression = inverted
        ? '255-($shapeExpression)'
        : shapeExpression;
    final effectFilter = switch (effect) {
      VideoMaskEffect.blur =>
        'gblur=sigma=${_filterNumber(2 + intensity * 22)}:steps=2',
      VideoMaskEffect.pixelate =>
        'pixelize=w=${(8 + intensity * 36).round()}:'
            'h=${(8 + intensity * 36).round()}:mode=avg',
      VideoMaskEffect.darken =>
        'eq=brightness=${_filterNumber(-0.78 * intensity)}',
    };
    final cleanLabel = '${labelPrefix}clean';
    final effectSourceLabel = '${labelPrefix}fxsrc';
    final maskSourceLabel = '${labelPrefix}masksrc';
    final effectLabel = '${labelPrefix}fx';
    final maskLabel = '${labelPrefix}alpha';
    return [
      '[$baseLabel]split=3[$cleanLabel][$effectSourceLabel][$maskSourceLabel]',
      '[$effectSourceLabel]$effectFilter[$effectLabel]',
      '[$maskSourceLabel]format=yuva444p,'
          "geq=lum='$maskExpression':cb='$maskExpression':cr='$maskExpression':a='$maskExpression'[$maskLabel]",
      '[$cleanLabel][$effectLabel][$maskLabel]maskedmerge[$outputLabel]',
    ];
  }

  List<String> _mainVideoFrameFilters(
    ExportSegment segment, {
    required int outputWidth,
    required int outputHeight,
    required bool coverOutputFrame,
  }) {
    final hasCameraKeyframes =
        _hasKeyframesFor(
          segment.videoKeyframes,
          ClipKeyframeProperty.overlayX,
        ) ||
        _hasKeyframesFor(
          segment.videoKeyframes,
          ClipKeyframeProperty.overlayY,
        ) ||
        _hasKeyframesFor(
          segment.videoKeyframes,
          ClipKeyframeProperty.overlayScale,
        );
    if (!segment.kenBurnsEnabled && !hasCameraKeyframes) {
      if (_hasStaticTransform(segment)) {
        return _staticMainTransformFilters(
          segment,
          outputWidth: outputWidth,
          outputHeight: outputHeight,
          coverOutputFrame: coverOutputFrame,
        );
      }
      if (coverOutputFrame) {
        return [
          'scale=$outputWidth:$outputHeight:'
              'force_original_aspect_ratio=increase:flags=lanczos',
          'crop=$outputWidth:$outputHeight:(iw-ow)/2:(ih-oh)/2',
        ];
      }
      return [
        'scale=$outputWidth:$outputHeight:'
            'force_original_aspect_ratio=decrease:flags=lanczos',
        'pad=$outputWidth:$outputHeight:(ow-iw)/2:(oh-ih)/2:color=black',
      ];
    }
    if (hasCameraKeyframes) {
      final scale = _keyframedExpression(
        keyframes: segment.videoKeyframes,
        property: ClipKeyframeProperty.overlayScale,
        outputStart: segment.outputStart,
        duration: segment.duration,
        fallback: segment.overlayScale,
      );
      final x = _keyframedExpression(
        keyframes: segment.videoKeyframes,
        property: ClipKeyframeProperty.overlayX,
        outputStart: segment.outputStart,
        duration: segment.duration,
        fallback: segment.overlayX,
      );
      final y = _keyframedExpression(
        keyframes: segment.videoKeyframes,
        property: ClipKeyframeProperty.overlayY,
        outputStart: segment.outputStart,
        duration: segment.duration,
        fallback: segment.overlayY,
      );
      final effectiveScale = (segment.transformScale - 1).abs() < 0.000001
          ? scale
          : '($scale)*${_filterNumber(segment.transformScale)}';
      final effectiveX = segment.transformOffsetX.abs() < 0.000001
          ? x
          : 'min(max(($x)+${_filterNumber(segment.transformOffsetX / 2)},0),1)';
      final effectiveY = segment.transformOffsetY.abs() < 0.000001
          ? y
          : 'min(max(($y)+${_filterNumber(segment.transformOffsetY / 2)},0),1)';
      return [
        "scale=w='$outputWidth*max(1,$effectiveScale)':"
            "h='$outputHeight*max(1,$effectiveScale)':"
            'eval=frame:force_original_aspect_ratio=increase:flags=lanczos',
        "crop=w=$outputWidth:h=$outputHeight:"
            "x='(iw-ow)*($effectiveX)':"
            "y='(ih-oh)*($effectiveY)'",
      ];
    }
    final progress = _overlayProgressExpression(
      segment.outputStart,
      segment.duration,
      startFraction: segment.kenBurnsStart,
      endFraction: segment.kenBurnsEnd,
    );
    final startScale = _clampCameraScale(
      segment.startOverlayScale * segment.transformScale,
    );
    final endScale = _clampCameraScale(
      segment.overlayScale * segment.transformScale,
    );
    final sx = _normalizedOverlayOffset(
      _transformOverlayOffset(segment.startOverlayX, segment.transformOffsetX),
    );
    final sy = _normalizedOverlayOffset(
      _transformOverlayOffset(segment.startOverlayY, segment.transformOffsetY),
    );
    final ex = _normalizedOverlayOffset(
      _transformOverlayOffset(segment.overlayX, segment.transformOffsetX),
    );
    final ey = _normalizedOverlayOffset(
      _transformOverlayOffset(segment.overlayY, segment.transformOffsetY),
    );
    return [
      "scale=w='$outputWidth*($startScale+($endScale-$startScale)*$progress)':"
          "h='$outputHeight*($startScale+($endScale-$startScale)*$progress)':"
          'eval=frame:force_original_aspect_ratio=increase:flags=lanczos',
      "crop=w=$outputWidth:h=$outputHeight:"
          "x='(iw-ow)*($sx+($ex-$sx)*$progress)':"
          "y='(ih-oh)*($sy+($ey-$sy)*$progress)'",
    ];
  }

  bool _hasStaticTransform(ExportSegment segment) {
    return segment.transformOffsetX.abs() > 0.000001 ||
        segment.transformOffsetY.abs() > 0.000001 ||
        (segment.transformScale - 1).abs() > 0.000001;
  }

  List<String> _staticMainTransformFilters(
    ExportSegment segment, {
    required int outputWidth,
    required int outputHeight,
    required bool coverOutputFrame,
  }) {
    final scale = _filterNumber(
      segment.transformScale.clamp(0.1, 8.0).toDouble(),
    );
    final offsetX = _filterNumber(
      segment.transformOffsetX.clamp(-1.0, 1.0).toDouble(),
    );
    final offsetY = _filterNumber(
      segment.transformOffsetY.clamp(-1.0, 1.0).toDouble(),
    );
    if (coverOutputFrame) {
      return [
        "scale=w='$outputWidth*max(1,$scale)':"
            "h='$outputHeight*max(1,$scale)':"
            'force_original_aspect_ratio=increase:flags=lanczos',
        "crop=w=$outputWidth:h=$outputHeight:"
            "x='(iw-ow)*(0.5-($offsetX)/2)':"
            "y='(ih-oh)*(0.5-($offsetY)/2)'",
      ];
    }
    return [
      "scale=w='$outputWidth*$scale':h='$outputHeight*$scale':"
          'force_original_aspect_ratio=decrease:flags=lanczos',
      "pad=w='ceil(max(iw,$outputWidth)/2)*2':"
          "h='ceil(max(ih,$outputHeight)/2)*2':"
          "x='(ow-iw)/2+($offsetX)*(ow-iw)/2':"
          "y='(oh-ih)/2+($offsetY)*(oh-ih)/2':color=black",
      "crop=w=$outputWidth:h=$outputHeight:"
          "x='(iw-ow)/2-($offsetX)*(iw-ow)/2':"
          "y='(ih-oh)/2-($offsetY)*(ih-oh)/2'",
    ];
  }

  List<String> _videoLookFiltersFor({
    required double brightness,
    required double contrast,
    required double saturation,
    required double exposure,
    required double hue,
    required double temperature,
    required double tint,
    required double shadows,
    required double highlights,
    required double curveShadows,
    required double curveMidtones,
    required double curveHighlights,
    required VideoFilterPreset filterPreset,
    List<ClipKeyframe> keyframes = const [],
    Duration outputStart = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    final filters = <String>[];
    switch (filterPreset) {
      case VideoFilterPreset.none:
        break;
      case VideoFilterPreset.blackAndWhite:
        filters.add('hue=s=0');
        break;
      case VideoFilterPreset.sepia:
        filters.add(
          'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131:0',
        );
        break;
      case VideoFilterPreset.vintage:
        filters.add(
          'colorbalance=rs=.08:gs=.04:bs=-.05:rm=.04:gm=.02:bm=-.04:rh=.02:gh=.01:bh=-.02',
        );
        filters.add('eq=contrast=1.080000:saturation=0.850000');
        break;
      case VideoFilterPreset.cinematic:
        filters.add(
          'colorbalance=rs=-.08:gs=.02:bs=.10:rm=.04:gm=0:bm=-.04:rh=.10:gh=.02:bh=-.08',
        );
        filters.add('eq=contrast=1.120000:saturation=1.080000');
        break;
    }

    final hasEqKeyframes =
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.brightness) ||
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.contrast) ||
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.saturation) ||
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.exposure);
    final hasManualAdjustments =
        brightness.abs() > 0.000001 ||
        (contrast - 1).abs() > 0.000001 ||
        (saturation - 1).abs() > 0.000001 ||
        exposure.abs() > 0.000001;
    if (hasEqKeyframes) {
      final brightnessExpr = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.brightness,
        outputStart: outputStart,
        duration: duration,
        fallback: brightness,
      );
      final contrastExpr = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.contrast,
        outputStart: outputStart,
        duration: duration,
        fallback: contrast,
      );
      final saturationExpr = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.saturation,
        outputStart: outputStart,
        duration: duration,
        fallback: saturation,
      );
      final exposureExpr = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.exposure,
        outputStart: outputStart,
        duration: duration,
        fallback: exposure,
      );
      filters.add(
        "eq=brightness='$brightnessExpr'"
        ":contrast='$contrastExpr'"
        ":saturation='$saturationExpr'"
        ":gamma='1+($exposureExpr)':eval=frame",
      );
    } else if (hasManualAdjustments) {
      final gamma = (1 + exposure).clamp(0.1, 3.0).toDouble();
      filters.add(
        'eq=brightness=${_filterNumber(brightness)}'
        ':contrast=${_filterNumber(contrast)}'
        ':saturation=${_filterNumber(saturation)}'
        ':gamma=${_filterNumber(gamma)}',
      );
    }
    final hasHueKeyframes = _hasKeyframesFor(
      keyframes,
      ClipKeyframeProperty.hue,
    );
    if (hasHueKeyframes) {
      final hueExpr = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.hue,
        outputStart: outputStart,
        duration: duration,
        fallback: hue,
      );
      filters.add("hue=H='$hueExpr':eval=frame");
    } else if (hue.abs() > 0.000001) {
      filters.add('hue=H=${_filterNumber(hue)}');
    }
    if (temperature.abs() > 0.000001 || tint.abs() > 0.000001) {
      final safeTemperature = temperature.clamp(-1.0, 1.0).toDouble();
      final safeTint = tint.clamp(-1.0, 1.0).toDouble();
      final red = safeTemperature * 0.20 + safeTint * 0.07;
      final green = -safeTint * 0.14;
      final blue = -safeTemperature * 0.20 + safeTint * 0.07;
      filters.add(
        'colorbalance='
        'rs=${_filterNumber(red)}:gs=${_filterNumber(green)}:bs=${_filterNumber(blue)}:'
        'rm=${_filterNumber(red)}:gm=${_filterNumber(green)}:bm=${_filterNumber(blue)}:'
        'rh=${_filterNumber(red)}:gh=${_filterNumber(green)}:bh=${_filterNumber(blue)}',
      );
    }
    if (shadows.abs() > 0.000001 ||
        highlights.abs() > 0.000001 ||
        curveShadows.abs() > 0.000001 ||
        curveMidtones.abs() > 0.000001 ||
        curveHighlights.abs() > 0.000001) {
      final shadowPoint = (0.25 + shadows * 0.18 + curveShadows * 0.18)
          .clamp(0.02, 0.48)
          .toDouble();
      final midPoint = (0.50 + curveMidtones * 0.22)
          .clamp(0.26, 0.74)
          .toDouble();
      final highlightPoint = (0.75 + highlights * 0.18 + curveHighlights * 0.18)
          .clamp(0.52, 0.98)
          .toDouble();
      filters.add(
        "curves=master='0/0 0.25/${_filterNumber(shadowPoint)} "
        "0.5/${_filterNumber(midPoint)} "
        "0.75/${_filterNumber(highlightPoint)} 1/1'",
      );
    }
    return filters;
  }

  String _segmentAudioFilter(
    ExportSegment segment,
    int segmentIndex,
    int inputIndex,
  ) {
    if (!segment.usesSourceAudio) {
      return _silentAudioFilter(segmentIndex, segment.duration);
    }

    final audioStart = _seconds(segment.audioSourceStart);
    final audioEnd = _seconds(
      segment.audioSourceStart + segment.audioSourceDuration,
    );
    final volumeFilter = _audioVolumeFilter(
      segment.volume,
      keyframes: segment.audioKeyframes,
      outputStart: segment.outputStart,
      duration: segment.duration,
    );
    final audioFadeFilters = _audioFadeFilters(
      fadeIn: segment.audioFadeIn,
      fadeOut: segment.audioFadeOut,
      duration: segment.duration,
    );
    return <String>[
      '[$inputIndex:a]atrim=start=$audioStart:end=$audioEnd',
      if (segment.reverseVideo) 'areverse',
      'asetpts=PTS-STARTPTS',
      ..._audioTempoFilters(segment.playbackSpeed),
      ..._audioNoiseReductionFilters(segment.audioNoiseReductionDb),
      if (audioFadeFilters.isEmpty)
        '$volumeFilter[a$segmentIndex]'
      else ...[
        volumeFilter,
        ...audioFadeFilters,
        'anull[a$segmentIndex]',
      ],
    ].join(',');
  }

  String _silentAudioFilter(int segmentIndex, Duration duration) {
    return 'anullsrc=channel_layout=stereo:sample_rate=48000,'
        'atrim=duration=${_seconds(duration)},'
        'asetpts=PTS-STARTPTS[a$segmentIndex]';
  }

  int _overlaySizePixels(num basePixels, double scale) {
    return (basePixels * scale).round();
  }

  String _imageOverlayFilter(
    ImageOverlaySegment overlay, {
    required int outputWidth,
    required int outputHeight,
  }) {
    final cropFilters = _cropFilters(
      left: overlay.cropLeft,
      top: overlay.cropTop,
      right: overlay.cropRight,
      bottom: overlay.cropBottom,
      keyframes: overlay.keyframes,
      outputStart: overlay.outputStart,
      duration: overlay.duration,
    );
    String fitFilter;
    switch (overlay.imageFit) {
      case ImageClipFit.cover:
        final hasCoverKeyframes =
            _hasKeyframesFor(
              overlay.keyframes,
              ClipKeyframeProperty.overlayX,
            ) ||
            _hasKeyframesFor(
              overlay.keyframes,
              ClipKeyframeProperty.overlayY,
            ) ||
            _hasKeyframesFor(
              overlay.keyframes,
              ClipKeyframeProperty.overlayScale,
            );
        fitFilter = hasCoverKeyframes
            ? _coverFrameKeyframeFilter(
                outputWidth: outputWidth,
                outputHeight: outputHeight,
                outputStart: overlay.outputStart,
                duration: overlay.duration,
                keyframes: overlay.keyframes,
                fallbackX: overlay.overlayX,
                fallbackY: overlay.overlayY,
                fallbackScale: overlay.overlayScale,
              )
            : overlay.kenBurnsEnabled
            ? _coverFrameAnimationFilter(
                outputWidth: outputWidth,
                outputHeight: outputHeight,
                outputStart: overlay.outputStart,
                duration: overlay.duration,
                startX: overlay.startOverlayX,
                startY: overlay.startOverlayY,
                endX: overlay.overlayX,
                endY: overlay.overlayY,
                startScale: overlay.startOverlayScale,
                endScale: overlay.overlayScale,
                startFraction: overlay.kenBurnsStart,
                endFraction: overlay.kenBurnsEnd,
              )
            : 'scale=$outputWidth:$outputHeight:force_original_aspect_ratio=increase,'
                  'crop=$outputWidth:$outputHeight';
      case ImageClipFit.contain:
        fitFilter =
            'scale=$outputWidth:$outputHeight:force_original_aspect_ratio=decrease';
      case ImageClipFit.overlay:
      case ImageClipFit.trackedOverlay:
        fitFilter = _overlayScaleFilter(
          outputWidth: outputWidth,
          outputHeight: outputHeight,
          outputStart: overlay.outputStart,
          duration: overlay.duration,
          startScale: overlay.startOverlayScale * overlay.transformScale,
          endScale: overlay.overlayScale * overlay.transformScale,
          animated: overlay.kenBurnsEnabled,
          startFraction: overlay.kenBurnsStart,
          endFraction: overlay.kenBurnsEnd,
          keyframes: overlay.keyframes,
        );
    }
    return [
      ...cropFilters,
      if (_hasOrientation(
        rotationDegrees: overlay.rotationDegrees,
        flipHorizontal: overlay.flipHorizontal,
        flipVertical: overlay.flipVertical,
      ))
        'format=rgba',
      ..._orientationFilters(
        rotationDegrees: overlay.rotationDegrees,
        flipHorizontal: overlay.flipHorizontal,
        flipVertical: overlay.flipVertical,
      ),
      fitFilter,
      if (overlay.imageFit != ImageClipFit.overlay &&
          overlay.imageFit != ImageClipFit.trackedOverlay &&
          (overlay.transformScale - 1).abs() > 0.000001)
        "scale=w='iw*${_filterNumber(overlay.transformScale)}':"
            "h='ih*${_filterNumber(overlay.transformScale)}'",
      ..._opacityFilters(
        opacity: overlay.opacity,
        keyframes: overlay.keyframes,
        outputStart: overlay.outputStart,
        duration: overlay.duration,
      ),
      ..._imageFadeFilters(overlay),
    ].join(',');
  }

  List<String> _imageFadeFilters(ImageOverlaySegment overlay) {
    final inSeconds = _fadeSeconds(overlay.fadeIn, overlay.duration);
    final outSeconds = _fadeSeconds(overlay.fadeOut, overlay.duration);
    if (inSeconds <= 0 && outSeconds <= 0) return const [];
    final start = _durationSeconds(overlay.outputStart);
    return [
      'format=rgba',
      if (inSeconds > 0)
        'fade=t=in:st=${start.toStringAsFixed(6)}:'
            'd=${inSeconds.toStringAsFixed(6)}:alpha=1',
      if (outSeconds > 0)
        'fade=t=out:st=${(start + _durationSeconds(overlay.duration) - outSeconds).toStringAsFixed(6)}:'
            'd=${outSeconds.toStringAsFixed(6)}:alpha=1',
    ];
  }

  String _videoOverlayScaleFilter(
    VideoOverlaySegment overlay, {
    required int outputWidth,
    required int outputHeight,
  }) {
    return _overlayScaleFilter(
      outputWidth: outputWidth,
      outputHeight: outputHeight,
      outputStart: overlay.outputStart,
      duration: overlay.duration,
      startScale: overlay.startOverlayScale * overlay.transformScale,
      endScale: overlay.overlayScale * overlay.transformScale,
      animated: overlay.kenBurnsEnabled,
      startFraction: overlay.kenBurnsStart,
      endFraction: overlay.kenBurnsEnd,
      keyframes: overlay.keyframes,
    );
  }

  String _coverFrameAnimationFilter({
    required int outputWidth,
    required int outputHeight,
    required Duration outputStart,
    required Duration duration,
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    required double startScale,
    required double endScale,
    required double startFraction,
    required double endFraction,
  }) {
    final progress = _overlayProgressExpression(
      outputStart,
      duration,
      startFraction: startFraction,
      endFraction: endFraction,
    );
    final startZoom = _clampCameraScale(startScale);
    final endZoom = _clampCameraScale(endScale);
    final sx = _normalizedOverlayOffset(startX);
    final sy = _normalizedOverlayOffset(startY);
    final ex = _normalizedOverlayOffset(endX);
    final ey = _normalizedOverlayOffset(endY);
    return "scale=w='$outputWidth*($startZoom+($endZoom-$startZoom)*$progress)':"
        "h='$outputHeight*($startZoom+($endZoom-$startZoom)*$progress)':"
        'eval=frame:force_original_aspect_ratio=increase,'
        "crop=w=$outputWidth:h=$outputHeight:"
        "x='(iw-ow)*($sx+($ex-$sx)*$progress)':"
        "y='(ih-oh)*($sy+($ey-$sy)*$progress)'";
  }

  String _coverFrameKeyframeFilter({
    required int outputWidth,
    required int outputHeight,
    required Duration outputStart,
    required Duration duration,
    required List<ClipKeyframe> keyframes,
    required double fallbackX,
    required double fallbackY,
    required double fallbackScale,
  }) {
    final scale = _keyframedExpression(
      keyframes: keyframes,
      property: ClipKeyframeProperty.overlayScale,
      outputStart: outputStart,
      duration: duration,
      fallback: fallbackScale,
    );
    final x = _keyframedExpression(
      keyframes: keyframes,
      property: ClipKeyframeProperty.overlayX,
      outputStart: outputStart,
      duration: duration,
      fallback: fallbackX,
    );
    final y = _keyframedExpression(
      keyframes: keyframes,
      property: ClipKeyframeProperty.overlayY,
      outputStart: outputStart,
      duration: duration,
      fallback: fallbackY,
    );
    return "scale=w='$outputWidth*max(1,$scale)':"
        "h='$outputHeight*max(1,$scale)':"
        'eval=frame:force_original_aspect_ratio=increase,'
        "crop=w=$outputWidth:h=$outputHeight:x='(iw-ow)*($x)':"
        "y='(ih-oh)*($y)'";
  }

  String _overlayScaleFilter({
    required int outputWidth,
    required int outputHeight,
    required Duration outputStart,
    required Duration duration,
    required double startScale,
    required double endScale,
    required bool animated,
    required double startFraction,
    required double endFraction,
    List<ClipKeyframe> keyframes = const [],
  }) {
    final end = _clampOverlayScale(endScale);
    final hasScaleKeyframes = _hasKeyframesFor(
      keyframes,
      ClipKeyframeProperty.overlayScale,
    );
    if (hasScaleKeyframes) {
      final scale = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.overlayScale,
        outputStart: outputStart,
        duration: duration,
        fallback: endScale,
      );
      return "scale=w='${_filterNumber(outputWidth / 4)}*($scale)':"
          "h='${_filterNumber(outputHeight / 4)}*($scale)':"
          'eval=frame:force_original_aspect_ratio=decrease';
    }
    if (!animated) {
      final overlayWidth = _overlaySizePixels(outputWidth / 4, end);
      final overlayHeight = _overlaySizePixels(outputHeight / 4, end);
      return 'scale=$overlayWidth:$overlayHeight:force_original_aspect_ratio=decrease';
    }

    final start = _clampOverlayScale(startScale);
    final startWidth = _overlaySizePixels(outputWidth / 4, start);
    final startHeight = _overlaySizePixels(outputHeight / 4, start);
    final endWidth = _overlaySizePixels(outputWidth / 4, end);
    final endHeight = _overlaySizePixels(outputHeight / 4, end);
    final progress = _overlayProgressExpression(
      outputStart,
      duration,
      startFraction: startFraction,
      endFraction: endFraction,
    );
    return "scale=w='$startWidth+($endWidth-$startWidth)*$progress':"
        "h='$startHeight+($endHeight-$startHeight)*$progress':"
        'eval=frame:force_original_aspect_ratio=decrease';
  }

  List<String> _cropFilters({
    required double left,
    required double top,
    required double right,
    required double bottom,
    List<ClipKeyframe> keyframes = const [],
    Duration outputStart = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    final hasCropKeyframes =
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.cropLeft) ||
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.cropTop) ||
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.cropRight) ||
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.cropBottom);
    if (hasCropKeyframes) {
      final l = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.cropLeft,
        outputStart: outputStart,
        duration: duration,
        fallback: left,
      );
      final t = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.cropTop,
        outputStart: outputStart,
        duration: duration,
        fallback: top,
      );
      final r = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.cropRight,
        outputStart: outputStart,
        duration: duration,
        fallback: right,
      );
      final b = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.cropBottom,
        outputStart: outputStart,
        duration: duration,
        fallback: bottom,
      );
      return [
        "crop=w='iw*max(0.05,1-($l)-($r))':"
            "h='ih*max(0.05,1-($t)-($b))':"
            "x='iw*($l)':y='ih*($t)':eval=frame",
      ];
    }
    final l = _clampUnit(left);
    final t = _clampUnit(top);
    final r = _clampUnit(right);
    final b = _clampUnit(bottom);
    if (l <= 0.000001 && t <= 0.000001 && r <= 0.000001 && b <= 0.000001) {
      return const [];
    }
    final width = math.max(0.05, 1 - l - r);
    final height = math.max(0.05, 1 - t - b);
    return [
      'crop=w=iw*${_filterNumber(width)}:h=ih*${_filterNumber(height)}:'
          'x=iw*${_filterNumber(l)}:y=ih*${_filterNumber(t)}',
    ];
  }

  List<String> _orientationFilters({
    required double rotationDegrees,
    required bool flipHorizontal,
    required bool flipVertical,
  }) {
    final filters = <String>[];
    if (flipHorizontal) filters.add('hflip');
    if (flipVertical) filters.add('vflip');
    final rotation = rotationDegrees.isFinite ? rotationDegrees : 0.0;
    if (rotation.abs() > 0.000001) {
      final angle = _filterNumber(rotation);
      filters.add(
        "rotate=angle='$angle*PI/180':ow='rotw($angle*PI/180)':"
        "oh='roth($angle*PI/180)':fillcolor=black@0",
      );
    }
    return filters;
  }

  bool _hasOrientation({
    required double rotationDegrees,
    required bool flipHorizontal,
    required bool flipVertical,
  }) {
    return flipHorizontal ||
        flipVertical ||
        (rotationDegrees.isFinite && rotationDegrees.abs() > 0.000001);
  }

  double _transformOverlayOffset(double base, double offset) {
    final safeBase = base.isFinite ? base : 0.5;
    final safeOffset = offset.isFinite ? offset : 0.0;
    return (safeBase + safeOffset / 2).clamp(0.0, 1.0).toDouble();
  }

  List<String> _chromaKeyFilters({
    required bool enabled,
    required int color,
    required double similarity,
    required double blend,
  }) {
    if (!enabled) {
      return const [];
    }
    final rgb = color & 0x00FFFFFF;
    final colorHex = '0x${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final safeSimilarity = similarity.isNaN || similarity.isInfinite
        ? 0.3
        : similarity.clamp(0.01, 1.0).toDouble();
    final safeBlend = blend.isNaN || blend.isInfinite
        ? 0.1
        : blend.clamp(0.0, 1.0).toDouble();
    return [
      'format=rgba',
      'chromakey=$colorHex:${_filterNumber(safeSimilarity)}:${_filterNumber(safeBlend)}',
    ];
  }

  List<String> _opacityFilters({
    required double opacity,
    required List<ClipKeyframe> keyframes,
    required Duration outputStart,
    required Duration duration,
  }) {
    final hasOpacityKeyframes = _hasKeyframesFor(
      keyframes,
      ClipKeyframeProperty.opacity,
    );
    if (hasOpacityKeyframes) {
      final expression = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.opacity,
        outputStart: outputStart,
        duration: duration,
        fallback: opacity,
        variable: 'T',
      );
      return [
        'format=rgba',
        "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*($expression)'",
      ];
    }
    final safeOpacity = _clampOpacity(opacity);
    if ((safeOpacity - 1).abs() <= 0.000001) {
      return const [];
    }
    return [
      'format=rgba',
      'colorchannelmixer=aa=${_filterNumber(safeOpacity)}',
    ];
  }

  String _overlayPositionExpression({
    required bool enabled,
    required Duration outputStart,
    required Duration duration,
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    required double startFraction,
    required double endFraction,
    required String fallbackX,
    required String fallbackY,
    List<ClipKeyframe> keyframes = const [],
    bool centered = false,
  }) {
    final hasPositionKeyframes =
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.overlayX) ||
        _hasKeyframesFor(keyframes, ClipKeyframeProperty.overlayY);
    if (hasPositionKeyframes) {
      final x = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.overlayX,
        outputStart: outputStart,
        duration: duration,
        fallback: endX,
      );
      final y = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.overlayY,
        outputStart: outputStart,
        duration: duration,
        fallback: endY,
      );
      if (centered) {
        return "x='W*($x)-w/2':y='H*($y)-h/2'";
      }
      return "x='(W-w)*($x)':y='(H-h)*($y)'";
    }
    if (!enabled) {
      if (centered) {
        return 'x=W*$fallbackX-w/2:y=H*$fallbackY-h/2';
      }
      return 'x=(W-w)*$fallbackX:y=(H-h)*$fallbackY';
    }
    final progress = _overlayProgressExpression(
      outputStart,
      duration,
      startFraction: startFraction,
      endFraction: endFraction,
    );
    final sx = _normalizedOverlayOffset(startX);
    final sy = _normalizedOverlayOffset(startY);
    final ex = _normalizedOverlayOffset(endX);
    final ey = _normalizedOverlayOffset(endY);
    if (centered) {
      return "x='W*($sx+($ex-$sx)*$progress)-w/2':"
          "y='H*($sy+($ey-$sy)*$progress)-h/2'";
    }
    return "x='(W-w)*($sx+($ex-$sx)*$progress)':"
        "y='(H-h)*($sy+($ey-$sy)*$progress)'";
  }

  String _overlayProgressExpression(
    Duration outputStart,
    Duration duration, {
    double startFraction = 0,
    double endFraction = 1,
  }) {
    final start =
        _durationSeconds(outputStart) +
        _durationSeconds(duration) * _clampUnit(startFraction);
    final end =
        _durationSeconds(outputStart) +
        _durationSeconds(duration) * _clampUnit(endFraction);
    final dur = math.max(0.001, end - start);
    return 'min(max((t-${start.toStringAsFixed(6)})/${dur.toStringAsFixed(6)},0),1)';
  }

  bool _hasKeyframesFor(
    List<ClipKeyframe> keyframes,
    ClipKeyframeProperty property,
  ) {
    return keyframes.any((keyframe) => keyframe.property == property);
  }

  List<ClipKeyframe> _keyframesFor(
    List<ClipKeyframe> keyframes,
    ClipKeyframeProperty property,
  ) {
    return [
      for (final keyframe in keyframes)
        if (keyframe.property == property) keyframe,
    ]..sort((a, b) => a.time.compareTo(b.time));
  }

  String _keyframedExpression({
    required List<ClipKeyframe> keyframes,
    required ClipKeyframeProperty property,
    required Duration outputStart,
    required Duration duration,
    required double fallback,
    String variable = 't',
  }) {
    final frames = _keyframesFor(keyframes, property);
    if (frames.isEmpty) {
      return _filterNumber(fallback);
    }
    if (frames.length == 1 || duration <= Duration.zero) {
      return _filterNumber(frames.first.value);
    }

    String frameTime(ClipKeyframe frame) {
      final seconds =
          _durationSeconds(outputStart) +
          _durationSeconds(duration) * _clampUnit(frame.time);
      return seconds.toStringAsFixed(6);
    }

    var expression = _filterNumber(frames.last.value);
    for (var index = frames.length - 2; index >= 0; index--) {
      final start = frames[index];
      final end = frames[index + 1];
      final startTime = frameTime(start);
      final endTime = frameTime(end);
      final span = math.max(
        0.001,
        double.parse(endTime) - double.parse(startTime),
      );
      final startValue = _filterNumber(start.value);
      final endValue = _filterNumber(end.value);
      final lerp =
          '$startValue+($endValue-$startValue)*(($variable-$startTime)/${span.toStringAsFixed(6)})';
      expression =
          'if(lte($variable,$startTime),$startValue,if(lte($variable,$endTime),$lerp,$expression))';
    }
    return expression;
  }

  bool _watermarkIsExportable(ProjectWatermark watermark) {
    return watermark.enabled && watermark.imagePath.trim().isNotEmpty;
  }

  String _appendWatermarkFilter(
    List<String> filters,
    ProjectWatermark watermark,
    String currentVideoLabel, {
    required int inputIndex,
    required int outputWidth,
    required int outputHeight,
  }) {
    if (!_watermarkIsExportable(watermark)) {
      return currentVideoLabel;
    }
    final watermarkLabel = 'wm0';
    final outputLabel = 'vwm0';
    final baseWidth = _overlaySizePixels(outputWidth / 6, watermark.scale);
    final baseHeight = _overlaySizePixels(outputHeight / 6, watermark.scale);
    filters
      ..add(
        '[$inputIndex:v]scale=$baseWidth:$baseHeight:'
        'force_original_aspect_ratio=decrease,format=rgba,'
        'colorchannelmixer=aa=${_filterNumber(_clampOpacity(watermark.opacity))}'
        '[$watermarkLabel]',
      )
      ..add(
        '[$currentVideoLabel][$watermarkLabel]overlay='
        '${_watermarkPositionExpression(watermark)}:eof_action=pass'
        '[$outputLabel]',
      );
    return outputLabel;
  }

  String _watermarkPositionExpression(ProjectWatermark watermark) {
    const margin = 24;
    return switch (watermark.position) {
      WatermarkPosition.topLeft => 'x=$margin:y=$margin',
      WatermarkPosition.topRight => 'x=W-w-$margin:y=$margin',
      WatermarkPosition.bottomLeft => 'x=$margin:y=H-h-$margin',
      WatermarkPosition.bottomRight => 'x=W-w-$margin:y=H-h-$margin',
      WatermarkPosition.custom =>
        'x=(W-w)*${_normalizedOverlayOffset(watermark.x)}:'
            'y=(H-h)*${_normalizedOverlayOffset(watermark.y)}',
    };
  }

  String _transitionOverlayFilter({
    required String baseLabel,
    required String transitionLabel,
    required String outputLabel,
    required String startSeconds,
    required String endSeconds,
    required TimelineTransitionBlendMode blendMode,
  }) {
    final enable = "enable='between(t,$startSeconds,$endSeconds)'";
    switch (blendMode) {
      case TimelineTransitionBlendMode.normal:
        return '[$baseLabel][$transitionLabel]overlay=0:0:$enable:'
            'eof_action=pass[$outputLabel]';
      case TimelineTransitionBlendMode.screen:
        return '[$baseLabel][$transitionLabel]blend=all_mode=screen:'
            'shortest=0:$enable[$outputLabel]';
    }
  }

  String _presetTransitionFilter({
    required String baseLabel,
    required String outputLabel,
    required TransitionOverlaySegment transition,
    required String startSeconds,
    required String endSeconds,
  }) {
    final preset = transition.preset;
    if (preset == TimelineTransitionPreset.fade ||
        preset == TimelineTransitionPreset.flash) {
      final color = _transitionFadeColor(
        preset == TimelineTransitionPreset.flash
            ? 0xFFFFFFFF
            : transition.color,
      );
      if (transition.placement == TimelineTransitionPlacement.start) {
        final durationSeconds = _seconds(transition.duration);
        return '[$baseLabel]fade=t=in:st=$startSeconds:'
            'd=$durationSeconds:color=$color:'
            "enable='between(t,$startSeconds,$endSeconds)'[$outputLabel]";
      }
      final halfDuration = Duration(
        microseconds: (transition.duration.inMicroseconds / 2).round(),
      );
      final halfSeconds = _seconds(halfDuration);
      final midpointSeconds = _seconds(transition.outputStart + halfDuration);
      return '[$baseLabel]fade=t=out:st=$startSeconds:d=$halfSeconds:color=$color:'
          "enable='between(t,$startSeconds,$midpointSeconds)',"
          'fade=t=in:st=$midpointSeconds:d=$halfSeconds:color=$color:'
          "enable='between(t,$midpointSeconds,$endSeconds)'[$outputLabel]";
    }

    final durationSeconds = _seconds(transition.duration);
    final color = _transitionDrawColor(transition.color, transition.intensity);
    final enable = "enable='between(t,$startSeconds,$endSeconds)'";
    switch (preset) {
      case TimelineTransitionPreset.wipe:
        final box = switch (transition.direction) {
          TimelineTransitionDirection.rightToLeft =>
            "x='iw-(t-$startSeconds)/$durationSeconds*2*iw':y=0:w=iw:h=ih",
          TimelineTransitionDirection.topToBottom =>
            "x=0:y='-ih+(t-$startSeconds)/$durationSeconds*2*ih':w=iw:h=ih",
          TimelineTransitionDirection.bottomToTop =>
            "x=0:y='ih-(t-$startSeconds)/$durationSeconds*2*ih':w=iw:h=ih",
          TimelineTransitionDirection.leftToRight =>
            "x='-iw+(t-$startSeconds)/$durationSeconds*2*iw':y=0:w=iw:h=ih",
        };
        return '[$baseLabel]drawbox=$box:color=$color:t=fill:'
            '$enable[$outputLabel]';
      case TimelineTransitionPreset.dissolve:
        return '[$baseLabel]tblend=all_mode=average:'
            '$enable[$outputLabel]';
      case TimelineTransitionPreset.blur:
        return '[$baseLabel]gblur=sigma=14:steps=2:'
            '$enable[$outputLabel]';
      case TimelineTransitionPreset.glitch:
        return '[$baseLabel]rgbashift=rh=12:rv=2:bh=-12:bv=-2:'
            'edge=wrap:$enable,noise=alls=18:allf=t+u:'
            '$enable[$outputLabel]';
      case TimelineTransitionPreset.spin:
        return '[$baseLabel]rotate='
            "'0.16*sin(2*PI*(t-$startSeconds)/$durationSeconds)':"
            'ow=iw:oh=ih:fillcolor=black@1:'
            '$enable[$outputLabel]';
      case TimelineTransitionPreset.pixelate:
        return '[$baseLabel]pixelize=w=28:h=28:mode=avg:'
            '$enable[$outputLabel]';
      case TimelineTransitionPreset.zoom:
        return '[$baseLabel]lenscorrection=k1=-0.22:k2=0.06:'
            'i=bilinear:fc=black:$enable[$outputLabel]';
      case TimelineTransitionPreset.lightLeak:
        final box =
            "x='-iw/2+(t-$startSeconds)/$durationSeconds*1.5*iw':"
            'y=0:w=iw/2:h=ih';
        return '[$baseLabel]drawbox=$box:color=$color:t=fill:'
            '$enable[$outputLabel]';
      case TimelineTransitionPreset.fade:
      case TimelineTransitionPreset.flash:
        throw StateError('Preset de fade deve ser tratado antes.');
      case null:
        return '[$baseLabel]null[$outputLabel]';
    }
  }

  String _transitionFadeColor(int argb) {
    final rgb = argb & 0x00FFFFFF;
    if (rgb == 0x000000) {
      return 'black';
    }
    if (rgb == 0xFFFFFF) {
      return 'white';
    }
    return '0x${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  String _transitionDrawColor(int argb, double intensity) {
    final rgb = argb & 0x00FFFFFF;
    final sourceAlpha = ((argb >> 24) & 0xff) / 255.0;
    final alpha = (sourceAlpha * _clampOpacity(intensity))
        .clamp(0.0, 1.0)
        .toStringAsFixed(3);
    return '0x${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}@$alpha';
  }

  String _drawTextFontFile(String fontFamily) {
    return "'${_escapeFilterPath(fontPath(fontFamily))}'";
  }

  String _drawTextSource(
    String value, {
    required int index,
    required String? directoryPath,
  }) {
    if (directoryPath == null || directoryPath.trim().isEmpty) {
      return 'text=${_escapeDrawText(value)}';
    }
    final path = _join(
      directoryPath,
      'drawtext_${index.toString().padLeft(3, '0')}.txt',
    );
    textFiles[path] = value;
    return "textfile='${_escapeFilterPath(path)}'";
  }

  String _escapeFilterPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    // Callers wrap the result in filtergraph single quotes. A literal quote
    // must survive both graph parsing and the filter's option parsing.
    return normalized.replaceAll(':', r'\:').replaceAll("'", r"'\\\''");
  }

  String _escapeDrawText(String value) {
    return value
        .replaceAll('\\', r'\\\\')
        .replaceAll("'", r"\\\'")
        .replaceAll(':', r'\\\:')
        .replaceAll(',', r'\\\,')
        .replaceAll(';', r'\\\;')
        .replaceAll('[', r'\\\[')
        .replaceAll(']', r'\\\]')
        .replaceAll('\r', ' ');
  }

  String _drawTextColor(int argb, double opacity) {
    final rgb = argb & 0x00FFFFFF;
    final alpha = (((argb >> 24) & 0xff) / 255.0) * _clampOpacity(opacity);
    return '0x${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}@${alpha.clamp(0.0, 1.0).toStringAsFixed(3)}';
  }

  String? _drawTextAlphaExpression(
    TextOverlaySegment overlay,
    String startSeconds,
  ) {
    final factors = <String>[
      if (overlay.animation == TextClipAnimation.fade ||
          overlay.animation == TextClipAnimation.pop)
        _drawTextIntroProgress(startSeconds),
      if (_hasKeyframesFor(overlay.keyframes, ClipKeyframeProperty.opacity))
        _keyframedExpression(
          keyframes: overlay.keyframes,
          property: ClipKeyframeProperty.opacity,
          outputStart: overlay.outputStart,
          duration: overlay.duration,
          fallback: overlay.opacity,
        ),
    ];
    if (overlay.fadeIn > Duration.zero) {
      factors.add(
        'min(max((t-$startSeconds)/${_seconds(overlay.fadeIn)},0),1)',
      );
    }
    if (overlay.fadeOut > Duration.zero) {
      factors.add(
        'min(max((${_seconds(overlay.outputStart + overlay.duration)}-t)/${_seconds(overlay.fadeOut)},0),1)',
      );
    }
    return factors.isEmpty
        ? null
        : factors.map((factor) => '($factor)').join('*');
  }

  String _drawTextXExpression(
    TextOverlaySegment overlay,
    String overlayX,
    String startSeconds, {
    required double slideDistancePixels,
  }) {
    final x = _hasKeyframesFor(overlay.keyframes, ClipKeyframeProperty.overlayX)
        ? _keyframedExpression(
            keyframes: overlay.keyframes,
            property: ClipKeyframeProperty.overlayX,
            outputStart: overlay.outputStart,
            duration: overlay.duration,
            fallback: overlay.overlayX,
          )
        : overlayX;
    final base = '(w-text_w)*($x)';
    return switch (overlay.animation) {
      TextClipAnimation.slideLeft =>
        '$base-(1-${_drawTextIntroProgress(startSeconds)})*'
            '${_filterNumber(slideDistancePixels)}',
      _ => base,
    };
  }

  String _drawTextYExpression(
    TextOverlaySegment overlay,
    String overlayY,
    String startSeconds, {
    required double riseDistancePixels,
  }) {
    final y = _hasKeyframesFor(overlay.keyframes, ClipKeyframeProperty.overlayY)
        ? _keyframedExpression(
            keyframes: overlay.keyframes,
            property: ClipKeyframeProperty.overlayY,
            outputStart: overlay.outputStart,
            duration: overlay.duration,
            fallback: overlay.overlayY,
          )
        : overlayY;
    final base = '(h-text_h)*($y)';
    return switch (overlay.animation) {
      TextClipAnimation.rise =>
        '$base+(1-${_drawTextIntroProgress(startSeconds)})*'
            '${_filterNumber(riseDistancePixels)}',
      _ => base,
    };
  }

  String _drawTextIntroProgress(String startSeconds) {
    return 'min(max((t-$startSeconds)/0.600000,0),1)';
  }

  String _drawTextFontSizeExpression(
    TextOverlaySegment overlay,
    int fontSize,
    String startSeconds,
  ) {
    if (overlay.animation != TextClipAnimation.pop) {
      return fontSize.toString();
    }
    final progress = _drawTextIntroProgress(startSeconds);
    return "'$fontSize*(0.82+$progress*0.18)'";
  }

  int _textFontSizePixels(double fontSize, int outputWidth, int outputHeight) {
    final safeFontSize = fontSize.isNaN || fontSize.isInfinite || fontSize <= 0
        ? 48.0
        : fontSize;
    final scaled =
        (safeFontSize * _textScaleForOutput(outputWidth, outputHeight)).round();
    final maximum = math.min(outputWidth, outputHeight) ~/ 4;
    final upper = maximum < 16 ? 16 : maximum;
    return scaled.clamp(12, upper).toInt();
  }

  int _textBoxBorderPixels(int outputWidth, int outputHeight) {
    final scaled = (18 * _textScaleForOutput(outputWidth, outputHeight))
        .round();
    return scaled.clamp(6, 42).toInt();
  }

  int _textShadowOffsetPixels(int outputWidth, int outputHeight) {
    final scaled = (2 * _textScaleForOutput(outputWidth, outputHeight)).round();
    return scaled.clamp(1, 8).toInt();
  }

  double _textScaleForOutput(int outputWidth, int outputHeight) {
    if (outputWidth <= 0 || outputHeight <= 0) {
      return 1;
    }
    return math.min(outputWidth, outputHeight) / 720;
  }

  String _wrapTextForExport(
    String value, {
    required int outputWidth,
    required int fontSizePixels,
  }) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.trim().isEmpty || outputWidth <= 0 || fontSizePixels <= 0) {
      return normalized.trim();
    }
    final horizontalPadding = fontSizePixels * 0.7;
    final availableWidth = math.max(
      1.0,
      outputWidth * 0.82 - horizontalPadding,
    );
    final averageGlyphWidth = math.max(1.0, fontSizePixels * 0.56);
    final maximumCharacters = (availableWidth / averageGlyphWidth)
        .floor()
        .clamp(8, 120);
    final lines = <String>[];
    for (final paragraph in normalized.split('\n')) {
      final words = paragraph
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty);
      var current = '';
      for (final word in words) {
        final candidate = current.isEmpty ? word : '$current $word';
        if (current.isEmpty || candidate.length <= maximumCharacters) {
          current = candidate;
          continue;
        }
        lines.add(current);
        current = word;
      }
      if (current.isNotEmpty) {
        lines.add(current);
      } else if (paragraph.isEmpty) {
        lines.add('');
      }
    }
    return lines.join('\n').trim();
  }

  double _clampOpacity(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _clampUnit(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _clampOverlayScale(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(0.35, 8.0).toDouble();
  }

  double _clampCameraScale(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(1.0, 8.0).toDouble();
  }

  String _normalizedOverlayOffset(double value) {
    if (value.isNaN || value.isInfinite) {
      return '0.000000';
    }
    return value.clamp(0.0, 1.0).toStringAsFixed(6);
  }

  String _audioVolumeFilter(
    double volume, {
    List<ClipKeyframe> keyframes = const [],
    Duration outputStart = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    if (_hasKeyframesFor(keyframes, ClipKeyframeProperty.volume)) {
      final expression = _keyframedExpression(
        keyframes: keyframes,
        property: ClipKeyframeProperty.volume,
        outputStart: outputStart,
        duration: duration,
        fallback: volume,
      );
      return "volume='$expression':eval=frame";
    }
    final clamped = (volume.isNaN || volume.isInfinite || volume < 0)
        ? 1
        : volume;
    return 'volume=${clamped.toStringAsFixed(6)}';
  }

  String _videoSetPtsFilter(double playbackSpeed) {
    final speed = _clampPlaybackSpeed(playbackSpeed);
    if ((speed - 1).abs() < 0.000001) {
      return 'setpts=PTS-STARTPTS';
    }
    return 'setpts=(PTS-STARTPTS)/${speed.toStringAsFixed(6)}';
  }

  String _videoSetPtsFilterWithOffset(
    double playbackSpeed,
    Duration outputStart,
  ) {
    final speed = _clampPlaybackSpeed(playbackSpeed);
    final offset = _seconds(outputStart);
    if ((speed - 1).abs() < 0.000001) {
      return 'setpts=PTS-STARTPTS+$offset/TB';
    }
    return 'setpts=(PTS-STARTPTS)/${speed.toStringAsFixed(6)}+$offset/TB';
  }

  List<String> _videoFadeFilters({
    bool alpha = false,
    Duration outputStart = Duration.zero,
    required Duration fadeIn,
    required Duration fadeOut,
    required Duration duration,
  }) {
    final filters = <String>[];
    final inSeconds = _fadeSeconds(fadeIn, duration);
    if (inSeconds > 0) {
      filters.add(
        'fade=t=in:st=${_seconds(outputStart)}:d=${inSeconds.toStringAsFixed(3)}${alpha ? ':alpha=1' : ''}',
      );
    }
    final outSeconds = _fadeSeconds(fadeOut, duration);
    if (outSeconds > 0) {
      final start =
          _durationSeconds(outputStart) +
          math.max(0.0, _durationSeconds(duration) - outSeconds);
      filters.add(
        'fade=t=out:st=${start.toStringAsFixed(3)}:d=${outSeconds.toStringAsFixed(3)}${alpha ? ':alpha=1' : ''}',
      );
    }
    return filters;
  }

  List<String> _audioFadeFilters({
    required Duration fadeIn,
    required Duration fadeOut,
    required Duration duration,
  }) {
    final filters = <String>[];
    final inSeconds = _fadeSeconds(fadeIn, duration);
    if (inSeconds > 0) {
      filters.add('afade=t=in:st=0:d=${inSeconds.toStringAsFixed(3)}');
    }
    final outSeconds = _fadeSeconds(fadeOut, duration);
    if (outSeconds > 0) {
      final start = math.max(0.0, _durationSeconds(duration) - outSeconds);
      filters.add(
        'afade=t=out:st=${start.toStringAsFixed(3)}:d=${outSeconds.toStringAsFixed(3)}',
      );
    }
    return filters;
  }

  double _fadeSeconds(Duration fade, Duration duration) {
    if (fade <= Duration.zero || duration <= Duration.zero) {
      return 0;
    }
    final maxFadeUs = (duration.inMicroseconds / 2).floor();
    final clampedUs = fade.inMicroseconds.clamp(0, maxFadeUs);
    return clampedUs / Duration.microsecondsPerSecond;
  }

  double _durationSeconds(Duration duration) {
    return duration.inMicroseconds / Duration.microsecondsPerSecond;
  }

  List<String> _audioTempoFilters(double playbackSpeed) {
    var remaining = _clampPlaybackSpeed(playbackSpeed);
    final filters = <String>[];
    while (remaining > 2.0) {
      filters.add('atempo=2.000000');
      remaining /= 2.0;
    }
    while (remaining < 0.5) {
      filters.add('atempo=0.500000');
      remaining /= 0.5;
    }
    if ((remaining - 1).abs() >= 0.000001) {
      filters.add('atempo=${remaining.toStringAsFixed(6)}');
    }
    return filters;
  }

  List<String> _audioNoiseReductionFilters(double noiseReductionDb) {
    if (noiseReductionDb.isNaN ||
        noiseReductionDb.isInfinite ||
        noiseReductionDb <= 0.1) {
      return const [];
    }
    final clamped = noiseReductionDb.clamp(0.0, 30.0).toDouble();
    return ['afftdn=nr=${clamped.toStringAsFixed(1)}'];
  }

  double _clampPlaybackSpeed(double value) {
    if (value.isNaN || value.isInfinite || value <= 0) {
      return 1;
    }
    return value.clamp(0.25, 4.0).toDouble();
  }

  String _seconds(Duration duration) {
    return (duration.inMicroseconds / Duration.microsecondsPerSecond)
        .toStringAsFixed(6);
  }

  String _filterNumber(double value) => value.toStringAsFixed(6);

  int _compareClipsByTimeline(Clip first, Clip second) {
    final byStart = first.timelineStart.compareTo(second.timelineStart);
    if (byStart != 0) {
      return byStart;
    }
    return first.id.compareTo(second.id);
  }

  Duration _maxDuration(Duration first, Duration second) {
    return first >= second ? first : second;
  }

  Duration _minDuration(Duration first, Duration second) {
    return first <= second ? first : second;
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

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    final normalizedMax = max < min ? min : max;
    if (value < min) {
      return min;
    }
    if (value > normalizedMax) {
      return normalizedMax;
    }
    return value;
  }

  FfmpegExportCommand _applyEditorExportOptions(
    FfmpegExportCommand command,
    FfmpegExportSettings settings,
  ) {
    final duration = settings.exportDuration(command.totalDuration);
    final arguments =
        settings.encoder == FfmpegVideoEncoder.software ||
            settings.encoder == FfmpegVideoEncoder.automatic
        ? List<String>.of(command.arguments)
        : replaceVideoEncoder(
            command.arguments,
            settings.encoder,
            settings.quality,
          );
    if (settings.hasRange) {
      // Output seeking preserves the timeline clock used by fades, text,
      // transitions and ducking, then resets the timestamps in the output.
      arguments.insertAll(arguments.length - 1, [
        '-ss',
        _seconds(settings.rangeStart ?? Duration.zero),
        '-t',
        _seconds(duration),
      ]);
    }
    return FfmpegExportCommand(
      arguments: arguments,
      totalDuration: duration,
      clipCount: command.clipCount,
      textFiles: command.textFiles,
    );
  }

  static List<String> replaceVideoEncoder(
    List<String> source,
    FfmpegVideoEncoder encoder,
    FfmpegExportQuality quality,
  ) {
    final args = List<String>.of(source);
    final codecIndex = args.indexOf('-c:v');
    if (codecIndex < 0) return args;
    args[codecIndex + 1] = encoder.codec;
    const options = {
      '-preset',
      '-crf',
      '-rc',
      '-cq',
      '-b:v',
      '-global_quality',
      '-quality',
      '-qp_i',
      '-qp_p',
    };
    for (var i = codecIndex + 2; i < args.length - 1;) {
      if (options.contains(args[i])) {
        args.removeRange(i, i + 2);
      } else {
        i++;
      }
    }
    final q = quality.crf.toString();
    final flags = switch (encoder) {
      FfmpegVideoEncoder.nvidia => [
        '-preset',
        'p4',
        '-rc',
        'vbr',
        '-cq',
        q,
        '-b:v',
        '0',
      ],
      FfmpegVideoEncoder.intel => ['-preset', 'medium', '-global_quality', q],
      FfmpegVideoEncoder.amd => [
        '-quality',
        'balanced',
        '-rc',
        'cqp',
        '-qp_i',
        q,
        '-qp_p',
        q,
      ],
      _ => ['-preset', quality.encoderPreset, '-crf', q],
    };
    args.insertAll(codecIndex + 2, flags);
    return args;
  }
}
