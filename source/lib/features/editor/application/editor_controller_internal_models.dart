part of 'editor_controller.dart';

class _ClipboardClip {
  const _ClipboardClip({required this.trackId, required this.clip});

  final String trackId;
  final domain.Clip clip;
}

class _TimelineVideoEdit {
  const _TimelineVideoEdit({required this.position, required this.trackId});

  final Duration position;
  final String trackId;
}

class _TimelineVideoTransitionTarget {
  const _TimelineVideoTransitionTarget({
    required this.position,
    required this.trackId,
    required this.placement,
  });

  final Duration position;
  final String trackId;
  final TimelineTransitionPlacement placement;
}

class _PasteClipboardResult {
  const _PasteClipboardResult(this.project, this.timelineGroupIds);

  final TgiProject project;
  final Set<String> timelineGroupIds;
}
