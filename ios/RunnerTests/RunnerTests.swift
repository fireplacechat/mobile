import Flutter
import UIKit
import XCTest
import Darwin
import fireplace_native

class RunnerTests: XCTestCase {

  func testCoreSymbolsAreLinkedForDartAndTheTestStreamIsAbsent() throws {
    let handle = try XCTUnwrap(dlopen(nil, RTLD_NOW))
    defer { dlclose(handle) }
    for symbol in [
      "fp_free", "fp_identity_generate", "fp_session_load", "fp_session_save",
      "fp_session_destroy", "fp_session_encrypt_handle", "fp_session_decrypt_handle"
    ] {
      XCTAssertNotNil(dlsym(handle, symbol), "Missing C ABI symbol: \(symbol)")
    }
    XCTAssertNil(dlsym(handle, "fp_set_test_rng"))
    XCTAssertNil(dlsym(handle, "fp_clear_test_rng"))
    let address = try XCTUnwrap(dlsym(handle, "fp_recovery_generate"))
    typealias Generate = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    let generate = unsafeBitCast(address, to: Generate.self)
    XCTAssertEqual(generate(nil), 6) // FP_BAD_ARG; no output allocation escapes.
  }

}

private final class MigrationStore: PreviewKeychainMigrationStore {
  var legacy = ["fictional-account": Data([1, 2, 3])]
  var shared: [String: Data] = [:]
  var failCopy = false
  var failDelete = false
  var failReadBack = false
  func legacyItems() throws -> [String: Data] { legacy }
  func sharedValue(_ account: String) throws -> Data? {
    if failReadBack && shared[account] != nil { throw PreviewStorageError.verification }
    return shared[account]
  }
  func copyToShared(_ account: String, value: Data) throws {
    if failCopy { throw PreviewStorageError.verification }
    shared[account] = value
  }
  func deleteLegacy(_ account: String) throws {
    if failDelete { throw PreviewStorageError.verification }
    legacy.removeValue(forKey: account)
  }
}

extension RunnerTests {
  func testKeychainMigrationCopiesVerifiesAndCanRepeat() throws {
    let store = MigrationStore()
    let original = store.legacy
    try PreviewKeychainMigration.run(store)
    XCTAssertTrue(store.legacy.isEmpty)
    XCTAssertEqual(store.shared, original)
    try PreviewKeychainMigration.run(store)
    XCTAssertEqual(store.shared, original)
  }

  func testMigrationKeepsTheSourceOnCopyReadBackOrDeleteFailure() throws {
    for stage in 0..<3 {
      let store = MigrationStore()
      let original = store.legacy
      store.failCopy = stage == 0
      store.failReadBack = stage == 1
      store.failDelete = stage == 2
      XCTAssertThrowsError(try PreviewKeychainMigration.run(store))
      XCTAssertEqual(store.legacy, original)
      store.failCopy = false
      store.failReadBack = false
      store.failDelete = false
      try PreviewKeychainMigration.run(store)
      XCTAssertTrue(store.legacy.isEmpty)
      XCTAssertEqual(store.shared, original)
    }
  }

  func testMigrationDoesNotOverwriteConflictingCopies() throws {
    let store = MigrationStore()
    store.shared = ["fictional-account": Data([9])]
    let old = store.legacy, shared = store.shared
    XCTAssertThrowsError(try PreviewKeychainMigration.run(store))
    XCTAssertEqual(store.legacy, old)
    XCTAssertEqual(store.shared, shared)
  }
}
