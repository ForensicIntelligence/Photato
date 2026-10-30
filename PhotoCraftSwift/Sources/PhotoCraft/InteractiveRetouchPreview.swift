import Foundation
import PhotoCraftCore
import PhotoCraftImaging

actor InteractiveRetouchPreview {
  private let original: CraftDocument
  private let metadata: Command
  private var renderer: IncrementalRetouchRenderer?
  private var unsupported = false
  private var acceptedPoints: [StrokePoint] = []
  private var committed = false
  init?(document: CraftDocument, command: Command) {
    guard DocumentRetouchStrokeSession.supports(document: document, command: command) else { return nil }
    original = document
    switch command {
    case .cloneStamp(let id, var stroke): stroke.points = []; metadata = .cloneStamp(id, stroke)
    case .toning(let id, var stroke): stroke.points = []; metadata = .toning(id, stroke)
    case .focus(let id, var stroke): stroke.points = []; metadata = .focus(id, stroke)
    default: return nil
    }
  }
  private func initialize(points: [StrokePoint]) throws {
    guard renderer == nil else { return }
    let command: Command
    switch metadata {
    case .cloneStamp(let id, var stroke): stroke.points = points; command = .cloneStamp(id, stroke)
    case .toning(let id, var stroke): stroke.points = points; command = .toning(id, stroke)
    case .focus(let id, var stroke): stroke.points = points; command = .focus(id, stroke)
    default: throw CraftError.unsupported("This command uses complete preparation.")
    }
    renderer = try IncrementalRetouchRenderer(document: original, command: command)
  }
  func snapshot(base: CraftDocument, points: [StrokePoint], previous: RenderSnapshot?) throws -> RenderSnapshot? {
    try Task.checkCancellation()
    guard !committed else { throw CancellationError() }
    guard !unsupported, base == original, !points.isEmpty else { return nil }
    if points.count < acceptedPoints.count {
      guard points.elementsEqual(acceptedPoints.prefix(points.count)) else {
        throw CraftError.invalid("The retouching preview source changed.")
      }
      // Actor messages may arrive out of order. Keep newer validated coverage.
      throw CancellationError()
    }
    do {
      try initialize(points: points)
      guard renderer!.hasInputPrefix(points) else { throw CraftError.invalid("The retouching preview source changed.") }
      let snapshot = try renderer!.snapshot(appending: Array(points.dropFirst(renderer!.sampleCount)), reusing: previous)
      acceptedPoints = points
      return snapshot
    } catch is CancellationError {
      renderer = nil; throw CancellationError()
    } catch CraftError.unsupported(_) {
      renderer = nil; unsupported = true; return nil
    }
  }
  func prepareCommit(base: CraftDocument, points: [StrokePoint]) throws -> PreparedEdit? {
    try Task.checkCancellation()
    guard !committed else { throw CraftError.invalid("The retouching stroke has already finished.") }
    guard !unsupported, base == original else { return nil }
    do {
      try initialize(points: points)
      let prepared = try renderer!.prepareEdit(points: points)
      acceptedPoints = points; committed = true
      return prepared
    } catch CraftError.unsupported(_) {
      renderer = nil; unsupported = true; return nil
    }
  }
}

extension EditorStore {
  func scheduleRetouchPreview() {
    guard let draft = cloneDraft, draft.previewCommand != nil, !draft.commitRequested else { return }
    if interactiveRetouchPreview == nil, let command = draft.previewCommand {
      interactiveRetouchPreview = InteractiveRetouchPreview(document: document, command: command)
    }
    guard retouchPreviewTask == nil else { return }
    let generation = UUID(); retouchPreviewGeneration = generation
    retouchPreviewTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled, self.retouchPreviewGeneration == generation {
        let delay = self.retouchPreviewDeadline - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        guard !Task.isCancelled, self.retouchPreviewGeneration == generation,
          let draft = self.cloneDraft, !draft.commitRequested else { break }
        guard draft.sessionGeneration == self.sessionGeneration else { self.cancelClone(); break }
        let count = draft.points.count, now = ProcessInfo.processInfo.systemUptime
        let interval = self.retouchPreviewFrameInterval
        self.retouchPreviewDeadline = self.retouchPreviewDeadline > 0 && now < self.retouchPreviewDeadline + interval
          ? self.retouchPreviewDeadline + interval : now + interval
        self.render(); await self.renderTask?.value
        guard !Task.isCancelled, self.retouchPreviewGeneration == generation else { break }
        if self.cloneDraft?.points.count == count { break }
      }
      if self.retouchPreviewGeneration == generation { self.retouchPreviewTask = nil }
    }
  }
  func stopRetouchPreview(discardRenderer: Bool = true) {
    retouchPreviewGeneration = UUID(); retouchPreviewTask?.cancel(); retouchPreviewTask = nil
    if discardRenderer { interactiveRetouchPreview = nil }
  }
}
