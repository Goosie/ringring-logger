import 'dart:convert';

import '../legacy/legacy_trip_format.dart';
import '../models/trip.dart';
import '../quill/track_point.dart';
import 'trip_track_points.dart';

/// Debug-import entry point: accepts either the app's own current export
/// ("points": [...]) or a legacy Ring-Ring export ("details": [...]),
/// detected by which key is present, and adapts either into [TrackPoint]s
/// for the quill pipeline. Two formats in, one shape out — nothing
/// downstream of this needs to know which one it was.
List<TrackPoint> parseTripJsonForImport(String jsonStr) {
  final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
  if (decoded.containsKey('points')) {
    return trackPointsFromTrip(Trip.fromJson(decoded));
  }
  if (decoded.containsKey('details')) {
    return parseLegacyDetails(jsonStr);
  }
  throw const FormatException('Onbekend trip-formaat: geen "points" of "details" veld gevonden.');
}
