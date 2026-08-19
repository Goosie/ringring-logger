import 'dart:math' as math;

import 'package:flutter/material.dart';

/// App version, mirrored from pubspec.yaml (version: 0.5.0+5).
/// The publication pipeline reads pubspec; this constant only lands in the
/// exported JSON's `appVersion` field.
const String kAppVersion = '0.5.0+5';

/// Export schema version. Bumped from the implicit 1 to 2 when the per-second
/// motion summary gained fs-normalized frequency features (windowSecs, fsHz,
/// accP95G, accZcrHz, degraded) and the structured `label` object replaced
/// free-text vehicle/placement labeling.
const int kSchemaVersion = 2;

/// Formats a [DateTime] as UTC ISO-8601 with a trailing `Z` and *no*
/// milliseconds, e.g. `2026-08-13T09:14:05Z`. Matches the legacy Ring-Ring
/// export exactly so a single parser handles both datasets.
String isoZ(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

/// The four modalities the user can declare up front.
enum Modality {
  walk('walk', 'Lopen', Icons.directions_walk),
  bike('bike', 'Fiets', Icons.directions_bike),
  car('car', 'Auto', Icons.directions_car),
  transit('transit', 'OV', Icons.directions_bus);

  const Modality(this.code, this.labelNl, this.icon);

  /// Stable machine code used in the export (walk/bike/car/transit).
  final String code;

  /// Dutch UI label.
  final String labelNl;

  final IconData icon;

  static Modality fromCode(String code) =>
      Modality.values.firstWhere((m) => m.code == code, orElse: () => Modality.walk);
}

/// Where on the body/bike the phone is carried during the trip. Affects how
/// the motion sensors read for a given modality (handlebar vibration reads
/// very differently from a jacket pocket), so it's captured up front and can
/// be re-declared mid-trip via [PlacementSwitch].
enum DevicePlacement {
  handlebar('handlebar', 'Stuur', Icons.pedal_bike),
  pocket('pocket', 'Broekzak', Icons.accessibility_new),
  jacketPocket('jacket_pocket', 'Jaszak', Icons.dry_cleaning),
  bag('bag', 'Tas', Icons.backpack),
  hand('hand', 'Hand', Icons.back_hand);

  const DevicePlacement(this.code, this.labelNl, this.icon);

  /// Stable machine code used in the export.
  final String code;

  /// Dutch UI label.
  final String labelNl;

  final IconData icon;

  static DevicePlacement fromCode(String code) => DevicePlacement.values
      .firstWhere((p) => p.code == code, orElse: () => DevicePlacement.pocket);
}

/// Structured vehicle-class label for [TripLabel]. Finer-grained than
/// [Modality] — in particular it splits "bike" into unassisted/assist_25/
/// assist_45/combustion — because that distinction was previously being
/// smuggled into free-text `deviceLabel`/`note` fields inconsistently
/// ("e-bik-hand", "e-bike achterzak" vs "e-bike broekzak").
enum VehicleClass {
  unassisted('unassisted', 'Onaangedreven'),
  assist25('assist_25', 'E-fiets (25 km/u)'),
  assist45('assist_45', 'Speed-pedelec (45 km/u)'),
  combustion('combustion', 'Verbrandingsmotor'),
  car('car', 'Auto'),
  bus('bus', 'Bus'),
  train('train', 'Trein'),
  walk('walk', 'Lopen'),
  other('other', 'Anders');

  const VehicleClass(this.code, this.labelNl);

  /// Stable machine code used in the export.
  final String code;

  /// Dutch UI label.
  final String labelNl;

  static VehicleClass fromCode(String code) => VehicleClass.values
      .firstWhere((v) => v.code == code, orElse: () => VehicleClass.other);
}

/// Structured phone-placement label for [TripLabel]. A finer-grained sibling
/// of [DevicePlacement], carried separately since [DevicePlacement] also
/// drives the mid-trip [PlacementSwitch] flow.
enum PhonePlacement {
  handlebar('handlebar', 'Stuur'),
  hand('hand', 'Hand'),
  trouserPocket('trouser_pocket', 'Broekzak'),
  jacketPocket('jacket_pocket', 'Jaszak'),
  backpack('backpack', 'Rugzak'),
  pannier('pannier', 'Fietstas'),
  other('other', 'Anders');

  const PhonePlacement(this.code, this.labelNl);

  /// Stable machine code used in the export.
  final String code;

  /// Dutch UI label.
  final String labelNl;

  static PhonePlacement fromCode(String code) => PhonePlacement.values
      .firstWhere((p) => p.code == code, orElse: () => PhonePlacement.other);
}

/// Structured trip label, collected up front on the pre-trip label screen.
/// Every field is an enum code or a number — no free text — so trips are
/// comparable across a batch of measurements. [note]/[deviceLabel] on [Trip]
/// remain free text for anything else, but are no longer used as labels.
class TripLabel {
  const TripLabel({
    required this.vehicleClass,
    required this.phonePlacement,
    required this.routeId,
    required this.runIndex,
  });

  /// A [VehicleClass] code.
  final String vehicleClass;

  /// A [PhonePlacement] code.
  final String phonePlacement;

  /// Short free-typed route identifier (e.g. "ijklus-v1"), picked from a
  /// combobox of previously used values or typed fresh.
  final String routeId;

  /// Repetition number within the same (vehicleClass, phonePlacement,
  /// routeId) cell.
  final int runIndex;

  static const unset = TripLabel(
    vehicleClass: 'other',
    phonePlacement: 'other',
    routeId: '',
    runIndex: 1,
  );

  Map<String, dynamic> toJson() => {
        'vehicleClass': vehicleClass,
        'phonePlacement': phonePlacement,
        'routeId': routeId,
        'runIndex': runIndex,
      };

  factory TripLabel.fromJson(Map<String, dynamic> j) => TripLabel(
        vehicleClass: j['vehicleClass'] as String? ?? 'other',
        phonePlacement: j['phonePlacement'] as String? ?? 'other',
        routeId: j['routeId'] as String? ?? '',
        runIndex: (j['runIndex'] as num?)?.toInt() ?? 1,
      );
}

/// A single GPS fix. Field names lat/lng/speed/date are intentionally identical
/// to the old Ring-Ring export. `speed` stays in m/s exactly as the sensor
/// reports it — never converted in storage.
class TripPoint {
  TripPoint({
    required this.lat,
    required this.lng,
    required this.speed,
    required this.accuracy,
    required this.heading,
    required this.altitude,
    required this.date,
  });

  final double lat;
  final double lng;
  final double speed; // m/s, raw from sensor
  final double accuracy; // meters
  final double heading; // degrees
  final double altitude; // meters
  final DateTime date;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'accuracy': accuracy,
        'heading': heading,
        'altitude': altitude,
        'date': isoZ(date),
      };

  factory TripPoint.fromJson(Map<String, dynamic> j) => TripPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        speed: (j['speed'] as num).toDouble(),
        accuracy: (j['accuracy'] as num).toDouble(),
        heading: (j['heading'] as num).toDouble(),
        altitude: (j['altitude'] as num).toDouble(),
        date: DateTime.parse(j['date'] as String),
      );
}

class ModalitySwitch {
  ModalitySwitch({required this.at, required this.modality});

  final DateTime at;
  final String modality; // modality code

  Map<String, dynamic> toJson() => {'at': isoZ(at), 'modality': modality};

  factory ModalitySwitch.fromJson(Map<String, dynamic> j) => ModalitySwitch(
        at: DateTime.parse(j['at'] as String),
        modality: j['modality'] as String,
      );
}

class PlacementSwitch {
  PlacementSwitch({required this.at, required this.placement});

  final DateTime at;
  final String placement; // device placement code

  Map<String, dynamic> toJson() => {'at': isoZ(at), 'placement': placement};

  factory PlacementSwitch.fromJson(Map<String, dynamic> j) => PlacementSwitch(
        at: DateTime.parse(j['at'] as String),
        placement: j['placement'] as String,
      );
}

/// Per-second summary of accelerometer/gyroscope/step-counter activity while
/// recording. Raw samples are never persisted — only this aggregate. Any
/// field is null when that sensor is unavailable on the device or hasn't
/// produced enough data yet (e.g. accDomHz needs a filled FFT window).
class MotionSample {
  MotionSample({
    required this.at,
    required this.accRmsG,
    required this.accStdG,
    required this.accPeakG,
    required this.accP95G,
    required this.accDomHz,
    required this.accZcr,
    required this.accZcrHz,
    required this.gyroRmsRad,
    required this.gyroPeakRad,
    required this.steps,
    required this.sampleCount,
    required this.windowSecs,
    required this.fsHz,
    required this.degraded,
    this.pressureHpa,
  });

  final DateTime at;
  final double? accRmsG;
  final double? accStdG;
  final double? accPeakG;

  /// 95th percentile of |acc magnitude - 1g| in the window — a robust
  /// counterpart to [accPeakG], which is sensitive to window length.
  final double? accP95G;

  /// Dominant frequency (Hz), computed after resampling the window's
  /// accelerometer signal to a fixed 50.0Hz grid — see [fsHz]/[windowSecs].
  final double? accDomHz;

  /// Zero-crossing count on the same resampled 50.0Hz signal as [accDomHz],
  /// crossing the (magnitude - 1g) zero line, i.e. 1g is subtracted (not the
  /// window mean). Raw count — see [accZcrHz] for the rate.
  final int? accZcr;

  /// [accZcr] / [windowSecs] — zero-crossing rate, comparable across windows
  /// of slightly different length.
  final double? accZcrHz;

  final double? gyroRmsRad;
  final double? gyroPeakRad;
  final int? steps;
  final int sampleCount;

  /// (t_last - t_first) in seconds over the raw samples in this window.
  final double? windowSecs;

  /// (sampleCount - 1) / windowSecs — the effective accelerometer sampling
  /// rate actually achieved this window. This is what varies between ~50Hz
  /// and ~94Hz across (and sometimes within) trips; accDomHz/accZcr/accZcrHz
  /// are normalized against a fixed 50.0Hz grid specifically so they stay
  /// comparable regardless of this value.
  final double? fsHz;

  /// True if a gap wider than 100ms between consecutive accelerometer
  /// samples was found in this window — resampling never interpolates across
  /// it, so accDomHz/accZcr/accZcrHz may be based on a shorter, discontinuous
  /// signal.
  final bool degraded;

  /// Atmospheric pressure in hPa, if this device has a barometer. Optional —
  /// null on devices without one.
  final double? pressureHpa;

  Map<String, dynamic> toJson() => {
        'at': isoZ(at),
        'accRmsG': accRmsG,
        'accStdG': accStdG,
        'accPeakG': accPeakG,
        'accP95G': accP95G,
        'accDomHz': accDomHz,
        'accZcr': accZcr,
        'accZcrHz': accZcrHz,
        'gyroRmsRad': gyroRmsRad,
        'gyroPeakRad': gyroPeakRad,
        'steps': steps,
        'sampleCount': sampleCount,
        'windowSecs': windowSecs,
        'fsHz': fsHz,
        'degraded': degraded,
        'pressureHpa': pressureHpa,
      };

  factory MotionSample.fromJson(Map<String, dynamic> j) => MotionSample(
        at: DateTime.parse(j['at'] as String),
        accRmsG: (j['accRmsG'] as num?)?.toDouble(),
        accStdG: (j['accStdG'] as num?)?.toDouble(),
        accPeakG: (j['accPeakG'] as num?)?.toDouble(),
        accP95G: (j['accP95G'] as num?)?.toDouble(),
        accDomHz: (j['accDomHz'] as num?)?.toDouble(),
        accZcr: (j['accZcr'] as num?)?.toInt(),
        accZcrHz: (j['accZcrHz'] as num?)?.toDouble(),
        gyroRmsRad: (j['gyroRmsRad'] as num?)?.toDouble(),
        gyroPeakRad: (j['gyroPeakRad'] as num?)?.toDouble(),
        steps: (j['steps'] as num?)?.toInt(),
        sampleCount: (j['sampleCount'] as num?)?.toInt() ?? 0,
        windowSecs: (j['windowSecs'] as num?)?.toDouble(),
        fsHz: (j['fsHz'] as num?)?.toDouble(),
        degraded: j['degraded'] as bool? ?? false,
        pressureHpa: (j['pressureHpa'] as num?)?.toDouble(),
      );
}

class BatterySample {
  BatterySample({required this.at, required this.level});

  final DateTime at;
  final int level; // 0..100

  Map<String, dynamic> toJson() => {'at': isoZ(at), 'level': level};

  factory BatterySample.fromJson(Map<String, dynamic> j) => BatterySample(
        at: DateTime.parse(j['at'] as String),
        level: (j['level'] as num).toInt(),
      );
}

class OsActivity {
  OsActivity({required this.at, required this.type, required this.confidence});

  final DateTime at;
  final String type;
  final int confidence;

  Map<String, dynamic> toJson() =>
      {'at': isoZ(at), 'type': type, 'confidence': confidence};

  factory OsActivity.fromJson(Map<String, dynamic> j) => OsActivity(
        at: DateTime.parse(j['at'] as String),
        type: j['type'] as String,
        confidence: (j['confidence'] as num).toInt(),
      );
}

/// One recording session ("rit"). Owns all collected data and knows how to
/// (de)serialize itself to the fixed export schema.
class Trip {
  Trip({
    required this.id,
    required this.deviceLabel,
    required this.note,
    required this.start,
    required this.declaredModality,
    required this.devicePlacement,
    this.end,
    List<ModalitySwitch>? modalitySwitches,
    List<OsActivity>? osActivity,
    List<BatterySample>? battery,
    List<TripPoint>? points,
    List<PlacementSwitch>? placementSwitches,
    List<MotionSample>? motion,
    this.appVersion = kAppVersion,
    this.schemaVersion = kSchemaVersion,
    this.label = TripLabel.unset,
  })  : modalitySwitches = modalitySwitches ?? [],
        osActivity = osActivity ?? [],
        battery = battery ?? [],
        points = points ?? [],
        placementSwitches = placementSwitches ?? [],
        motion = motion ?? [];

  final String id;
  final String appVersion;
  final int schemaVersion;
  final String deviceLabel;
  final String note;
  final DateTime start;
  DateTime? end;
  final String declaredModality; // modality code
  final String devicePlacement; // device placement code
  final TripLabel label;
  final List<ModalitySwitch> modalitySwitches;
  final List<OsActivity> osActivity;
  final List<BatterySample> battery;
  final List<TripPoint> points;
  final List<PlacementSwitch> placementSwitches;
  final List<MotionSample> motion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'appVersion': appVersion,
        'schemaVersion': schemaVersion,
        'deviceLabel': deviceLabel,
        'note': note,
        'start': isoZ(start),
        'end': end == null ? null : isoZ(end!),
        'declaredModality': declaredModality,
        'modalitySwitches': modalitySwitches.map((e) => e.toJson()).toList(),
        'osActivity': osActivity.map((e) => e.toJson()).toList(),
        'battery': battery.map((e) => e.toJson()).toList(),
        'points': points.map((e) => e.toJson()).toList(),
        'devicePlacement': devicePlacement,
        'placementSwitches': placementSwitches.map((e) => e.toJson()).toList(),
        'motion': motion.map((e) => e.toJson()).toList(),
        'label': label.toJson(),
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        appVersion: (j['appVersion'] as String?) ?? kAppVersion,
        schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
        deviceLabel: j['deviceLabel'] as String? ?? '',
        note: j['note'] as String? ?? '',
        start: DateTime.parse(j['start'] as String),
        end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
        declaredModality: j['declaredModality'] as String? ?? 'walk',
        devicePlacement: j['devicePlacement'] as String? ?? 'pocket',
        label: j['label'] == null
            ? TripLabel.unset
            : TripLabel.fromJson(j['label'] as Map<String, dynamic>),
        modalitySwitches: ((j['modalitySwitches'] as List?) ?? [])
            .map((e) => ModalitySwitch.fromJson(e as Map<String, dynamic>))
            .toList(),
        osActivity: ((j['osActivity'] as List?) ?? [])
            .map((e) => OsActivity.fromJson(e as Map<String, dynamic>))
            .toList(),
        battery: ((j['battery'] as List?) ?? [])
            .map((e) => BatterySample.fromJson(e as Map<String, dynamic>))
            .toList(),
        points: ((j['points'] as List?) ?? [])
            .map((e) => TripPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        placementSwitches: ((j['placementSwitches'] as List?) ?? [])
            .map((e) => PlacementSwitch.fromJson(e as Map<String, dynamic>))
            .toList(),
        motion: ((j['motion'] as List?) ?? [])
            .map((e) => MotionSample.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // ---- Derived summary values for the end screen ----

  Duration get duration =>
      (end ?? (points.isNotEmpty ? points.last.date : start)).difference(start);

  int get fixCount => points.length;

  /// The modality code in effect at [at]: the most recent switch at or
  /// before that moment, or [declaredModality] if none happened yet.
  /// Assumes [modalitySwitches] is chronological, which it is — the
  /// recorder only ever appends to it live.
  String modalityAt(DateTime at) {
    var modality = declaredModality;
    for (final s in modalitySwitches) {
      if (s.at.isAfter(at)) break;
      modality = s.modality;
    }
    return modality;
  }

  /// Total distance in km as a haversine sum over consecutive points.
  double get distanceKm {
    double meters = 0;
    for (var i = 1; i < points.length; i++) {
      meters += _haversine(
        points[i - 1].lat,
        points[i - 1].lng,
        points[i].lat,
        points[i].lng,
      );
    }
    return meters / 1000.0;
  }

  /// Median speed in km/h (points' m/s converted for display only).
  double get medianSpeedKmh {
    if (points.isEmpty) return 0;
    final speeds = points.map((p) => p.speed * 3.6).toList()..sort();
    final mid = speeds.length ~/ 2;
    if (speeds.length.isOdd) return speeds[mid];
    return (speeds[mid - 1] + speeds[mid]) / 2.0;
  }

  /// Battery drop in percentage points (first sample minus last sample).
  int get batteryDropPct {
    if (battery.length < 2) return 0;
    return battery.first.level - battery.last.level;
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // earth radius meters
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
