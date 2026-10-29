import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var usesModeChannels: Bool { DocumentColorMode.componentModes.contains(document.colorMode) && (document.hasNativeModeStorage || document.depth != .u8) }
  var isCompositeColorTarget: Bool { componentTarget == .composite && modeComponentTargets.isEmpty }
  var modeVisibleComponents: Set<Int> { modeComponentVisibility ?? Set(0..<document.colorMode.componentCount) }
  var canEditModeComponents: Bool {
    guard canSelectComponentTarget, historyOperation == nil, !editingMask, editingChannel == nil,
      let layer = activeLayer, !document.isImageLocked(layer.id), layer.smartObject == nil,
      layer.smartFilters == nil, case .raster = layer.content else { return false }
    return true
  }
  func selectModeComponents(_ components: Set<Int>) throws {
    finishNumericField(); finishLayerName()
    guard usesModeChannels, canSelectComponentTarget, historyOperation == nil,
      components.isSubset(of: Set(0..<document.colorMode.componentCount)), document.quickMask == nil else {
      throw CraftError.invalid("Finish the current interaction and choose valid color components.")
    }
    alphaEditingID = nil; componentTarget = .composite
    maskEditingLayerID = nil; smartFilterMaskEditing = false; clearMaskView()
    modeComponentTargets = components
    if components.isEmpty { modeComponentVisibility = nil }
    else if modeComponentVisibility == nil || !components.isSubset(of: modeVisibleComponents) { modeComponentVisibility = components }
    render()
  }
  func setModeComponentVisibility(_ components: Set<Int>) throws {
    guard usesModeChannels, canChangeChannelVisibility, !components.isEmpty,
      components.isSubset(of: Set(0..<document.colorMode.componentCount)) else {
      throw CraftError.invalid("Choose at least one valid visible component after finishing the current interaction.")
    }
    modeComponentVisibility = document.colorMode.componentCount > 1 && components == Set(0..<document.colorMode.componentCount) ? nil : components
    render()
  }
  func routeModeComponents(_ command: Command) throws -> Command {
    guard !modeComponentTargets.isEmpty else { return command }
    let id: UUID, operation: ModeComponentEdit.Operation
    switch command {
    case .stroke(let layer, let points, let brush): id = layer; operation = .stroke(points, brush)
    case .fill(let layer, let color):
      id = layer; operation = .fill(unit(color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722), color.a)
    case .clear(let layer): id = layer; operation = .fill(1, 1)
    case .applyAdjustment(let layer, .invert): id = layer; operation = .invert
    case .applyFilter(let layer, let filter): id = layer; operation = .filter(filter)
    default: return command
    }
    return .modeComponents(.init(layerID: id, components: modeComponentTargets, operation: operation))
  }
}
