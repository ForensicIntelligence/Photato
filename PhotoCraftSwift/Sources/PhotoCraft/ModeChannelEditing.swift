import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var usesModeChannels: Bool { DocumentColorMode.componentModes.contains(document.colorMode) && (document.hasNativeModeStorage || document.depth != .u8) }
  var isCompositeColorTarget: Bool { componentTarget == .composite && modeComponentTargets.isEmpty }
  /// Editing intent spans the legacy RGB8 selector and retained/native selectors.
  /// Preview/visibility state keeps its existing independent representation.
  var effectiveComponentTargets: Set<Int> {
    if !modeComponentTargets.isEmpty { return modeComponentTargets }
    guard document.colorMode == .rgb, document.depth == .u8,
      let legacy = componentTarget.editComponents else { return [] }
    return Set([RGBComponents.red,.green,.blue].enumerated().compactMap { legacy.contains($0.element) ? $0.offset:nil })
  }
  var modeVisibleComponents: Set<Int> { colorChannelsVisible ? (modeComponentVisibility ?? Set(0..<document.colorMode.componentCount)):[] }
  var canEditModeComponents: Bool {
    guard canSelectComponentTarget, historyOperation == nil, !editingMask, editingChannel == nil,
      let layer = activeLayer, !document.isImageLocked(layer.id), layer.smartObject == nil,
      layer.smartFilters == nil, case .raster = layer.content else { return false }
    return true
  }
  func selectModeComponents(_ components: Set<Int>) throws {
    finishNumericField(); finishLayerName()
    guard usesModeChannels, canSelectComponentTarget, historyOperation == nil,
      components.isSubset(of: Set(0..<document.colorMode.componentCount)) else {
      throw CraftError.invalid("Finish the current interaction and choose valid color components.")
    }
    selectColorChannelVisibility()
    deselectQuickMaskTarget()
    alphaEditingID = nil; componentTarget = .composite
    maskEditingLayerID = nil; smartFilterMaskEditing = false; clearMaskView()
    modeComponentTargets = components
    if components.isEmpty { modeComponentVisibility = nil }
    else if modeComponentVisibility == nil || !components.isSubset(of: modeVisibleComponents) { modeComponentVisibility = components }
    render()
  }
  func setModeComponentVisibility(_ components: Set<Int>) throws {
    guard usesModeChannels,canSelectComponentTarget,historyOperation==nil,
      components.isSubset(of:Set(0..<document.colorMode.componentCount)) else {throw CraftError.invalid("Choose valid visible components after finishing the current interaction.")}
    guard !components.isEmpty || hasAuxiliaryChannelRows else{throw CraftError.invalid("Retain a visible image component when there are no auxiliary channels.")}
    let before=channelVisibilitySnapshot
    materializeTemporaryMaskView()
    if !components.isEmpty {modeComponentVisibility=document.colorMode.componentCount>1 && components.count==document.colorMode.componentCount ? nil:components}
    var value=savedChannelView;value.imageVisible = !components.isEmpty;savedChannelVisibility=value
    if alphaEditingID != nil {alphaOverlay=value.imageVisible}
    if before != channelVisibilitySnapshot {render()}
  }
  func routeModeComponents(_ command: Command) throws -> Command {
    let targets = effectiveComponentTargets
    guard !targets.isEmpty else { return command }
    let id: UUID, operation: ModeComponentEdit.Operation
    switch command {
    case .stroke(let layer, let points, let brush): id = layer; operation = .stroke(points, brush)
    case .fill(let layer, let color):
      // Keep generic/API Fill aligned with the desktop's explicit neutral scope.
      guard color.r == color.g, color.g == color.b, color.a.isFinite, (0...1).contains(color.a) else {
        throw CraftError.unsupported("Component Fill currently supports neutral colors. Choose Black, 50% Gray or White.")
      }
      id = layer; operation = .fill(color.r, color.a)
    case .clear(let layer): id = layer; operation = .fill(1, 1)
    case .applyAdjustment(let layer, .invert): id = layer; operation = .invert
    case .applyFilter(let layer, let filter): id = layer; operation = .filter(filter)
    default: return command
    }
    return .modeComponents(.init(layerID: id, components: targets, operation: operation))
  }
}
