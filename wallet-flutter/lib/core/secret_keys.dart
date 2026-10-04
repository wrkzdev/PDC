// Secret spend and view keys as the wallet engine takes them for "restore from keys": 32 bytes, 64 hex characters each.
// Only the shape is checked here (cheap, so the user gets a clear message); the engine decides whether the two keys
// belong together.

final RegExp _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// Returns [input] trimmed and lower-cased, or throws a FormatException naming [what] ("spend key", "view key").
String normalizeSecretKey(String input, String what) {
  final k = input.trim().toLowerCase();
  if (!_hexKey.hasMatch(k)) {
    throw FormatException('The $what must be 64 hexadecimal characters (0-9, a-f).');
  }
  return k;
}
