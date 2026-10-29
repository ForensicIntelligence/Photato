import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canDevelopRaw: Bool { canEditSmartObject && activeLayer?.smartObject?.rawDevelopment != nil }
  func beginRawDevelopment() {
    guard canDevelopRaw,let layer = activeLayer,let settings = layer.smartObject?.rawDevelopment else { return }
    var filter = RasterFilter(.cameraRaw); filter.cameraRaw = settings.adjustments
    filterDraft = FilterDraft(id:layer.id,filter:filter,rawDevelopment:settings)
  }
}
