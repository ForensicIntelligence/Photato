import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RemoveRelatedPreference {
  static let key = "localRemoveRelatedElementsModel"
}

struct RemoveRelatedReview: Sendable {
  let groups: [RemoveRelatedElementGroup]
  var enabled: Set<RemoveRelatedElement>

  init(groups: [RemoveRelatedElementGroup]) {
    self.groups = groups
    enabled = Set(groups.map(\.element))
  }

  var selected: [RemoveRelatedElementGroup] { groups.filter { enabled.contains($0.element) } }
}

extension EditorStore {
  var removeRelatedModelURL: URL? { removeRelatedBookmark.flatMap(GenerativeFillModelPreference.resolve) }

  var canStartRelatedElements: Bool {
    localRemoveAvailable && (removeRelatedModelURL != nil || removeRelatedDetector != nil)
      && canUseRemoveTarget(for: effectiveRemoveSettings(removeSettings, related: true))
      && !removeRelatedArmed && removeDraft == nil && removeStroke == nil && removeApplying == nil
  }

  var canFindRelatedElements: Bool {
    guard removeRelatedArmed, removeRelatedID == nil, removeStroke == nil, canUseRemove,
      let draft = removeDraft, draft.relatedElements, draft.relatedReview == nil,
      draft.hasMarks, removeSourceMatches(draft) else { return false }
    return true
  }

  func effectiveRemoveSettings(_ base: RemoveToolSettings, related: Bool? = nil) -> RemoveToolSettings {
    guard related ?? removeRelatedArmed else { return base }
    var options = base
    options.mode = .generativeOn
    options.createNewLayer = true
    options.removeAfterEachStroke = false
    return options
  }

  func armRelatedElements() throws {
    guard canStartRelatedElements else {
      throw CraftError.unavailable("Choose the Remove and Related Elements models and an eligible RGB layer before starting.")
    }
    removeRelatedArmed = true
    removeRevision = UUID()
    status = "Mark the object, then review its related elements."
  }

  func findRelatedElements() {
    guard canFindRelatedElements else { return }
    removeDetectionTask = Task { [weak self] in
      guard let self else { return }
      defer { if !Task.isCancelled { self.removeDetectionTask = nil } }
      do { _ = try await self.detectRelatedElements() }
      catch is CancellationError { }
      catch { if !Task.isCancelled { self.status = error.localizedDescription } }
    }
  }

  @discardableResult func detectRelatedElements(validate: @escaping @MainActor () throws -> Void = {}) async throws
    -> [RemoveRelatedElementGroup] {
    guard canFindRelatedElements, var draft = removeDraft else {
      throw CraftError.invalid("Mark an object with Related Elements before reviewing it.")
    }
    let id = UUID(), currentTool = tool, testDetector = removeRelatedDetector, modelURL = removeRelatedModelURL
    let request = draft.request, source = draft.original
    removeRelatedID = id; geometryBusy = true; removeRevision = UUID()
    status = "Finding related elements…"
    let worker = Task.detached(priority: .userInitiated) {
      let read = modelURL?.startAccessingSecurityScopedResource() ?? false
      defer { if read { modelURL?.stopAccessingSecurityScopedResource() } }
      let detector: any RemoveRelatedElementDetecting
      if let testDetector { detector = testDetector }
      else if let modelURL { detector = try CoreMLRelatedElements(url: modelURL) }
      else { throw CraftError.unavailable("Choose a model for Related Elements.") }
      return try await RemoveRelatedElements.analyze(request, source: source, detector: detector)
    }
    geometryTask = Task {
      await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() }
    }
    defer {
      if removeRelatedID == id {
        removeRelatedID = nil
        if layerPanelGeneration == draft.generation { geometryBusy = false; geometryTask = nil }
      }
    }
    let analysis = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !worker.isCancelled, removeRelatedID == id, removeSourceMatches(draft), tool == currentTool else { throw CancellationError() }
    geometryBusy = false; geometryTask = nil
    try validate()
    draft.initialCoverage = analysis.object
    draft.initialOverlay = analysis.objectOverlay
    draft.strokes.removeAll()
    draft.relatedReview = RemoveRelatedReview(groups: analysis.groups)
    removeDraft = draft; removeRevision = UUID()
    status = analysis.groups.isEmpty ? "No related elements found. Apply to remove the marked object." : "Review the suggested areas, then Apply."
    return analysis.groups
  }

  func updateRelatedElements(_ enabled: Set<RemoveRelatedElement>) throws {
    guard !geometryBusy, removeStroke == nil, var draft = removeDraft, removeSourceMatches(draft), var review = draft.relatedReview else {
      throw CraftError.invalid("Review an object’s related elements first.")
    }
    guard enabled.isSubset(of: Set(review.groups.map(\.element))) else {
      throw CraftError.invalid("Only suggested related elements can be enabled.")
    }
    review.enabled = enabled
    draft.relatedReview = review; removeDraft = draft; removeRevision = UUID()
  }
}
