import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RemoveDistractionModelPreference {
  static let key = "removeGeneralDistractionModel"

  static func url(bookmark: Data?) -> URL? {
    bookmark.flatMap(GenerativeFillModelPreference.resolve)
      ?? Bundle.main.url(forResource: CoreMLDistractionDetector.modelName, withExtension: "mlmodelc")
  }
}

struct RemoveDistractionReview: Sendable {
  let groups: [RemoveDistractionGroup]
  var enabled: Set<RemoveDistractionCategory>
  var overlayOpacity: Double = 0.45

  init(groups: [RemoveDistractionGroup]) {
    self.groups = groups
    enabled = Set(groups.map(\.category))
  }

  var selectedGroups: [RemoveDistractionGroup] { groups.filter { enabled.contains($0.category) } }
}

extension EditorStore {
  var canFindGeneralDistractions: Bool {
    canFindRemovePeople && removeDistractionID == nil && removeApplying == nil
  }

  func findGeneralDistractions() {
    guard canFindGeneralDistractions else { return }
    removeDetectionTask = Task { [weak self] in
      guard let self else { return }
      defer { if !Task.isCancelled { self.removeDetectionTask = nil } }
      do { _ = try await self.detectGeneralDistractions() }
      catch is CancellationError { }
      catch { if !Task.isCancelled { self.status = error.localizedDescription } }
    }
  }

  @discardableResult func detectGeneralDistractions(validate: @escaping @MainActor () throws -> Void = {}) async throws
    -> [RemoveDistractionGroup] {
    guard canFindGeneralDistractions, let layerID = activeLayer?.id else {
      throw CraftError.invalid("Apply or clear current Remove marks and finish other work before finding distractions.")
    }
    let id = UUID(), source = document, sourceTool = tool, options = removeSettings
    let bookmark = removeDistractionModelBookmark, testDetector = removeDistractionDetector
    let draft = RemoveDraft(original: source, session: sessionGeneration, generation: layerPanelGeneration,
      layerID: layerID, settings: options)
    removeDraft = draft; removeDistractionID = id; geometryBusy = true; removeRevision = UUID()
    status = "Finding general distractions…"
    let worker = Task.detached(priority: .userInitiated) {
      let url = RemoveDistractionModelPreference.url(bookmark: bookmark)
      let scoped = url?.startAccessingSecurityScopedResource() ?? false
      defer { if scoped { url?.stopAccessingSecurityScopedResource() } }
      let detector: any RemoveDistractionDetecting
      if let testDetector { detector = testDetector }
      else { detector = NativeDistractionDetection(model: try url.map { try CoreMLDistractionDetector(url: $0) }) }
      return try await RemoveDistractionPreparation.detect(source, layerID: layerID, settings: options, detector: detector)
    }
    geometryTask = Task {
      await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() }
    }
    defer {
      if removeDistractionID == id {
        removeDistractionID = nil
        if layerPanelGeneration == draft.generation { geometryBusy = false; geometryTask = nil }
      }
    }
    do {
      let groups = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      guard !worker.isCancelled, removeDistractionID == id, removeSourceMatches(draft), tool == sourceTool else { throw CancellationError() }
      geometryBusy = false; geometryTask = nil
      guard canUseRemove else { throw CraftError.invalid("The Remove target changed during detection.") }
      try validate()
      var reviewed = draft
      reviewed.distractionReview = .init(groups: groups)
      removeDraft = reviewed; removeRevision = UUID()
      status = groups.isEmpty ? "No general distractions found." : "Review the marked distractions, then Apply."
      return groups
    } catch {
      if removeDistractionID == id { removeDraft = nil; removeRevision = UUID() }
      throw error
    }
  }

  func updateGeneralDistractions(categories: Set<RemoveDistractionCategory>? = nil, opacity: Double? = nil) throws {
    guard !geometryBusy, removeStroke == nil, var draft = removeDraft, removeSourceMatches(draft),
      var review = draft.distractionReview else { throw CraftError.invalid("Find distractions before changing the review.") }
    if let categories {
      guard categories.isSubset(of: Set(review.groups.map(\.category))) else {
        throw CraftError.invalid("Only detected distraction categories can be enabled.")
      }
      review.enabled = categories
    }
    if let opacity {
      guard opacity.isFinite, (0...1).contains(opacity) else { throw CraftError.invalid("Overlay opacity must be between 0 and 1.") }
      review.overlayOpacity = opacity
    }
    draft.distractionReview = review; removeDraft = draft; removeRevision = UUID()
  }
}
