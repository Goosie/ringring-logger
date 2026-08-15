import 'geo.dart';
import 'matcher.dart';
import 'params.dart';
import 'registry.dart';
import 'track_point.dart';

/// A privacy-scrubbed claim for one corridor traversal. Deliberately
/// carries no coordinates and no point ordering — only what the claim
/// schema needs. [CorridorClaim.toJson] is the contract; the "no lat/lng
/// anywhere" test in test/quill/ asserts against that serialized form.
class CorridorClaim {
  CorridorClaim({
    required this.corridorId,
    required this.registryVersion,
    required this.date,
    required this.hourBucket,
    required this.modality,
    required this.v85,
    required this.sampleCount,
  });

  final String corridorId;
  final String registryVersion;

  /// yyyy-MM-dd, local time.
  final String date;

  /// 0-23, local time, from the traversal's start.
  final int hourBucket;

  /// "bike" or "other" — see [classifyModality].
  final String modality;

  /// 85th percentile of point speeds in km/h, 1 decimal.
  final double v85;

  final int sampleCount;

  Map<String, dynamic> toJson() => {
        'corridorId': corridorId,
        'registryVersion': registryVersion,
        'date': date,
        'hourBucket': hourBucket,
        'modality': modality,
        'v85': v85,
        'sampleCount': sampleCount,
      };

  factory CorridorClaim.fromJson(Map<String, dynamic> j) => CorridorClaim(
        corridorId: j['corridorId'] as String,
        registryVersion: j['registryVersion'] as String,
        date: j['date'] as String,
        hourBucket: j['hourBucket'] as int,
        modality: j['modality'] as String,
        v85: (j['v85'] as num).toDouble(),
        sampleCount: j['sampleCount'] as int,
      );
}

/// Turns matched [traversals] into claims, dropping any traversal that's
/// too thin to say anything useful about its corridor. Output is sorted
/// alphabetically by corridorId — never by traversal/visit order, since
/// that order is itself information the claim set must not carry.
List<CorridorClaim> deriveClaims(List<CorridorTraversal> traversals, Registry registry) {
  final claims = <CorridorClaim>[];

  for (final t in traversals) {
    final corridor = registry.corridorById(t.corridorId);
    if (corridor == null || t.points.isEmpty) continue;

    final coveredM = _traversalLengthM(t.points);
    final coverageOk = corridor.lengthM > 0 && (coveredM / corridor.lengthM) >= QuillParams.minCoverageFraction;
    final countOk = t.points.length >= QuillParams.minMatchedPoints;
    if (!coverageOk && !countOk) continue;

    final sorted = [...t.points]..sort((a, b) => a.date.compareTo(b.date));
    final local = sorted.first.date.toLocal();

    claims.add(CorridorClaim(
      corridorId: t.corridorId,
      registryVersion: registry.version,
      date: _dateLabel(local),
      hourBucket: local.hour,
      modality: classifyModality(sorted),
      v85: double.parse(_percentile(sorted.map((p) => p.speedKmh).toList(), 0.85).toStringAsFixed(1)),
      sampleCount: t.points.length,
    ));
  }

  claims.sort((a, b) => a.corridorId.compareTo(b.corridorId));
  return claims;
}

/// Modality for one traversal, from its own points only (see the "per
/// traversal" scope decision — a trip that switches from bike to walk
/// mid-route must not tag every claim with one trip-wide modality).
///
/// Bucket the traversal's points into non-overlapping
/// [QuillParams.rollingWindowSeconds] windows (elapsed time from the
/// traversal's first point), take the median speed per window, classify
/// each window "bike" when its median falls in
/// [QuillParams.bikeMinKmh, QuillParams.bikeMaxKmh) — else "other" — and
/// let the windows vote (ties go to "bike"). This is a coarse speed-only
/// proxy, not the sensor-based classifier described in the app's README;
/// revise the band in params.dart if it disagrees with declared ground
/// truth from testdata/trips/.
String classifyModality(List<TrackPoint> sortedPoints) {
  final windows = _bucketedMedianSpeeds(sortedPoints, QuillParams.rollingWindowSeconds);
  var bikeVotes = 0;
  var otherVotes = 0;
  for (final median in windows) {
    if (median >= QuillParams.bikeMinKmh && median < QuillParams.bikeMaxKmh) {
      bikeVotes++;
    } else {
      otherVotes++;
    }
  }
  return bikeVotes >= otherVotes ? 'bike' : 'other';
}

List<double> _bucketedMedianSpeeds(List<TrackPoint> sortedPoints, int windowSeconds) {
  if (sortedPoints.isEmpty) return const [];
  final start = sortedPoints.first.date;
  final buckets = <int, List<double>>{};
  for (final p in sortedPoints) {
    final index = p.date.difference(start).inSeconds ~/ windowSeconds;
    buckets.putIfAbsent(index, () => []).add(p.speedKmh);
  }
  return buckets.values.map(_median).toList();
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

/// Linear-interpolation percentile (0 <= fraction <= 1) over [values].
double _percentile(List<double> values, double fraction) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  if (sorted.length == 1) return sorted.first;
  final rank = fraction * (sorted.length - 1);
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return sorted[lower];
  final frac = rank - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * frac;
}

double _traversalLengthM(List<TrackPoint> points) {
  final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
  var meters = 0.0;
  for (var i = 1; i < sorted.length; i++) {
    meters += haversineM(sorted[i - 1].lat, sorted[i - 1].lng, sorted[i].lat, sorted[i].lng);
  }
  return meters;
}

String _dateLabel(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}
