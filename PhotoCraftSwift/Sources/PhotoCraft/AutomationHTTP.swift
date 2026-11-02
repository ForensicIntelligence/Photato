import PhotoCraftCore
import PhotoCraftImaging
import Foundation
import Network

struct AutomationFailure: Error {
  let status: Int
  let message: String
}

struct AutomationRequest: Sendable {
  let method: String
  let path: String
  let headers: [String: String]
  let body: Data

  /// One bounded HTTP/1.1 request per connection. Chunked bodies and pipelining are unsupported.
  static func parse(_ data: Data) throws -> Self? {
    guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
      guard data.count <= 16_384 else {
        throw AutomationFailure(status: 413, message: "Headers too large.")
      }
      return nil
    }
    guard separator.upperBound <= 16_384,
      let header = String(data: data[..<separator.lowerBound], encoding: .utf8),
      header.utf8.allSatisfy({ $0 == 13 || $0 == 10 || (32...126).contains($0) })
    else { throw AutomationFailure(status: 400, message: "Invalid headers.") }
    let lines = header.components(separatedBy: "\r\n")
    let first = lines[0].components(separatedBy: " ")
    guard first.count == 3, first[2] == "HTTP/1.1", ["GET", "POST"].contains(first[0]),
      first[1].hasPrefix("/"), !first[1].contains("%"), !first[1].contains("?"),
      !first[1].contains("#"), !first[1].contains("\\")
    else { throw AutomationFailure(status: 400, message: "Unsupported request line.") }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else {
        throw AutomationFailure(status: 400, message: "Invalid header.")
      }
      let key = String(line[..<colon]).lowercased()
      guard !key.isEmpty,
        key.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
        headers[key] == nil
      else { throw AutomationFailure(status: 400, message: "Invalid or duplicate header.") }
      headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    guard headers["transfer-encoding"] == nil, headers["expect"] == nil else {
      throw AutomationFailure(status: 400, message: "Streaming request bodies are unsupported.")
    }
    let length: Int
    if let raw = headers["content-length"] {
      guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(raw),
        n <= Self.maximumBodyBytes(method: first[0], path: first[1])
      else {
        throw AutomationFailure(status: 413, message: "Body too large or invalid length.")
      }
      length = n
    } else {
      guard first[0] == "GET" else {
        throw AutomationFailure(status: 411, message: "Content-Length required.")
      }
      length = 0
    }
    guard first[0] != "GET" || length == 0 else {
      throw AutomationFailure(status: 400, message: "GET bodies are unsupported.")
    }
    let expected = separator.upperBound + length
    guard data.count <= expected else {
      throw AutomationFailure(status: 400, message: "Pipelining is unsupported.")
    }
    guard data.count == expected else { return nil }
    return Self(
      method: first[0], path: first[1], headers: headers,
      body: data.subdata(in: separator.upperBound..<expected))
  }
  static func maximumBodyBytes(method: String, path: String) -> Int {
    guard method == "POST" else { return 65_536 }
    let parts = path.split(separator: "/")
    if parts.count == 4, parts[0] == "v1", parts[1] == "documents", UUID(uuidString: String(parts[2])) != nil, parts[3] == "commands" { return max(LiquifyMeshFile.maximumBytes, (ICCProfile.maximumBytes + 2) / 3 * 4 + 16_384) }
    if parts.count == 4, parts[0] == "v1", parts[1] == "documents", UUID(uuidString:String(parts[2])) != nil, parts[3] == "audio" { return TimelineAudioSource.maximumBytes }
    if parts.count == 5, parts[0] == "v1", parts[1] == "documents", UUID(uuidString:String(parts[2])) != nil,
      parts[3] == "smart-objects", ["pdf","source"].contains(parts[4]) { return PDFImport.maximumSourceBytes }
    if parts.count == 6, parts[0] == "v1",parts[1] == "documents",UUID(uuidString:String(parts[2])) != nil,
      parts[3] == "smart-objects",UUID(uuidString:String(parts[4])) != nil,["source","linked-source"].contains(parts[5]) {return SmartObject.maximumSourceBytes}
    if path == "/v1/preferences/color-settings" { return ColorSettings.maximumArchiveBytes }
    if path == "/v1/luts" { return ColorLUT.maximumFileBytes }
    if path == "/v1/documents/import" { return DocumentIO.maximumUploadBytes }
    if [PDFImportAPI.inspectPath,PDFImportAPI.importPath,PDFImageImportAPI.inspectPath,PDFImageImportAPI.importPath].contains(path) {return DocumentIO.maximumUploadBytes}
    if ["/v2/create-artboard", "/v2/edit", "/v2/execute-actions", "/v2/create-composite", "/v2/remove-background", "/v1/action-jobs"].contains(path) {
      return AdobeActionsRequest.maximumBodyBytes
    }
    return 65_536
  }
}

struct AutomationResponse: Sendable {
  let status: Int
  let contentType: String
  let body: Data
  var didSend: (@MainActor @Sendable (Bool) -> Void)? = nil
  var headers:[String:String]=[:]
  static func json(_ value: [String: Any], status: Int = 200) -> Self {
    Self(
      status: status, contentType: "application/json",
      body: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
        ?? Data("{}".utf8))
  }
  static func failure(_ error: AutomationFailure, requestData: Data? = nil) -> Self {
    // Framing/host/origin failures occur before the route handler. Retain the
    // published error envelope when the bounded request line identifies Adobe v2.
    if let data = requestData,
      let end = data.prefix(16_384).range(of: Data("\r\n".utf8))?.lowerBound,
      let line = String(data: data[..<end], encoding: .utf8)
    {
      let fields = line.split(separator: " ")
      if fields.count == 3, fields[1].hasPrefix("/v2/") {
        return AdobeAPIError(
          status: error.status,
          code: error.status == 403 ? "unauthorized_forbidden" : "validation_error",
          message: error.message
        ).response
      }
    }
    return .json(["error": error.message], status: error.status)
  }
  var wire: Data {
    let reserved:Set<String>=["content-type","content-length","connection","cache-control","x-content-type-options","x-frame-options","referrer-policy","content-security-policy"]
    let custom=headers.sorted{$0.key.lowercased()<$1.key.lowercased()}.filter {key,value in
      !key.isEmpty && !reserved.contains(key.lowercased()) && key.utf8.allSatisfy{(65...90).contains($0)||(97...122).contains($0)||(48...57).contains($0)||$0==45} && value.utf8.count<=8192 && value.utf8.allSatisfy{(32...126).contains($0)}
    }.map{"\($0.key): \($0.value)\r\n"}.joined()
    let text =
      "HTTP/1.1 \(status) \(status == 200 ? "OK" : status == 201 ? "Created" : status == 202 ? "Accepted" : "Error")\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' blob:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\(custom)\r\n"
    return Data(text.utf8) + body
  }
}

@MainActor final class AutomationHTTPServer {
  typealias Handler = @MainActor (AutomationRequest) async -> AutomationResponse
  private var listener: NWListener?
  private var connections: [UUID: AutomationHTTPConnection] = [:]
  private(set) var port: UInt16?
  private let connectionTimeout: Duration

  init(connectionTimeout: Duration = .seconds(15)) {
    self.connectionTimeout = connectionTimeout
  }

  func start(onState: @escaping @MainActor (UInt16?, String?) -> Void, handler: @escaping Handler)
    throws
  {
    stop()
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
    let listener = try NWListener(using: parameters)
    self.listener = listener
    listener.stateUpdateHandler = { [weak self, weak listener] state in
      Task { @MainActor in
        guard let self, let listener, self.listener === listener else { return }
        switch state {
        case .ready:
          self.port = listener.port?.rawValue
          onState(self.port, nil)
        case .failed:
          self.stop()
          onState(nil, "Could not start the local API. Try starting it again.")
        default: break
        }
      }
    }
    listener.newConnectionHandler = { [weak self, weak listener] connection in
      Task { @MainActor in
        guard let self, let listener, self.listener === listener, let port = self.port,
          self.connections.count < 8
        else {
          connection.cancel()
          return
        }
        let id = UUID()
        let client = AutomationHTTPConnection(connection: connection, port: port,
          connectionTimeout: self.connectionTimeout, handler: handler)
        { [weak self] in
          self?.connections.removeValue(forKey: id)
        }
        self.connections[id] = client
        client.start()
      }
    }
    listener.start(queue: .main)
  }
  func stop() {
    listener?.cancel()
    listener = nil
    port = nil
    let clients = Array(connections.values)
    connections.removeAll()
    clients.forEach { $0.finish() }
  }
}

@MainActor private final class AutomationHTTPConnection {
  let connection: NWConnection
  let port: UInt16
  let connectionTimeout: Duration
  let handler: AutomationHTTPServer.Handler
  let onFinish: @MainActor () -> Void
  var data = Data()
  var finished = false
  var timeout: Task<Void, Never>?
  var work: Task<Void, Never>?
  init(
    connection: NWConnection, port: UInt16, connectionTimeout: Duration,
    handler: @escaping AutomationHTTPServer.Handler,
    onFinish: @escaping @MainActor () -> Void
  ) {
    self.connection = connection
    self.port = port
    self.connectionTimeout = connectionTimeout
    self.handler = handler
    self.onFinish = onFinish
  }
  func start() {
    connection.start(queue: .main)
    armTransferTimeout()
    receive()
  }
  private func armTransferTimeout() {
    timeout?.cancel()
    timeout = Task { [weak self] in
      guard let duration = self?.connectionTimeout else { return }
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      self?.finish()
    }
  }
  func receive() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
      [weak self] bytes, _, complete, error in
      Task { @MainActor in
        guard let self, !self.finished else { return }
        if let bytes { self.data.append(bytes) }
        do {
          if let request = try AutomationRequest.parse(self.data) {
            let authority = "127.0.0.1:\(self.port)"
            guard request.headers["host"] == authority,
              request.headers["origin"] == nil
                || request.headers["origin"] == "http://\(authority)",
              request.headers["sec-fetch-site"] != "cross-site"
            else {
              throw AutomationFailure(
                status: 403, message: "Only same-origin local clients are accepted.")
            }
            // Framing/delivery deadlines must not cancel valid long-running native work.
            // Server stop still cancels the work through finish().
            self.timeout?.cancel()
            self.timeout = nil
            self.work = Task { [weak self] in
              guard let self, !self.finished else { return }
              let response = await self.handler(request)
              guard !self.finished, !Task.isCancelled else {
                response.didSend?(false)
                return
              }
              self.send(response)
            }
          } else if complete || error != nil {
            self.finish()
          } else {
            self.receive()
          }
        } catch let failure as AutomationFailure {
          self.send(.failure(failure, requestData: self.data))
        } catch { self.finish() }
      }
    }
  }
  func send(_ response: AutomationResponse) {
    guard !finished else { response.didSend?(false); return }
    pendingDelivery = response.didSend
    armTransferTimeout()
    connection.send(
      content: response.wire,
      completion: .contentProcessed { [weak self] error in
        Task { @MainActor in
          guard let self, !self.finished else { return }
          let callback = self.pendingDelivery
          self.pendingDelivery = nil
          self.finish()
          callback?(error == nil)
        }
      })
  }
  var pendingDelivery: (@MainActor @Sendable (Bool) -> Void)?
  func finish() {
    guard !finished else { return }
    finished = true
    timeout?.cancel()
    work?.cancel()
    connection.cancel()
    let callback = pendingDelivery
    pendingDelivery = nil
    callback?(false)
    onFinish()
  }
}
