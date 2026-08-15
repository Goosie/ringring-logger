// Guards the one hard requirement on lib/quill/: it must run under plain
// `dart test`/`dart run`, which means zero Flutter imports anywhere in it.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('lib/quill/ never imports package:flutter', () {
    final dir = Directory('lib/quill');
    final offenders = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (content.contains('package:flutter')) offenders.add(entity.path);
    }
    expect(offenders, isEmpty, reason: 'found package:flutter import in: $offenders');
  });
}
