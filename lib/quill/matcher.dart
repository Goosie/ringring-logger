import 'geo.dart';
import 'params.dart';
import 'registry.dart';
import 'track_point.dart';

/// A run of consecutive points snapped to the same corridor. Internal to
/// quill — carries coordinates and point order, unlike [CorridorClaim]
/// which must carry neither. Never serialized as-is.
class CorridorTraversal {
  CorridorTraversal({required this.corridorId, required this.points});

  final String corridorId;
  final List<TrackPoint> points;
}

/// Matches [points] against [registry]: each point snaps to the nearest
/// corridor polyline within [QuillParams.snapToleranceM], preferring the
/// previous point's corridor when it's still within tolerance (continuity/
/// stickiness rule — deliberately no HMM). Points that snap to nothing
/// close a run without starting a new one. Consecutive points on the same
/// corridor form one [CorridorTraversal].
List<CorridorTraversal> matchTrip(List<TrackPoint> points, Registry registry) {
  final traversals = <CorridorTraversal>[];

  String? currentCorridor;
  var currentPoints = <TrackPoint>[];
  String? prevCorridor;

  void closeRun() {
    if (currentCorridor != null && currentPoints.isNotEmpty) {
      traversals.add(CorridorTraversal(corridorId: currentCorridor!, points: currentPoints));
    }
    currentCorridor = null;
    currentPoints = [];
  }

  for (final p in points) {
    final snapped = _snap(p, registry, prevCorridor);
    if (snapped == null) {
      closeRun();
      prevCorridor = null;
      continue;
    }
    if (snapped != currentCorridor) {
      closeRun();
      currentCorridor = snapped;
    }
    currentPoints.add(p);
    prevCorridor = snapped;
  }
  closeRun();

  return traversals;
}

String? _snap(TrackPoint p, Registry registry, String? prevCorridorId) {
  if (prevCorridorId != null) {
    final prev = registry.corridorById(prevCorridorId);
    if (prev != null) {
      final d = distanceToPolylineM(p.lat, p.lng, prev.coords);
      if (d <= QuillParams.snapToleranceM) return prevCorridorId;
    }
  }

  String? bestId;
  var bestDist = double.infinity;
  for (final c in registry.corridors) {
    final d = distanceToPolylineM(p.lat, p.lng, c.coords);
    if (d < bestDist) {
      bestDist = d;
      bestId = c.id;
    }
  }
  return (bestId != null && bestDist <= QuillParams.snapToleranceM) ? bestId : null;
}
