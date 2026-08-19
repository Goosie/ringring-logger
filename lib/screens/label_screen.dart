import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../widgets/big_button.dart';
import 'recording_screen.dart';

const _kPrefVehicleClass = 'label_vehicle_class';
const _kPrefPhonePlacement = 'label_phone_placement';
const _kPrefRouteId = 'label_route_id';
const _kPrefRunIndex = 'label_run_index';
const _kPrefKnownRouteIds = 'label_known_route_ids';
const _kMaxKnownRouteIds = 20;

/// Pre-trip screen: collects the four structured, comparable label fields
/// (vehicleClass, phonePlacement, routeId, runIndex) right before the
/// recording actually starts. The last choice is remembered in
/// SharedPreferences and prefilled; runIndex auto-increments as long as
/// vehicleClass/phonePlacement/routeId stay the same as last time, and resets
/// to 1 the moment any of the three changes — each (vehicleClass,
/// phonePlacement, routeId) combination is its own repetition cell.
class LabelScreen extends StatefulWidget {
  const LabelScreen({
    super.key,
    required this.tripId,
    required this.deviceLabel,
    required this.note,
    required this.modality,
    required this.devicePlacement,
  });

  final String tripId;
  final String deviceLabel;
  final String note;
  final String modality;
  final String devicePlacement;

  @override
  State<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends State<LabelScreen> {
  VehicleClass? _vehicleClass;
  PhonePlacement? _phonePlacement;
  final _routeIdCtrl = TextEditingController();
  List<String> _knownRouteIds = [];

  String? _loadedVehicleClass;
  String? _loadedPhonePlacement;
  String _loadedRouteId = '';
  int _loadedRunIndex = 0;

  int _runIndex = 1;
  bool _loaded = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _routeIdCtrl.addListener(_recomputeRunIndex);
    _load();
  }

  @override
  void dispose() {
    _routeIdCtrl.removeListener(_recomputeRunIndex);
    _routeIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final vClass = prefs.getString(_kPrefVehicleClass);
    final pPlacement = prefs.getString(_kPrefPhonePlacement);
    final routeId = prefs.getString(_kPrefRouteId) ?? '';
    final runIndex = prefs.getInt(_kPrefRunIndex) ?? 0;
    final known = prefs.getStringList(_kPrefKnownRouteIds) ?? [];
    if (!mounted) return;
    setState(() {
      _loadedVehicleClass = vClass;
      _loadedPhonePlacement = pPlacement;
      _loadedRouteId = routeId;
      _loadedRunIndex = runIndex;
      _vehicleClass = vClass == null ? null : VehicleClass.fromCode(vClass);
      _phonePlacement = pPlacement == null ? null : PhonePlacement.fromCode(pPlacement);
      _routeIdCtrl.text = routeId;
      _knownRouteIds = known;
      _loaded = true;
    });
    _recomputeRunIndex();
  }

  /// Same (vehicleClass, phonePlacement, routeId) cell as last time -> next
  /// run in that cell. Anything different -> a fresh cell, starting at 1.
  void _recomputeRunIndex() {
    final sameCell = _vehicleClass?.code == _loadedVehicleClass &&
        _phonePlacement?.code == _loadedPhonePlacement &&
        _routeIdCtrl.text.trim() == _loadedRouteId;
    final next = sameCell ? _loadedRunIndex + 1 : 1;
    if (next != _runIndex) setState(() => _runIndex = next);
  }

  Future<void> _pickKnownRouteId() async {
    if (_knownRouteIds.isEmpty) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Eerder gebruikte route',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ..._knownRouteIds.map((r) => ListTile(
                  title: Text(r),
                  onTap: () => Navigator.of(ctx).pop(r),
                )),
          ],
        ),
      ),
    );
    if (chosen != null) {
      _routeIdCtrl.text = chosen;
      _recomputeRunIndex();
    }
  }

  Future<void> _start() async {
    final vehicleClass = _vehicleClass;
    final phonePlacement = _phonePlacement;
    if (vehicleClass == null || phonePlacement == null || _starting) return;

    setState(() => _starting = true);
    final routeId = _routeIdCtrl.text.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefVehicleClass, vehicleClass.code);
    await prefs.setString(_kPrefPhonePlacement, phonePlacement.code);
    await prefs.setString(_kPrefRouteId, routeId);
    await prefs.setInt(_kPrefRunIndex, _runIndex);
    if (routeId.isNotEmpty && !_knownRouteIds.contains(routeId)) {
      final updated = [routeId, ..._knownRouteIds].take(_kMaxKnownRouteIds).toList();
      await prefs.setStringList(_kPrefKnownRouteIds, updated);
    }

    final result = await TripService.start(
      id: widget.tripId,
      deviceLabel: widget.deviceLabel,
      note: widget.note,
      modality: widget.modality,
      devicePlacement: widget.devicePlacement,
      vehicleClass: vehicleClass.code,
      phonePlacement: phonePlacement.code,
      routeId: routeId,
      runIndex: _runIndex,
    );

    if (!mounted) return;
    setState(() => _starting = false);

    if (result is ServiceRequestSuccess) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RecordingScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kon de meting niet starten.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _vehicleClass != null && _phonePlacement != null && !_starting;

    return Scaffold(
      appBar: AppBar(title: const Text('Labels')),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Voertuigklasse',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<VehicleClass>(
                    initialValue: _vehicleClass,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Kies voertuigklasse',
                    ),
                    items: VehicleClass.values
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.labelNl),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _vehicleClass = v);
                      _recomputeRunIndex();
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('Telefoonplaatsing',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<PhonePlacement>(
                    initialValue: _phonePlacement,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Kies telefoonplaatsing',
                    ),
                    items: PhonePlacement.values
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.labelNl),
                            ))
                        .toList(),
                    onChanged: (p) {
                      setState(() => _phonePlacement = p);
                      _recomputeRunIndex();
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('Route-ID',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _routeIdCtrl,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'bijv. ijklus-v1',
                      suffixIcon: _knownRouteIds.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.arrow_drop_down),
                              onPressed: _pickKnownRouteId,
                              tooltip: 'Eerder gebruikte routes',
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Herhalingsnummer',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _runIndex,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: List.generate(math.max(20, _runIndex + 5), (i) => i + 1)
                        .map((i) => DropdownMenuItem(value: i, child: Text('$i')))
                        .toList(),
                    onChanged: (i) {
                      if (i != null) setState(() => _runIndex = i);
                    },
                  ),
                  const SizedBox(height: 28),
                  BigButton(
                    label: _starting ? 'Bezig…' : 'START METING',
                    icon: Icons.play_arrow,
                    height: 84,
                    color: canStart ? const Color(0xFF00E5A0) : Colors.grey.shade800,
                    onPressed: canStart ? _start : null,
                  ),
                  if (_vehicleClass == null || _phonePlacement == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'Kies eerst een voertuigklasse en telefoonplaatsing.',
                          textAlign: TextAlign.center),
                    ),
                ],
              ),
      ),
    );
  }
}
