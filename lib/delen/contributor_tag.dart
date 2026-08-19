import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The Mailroom needs to count unique contributors per corridor, not
/// enveloppen — without that, one device that posts the same corridor
/// twice on the same day looks like two contributors, which undermines a
/// k>=5 threshold meant to protect low-traffic corridors. [contributorTag]
/// gives every claim a per-corridor, per-day pseudonym so the Mailroom can
/// deduplicate before counting.
///
/// The tag is `HMAC-SHA256(vaultSecret, "<corridorId>|<date>")`, hex-encoded.
/// The pipe is a deliberate separator: without it, corridor "12" + date
/// "3-04-05" and corridor "123" + date "-04-05" would hash to the same
/// input string.
///
/// Privacy trade-off, accepted by design: within one corridor and one day
/// the tag is a stable pseudonym, so the Mailroom can see that the same
/// device passed twice. Across different corridors or different days the
/// tag is unlinkable — it's derived from a secret that never leaves the
/// device, so nobody outside this app can correlate two tags back to the
/// same contributor.
const _secureStorageKey = 'vault_secret';
const _vaultSecretLength = 32;

/// Loads this installation's vault secret from secure storage (Android
/// Keystore-backed), generating and persisting a fresh 32-byte secret with
/// [Random.secure] on first call. Idempotent: subsequent calls return the
/// exact same bytes. The secret never leaves the device, is never logged,
/// and never appears in the JSON trip export.
Future<Uint8List> loadOrCreateVaultSecret() async {
  const storage = FlutterSecureStorage();
  final existing = await storage.read(key: _secureStorageKey);
  if (existing != null) {
    return base64Decode(existing);
  }

  final random = Random.secure();
  final secret = Uint8List.fromList(
    List<int>.generate(_vaultSecretLength, (_) => random.nextInt(256)),
  );
  await storage.write(key: _secureStorageKey, value: base64Encode(secret));
  return secret;
}

/// Pure function: HMAC-SHA256 of `"<corridorId>|<date>"` keyed by
/// [vaultSecret], hex-encoded lowercase (64 characters). No I/O, no
/// Flutter imports, so it runs under plain `dart test`.
String contributorTag(Uint8List vaultSecret, String corridorId, String date) {
  final hmac = Hmac(sha256, vaultSecret);
  final digest = hmac.convert(utf8.encode('$corridorId|$date'));
  return digest.toString();
}
