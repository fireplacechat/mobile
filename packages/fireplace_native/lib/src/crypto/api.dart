part of '../../fireplace_crypto.dart';

/// Fixed C signatures: callers cannot accidentally use the wrong signature
/// for an arbitrary symbol. JSON remains the existing protocol representation.
extension NativeCryptoApi on NativeCrypto {
  Map<String, dynamic> identityGenerate() =>
      NativeCrypto.decodeJson(_generate('fp_identity_generate'));
  Uint8List identityPublic(Map<String, dynamic> identity) =>
      _unary('fp_identity_public', NativeCrypto.jsonBytes(identity));
  Uint8List identitySign(Map<String, dynamic> identity, List<int> message) =>
      _binary('fp_identity_sign', NativeCrypto.jsonBytes(identity), message);
  bool identityVerify(
    List<int> identity,
    List<int> message,
    List<int> signature,
  ) => _verify(identity, message, signature);
  bool identityConsistent(Map<String, dynamic> identity) =>
      _checkOne('fp_identity_consistent', NativeCrypto.jsonBytes(identity));
  String fingerprint(List<int> identity) =>
      utf8.decode(_unary('fp_identity_fingerprint', identity));
  String safetyNumber(List<int> a, List<int> b) =>
      utf8.decode(_binary('fp_safety_number', a, b));
  Map<String, dynamic> deviceGenerate() =>
      NativeCrypto.decodeJson(_generate('fp_device_generate'));
  Map<String, dynamic> deviceCertify(
    Map<String, dynamic> device,
    Map<String, dynamic> identity,
    String uid,
  ) => NativeCrypto.decodeJson(
    _ternary(
      'fp_device_certify',
      NativeCrypto.jsonBytes(device),
      NativeCrypto.jsonBytes(identity),
      utf8.encode(uid),
    ),
  );
  bool deviceVerify(Map<String, dynamic> bundle) =>
      _checkOne('fp_device_verify_cert', NativeCrypto.jsonBytes(bundle));
  bool deviceConsistent(Map<String, dynamic> device) =>
      _checkOne('fp_device_consistent', NativeCrypto.jsonBytes(device));
  Map<String, dynamic> prekeyGenerate(int now) =>
      NativeCrypto.decodeJson(_generatePrekey(now));
  Map<String, dynamic> prekeySign(
    Map<String, dynamic> record,
    Map<String, dynamic> identity,
    String uid,
    String device,
  ) => NativeCrypto.decodeJson(
    _quaternary(
      'fp_prekey_sign',
      NativeCrypto.jsonBytes(record),
      NativeCrypto.jsonBytes(identity),
      utf8.encode(uid),
      utf8.encode(device),
    ),
  );
  Map<String, dynamic> prekeyOneTime(Map<String, dynamic> record) =>
      NativeCrypto.decodeJson(
        _unary('fp_prekey_onetime', NativeCrypto.jsonBytes(record)),
      );
  bool prekeyVerify(Map<String, dynamic> bundle, Map<String, dynamic> signed) =>
      _checkTwo(
        'fp_prekey_verify',
        NativeCrypto.jsonBytes(bundle),
        NativeCrypto.jsonBytes(signed),
      );
  Uint8List recoveryGenerate() => _generate('fp_recovery_generate');
  String recoveryDisplay(List<int> key) =>
      utf8.decode(_unary('fp_recovery_display', key));
  Uint8List recoveryParse(String text) =>
      _unary('fp_recovery_parse', utf8.encode(text));
  String recoveryEncrypt(Map<String, dynamic> identity, List<int> key) =>
      utf8.decode(
        _binary('fp_recovery_encrypt', NativeCrypto.jsonBytes(identity), key),
      );
  Map<String, dynamic> recoveryDecrypt(String blob, List<int> key) =>
      NativeCrypto.decodeJson(
        _binary('fp_recovery_decrypt', utf8.encode(blob), key),
      );
  String linkFingerprint(List<int> x, List<int> kem) =>
      utf8.decode(_binary('fp_link_fingerprint', x, kem));
  String linkConfirmation(List<int> identity, List<int> x, List<int> kem) =>
      utf8.decode(_ternary('fp_link_confirmation', identity, x, kem));
  Map<String, dynamic> linkSeal(
    Map<String, dynamic> identity,
    String uid,
    String device,
    List<int> x,
    List<int> kem,
  ) => NativeCrypto.decodeJson(
    _seal(
      NativeCrypto.jsonBytes(identity),
      utf8.encode(uid),
      utf8.encode(device),
      x,
      kem,
    ),
  );
  Map<String, dynamic> linkOpen(
    Map<String, dynamic> sealed,
    String uid,
    Map<String, dynamic> device,
  ) => NativeCrypto.decodeJson(
    _ternary(
      'fp_link_open',
      NativeCrypto.jsonBytes(sealed),
      utf8.encode(uid),
      NativeCrypto.jsonBytes(device),
    ),
  );
  bool sessionValidate(Map<String, dynamic> state) =>
      _checkOne('fp_session_validate', NativeCrypto.jsonBytes(state));
  bool sessionSelfCheck(Map<String, dynamic> state) =>
      _checkOne('fp_session_self_check', NativeCrypto.jsonBytes(state));
}
