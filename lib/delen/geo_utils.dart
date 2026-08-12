import 'dart:math' as math;

import '../models/trip.dart';

double haversineMeters(TripPoint a, TripPoint b) {
  const r = 6371000.0;
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lng - a.lng);
  final sa = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(sa), math.sqrt(1 - sa));
}

double _rad(double deg) => deg * math.pi / 180.0;

/// Drops the fixes within [meters] of the trip's start and end, measured
/// along the route (cumulative point-to-point distance). Returns an empty
/// list when the whole route is shorter than 2x [meters].
List<TripPoint> trimRouteEnds(List<TripPoint> points, double meters) {
  if (points.length < 2) return const [];

  var startIdx = points.length;
  var acc = 0.0;
  for (var i = 1; i < points.length; i++) {
    acc += haversineMeters(points[i - 1], points[i]);
    if (acc >= meters) {
      startIdx = i;
      break;
    }
  }

  var endIdx = -1;
  acc = 0.0;
  for (var i = points.length - 2; i >= 0; i--) {
    acc += haversineMeters(points[i + 1], points[i]);
    if (acc >= meters) {
      endIdx = i;
      break;
    }
  }

  if (startIdx > endIdx) return const [];
  return points.sublist(startIdx, endIdx + 1);
}
