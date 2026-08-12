import 'dart:convert';

import 'package:nostr/nostr.dart';

import '../ringring_config.dart';
import 'attest_provider.dart';
import 'envelope.dart';

/// Builds the signed kind-4451 event for [envelope] using a fresh,
/// disposable [keys] pair. Only geohash + the three content values ever
/// reach the event — never raw coordinates or the raw samples array.
Event buildEnvelopeEvent(Envelope envelope, Keys keys, AttestProvider attest) {
  final (attestType, attestPayload) = attest.createAttest();

  final tags = <List<String>>[
    ['v', RingRingConfig.envelopVersie],
    ['g', envelope.geohash],
    ['t', envelope.dayLabel],
    ['attest', attestType, attestPayload],
  ];

  final content = jsonEncode({
    'roughness': double.parse(envelope.roughness.toStringAsFixed(2)),
    'speed_kmh': double.parse(envelope.speedKmh.toStringAsFixed(1)),
    'samples': envelope.samples,
  });

  return Event.from(
    kind: RingRingConfig.eventKind,
    content: content,
    secretKey: keys.secret,
    createdAt: envelope.day.millisecondsSinceEpoch ~/ 1000,
    tags: tags,
    pubkey: keys.public,
  );
}
