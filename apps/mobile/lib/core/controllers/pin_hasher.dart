import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hashes the local PIN for at-rest storage. Improves on v1's UNsalted SHA-256 by adding a
/// per-install random salt (generated once at PIN setup, stored beside the hash in secure
/// storage). The PIN/hash never leaves the device — this gates local unlock only.
class PinHasher {
  const PinHasher();

  /// A fresh 16-byte salt, base64url-encoded. [rng] is injectable for deterministic tests.
  String generateSalt([Random? rng]) {
    final r = rng ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// SHA-256 over `salt:pin`. Deterministic given the same inputs.
  String hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// UNsalted lowercase-hex SHA-256 of the raw PIN — the `pin_hash` the registration/login
  /// wire expects (identity Argon2's this server-side; `POST /auth/register` validates a
  /// 64-hex shape and `POST /auth/login` Argon2-verifies the submitted password against it).
  /// This is distinct from [hash] (the salted LOCAL gate digest) — same PIN, different purpose:
  /// [hash] never leaves the device; [pinHash] is the credential sent to identity.
  String pinHash(String pin) => sha256.convert(utf8.encode(pin)).toString();

  /// Constant-time comparison (avoid leaking match progress via timing).
  bool verify(String pin, String salt, String expectedHash) =>
      _constantTimeEquals(hash(pin, salt), expectedHash);

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
