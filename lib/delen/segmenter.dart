import 'dart:math' as math;

import 'package:dart_geohash/dart_geohash.dart';

import '../models/trip.dart';
import '../ringring_config.dart';
import 'envelope.dart';
import 'geo_utils.dart';

/// Cuts a trip into geohash segments and scrubs them per
/// [RingRingConfig]: trims the route ends, drops sparse segments, keeps
/// only day-level dates. The raw trace (lat/lon, timestamps) never leaves
/// this function — only the derived [Envelope] values come out.
List<Envelope> buildEnvelopes(Trip trip) {
  final trimmed = trimRouteEnds(trip.points, RingRingConfig.trimAfstandMeter);
  if (trimmed.isEmpty) return const [];

  final hasher = GeoHasher();
  String hashOf(TripPoint p) =>
      hasher.encode(p.lng, p.lat, precision: RingRingConfig.geohashPrecisie);

  final envelopes = <Envelope>[];
  var runStart = 0;
  var runHash = hashOf(trimmed[0]);

  void closeRun(int endExclusive) {
    final runPoints = trimmed.sublist(runStart, endExclusive);
    if (runPoints.length < RingRingConfig.minSamplesPerSegment) return;
    envelopes.add(_toEnvelope(runHash, runPoints, trip.motion));
  }

  for (var i = 1; i <= trimmed.length; i++) {
    if (i == trimmed.length) {
      closeRun(i);
      break;
    }
    final h = hashOf(trimmed[i]);
    if (h != runHash) {
      closeRun(i);
      runStart = i;
      runHash = h;
    }
  }

  return envelopes;
}

Envelope _toEnvelope(String geohash, List<TripPoint> runPoints, List<MotionSample> motion) {
  final first = runPoints.first.date;
  final last = runPoints.last.date;
  final firstUtc = first.toUtc();
  final day = DateTime.utc(firstUtc.year, firstUtc.month, firstUtc.day);

  final speedKmh =
      runPoints.map((p) => p.speed * 3.6).reduce((a, b) => a + b) / runPoints.length;

  final inRange = motion.where(
    (m) => !m.at.isBefore(first) && !m.at.isAfter(last) && m.accStdG != null,
  );
  var roughness = 0.0;
  var weightedVarSum = 0.0;
  var weightSum = 0.0;
  for (final m in inRange) {
    final w = m.sampleCount > 0 ? m.sampleCount.toDouble() : 1.0;
    weightedVarSum += w * m.accStdG! * m.accStdG!;
    weightSum += w;
  }
  if (weightSum > 0) roughness = math.sqrt(weightedVarSum / weightSum);

  return Envelope(
    geohash: geohash,
    day: day,
    roughness: double.parse(roughness.toStringAsFixed(2)),
    speedKmh: double.parse(speedKmh.toStringAsFixed(1)),
    samples: runPoints.length,
  );
}
