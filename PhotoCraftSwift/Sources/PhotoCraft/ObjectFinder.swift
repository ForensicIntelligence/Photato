import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class ObjectFinderWorkspace {
  var cacheID = UUID()
  var source: ObjectFinderSource?
  var scene: ObjectFinderScene?
  var busy = false
  var error: String?
  var hoveredID: Int?
  var image: CGImage?
  var point: PathPoint?
  var pendingClick: (PathPoint, SelectionMode)?
  @ObservationIgnored var task: Task<Void, Never>?
  @ObservationIgnored var overlayTask: Task<Void, Never>?
  @ObservationIgnored var overlayID = UUID()
  func cancel() {
    task?.cancel(); task = nil; overlayTask?.cancel(); overlayTask = nil
    cacheID = UUID(); overlayID = UUID(); source = nil; scene = nil; busy = false
    error = nil; hoveredID = nil; image = nil; point = nil; pendingClick = nil
  }
}

extension EditorStore {
  var canFindObjects: Bool {
    clipboardTargetAvailable && canUseSelectionTools
      && SelectionToolPreparation.canSample(document,layerID:activeLayer?.id,allLayers:selectionSampleAllLayers)
      && (try? ForegroundSelection.checkSize(document.width, document.height)) != nil
  }
  var objectFinderSource: ObjectFinderSource {
    .init(document, layerID: activeLayer?.id, sampleAllLayers: selectionSampleAllLayers)
  }
  func stopObjectFinder() {
    objectFinder.cancel(); objectFinder.source = objectFinderSource
    objectFinder.error = "Object detection cancelled. Refresh to try again."
  }
  func invalidateObjectFinderIfNeeded() {
    if let source = objectFinder.source, source != objectFinderSource { objectFinder.cancel() }
  }
  func refreshObjectFinderIfNeeded() {
    invalidateObjectFinderIfNeeded()
    if tool == .objectSelection, objectFinderEnabled, canFindObjects { requestObjectFinder() }
  }
  func requestObjectFinder(force: Bool = false) {
    guard canFindObjects else { return }
    let key = objectFinderSource
    if !force, objectFinder.source == key { return }
    objectFinder.cancel(); objectFinder.source = key; objectFinder.busy = true
    let identity = objectFinder.cacheID, original = document, detector = allObjectsDetector
    objectFinder.task = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        try await ObjectFinderScene.detect(original, layerID: key.layerID, sampleAllLayers: key.sampleAllLayers, detector: detector)
      }
      do {
        let scene = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard let self, self.objectFinder.cacheID == identity, self.objectFinderSource == key else { return }
        self.objectFinder.scene = scene; self.objectFinder.busy = false
        if let point = self.objectFinder.point { self.hoverObject(at: point) }
        if let click = self.objectFinder.pendingClick {
          self.objectFinder.pendingClick = nil; self.selectFoundObject(at: click.0, mode: click.1)
        }
      } catch {
        guard let self, self.objectFinder.cacheID == identity else { return }
        self.objectFinder.busy = false; self.objectFinder.pendingClick = nil
        if !(error is CancellationError) { self.objectFinder.error = error.localizedDescription }
      }
    }
  }
  func hoverObject(at point: PathPoint?) {
    guard tool == .objectSelection, objectFinderEnabled, canFindObjects else { clearObjectHover(); return }
    if point != nil { requestObjectFinder() }
    objectFinder.point = point
    let id = point.flatMap { objectFinder.scene?.object(at: $0)?.instanceID }
    setObjectHover(id)
  }
  func clearObjectHover() { objectFinder.point = nil; setObjectHover(nil) }
  func setObjectHover(_ id: Int?, force: Bool = false) {
    guard force || objectFinder.hoveredID != id else { return }
    objectFinder.overlayTask?.cancel(); objectFinder.overlayID = UUID()
    objectFinder.hoveredID = id; objectFinder.image = nil
    guard let id, let mask = objectFinder.scene?.objects.first(where: { $0.instanceID == id })?.mask else { return }
    let color = objectFinderColor, overlayID = objectFinder.overlayID, cacheID = objectFinder.cacheID
    objectFinder.overlayTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) { try SelectionToolPreparation.overlay(mask, color: color) }
      do {
        let image = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, let self, self.objectFinder.overlayID == overlayID, self.objectFinder.cacheID == cacheID else { return }
        self.objectFinder.image = image
      } catch { /* Replaced hover/cancelled inference must not display stale overlays. */ }
    }
  }
  func selectFoundObject(at point: PathPoint, mode: SelectionMode) {
    guard canFindObjects else { return }
    requestObjectFinder()
    if objectFinder.busy {
      objectFinder.pendingClick = (point,mode)
      status = "Detecting objects…"; return
    }
    guard let scene = objectFinder.scene, let object = scene.object(at: point) else {
      status = objectFinder.error ?? "No detected object here. Use Rectangle or Lasso to define a region."; return
    }
    do { performGeometry(try scene.command(instanceID: object.instanceID, mode: mode, hardEdge: objectFinderHardEdge)) }
    catch { self.error = error.localizedDescription }
  }
}
