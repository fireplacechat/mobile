/// QR payload for comparing safety numbers: `fireplace://verify/1/<60 digits>`.
/// Both people show the same number; scanning checks it equals ours.
class VerifyPayload {
  VerifyPayload(this.digits);
  final String digits;

  factory VerifyPayload.fromSafetyNumber(String safetyNumber) =>
      VerifyPayload(safetyNumber.replaceAll(' ', ''));

  String encode() => 'fireplace://verify/1/$digits';

  static final _re = RegExp(r'^fireplace://verify/1/(\d{60})$');

  static VerifyPayload? parse(String? raw) {
    final m = _re.firstMatch((raw ?? '').trim());
    return m == null ? null : VerifyPayload(m.group(1)!);
  }

  bool matches(String safetyNumber) =>
      digits == safetyNumber.replaceAll(' ', '');
}
