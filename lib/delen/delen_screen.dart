import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nostr/nostr.dart';

import '../claims/claims_storage.dart';
import '../quill/claims.dart';
import '../quill/matcher.dart';
import '../quill/registry.dart';
import '../quill/track_point.dart';
import '../ringring_config.dart';
import '../transport/nostr_transport.dart';
import '../transport/transport.dart';
import '../widgets/big_button.dart';
import 'attest_provider.dart';
import 'contributor_tag.dart';
import 'envelope.dart';
import 'envelope_codec.dart';
import 'geo_utils.dart';

/// Stap 1 (knip + schrob + corridor-match) -> stap 2 (per envelop of
/// gespreid posten) -> stap 3 (statuslijst) van de publicatieflow, allemaal
/// op één scherm zodat elke stap zichtbaar blijft voor de gebruiker.
///
/// Works on plain [TrackPoint]s rather than a [Trip] — a just-recorded trip
/// and a debug-imported legacy export both adapt into the same shape (see
/// lib/claims/trip_track_points.dart and lib/claims/import_trip_json.dart)
/// before reaching this screen, so both can be tested without cycling.
class DelenScreen extends StatefulWidget {
  const DelenScreen({super.key, required this.points});

  final List<TrackPoint> points;

  @override
  State<DelenScreen> createState() => _DelenScreenState();
}

class _DelenScreenState extends State<DelenScreen> {
  final Transport _transport = NostrTransport();
  final AttestProvider _attest = NoneAttest();
  final math.Random _rng = math.Random();

  List<Envelope>? _envelopes;
  Registry? _registry;
  bool _matching = false;
  bool _postingAll = false;

  // Loaded once per screen so every envelope's contributor tag is derived
  // from the same per-installation secret. Null means either "not loaded
  // yet" or "failed to load" — _vaultSecretError distinguishes the two,
  // and _postOne refuses to post while it's null rather than falling back
  // to an empty/zero secret.
  Uint8List? _vaultSecret;
  String? _vaultSecretError;

  Future<void> _makeEnvelopes() async {
    setState(() => _matching = true);
    // Trim before matching, not after: claims near the start/end of a trip
    // are the ones most likely to identify home or work, so they must
    // never reach the corridor-matcher at all — not just get filtered out
    // of the UI afterward.
    final points = trimRouteEnds(widget.points, RingRingConfig.trimAfstandMeter);

    final registry = await ClaimsStorage.loadBundledRegistry();
    final traversals = matchTrip(points, registry);
    final claims = deriveClaims(traversals, registry);

    Uint8List? vaultSecret;
    String? vaultSecretError;
    try {
      vaultSecret = await loadOrCreateVaultSecret();
    } catch (err) {
      vaultSecretError = 'Kan de bijdrager-sleutel niet laden: $err';
    }

    if (!mounted) return;
    setState(() {
      _registry = registry;
      _envelopes = claims.map(Envelope.new).toList();
      _vaultSecret = vaultSecret;
      _vaultSecretError = vaultSecretError;
      _matching = false;
    });
  }

  Future<void> _postOne(Envelope e) async {
    if (e.status == EnvelopeStatus.posting || e.status == EnvelopeStatus.posted) {
      return;
    }
    final vaultSecret = _vaultSecret;
    if (vaultSecret == null) {
      setState(() {
        e.status = EnvelopeStatus.failed;
        e.error = _vaultSecretError ?? 'Bijdrager-sleutel niet beschikbaar.';
      });
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
      final tag = contributorTag(vaultSecret, e.claim.corridorId, e.claim.date);
      final event = await buildEnvelopeEvent(e, keys, _attest, contributorTag: tag);
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
          'Dit knipt 300 m van begin en eind van de rit af, matcht de rest '
          'tegen corridors (echte wegvakken) en vat elke doorgang samen tot '
          'één claim: corridor, uur, modaliteit, v85. De ruwe GPS-trace '
          'verlaat het toestel nooit — alleen die claims worden straks '
          'gepost, elk versleuteld (NIP-44) en verpakt (NIP-59 gift wrap) '
          'met een eigen wegwerp-sleutel, leesbaar voor niemand behalve de '
          'ontvanger.',
        ),
        const SizedBox(height: 20),
        BigButton(
          label: _matching ? 'BEZIG MET MATCHEN...' : 'MAAK ENVELOPPEN',
          icon: Icons.content_cut,
          color: const Color(0xFF00E5A0),
          onPressed: _matching ? null : _makeEnvelopes,
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
            'Geen corridor-claims: rit te kort, buiten het gedekte gebied, '
            'of geen enkel wegvak lang/vaak genoeg geraakt.',
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
    final claim = e.claim;
    final name = _registry?.corridorById(claim.corridorId)?.name ?? '';
    final title = name.isEmpty ? claim.corridorId : name;
    final modalityLabel = claim.modality == 'bike' ? 'Fiets (geschat)' : 'Overig (geschat)';

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
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                _statusBadge(e.status),
              ],
            ),
            const SizedBox(height: 6),
            Text('${claim.date} · ${claim.hourBucket.toString().padLeft(2, '0')}u',
                style: TextStyle(color: Colors.grey.shade400)),
            Text('Modaliteit: $modalityLabel'),
            Text('v85: ${claim.v85} km/u'),
            Text('Samples: ${claim.sampleCount}'),
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
