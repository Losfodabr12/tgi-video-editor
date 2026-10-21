part of 'editor_controller.dart';

extension EditorTimelineOperations on EditorController {
  void updateSelectedAudioPlaybackSpeed(double speed) {
    final clip = selectedTimelineAudioClip;
    if (clip == null) return;
    final next = _commandProject('set_clip_speed', {
      'clip_id': clip.id,
      'speed': speed.clamp(0.25, 4).toDouble(),
    });
    if (identical(next, _project) && clip.playbackSpeed != speed) {
      _errorMessage =
          'Não há espaço para alterar a duração ou uma pista vinculada está bloqueada.';
      notifyListeners();
      return;
    }
    _commitStructure(next, 'Velocidade do áudio atualizada.');
  }

  void _commitStructure(TgiProject next, String message) {
    if (identical(next, _project)) return;
    if (_interactiveEditBaseProject == null) {
      _commitProjectMutation(next, syncGapPlaybackTimer: true);
    } else {
      _project = next;
      _syncGapPlaybackTimer();
    }
    final present = {
      for (final track in next.tracks)
        for (final clip in track.clips) clip.timelineGroupId,
    };
    _setSelectedTimelineGroups(_selectedTimelineGroupIds.intersection(present));
    if (!present.contains(_selectedTimelineGroupId)) {
      _selectedTimelineGroupId = null;
    }
    _errorMessage = null;
    _statusMessage = message;
    notifyListeners();
  }

  void deleteTimelineTrack(String id) => _commitStructure(
    _project.deleteTrack(id),
    'Pista excluída. Ctrl+Z para desfazer.',
  );

  void reorderTimelineTrack(String id, int targetIndex) => _commitStructure(
    _project.reorderTrack(id, targetIndex),
    'Ordem das camadas atualizada.',
  );

  void resizeTimelineTrack(String id, double height) => _commitStructure(
    _project.setTrackHeight(id, height),
    'Altura da pista atualizada.',
  );

  void removeSelectedAudio() {
    final group = _selectedTimelineGroupId;
    if (group != null) {
      _commitStructure(
        _project.removeGroupAudio(group),
        'Áudio removido; imagem preservada.',
      );
    }
  }
}
