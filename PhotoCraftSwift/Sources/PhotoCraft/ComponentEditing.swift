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
  var canSelectComponentTarget: Bool {canSelectComponentTarget(excludingChannelDialog:false)}
  func canSelectComponentTarget(excludingChannelDialog:Bool,excludingChannelVisibilitySweep:Bool=false)->Bool {
    !geometryBusy && !aiBusy && !(excludingChannelDialog ? hasToneDraftExceptChannelDialog:hasToneDraft) && transformDraft == nil
      && !coalescingChanges && pathGesture == nil && brushGesture == nil && historyOperation == nil && geometrySheet == nil
      && !showAI && !showImagePlayground && !showFeatherSelection
      && (excludingChannelVisibilitySweep || channelVisibilitySweep == nil)
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
    let changed = editingChannel != nil || componentTarget != channel || editingMask || currentMaskView != nil
      || !visibleAlphaIDs.isEmpty || !visibleTemporaryMaskChannels.isEmpty || !colorChannelsVisible
    selectColorChannelVisibility()
    deselectQuickMaskTarget()
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
      case .channel, .layerComp, .documentMetadata, .guides, .selection, .selectShape, .selectionCoverage, .invertSelection, .featherSelection,
        .renameLayer, .layerColor, .layerVisibility, .visibility, .lock, .opacity, .blend: break
      default: throw CraftError.unsupported("Select the composite color target for this operation.")
      }
      return
    }
    guard let target = componentTarget.editComponents else { return }
    switch command {
    case .modeComponents(let edit):
      guard !editingMask, editingChannel == nil, edit.layerID == document.activeLayerID,
        edit.components == effectiveComponentTargets else {
        throw CraftError.invalid("The edit must match the selected layer and color components.")
      }
    case .fillComponents(let id, let fill):
      guard !editingMask, id == document.activeLayerID, fill.components == target else {
        throw CraftError.invalid("Component Fill must match the active layer and channel target.")
      }
    case .channel, .layerComp, .documentMetadata, .guides, .selection, .selectShape, .selectionCoverage, .invertSelection, .featherSelection,
      .renameLayer, .layerColor, .layerVisibility, .visibility, .lock, .opacity, .blend:
      break
    default:
      throw CraftError.unsupported(
        "\(command.label) is not available for individual channels yet. Select RGB to edit layer content."
      )
    }
  }

  func executeCompositePreparedEdit(_ prepared: PreparedEdit, allowAuxiliary: Bool = false, allowModeComponents: Bool = false, allowChannelArithmetic: Bool = false, allowLinkedSmartObject: Bool = false) throws {
    try publishCompositePreparedEdit(prepared, allowAuxiliary: allowAuxiliary,
      allowModeComponents: allowModeComponents, allowChannelArithmetic: allowChannelArithmetic,
      allowLinkedSmartObject: allowLinkedSmartObject)
    if let filter = prepared.filterRecallValue { filterRecall.remember(filter) }
  }

  private func publishCompositePreparedEdit(_ prepared: PreparedEdit, allowAuxiliary: Bool, allowModeComponents: Bool, allowChannelArithmetic: Bool, allowLinkedSmartObject: Bool) throws {
    // Fit Image always resizes the document and every retained channel/mask.
    // Its typed prepared command cannot be repurposed as a selected-target edit.
    if prepared.isFitImageEdit { try session.executePrepared(prepared); return }
    if let command = prepared.channelCommand { try validateQuickMaskVisibility(.channel(command)) }
    if let request = prepared.pixelPaintRequest { try validateQuickMaskVisibility(.pixelPaint(request)) }
    if let request = prepared.paintingRequest { try validateQuickMaskPaintingTarget(request.target) }
    if prepared.isSelectionOnly || (allowAuxiliary && prepared.isChannelOnlyEdit) {try session.executePrepared(prepared);return}
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
    (editingChannel != nil && tool == .move && transformDraft?.channelTarget != nil) || (!effectiveComponentTargets.isEmpty && [.brush, .eraser].contains(tool)) || (editingChannel != nil && [.brush, .eraser, .pencil, .mixerBrush, .patternStamp, .marquee, .ellipticalMarquee, .rowMarquee, .columnMarquee, .lasso, .polygonLasso, .hand, .zoom].contains(tool)) || !editingComponent
      || [.marquee, .ellipticalMarquee, .rowMarquee, .columnMarquee, .lasso, .polygonLasso, .hand, .zoom].contains(tool)
  }

  @discardableResult func handleComponentShortcut(_ event: NSEvent) -> Bool {
    if handleMaskOverlayShortcut(event) {return true}
    if document.quickMask != nil, event.type == .keyDown,
      event.modifierFlags.intersection([.command,.control,.option,.shift]) == [.command],
      let number = Int(event.charactersIgnoringModifiers ?? ""), (2...9).contains(number) {
      let alphaStart = document.isChannelOnly || document.colorMode == .grayscale ? 3 : 3 + document.colorMode.componentCount
      if number == alphaStart + (document.alphaChannels?.count ?? 0) {
        do { try selectQuickMaskChannel() } catch { self.error = error.localizedDescription }
        return true
      }
    }
    if event.type == .keyDown,event.modifierFlags.intersection([.command,.control,.option,.shift]) == [.command,.option],
      let number=Int(event.charactersIgnoringModifiers ?? ""),canEditChannels {
      let start=3+document.colorMode.componentCount
      if document.colorMode.componentCount>0,number==2 {loadSelectionSource(.composite);return true}
      if number>=3,number<start {loadSelectionSource(.component(number-3));return true}
      if let channels=document.alphaChannels,channels.indices.contains(number-start),canEditChannels {
        perform(.channel(.load(.alpha(channels[number-start].id),.replace,false)));return true
      }
    }
    if document.isChannelOnly,event.type == .keyDown,
      event.modifierFlags.intersection([.command,.control,.option,.shift]) == [.command],
      let number=Int(event.charactersIgnoringModifiers ?? ""),let channels=document.alphaChannels,channels.indices.contains(number-3) {
      do{try selectAlphaChannel(channels[number-3].id)}catch{self.error=error.localizedDescription};return true
    }
    if document.isChannelOnly,event.modifierFlags.contains(.command),["2","3","4","5"].contains(event.charactersIgnoringModifiers ?? "") {return false}
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
