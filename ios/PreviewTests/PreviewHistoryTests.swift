import CryptoKit
import Foundation
import XCTest
import PreviewCore

final class PreviewHistoryTests: XCTestCase {
  func testReadsAuthenticatedSmallHistoryAndRefusesLogsOrLargeFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let chat = "fictional-alice_fictional-bob"
    let key = Data(repeating: 7, count: 32)
    let hash = SHA256.hash(data: Data(chat.utf8)).map { String(format: "%02x", $0) }.joined()
    let file = directory.appendingPathComponent(hash + ".msgs")
    let records: [[String: Any]] = [["id": "target", "chatId": chat, "senderUid": "fictional-alice", "body": "fictional quote", "status": "ok"]]
    let plain = try JSONSerialization.data(withJSONObject: records)
    let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key), authenticating: Data(chat.utf8))
    try XCTUnwrap(box.combined).write(to: file)
    let target = try XCTUnwrap(PreviewHistory.target(directory: directory, chat: chat, id: "target", key: key))
    XCTAssertEqual(target.body, "fictional quote")
    XCTAssertEqual(target.sender, "fictional-alice")
    XCTAssertFalse(target.deleted)
    XCTAssertThrowsError(try PreviewHistory.target(directory: directory, chat: chat, id: "target", key: Data(repeating: 8, count: 32)))
    let log = URL(fileURLWithPath: file.path + ".log")
    try Data([1]).write(to: log)
    XCTAssertNil(try PreviewHistory.target(directory: directory, chat: chat, id: "target", key: key))
    try FileManager.default.removeItem(at: log)
    try Data(repeating: 0, count: PreviewHistory.byteLimit + 1).write(to: file)
    XCTAssertNil(try PreviewHistory.target(directory: directory, chat: chat, id: "target", key: key))
  }
}
