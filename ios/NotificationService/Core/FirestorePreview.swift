import Foundation

public enum PreviewParseError: Error { case invalid, oversized }

public enum PreviewRequests {
  public static func refresh(apiKey: String, refreshToken: String, timeout: TimeInterval) throws -> URLRequest {
    guard !apiKey.isEmpty, apiKey.utf8.count <= 256, !refreshToken.isEmpty,
          refreshToken.utf8.count <= 16 * 1024, timeout > 0, timeout <= 5 else { throw PreviewParseError.invalid }
    var endpoint = URLComponents(string: "https://securetoken.googleapis.com/v1/token")!
    endpoint.queryItems = [URLQueryItem(name: "key", value: apiKey)]
    var form = URLComponents()
    form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "refresh_token", value: refreshToken)]
    var request = URLRequest(url: endpoint.url!)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    // The credential belongs to the parent app's iOS-restricted Firebase key.
    request.setValue("com.fireplacechat.app", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
    request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    return request
  }
}

public struct PreviewDocument {
  public let id: String
  public let fields: [String: Any]
}

public enum FirestorePreview {
  public static let pageLimit = 10
  public static func pushKey(threadIdentifier: String, legacyMarker: String? = nil, legacyKey: String? = nil) -> String? {
    let key = threadIdentifier.isEmpty ? (legacyMarker == "1" ? legacyKey : nil) : threadIdentifier
    guard let key = key, key.utf8.count == 32,
          key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
    return key
  }
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
