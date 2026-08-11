import 'dart:math' as math;

import 'package:flutter/material.dart';

/// App version, mirrored from pubspec.yaml (version: 0.1.0+1).
/// The publication pipeline reads pubspec; this constant only lands in the
/// exported JSON's `appVersion` field.
const String kAppVersion = '0.1.0+1';

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
    this.end,
    List<ModalitySwitch>? modalitySwitches,
    List<OsActivity>? osActivity,
    List<BatterySample>? battery,
    List<TripPoint>? points,
    this.appVersion = kAppVersion,
  })  : modalitySwitches = modalitySwitches ?? [],
        osActivity = osActivity ?? [],
        battery = battery ?? [],
        points = points ?? [];

  final String id;
  final String appVersion;
  final String deviceLabel;
  final String note;
  final DateTime start;
  DateTime? end;
  final String declaredModality; // modality code
  final List<ModalitySwitch> modalitySwitches;
  final List<OsActivity> osActivity;
  final List<BatterySample> battery;
  final List<TripPoint> points;

  Map<String, dynamic> toJson() => {
        'id': id,
        'appVersion': appVersion,
        'deviceLabel': deviceLabel,
        'note': note,
        'start': isoZ(start),
        'end': end == null ? null : isoZ(end!),
        'declaredModality': declaredModality,
        'modalitySwitches': modalitySwitches.map((e) => e.toJson()).toList(),
        'osActivity': osActivity.map((e) => e.toJson()).toList(),
        'battery': battery.map((e) => e.toJson()).toList(),
        'points': points.map((e) => e.toJson()).toList(),
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        appVersion: (j['appVersion'] as String?) ?? kAppVersion,
        deviceLabel: j['deviceLabel'] as String? ?? '',
        note: j['note'] as String? ?? '',
        start: DateTime.parse(j['start'] as String),
        end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
        declaredModality: j['declaredModality'] as String? ?? 'walk',
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
      );

  // ---- Derived summary values for the end screen ----

  Duration get duration =>
      (end ?? (points.isNotEmpty ? points.last.date : start)).difference(start);

  int get fixCount => points.length;

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
