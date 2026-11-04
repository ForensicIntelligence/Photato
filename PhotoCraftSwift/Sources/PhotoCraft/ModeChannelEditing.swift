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
  var modeVisibleComponents: Set<Int> {
    guard colorChannelsVisible else { return [] }
    if !usesModeChannels, document.colorMode == .rgb {
      return Set(channelView.visible.map { $0.rawValue - 1 })
    }
    return modeComponentVisibility ?? Set(0..<document.colorMode.componentCount)
  }
  var colorComponentTargetTitle: String {
    if !modeComponentTargets.isEmpty {
      return modeComponentTargets.sorted().map { document.colorMode.componentNames[$0] }.joined(separator: ", ")
    }
    return usesModeChannels ? document.colorMode.title : componentTarget.title
  }
  func isColorComponentSelected(_ component: Int?) -> Bool {
    guard !editingMask, editingChannel == nil else { return false }
    return component.map { effectiveComponentTargets.isEmpty || effectiveComponentTargets.contains($0) }
      ?? isCompositeColorTarget
  }
  /// Both channel panels dispatch the effective set, independently of the eyes.
  func selectColorComponentRow(_ component: Int?, modifiers: NSEvent.ModifierFlags) throws {
    var selection = component.map { Set([$0]) } ?? []
    if let component, modifiers.contains(.shift) {
      selection = effectiveComponentTargets.isEmpty ? Set(0..<document.colorMode.componentCount) : effectiveComponentTargets
      if selection.contains(component) {
        // An empty API set means composite, not "no editing target".
        // Keep the final individual target until that context is qualified.
        if selection.count > 1 { selection.remove(component) }
      } else { selection.insert(component) }
    }
    try selectModeComponents(selection)
  }
  var canEditModeComponents: Bool {
    guard canSelectComponentTarget, historyOperation == nil, !editingMask, editingChannel == nil,
      let layer = activeLayer, !document.isImageLocked(layer.id), layer.smartObject == nil,
      layer.smartFilters == nil, case .raster = layer.content else { return false }
    return true
  }
  func selectModeComponents(_ components: Set<Int>) throws {
    finishNumericField(); finishLayerName()
    let legacyRGB8 = document.colorMode == .rgb && document.depth == .u8 && !document.hasNativeModeStorage && !document.isChannelOnly
    guard usesModeChannels || legacyRGB8, canSelectComponentTarget, historyOperation == nil,
      components.isSubset(of: Set(0..<document.colorMode.componentCount)) else {
      throw CraftError.invalid("Finish the current interaction and choose valid color components.")
    }
    if legacyRGB8 {
      if components.isEmpty || components.count == 3 {
        try selectEditingChannel(.composite); return
      }
      if components.count == 1, let index = components.first, let channel = RGBChannelPreview(rawValue: index + 1) {
        try selectEditingChannel(channel); return
      }
      selectColorChannelVisibility(); deselectQuickMaskTarget()
      alphaEditingID = nil; componentTarget = .composite
      maskEditingLayerID = nil; smartFilterMaskEditing = false; clearMaskView()
      modeComponentTargets = components; modeComponentVisibility = nil
      var view = channelView
      view.selectPreview(.composite)
      for channel in RGBChannelView.components where !components.contains(channel.rawValue - 1) { view.setVisible(channel, false) }
      channelView = view
      render()
      return
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
