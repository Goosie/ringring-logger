import '../quill/claims.dart';
import '../ringring_config.dart';

enum EnvelopeStatus { pending, posting, posted, failed }

/// Publish-state wrapper around one [CorridorClaim]. The claim itself comes
/// straight from the quill engine (the single source of truth for what a
/// claim contains); this only adds what the DELEN screen needs to track
/// per-claim publish progress.
class Envelope {
  Envelope(this.claim) : status = EnvelopeStatus.pending;

  final CorridorClaim claim;

  EnvelopeStatus status;
  String? eventId;
  String? error;

  bool get isLowTraffic => claim.sampleCount < RingRingConfig.laagVerkeerDrempel;
}
