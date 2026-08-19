// Flutter-free parser for the app's own export ("points": [...]), so
// tool/match_trip.dart can run under plain `dart run`. Mirrors
// trackPointsFromPoints: speed is m/s in storage, km/h in the engine.
// Temporary: drop this once lib/models/trip.dart no longer imports Flutter.
import 'dart:convert';

import 'package:ringring_logger/quill/track_point.dart';

List<TrackPoint> parsePointsExport(String jsonStr) {
  final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
  final raw = (decoded['points'] ?? decoded['details']) as List?;
  if (raw == null) {
    throw const FormatException('Geen "points" of "details" in dit bestand.');
  }
  return raw.map((e) {
    final j = e as Map<String, dynamic>;
    return TrackPoint(
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      speedKmh: (j['speed'] as num).toDouble() * 3.6,
      date: DateTime.parse(j['date'] as String),
    );
  }).toList();
}
