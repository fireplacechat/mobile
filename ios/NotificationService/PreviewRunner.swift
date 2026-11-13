import CryptoKit
import Foundation

struct DecryptedPreview {
  let body: String
  let message: String
}

private enum PreviewAttempt {
  case body(DecryptedPreview), remoteDevice(String), none
}

final class PreviewRunner {
  let store: PreviewKeychain
  let root: URL
  let deadline: PreviewDeadline
  private var sessions: [String: PreviewSession] = [:]
  private var sessionPins: [String: String] = [:]

  init(store: PreviewKeychain, root: URL, deadline: PreviewDeadline) {
    self.store = store; self.root = root; self.deadline = deadline
  }

  private func locked<T>(uid: String, _ read: () throws -> T) throws -> T {
    try deadline.check()
    let lock = try PreviewReadLock(file: root.appendingPathComponent("locks/\(uid).lock"),
      deadline: min(deadline.end, DispatchTime.now().uptimeNanoseconds + 150_000_000))
    return try withExtendedLifetime(lock, read)
  }

  private func chat(key: String, uid: String) throws -> String {
    guard key.count == 32, key.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
          let data = try store.read("pushchats:\(uid)", cap: 128 * 1024),
          let ids = try JSONSerialization.jsonObject(with: data) as? [String], ids.count <= 1000 else { throw PreviewFailure.unavailable }
    for id in ids {
      guard id.utf8.count <= 256, FirestorePreview.component(id) else { continue }
      let digest = SHA256.hash(data: Data(("fireplace-push:" + id).utf8))
        .map { String(format: "%02x", $0) }.joined()
      if String(digest.prefix(32)) == key { return id }
    }
    throw PreviewFailure.unavailable
  }

  private func peer(chat: String, uid: String) throws -> String {
    let parts = chat.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2, parts.contains(uid) else { throw PreviewFailure.invalid }
    let peer = parts[0] == uid ? parts[1] : parts[0]
    guard peer != uid, FirestorePreview.component(peer) else { throw PreviewFailure.invalid }
    return peer
  }

  func run(key: String, credentials: PreviewCredentials) async throws -> DecryptedPreview? {
    let uid = credentials.uid
    let snapshot = try locked(uid: uid) { () -> (String, String, String?) in
      guard try store.read("pushoff:\(uid)") == nil,
            try store.read("pushnopreview:\(uid)") == nil,
            let device = try store.object("device:\(uid)"), let id = device["deviceId"] as? String,
            FirestorePreview.component(id), try store.read("journal:\(id)") == nil else { throw PreviewFailure.unavailable }
      if let legacy = try store.text("journals:\(id)"), legacy != "[]" { throw PreviewFailure.unavailable }
      let chat = try self.chat(key: key, uid: uid)
      return (chat, id, try store.text("cursor:\(id):\(chat)", cap: 128))
    }
    let (chat, local, cursor) = snapshot
    let other = try peer(chat: chat, uid: uid)
    let rest = PreviewREST(credentials: credentials, token: try await credentials.token(deadline: deadline), deadline: deadline)
    let documents = try await rest.messages(chat: chat, device: local, cursor: cursor)
    var remote: [String: [String: Any]] = [:]
    var last: DecryptedPreview?
    for document in documents {
      try deadline.check()
      var attempt = try locked(uid: uid) {
        try autoreleasepool { try self.attempt(document, uid: uid, peer: other, local: local, chat: chat, remote: remote) }
      }
      if case .remoteDevice(let device) = attempt {
        // A certificate read is needed only for a new handshake; established
        // sessions have already authenticated their peer in the app.
        guard remote.count < 2 else { throw PreviewFailure.unavailable }
        remote[device] = try await rest.device(uid: other, id: device)
        attempt = try locked(uid: uid) {
          try autoreleasepool { try self.attempt(document, uid: uid, peer: other, local: local, chat: chat, remote: remote) }
        }
      }
      if case .body(let preview) = attempt { last = preview }
      else { last = nil } // Never retain a quote/text superseded by a mutation.
    }
    return last
  }

  private func attempt(_ doc: PreviewDocument, uid: String, peer: String, local: String,
    chat: String, remote: [String: [String: Any]]) throws -> PreviewAttempt {
    // Recheck local choices and journals on each read snapshot. The app may
    // have changed them while the bounded network request was in progress.
    guard try store.read("pushoff:\(uid)") == nil, try store.read("pushnopreview:\(uid)") == nil,
          try store.read("journal:\(local)") == nil,
          let auth = try store.object("ios-preview-auth", cap: 32 * 1024), auth["uid"] as? String == uid else { throw PreviewFailure.unavailable }
    if let legacy = try store.text("journals:\(local)"), legacy != "[]" { throw PreviewFailure.unavailable }
    guard doc.fields["senderUid"] as? String == peer,
          let sender = doc.fields["senderDevice"] as? String, FirestorePreview.component(sender),
          let envelopes = doc.fields["envelopes"] as? [String: Any],
          let envelope = envelopes[local] as? [String: Any], let sid = envelope["sid"] as? String else { return .none }
    let pair = try JSONSerialization.data(withJSONObject: [uid, peer], options: [.withoutEscapingSlashes])
    guard let pairText = String(data: pair, encoding: .utf8),
          let pin = try store.text("pin:account:" + pairText, cap: 16 * 1024) else { return .none }
    let cacheKey = sender + ":" + sid
    var session = sessions[cacheKey]
    if session != nil && sessionPins[cacheKey] != pin { throw PreviewFailure.unavailable }
    if session == nil {
      guard sessions.count < 2 else { throw PreviewFailure.unavailable }
      if let data = try store.read("sess:\(local):\(peer):\(sender)", cap: 512 * 1024),
         let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], records.count <= 32 {
        if let record = records.first(where: { $0["sid"] as? String == sid && $0["localUid"] as? String == uid &&
          $0["localDevice"] as? String == local && $0["remoteUid"] as? String == peer && $0["remoteDevice"] as? String == sender }) {
          session = try PreviewSession(json: record)
        }
      }
      if session == nil {
        guard let handshake = envelope["hs"] as? [String: Any] else { return .none }
        guard let bundle = remote[sender] else { return .remoteDevice(sender) }
        guard let identity = bundle["identityPub"] as? String,
              let pinned = Self.base64(pin), pinned == Self.base64(identity),
              let keys = try store.object("device:\(uid)"), keys["deviceId"] as? String == local,
              let raw = try store.object("bundle:\(uid)"),
              raw["x25519Pub"] as? String == keys["x25519Pub"] as? String,
              raw["kemPub"] as? String == keys["kemPub"] as? String,
              let prekeys = try store.object("prekeys:\(uid):\(local)"),
              let signedId = handshake["spk"] as? String,
              let signed = (prekeys["signed"] as? [[String: Any]])?.first(where: { $0["id"] as? String == signedId }) else { return .none }
        let opk = handshake["opk"] as? String
        let oneTime = opk.flatMap { (prekeys["oneTime"] as? [String: [String: Any]])?[$0] }
        if opk != nil && oneTime == nil { return .none }
        try PreviewCoreBridge.checkDeviceKeys(keys)
        var signedKeys = signed
        signedKeys["deviceId"] = "preview-prekey"
        try PreviewCoreBridge.checkDeviceKeys(signedKeys)
        if var oneTimeKeys = oneTime {
          oneTimeKeys["deviceId"] = "preview-prekey"
          try PreviewCoreBridge.checkDeviceKeys(oneTimeKeys)
        }
        session = try PreviewCoreBridge.accept(keys: keys,
          local: PreviewCoreBridge.bundle(raw, uid: uid, device: local), remote: bundle,
          handshake: handshake, signed: signed, oneTime: oneTime)
      }
      guard let created = session, created.id == sid else { return .none }
      sessions[cacheKey] = created
      sessionPins[cacheKey] = pin
    }
    guard let session = session else { return .none }
    let event: PreviewEvent?
    do { event = PreviewPayload.decode(try session.decrypt(envelope: envelope, chat: chat)) }
    catch PreviewFailure.crypto(let code) {
      if code == 2 { return .none } // Replayed/already received or invalid ciphertext.
      throw PreviewFailure.crypto(code)
    }
    switch event {
    case .text(let body): return .body(DecryptedPreview(body: PreviewText.body(body), message: doc.id))
    case .reaction(let target, let emoji, let clear):
      if clear { return .none }
      let encoded = try store.text("msgkey:\(uid)", cap: 1024)
      let key = encoded.flatMap { PreviewRunner.base64($0) }
      let original = try PreviewHistory.target(directory: root.appendingPathComponent("messages_\(uid)"), chat: chat, id: target, key: key)
      if let original = original, original.sender != uid || original.deleted { return .none }
      return .body(DecryptedPreview(body: PreviewText.reaction(emoji, target: original?.body), message: target))
    // Suppression of a newly arriving alert needs Apple's filtering entitlement.
    // Retain the original push for mutation cases this extension cannot match.
    case .edit, .delete, nil: return .none
    }
  }

  static func base64(_ text: String) -> Data? {
    var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    value += String(repeating: "=", count: (4 - value.count % 4) % 4)
    return Data(base64Encoded: value)
  }
}
