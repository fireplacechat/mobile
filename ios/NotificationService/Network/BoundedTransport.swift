import Foundation

public enum PreviewNetworkError: Error { case tooLarge, badResponse, cancelled, expired }

/// Cancels before appending a response chunk that would exceed the cap. An
/// ordinary data(for:) call would allocate the entire response before checking.
public final class BoundedTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let configuration: URLSessionConfiguration
  private let limit: Int
  private let state = NSLock()
  private var continuation: CheckedContinuation<Data, Error>?
  private var bytes = Data()
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var cancelled = false

  public init(limit: Int, configuration: URLSessionConfiguration = .ephemeral) {
    self.limit = limit
    self.configuration = configuration
    super.init()
  }

  public func data(for request: URLRequest) async throws -> Data {
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { callback in
        state.lock()
        if cancelled {
          state.unlock()
          callback.resume(throwing: PreviewNetworkError.cancelled)
          return
        }
        continuation = callback
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let connection = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        session = connection
        task = connection.dataTask(with: request)
        task?.resume()
        state.unlock()
      }
    }, onCancel: { self.finish(error: PreviewNetworkError.cancelled) })
  }

  private func finish(error: Error? = nil) {
    state.lock()
    cancelled = true
    let callback = continuation
    continuation = nil
    let result = bytes
    bytes = Data()
    let connection = session
    session = nil
    task = nil
    state.unlock()
    connection?.invalidateAndCancel()
    if let error = error { callback?.resume(throwing: error) }
    else { callback?.resume(returning: result) }
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      completionHandler(.cancel)
      finish(error: PreviewNetworkError.badResponse)
      return
    }
    guard response.expectedContentLength < 0 || response.expectedContentLength <= limit else {
      completionHandler(.cancel)
      finish(error: PreviewNetworkError.tooLarge)
      return
    }
    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    state.lock()
    let overflow = data.count > limit - bytes.count
    if !cancelled && !overflow { bytes.append(data) }
    state.unlock()
    if overflow { finish(error: PreviewNetworkError.tooLarge) }
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    finish(error: error)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) {
    // Neither the bearer token nor refresh-token body may follow a redirect.
    completionHandler(nil)
    finish(error: PreviewNetworkError.badResponse)
  }
}
