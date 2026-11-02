import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension RGBChannelPreview {
  var editComponents: RGBComponents? {
    switch self {
    case .composite: nil
    case .red: .red
    case .green: .green
    case .blue: .blue
    }
  }
}

extension EditorStore {
  var editingComponent: Bool { !isCompositeColorTarget || editingChannel != nil }
  var canSelectComponentTarget: Bool {
    !geometryBusy && !aiBusy && !hasToneDraft && transformDraft == nil
      && !coalescingChanges && pathGesture == nil && brushGesture == nil && historyOperation == nil && geometrySheet == nil
      && !showAI && !showImagePlayground && !showFeatherSelection
      && patternNameDraft == nil && gradientNameDraft == nil
  }

  /// Editing selection is separate from the public view-only preview operation.
  /// It is document-local UI state, not a pixel edit or an undo history entry.
  func selectEditingChannel(_ channel: RGBChannelPreview) throws {
    if document.inkMode != nil { guard channel == .composite else { throw CraftError.invalid("Choose an ink channel.") }; try selectInkChannels([]); return }
    if usesModeChannels {
      guard channel == .composite || document.colorMode == .rgb else { throw CraftError.invalid("Choose a component of the current color mode.") }
      try selectModeComponents(channel == .composite ? [] : [channel.rawValue - 1]); return
    }
    finishNumericField()
    finishLayerName()
    guard canSelectComponentTarget else {
      throw CraftError.invalid("Finish the current interaction before selecting a channel.")
    }
    guard channel == .composite || (document.depth == .u8 && document.colorMode == .rgb) else {
      throw CraftError.unsupported("Component editing currently requires an RGB 8-bit document.")
    }
    let oldRevision = revision
    let changed = alphaEditingID != nil || componentTarget != channel || editingMask || currentMaskView != nil
    alphaEditingID = nil
    modeComponentTargets = []; modeComponentVisibility = nil
    componentTarget = channel
    maskEditingLayerID = nil
    clearMaskView()
    channelView.selectPreview(channel)
    if changed && revision == oldRevision { render() }
  }

  func componentFillCommand(value: Float, opacity: Float) throws -> Command {
    if !modeComponentTargets.isEmpty, let layer = activeLayer, !editingMask { return .modeComponents(.init(layerID: layer.id, components: modeComponentTargets, operation: .fill(value, opacity))) }
    guard let components = componentTarget.editComponents, !editingMask,
      let layer = activeLayer
    else { throw CraftError.invalid("Select a Red, Green or Blue editing target first.") }
    let fill = RGBComponentFill(components: components, value: value, opacity: opacity)
    try fill.validate()
    return .fillComponents(layer.id, fill)
  }

  /// Fail before any document/history mutation if an operation has no component port.
  /// Explicit cases make new commands fail closed until their target behavior is reviewed.
  func validateComponentContext(_ command: Command) throws {
    if !modeComponentTargets.isEmpty {
      switch command {
      case .modeComponents(let edit):
        guard !editingMask, editingChannel == nil, edit.layerID == document.activeLayerID, edit.components == modeComponentTargets else { throw CraftError.invalid("The edit must match the selected layer and color components.") }
      case .layerComp, .documentMetadata, .guides, .selection, .selectShape, .selectionCoverage, .invertSelection, .featherSelection,
        .renameLayer, .layerColor, .layerVisibility, .visibility, .lock, .opacity, .blend: break
      default: throw CraftError.unsupported("Select the composite color target for this operation.")
      }
      return
    }
    guard let target = componentTarget.editComponents else { return }
    switch command {
    case .fillComponents(let id, let fill):
      guard !editingMask, id == document.activeLayerID, fill.components == target else {
        throw CraftError.invalid("Component Fill must match the active layer and channel target.")
      }
    case .layerComp, .documentMetadata, .guides, .selection, .selectShape, .selectionCoverage, .invertSelection, .featherSelection,
      .renameLayer, .layerColor, .layerVisibility, .visibility, .lock, .opacity, .blend:
      break
    default:
      throw CraftError.unsupported(
        "\(command.label) is not available for individual channels yet. Select RGB to edit layer content."
      )
    }
  }

  func executeCompositePreparedEdit(_ prepared: PreparedEdit, allowAuxiliary: Bool = false, allowModeComponents: Bool = false, allowChannelArithmetic: Bool = false, allowLinkedSmartObject: Bool = false) throws {
    if prepared.isSelectionOnly {try session.executePrepared(prepared);return}
    if allowLinkedSmartObject {
      guard let edit=prepared.linkedSmartObjectEdit,edit.source==document else {throw CraftError.invalid("Missing or stale linked artwork transaction.")}
      try session.executePrepared(prepared);return
    }
    if allowChannelArithmetic {
      guard let edit=prepared.channelArithmeticEdit,edit.source==document else {throw CraftError.invalid("Missing or stale channel transaction.")}
      try session.executePrepared(prepared);return
    }
    if allowModeComponents {
      guard let edit = prepared.modeComponentEdit else { throw CraftError.invalid("Missing color component edit.") }
      try validateComponentContext(.modeComponents(edit))
    }
    guard !editingComponent || (allowAuxiliary && isCompositeColorTarget) || (allowModeComponents && editingChannel == nil && !editingMask) else {
      throw CraftError.unsupported("This operation requires the RGB editing target.")
    }
    try session.executePrepared(prepared)
    if let id=prepared.adjustmentBrushTarget {acceptAdjustmentBrush(id)}
    if let result=prepared.paintingSession { acceptPainting(result) }
  }

  var canUseComponentCanvasTool: Bool {
    (editingChannel != nil && tool == .move && transformDraft?.channelTarget != nil) || (!modeComponentTargets.isEmpty && [.brush, .eraser].contains(tool)) || (editingChannel != nil && [.brush, .eraser, .pencil, .mixerBrush, .patternStamp, .marquee, .ellipticalMarquee, .lasso, .polygonLasso, .hand, .zoom].contains(tool)) || !editingComponent
      || [.marquee, .ellipticalMarquee, .lasso, .polygonLasso, .hand, .zoom].contains(tool)
  }

  @discardableResult func handleComponentShortcut(_ event: NSEvent) -> Bool {
    if usesModeChannels, event.type == .keyDown,
      event.modifierFlags.intersection([.command,.control,.option,.shift]) == [.command],
      let number = Int(event.charactersIgnoringModifiers ?? ""), (2...9).contains(number) {
      let gray = document.colorMode == .grayscale
      let alphaStart = gray ? 3 : 3 + document.colorMode.componentCount
      do {
        if number < alphaStart { try selectModeComponents(number == 2 ? (gray ? [0] : []) : [number - 3]) }
        else if let channels = document.alphaChannels, channels.indices.contains(number - alphaStart) { try selectAlphaChannel(channels[number - alphaStart].id) }
        else { return false }
      } catch { self.error = error.localizedDescription }
      return true
    }
    if event.type == .keyDown, event.modifierFlags.intersection([.command,.control,.option]) == [], event.charactersIgnoringModifiers?.lowercased() == "q" { toggleQuickMask(); return true }
    if event.type == .keyDown, event.modifierFlags.intersection([.command,.control,.option,.shift]) == [.command], let n = Int(event.charactersIgnoringModifiers ?? ""), (6...9).contains(n), let channels = document.alphaChannels, channels.indices.contains(n-6) {
      do { try selectAlphaChannel(channels[n-6].id) } catch { self.error = error.localizedDescription }; return true
    }
    guard event.type == .keyDown,
      event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command],
      let number = Int(event.charactersIgnoringModifiers ?? ""), (2...5).contains(number),
      let channel = RGBChannelPreview(rawValue: number - 2)
    else { return false }
    do { try selectEditingChannel(channel) } catch { self.error = error.localizedDescription }
    return true
  }
}
