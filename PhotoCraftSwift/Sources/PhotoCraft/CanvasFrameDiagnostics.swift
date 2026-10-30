import AppKit
import QuartzCore

/// Opt-in CPU/scheduling evidence. A draw or display-link callback is not proof
/// that WindowServer physically presented that preview.
@MainActor final class CanvasFrameTrace {
  struct Frame: Sendable {
    let stroke: UUID
    let revision: Int
    let samples: Int
    let input: TimeInterval
  }
  struct Event: Codable, Sendable {
    let kind: String
    let uptime: TimeInterval
    var samples: Int?
    var revision: Int?
    var inputUptime: TimeInterval?
    var eventTimestamp: TimeInterval?
    var durationMS: Double?
    var displayTimestamp: TimeInterval?
    var displayTarget: TimeInterval?
  }
  struct Report: Codable, Sendable {
    let version: Int
    let stroke: UUID
    let tool: String
    let outcome: String
    let droppedEvents: Int
    let events: [Event]
    let physicalPresentationMeasured: Bool
  }
  static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> CanvasFrameTrace? {
    guard let path = environment["PHOTATO_CANVAS_TRACE_DIR"], path.hasPrefix("/") else { return nil }
    return CanvasFrameTrace(directory: URL(fileURLWithPath: path, isDirectory: true))
  }
  let directory: URL
  let limit: Int
  let clock: () -> TimeInterval
  private(set) var events: [Event] = []
  private(set) var droppedEvents = 0
  private(set) var stroke: UUID?
  private(set) var active = false
  private var tool = ""
  private var outcome = "active"
  private var latestInput: TimeInterval = 0
  private var latestPrepared: Frame?
  private var tailTask: Task<Void, Never>?
  init(directory: URL, limit: Int = 20_000, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
    self.directory = directory; self.limit = max(1, limit); self.clock = clock
  }
  func begin(tool: String, eventTimestamp: TimeInterval? = nil) {
    if stroke != nil { _ = flush() }
    stroke = UUID(); self.tool = tool; outcome = "active"; active = true
    events.removeAll(keepingCapacity: true); droppedEvents = 0; latestPrepared = nil
    input(samples: 1, eventTimestamp: eventTimestamp)
  }
  private func record(_ event: Event) {
    guard stroke != nil else { return }
    if events.count < limit { events.append(event) } else { droppedEvents += 1 }
  }
  func input(samples: Int, eventTimestamp: TimeInterval? = nil) {
    guard active else { return }
    latestInput = clock()
    record(Event(kind: "input", uptime: latestInput, samples: samples, eventTimestamp: eventTimestamp))
  }
  func beginFrame(samples: Int, revision: Int) -> Frame? {
    guard active, samples > 0, let stroke else { latestPrepared = nil; return nil }
    let frame = Frame(stroke: stroke, revision: revision, samples: samples, input: latestInput)
    record(Event(kind: "prepare", uptime: clock(), samples: samples, revision: revision, inputUptime: frame.input))
    return frame
  }
  func prepared(_ frame: Frame?) {
    guard let frame, active, frame.stroke == stroke else { return }
    latestPrepared = frame
    record(Event(kind: "ready", uptime: clock(), samples: frame.samples, revision: frame.revision, inputUptime: frame.input))
  }
  func beginDraw() -> (Frame?, TimeInterval)? {
    guard stroke != nil else { return nil }
    return (latestPrepared, clock())
  }
  func drew(_ draw: (Frame?, TimeInterval)?) {
    guard let draw, draw.0 == nil || draw.0?.stroke == stroke else { return }
    let now = clock()
    record(Event(kind: "draw", uptime: now, samples: draw.0?.samples, revision: draw.0?.revision,
      inputUptime: draw.0?.input, durationMS: max(0, now - draw.1) * 1000))
  }
  func display(timestamp: TimeInterval, target: TimeInterval) {
    guard active else { return }
    record(Event(kind: "displayCallback", uptime: clock(), displayTimestamp: timestamp, displayTarget: target))
  }
  func end(cancelled: Bool) {
    guard active else { return }
    record(Event(kind: "end", uptime: clock()))
    active = false; outcome = cancelled ? "cancelled" : "committed"
    tailTask?.cancel()
    tailTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
      guard let self else { return }; _ = self.flush()
    }
  }
  /// Copies a bounded report, then performs file I/O away from input handling.
  @discardableResult func flush() -> Task<URL?, Never>? {
    tailTask?.cancel(); tailTask = nil
    guard let stroke else { return nil }
    let report = Report(version: 1, stroke: stroke, tool: tool, outcome: outcome,
      droppedEvents: droppedEvents, events: events, physicalPresentationMeasured: false)
    self.stroke = nil; active = false; latestPrepared = nil
    let directory = directory
    return Task.detached(priority: .utility) {
      do {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("stroke-\(stroke.uuidString).json")
        try data.write(to: url, options: .atomic); return url
      } catch { NSLog("Photato canvas timing report could not be written"); return nil }
    }
  }
}

@MainActor final class CanvasFrameProbe: NSObject {
  private weak var trace: CanvasFrameTrace?
  private var link: CADisplayLink?
  init(view: NSView, trace: CanvasFrameTrace) {
    self.trace = trace; super.init()
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    self.link = link; link.add(to: .main, forMode: .common)
  }
  @objc private func tick(_ link: CADisplayLink) {
    guard let trace, trace.active else { invalidate(); return }
    trace.display(timestamp: link.timestamp, target: link.targetTimestamp)
  }
  func invalidate() { link?.invalidate(); link = nil }
}

extension CraftCanvas {
  func synchronizeFrameProbe() {
    guard window != nil, let trace = store.canvasFrameTrace, trace.active else {
      frameProbe?.invalidate(); frameProbe = nil; return
    }
    if frameProbe == nil { frameProbe = CanvasFrameProbe(view: self, trace: trace) }
  }
}
