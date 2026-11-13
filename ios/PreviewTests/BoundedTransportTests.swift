import Foundation
import XCTest
import PreviewNetworking

private final class FixtureProtocol: URLProtocol {
  static var chunks: [Data] = []
  static var headers: [String: String] = [:]
  static var status = 200
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: Self.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    for chunk in Self.chunks { client?.urlProtocol(self, didLoad: chunk) }
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

final class BoundedTransportTests: XCTestCase {
  private func fetch(limit: Int = 8) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureProtocol.self]
    var request = URLRequest(url: URL(string: "https://firestore.googleapis.com/fictional")!)
    request.timeoutInterval = 1
    return try await BoundedTransport(limit: limit, configuration: configuration).data(for: request)
  }

  override func setUp() {
    FixtureProtocol.status = 200
    FixtureProtocol.headers = [:]
    FixtureProtocol.chunks = []
  }

  func testAcceptsOnlyTheBoundedResponse() async throws {
    FixtureProtocol.chunks = [Data([1, 2]), Data([3])]
    let data = try await fetch()
    XCTAssertEqual(data, Data([1, 2, 3]))
  }

  func testRejectsOversizedAdvertisedOrChunkedResponses() async throws {
    for advertised in [true, false] {
      FixtureProtocol.headers = advertised ? ["Content-Length": "9"] : [:]
      FixtureProtocol.chunks = [Data(repeating: 1, count: 8), Data([2])]
      do { _ = try await fetch(); XCTFail("Oversized response accepted") }
      catch PreviewNetworkError.tooLarge {} catch { XCTFail("Wrong failure kind") }
    }
  }

  func testRejectsAuthenticationAndRedirectResponses() async throws {
    for status in [401, 403, 302] {
      FixtureProtocol.status = status
      do { _ = try await fetch(); XCTFail("Non-success response accepted") }
      catch PreviewNetworkError.badResponse {} catch { XCTFail("Wrong failure kind") }
    }
  }
}
