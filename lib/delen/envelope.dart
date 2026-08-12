import '../ringring_config.dart';

enum EnvelopeStatus { pending, posting, posted, failed }

/// A single derived, privacy-scrubbed measurement for one geohash segment
/// of a trip. Never carries raw lat/lon or the raw samples array — only
/// what's needed to build the envelope's content JSON.
class Envelope {
  Envelope({
    required this.geohash,
    required this.day,
    required this.roughness,
    required this.speedKmh,
    required this.samples,
  }) : status = EnvelopeStatus.pending;

  final String geohash;

  /// UTC midnight of the trip day this segment belongs to.
  final DateTime day;

  final double roughness;
  final double speedKmh;
  final int samples;

  EnvelopeStatus status;
  String? eventId;
  String? error;

  bool get isLowTraffic => samples < RingRingConfig.laagVerkeerDrempel;

  String get dayLabel {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }
}
