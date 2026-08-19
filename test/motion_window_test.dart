import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ringring_logger/services/motion_window.dart';

/// Builds a synthetic (magnitude - 1g) window: a [freqHz] sine of unit
/// amplitude, sampled at [fsHz] across [durationSecs], starting at absolute
/// time [startUs] (so consecutive windows stay phase-continuous).
({List<int> timestampsUs, List<double> deltaG}) _syntheticWindow({
  required double freqHz,
  required double fsHz,
  required double durationSecs,
  int startUs = 0,
}) {
  final stepUs = (1e6 / fsHz).round();
  final n = (durationSecs * fsHz).floor();
  final timestamps = <int>[];
  final values = <double>[];
  for (var k = 0; k < n; k++) {
    final tUs = startUs + k * stepUs;
    final tSec = tUs / 1e6;
    timestamps.add(tUs);
    values.add(math.sin(2 * math.pi * freqHz * tSec));
  }
  return (timestampsUs: timestamps, deltaG: values);
}

void main() {
  group('computeAccWindow — fs normalization (C2)', () {
    final w50 = _syntheticWindow(freqHz: 10.0, fsHz: 50.0, durationSecs: 1.0);
    final w94 = _syntheticWindow(freqHz: 10.0, fsHz: 94.0, durationSecs: 1.0);

    final r50 = computeAccWindow(w50.timestampsUs, w50.deltaG);
    final r94 = computeAccWindow(w94.timestampsUs, w94.deltaG);

    test('accDomHz agrees between 50Hz and 94Hz windows', () {
      expect(r50.accDomHz, isNotNull);
      expect(r94.accDomHz, isNotNull);
      expect((r50.accDomHz! - r94.accDomHz!).abs(), lessThan(0.5));
    });

    test('accDomHz is within 0.5Hz of the true 10.0Hz signal', () {
      expect((r50.accDomHz! - 10.0).abs(), lessThan(0.5));
      expect((r94.accDomHz! - 10.0).abs(), lessThan(0.5));
    });

    test('accZcrHz agrees within 5% between 50Hz and 94Hz windows', () {
      expect(r50.accZcrHz, isNotNull);
      expect(r94.accZcrHz, isNotNull);
      final diff = (r50.accZcrHz! - r94.accZcrHz!).abs();
      final rel = diff / r50.accZcrHz!;
      expect(rel, lessThan(0.05));
    });

    test('accRmsG agrees within 2% between 50Hz and 94Hz windows', () {
      expect(r50.accRmsG, isNotNull);
      expect(r94.accRmsG, isNotNull);
      final diff = (r50.accRmsG! - r94.accRmsG!).abs();
      final rel = diff / r50.accRmsG!;
      expect(rel, lessThan(0.02));
    });
  });

  test(
      'computeAccWindow — an fs transition mid-window still finds the right '
      'dominant frequency (C3)', () {
    const freqHz = 10.0;
    final first = _syntheticWindow(
      freqHz: freqHz,
      fsHz: 50.0,
      durationSecs: 0.5,
      startUs: 0,
    );
    final firstEndUs = first.timestampsUs.isEmpty ? 0 : first.timestampsUs.last;
    final second = _syntheticWindow(
      freqHz: freqHz,
      fsHz: 94.0,
      durationSecs: 0.5,
      startUs: firstEndUs + (1e6 / 94.0).round(),
    );

    final timestampsUs = [...first.timestampsUs, ...second.timestampsUs];
    final deltaG = [...first.deltaG, ...second.deltaG];

    final result = computeAccWindow(timestampsUs, deltaG);

    expect(result.accDomHz, isNotNull);
    expect((result.accDomHz! - freqHz).abs(), lessThan(0.5));
  });
}
