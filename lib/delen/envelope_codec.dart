import 'dart:convert';

import 'package:nostr/nostr.dart';

import '../ringring_config.dart';
import 'attest_provider.dart';
import 'envelope.dart';

/// Builds the NIP-59 gift-wrapped (kind 1059) event for [envelope], using a
/// fresh, disposable [keys] pair as the claim's author — the pair that
/// authors and seals the rumor, never reused across envelopes. The gift
/// wrap itself gets a second, independent ephemeral key (handled inside
/// [GiftWrap.wrap]) and a randomized `created_at`, so even the outer
/// envelope's signer and timing change every time.
///
/// Only the corridor/hour/modality claim and its derived numbers ever
/// reach the rumor — never raw coordinates or the raw samples array. The
/// rumor is NIP-44-encrypted twice (seal, then wrap) before it ever
/// touches a relay; only whoever holds [RingRingConfig.recipientPubkey]'s
/// secret key can read it.
Future<Event> buildEnvelopeEvent(
  Envelope envelope,
  Keys keys,
  AttestProvider attest,
) async {
  final claim = envelope.claim;
  final (attestType, attestPayload) = attest.createAttest();

  final tags = <List<String>>[
    ['v', RingRingConfig.envelopVersie],
    ['corridor', claim.corridorId],
    ['t', claim.date],
    ['hour', claim.hourBucket.toString().padLeft(2, '0')],
    ['modality', claim.modality],
    ['attest', attestType, attestPayload],
  ];

  final content = jsonEncode({
    'registryVersion': claim.registryVersion,
    'v85': claim.v85,
    'samples': claim.sampleCount,
  });

  final rumor = Event.partial(
    pubkey: keys.public,
    createdAt: DateTime.parse('${claim.date}T00:00:00Z').millisecondsSinceEpoch ~/ 1000,
    kind: RingRingConfig.eventKind,
    tags: tags,
    content: content,
  );

  return GiftWrap.wrap(
    rumor: rumor,
    authorSecretKey: keys.secret,
    recipientPubkey: RingRingConfig.recipientPubkey,
  );
}
