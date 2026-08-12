import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:fftea/fftea.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:sensors_plus/sensors_plus.dart';

import '../models/trip.dart';
import 'trip_storage.dart';

/// Config keys written to FlutterForegroundTask storage by the UI before the
/// service starts, then read back here in [onStart].
const String kCfgId = 'cfg_id';
const String kCfgDeviceLabel = 'cfg_device_label';
const String kCfgNote = 'cfg_note';
const String kCfgModality = 'cfg_modality';
const String kCfgDevicePlacement = 'cfg_device_placement';

/// Standard gravity, used to convert accelerometer m/s² readings to g.
const double _kGravityMs2 = 9.80665;

/// FFT window size for [RecordingTaskHandler._computeDominantHz], in samples.
/// At the ~50Hz accelerometer sampling rate this spans roughly 2.5s.
const int _kFftWindowSize = 128;

/// Entry point that the OS/plugin invokes in the *background isolate*. Must be a
/// top-level function marked with the vm:entry-point pragma.
@pragma('vm:entry-point')
void startRecordingCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

/// Runs entirely inside the foreground-service isolate. It owns ALL recording
/// state: the location stream, battery sampling, crash-recovery persistence and
/// the trip file. The UI isolate is a pure view + command sender and talks to
/// this handler over sendDataToTask / sendDataToMain.
class RecordingTaskHandler extends TaskHandler {
  Trip? _trip;
  StreamSubscription<Position>? _sub;
  StreamSubscription<Activity>? _activitySub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<BarometerEvent>? _baroSub;
  final Battery _battery = Battery();
  int _tick = 0;
  String _currentModality = 'walk';
  String _currentPlacement = 'pocket';
  String? _lastOsActivityType;
  DateTime? _lastOsActivityWriteAt;

  // ---- Motion sensor state (background isolate only; never persisted raw) ----

  /// (magnitude - 1g) accelerometer samples collected since the last
  /// per-second flush. Cleared on every flush.
  final List<double> _secAccDeltaG = [];

  /// Gyroscope angular-velocity magnitude samples (rad/s) since the last flush.
  final List<double> _secGyroMagRad = [];

  /// Rolling buffer of the last [_kFftWindowSize] accelerometer
  /// (magnitude - 1g) samples, independent of the 1s flush boundary — used
  /// only for the dominant-frequency FFT.
  final List<double> _fftAccDeltaG = [];
  final List<DateTime> _fftAccTimestamps = [];

  double? _lastAccRmsG; // for live stats display
  double? _lastPressureHpa;
  int? _stepsBaseline; // cumulative step count at first pedometer reading
  int? _lastStepsCumulative;
  int? _stepsAtWindowStart;

  DateTime _now() => DateTime.now().toUtc();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final id = await FlutterForegroundTask.getData<String>(key: kCfgId) ?? 'unknown';
    final deviceLabel =
        await FlutterForegroundTask.getData<String>(key: kCfgDeviceLabel) ?? '';
    final note = await FlutterForegroundTask.getData<String>(key: kCfgNote) ?? '';
    final modality =
        await FlutterForegroundTask.getData<String>(key: kCfgModality) ?? 'walk';
    final placement =
        await FlutterForegroundTask.getData<String>(key: kCfgDevicePlacement) ??
            'pocket';

    _currentModality = modality;
    _currentPlacement = placement;
    _trip = Trip(
      id: id,
      deviceLabel: deviceLabel,
      note: note,
      start: _now(),
      declaredModality: modality,
      devicePlacement: placement,
    );

    await _sampleBattery(); // battery at start
    await _persist();
    _startLocationStream();
    await _startActivityRecognition();
    _startMotionSensors();
    _sendStats();
  }

  void _startLocationStream() {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        final trip = _trip;
        if (trip == null) return;
        trip.points.add(TripPoint(
          lat: pos.latitude,
          lng: pos.longitude,
          speed: pos.speed,
          accuracy: pos.accuracy,
          heading: pos.heading,
          altitude: pos.altitude,
          date: pos.timestamp.toUtc(),
        ));
        _sendStats();
      },
      onError: (_) {
        // Never let a transient location error crash the service.
      },
    );
  }

  /// Optional: subscribe to OS activity recognition (WALKING/ON_BICYCLE/...).
  /// Only *checks* the permission here (never requests it — that needs an
  /// Activity and already happened in the UI's permission flow). Any failure
  /// (permission denied, plugin unavailable) leaves osActivity empty and the
  /// rest of the recording unaffected.
  ///
  /// Uses permission_handler (not FlutterActivityRecognition.checkPermission)
  /// deliberately: this handler runs in the headless background FlutterEngine
  /// that flutter_foreground_task spins up, which is never attached to an
  /// Activity. flutter_activity_recognition's native checkPermission requires
  /// `binding?.activity` to be non-null and otherwise throws
  /// PlatformException(ACTIVITY_NOT_ATTACHED) — which the old try/catch here
  /// swallowed silently on *every* recording, so activityStream was never
  /// subscribed. permission_handler's status check only needs a Context and
  /// works fine from this isolate.
  Future<void> _startActivityRecognition() async {
    try {
      final status = await ph.Permission.activityRecognition.status;
      // DEBUG(osActivity): temporary — remove once the empty-osActivity issue
      // is confirmed fixed.
      print('[RRL:osActivity] permission status (background isolate) = $status');
      if (!status.isGranted) {
        print('[RRL:osActivity] permission not granted — activity recognition stays off');
        return;
      }
      _activitySub = FlutterActivityRecognition.instance.activityStream.listen(
        _onOsActivity,
        onError: (e) {
          print('[RRL:osActivity] activityStream error: $e');
        },
      );
      print('[RRL:osActivity] subscribed to activityStream');
    } catch (e) {
      // No activity recognition support on this device/build — carry on without it.
      print('[RRL:osActivity] failed to start activity recognition: $e');
    }
  }

  void _onOsActivity(Activity activity) {
    final trip = _trip;
    if (trip == null) return;
    final type = activity.type.name;
    final now = _now();
    // DEBUG(osActivity): log every incoming update, including repeats — lets us
    // tell "stream never fires" apart from "stream fires but gets filtered out".
    print('[RRL:osActivity] update: type=$type confidence=${activity.confidence} at=$now');
    _lastOsActivityType = type;

    // Write every update rather than only on change, throttled to at most one
    // entry per 10s. A strict change-only filter can make a live stream look
    // empty if the reported activity never changes during a short test walk.
    final lastWrite = _lastOsActivityWriteAt;
    if (lastWrite != null && now.difference(lastWrite) < const Duration(seconds: 10)) {
      return;
    }
    _lastOsActivityWriteAt = now;
    trip.osActivity.add(OsActivity(
      at: now,
      type: type,
      confidence: _confidencePct(activity.confidence),
    ));
    _persist();
    _sendStats();
  }

  int _confidencePct(ActivityConfidence c) => switch (c) {
        ActivityConfidence.HIGH => 95,
        ActivityConfidence.MEDIUM => 65,
        ActivityConfidence.LOW => 25,
      };

  /// Starts accelerometer/gyroscope/step-counter sampling. Each stream is
  /// subscribed independently and failures never crash the recording — a
  /// missing sensor just means its fields stay null in every [MotionSample]
  /// for this trip (see [_flushMotionWindow]).
  void _startMotionSensors() {
    try {
      _accSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval, // ~50Hz
      ).listen(_onAccelEvent, onError: (_) {});
    } catch (_) {
      // No accelerometer on this device/build — accXxx fields stay null.
    }
    try {
      _gyroSub = gyroscopeEventStream(
        samplingPeriod: SensorInterval.gameInterval, // ~50Hz
      ).listen(_onGyroEvent, onError: (_) {});
    } catch (_) {
      // No gyroscope on this device/build — gyroXxx fields stay null.
    }
    try {
      _stepSub = Pedometer.stepCountStream.listen(_onStepCount, onError: (_) {});
    } catch (_) {
      // No hardware step counter on this device/build — steps stays null.
    }
    try {
      _baroSub = barometerEventStream(samplingPeriod: SensorInterval.normalInterval)
          .listen((e) => _lastPressureHpa = e.pressure, onError: (_) {});
    } catch (_) {
      // No barometer on this device/build — pressureHpa stays null.
    }
  }

  void _onAccelEvent(AccelerometerEvent e) {
    final magG = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / _kGravityMs2;
    final deltaG = magG - 1.0;
    _secAccDeltaG.add(deltaG);
    _fftAccDeltaG.add(deltaG);
    _fftAccTimestamps.add(_now());
    if (_fftAccDeltaG.length > _kFftWindowSize) {
      _fftAccDeltaG.removeAt(0);
      _fftAccTimestamps.removeAt(0);
    }
  }

  void _onGyroEvent(GyroscopeEvent e) {
    _secGyroMagRad.add(math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
  }

  void _onStepCount(StepCount sc) {
    _stepsBaseline ??= sc.steps;
    _lastStepsCumulative = sc.steps;
  }

  /// Aggregates the accelerometer/gyroscope/step samples collected since the
  /// last call into one [MotionSample], appends it to the trip, and clears
  /// the per-second buffers. Called once per [onRepeatEvent] tick (~1s), so
  /// windows are approximately calendar-second-aligned like the GPS fixes.
  void _flushMotionWindow() {
    final trip = _trip;
    if (trip == null) return;

    final n = _secAccDeltaG.length;
    double? accRms, accStd, accPeak;
    int? accZcr;
    if (n > 0) {
      final sumSq = _secAccDeltaG.fold(0.0, (s, v) => s + v * v);
      accRms = math.sqrt(sumSq / n);
      final mean = _secAccDeltaG.fold(0.0, (s, v) => s + v) / n;
      final varSum = _secAccDeltaG.fold(0.0, (s, v) => s + (v - mean) * (v - mean));
      accStd = math.sqrt(varSum / n);
      accPeak = _secAccDeltaG.fold<double>(0.0, (m, v) => v.abs() > m ? v.abs() : m);
      accZcr = 0;
      for (var i = 1; i < n; i++) {
        if ((_secAccDeltaG[i - 1] < 0) != (_secAccDeltaG[i] < 0)) accZcr = accZcr! + 1;
      }
    }
    final accDomHz = _computeDominantHz();

    final gyroN = _secGyroMagRad.length;
    double? gyroRms, gyroPeak;
    if (gyroN > 0) {
      final sumSq = _secGyroMagRad.fold(0.0, (s, v) => s + v * v);
      gyroRms = math.sqrt(sumSq / gyroN);
      gyroPeak = _secGyroMagRad.fold<double>(0.0, (m, v) => v > m ? v : m);
    }

    int? steps;
    final lastCum = _lastStepsCumulative;
    if (lastCum != null) {
      final windowStart = _stepsAtWindowStart ?? lastCum;
      steps = lastCum - windowStart;
      if (steps < 0) steps = 0; // pedometer counter can only increase
      _stepsAtWindowStart = lastCum;
    }

    trip.motion.add(MotionSample(
      at: _now(),
      accRmsG: accRms,
      accStdG: accStd,
      accPeakG: accPeak,
      accDomHz: accDomHz,
      accZcr: accZcr,
      gyroRmsRad: gyroRms,
      gyroPeakRad: gyroPeak,
      steps: steps,
      sampleCount: n,
      pressureHpa: _lastPressureHpa,
    ));

    _lastAccRmsG = accRms;
    _secAccDeltaG.clear();
    _secGyroMagRad.clear();
  }

  /// Dominant frequency of the accelerometer magnitude signal via FFT over
  /// the last [_kFftWindowSize] samples, or null if the rolling buffer isn't
  /// full yet or anything goes wrong — zero-crossing rate (accZcr) already
  /// gives a usable approximation, so failures here are never fatal.
  double? _computeDominantHz() {
    if (_fftAccDeltaG.length < _kFftWindowSize) return null;
    try {
      final fft = FFT(_kFftWindowSize);
      final freqDomain = fft.realFft(_fftAccDeltaG);
      final mags = freqDomain.magnitudes();

      final elapsedUs =
          _fftAccTimestamps.last.difference(_fftAccTimestamps.first).inMicroseconds;
      if (elapsedUs <= 0) return null;
      final sampleRateHz = (_kFftWindowSize - 1) * 1e6 / elapsedUs;

      var bestBin = 1;
      var bestMag = -1.0;
      final nyquistBin = _kFftWindowSize ~/ 2;
      for (var i = 1; i < nyquistBin; i++) {
        if (mags[i] > bestMag) {
          bestMag = mags[i];
          bestBin = i;
        }
      }
      return bestBin * sampleRateHz / _kFftWindowSize;
    } catch (_) {
      return null;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_trip == null) return;
    _tick++;
    if (_tick % 60 == 0) {
      _sampleBattery(); // battery every 60s
    }
    if (_tick % 30 == 0) {
      _persist(); // crash-recovery write every 30s
    }
    _flushMotionWindow(); // one MotionSample per tick, ~calendar-second
    _sendStats();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final command = data['command'];
    if (command == 'switch') {
      final code = data['modality'] as String?;
      final trip = _trip;
      if (code == null || trip == null) return;
      _currentModality = code;
      trip.modalitySwitches.add(ModalitySwitch(at: _now(), modality: code));
      _persist();
      _sendStats();
    } else if (command == 'switchPlacement') {
      final code = data['placement'] as String?;
      final trip = _trip;
      if (code == null || trip == null) return;
      _currentPlacement = code;
      trip.placementSwitches.add(PlacementSwitch(at: _now(), placement: code));
      _persist();
      _sendStats();
    } else if (command == 'stop') {
      _finalize();
    }
  }

  Future<void> _finalize() async {
    final trip = _trip;
    if (trip == null) return;
    await _sub?.cancel();
    await _activitySub?.cancel();
    await _accSub?.cancel();
    await _gyroSub?.cancel();
    await _stepSub?.cancel();
    await _baroSub?.cancel();
    print('[RRL:osActivity] activitySub cancelled (finalize) — '
        '${trip.osActivity.length} entries this trip');
    trip.end = _now();
    await _sampleBattery(); // battery at stop
    await TripStorage.writeLast(trip);
    await TripStorage.deleteActive(); // clean stop → no recovery prompt
    _trip = null;
    FlutterForegroundTask.sendDataToMain({'event': 'stopped'});
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _sub?.cancel();
    await _activitySub?.cancel();
    await _accSub?.cancel();
    await _gyroSub?.cancel();
    await _stepSub?.cancel();
    await _baroSub?.cancel();
    print('[RRL:osActivity] activitySub cancelled (onDestroy, isTimeout=$isTimeout)');
    final trip = _trip;
    // If we were destroyed without a clean stop, keep active_trip.json around
    // so the app can offer recovery on next launch.
    if (trip != null && trip.end == null) {
      await _persist();
    }
  }

  Future<void> _sampleBattery() async {
    final trip = _trip;
    if (trip == null) return;
    try {
      final level = await _battery.batteryLevel;
      trip.battery.add(BatterySample(at: _now(), level: level));
    } catch (_) {
      // ignore battery read failures
    }
  }

  Future<void> _persist() async {
    final trip = _trip;
    if (trip == null) return;
    try {
      await TripStorage.writeActive(trip);
    } catch (_) {
      // ignore write failures; next tick retries
    }
  }

  void _sendStats() {
    final trip = _trip;
    if (trip == null) return;
    final last = trip.points.isNotEmpty ? trip.points.last : null;
    FlutterForegroundTask.sendDataToMain({
      'event': 'stats',
      'elapsedSec': _now().difference(trip.start).inSeconds,
      'fixCount': trip.points.length,
      'lastSpeed': last?.speed ?? -1.0,
      'lastAccuracy': last?.accuracy ?? -1.0,
      'battery': trip.battery.isNotEmpty ? trip.battery.last.level : -1,
      'modality': _currentModality,
      'osActivity': _lastOsActivityType,
      'devicePlacement': _currentPlacement,
      'accRmsG': _lastAccRmsG,
      'steps': (_lastStepsCumulative != null && _stepsBaseline != null)
          ? _lastStepsCumulative! - _stepsBaseline!
          : null,
    });
  }
}
