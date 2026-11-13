import Foundation
import Security

enum PreviewFailure: Error { case unavailable, invalid, crypto(Int32), deadline }

/// This extension has no keychain write, delete or migration API.
struct PreviewKeychain {
  let group: String
  func read(_ key: String, cap: Int = 512 * 1024) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "flutter_secure_storage_service",
      kSecAttrAccessGroup as String: group,
      kSecAttrAccount as String: key,
      kSecAttrSynchronizable as String: false,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnData as String: true,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data, data.count <= cap else { throw PreviewFailure.unavailable }
    return data
  }

  func text(_ key: String, cap: Int = 512 * 1024) throws -> String? {
    guard let data = try read(key, cap: cap) else { return nil }
    guard let text = String(data: data, encoding: .utf8) else { throw PreviewFailure.invalid }
    return text
  }

  func object(_ key: String, cap: Int = 512 * 1024) throws -> [String: Any]? {
    guard let data = try read(key, cap: cap) else { return nil }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PreviewFailure.invalid }
    return object
  }
}
