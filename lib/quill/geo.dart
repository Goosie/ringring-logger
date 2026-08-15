import 'dart:math' as math;

import 'registry.dart';

double haversineM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Shortest distance (meters) from (lat, lng) to the polyline [coords],
/// via an equirectangular projection local to each segment — accurate
/// enough at the sub-city scale a corridor registry covers.
double distanceToPolylineM(double lat, double lng, List<LatLng> coords) {
  if (coords.isEmpty) return double.infinity;
  if (coords.length == 1) return haversineM(lat, lng, coords[0].lat, coords[0].lng);
  var best = double.infinity;
  for (var i = 0; i < coords.length - 1; i++) {
    final d = _distanceToSegmentM(lat, lng, coords[i].lat, coords[i].lng, coords[i + 1].lat, coords[i + 1].lng);
    if (d < best) best = d;
  }
  return best;
}

double _distanceToSegmentM(
  double plat,
  double plng,
  double alat,
  double alng,
  double blat,
  double blng,
) {
  final refLat = (alat + blat + plat) / 3.0;
  const mPerDegLat = 111320.0;
  final mPerDegLng = 111320.0 * math.cos(_rad(refLat));

  double x(double lng) => lng * mPerDegLng;
  double y(double lat) => lat * mPerDegLat;

  final ax = x(alng), ay = y(alat);
  final bx = x(blng), by = y(blat);
  final px = x(plng), py = y(plat);

  final dx = bx - ax, dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  var t = lenSq > 0 ? ((px - ax) * dx + (py - ay) * dy) / lenSq : 0.0;
  t = t.clamp(0.0, 1.0);

  final projX = ax + t * dx, projY = ay + t * dy;
  final ddx = px - projX, ddy = py - projY;
  return math.sqrt(ddx * ddx + ddy * ddy);
}

double _rad(double deg) => deg * math.pi / 180.0;
