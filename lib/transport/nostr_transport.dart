import 'dart:async';
import 'dart:convert';

import 'package:nostr/nostr.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../ringring_config.dart';
import 'transport.dart';

/// The one and only [Transport] implementation: a single relay reached
/// over a plain Nostr websocket.
class NostrTransport implements Transport {
  NostrTransport({String? relayUrl}) : relayUrl = relayUrl ?? RingRingConfig.relayUrl;

  final String relayUrl;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<String> submitEnvelope(Event event) async {
    final channel = WebSocketChannel.connect(Uri.parse(relayUrl));
    final completer = Completer<String>();
    final sub = channel.stream.listen(
      (raw) {
        final data = jsonDecode(raw as String);
        if (data is! List || data.length < 3) return;
        if (data[0] != 'OK' || data[1] != event.id) return;
        if (completer.isCompleted) return;
        if (data[2] == true) {
          completer.complete(event.id);
        } else {
          final reason = data.length > 3 ? data[3] : 'geweigerd';
          completer.completeError(Exception('Relay weigerde envelop: $reason'));
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Relayverbinding gesloten zonder antwoord'));
        }
      },
    );
    try {
      await channel.ready;
      channel.sink.add(event.serialize());
      return await completer.future.timeout(_timeout);
    } finally {
      await sub.cancel();
      unawaited(channel.sink.close());
    }
  }

  @override
  Future<List<Event>> queryEnvelopes(Filter filter) async {
    final channel = WebSocketChannel.connect(Uri.parse(relayUrl));
    final events = <Event>[];
    final subId = generateRandomHex(bytes: 8);
    final completer = Completer<void>();
    final sub = channel.stream.listen(
      (raw) {
        final data = jsonDecode(raw as String);
        if (data is! List || data.isEmpty) return;
        if (data[0] == 'EVENT' && data.length >= 3 && data[1] == subId) {
          events.add(Event.fromMap(data[2] as Map<String, dynamic>));
        } else if (data[0] == 'EOSE' && data.length >= 2 && data[1] == subId) {
          if (!completer.isCompleted) completer.complete();
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
    try {
      await channel.ready;
      final request = Request(subscriptionId: subId, filters: [filter]);
      channel.sink.add(request.serialize());
      await completer.future.timeout(_timeout);
      return events;
    } finally {
      await sub.cancel();
      unawaited(channel.sink.close());
    }
  }
}
