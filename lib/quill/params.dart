/// All tunable thresholds for the quill corridor-matching engine, kept in
/// one place so revising the model touches exactly this file.
class QuillParams {
  const QuillParams._();

  /// Max distance (meters) from a point to a corridor polyline to count as
  /// a snap.
  static const double snapToleranceM = 25;

  /// A traversal becomes a claim once it covers at least this fraction of
  /// the corridor's length ([Corridor.lengthM])...
  static const double minCoverageFraction = 0.6;

  /// ...OR contains at least this many matched points (whichever the
  /// traversal reaches first).
  static const int minMatchedPoints = 30;

  /// Window (seconds) used to bucket a traversal's points for the
  /// rolling-median speed test that drives modality classification.
  static const int rollingWindowSeconds = 60;

  /// Lower bound (inclusive, km/h) of the speed band classified as "bike".
  static const double bikeMinKmh = 6;

  /// Upper bound (exclusive, km/h) of the speed band classified as "bike".
  static const double bikeMaxKmh = 25;
}
