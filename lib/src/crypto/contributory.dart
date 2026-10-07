/// Rejects X25519 outputs that provide no secret contribution.
/// Scan every byte; this does not establish constant-time execution in Dart.
bool isContributoryX25519Secret(List<int> secret) {
  if (secret.length != 32) return false;
  var combined = 0;
  for (final byte in secret) {
    combined |= byte;
  }
  return combined != 0;
}
