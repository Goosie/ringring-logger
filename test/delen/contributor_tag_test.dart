import 'dart:typed_data';

import 'package:ringring_logger/delen/contributor_tag.dart';
import 'package:test/test.dart';

Uint8List _secret(int seed) => Uint8List.fromList(List<int>.generate(32, (i) => (i + seed) % 256));

void main() {
  final secretA = _secret(0);
  final secretB = _secret(1);

  test('determinism: same secret + corridor + date gives the same tag twice', () {
    final t1 = contributorTag(secretA, 'corr-1', '2026-08-12');
    final t2 = contributorTag(secretA, 'corr-1', '2026-08-12');
    expect(t1, equals(t2));
  });

  test('different corridor gives a different tag', () {
    final t1 = contributorTag(secretA, 'corr-1', '2026-08-12');
    final t2 = contributorTag(secretA, 'corr-2', '2026-08-12');
    expect(t1, isNot(equals(t2)));
  });

  test('different date gives a different tag', () {
    final t1 = contributorTag(secretA, 'corr-1', '2026-08-12');
    final t2 = contributorTag(secretA, 'corr-1', '2026-08-13');
    expect(t1, isNot(equals(t2)));
  });

  test('different secret gives a different tag', () {
    final t1 = contributorTag(secretA, 'corr-1', '2026-08-12');
    final t2 = contributorTag(secretB, 'corr-1', '2026-08-12');
    expect(t1, isNot(equals(t2)));
  });

  test('the pipe separator prevents corridor/date ambiguity', () {
    final t1 = contributorTag(secretA, '12', '3-04-05');
    final t2 = contributorTag(secretA, '123', '-04-05');
    expect(t1, isNot(equals(t2)));
  });

  test('tag is 64 lowercase hex characters', () {
    final tag = contributorTag(secretA, 'corr-1', '2026-08-12');
    expect(tag.length, equals(64));
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(tag), isTrue);
  });

  test('the secret never appears in the output', () {
    final tag = contributorTag(secretA, 'corr-1', '2026-08-12');
    final secretHex = secretA.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(tag.contains(secretHex), isFalse);
    expect(secretHex.contains(tag), isFalse);
  });
}
