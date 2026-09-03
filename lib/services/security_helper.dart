// ══════════════════════════════════════════════════════════════════════════════
//  SecurityHelper — password hashing + brute-force protection
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecurityHelper {
  SecurityHelper._();

  // ── SHA-256 hashing ────────────────────────────────────────────────────────
  /// Hash a password with SHA-256. Salted with the identifier (rollNumber /
  /// employeeId) so two users with the same password get different hashes.
  static String hashPassword(String password, String identifier) {
    final salted = '${identifier.toUpperCase()}:$password';
    final bytes  = utf8.encode(salted);
    return sha256.convert(bytes).toString();
  }

  /// Hash with no salt — used only for the initial default hash
  /// stored when the account is first created.
  static String hashRaw(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  /// Check if a stored hash matches a candidate password + identifier.
  static bool verify(String candidate, String identifier, String storedHash) {
    return hashPassword(candidate, identifier) == storedHash;
  }

  /// Check if a stored hash matches a plain SHA-256 of value (legacy/default).
  static bool verifyRaw(String value, String storedHash) {
    return hashRaw(value) == storedHash;
  }

  // ── Brute-force protection ─────────────────────────────────────────────────
  // In-memory attempt tracker — resets on app restart.
  // Persisting to DB would be better for production but adds complexity.
  static final _attempts  = <String, int>{};
  static final _lockUntil = <String, DateTime>{};

  static const _maxAttempts  = 5;
  static const _lockDuration = Duration(minutes: 5);

  /// Returns null if allowed, or a message like "Too many attempts. Try in 4 min."
  static String? checkRateLimit(String key) {
    final lockUntil = _lockUntil[key];
    if (lockUntil != null && DateTime.now().isBefore(lockUntil)) {
      final remaining = lockUntil.difference(DateTime.now()).inMinutes + 1;
      return 'Too many failed attempts. Try again in $remaining min.';
    }
    return null;
  }

  /// Call after a failed login attempt.
  static void recordFailure(String key) {
    _attempts[key] = (_attempts[key] ?? 0) + 1;
    if ((_attempts[key] ?? 0) >= _maxAttempts) {
      _lockUntil[key] = DateTime.now().add(_lockDuration);
      _attempts.remove(key);
    }
  }

  /// Call after a successful login — clear the counter.
  static void recordSuccess(String key) {
    _attempts.remove(key);
    _lockUntil.remove(key);
  }

  // ── Password validation ────────────────────────────────────────────────────
  /// Returns null if valid, or an error message.
  static String? validatePassword(String password) {
    if (password.length < 6) return 'Password must be at least 6 characters.';
    if (password.length > 64) return 'Password must be under 64 characters.';
    // Must have at least one digit OR special char (not purely letters)
    if (!RegExp(r'[0-9!@#\$%^&*()_+\-=\[\]{}|;:,.<>?]').hasMatch(password)) {
      return 'Password must contain at least one number or special character.';
    }
    return null;
  }

  /// Returns true if the password is still the default (i.e. user never changed it)
  static bool isDefaultPassword(String identifier, String storedHash) {
    // Faculty default: hash(employeeId:employeeId)
    return storedHash == hashPassword(identifier, identifier) ||
           // Legacy: stored as plain identifier before hashing was added
           storedHash == identifier;
  }
}
