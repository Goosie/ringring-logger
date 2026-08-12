// Smoke test: the app boots without throwing.
import 'package:flutter_test/flutter_test.dart';

import 'package:ringring_logger/models/trip.dart';

void main() {
  test('isoZ formats UTC with Z and no milliseconds', () {
    final d = DateTime.utc(2026, 8, 13, 9, 14, 5, 123);
    expect(isoZ(d), '2026-08-13T09:14:05Z');
  });

  test('Trip serializes to the fixed export schema', () {
    final trip = Trip(
      id: 'abc',
      deviceLabel: 'perry-pixel',
      note: 'stad',
      start: DateTime.utc(2026, 8, 13, 9, 14, 2),
      declaredModality: 'bike',
      devicePlacement: 'handlebar',
    )
      ..points.add(TripPoint(
        lat: 52.3865343,
        lng: 4.9524378,
        speed: 5.1,
        accuracy: 3.2,
        heading: 84.0,
        altitude: 12.3,
        date: DateTime.utc(2026, 8, 13, 9, 14, 5),
      ));
    final json = trip.toJson();
    expect(json['declaredModality'], 'bike');
    expect(json['osActivity'], isEmpty);
    expect((json['points'] as List).first['speed'], 5.1);
    expect((json['points'] as List).first['date'], '2026-08-13T09:14:05Z');
  });
}
