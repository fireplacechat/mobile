import Darwin
import FireplaceCrypto
import Foundation

private final class CoreInput {
  let pointer: UnsafeMutablePointer<UInt8>
  let count: Int
  init(_ data: Data) throws {
    guard data.count <= 512 * 1024 else { throw PreviewFailure.invalid }
    count = data.count
    pointer = .allocate(capacity: max(1, count))
    data.copyBytes(to: pointer, count: count)
  }
  convenience init(json: [String: Any]) throws {
    try self.init(JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]))
  }
  deinit {
    explicit_bzero(pointer, max(1, count))
    pointer.deallocate()
  }
}

enum PreviewCoreBridge {
  static func check(_ code: Int32) throws {
    if code != 0 { throw PreviewFailure.crypto(code) }
  }
  static func verifyDevice(_ bundle: [String: Any]) throws {
    let input = try CoreInput(json: bundle)
    var valid: Int32 = 0
    try check(fp_device_verify_cert(input.pointer, input.count, &valid))
    guard valid == 1 else { throw PreviewFailure.invalid }
  }
  static func checkDeviceKeys(_ keys: [String: Any]) throws {
    let input = try CoreInput(json: keys)
    var valid: Int32 = 0
    try check(fp_device_consistent(input.pointer, input.count, &valid))
    guard valid == 1 else { throw PreviewFailure.invalid }
  }
  static func bundle(_ raw: [String: Any], uid: String, device: String) throws -> [String: Any] {
    guard let x = raw["x25519Pub"] as? String, let kem = raw["kemPub"] as? String,
          let identity = raw["sigPub"] as? String, let cert = raw["deviceCert"] as? String else { throw PreviewFailure.invalid }
    let value: [String: Any] = ["uid": uid, "deviceId": device, "x25519Pub": x, "kemPub": kem, "identityPub": identity, "cert": cert]
    try verifyDevice(value)
    return value
  }

  static func accept(keys: [String: Any], local: [String: Any], remote: [String: Any],
    handshake: [String: Any], signed: [String: Any], oneTime: [String: Any]?) throws -> PreviewSession {
    let k = try CoreInput(json: keys), l = try CoreInput(json: local), r = try CoreInput(json: remote)
    let h = try CoreInput(json: handshake), s = try CoreInput(json: signed)
    let o = try oneTime.map { try CoreInput(json: $0) }
    var output = FpBuf(ptr: nil, len: 0)
    defer { fp_free(output.ptr, output.len) }
    try check(fp_session_accept(k.pointer, k.count, l.pointer, l.count, r.pointer, r.count,
      h.pointer, h.count, s.pointer, s.count, o?.pointer, o?.count ?? 0,
      Int64(Date().timeIntervalSince1970 * 1000), &output))
    guard let pointer = output.ptr, output.len <= 256 * 1024 else { throw PreviewFailure.invalid }
    return try PreviewSession(data: Data(bytes: pointer, count: output.len))
  }
}

/// In-memory copy only. Saving is intentionally absent from this wrapper.
final class PreviewSession {
  private var handle: OpaquePointer?
  let id: String
  init(data: Data) throws {
    guard data.count <= 256 * 1024,
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sid = json["sid"] as? String else { throw PreviewFailure.invalid }
    id = sid
    let input = try CoreInput(data)
    var valid: Int32 = 0
    try PreviewCoreBridge.check(fp_session_self_check(input.pointer, input.count, &valid))
    guard valid == 1 else { throw PreviewFailure.invalid }
    try PreviewCoreBridge.check(fp_session_load(input.pointer, input.count, &handle))
    guard handle != nil else { throw PreviewFailure.invalid }
  }
  convenience init(json: [String: Any]) throws {
    try self.init(data: JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]))
  }
  deinit { fp_session_destroy(handle) }

  func decrypt(envelope: [String: Any], chat: String) throws -> Data {
    let input = try CoreInput(json: envelope), context = try CoreInput(Data(chat.utf8))
    var state = FpBuf(ptr: nil, len: 0), plain = FpBuf(ptr: nil, len: 0)
    defer { fp_free(state.ptr, state.len); fp_free(plain.ptr, plain.len) }
    try PreviewCoreBridge.check(fp_session_decrypt_handle(handle, input.pointer, input.count,
      context.pointer, context.count, nil, &state, &plain))
    guard plain.len <= 128 * 1024 else { throw PreviewFailure.invalid }
    if plain.len == 0 { return Data() }
    guard let pointer = plain.ptr else { throw PreviewFailure.invalid }
    return Data(bytes: pointer, count: plain.len)
  }
}
