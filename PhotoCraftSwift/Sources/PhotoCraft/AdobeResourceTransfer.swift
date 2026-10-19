import Foundation

struct NativeAdobeResourceTransport: AdobeResourceTransport {
  func fetch(_ url: URL) async throws -> Data {
    return try await AdobeResourceTransfer.perform(
      Self.fetchRequest(url),
      maximumBytes: AdobeActionAssets.maximumResourceBytes)
  }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
    _ = try await AdobeResourceTransfer.perform(
      Self.uploadRequest(data, output: output), maximumBytes: 65_536)
  }
  static func fetchRequest(_ url: URL) throws -> URLRequest {
    var request = try Self.request(url, method: "GET")
    request.setValue("image/vnd.adobe.photoshop, image/png", forHTTPHeaderField: "Accept")
    return request
  }
  static func uploadRequest(_ data: Data, output: AdobeActionsRequest.Output) throws -> URLRequest {
    guard case .external(let url, let storageType) = output.destination else {
      throw AdobeAPIError.invalid("Upload requires an external destination.")
    }
    guard storageType != "dropbox" else {
      throw AdobeAPIError.unsupported("Dropbox output transport is not implemented.")
    }
    guard data.count <= AdobeActionAssets.maximumResourceBytes else {
      throw AdobeAPIError.invalid("Output exceeds the local resource limit.")
    }
    var request = try Self.request(url, method: "PUT")
    request.httpBody = data
    request.setValue(output.mediaType.rawValue, forHTTPHeaderField: "Content-Type")
    if storageType == "azure" {
      request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
    }
    if output.shouldOverwrite == false {
      request.setValue("*", forHTTPHeaderField: "If-None-Match")
    }
    return request
  }
  private static func request(_ url: URL, method: String) throws -> URLRequest {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = parts.scheme?.lowercased(),
      (method == "PUT" ? ["https"] : ["http", "https"]).contains(scheme),
      !(parts.host ?? "").isEmpty, parts.user == nil, parts.password == nil,
      parts.fragment == nil
    else { throw AdobeAPIError.invalid("Invalid resource URL.") }
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    request.httpMethod = method
    return request
  }
}

/// One ephemeral transfer with a byte ceiling enforced as data arrives, even
/// when the server omits Content-Length. All mutable state is protected by lock.
final class AdobeResourceTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private let maximumBytes: Int
  private let configuration: URLSessionConfiguration
  private var continuation: CheckedContinuation<Data, any Error>?
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var receivedResponse = false
  private var bytes = Data()
  private var finished = false

  init(maximumBytes: Int, configuration: URLSessionConfiguration = .ephemeral) {
    self.maximumBytes = maximumBytes
    self.configuration = configuration
    super.init()
  }
  static func perform(
    _ request: URLRequest, maximumBytes: Int,
    configuration: URLSessionConfiguration = .ephemeral
  ) async throws -> Data {
    let transfer = AdobeResourceTransfer(maximumBytes: maximumBytes, configuration: configuration)
    return try await withTaskCancellationHandler(
      operation: {
        try await withCheckedThrowingContinuation { transfer.start(request, continuation: $0) }
      }, onCancel: { transfer.finish(.failure(CancellationError())) })
  }
  private func start(_ request: URLRequest, continuation: CheckedContinuation<Data, any Error>) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      continuation.resume(throwing: CancellationError())
      return
    }
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    configuration.httpMaximumConnectionsPerHost = 1
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    let task = session.dataTask(with: request)
    self.session = session
    self.task = task
    self.continuation = continuation
    lock.unlock()
    task.resume()
  }
  private func finish(_ result: Result<Data, any Error>) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    finished = true
    let continuation = self.continuation
    let session = self.session
    let task = self.task
    self.continuation = nil
    self.session = nil
    self.task = nil
    bytes.removeAll()
    lock.unlock()
    task?.cancel()
    session?.invalidateAndCancel()
    continuation?.resume(with: result)
  }
  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard let response = response as? HTTPURLResponse,
      (200...299).contains(response.statusCode),
      dataTask.originalRequest?.httpMethod != "GET" || response.statusCode == 200
    else {
      completionHandler(.cancel)
      finish(
        .failure(
          AdobeAPIError(
            status: 422, code: "resource_error",
            message: "Resource server returned an unsuccessful HTTP status.")))
      return
    }
    guard response.expectedContentLength <= Int64(maximumBytes) else {
      completionHandler(.cancel)
      finish(.failure(AdobeAPIError.invalid("Resource response exceeds the local byte limit.")))
      return
    }
    lock.lock()
    receivedResponse = true
    let stopped = finished
    lock.unlock()
    completionHandler(stopped ? .cancel : .allow)
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    guard data.count <= maximumBytes - bytes.count else {
      lock.unlock()
      finish(.failure(AdobeAPIError.invalid("Resource response exceeds the local byte limit.")))
      return
    }
    bytes.append(data)
    lock.unlock()
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    if let error {
      finish(.failure(error))
      return
    }
    lock.lock()
    let response = receivedResponse
    let data = bytes
    lock.unlock()
    if response {
      finish(.success(data))
    } else {
      finish(.failure(AdobeAPIError.invalid("Missing HTTP resource response.")))
    }
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
    finish(
      .failure(
        AdobeAPIError.unsupported("Resource redirects are not supported; use the final URL.")))
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    // Use system TLS trust, never ambient credentials for authenticated resources.
    completionHandler(
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        ? .performDefaultHandling : .rejectProtectionSpace, nil)
  }
}
