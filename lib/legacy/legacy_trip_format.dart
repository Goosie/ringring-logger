import 'dart:convert';

import '../quill/track_point.dart';

/// Parses the legacy Ring-Ring export shape: a top-level object with a
/// "details" array of {lat, lng, speed, date}, `speed` in m/s — same
/// convention as the current app's own export (see README). Converted to
/// km/h here since that's what the quill engine and claim schema expect.
///
/// Pure dart, no Flutter imports: shared by tool/match_trip.dart (which
/// runs under plain `dart run`) and the app's debug "Import trip JSON"
/// action, so the parsing logic exists exactly once.
List<TrackPoint> parseLegacyDetails(String jsonStr) {
  final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
  final details = decoded['details'] as List;
  return details.map((raw) {
    final j = raw as Map<String, dynamic>;
    return TrackPoint(
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      speedKmh: (j['speed'] as num).toDouble() * 3.6,
      date: DateTime.parse(j['date'] as String),
    );
  }).toList();
}
