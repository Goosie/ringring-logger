/// All tunable values for the "Delen" (envelope publication) flow live
/// here, and only here. Changing a value must change app behavior without
/// any other code edits.
class RingRingConfig {
  const RingRingConfig._();

  /// Route distance (meters) trimmed off the start and end of a trip
  /// before corridor-matching for publication, measured along consecutive
  /// GPS fixes. Keeps claims near home/work — the two points that identify
  /// a person fastest — out of what gets sent at all. Segment-level
  /// thresholds (min samples/coverage) live in QuillParams; this is a
  /// publish-flow privacy concern, not a map-matching one.
  static const double trimAfstandMeter = 300;

  /// Envelopes only ever carry a day-level date, never a timestamp.
  static const String tijdResolutie = 'dag';

  /// Upper bound (seconds) for the random per-envelope delay used by
  /// "Post alle (gespreid)".
  static const int postDelayMaxSec = 30;

  /// Relays that envelopes are submitted to and queried from. Fase 1 talks
  /// to exactly one; add entries here to reach more later — NostrTransport
  /// fans out to every relay in this list without needing code changes.
  static const List<String> relayUrls = ['wss://relay.goosielabs.com'];

  /// Nostr event kind used for envelopes.
  static const int eventKind = 4451;

  /// Envelope schema version, carried in the `v` tag.
  static const String envelopVersie = '1';

  /// The gift wrap's recipient (NIP-59 `p` tag) — the "Ring-Ring address".
  /// This is a fresh, throwaway TEST keypair generated for this phase, not
  /// the eventual production identity (that's still an open governance
  /// question — see the Stamp Office discussion). Hex-encoded pubkey;
  /// corresponding nsec was shared with Perry directly, never committed.
  static const String recipientPubkey =
      '419f5d9b4e1a79a5d893bfdc7a57abed9b183381c0f01452ec6fa56c637d6c8c';

  /// Segments with fewer samples than this get a "laag verkeer — hoger
  /// risico" warning in the UI. This is a risk label only, not a filter —
  /// segments still get posted.
  static const int laagVerkeerDrempel = 60;
}
