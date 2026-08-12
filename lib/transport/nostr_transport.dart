import 'dart:async';
import 'dart:convert';

import 'package:nostr/nostr.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../ringring_config.dart';
import 'transport.dart';

/// The one and only [Transport] implementation. Fans out to every relay in
/// [relayUrls] (just [RingRingConfig.relayUrls] by default) over plain
/// Nostr websockets — adding a relay later is a config change, not a code
/// change.
class NostrTransport implements Transport {
  NostrTransport({List<String>? relayUrls})
      : relayUrls = relayUrls ?? RingRingConfig.relayUrls;

  final List<String> relayUrls;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<String> submitEnvelope(Event event) async {
    final errors = <String>[];
    final results = await Future.wait(relayUrls.map((url) async {
      try {
        await _submitToRelay(url, event);
        return true;
      } catch (e) {
        errors.add('$url: $e');
        return false;
      }
    }));
    if (results.any((ok) => ok)) return event.id;
    throw Exception('Geen enkele relay accepteerde de envelop:\n${errors.join('\n')}');
  }

  @override
  Future<List<Event>> queryEnvelopes(Filter filter) async {
    final errors = <String>[];
    final merged = <String, Event>{};
    await Future.wait(relayUrls.map((url) async {
      try {
        final events = await _queryRelay(url, filter);
        for (final e in events) {
          merged[e.id] = e;
        }
      } catch (e) {
        errors.add('$url: $e');
      }
    }));
    if (merged.isEmpty && errors.isNotEmpty && errors.length == relayUrls.length) {
      throw Exception('Geen enkele relay bereikbaar:\n${errors.join('\n')}');
    }
    return merged.values.toList();
  }

  Future<void> _submitToRelay(String relayUrl, Event event) async {
    final channel = WebSocketChannel.connect(Uri.parse(relayUrl));
    final completer = Completer<void>();
    final sub = channel.stream.listen(
      (raw) {
        final data = jsonDecode(raw as String);
        if (data is! List || data.length < 3) return;
        if (data[0] != 'OK' || data[1] != event.id) return;
        if (completer.isCompleted) return;
        if (data[2] == true) {
          completer.complete();
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
      await completer.future.timeout(_timeout);
    } finally {
      await sub.cancel();
      unawaited(channel.sink.close());
    }
  }

  Future<List<Event>> _queryRelay(String relayUrl, Filter filter) async {
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
