import Foundation

public enum PreviewParseError: Error { case invalid, oversized }

public struct PreviewDocument {
  public let id: String
  public let fields: [String: Any]
}

public enum FirestorePreview {
  public static let pageLimit = 10
  public static func component(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 256 && value != "." && value != ".." &&
      value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }
  }

  public static func cursorTimestamp(_ raw: String) throws -> String {
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let seconds = Int64(parts[0]), let nanos = Int64(parts[1]),
          (-62135596800...253402300799).contains(seconds), (0...999999999).contains(nanos) else { throw PreviewParseError.invalid }
    let formatter = ISO8601DateFormatter()
    let base = formatter.string(from: Date(timeIntervalSince1970: Double(seconds)))
    guard base.hasSuffix("Z") else { throw PreviewParseError.invalid }
    return String(base.dropLast()) + "." + String(format: "%09lld", nanos) + "Z"
  }

  public static func query(device: String, cursor: String?) throws -> [String: Any] {
    guard component(device) else { throw PreviewParseError.invalid }
    var query: [String: Any] = [
      "from": [["collectionId": "messages"]],
      "select": ["fields": ["senderUid", "senderDevice", "ts", "envelopes.`\(device)`"].map { ["fieldPath": $0] }],
      "orderBy": [["field": ["fieldPath": "ts"], "direction": cursor == nil ? "DESCENDING" : "ASCENDING"]],
      "limit": pageLimit
    ]
    if let cursor = cursor {
      query["where"] = ["fieldFilter": [
        "field": ["fieldPath": "ts"], "op": "GREATER_THAN_OR_EQUAL",
        "value": ["timestampValue": try cursorTimestamp(cursor)]
      ]]
    }
    return ["structuredQuery": query]
  }

  public static func fields(_ raw: [String: Any]) throws -> [String: Any] {
    var remaining = 2048
    func decode(_ raw: Any, depth: Int) throws -> Any {
      remaining -= 1
      guard remaining >= 0, depth <= 16, let value = raw as? [String: Any], value.count == 1 else { throw PreviewParseError.invalid }
      for key in ["stringValue", "timestampValue"] {
        if let text = value[key] as? String {
          guard text.utf8.count <= 128 * 1024 else { throw PreviewParseError.oversized }
          return text
        }
      }
      if let integer = value["integerValue"] as? String, let number = Int64(integer) { return NSNumber(value: number) }
      if let boolean = value["booleanValue"] as? Bool { return boolean }
      if value["nullValue"] is NSNull { return NSNull() }
      if let map = value["mapValue"] as? [String: Any] {
        guard let children = map["fields"] as? [String: Any] ?? (map.isEmpty ? [:] : nil) else { throw PreviewParseError.invalid }
        var result: [String: Any] = [:]
        for (name, child) in children {
          guard name.utf8.count <= 256 else { throw PreviewParseError.invalid }
          result[name] = try decode(child, depth: depth + 1)
        }
        return result
      }
      if let array = value["arrayValue"] as? [String: Any] {
        guard let children = array["values"] as? [Any] ?? (array.isEmpty ? [] : nil), children.count <= 2048 else { throw PreviewParseError.invalid }
        return try children.map { try decode($0, depth: depth + 1) }
      }
      throw PreviewParseError.invalid
    }
    var result: [String: Any] = [:]
    guard raw.count <= 128 else { throw PreviewParseError.invalid }
    for (name, value) in raw { result[name] = try decode(value, depth: 0) }
    return result
  }

  public static func documents(_ data: Data) throws -> [PreviewDocument] {
    guard data.count <= 512 * 1024,
          let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], rows.count <= 32 else { throw PreviewParseError.oversized }
    var documents: [PreviewDocument] = []
    for row in rows {
      guard let document = row["document"] as? [String: Any] else { continue }
      guard documents.count < pageLimit, let name = document["name"] as? String,
            let id = name.split(separator: "/").last.map(String.init), component(id),
            let raw = document["fields"] as? [String: Any] else { throw PreviewParseError.invalid }
      documents.append(PreviewDocument(id: id, fields: try fields(raw)))
    }
    return documents
  }
}
