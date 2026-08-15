import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../claims/claims_storage.dart';
import '../claims/trip_track_points.dart';
import '../delen/delen_screen.dart';
import '../models/trip.dart';
import '../services/trip_storage.dart';
import '../widgets/big_button.dart';
import 'claims_screen.dart';
import 'start_screen.dart';

class EndScreen extends StatefulWidget {
  const EndScreen({super.key, required this.trip, this.recovered = false});

  final Trip trip;

  /// True when this trip was recovered from an interrupted recording.
  final bool recovered;

  @override
  State<EndScreen> createState() => _EndScreenState();
}

class _EndScreenState extends State<EndScreen> {
  Trip get trip => widget.trip;
  bool get recovered => widget.recovered;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: precompute + persist corridor claims right after the
    // recording stops, so opening the Claims screen is instant. A debug
    // import re-triggers the same computation for its own generated id.
    ClaimsStorage.loadOrCompute(trip.id, trackPointsFromTrip(trip));
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> _export(BuildContext context) async {
    try {
      final file = await TripStorage.writeExport(trip);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'RingRing Logger rit',
          text: 'Grondwaarheid-rit (${trip.declaredModality}).',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exporteren mislukt: $e')),
        );
      }
    }
  }

  Future<void> _newTrip(BuildContext context) async {
    await TripStorage.deleteActive();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const StartScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modality = Modality.fromCode(trip.declaredModality);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(recovered ? 'Herstelde rit' : 'Rit voltooid'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (recovered)
                Card(
                  color: Colors.amber.shade900,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Deze rit is hersteld uit een onderbroken opname. '
                      'Exporteer hem om de data te bewaren.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Center(
                child: Column(
                  children: [
                    Icon(modality.icon, size: 48, color: const Color(0xFF00E5A0)),
                    const SizedBox(height: 6),
                    Text(modality.labelNl,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    if (trip.note.isNotEmpty)
                      Text(trip.note,
                          style: TextStyle(color: Colors.grey.shade400)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _summaryTile('Duur', _fmtDuration(trip.duration), Icons.timer),
              _summaryTile('Aantal fixes', '${trip.fixCount}', Icons.gps_fixed),
              _summaryTile('Afstand',
                  '${trip.distanceKm.toStringAsFixed(2)} km', Icons.straighten),
              _summaryTile('Mediaansnelheid',
                  '${trip.medianSpeedKmh.toStringAsFixed(1)} km/u', Icons.speed),
              _summaryTile('Batterijverbruik',
                  '${trip.batteryDropPct} procentpunt', Icons.battery_alert),
              if (trip.modalitySwitches.isNotEmpty)
                _summaryTile('Modaliteitswissels',
                    '${trip.modalitySwitches.length}', Icons.swap_horiz),
              const SizedBox(height: 24),
              BigButton(
                label: 'EXPORTEER JSON',
                icon: Icons.ios_share,
                height: 80,
                color: const Color(0xFF00E5A0),
                onPressed: () => _export(context),
              ),
              const SizedBox(height: 12),
              BigButton(
                label: 'CLAIMS',
                icon: Icons.route,
                color: Colors.grey.shade800,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClaimsScreen(
                      claimsId: trip.id,
                      points: trackPointsFromTrip(trip),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BigButton(
                label: 'DELEN',
                icon: Icons.share,
                color: Colors.grey.shade800,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DelenScreen(points: trackPointsFromTrip(trip)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BigButton(
                label: 'NIEUWE RIT',
                icon: Icons.add,
                color: Colors.grey.shade800,
                onPressed: () => _newTrip(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryTile(String label, String value, IconData icon) {
    return Card(
      color: Colors.grey.shade900,
      child: ListTile(
        leading: Icon(icon, color: Colors.grey.shade400),
        title: Text(label, style: TextStyle(color: Colors.grey.shade400)),
        trailing: Text(value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
