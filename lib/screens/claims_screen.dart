import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../claims/claims_storage.dart';
import '../delen/delen_screen.dart';
import '../quill/claims.dart';
import '../quill/track_point.dart';
import '../widgets/big_button.dart';

/// Shows the corridor claims derived from [points] — either the trip just
/// recorded, or a debug-imported legacy export. Computation and export both
/// go through [ClaimsStorage], so this screen is a thin display layer.
class ClaimsScreen extends StatefulWidget {
  const ClaimsScreen({
    super.key,
    required this.claimsId,
    required this.points,
    this.subtitle,
  });

  /// Filename key for `claims-<claimsId>.json` — the trip id for a normal
  /// recording, a generated id for a debug import.
  final String claimsId;
  final List<TrackPoint> points;

  /// Optional extra context shown under the app bar (e.g. the imported
  /// file's name).
  final String? subtitle;

  @override
  State<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends State<ClaimsScreen> {
  late final Future<ClaimsResult> _future;

  @override
  void initState() {
    super.initState();
    _future = ClaimsStorage.loadOrCompute(widget.claimsId, widget.points);
  }

  Future<void> _export(ClaimsResult result) async {
    try {
      final file = await ClaimsStorage.fileFor(widget.claimsId);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'RingRing Logger corridor-claims',
          text: 'Corridor-claims (registry ${result.registry.version}).',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exporteren mislukt: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Claims')),
      body: SafeArea(
        child: FutureBuilder<ClaimsResult>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Matchen mislukt: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final result = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Registry ${result.registry.version}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (widget.subtitle != null)
                        Text(widget.subtitle!, style: TextStyle(color: Colors.grey.shade500)),
                      Text('${result.claims.length} claims',
                          style: TextStyle(color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                Expanded(
                  child: result.claims.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Geen corridor-claims: geen enkel wegvak werd '
                              'lang genoeg of vaak genoeg geraakt.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: result.claims.length,
                          itemBuilder: (context, i) => _claimTile(result, result.claims[i]),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: BigButton(
                    label: 'EXPORTEER CLAIMS',
                    icon: Icons.ios_share,
                    color: const Color(0xFF00E5A0),
                    onPressed: result.claims.isEmpty ? null : () => _export(result),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: BigButton(
                    label: 'DELEN',
                    icon: Icons.share,
                    color: Colors.grey.shade800,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DelenScreen(points: widget.points),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _claimTile(ClaimsResult result, CorridorClaim c) {
    final corridor = result.registry.corridorById(c.corridorId);
    final title = (corridor?.name.isNotEmpty ?? false) ? corridor!.name : c.corridorId;
    final modalityLabel = c.modality == 'bike' ? 'Fiets (geschat)' : 'Overig (geschat)';

    return Card(
      color: Colors.grey.shade900,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('corridor ${c.corridorId}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(height: 6),
            Text('${c.date} · ${c.hourBucket.toString().padLeft(2, '0')}u'),
            Text('Modaliteit: $modalityLabel'),
            Text('v85: ${c.v85} km/u'),
            Text('Samples: ${c.sampleCount}'),
          ],
        ),
      ),
    );
  }
}
