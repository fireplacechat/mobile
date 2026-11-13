import Foundation

struct PreviewDeadline {
  let end: UInt64
  init(seconds: Double = 4.2) { end = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1_000_000_000) }
  var remaining: Double { Double(max(0, Int64(clamping: end) - Int64(clamping: DispatchTime.now().uptimeNanoseconds))) / 1_000_000_000 }
  func check() throws {
    if remaining < 0.05 || Task<Never, Never>.isCancelled { throw PreviewFailure.deadline }
  }
}

struct PreviewCredentials {
  let uid: String, project: String, apiKey: String, idToken: String, refreshToken: String
  let expiresAt: Double
  init(_ json: [String: Any]) throws {
    guard let uid = json["uid"] as? String, FirestorePreview.component(uid),
          let project = json["projectId"] as? String, FirestorePreview.component(project),
          let apiKey = json["apiKey"] as? String, !apiKey.isEmpty, apiKey.utf8.count <= 256,
          let token = json["idToken"] as? String, !token.isEmpty, token.utf8.count <= 16 * 1024,
          let refresh = json["refreshToken"] as? String, !refresh.isEmpty, refresh.utf8.count <= 16 * 1024,
          let expiry = json["expiresAt"] as? NSNumber else { throw PreviewFailure.invalid }
    self.uid = uid; self.project = project; self.apiKey = apiKey
    idToken = token; refreshToken = refresh; expiresAt = expiry.doubleValue / 1000
  }

  func token(deadline: PreviewDeadline) async throws -> String {
    try deadline.check()
    if expiresAt > Date().timeIntervalSince1970 + 30 { return idToken }
    var endpoint = URLComponents(string: "https://securetoken.googleapis.com/v1/token")!
    endpoint.queryItems = [URLQueryItem(name: "key", value: apiKey)]
    var form = URLComponents()
    form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "refresh_token", value: refreshToken)]
    var request = URLRequest(url: endpoint.url!)
    request.httpMethod = "POST"
    request.timeoutInterval = deadline.remaining
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    let data = try await BoundedTransport(limit: 32 * 1024).data(for: request)
    guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          result["user_id"] as? String == uid, let token = result["id_token"] as? String,
          !token.isEmpty, token.utf8.count <= 16 * 1024 else { throw PreviewFailure.invalid }
    // The endpoint is trusted TLS. Inspect audience/subject only as a binding
    // check; Firestore verifies the token's signature and applies its rules.
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { throw PreviewFailure.invalid }
    var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let claimsData = Data(base64Encoded: encoded),
          let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
          claims["sub"] as? String == uid, claims["aud"] as? String == project,
          claims["iss"] as? String == "https://securetoken.google.com/\(project)" else { throw PreviewFailure.invalid }
    return token // No refreshed credential is persisted by the extension.
  }
}

struct PreviewREST {
  let credentials: PreviewCredentials
  let token: String
  let deadline: PreviewDeadline

  private func url(_ components: [String], query: [URLQueryItem] = []) throws -> URL {
    var address = URL(string: "https://firestore.googleapis.com/v1/projects")!
      .appendingPathComponent(credentials.project).appendingPathComponent("databases")
      .appendingPathComponent("(default)").appendingPathComponent("documents")
    for component in components {
      guard FirestorePreview.component(component) else { throw PreviewFailure.invalid }
      address.appendPathComponent(component)
    }
    var result = URLComponents(url: address, resolvingAgainstBaseURL: false)!
    result.queryItems = query.isEmpty ? nil : query
    return result.url!
  }

  private func request(_ url: URL) throws -> URLRequest {
    try deadline.check()
    var request = URLRequest(url: url)
    request.timeoutInterval = deadline.remaining
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }

  func messages(chat: String, device: String, cursor: String?) async throws -> [PreviewDocument] {
    var endpoint = URLComponents(url: try url(["chats", chat]), resolvingAgainstBaseURL: false)!
    endpoint.percentEncodedPath += ":runQuery"
    var call = try request(endpoint.url!)
    call.httpMethod = "POST"
    call.setValue("application/json", forHTTPHeaderField: "Content-Type")
    call.httpBody = try JSONSerialization.data(withJSONObject: FirestorePreview.query(device: device, cursor: cursor))
    let data = try await BoundedTransport(limit: 512 * 1024).data(for: call)
    let rows = try FirestorePreview.documents(data)
    return cursor == nil ? Array(rows.reversed()) : rows
  }

  func device(uid: String, id: String) async throws -> [String: Any] {
    let mask = ["x25519Pub", "kemPub", "sigPub", "deviceCert", "revokedAt"].map { URLQueryItem(name: "mask.fieldPaths", value: $0) }
    let call = try request(url(["users", uid, "devices", id], query: mask))
    let data = try await BoundedTransport(limit: 64 * 1024).data(for: call)
    guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let raw = document["fields"] as? [String: Any] else { throw PreviewFailure.invalid }
    let fields = try FirestorePreview.fields(raw)
    if let revoked = fields["revokedAt"], !(revoked is NSNull) { throw PreviewFailure.invalid }
    return try PreviewCoreBridge.bundle(fields, uid: uid, device: id)
  }
}
