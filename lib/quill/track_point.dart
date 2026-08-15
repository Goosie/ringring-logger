/// A single position fix, format-agnostic: the app's own [Trip] model and
/// the legacy Ring-Ring "details" export both get adapted into this before
/// reaching the quill engine. Nothing under lib/quill/ depends on either
/// source format directly.
class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.date,
  });

  final double lat;
  final double lng;
  final double speedKmh;
  final DateTime date;
}
