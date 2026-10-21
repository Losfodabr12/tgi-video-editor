import 'dart:math' as math;
import '../../domain/models/clip.dart';
import '../../domain/models/placement_conflict.dart';
import '../../domain/models/project.dart';
import '../../domain/models/timeline_transition.dart';
import '../../domain/models/track.dart';
import 'editor_command.dart';

/// Continuous, nondecreasing F(t) = t - sum(clamp(t - start, 0, length)).
/// All arithmetic at edit boundaries uses integer microseconds.
class TimelineTimeMap {
  TimelineTimeMap(Iterable<(int, int)> ranges, {required this.end}) {
    final sorted =
        ranges
            .map((r) => (r.$1.clamp(0, end), r.$2.clamp(0, end)))
            .where((r) => r.$2 > r.$1)
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final range in sorted) {
      if (merged.isEmpty || range.$1 > merged.last.$2) {
        merged.add(range);
      } else {
        merged[merged.length - 1] = (
          merged.last.$1,
          math.max(range.$2, merged.last.$2),
        );
      }
    }
    removed = List.unmodifiable(merged);
    final kept = <(int, int)>[];
    var cursor = 0;
    for (final range in removed) {
      if (cursor < range.$1) kept.add((cursor, range.$1));
      cursor = range.$2;
    }
    if (cursor < end) kept.add((cursor, end));
    retained = List.unmodifiable(kept);
  }
  final int end;
  late final List<(int, int)> removed, retained;
  int get removedDuration => removed.fold(0, (sum, r) => sum + r.$2 - r.$1);
  int map(int time) {
    var result = time;
    for (final range in removed) {
      if (time <= range.$1) break;
      result -= (time - range.$1).clamp(0, range.$2 - range.$1);
    }
    return result;
  }

  Map<String, Object?> toJson() => {
    'removed_duration': removedDuration / 1e6,
    'removed_ranges': [
      for (final r in removed) {'start': r.$1 / 1e6, 'end': r.$2 / 1e6},
    ],
    'kept_ranges': [
      for (final r in retained)
        {
          'old_start': r.$1 / 1e6,
          'old_end': r.$2 / 1e6,
          'new_start': map(r.$1) / 1e6,
          'new_end': map(r.$2) / 1e6,
        },
    ],
  };
}

class RemapSelection {
  const RemapSelection(this.tracks, this.skipped, this.unlocked);
  final Set<String> tracks, skipped, unlocked;
}

class TimelineRemapResult {
  const TimelineRemapResult(
    this.project,
    this.timeMap,
    this.selection,
    this.scope,
  );
  final TgiProject project;
  final TimelineTimeMap timeMap;
  final RemapSelection selection;
  final String scope;
  Map<String, Object?> toJson() => {
    'scope': scope,
    'affected_track_ids': selection.tracks.toList(),
    'skipped_track_ids': selection.skipped.toList(),
    'unlocked_track_ids': selection.unlocked.toList(),
    'time_map': timeMap.toJson(),
    if (selection.skipped.isNotEmpty || scope == 'main_track_only')
      'warning':
          'Camadas fora do escopo ou ignoradas mantêm seus tempos e podem ficar fora de sincronia; a duração global pode permanecer maior.',
  };
}

/// Pure snapshot transformation. No per-cut ripple, history or process access.
class TimelineRemapper {
  const TimelineRemapper();

  RemapSelection preflight(
    TgiProject project,
    Clip anchor, {
    String scope = 'all_tracks',
    String lockedTracks = 'fail',
  }) {
    if (!['all_tracks', 'main_track_only'].contains(scope) ||
        !['fail', 'skip', 'unlock'].contains(lockedTracks)) {
      throw const CommandError(
        'invalid_argument',
        'Use scope all_tracks|main_track_only e locked_tracks fail|skip|unlock.',
      );
    }
    final selected = scope == 'all_tracks'
        ? project.tracks.map((t) => t.id).toSet()
        : {project.clipTrackById(anchor.id)!.id};
    // A scope or skip must never split the ownership of linked companions.
    void linkedClosure(Set<String> ids) {
      var changed = true;
      while (changed) {
        final groups = project.tracks
            .where((t) => ids.contains(t.id))
            .expand((t) => t.clips)
            .map((c) => c.timelineGroupId)
            .toSet();
        changed = false;
        for (final track in project.tracks) {
          if (track.clips.any((c) => groups.contains(c.timelineGroupId))) {
            changed = ids.add(track.id) || changed;
          }
        }
      }
    }

    if (scope == 'main_track_only') linkedClosure(selected);
    final locked = project.tracks
        .where((t) => selected.contains(t.id) && t.isLocked)
        .toList();
    if (locked.isNotEmpty && lockedTracks == 'fail') {
      throw CommandError(
        'placement_conflict',
        'Há camadas bloqueadas no escopo; nenhuma alteração foi iniciada.',
        {
          ...PlacementConflict(
            cause: PlacementConflictCause.lockedTrack,
            clipIds: locked.expand((t) => t.clips).map((c) => c.id).toList(),
            trackIds: locked.map((t) => t.id).toList(),
            start: Duration.zero,
            end: project.timelineDuration,
            suggestion:
                'Desbloqueie as camadas listadas ou use locked_tracks="skip"|"unlock" explicitamente.',
          ).toJson(),
          'locked_track_ids': locked.map((t) => t.id).toList(),
          'locked_tracks': [
            for (final t in locked) {'id': t.id, 'name': t.name},
          ],
        },
      );
    }
    final skipped = <String>{};
    if (lockedTracks == 'skip') {
      skipped.addAll(locked.map((t) => t.id));
      linkedClosure(skipped);
      selected.removeAll(skipped);
    }
    if (!selected.contains(project.clipTrackById(anchor.id)!.id)) {
      throw CommandError(
        'placement_conflict',
        'O clipe principal ou um vínculo está em camada ignorada.',
        {
          ...PlacementConflict(
            cause: PlacementConflictCause.linkedGroup,
            clipIds: [anchor.id],
            trackIds: skipped.toList(),
            groupIds: [anchor.timelineGroupId],
            start: anchor.timelineStart,
            end: anchor.timelineEnd,
            suggestion:
                'Use locked_tracks="unlock" ou desbloqueie todas as camadas do grupo A/V.',
          ).toJson(),
          'skipped_track_ids': skipped.toList(),
        },
      );
    }
    return RemapSelection(
      selected,
      skipped,
      lockedTracks == 'unlock' ? locked.map((t) => t.id).toSet() : {},
    );
  }

  TimelineRemapResult apply(
    TgiProject original,
    Clip anchor,
    TimelineTimeMap map, {
    String scope = 'all_tracks',
    String lockedTracks = 'fail',
    int joinFadeMs = 0,
  }) {
    if (joinFadeMs < 0 || joinFadeMs > 100) {
      throw const CommandError('out_of_range', 'join_fade_ms deve ser 0..100.');
    }
    final selection = preflight(
      original,
      anchor,
      scope: scope,
      lockedTracks: lockedTracks,
    );
    if (map.removed.isEmpty) {
      return TimelineRemapResult(original, map, selection, scope);
    }
    final all = original.tracks.expand((t) => t.clips).toList();
    final clipIds = all.map((c) => c.id).toSet();
    final groupIds = all.map((c) => c.timelineGroupId).toSet();
    final groupPieces = <(String, int), String>{};
    final usedGroups = <String>{};
    final lineage = <String, String>{};
    final reversedGroups = all
        .where((c) => c.trackType == TrackType.video && c.reverseVideo)
        .map((c) => c.timelineGroupId)
        .toSet();
    String unique(String base, Set<String> used) {
      var value = base, n = 1;
      while (!used.add(value)) {
        value = '${base}_${n++}';
      }
      return value;
    }

    String group(Clip clip, int segment) =>
        groupPieces.putIfAbsent((clip.timelineGroupId, segment), () {
          if (usedGroups.add(clip.timelineGroupId)) return clip.timelineGroupId;
          return unique('${clip.timelineGroupId}_silence_$segment', groupIds);
        });
    // Reserve groups in timeline order even when an early companion is unchanged.
    for (var i = 0; i < map.retained.length; i++) {
      final r = map.retained[i];
      for (final clip in all) {
        if ((clip.trackType == TrackType.video ||
                clip.trackType == TrackType.audio) &&
            clip.timelineStart.inMicroseconds < r.$2 &&
            clip.timelineEnd.inMicroseconds > r.$1) {
          group(clip, i);
        }
      }
    }
    final tracks = <Track>[];
    for (final track in original.tracks) {
      if (!selection.tracks.contains(track.id)) {
        tracks.add(track);
        continue;
      }
      final output = <Clip>[];
      for (final clip in track.clips) {
        final start = clip.timelineStart.inMicroseconds,
            end = clip.timelineEnd.inMicroseconds;
        final pieces = <(int, int, int)>[];
        for (var i = 0; i < map.retained.length; i++) {
          final r = map.retained[i],
              a = math.max(start, r.$1),
              b = math.min(end, r.$2);
          if (b > a) pieces.add((a, b, i));
        }
        if (pieces.isEmpty) continue;
        final media =
            clip.trackType == TrackType.video ||
            clip.trackType == TrackType.audio;
        if (!media) {
          final nextStart = map.map(start), duration = map.map(end) - nextStart;
          final next =
              nextStart == start && duration == clip.duration.inMicroseconds
              ? clip
              : clip.copyWith(
                  timelineStart: Duration(microseconds: nextStart),
                  duration: Duration(microseconds: duration),
                  sourceDuration: Duration(microseconds: duration),
                  keyframes: duration == clip.duration.inMicroseconds
                      ? clip.keyframes
                      : _keyframes(clip, pieces, map, nextStart, duration),
                  fadeIn: Duration(
                    microseconds:
                        (map.map(start + clip.fadeIn.inMicroseconds) -
                                nextStart)
                            .clamp(0, duration),
                  ),
                  fadeOut: Duration(
                    microseconds:
                        (map.map(end) -
                                map.map(end - clip.fadeOut.inMicroseconds))
                            .clamp(0, duration),
                  ),
                );
          output.add(next);
          lineage[next.id] = clip.id;
          continue;
        }
        for (var i = 0; i < pieces.length; i++) {
          final piece = pieces[i], a = piece.$1, b = piece.$2;
          final id = i == 0
              ? clip.id
              : unique('${clip.id}_silence_$i', clipIds);
          final nextStart = map.map(a), duration = b - a;
          int sourceOffset(int at) => at == end
              ? clip.effectiveSourceDuration.inMicroseconds
              : ((at - start) * clip.playbackSpeed).round().clamp(
                  0,
                  clip.effectiveSourceDuration.inMicroseconds,
                );
          final from = sourceOffset(a), to = sourceOffset(b);
          final reversed =
              clip.reverseVideo ||
              reversedGroups.contains(clip.timelineGroupId);
          final unchanged = pieces.length == 1 && a == start && b == end;
          final next = unchanged && nextStart == start
              ? clip
              : clip.copyWith(
                  id: id,
                  timelineGroupId: group(clip, piece.$3),
                  timelineStart: Duration(microseconds: nextStart),
                  duration: Duration(microseconds: duration),
                  sourceStart: unchanged
                      ? clip.sourceStart
                      : Duration(
                          microseconds: reversed
                              ? clip.sourceEnd.inMicroseconds - to
                              : clip.sourceStart.inMicroseconds + from,
                        ),
                  sourceDuration: unchanged
                      ? clip.sourceDuration
                      : Duration(microseconds: to - from),
                  keyframes: unchanged
                      ? clip.keyframes
                      : _keyframes(clip, [piece], map, nextStart, duration),
                  fadeIn: Duration(
                    microseconds:
                        (math.min(b, start + clip.fadeIn.inMicroseconds) - a)
                            .clamp(0, duration)
                            .toInt(),
                  ),
                  fadeOut: Duration(
                    microseconds:
                        (b - math.max(a, end - clip.fadeOut.inMicroseconds))
                            .clamp(0, duration)
                            .toInt(),
                  ),
                );
          // Only audio: v14 shares fade fields with visual opacity fades.
          // An edge is a new join only when audio survives on both sides.
          final joinIn = map.removed.any((r) => r.$2 == a && r.$1 > 0);
          final joinOut = map.removed.any((r) => r.$1 == b && r.$2 < map.end);
          final fade = math.min(joinFadeMs * 1000, duration ~/ 2);
          output.add(
            clip.trackType == TrackType.audio && fade > 0
                ? next.copyWith(
                    fadeIn: Duration(
                      microseconds: math.max(
                        next.fadeIn.inMicroseconds,
                        joinIn ? fade : 0,
                      ),
                    ),
                    fadeOut: Duration(
                      microseconds: math.max(
                        next.fadeOut.inMicroseconds,
                        joinOut ? fade : 0,
                      ),
                    ),
                  )
                : next,
          );
          lineage[id] = clip.id;
        }
      }
      output.sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
      tracks.add(
        track.copyWith(
          clips: output,
          isLocked: selection.unlocked.contains(track.id)
              ? false
              : track.isLocked,
        ),
      );
    }
    final next = original.copyWith(
      tracks: tracks,
      markers: [
        for (final marker in original.markers)
          marker.copyWith(
            position: Duration(
              microseconds: map.map(marker.position.inMicroseconds),
            ),
          ),
      ],
      transitions: [
        for (final t in original.transitions)
          if (map.map(t.timelineEnd.inMicroseconds) >
              map.map(t.timelineStart.inMicroseconds))
            _transition(t, map),
      ],
      updatedAt: DateTime.now(),
    );
    _validate(original, next, lineage);
    return TimelineRemapResult(next, map, selection, scope);
  }

  TimelineTransition _transition(TimelineTransition t, TimelineTimeMap map) {
    final start = map.map(t.timelineStart.inMicroseconds);
    final duration = map.map(t.timelineEnd.inMicroseconds) - start;
    return t.copyWith(
      duration: Duration(microseconds: duration),
      timelinePosition: Duration(
        microseconds: t.placement == TimelineTransitionPlacement.start
            ? start
            : start + duration ~/ 2,
      ),
    );
  }

  List<ClipKeyframe> _keyframes(
    Clip clip,
    List<(int, int, int)> pieces,
    TimelineTimeMap map,
    int start,
    int duration,
  ) {
    if (clip.keyframes.isEmpty) return clip.keyframes;
    final result = <ClipKeyframe>[];
    final oldStart = clip.timelineStart.inMicroseconds,
        oldDuration = clip.duration.inMicroseconds;
    var counter = 0;
    for (final property in clip.keyframes.map((k) => k.property).toSet()) {
      final samples = <(int, double, String)>[];
      for (final p in pieces) {
        double value(int at) =>
            clip.keyframedValue(property, (at - oldStart) / oldDuration);
        samples.add((
          map.map(p.$1) - start,
          value(p.$1),
          '${clip.id}_remap_${start}_${counter++}',
        ));
        for (final key in clip.keyframesFor(property)) {
          final at = oldStart + (key.time * oldDuration).round();
          if (at > p.$1 && at < p.$2) {
            samples.add((map.map(at) - start, key.value, key.id));
          }
        }
        samples.add((
          map.map(p.$2) - start,
          value(p.$2),
          '${clip.id}_remap_${start}_${counter++}',
        ));
      }
      final resolved = <(int, double, String)>[];
      for (final sample in samples) {
        if (resolved.isNotEmpty && sample.$1 == resolved.last.$1) {
          final left = resolved.removeLast();
          // v14 linear curves express a cut discontinuity with a 1µs step.
          if (left.$1 > 0 &&
              (resolved.isEmpty || resolved.last.$1 < left.$1 - 1)) {
            resolved.add((left.$1 - 1, left.$2, left.$3));
          }
        }
        resolved.add(sample);
      }
      result.addAll(
        resolved.map(
          (s) => ClipKeyframe(
            id: s.$3,
            property: property,
            time: s.$1 / duration,
            value: s.$2,
          ),
        ),
      );
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  void _validate(
    TgiProject before,
    TgiProject after,
    Map<String, String> lineage,
  ) {
    for (final track in after.tracks) {
      for (var i = 0; i < track.clips.length; i++) {
        final a = track.clips[i];
        for (var j = i + 1; j < track.clips.length; j++) {
          final b = track.clips[j];
          if (b.timelineStart >= a.timelineEnd) break;
          if (a.timelineStart >= b.timelineEnd) continue;
          final oldA = before.clipById(lineage[a.id] ?? a.id)!,
              oldB = before.clipById(lineage[b.id] ?? b.id)!;
          if (oldA.id != oldB.id &&
              oldA.timelineStart < oldB.timelineEnd &&
              oldB.timelineStart < oldA.timelineEnd) {
            continue;
          }
          throw CommandError(
            'placement_conflict',
            'O remapeamento criaria uma nova sobreposição.',
            PlacementConflict(
              cause: PlacementConflictCause.overlap,
              clipIds: [a.id, b.id],
              trackIds: [track.id],
              start: b.timelineStart,
              end: a.timelineEnd < b.timelineEnd
                  ? a.timelineEnd
                  : b.timelineEnd,
              suggestion:
                  'Revise os intervalos e os vínculos da camada antes de aplicar.',
            ).toJson(),
          );
        }
      }
    }
  }
}
