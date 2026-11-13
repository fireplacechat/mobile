import Foundation
import XCTest
@testable import PreviewCore

final class PreviewTextTests: XCTestCase {
  func testMatchesDartNotificationTextIncludingScalarAndWhitespaceEdges() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "preview-text", withExtension: "json", subdirectory: "fixtures"))
    let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for value in fixture["bodies"] as! [[String: String]] {
      XCTAssertEqual(PreviewText.body(value["text"]!), value["expected"]!)
    }
    for value in fixture["reactions"] as! [[String: String]] {
      XCTAssertEqual(PreviewText.reaction(value["emoji"]!, target: value["text"]!), value["expected"]!)
    }
    XCTAssertEqual(PreviewText.reaction("❤️", target: nil), "Reacted ❤️ to a message")
    for value in fixture["payloads"] as! [[String: Any]] {
      let event = PreviewPayload.decode(try XCTUnwrap(Data(base64Encoded: value["base64"] as! String)))
      let parsed: [String: Any]?
      switch event {
      case .text(let body): parsed = ["kind": "text", "body": body]
      case .reaction(let target, let emoji, let clear): parsed = ["kind": "reaction", "target": target, "emoji": emoji, "clear": clear]
      case .edit(let target, let body): parsed = ["kind": "edit", "target": target, "body": body]
      case .delete(let target): parsed = ["kind": "delete", "target": target]
      case nil: parsed = nil
      }
      if value["expected"] is NSNull { XCTAssertNil(parsed) }
      else { XCTAssertEqual(parsed as NSDictionary?, value["expected"] as? NSDictionary) }
    }
  }
}
