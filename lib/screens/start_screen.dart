import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/trip.dart';
import '../services/permissions.dart';
import '../services/trip_service.dart';
import '../widgets/big_button.dart';
import 'recording_screen.dart';

const _kPrefDeviceLabel = 'device_label';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> with WidgetsBindingObserver {
  Modality? _modality;
  final _noteCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  PermissionStatus2? _perms;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLabel();
    _refreshPerms();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permissions may have changed while the user was in system settings.
    if (state == AppLifecycleState.resumed) _refreshPerms();
  }

  Future<void> _loadLabel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefDeviceLabel) ?? '';
    if (mounted) _labelCtrl.text = saved;
  }

  Future<void> _saveLabel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefDeviceLabel, _labelCtrl.text.trim());
  }

  Future<void> _refreshPerms() async {
    final p = await Permissions.check();
    if (mounted) setState(() => _perms = p);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _runPermissionFlow() async {
    // Step 1: foreground location.
    final fg = await Permissions.requestForegroundLocation();
    if (!fg) {
      _snack('Locatie (voorgrond) geweigerd — meten kan niet zonder.');
      await _refreshPerms();
      return;
    }

    // Step 2: explain, then request background location.
    if (!mounted) return;
    final proceed = await _explainBackground();
    if (proceed == true) {
      final bg = await Permissions.requestBackgroundLocation();
      if (!bg) {
        _snack('Achtergrondlocatie geweigerd. Kies in de systeeminstelling '
            '"Altijd toestaan" om met scherm uit te meten.');
      }
    }

    // Step 3: notifications (Android 13+).
    final notif = await Permissions.requestNotifications();
    if (!notif) {
      _snack('Notificaties geweigerd — de meet-notificatie is dan niet zichtbaar.');
    }

    // Step 4 (optioneel): OS-activiteitsherkenning. Weigeren is prima; de app
    // werkt onveranderd door, alleen het osActivity-veld blijft dan leeg.
    await Permissions.requestActivityRecognition();

    await _refreshPerms();
  }

  Future<bool?> _explainBackground() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Achtergrondlocatie nodig'),
        content: const Text(
          'Om te blijven meten met het scherm uit of de telefoon in je zak, '
          'heeft de app locatietoegang "Altijd toestaan" nodig.\n\n'
          'Op het volgende scherm: kies "Altijd toestaan".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Doorgaan'),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final modality = _modality;
    final perms = _perms;
    if (modality == null || perms == null || !perms.canRecord || _starting) return;

    setState(() => _starting = true);
    await _saveLabel();

    final result = await TripService.start(
      id: const Uuid().v4(),
      deviceLabel: _labelCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      modality: modality.code,
    );

    if (!mounted) return;
    setState(() => _starting = false);

    if (result is ServiceRequestSuccess) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RecordingScreen()),
      );
    } else {
      _snack('Kon de meting niet starten. Controleer de permissies.');
      await _refreshPerms();
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = _perms;
    final canStart =
        _modality != null && perms != null && perms.canRecord && !_starting;

    return Scaffold(
      appBar: AppBar(title: const Text('RingRing Logger')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Modaliteit',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _modalityGrid(),
            const SizedBox(height: 20),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Notitie',
                hintText: 'bijv. stad, buitenweg',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Toestel-label',
                hintText: 'bijv. perry-pixel',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            _permissionCard(perms),
            const SizedBox(height: 20),
            BigButton(
              label: _starting ? 'Bezig…' : 'START',
              icon: Icons.play_arrow,
              height: 84,
              color: canStart ? const Color(0xFF00E5A0) : Colors.grey.shade800,
              onPressed: canStart ? _start : null,
            ),
            if (_modality == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Kies eerst een modaliteit.',
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }

  Widget _modalityGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: Modality.values.map((m) {
        final selected = _modality == m;
        return FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: selected
                ? const Color(0xFF00E5A0)
                : Colors.grey.shade900,
            foregroundColor: selected ? Colors.black : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => setState(() => _modality = m),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(m.icon, size: 30),
              const SizedBox(height: 4),
              Text(m.labelNl,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _permissionCard(PermissionStatus2? perms) {
    return Card(
      color: Colors.grey.shade900,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Permissies',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (perms == null)
              const Text('Controleren…')
            else ...[
              _permRow('Locatie (voorgrond)', perms.foregroundLocation),
              _permRow('Locatie (achtergrond)', perms.backgroundLocation),
              _permRow('Notificaties', perms.notifications),
              _permRow('Batterijoptimalisatie uit',
                  perms.ignoreBatteryOptimizations),
              _permRow('Activiteitsherkenning (optioneel)',
                  perms.activityRecognition),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Permissies aanvragen'),
                      onPressed: _runPermissionFlow,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.battery_saver),
                label: const Text('Batterijoptimalisatie uitschakelen'),
                onPressed: () async {
                  await Permissions.requestIgnoreBatteryOptimizations();
                  await _refreshPerms();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _permRow(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              color: ok ? const Color(0xFF00E5A0) : Colors.redAccent, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}
