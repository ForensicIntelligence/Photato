import Foundation
import PhotoCraftImaging

protocol AdobeResourceTransport: Sendable {
  func fetch(_ url: URL) async throws -> Data
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws
}

/// Asynchronous native jobs operate on isolated input documents. The HTTP service
/// owns authentication and the lifetime of this store; it must revoke on stop.
@MainActor final class AdobeActionJobs {
  enum Status: String, Sendable {
    case notStarted = "not_started"
    case running, succeeded, failed
  }
  struct Output: Sendable {
    enum Content: Sendable {
      case url(URL)
      case embedded(AdobeActionsRequest.EmbeddedFormat, Data)
    }
    let mediaType: AdobeActionsRequest.MediaType
    let content: Content
    var url: URL? {
      if case .url(let url) = content { return url }
      return nil
    }
    var inlineBytes: Int {
      if case .embedded(let format, let bytes) = content {
        return format == .base64 ? (bytes.count + 2) / 3 * 4 : bytes.count
      }
      return 0
    }
    var json: [String: Any] {
      let destination: [String: Any]
      switch content {
      case .url(let url): destination = ["url": url.absoluteString]
      case .embedded(let format, let data):
        let value: Any
        switch format {
        case .json: value = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
        case .string: value = String(decoding: data, as: UTF8.self)
        case .base64: value = data.base64EncodedString()
        }
        destination = ["embedded": format.rawValue, "content": value]
      }
      return ["mediaType": mediaType.rawValue, "destination": destination]
    }
  }
  struct Snapshot: Sendable {
    let id: UUID
    let created: Date
    var modified: Date
    var status: Status
    var outputs: [Output] = []
    var error: AdobeAPIError?
    var response: AutomationResponse {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var json: [String: Any] = [
        "jobId": id.uuidString, "createdTime": formatter.string(from: created),
        "modifiedTime": formatter.string(from: modified), "status": status.rawValue,
      ]
      if status == .succeeded { json["result"] = ["outputs": outputs.map(\.json)] }
      if let error {
        json["errorDetails"] = [["errorCode": error.code, "message": error.message]]
      }
      return .json(json)
    }
  }
  struct Asset: Sendable {
    let data: Data
    let mediaType: String
    let expires: Date
  }
  private enum Request: Sendable {
    case actions(AdobeActionsRequest), background(AdobeRemoveBackgroundRequest), colorEdit(AdobeColorEditRequest), artboards(AdobeArtboardRequest)
    case manifest(AdobeManifestRequest)
    var input: URL? {
      switch self {
      case .actions(let request): request.input
      case .background(let request): request.input
      case .colorEdit(let request): request.input
      case .artboards(let request): request.input
      case .manifest(let request): request.input
      }
    }
  }
  private struct Job {
    let request: Request
    let baseURL: URL
    let assetPath: String
    var snapshot: Snapshot
  }
  private let detector: any ForegroundDetecting
  private let transport: any AdobeResourceTransport
  private let now: @Sendable () -> Date
  private let maximumJobs: Int
  private let maximumStoredBytes: Int
  private var jobs: [UUID: Job] = [:]
  private var queue: [UUID] = []
  private var assets: [UUID: Asset] = [:]
  private var worker: Task<Void, Never>?
  private var generation = UUID()

  init(
    transport: any AdobeResourceTransport, detector: any ForegroundDetecting = VisionForegroundDetector(), maximumJobs: Int = 16,
    maximumStoredBytes: Int = 128 * 1_024 * 1_024,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.transport = transport
    self.detector = detector
    self.maximumJobs = maximumJobs
    self.maximumStoredBytes = maximumStoredBytes
    self.now = now
  }

  func submit(_ request: AdobeActionsRequest, baseURL: URL, assetPath: String = "v2/assets") throws
    -> Snapshot
  {
    try submit(.actions(request), baseURL: baseURL, assetPath: assetPath)
  }
  func submit(_ request: AdobeRemoveBackgroundRequest, baseURL: URL) throws -> Snapshot {
    try submit(.background(request), baseURL: baseURL, assetPath: "v2/assets")
  }
  func submit(_ request: AdobeColorEditRequest, baseURL: URL) throws -> Snapshot {
    try submit(.colorEdit(request), baseURL: baseURL, assetPath: "v2/assets")
  }
  func submit(_ request: AdobeArtboardRequest, baseURL: URL) throws -> Snapshot {
    try submit(.artboards(request), baseURL: baseURL, assetPath: "v2/assets")
  }
  func submit(_ request: AdobeManifestRequest, baseURL: URL) throws -> Snapshot {
    try submit(.manifest(request), baseURL: baseURL, assetPath: "v2/assets")
  }
  private func submit(_ request: Request, baseURL: URL, assetPath: String) throws -> Snapshot {
    prune()
    guard jobs.count < maximumJobs else {
      throw AdobeAPIError(
        status: 429, code: "rate_limit_exceeded",
        message: "The local job limit is reached. Stop the API to revoke jobs or wait for expiry.")
    }
    let id = UUID()
    let timestamp = now()
    let snapshot = Snapshot(id: id, created: timestamp, modified: timestamp, status: .notStarted)
    jobs[id] = Job(request: request, baseURL: baseURL, assetPath: assetPath, snapshot: snapshot)
    queue.append(id)
    schedule()
    return snapshot
  }
  func snapshot(_ id: UUID) -> Snapshot? {
    prune()
    return jobs[id]?.snapshot
  }
  func asset(_ id: UUID) -> Asset? {
    prune()
    return assets[id]
  }
  func revoke() {
    generation = UUID()
    worker?.cancel()
    worker = nil
    queue.removeAll()
    jobs.removeAll()
    assets.removeAll()
  }
  private func prune() {
    let time = now()
    assets = assets.filter { $0.value.expires > time }
    jobs = jobs.filter {
      [.notStarted, .running].contains($0.value.snapshot.status)
        || time.timeIntervalSince($0.value.snapshot.modified) < 86_400
    }
  }
  private func schedule() {
    guard worker == nil, !queue.isEmpty else { return }
    let expected = generation
    let id = queue.removeFirst()
    worker = Task { [weak self] in
      guard let self else { return }
      await self.run(id, generation: expected)
      guard self.generation == expected else { return }
      self.worker = nil
      self.schedule()
    }
  }
  private func check(_ expected: UUID) throws {
    try Task.checkCancellation()
    guard expected == generation else { throw CancellationError() }
  }
  private func run(_ id: UUID, generation expected: UUID) async {
    guard var job = jobs[id], expected == generation else { return }
    job.snapshot.status = .running
    job.snapshot.modified = now()
    jobs[id] = job
    do {
      try check(expected)
      let input: Data
      if let url = job.request.input { input = try await transport.fetch(url) }
      else { input = Data() }
      try check(expected)
      let request = job.request
      let detector = detector
      var fetched: [URL: Data] = [:]
      if case .actions(let action) = request {
        var total = input.count
        let resourceURLs = (action.layerEdits ?? []).flatMap(\.resources)
          + (action.creation?.resource.map { [$0] } ?? [])
          + action.outputs.compactMap { $0.colorProfile?.resource }
        for url in Set(resourceURLs) {
          let data = try await transport.fetch(url)
          try check(expected)
          total += data.count
          guard data.count <= AdobeActionAssets.maximumResourceBytes, total <= AdobeActionAssets.maximumOutputBytes else {
            throw AdobeAPIError.invalid("Job resources exceed the local 128 MiB aggregate limit.")
          }
          fetched[url] = data
        }
      }
      if case .artboards(let artboards) = request {
        var total = input.count
        guard input.count <= AdobeActionAssets.maximumResourceBytes else { throw AdobeAPIError.invalid("Input exceeds64MiB.") }
        for url in Set(artboards.images.map(\.source) + artboards.request.outputs.compactMap { $0.colorProfile?.resource }).subtracting([artboards.input]) {
          let data = try await transport.fetch(url); try check(expected); total += data.count
          guard data.count <= AdobeActionAssets.maximumResourceBytes, total <= AdobeActionAssets.maximumOutputBytes else { throw AdobeAPIError.invalid("Artboard inputs exceed the128MiB aggregate limit.") }
          fetched[url] = data
        }
        fetched[artboards.input] = input
      }
      let resources = fetched
      let computation: Task<AdobeActionAssets.JobResult, Error>
      switch request {
      case .actions(let request):
        computation = Task.detached(priority: .utility) {
          .init(outputs: try AdobeActionAssets.execute(request, input: input, resources: resources))
        }
      case .manifest(let request):
        let assetBase = job.baseURL.appendingPathComponent(job.assetPath)
        computation = Task.detached(priority: .utility) { try request.execute(input: input, assetBase: assetBase) }
      case .artboards(let request):
        computation = Task.detached(priority: .utility) { .init(outputs: try request.execute(resources: resources)) }
      case .colorEdit(let request):
        computation = Task.detached(priority: .utility) { .init(outputs: try request.execute(input: input)) }
      case .background(let request):
        computation = Task.detached(priority: .utility) { .init(outputs: try await request.execute(input: input, detector: detector)) }
      }
      let result = try await withTaskCancellationHandler(
        operation: { try await computation.value }, onCancel: { computation.cancel() })
      try check(expected)
      prune()
      let attachmentBytes = result.attachments.values.reduce(0) { $0 + $1.data.count }
      let needed = result.outputs.reduce(attachmentBytes) { total, item in
        switch item.output.destination {
        case .hosted: return total + item.data.count
        case .external: return total
        case .embedded(let format):
          return total + Output(mediaType: item.output.mediaType, content: .embedded(format, item.data)).inlineBytes
        }
      }
      let hostedBytes = assets.values.reduce(0) { $0 + $1.data.count }
      let embeddedBytes = jobs.values.reduce(0) { total, job in
        total + job.snapshot.outputs.reduce(0) { $0 + $1.inlineBytes }
      }
      guard needed <= maximumStoredBytes - hostedBytes - embeddedBytes else {
        throw AdobeAPIError(
          status: 429, code: "rate_limit_exceeded",
          message: "Hosted or embedded outputs exceed the local storage budget. Wait for output expiry.")
      }
      // Validate and encode all outputs first. Remote PUTs cannot be rolled back
      // if a later destination fails; report failure without publishing hosted assets.
      for item in result.outputs {
        try check(expected)
        if case .external = item.output.destination {
          try await transport.upload(item.data, output: item.output)
        }
      }
      try check(expected)
      let completed = now()
      var pending = result.attachments.mapValues { attachment in
        Asset(data: attachment.data, mediaType: attachment.mediaType,
              expires: completed.addingTimeInterval(TimeInterval(result.attachmentValidity)))
      }
      let outputs = result.outputs.map { item -> Output in
        let content: Output.Content
        switch item.output.destination {
        case .external(let destination, _): content = .url(destination)
        case .embedded(let format): content = .embedded(format, item.data)
        case .hosted(let validity):
          let assetID = UUID()
          pending[assetID] = Asset(
            data: item.data, mediaType: item.output.mediaType.rawValue,
            expires: completed.addingTimeInterval(TimeInterval(validity)))
          content = .url(job.baseURL.appendingPathComponent("\(job.assetPath)/\(assetID.uuidString)"))
        }
        return Output(mediaType: item.output.mediaType, content: content)
      }
      assets.merge(pending) { _, new in new }
      job.snapshot.status = .succeeded
      job.snapshot.modified = completed
      job.snapshot.outputs = outputs
      jobs[id] = job
    } catch {
      guard expected == generation else { return }
      job.snapshot.status = .failed
      job.snapshot.modified = now()
      job.snapshot.error = Self.failure(error)
      jobs[id] = job
    }
  }
  private static func failure(_ error: any Error) -> AdobeAPIError {
    if let error = error as? AdobeAPIError { return error }
    if error is CancellationError {
      return .init(status: 503, code: "job_cancelled", message: "The local job was cancelled.")
    }
    // URLSession errors can include signed resource URLs. Expose neither those
    // credentials nor filesystem paths through the job status response.
    if error is URLError {
      return .init(status: 422, code: "resource_error", message: "Resource transfer failed.")
    }
    return .init(status: 422, code: "processing_error", message: error.localizedDescription)
  }
}
