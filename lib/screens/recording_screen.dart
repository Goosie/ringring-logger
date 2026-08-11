import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../services/trip_storage.dart';
import '../widgets/big_button.dart';
import 'end_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  int _elapsedSec = 0;
  int _fixCount = 0;
  double _lastSpeed = -1; // m/s
  double _lastAccuracy = -1; // m
  int _battery = -1;
  String _modality = 'walk';
  String? _osActivity;

  bool _stopping = false;
  Timer? _stopTimeout;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    _stopTimeout?.cancel();
    super.dispose();
  }

  void _onData(Object data) {
    if (data is! Map) return;
    final event = data['event'];
    if (event == 'stats') {
      if (!mounted) return;
      setState(() {
        _elapsedSec = (data['elapsedSec'] as num?)?.toInt() ?? _elapsedSec;
        _fixCount = (data['fixCount'] as num?)?.toInt() ?? _fixCount;
        _lastSpeed = (data['lastSpeed'] as num?)?.toDouble() ?? _lastSpeed;
        _lastAccuracy = (data['lastAccuracy'] as num?)?.toDouble() ?? _lastAccuracy;
        _battery = (data['battery'] as num?)?.toInt() ?? _battery;
        _modality = (data['modality'] as String?) ?? _modality;
        _osActivity = data['osActivity'] as String?;
      });
    } else if (event == 'stopped') {
      _finishAfterStop();
    }
  }

  Future<void> _finishAfterStop() async {
    _stopTimeout?.cancel();
    final trip = await TripStorage.readLast();
    await TripService.stopService();
    if (!mounted) return;
    if (trip != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EndScreen(trip: trip)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kon de rit niet lezen bij stoppen.')),
      );
      setState(() => _stopping = false);
    }
  }

  void _stop() {
    if (_stopping) return;
    setState(() => _stopping = true);
    TripService.requestStop();
    // Fallback: if the 'stopped' event never arrives, try to finalize anyway.
    _stopTimeout = Timer(const Duration(seconds: 6), _finishAfterStop);
  }

  Future<void> _switchModality() async {
    final chosen = await showModalBottomSheet<Modality>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Wissel naar…',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            ...Modality.values.map((m) => ListTile(
                  leading: Icon(m.icon, size: 30),
                  title: Text(m.labelNl, style: const TextStyle(fontSize: 20)),
                  trailing: m.code == _modality
                      ? const Icon(Icons.check, color: Color(0xFF00E5A0))
                      : null,
                  onTap: () => Navigator.of(ctx).pop(m),
                )),
          ],
        ),
      ),
    );
    if (chosen != null && chosen.code != _modality) {
      TripService.switchModality(chosen.code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gewisseld naar ${chosen.labelNl}')),
        );
      }
    }
  }

  static const _osActivityLabelsNl = {
    'WALKING': 'lopen',
    'ON_BICYCLE': 'fiets',
    'IN_VEHICLE': 'voertuig',
    'RUNNING': 'rennen',
    'STILL': 'stil',
    'UNKNOWN': 'onbekend',
  };

  String _fmtDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final modality = Modality.fromCode(_modality);
    return PopScope(
      canPop: false, // don't let back-button silently abandon the recording
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(modality.icon, size: 34, color: const Color(0xFF00E5A0)),
                    const SizedBox(width: 10),
                    Text(modality.labelNl.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_osActivity != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'OS: ${_osActivityLabelsNl[_osActivity] ?? _osActivity}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(_fmtDuration(_elapsedSec),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      _stat('Fixes', '$_fixCount', Icons.gps_fixed),
                      _stat(
                          'Snelheid',
                          _lastSpeed < 0
                              ? '—'
                              : '${(_lastSpeed * 3.6).toStringAsFixed(1)} km/u',
                          Icons.speed),
                      _stat(
                          'Nauwkeurigheid',
                          _lastAccuracy < 0
                              ? '—'
                              : '${_lastAccuracy.toStringAsFixed(1)} m',
                          Icons.my_location),
                      _stat('Batterij', _battery < 0 ? '—' : '$_battery%',
                          Icons.battery_full),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                BigButton(
                  label: 'MODALITEIT WISSELEN',
                  icon: Icons.swap_horiz,
                  color: Colors.blueGrey.shade700,
                  onPressed: _stopping ? null : _switchModality,
                ),
                const SizedBox(height: 12),
                BigButton(
                  label: _stopping ? 'STOPPEN…' : 'STOP',
                  icon: Icons.stop,
                  height: 84,
                  color: Colors.redAccent.shade700,
                  onPressed: _stopping ? null : _stop,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: Colors.grey.shade400),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}
