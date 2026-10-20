import '../../../domain/models/project.dart';

/// Snapshot history is independent of selection, playback and widget lifetime.
class EditorHistory {
  EditorHistory({this.limit = 50});
  final int limit;
  final List<TgiProject> undoStack = [];
  final List<TgiProject> redoStack = [];
  void record(TgiProject project) {
    undoStack.add(project);
    if (undoStack.length > limit) undoStack.removeAt(0);
    redoStack.clear();
  }

  void clear() {
    undoStack.clear();
    redoStack.clear();
  }
}
