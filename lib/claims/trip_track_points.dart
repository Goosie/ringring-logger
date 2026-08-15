import '../models/trip.dart';
import '../quill/track_point.dart';

/// Adapts a list of the app's own [TripPoint]s (speed in m/s) into the
/// format-agnostic [TrackPoint] the quill engine expects.
List<TrackPoint> trackPointsFromPoints(List<TripPoint> points) => points
    .map((p) => TrackPoint(lat: p.lat, lng: p.lng, speedKmh: p.speed * 3.6, date: p.date))
    .toList();

/// Adapts a whole [Trip] (points, speed in m/s) into the format-agnostic
/// [TrackPoint] the quill engine expects. The other input path — legacy
/// Ring-Ring "details" exports — has its own adapter in
/// lib/legacy/legacy_trip_format.dart; the two never merge into one format
/// upstream of this point on purpose, since only Trip carries the fields
/// (declaredModality etc.) the rest of the app needs.
List<TrackPoint> trackPointsFromTrip(Trip trip) => trackPointsFromPoints(trip.points);
