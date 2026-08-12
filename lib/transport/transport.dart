import 'package:nostr/nostr.dart';

/// The single door through which envelopes reach the outside world. No
/// other code may talk to a relay directly.
abstract class Transport {
  /// Submits a signed envelope event, returning its event id once the
  /// relay has accepted it. Throws if the relay rejects it or the
  /// submission fails.
  Future<String> submitEnvelope(Event event);

  /// Queries envelopes matching [filter].
  Future<List<Event>> queryEnvelopes(Filter filter);
}
