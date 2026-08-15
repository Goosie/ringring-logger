import 'dart:convert';

/// A single lat/lng pair. Not the app's Trip model's coordinate type —
/// registries and trips are unrelated data on purpose.
class LatLng {
  const LatLng(this.lat, this.lng);

  final double lat;
  final double lng;
}

/// One corridor: today always exactly one NWB wegvak (see
/// tool/build_registry.py — chaining multiple wegvakken into one corridor
/// is out of scope for v1).
class Corridor {
  Corridor({
    required this.id,
    required this.name,
    required this.coords,
    required this.lengthM,
  });

  final String id;
  final String name;
  final List<LatLng> coords;
  final double lengthM;

  factory Corridor.fromJson(Map<String, dynamic> j) => Corridor(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        coords: (j['coords'] as List)
            .map((c) {
              final pair = c as List;
              return LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
            })
            .toList(),
        lengthM: (j['lengthM'] as num).toDouble(),
      );
}

/// A versioned set of corridors, as produced by tool/build_registry.py and
/// bundled as assets/registry/registry-v1.json.
class Registry {
  Registry({required this.version, required this.region, required this.corridors});

  final String version;
  final String region;
  final List<Corridor> corridors;

  factory Registry.fromJson(Map<String, dynamic> j) => Registry(
        version: j['version'] as String,
        region: j['region'] as String? ?? '',
        corridors: (j['corridors'] as List)
            .map((c) => Corridor.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  factory Registry.parse(String jsonStr) =>
      Registry.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

  Corridor? corridorById(String id) {
    for (final c in corridors) {
      if (c.id == id) return c;
    }
    return null;
  }
}
