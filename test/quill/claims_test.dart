import 'dart:convert';
import 'dart:math' as math;

import 'package:ringring_logger/quill/claims.dart';
import 'package:ringring_logger/quill/matcher.dart';
import 'package:ringring_logger/quill/registry.dart';
import 'package:ringring_logger/quill/track_point.dart';
import 'package:test/test.dart';

const _baseLat = 52.300000;
const _lng0 = 4.900000;

double _lngOffset(double meters) => meters / (111320.0 * math.cos(_baseLat * math.pi / 180));

TrackPoint _pt(double lngOffsetM, int atSecond, {double speedKmh = 15}) => TrackPoint(
      lat: _baseLat,
      lng: _lng0 + _lngOffset(lngOffsetM),
      speedKmh: speedKmh,
      date: DateTime.utc(2026, 8, 12, 10, 0, atSecond),
    );

Registry _registryWith(List<Corridor> corridors) =>
    Registry(version: 'v1', region: 'test', corridors: corridors);

Corridor _corridor(String id, double lengthM) => Corridor(
      id: id,
      name: 'name-$id',
      coords: const [LatLng(_baseLat, _lng0), LatLng(_baseLat, _lng0 + 0.01)],
      lengthM: lengthM,
    );

void main() {
  group('deriveClaims traversal thresholds', () {
    test('coverage >= 60% alone is enough, even with few points', () {
      final traversal = CorridorTraversal(
        corridorId: 'COVERS',
        points: [_pt(0, 0), _pt(75, 1)], // ~75 m span on a 100 m corridor
      );
      final registry = _registryWith([_corridor('COVERS', 100)]);
      final claims = deriveClaims([traversal], registry);
      expect(claims.map((c) => c.corridorId), ['COVERS']);
    });

    test('>= 30 points alone is enough, even with little coverage', () {
      final points = [for (var i = 0; i < 35; i++) _pt(0.1 * i, i)]; // ~3.4 m total span
      final traversal = CorridorTraversal(corridorId: 'DENSE', points: points);
      final registry = _registryWith([_corridor('DENSE', 100)]);
      final claims = deriveClaims([traversal], registry);
      expect(claims.map((c) => c.corridorId), ['DENSE']);
    });

    test('neither threshold met drops the traversal entirely', () {
      final points = [_pt(0, 0), _pt(1, 1), _pt(2, 2)]; // ~2 m span, 3 points
      final traversal = CorridorTraversal(corridorId: 'THIN', points: points);
      final registry = _registryWith([_corridor('THIN', 100)]);
      expect(deriveClaims([traversal], registry), isEmpty);
    });
  });

  test('v85 matches a hand-computed percentile', () {
    // Speeds 0,10,...,100 (n=11). rank = 0.85*(11-1) = 8.5 -> interpolate
    // between the 9th (80) and 10th (90) sorted values -> 85.0.
    final points = [
      for (var i = 0; i < 11; i++) _pt(i * 1.0, i, speedKmh: (i * 10).toDouble()),
    ];
    final traversal = CorridorTraversal(corridorId: 'V85', points: points);
    // lengthM tiny so the ~10 m span trivially clears the coverage bar
    // without needing 30 points.
    final registry = _registryWith([_corridor('V85', 1)]);
    final claims = deriveClaims([traversal], registry);
    expect(claims, hasLength(1));
    expect(claims.single.v85, 85.0);
  });

  test('claims are sorted alphabetically by corridorId, not traversal order', () {
    final registry = _registryWith([_corridor('ZEBRA', 1), _corridor('ALPHA', 1)]);
    final traversals = [
      CorridorTraversal(corridorId: 'ZEBRA', points: [_pt(0, 0), _pt(50, 1)]),
      CorridorTraversal(corridorId: 'ALPHA', points: [_pt(0, 2), _pt(50, 3)]),
    ];
    final claims = deriveClaims(traversals, registry);
    expect(claims.map((c) => c.corridorId), ['ALPHA', 'ZEBRA']);
  });

  test('serialized claims never contain coordinate keys', () {
    final registry = _registryWith([_corridor('NOCOORDS', 1)]);
    final traversal = CorridorTraversal(corridorId: 'NOCOORDS', points: [_pt(0, 0), _pt(50, 1)]);
    final claims = deriveClaims([traversal], registry);
    expect(claims, isNotEmpty);
    final jsonStr = jsonEncode(claims.map((c) => c.toJson()).toList());
    expect(jsonStr.contains('lat'), isFalse);
    expect(jsonStr.contains('lng'), isFalse);
  });
}
