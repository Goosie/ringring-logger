import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../quill/claims.dart';
import '../quill/matcher.dart';
import '../quill/registry.dart';
import '../quill/track_point.dart';

class ClaimsResult {
  ClaimsResult({required this.registry, required this.claims});

  final Registry registry;
  final List<CorridorClaim> claims;
}

/// Runs the quill pipeline for a set of points and persists/reuses the
/// result as `claims-<id>.json` in the app documents dir — the file the
/// Claims screen's export button shares. Purely additive: never touches
/// trip_storage.dart or the trip JSON schema.
///
/// [id] is the trip id for a normally-recorded trip, or a generated id for
/// a debug-imported legacy file — either way it's just a filename key, the
/// pipeline itself only cares about [points].
class ClaimsStorage {
  static Future<Directory> _dir() => getApplicationDocumentsDirectory();

  static Future<File> fileFor(String id) async =>
      File('${(await _dir()).path}/claims-$id.json');

  static Future<Registry> loadBundledRegistry() async {
    final raw = await rootBundle.loadString('assets/registry/registry-v1.json');
    return Registry.parse(raw);
  }

  static Future<ClaimsResult> loadOrCompute(String id, List<TrackPoint> points) async {
    final registry = await loadBundledRegistry();

    final f = await fileFor(id);
    if (await f.exists()) {
      try {
        final persisted = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (persisted['registryVersion'] == registry.version) {
          final claims = (persisted['claims'] as List)
              .map((j) => CorridorClaim.fromJson(j as Map<String, dynamic>))
              .toList();
          return ClaimsResult(registry: registry, claims: claims);
        }
      } catch (_) {
        // Unreadable/stale — fall through and recompute.
      }
    }

    final traversals = matchTrip(points, registry);
    final claims = deriveClaims(traversals, registry);
    await _persist(id, registry.version, claims);
    return ClaimsResult(registry: registry, claims: claims);
  }

  static Future<void> _persist(String id, String registryVersion, List<CorridorClaim> claims) async {
    final f = await fileFor(id);
    final tmp = File('${f.path}.tmp');
    final payload = {
      'registryVersion': registryVersion,
      'claims': claims.map((c) => c.toJson()).toList(),
    };
    await tmp.writeAsString(jsonEncode(payload), flush: true);
    await tmp.rename(f.path);
  }
}
