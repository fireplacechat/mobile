import CryptoKit
import Darwin
import Foundation

public struct PreviewHistoryTarget {
  public let sender: String
  public let body: String
  public let deleted: Bool
}

public enum PreviewHistory {
  public static let byteLimit = 512 * 1024

  /// Reaction quotes only. A nonempty append log may supersede the snapshot;
  /// use the generic reaction body rather than showing a stale/deleted quote.
  public static func target(directory: URL, chat: String, id: String, key: Data?) throws -> PreviewHistoryTarget? {
    guard let key = key, key.count == 32 else { return nil }
    let hash = SHA256.hash(data: Data(chat.utf8)).map { String(format: "%02x", $0) }.joined()
    let snapshot = directory.appendingPathComponent(hash + ".msgs")
    var metadata = stat()
    let log = snapshot.path + ".log"
    if lstat(log, &metadata) == 0 {
      if metadata.st_size > 0 || (metadata.st_mode & S_IFMT) != S_IFREG { return nil }
    } else if errno != ENOENT { return nil }
    let descriptor = open(snapshot.path, O_RDONLY | O_NOFOLLOW)
    if descriptor < 0 { return nil }
    defer { close(descriptor) }
    guard fstat(descriptor, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFREG,
          metadata.st_size >= 28, metadata.st_size <= byteLimit else { return nil }
    var encrypted = Data(count: Int(metadata.st_size))
    try encrypted.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
      var offset = 0
      while offset < buffer.count {
        let count = read(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
        if count <= 0 { throw PreviewParseError.invalid }
        offset += count
      }
    }
    let box = try AES.GCM.SealedBox(combined: encrypted)
    let plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(chat.utf8))
    guard let records = try JSONSerialization.jsonObject(with: plain) as? [[String: Any]], records.count <= 4096 else { return nil }
    guard let record = records.first(where: { $0["id"] as? String == id && $0["chatId"] as? String == chat }),
          record["status"] as? String == "ok", record["mutation"] == nil,
          record["locallyDeleted"] as? Bool != true,
          let sender = record["senderUid"] as? String, let body = record["body"] as? String else { return nil }
    return PreviewHistoryTarget(sender: sender, body: body, deleted: record["remotelyDeleted"] as? Bool == true)
  }
}
