import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'models/trip.dart';
import 'screens/end_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/start_screen.dart';
import 'services/trip_service.dart';
import 'services/trip_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Required before using sendDataToMain/sendDataToTask across isolates.
  FlutterForegroundTask.initCommunicationPort();
  TripService.init();
  runApp(const RingRingApp());
}

class RingRingApp extends StatelessWidget {
  const RingRingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00E5A0),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'RingRing Logger',
      debugShowCheckedModeBanner: false,
      theme: base,
      home: const _Boot(),
    );
  }
}

/// Decides the first screen at launch:
///  - service already running → jump straight to the recording screen
///  - an interrupted recording lingers (active_trip.json) → recovery prompt
///  - otherwise → start screen
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    final running = await TripService.isRunning();
    if (!mounted) return;
    if (running) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RecordingScreen()),
      );
      return;
    }

    final interrupted = await TripStorage.readActive();
    if (!mounted) return;
    if (interrupted != null && interrupted.points.isNotEmpty) {
      final recover = await _askRecover(interrupted);
      if (!mounted) return;
      if (recover == true) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EndScreen(trip: interrupted, recovered: true),
          ),
        );
        return;
      } else if (recover == false) {
        await TripStorage.deleteActive();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const StartScreen()),
    );
  }

  Future<bool?> _askRecover(Trip trip) {
    final mod = Modality.fromCode(trip.declaredModality).labelNl;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Onderbroken rit gevonden'),
        content: Text(
          'Er staat een niet-afgesloten opname klaar:\n\n'
          'Modaliteit: $mod\n'
          'Fixes: ${trip.points.length}\n'
          'Start: ${trip.start.toLocal()}\n\n'
          'Wil je deze herstellen (bekijken en exporteren) of verwerpen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Verwerpen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Herstellen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
