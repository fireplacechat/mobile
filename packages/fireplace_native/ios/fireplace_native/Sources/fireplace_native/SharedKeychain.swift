import Foundation
import Security

public protocol PreviewKeychainMigrationStore {
  func legacyItems() throws -> [String: Data]
  func sharedValue(_ account: String) throws -> Data?
  func copyToShared(_ account: String, value: Data) throws
  func deleteLegacy(_ account: String) throws
}

public enum PreviewStorageError: Error {
  case configuration, conflictingCopy, verification, keychain(OSStatus), fileLock
}

/// Copy, read back, compare, then delete. An interrupted run can repeat safely;
/// a conflicting copy is never overwritten and never causes the source to go.
public enum PreviewKeychainMigration {
  public static func run(_ store: PreviewKeychainMigrationStore) throws {
    let items = try store.legacyItems()
    for account in items.keys.sorted() {
      let value = items[account]!
      if let existing = try store.sharedValue(account), existing != value {
        throw PreviewStorageError.conflictingCopy
      }
      try store.copyToShared(account, value: value)
      guard try store.sharedValue(account) == value else {
        throw PreviewStorageError.verification
      }
      try store.deleteLegacy(account)
    }
  }
}

/// Only Fireplace's flutter_secure_storage service is migrated. Firebase
/// Auth's own records stay in the app's original default access group.
struct SystemPreviewKeychain: PreviewKeychainMigrationStore {
  let legacyGroup: String
  let sharedGroup: String
  static let service = "flutter_secure_storage_service"

  private func query(_ group: String, account: String? = nil) -> [String: Any] {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccessGroup as String: group,
      kSecAttrSynchronizable as String: false
    ]
    if let account = account { q[kSecAttrAccount as String] = account }
    return q
  }

  func legacyItems() throws -> [String: Data] {
    var q = query(legacyGroup)
    q[kSecMatchLimit as String] = kSecMatchLimitAll
    q[kSecReturnAttributes as String] = true
    q[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return [:] }
    guard status == errSecSuccess else { throw PreviewStorageError.keychain(status) }
    guard let records = result as? [[String: Any]] else {
      throw PreviewStorageError.verification
    }
    var items: [String: Data] = [:]
    for record in records {
      guard let account = record[kSecAttrAccount as String] as? String,
            let data = record[kSecValueData as String] as? Data,
            items[account] == nil else { throw PreviewStorageError.verification }
      items[account] = data
    }
    return items
  }

  func sharedValue(_ account: String) throws -> Data? {
    var q = query(sharedGroup, account: account)
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    q[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw PreviewStorageError.keychain(status) }
    guard let data = result as? Data else { throw PreviewStorageError.verification }
    return data
  }

  func copyToShared(_ account: String, value: Data) throws {
    let q = query(sharedGroup, account: account)
    let protection: [String: Any] = [
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    var attributes = q.merging(protection) { _, new in new }
    attributes[kSecValueData as String] = value
    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status == errSecDuplicateItem {
      // A previous run copied it before being interrupted. Recheck before
      // changing protection; never replace an independently different key.
      guard try sharedValue(account) == value else {
        throw PreviewStorageError.conflictingCopy
      }
      let updated = SecItemUpdate(q as CFDictionary, protection as CFDictionary)
      guard updated == errSecSuccess else { throw PreviewStorageError.keychain(updated) }
    } else if status != errSecSuccess {
      throw PreviewStorageError.keychain(status)
    }
  }

  func deleteLegacy(_ account: String) throws {
    let status = SecItemDelete(query(legacyGroup, account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw PreviewStorageError.keychain(status)
    }
  }
}
