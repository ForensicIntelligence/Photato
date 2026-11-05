import AppKit
import PhotoCraftCore

enum ManagedMaskTarget: String, CaseIterable, Sendable {
  case layerMask, vectorMask, smartFilterMask
  var title: String {
    switch self {
    case .layerMask: "Layer Mask"
    case .vectorMask: "Vector Mask"
    case .smartFilterMask: "Filter Mask"
    }
  }
}

struct MaskManagementRequest: Sendable {
  enum Operation: String, Sendable { case apply, delete }
  let layerID: UUID
  let target: ManagedMaskTarget
  let operation: Operation

  func command(in document: CraftDocument) throws -> Command {
    guard let layer = document.layers.first(where: { $0.id == layerID }) else {
      throw CraftError.invalid("The mask layer is no longer available.")
    }
    guard !document.isLocked(layerID) else { throw CraftError.invalid("Unlock the layer before removing its mask.") }
    switch (target, operation) {
    case (.layerMask, .delete):
      guard layer.mask != nil else { throw CraftError.invalid("Layer mask not found.") }
      return .deleteMask(layerID)
    case (.layerMask, .apply):
      guard layer.smartObject == nil, layer.canApplyPixelMask, !document.isImageLocked(layerID) else {
        throw CraftError.unsupported("This layer's pixel mask cannot be applied. Delete it or keep it editable.")
      }
      return .applyMask(layerID)
    case (.vectorMask, .delete):
      guard layer.vectorMask != nil else { throw CraftError.invalid("Vector mask not found.") }
      return .vectorMask(layerID, nil)
    case (.smartFilterMask, .delete):
      guard !document.isImageLocked(layerID), var stack = layer.smartFilters, stack.mask != nil else {
        throw CraftError.invalid("An unlocked Smart Filter mask is required.")
      }
      stack.mask = nil
      return .smartFilters(layerID, stack)
    default:
      throw CraftError.unsupported("Only a supported pixel layer mask can be applied here.")
    }
  }
}

struct MaskRemovalPrompt {
  let target: ManagedMaskTarget
  let layerName: String
  let canApply: Bool
}
enum MaskRemovalChoice { case apply, delete, cancel }

@MainActor enum MaskRemovalAlert {
  static func make(_ prompt: MaskRemovalPrompt) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .warning
    if prompt.target == .layerMask {
      alert.messageText = "Apply mask to layer before removing?"
      alert.informativeText = "Apply changes the transparency of “\(prompt.layerName)”. Delete removes only the mask."
      alert.addButton(withTitle: "Apply").isEnabled = prompt.canApply
      let delete = alert.addButton(withTitle: "Delete")
      if !prompt.canApply { alert.buttons[0].keyEquivalent = ""; delete.keyEquivalent = "\r" }
    } else {
      alert.messageText = "Delete the \(prompt.target.title.lowercased())?"
      alert.informativeText = "The layer “\(prompt.layerName)” will be retained."
      alert.addButton(withTitle: "Delete")
    }
    alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
    return alert
  }
  static func confirm(_ prompt: MaskRemovalPrompt) -> MaskRemovalChoice {
    let response = make(prompt).runModal()
    if prompt.target == .layerMask {
      if response == .alertFirstButtonReturn, prompt.canApply { return .apply }
      if response == .alertSecondButtonReturn { return .delete }
    } else if response == .alertFirstButtonReturn { return .delete }
    return .cancel
  }
}

@MainActor extension EditorStore {
  /// Retain target intent even if a stale mask disappeared; never fall back to deleting its layer.
  var footerMaskTarget: ManagedMaskTarget? {
    guard let id = activeLayer?.id else { return nil }
    if maskEditingLayerID == id { return smartFilterMaskEditing ? .smartFilterMask : .layerMask }
    if pathTarget == .vectorMask(id) { return .vectorMask }
    return nil
  }
  func canRemoveMask(_ target: ManagedMaskTarget, layerID: UUID) -> Bool {
    canBeginLayerCreation && !editingComponent && !aiBusy
      && (try? MaskManagementRequest(layerID: layerID, target: target, operation: .delete).command(in: document)) != nil
  }
  var canDeleteFromLayerFooter: Bool {
    if let target = footerMaskTarget, let id = activeLayer?.id { return canRemoveMask(target, layerID: id) }
    return canRequestLayerDeletion()
  }
  var layerFooterDeletionHelp: String {
    if let target = footerMaskTarget { return "Delete \(target.title) (Option-click to skip confirmation)" }
    return "Delete selected layers (Option-click to skip confirmation)"
  }
  func requestMaskRemoval(_ target: ManagedMaskTarget, layerID: UUID, bypassingConfirmation: Bool = false) {
    finishLayerName()
    guard canRemoveMask(target, layerID: layerID), let layer = activeLayer, layer.id == layerID else { return }
    let original = document, selected = groupSelectionIDs, selectedTarget = footerMaskTarget
    let generation = layerPanelGeneration, sessionID = sessionGeneration, owner = documentController
    if let owner, !owner.documents.contains(where: { ($0 as? CraftNSDocument)?.store === self }) { return }
    let canApply = (try? MaskManagementRequest(layerID: layerID, target: target, operation: .apply).command(in: original)) != nil
    let choice: MaskRemovalChoice
    if bypassingConfirmation { choice = .delete }
    else {
      confirmingLayerDeletion = true
      choice = (maskRemovalConfirmation ?? MaskRemovalAlert.confirm)(.init(target: target, layerName: layer.name, canApply: canApply))
      confirmingLayerDeletion = false
    }
    guard choice != .cancel else { return }
    guard canRemoveMask(target, layerID: layerID), document == original,
      groupSelectionIDs == selected, footerMaskTarget == selectedTarget,
      layerPanelGeneration == generation, sessionGeneration == sessionID,
      documentController === owner,
      owner.map({ !$0.documentClosing.isActive && $0.documents.contains(where: { ($0 as? CraftNSDocument)?.store === self }) }) ?? true
    else { error = "The document or mask target changed. Select the mask and try again."; return }
    guard choice != .apply || canApply else { return }
    let request = MaskManagementRequest(layerID: layerID, target: target, operation: choice == .apply ? .apply : .delete)
    performGeometry(label: choice == .apply ? "Apply Layer Mask" : "Delete \(target.title)",
      prepare: { try request.command(in: $0) }, onSuccess: { [weak self] in self?.finishMaskRemoval(request) })
  }
  func finishMaskRemoval(_ request: MaskManagementRequest) {
    guard activeLayer?.id == request.layerID,
      footerMaskTarget == request.target || (request.target == .smartFilterMask && smartFilterMaskEditing)
    else { return }
    select(request.layerID)
    render()
  }
}
