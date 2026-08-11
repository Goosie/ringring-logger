import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/trip.dart';

/// Reads/writes trip files on local storage. Two well-known files live in the
/// app documents dir:
///  - active_trip.json : the in-progress recording, rewritten every ~30s and on
///    every significant event. Its mere presence (with the service not running)
///    means a recording was interrupted → recovery prompt.
///  - last_trip.json   : the most recently finalized recording, read by the end
///    screen.
class TripStorage {
  static const _activeName = 'active_trip.json';
  static const _lastName = 'last_trip.json';

  static Future<Directory> _dir() => getApplicationDocumentsDirectory();

  static Future<File> _activeFile() async =>
      File('${(await _dir()).path}/$_activeName');

  static Future<File> _lastFile() async =>
      File('${(await _dir()).path}/$_lastName');

  static Future<void> writeActive(Trip trip) async {
    final f = await _activeFile();
    // Write to a temp file first, then rename, so a crash mid-write never
    // leaves a half-written (unparseable) active file.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(trip.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  static Future<Trip?> readActive() async {
    try {
      final f = await _activeFile();
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      if (txt.trim().isEmpty) return null;
      return Trip.fromJson(jsonDecode(txt) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasActive() async => (await _activeFile()).exists();

  static Future<void> deleteActive() async {
    final f = await _activeFile();
    if (await f.exists()) await f.delete();
  }

  static Future<void> writeLast(Trip trip) async {
    final f = await _lastFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(trip.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  static Future<Trip?> readLast() async {
    try {
      final f = await _lastFile();
      if (!await f.exists()) return null;
      return Trip.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Writes the export file with the schema-defined name and returns it for
  /// sharing: `trip-YYYYMMDD-HHMMSS-<modality>-<deviceLabel>.json`
  static Future<File> writeExport(Trip trip) async {
    final u = trip.start.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
        '-${two(u.hour)}${two(u.minute)}${two(u.second)}';
    final label = _sanitize(trip.deviceLabel.isEmpty ? 'toestel' : trip.deviceLabel);
    final name = 'trip-$stamp-${trip.declaredModality}-$label.json';
    final f = File('${(await _dir()).path}/$name');
    await f.writeAsString(jsonEncode(trip.toJson()), flush: true);
    return f;
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
}
