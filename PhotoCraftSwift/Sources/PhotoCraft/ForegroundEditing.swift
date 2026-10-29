import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  func canDetectSubject(removeBackground: Bool = false) -> Bool {
    guard clipboardTargetAvailable, let layer = activeLayer, case .raster = layer.content,
      (try? ForegroundSelection.checkSize(document.width, document.height)) != nil else { return false }
    return !removeBackground || (!document.isLocked(layer.id) && layer.mask == nil)
  }
  func detectSubject(removeBackground: Bool = false) {
    guard canDetectSubject(removeBackground: removeBackground), let id = activeLayer?.id else { return }
    let detector = foregroundDetector, all = subjectSampleAllLayers
    performGeometry(label: removeBackground ? "Remove Background" : "Select Subject", prepare: { original in
      try await ForegroundSelection.command(document: original, layerID: id,
        removeBackground: removeBackground, sampleAllLayers: all, detector: detector)
    }, onSuccess: { [weak self] in
      if removeBackground { self?.selectMask(id) }
    })
  }
}

extension AppDelegate {
  @objc func selectSubject() { store?.detectSubject() }
}
