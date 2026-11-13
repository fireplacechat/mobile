import Flutter
import UIKit
import XCTest
import Darwin

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
