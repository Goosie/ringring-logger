import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart';

import '../transport/nostr_transport.dart';
import '../widgets/big_button.dart';

class _UnwrapResult {
  _UnwrapResult({required this.giftWrap, this.rumor, this.error});

  final Event giftWrap;
  final Event? rumor;
  final String? error;
}

/// Debug-only tool: paste in an nsec to unwrap and inspect kind-1059 gift
/// wraps addressed to that key on the configured relay(s). This is the
/// "what does the recipient see" counterpart to DelenScreen — never bundle
/// a real recipient secret key into the shipped app, or the sender could
/// decrypt everyone's claims, not just their own. The key typed in here
/// lives only in this screen's in-memory controller for as long as it's
/// open; nothing is persisted.
class ReceivedEnvelopesScreen extends StatefulWidget {
  const ReceivedEnvelopesScreen({super.key});

  @override
  State<ReceivedEnvelopesScreen> createState() => _ReceivedEnvelopesScreenState();
}

class _ReceivedEnvelopesScreenState extends State<ReceivedEnvelopesScreen> {
  final _nsecCtrl = TextEditingController();
  final _transport = NostrTransport();

  bool _loading = false;
  String? _error;
  List<_UnwrapResult>? _results;

  @override
  void dispose() {
    _nsecCtrl.dispose();
    super.dispose();
  }

  /// Fills the field from the clipboard directly, bypassing the on-screen
  /// keyboard entirely — some keyboards autocorrect/autocapitalize typed
  /// or even pasted text into a field, which silently corrupts a secret
  /// key without any visible sign something changed.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _nsecCtrl.text = text;
  }

  Future<void> _fetch() async {
    // Strip all whitespace, not just leading/trailing — a wrapped paste
    // can introduce a newline or space in the middle of the key.
    final input = _nsecCtrl.text.replaceAll(RegExp(r'\s+'), '');
    if (input.isEmpty) return;
    if (!RegExp(r'^(nsec1[0-9a-z]+|[0-9A-Fa-f]{64})$').hasMatch(input)) {
      setState(() {
        _error = 'Verwacht een nsec1... of een 64-tekens hex secret key '
            '(kreeg ${input.length} tekens${input.contains('nsec') ? ', begint met nsec maar klopt de rest niet' : ''}).';
        _results = null;
      });
      return;
    }

    final Keys keys;
    try {
      keys = Keys(input);
    } catch (e) {
      setState(() {
        _error = 'Ongeldige nsec/hex secret key: $e';
        _results = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });

    try {
      // NIP-59 randomizes created_at up to ~2 days into the past to defeat
      // timing correlation, so a short "since" window would silently miss
      // most envelopes.
      final since = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000;
      final filter = Filter(kinds: [1059], pTags: [keys.public], since: since);
      final events = await _transport.queryEnvelopes(filter);
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final results = <_UnwrapResult>[];
      for (final e in events) {
        try {
          final rumor = await GiftWrap.unwrap(giftWrap: e, recipientSecretKey: keys.secret);
          results.add(_UnwrapResult(giftWrap: e, rumor: rumor));
        } catch (err) {
          results.add(_UnwrapResult(giftWrap: e, error: '$err'));
        }
      }
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ophalen mislukt: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: const Text('Ontvangen enveloppen (debug)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Debug-tool: plak een nsec om de kind-1059 gift wraps te '
                'ontgrendelen die voor die pubkey klaarstaan op '
                '${_transport.relayUrls.join(", ")}. De sleutel wordt '
                'nergens opgeslagen — alleen in het geheugen van dit '
                'scherm, zolang het open staat.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nsecCtrl,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'nsec (of hex secret key)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    tooltip: 'Plak uit klembord',
                    onPressed: _pasteFromClipboard,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BigButton(
                label: _loading ? 'BEZIG...' : 'OPHALEN & ONTCIJFEREN',
                icon: Icons.lock_open,
                color: const Color(0xFF00E5A0),
                onPressed: _loading ? null : _fetch,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 12),
              if (results != null)
                Text('${results.length} kind-1059 events gevonden',
                    style: TextStyle(color: Colors.grey.shade400)),
              const SizedBox(height: 8),
              Expanded(
                child: results == null
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) => _resultTile(results[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultTile(_UnwrapResult r) {
    final rumor = r.rumor;
    return Card(
      color: Colors.grey.shade900,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('gift wrap: ${r.giftWrap.id}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            Text('afzender (ephemeral): ${r.giftWrap.pubkey}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            const SizedBox(height: 6),
            if (rumor != null) ...[
              Text('kind ${rumor.kind}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('tags: ${rumor.tags}'),
              Text('content: ${rumor.content}'),
            ] else
              Text('kon niet ontcijferen: ${r.error}',
                  style: const TextStyle(color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }
}
