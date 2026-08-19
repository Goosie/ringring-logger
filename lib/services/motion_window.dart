import 'dart:math' as math;

import 'package:fftea/fftea.dart';

/// Fixed sampling rate every accelerometer frequency-domain feature
/// (accDomHz, accZcr, accZcrHz) is computed against, regardless of the
/// device's actual sensor rate for a given window. Measured across real
/// exports, the effective accelerometer rate swings between ~50Hz and ~94Hz —
/// sometimes mid-trip — so without a common grid accZcr scales linearly with
/// the device's real fs and accDomHz gets a shifted frequency axis, making
/// both fields useless for comparing trips.
const double kResampleHz = 50.0;

/// Below this many raw samples in a window, fsHz/accDomHz/accZcr/accZcrHz are
/// reported as null rather than guessed from too little data.
const int kMinSamplesForFreq = 20;

/// Gaps between consecutive raw samples wider than this are never bridged by
/// linear interpolation when resampling — the affected window is instead
/// marked [MotionWindowResult.degraded].
const int kMaxInterpGapUs = 100000; // 100ms

/// Per-window accelerometer summary produced by [computeAccWindow].
class MotionWindowResult {
  const MotionWindowResult({
    required this.windowSecs,
    required this.fsHz,
    required this.accRmsG,
    required this.accStdG,
    required this.accPeakG,
    required this.accP95G,
    required this.accDomHz,
    required this.accZcr,
    required this.accZcrHz,
    required this.degraded,
  });

  /// (t_last - t_first) in seconds, or null if the window has no samples.
  final double? windowSecs;

  /// (sampleCount - 1) / windowSecs — the effective sampling rate actually
  /// achieved this window. Null below [kMinSamplesForFreq] samples.
  final double? fsHz;

  final double? accRmsG;
  final double? accStdG;
  final double? accPeakG;

  /// 95th percentile of |magnitude - 1g| in the window — a robust
  /// counterpart to [accPeakG], which is sensitive to a single outlier
  /// sample and to window length.
  final double? accP95G;

  /// Dominant frequency, computed on the window's signal after resampling to
  /// [kResampleHz]. Null below [kMinSamplesForFreq] samples.
  final double? accDomHz;

  /// Zero-crossing count, computed on the same resampled signal as
  /// [accDomHz], crossing the (magnitude - 1g) zero line — i.e. 1g is
  /// subtracted, not the window mean. Null below [kMinSamplesForFreq]
  /// samples.
  final int? accZcr;

  /// [accZcr] normalized by [windowSecs], so it's comparable across windows
  /// of slightly different length. Null below [kMinSamplesForFreq] samples.
  final double? accZcrHz;

  /// True if any gap between consecutive raw samples in this window exceeded
  /// [kMaxInterpGapUs] — resampling never interpolates across such a gap, so
  /// frequency-domain features from a degraded window may be based on a
  /// shorter, discontinuous signal.
  final bool degraded;
}

/// Summarizes one window of accelerometer (magnitude - 1g) samples.
///
/// [timestampsUs] and [deltaG] must be the same length, sorted ascending by
/// time. Timestamps are in microseconds on whatever monotonic clock the
/// caller used (a [Stopwatch]'s `elapsedMicroseconds` in production).
///
/// accRmsG/accStdG/accPeakG/accP95G are amplitude statistics computed
/// directly on the raw (unresampled) samples — unlike the frequency features
/// below, they don't need a common sample grid to be comparable across
/// windows recorded at different effective sensor rates.
///
/// accDomHz/accZcr/accZcrHz are computed on the signal *after* resampling to
/// a fixed [kResampleHz] grid via linear interpolation over the real
/// timestamps. This is what makes them comparable between a window sampled
/// at ~50Hz and one sampled at ~94Hz.
MotionWindowResult computeAccWindow(List<int> timestampsUs, List<double> deltaG) {
  final n = deltaG.length;
  if (n != timestampsUs.length) {
    throw ArgumentError('timestampsUs and deltaG must be the same length');
  }

  if (n == 0) {
    return const MotionWindowResult(
      windowSecs: null,
      fsHz: null,
      accRmsG: null,
      accStdG: null,
      accPeakG: null,
      accP95G: null,
      accDomHz: null,
      accZcr: null,
      accZcrHz: null,
      degraded: false,
    );
  }

  final sumSq = deltaG.fold(0.0, (s, v) => s + v * v);
  final accRms = math.sqrt(sumSq / n);
  final mean = deltaG.fold(0.0, (s, v) => s + v) / n;
  final varSum = deltaG.fold(0.0, (s, v) => s + (v - mean) * (v - mean));
  final accStd = math.sqrt(varSum / n);
  final absVals = deltaG.map((v) => v.abs()).toList()..sort();
  final accPeak = absVals.last;
  final accP95 = _percentile(absVals, 95);

  final windowSecs = (timestampsUs.last - timestampsUs.first) / 1e6;

  double? fsHz;
  double? accDomHz;
  int? accZcr;
  double? accZcrHz;
  var degraded = false;

  if (n >= 2) {
    var maxGapUs = 0;
    for (var i = 1; i < n; i++) {
      final gap = timestampsUs[i] - timestampsUs[i - 1];
      if (gap > maxGapUs) maxGapUs = gap;
    }
    degraded = maxGapUs > kMaxInterpGapUs;

    if (n >= kMinSamplesForFreq && windowSecs > 0) {
      fsHz = (n - 1) / windowSecs;
      final resampled = _resampleLinear(timestampsUs, deltaG, kResampleHz);
      if (resampled.length >= 2) {
        accDomHz = _dominantHz(resampled, kResampleHz);
        accZcr = _zeroCrossings(resampled);
        accZcrHz = accZcr / windowSecs;
      }
    }
  }

  return MotionWindowResult(
    windowSecs: windowSecs,
    fsHz: fsHz,
    accRmsG: accRms,
    accStdG: accStd,
    accPeakG: accPeak,
    accP95G: accP95,
    accDomHz: accDomHz,
    accZcr: accZcr,
    accZcrHz: accZcrHz,
    degraded: degraded,
  );
}

/// Linear-interpolation percentile (numpy's default "linear" method) over an
/// already-sorted list.
double _percentile(List<double> sortedAbs, double p) {
  if (sortedAbs.length == 1) return sortedAbs[0];
  final rank = (p / 100.0) * (sortedAbs.length - 1);
  final lo = rank.floor();
  final hi = rank.ceil();
  if (lo == hi) return sortedAbs[lo];
  final frac = rank - lo;
  return sortedAbs[lo] + (sortedAbs[hi] - sortedAbs[lo]) * frac;
}

/// Resamples ([timestampsUs], [values]) onto a fixed grid at [targetHz],
/// spanning `timestampsUs.first` .. `timestampsUs.last`, via linear
/// interpolation. A grid point that would require interpolating across a gap
/// wider than [kMaxInterpGapUs] is omitted rather than fabricated.
List<double> _resampleLinear(
  List<int> timestampsUs,
  List<double> values,
  double targetHz,
) {
  final t0 = timestampsUs.first;
  final spanUs = timestampsUs.last - t0;
  if (spanUs <= 0) return [values.first];

  final stepUs = 1e6 / targetHz;
  final gridCount = (spanUs / stepUs).floor() + 1;
  final out = <double>[];
  var srcIdx = 0;
  for (var k = 0; k < gridCount; k++) {
    final tg = t0 + k * stepUs;
    while (srcIdx + 1 < timestampsUs.length && timestampsUs[srcIdx + 1] < tg) {
      srcIdx++;
    }
    final lo = srcIdx;
    final hi = (srcIdx + 1 < timestampsUs.length) ? srcIdx + 1 : srcIdx;
    if (lo == hi) {
      out.add(values[lo]);
      continue;
    }
    final tLo = timestampsUs[lo];
    final tHi = timestampsUs[hi];
    if (tHi - tLo > kMaxInterpGapUs) continue; // don't bridge large gaps
    final frac = (tg - tLo) / (tHi - tLo);
    out.add(values[lo] + (values[hi] - values[lo]) * frac);
  }
  return out;
}

/// Dominant frequency via FFT, with the frequency axis derived from [fsHz]
/// (bin k -> f = k * fsHz / N) rather than any assumption baked into the FFT
/// size — [signal] can be any length, [FFT] picks the matching algorithm.
double _dominantHz(List<double> signal, double fsHz) {
  final n = signal.length;
  final nyquistBin = n ~/ 2;
  if (nyquistBin < 2) return 0.0;
  final fft = FFT(n);
  final freqDomain = fft.realFft(signal);
  final mags = freqDomain.magnitudes();

  var bestBin = 1;
  var bestMag = -1.0;
  for (var i = 1; i < nyquistBin; i++) {
    if (mags[i] > bestMag) {
      bestMag = mags[i];
      bestBin = i;
    }
  }
  return bestBin * fsHz / n;
}

int _zeroCrossings(List<double> signal) {
  var count = 0;
  for (var i = 1; i < signal.length; i++) {
    if ((signal[i - 1] < 0) != (signal[i] < 0)) count++;
  }
  return count;
}
