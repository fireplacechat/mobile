import Foundation
import UserNotifications
import XCTest

final class NativePreviewTests: XCTestCase {
  func testOnlyOnePreviewCanOwnTheProcessMemoryBudget() {
    let admission = PreviewAdmission()
    var first = admission.acquire()
    XCTAssertNotNil(first)
    XCTAssertNil(admission.acquire())
    first = nil
    let next = admission.acquire()
    XCTAssertNotNil(next)
    withExtendedLifetime(next) {}
  }
  func testOwnedInputWipeClearsEveryByte() {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 3)
    buffer.initialize(repeating: 7, count: 3)
    fireplace_preview_wipe(buffer, 3)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: buffer, count: 3)), [0, 0, 0])
    buffer.deallocate()
  }
  func testSwiftBridgeDecryptsBothDirectionsAndKeepsStoredSnapshotsUnchanged() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "rust_session", withExtension: "json"))
    let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
    for (state, envelope, expected) in [("bobSession", "envelope", "plaintext"), ("aliceSession", "reply", "replyPlaintext")] {
      let data = try XCTUnwrap(fixture[state]?.data(using: .utf8))
      let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(fixture[envelope]!.utf8)) as? [String: Any])
      let first = try PreviewSession(data: data)
      XCTAssertThrowsError(try first.decrypt(envelope: wire, chat: "fictional-wrong-chat"))
      let plain = try first.decrypt(envelope: wire, chat: fixture["chatId"]!)
      XCTAssertEqual(String(data: plain, encoding: .utf8), fixture[expected])
      XCTAssertThrowsError(try first.decrypt(envelope: wire, chat: fixture["chatId"]!))
      let independent = try PreviewSession(data: data)
      XCTAssertEqual(try independent.decrypt(envelope: wire, chat: fixture["chatId"]!), plain)
    }
  }

  func testFallbackAndExpiryDeliverTheOriginalExactlyOnce() {
    let service = NotificationService()
    let content = UNMutableNotificationContent()
    content.body = "New Message"
    let request = UNNotificationRequest(identifier: "fictional", content: content, trigger: nil)
    var completions = 0
    service.didReceive(request) { delivered in
      completions += 1
      XCTAssertEqual(delivered.body, "New Message")
    }
    service.serviceExtensionTimeWillExpire()
    service.serviceExtensionTimeWillExpire()
    XCTAssertEqual(completions, 1)
  }
}
