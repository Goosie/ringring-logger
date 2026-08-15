// Runs the quill corridor-matching pipeline — the exact path the app itself
// uses (trackPointsFromTrip -> matchTrip -> deriveClaims) — against the real
// trip exports in testdata/trips/, so you can see actual corridor claims on
// your own recorded rides with:
//   flutter test test/testdata_claims_test.dart
//
// The bundled registry (assets/registry/registry-v1.json) only covers a
// fixed bbox — see tool/build_registry.py for which one and why. Trips
// outside it will correctly show 0 claims; that's the bbox, not a bug.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringring_logger/claims/trip_track_points.dart';
import 'package:ringring_logger/models/trip.dart';
import 'package:ringring_logger/quill/claims.dart';
import 'package:ringring_logger/quill/matcher.dart';
import 'package:ringring_logger/quill/registry.dart';

void main() {
  final dir = Directory('testdata/trips');
  final files = dir.existsSync()
      ? dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      : <File>[];

  if (files.isEmpty) {
    test('geen testdata gevonden (sla over)', () {}, skip: 'testdata/trips/*.json ontbreekt');
    return;
  }

  final registry = Registry.parse(File('assets/registry/registry-v1.json').readAsStringSync());

  for (final file in files) {
    test('quill-claims voor ${file.path.split(Platform.pathSeparator).last}', () {
      final trip = Trip.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      final points = trackPointsFromTrip(trip);
      final traversals = matchTrip(points, registry);
      final claims = deriveClaims(traversals, registry);

      // ignore: avoid_print
      print(
        '${file.path}: ${points.length} punten -> ${traversals.length} traversals -> '
        '${claims.length} claims  (registry ${registry.version}, ${registry.corridors.length} corridors)',
      );
      for (final c in claims) {
        final name = registry.corridorById(c.corridorId)?.name ?? '';
        // ignore: avoid_print
        print(
          '  ${c.corridorId} $name  ${c.date} ${c.hourBucket.toString().padLeft(2, '0')}u  '
          'modaliteit=${c.modality}  v85=${c.v85}km/u  samples=${c.sampleCount}',
        );
      }
    });
  }
}
