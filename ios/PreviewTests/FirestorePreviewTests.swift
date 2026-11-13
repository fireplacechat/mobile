import Foundation
import XCTest
import PreviewCore

final class FirestorePreviewTests: XCTestCase {
  func testRefreshUsesTheParentAppKeyRestrictionAndPreservesFormBytes() throws {
    let request = try PreviewRequests.refresh(apiKey: "fictional-key", refreshToken: "fictional+refresh/token==", timeout: 4)
    XCTAssertEqual(request.url?.host, "securetoken.googleapis.com")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier"), "com.fireplacechat.app")
    let body = try XCTUnwrap(String(data: request.httpBody!, encoding: .utf8))
    XCTAssertTrue(body.contains("fictional%2Brefresh"))
    XCTAssertFalse(body.contains("fictional+refresh"))
  }
  func testCurrentApnsThreadKeyWorksWithoutAndroidDataFields() {
    let key = "0123456789abcdef0123456789abcdef"
    XCTAssertEqual(FirestorePreview.pushKey(threadIdentifier: key), key)
    XCTAssertEqual(FirestorePreview.pushKey(threadIdentifier: "", legacyMarker: "1", legacyKey: key), key)
    XCTAssertNil(FirestorePreview.pushKey(threadIdentifier: "", legacyKey: key))
    XCTAssertNil(FirestorePreview.pushKey(threadIdentifier: "INVALID"))
  }
  func testQueryFetchesOnlyOneDeviceAndTenDocuments() throws {
    let body = try FirestorePreview.query(device: "fictional-device", cursor: "1700000000:123456789")
    let query = body["structuredQuery"] as! [String: Any]
    XCTAssertEqual(query["limit"] as? Int, 10)
    let fields = (query["select"] as! [String: [[String: String]]])["fields"]!.compactMap { $0["fieldPath"] }
    XCTAssertEqual(fields, ["senderUid", "senderDevice", "ts", "envelopes.`fictional-device`"])
    XCTAssertEqual(try FirestorePreview.cursorTimestamp("1700000000:123456789"), "2023-11-14T22:13:20.123456789Z")
    XCTAssertThrowsError(try FirestorePreview.query(device: "bad`field", cursor: nil))
    XCTAssertThrowsError(try FirestorePreview.cursorTimestamp("1700000000:1000000000"))
  }

  func testDecodesFirestoreValuesWithoutChangingEnvelopeFields() throws {
    let values: [String: Any] = [
      "senderUid": ["stringValue": "fictional-alice"],
      "envelopes": ["mapValue": ["fields": ["fictional-device": ["mapValue": ["fields": [
        "n": ["integerValue": "7"], "ct": ["stringValue": "fictional-ciphertext"]
      ]]]]]]
    ]
    let decoded = try FirestorePreview.fields(values)
    XCTAssertEqual(decoded["senderUid"] as? String, "fictional-alice")
    let envelope = (decoded["envelopes"] as! [String: [String: Any]])["fictional-device"]!
    XCTAssertEqual(envelope["n"] as? Int, 7)
    XCTAssertEqual(envelope["ct"] as? String, "fictional-ciphertext")
  }

  func testRejectsOversizedPagesAndDeepOrUnrecognisedValues() throws {
    let document: [String: Any] = ["document": [
      "name": "projects/fictional/databases/(default)/documents/chats/a_b/messages/id",
      "fields": ["senderUid": ["stringValue": "a"]]
    ]]
    XCTAssertThrowsError(try FirestorePreview.documents(JSONSerialization.data(withJSONObject: Array(repeating: document, count: 11))))
    var deep: [String: Any] = ["stringValue": "fictional"]
    for _ in 0..<18 { deep = ["mapValue": ["fields": ["nested": deep]]] }
    XCTAssertThrowsError(try FirestorePreview.fields(["deep": deep]))
    XCTAssertThrowsError(try FirestorePreview.fields(["bad": ["unknownValue": 1]]))
  }
}
