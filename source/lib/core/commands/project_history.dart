import '../../domain/models/project.dart';

/// Snapshots and labels remain shared between UI and AI operations.
class EditorHistory {
  EditorHistory({this.limit = 50});
  final int limit;
  final List<TgiProject> undoStack = [];
  final List<TgiProject> redoStack = [];
  final List<String> _undoLabels = [];
  final List<String> _redoLabels = [];
  String? get undoLabel => _undoLabels.isEmpty ? null : _undoLabels.last;
  String? get redoLabel => _redoLabels.isEmpty ? null : _redoLabels.last;
  void record(TgiProject project, {String label = 'Edição'}) {
    undoStack.add(project);
    _undoLabels.add(label);
    if (undoStack.length > limit) {
      undoStack.removeAt(0);
      _undoLabels.removeAt(0);
    }
    redoStack.clear();
    _redoLabels.clear();
  }

  TgiProject undo(TgiProject current) {
    if (undoStack.isEmpty) {
      return current;
    }
    redoStack.add(current);
    _redoLabels.add(_undoLabels.isEmpty ? 'Edição' : _undoLabels.removeLast());
    return undoStack.removeLast();
  }

  TgiProject redo(TgiProject current) {
    if (redoStack.isEmpty) {
      return current;
    }
    undoStack.add(current);
    _undoLabels.add(_redoLabels.isEmpty ? 'Edição' : _redoLabels.removeLast());
    if (undoStack.length > limit) {
      undoStack.removeAt(0);
      _undoLabels.removeAt(0);
    }
    return redoStack.removeLast();
  }

  void clear() {
    undoStack.clear();
    redoStack.clear();
    _undoLabels.clear();
    _redoLabels.clear();
  }
}
