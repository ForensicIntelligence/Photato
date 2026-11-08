import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canFindRemovePeople: Bool {
    canUseRemove && removeDraft == nil && removeStroke == nil && removeDetectionID == nil
  }
  func findRemovePeople() {
    guard canFindRemovePeople else { return }
    removeDetectionTask = Task { [weak self] in
      guard let self else { return }
      defer { if !Task.isCancelled { self.removeDetectionTask = nil } }
      do { _ = try await self.detectRemovePeople() }
      catch is CancellationError { }
      catch { if !Task.isCancelled { self.status = error.localizedDescription } }
    }
  }
  @discardableResult func detectRemovePeople(validate: @escaping @MainActor () throws -> Void = {}) async throws -> RemovePeopleDetection {
    guard canFindRemovePeople, let layerID = activeLayer?.id else {
      throw CraftError.invalid("Apply or clear current Remove marks and finish other work before detecting people.")
    }
    let id = UUID(), original = document, detector = peopleDetector, foreground = foregroundDetector, settings = removeSettings, sourceTool = tool
    let draft = RemoveDraft(original: original, session: sessionGeneration, generation: layerPanelGeneration,
      layerID: layerID, settings: settings)
    removeDraft = draft; removeDetectionID = id; geometryBusy = true; removeRevision = UUID()
    let worker = Task.detached(priority: .userInitiated) {
      try await RemovePeoplePreparation.detect(original, layerID: layerID, settings: settings, detector: detector, foregroundDetector: foreground)
    }
    geometryTask = Task {
      await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() }
    }
    defer {
      if removeDetectionID == id {
        removeDetectionID = nil
        if layerPanelGeneration == draft.generation { geometryBusy = false; geometryTask = nil }
      }
    }
    do {
      let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      guard !worker.isCancelled, removeDetectionID == id, removeSourceMatches(draft), tool == sourceTool else {
        throw CancellationError()
      }
      // Release only our own busy state. Validation/publication below has no suspension point.
      geometryBusy = false; geometryTask = nil
      guard canUseRemove else { throw CraftError.invalid("The Remove target changed during detection.") }
      try validate()
      if let mask = result.coverage {
        var marked = draft; marked.initialCoverage = mask; marked.initialOverlay = result.overlay
        marked.detectedPeople = result.count; removeDraft = marked
        status = "Detected \(result.count) people. Refine the marks, then Apply to remove."
      } else {
        removeDraft = nil
        status = result.protectedCount > 0
          ? "No background people found. Foreground people were kept. No pixels were changed."
          : "No people found. No pixels were changed."
      }
      removeRevision = UUID()
      return result
    } catch {
      if removeDetectionID == id { removeDraft = nil; removeRevision = UUID() }
      throw error
    }
  }
}
