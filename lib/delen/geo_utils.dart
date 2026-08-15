import '../quill/geo.dart';
import '../quill/track_point.dart';

/// Drops the fixes within [meters] of the trip's start and end, measured
/// along the route (cumulative point-to-point distance). Returns an empty
/// list when the whole route is shorter than 2x [meters].
List<TrackPoint> trimRouteEnds(List<TrackPoint> points, double meters) {
  if (points.length < 2) return const [];

  double dist(TrackPoint a, TrackPoint b) => haversineM(a.lat, a.lng, b.lat, b.lng);

  var startIdx = points.length;
  var acc = 0.0;
  for (var i = 1; i < points.length; i++) {
    acc += dist(points[i - 1], points[i]);
    if (acc >= meters) {
      startIdx = i;
      break;
    }
  }

  var endIdx = -1;
  acc = 0.0;
  for (var i = points.length - 2; i >= 0; i--) {
    acc += dist(points[i + 1], points[i]);
    if (acc >= meters) {
      endIdx = i;
      break;
    }
  }

  if (startIdx > endIdx) return const [];
  return points.sublist(startIdx, endIdx + 1);
}
