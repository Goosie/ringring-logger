/// All tunable values for the "Delen" (envelope publication) flow live
/// here, and only here. Changing a value must change app behavior without
/// any other code edits.
class RingRingConfig {
  const RingRingConfig._();

  /// Geohash length used to cut a trip into segments.
  static const int geohashPrecisie = 7;

  /// Route distance (meters) trimmed off the start and end of a trip
  /// before segmentation, measured along consecutive GPS fixes.
  static const double trimAfstandMeter = 300;

  /// Segments with fewer GPS fixes than this are dropped entirely.
  static const int minSamplesPerSegment = 30;

  /// Envelopes only ever carry a day-level date, never a timestamp.
  static const String tijdResolutie = 'dag';

  /// Upper bound (seconds) for the random per-envelope delay used by
  /// "Post alle (gespreid)".
  static const int postDelayMaxSec = 30;

  static const String relayUrl = 'wss://relay.goosielabs.com';

  /// Nostr event kind used for envelopes.
  static const int eventKind = 4451;

  /// Envelope schema version, carried in the `v` tag.
  static const String envelopVersie = '1';

  /// Segments with fewer samples than this get a "laag verkeer — hoger
  /// risico" warning in the UI. This is a risk label only, not a filter —
  /// segments still get posted.
  static const int laagVerkeerDrempel = 60;
}
