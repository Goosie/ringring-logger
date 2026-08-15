import 'package:ringring_logger/quill/matcher.dart';
import 'package:ringring_logger/quill/registry.dart';
import 'package:ringring_logger/quill/track_point.dart';
import 'package:test/test.dart';

// Two parallel ~102 m corridors, 15 m apart, at a latitude where
// 1 degree of latitude is ~111320 m — used to place fixture points at
// known meter offsets without depending on the engine's own geo math.
double _latOffset(double meters) => meters / 111320.0;

const _baseLat = 52.300000;
const _lng0 = 4.900000;
const _lng1 = 4.901500;

Registry _twoParallelCorridors() => Registry(
      version: 'test',
      region: 'test',
      corridors: [
        Corridor(
          id: 'A',
          name: 'Corridor A',
          coords: const [LatLng(_baseLat, _lng0), LatLng(_baseLat, _lng1)],
          lengthM: 102.1,
        ),
        Corridor(
          id: 'B',
          name: 'Corridor B',
          coords: [
            LatLng(_baseLat + _latOffset(15), _lng0),
            LatLng(_baseLat + _latOffset(15), _lng1),
          ],
          lengthM: 102.1,
        ),
      ],
    );

TrackPoint _pt({required double latOffsetM, required int atSecond}) => TrackPoint(
      lat: _baseLat + _latOffset(latOffsetM),
      lng: 4.9005,
      speedKmh: 15,
      date: DateTime.utc(2026, 8, 12, 10, 0, atSecond),
    );

void main() {
  group('matchTrip snapping tolerance', () {
    test('a point exactly on a corridor snaps to it', () {
      final registry = _twoParallelCorridors();
      final traversals = matchTrip([_pt(latOffsetM: 0, atSecond: 0)], registry);
      expect(traversals, hasLength(1));
      expect(traversals.single.corridorId, 'A');
    });

    test('a point far from every corridor matches nothing', () {
      final registry = _twoParallelCorridors();
      final farPoint = TrackPoint(
        lat: 52.5,
        lng: 5.2,
        speedKmh: 15,
        date: DateTime.utc(2026, 8, 12, 10, 0, 0),
      );
      expect(matchTrip([farPoint], registry), isEmpty);
    });
  });

  group('matchTrip stickiness', () {
    test('a point closer to another corridor stays on the previous one when within tolerance', () {
      final registry = _twoParallelCorridors();
      // p0 on A. p1 sits exactly on B's line (15 m from A, 0 m from B) —
      // nearest overall is B, but 15 m is still within the 25 m tolerance
      // of the corridor the trip was just on, so stickiness should keep
      // it on A.
      final points = [
        _pt(latOffsetM: 0, atSecond: 0),
        _pt(latOffsetM: 15, atSecond: 1),
      ];
      final traversals = matchTrip(points, registry);
      expect(traversals, hasLength(1));
      expect(traversals.single.corridorId, 'A');
      expect(traversals.single.points, hasLength(2));
    });

    test('switches corridor once the previous one falls outside tolerance', () {
      final registry = _twoParallelCorridors();
      final points = [
        _pt(latOffsetM: 0, atSecond: 0), // on A
        _pt(latOffsetM: 15, atSecond: 1), // sticks to A (15 m <= 25 m)
        _pt(latOffsetM: 30, atSecond: 2), // 30 m from A (out), 15 m from B (in) -> switches
      ];
      final traversals = matchTrip(points, registry);
      expect(traversals.map((t) => t.corridorId), ['A', 'B']);
      expect(traversals[0].points, hasLength(2));
      expect(traversals[1].points, hasLength(1));
    });

    test('a gap between two on-corridor points splits the traversal instead of bridging it', () {
      final registry = _twoParallelCorridors();
      final farPoint = TrackPoint(
        lat: 52.5,
        lng: 5.2,
        speedKmh: 15,
        date: DateTime.utc(2026, 8, 12, 10, 0, 1),
      );
      final points = [
        _pt(latOffsetM: 0, atSecond: 0),
        farPoint,
        _pt(latOffsetM: 0, atSecond: 2),
      ];
      final traversals = matchTrip(points, registry);
      expect(traversals, hasLength(2));
      expect(traversals.every((t) => t.corridorId == 'A'), isTrue);
      expect(traversals[0].points, hasLength(1));
      expect(traversals[1].points, hasLength(1));
    });
  });
}
