import 'package:ringring_logger/quill/registry.dart';
import 'package:test/test.dart';

void main() {
  group('Registry.parse', () {
    const json = '''
    {
      "version": "v1",
      "region": "test-bbox",
      "corridors": [
        {
          "id": "NL-TEST-001",
          "name": "Teststraat",
          "coords": [[52.30, 4.90], [52.30, 4.9015]],
          "lengthM": 102.1
        },
        {
          "id": "NL-TEST-002",
          "name": "Voorbeeldlaan",
          "coords": [[52.301, 4.90], [52.301, 4.9015]],
          "lengthM": 102.1
        }
      ]
    }
    ''';

    test('reads version, region and corridor fields', () {
      final registry = Registry.parse(json);
      expect(registry.version, 'v1');
      expect(registry.region, 'test-bbox');
      expect(registry.corridors, hasLength(2));

      final first = registry.corridors.first;
      expect(first.id, 'NL-TEST-001');
      expect(first.name, 'Teststraat');
      expect(first.lengthM, 102.1);
      expect(first.coords, hasLength(2));
      expect(first.coords.first.lat, 52.30);
      expect(first.coords.first.lng, 4.90);
    });

    test('corridorById finds an existing id and returns null otherwise', () {
      final registry = Registry.parse(json);
      expect(registry.corridorById('NL-TEST-002')?.name, 'Voorbeeldlaan');
      expect(registry.corridorById('does-not-exist'), isNull);
    });
  });
}
