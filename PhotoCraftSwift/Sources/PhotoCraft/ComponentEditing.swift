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
  var editingComponent: Bool { componentTarget != .composite }
  var canSelectComponentTarget: Bool {
    !geometryBusy && !aiBusy && !hasToneDraft && transformDraft == nil
      && !coalescingChanges && pathGesture == nil && geometrySheet == nil
      && !showAI && !showImagePlayground && !showFeatherSelection
      && patternNameDraft == nil && gradientNameDraft == nil
  }

  /// Editing selection is separate from the public view-only preview operation.
  /// It is document-local UI state, not a pixel edit or an undo history entry.
  func selectEditingChannel(_ channel: RGBChannelPreview) throws {
    finishNumericField()
    finishLayerName()
    guard canSelectComponentTarget else {
      throw CraftError.invalid("Finish the current interaction before selecting a channel.")
    }
    guard channel == .composite || document.depth == .u8 else {
      throw CraftError.unsupported("Component editing currently requires an RGB 8-bit document.")
    }
    let oldRevision = revision
    let changed = componentTarget != channel || editingMask || currentMaskView != nil
    componentTarget = channel
    maskEditingLayerID = nil
    clearMaskView()
    channelView.selectPreview(channel)
    if changed && revision == oldRevision { render() }
  }

  func componentFillCommand(value: Float, opacity: Float) throws -> Command {
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
    guard let target = componentTarget.editComponents else { return }
    switch command {
    case .fillComponents(let id, let fill):
      guard !editingMask, id == document.activeLayerID, fill.components == target else {
        throw CraftError.invalid("Component Fill must match the active layer and channel target.")
      }
    case .selection, .selectShape, .selectionCoverage, .invertSelection, .featherSelection,
      .renameLayer, .layerColor, .layerVisibility, .visibility, .lock, .opacity, .blend:
      break
    default:
      throw CraftError.unsupported(
        "\(command.label) is not available for individual channels yet. Select RGB to edit layer content."
      )
    }
  }

  func executeCompositePreparedEdit(_ prepared: PreparedEdit) throws {
    guard !editingComponent else {
      throw CraftError.unsupported("This operation requires the RGB editing target.")
    }
    try session.executePrepared(prepared)
  }

  var canUseComponentCanvasTool: Bool {
    !editingComponent
      || [.marquee, .ellipticalMarquee, .lasso, .polygonLasso, .hand, .zoom].contains(tool)
  }

  @discardableResult func handleComponentShortcut(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown,
      event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command],
      let number = Int(event.charactersIgnoringModifiers ?? ""), (2...5).contains(number),
      let channel = RGBChannelPreview(rawValue: number - 2)
    else { return false }
    do { try selectEditingChannel(channel) } catch { self.error = error.localizedDescription }
    return true
  }
}
