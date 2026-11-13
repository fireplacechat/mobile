part of 'crypto_backend.dart';

class Session {
  Session.dart(this._dart) : _rust = null;
  Session.rust(NativeSession session) : _rust = track(session), _dart = null;
  final reference.Session? _dart;
  final NativeSession? _rust;
  static const maxSkip = reference.Session.maxSkip;

  static Future<(Session, reference.HandshakeInit)> initiate({
    required reference.DeviceKeys local,
    required reference.DeviceBundle localBundle,
    required reference.PreKeyBundle remote,
  }) async {
    if (!(initiateWithRust ?? useRust)) {
      final (session, handshake) = await reference.Session.initiate(
        local: local,
        localBundle: localBundle,
        remote: remote,
      );
      return (Session.dart(session), handshake);
    }
    return sessionOperation(() {
      final (session, handshake) = nativeCrypto.initiate(
        local.toJson(),
        bundleJson(localBundle),
        {
          'device': bundleJson(remote.device),
          'signed': {'id': remote.signed.id, ...remote.signed.toFirestore()},
          if (remote.oneTime != null)
            'oneTime': {
              'id': remote.oneTime!.id,
              ...remote.oneTime!.toFirestore(),
            },
        },
        DateTime.now().millisecondsSinceEpoch,
      );
      return (
        Session.rust(session),
        reference.HandshakeInit.fromJson(handshake),
      );
    });
  }

  static Future<Session> accept({
    required reference.DeviceKeys local,
    required reference.DeviceBundle localBundle,
    required reference.DeviceBundle remote,
    required reference.HandshakeInit handshake,
    required reference.PreKeyRecord signedPreKey,
    reference.PreKeyRecord? oneTimePreKey,
  }) async => (acceptWithRust ?? useRust)
      ? sessionOperation(
          () => Session.rust(
            nativeCrypto.accept(
              local.toJson(),
              bundleJson(localBundle),
              bundleJson(remote),
              handshake.toJson(),
              signedPreKey.toJson(),
              oneTimePreKey?.toJson(),
              DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        )
      : Session.dart(
          await reference.Session.accept(
            local: local,
            localBundle: localBundle,
            remote: remote,
            handshake: handshake,
            signedPreKey: signedPreKey,
            oneTimePreKey: oneTimePreKey,
          ),
        );

  factory Session.fromJson(Map<String, dynamic> json) =>
      (reloadWithRust?.call() ?? useRust)
      ? Session.rust(nativeCrypto.loadSession(json))
      : Session.dart(reference.Session.fromJson(json));
  static Session? tryFromJson(Map<String, dynamic> json) {
    if (!useRust) {
      final session = reference.Session.tryFromJson(json);
      return session == null ? null : Session.dart(session);
    }
    return nativeCrypto.sessionValidate(json) ? Session.fromJson(json) : null;
  }

  Map<String, dynamic> toJson() => _dart?.toJson() ?? _rust!.toJson();
  String get sessionId => _dart?.sessionId ?? toJson()['sid'] as String;
  String get localUid => _dart?.localUid ?? toJson()['localUid'] as String;
  String get localDevice =>
      _dart?.localDevice ?? toJson()['localDevice'] as String;
  String get remoteUid => _dart?.remoteUid ?? toJson()['remoteUid'] as String;
  String get remoteDevice =>
      _dart?.remoteDevice ?? toJson()['remoteDevice'] as String;
  bool get isInitiator => _dart?.isInitiator ?? toJson()['isInitiator'] as bool;
  DateTime get createdAt =>
      _dart?.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(toJson()['createdAt'] as int);
  bool get acknowledged => _dart?.acknowledged ?? !toJson().containsKey('hs');
  bool get canSend => _dart?.canSend ?? (toJson()['st'] as Map)['cks'] != null;
  int get sendCounter =>
      _dart?.sendCounter ?? (toJson()['st'] as Map)['ns'] as int;
  Future<bool> selfCheck() async =>
      _dart?.selfCheck() ?? nativeCrypto.sessionSelfCheck(toJson());
  Future<reference.Envelope> encrypt(
    List<int> plain, {
    required String chatId,
  }) async => _dart != null
      ? _dart.encrypt(plain, chatId: chatId)
      : sessionOperation(
          () => reference.Envelope.fromJson(_rust!.encrypt(plain, chatId)),
        );
  Future<Uint8List> decrypt(
    reference.Envelope envelope, {
    required String chatId,
  }) async => _dart != null
      ? _dart.decrypt(envelope, chatId: chatId)
      : sessionOperation(() => _rust!.decrypt(envelope.toJson(), chatId));
}
