import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nostr/nostr.dart';

import '../models/trip.dart';
import '../ringring_config.dart';
import '../transport/nostr_transport.dart';
import '../transport/transport.dart';
import '../widgets/big_button.dart';
import 'attest_provider.dart';
import 'envelope.dart';
import 'envelope_codec.dart';
import 'segmenter.dart';

/// Stap 1 (knip + schrob) -> stap 2 (per envelop of gespreid posten) ->
/// stap 3 (statuslijst) van de publicatieflow, allemaal op één scherm zodat
/// elke stap zichtbaar blijft voor de gebruiker.
class DelenScreen extends StatefulWidget {
  const DelenScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<DelenScreen> createState() => _DelenScreenState();
}

class _DelenScreenState extends State<DelenScreen> {
  final Transport _transport = NostrTransport();
  final AttestProvider _attest = NoneAttest();
  final math.Random _rng = math.Random();

  List<Envelope>? _envelopes;
  bool _postingAll = false;

  void _makeEnvelopes() {
    setState(() => _envelopes = buildEnvelopes(widget.trip));
  }

  Future<void> _postOne(Envelope e) async {
    if (e.status == EnvelopeStatus.posting || e.status == EnvelopeStatus.posted) {
      return;
    }
    setState(() {
      e.status = EnvelopeStatus.posting;
      e.error = null;
    });
    try {
      // Vers keypair per envelop; de private key leeft alleen in deze
      // lokale variabele en wordt na signeren nergens bewaard of gelogd.
      final keys = Keys.generate();
      final event = buildEnvelopeEvent(e, keys, _attest);
      final id = await _transport.submitEnvelope(event);
      if (!mounted) return;
      setState(() {
        e.status = EnvelopeStatus.posted;
        e.eventId = id;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        e.status = EnvelopeStatus.failed;
        e.error = '$err';
      });
    }
  }

  Future<void> _postAll() async {
    final envelopes = _envelopes;
    if (envelopes == null || envelopes.isEmpty) return;
    setState(() => _postingAll = true);
    final pending = envelopes.where((e) => e.status == EnvelopeStatus.pending).toList();
    final futures = <Future<void>>[
      for (final e in pending)
        Future.delayed(
          Duration(milliseconds: _rng.nextInt(RingRingConfig.postDelayMaxSec * 1000 + 1)),
          () => _postOne(e),
        ),
    ];
    await Future.wait(futures);
    if (!mounted) return;
    setState(() => _postingAll = false);
  }

  @override
  Widget build(BuildContext context) {
    final envelopes = _envelopes;
    return Scaffold(
      appBar: AppBar(title: const Text('Delen')),
      body: SafeArea(
        child: envelopes == null ? _buildIntro() : _buildList(envelopes),
      ),
    );
  }

  Widget _buildIntro() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Dit knipt de rit in geohash-segmenten, gooit begin en eind weg en '
          'houdt alleen dag-datums aan. De ruwe GPS-trace verlaat het toestel '
          'nooit — alleen de afgeleide waarden per segment worden straks '
          'gepost, elk met een eigen wegwerp-sleutel.',
        ),
        const SizedBox(height: 20),
        BigButton(
          label: 'MAAK ENVELOPPEN',
          icon: Icons.content_cut,
          color: const Color(0xFF00E5A0),
          onPressed: _makeEnvelopes,
        ),
      ],
    );
  }

  Widget _buildList(List<Envelope> envelopes) {
    if (envelopes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Geen bruikbare segmenten (rit te kort, of alle segmenten hebben '
            'te weinig samples).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: BigButton(
            label: _postingAll ? 'BEZIG MET POSTEN...' : 'POST ALLE (GESPREID)',
            icon: Icons.send,
            color: const Color(0xFF00E5A0),
            onPressed: _postingAll ? null : _postAll,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: envelopes.length,
            itemBuilder: (context, i) => _envelopeTile(envelopes[i]),
          ),
        ),
      ],
    );
  }

  Widget _envelopeTile(Envelope e) {
    return Card(
      color: Colors.grey.shade900,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.geohash,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                _statusBadge(e.status),
              ],
            ),
            const SizedBox(height: 6),
            Text('Dag: ${e.dayLabel}', style: TextStyle(color: Colors.grey.shade400)),
            Text('Ruwheid: ${e.roughness.toStringAsFixed(2)}'),
            Text('Snelheid: ${e.speedKmh.toStringAsFixed(1)} km/u'),
            Text('Samples: ${e.samples}'),
            if (e.isLowTraffic)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'laag verkeer — hoger risico',
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                ),
              ),
            if (e.status == EnvelopeStatus.posted && e.eventId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('event: ${e.eventId}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ),
            if (e.status == EnvelopeStatus.failed && e.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(e.error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (e.status == EnvelopeStatus.pending ||
                        e.status == EnvelopeStatus.failed)
                    ? () => _postOne(e)
                    : null,
                child: const Text('POST'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(EnvelopeStatus status) {
    final (label, color) = switch (status) {
      EnvelopeStatus.pending => ('wachtend', Colors.grey),
      EnvelopeStatus.posting => ('bezig', Colors.blueAccent),
      EnvelopeStatus.posted => ('geplaatst', Colors.greenAccent),
      EnvelopeStatus.failed => ('mislukt', Colors.redAccent),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.2),
      labelStyle: TextStyle(color: color),
    );
  }
}
