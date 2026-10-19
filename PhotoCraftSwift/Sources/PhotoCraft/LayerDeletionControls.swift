import AppKit
import PhotoCraftCore

enum LayerDeletionChoice { case contents, groupOnly, cancel }

struct LayerDeletionRequest {
  let original: CraftDocument
  let selected: Set<UUID>
  var roots: [Layer] { (try? LayerDuplication.roots(in: original, selected: selected)) ?? [] }
  var group: Layer? { roots.count == 1 && roots[0].isGroup ? roots[0] : nil }
  var canDeleteContents: Bool { LayerDeletion.canDelete(in: original, selected: selected) }
  var canDeleteGroupOnly: Bool {
    guard let group else { return false }
    var candidate = original
    return (try? Command.ungroup(group.id).apply(to: &candidate)) != nil
      && !candidate.layers.isEmpty
  }
}

@MainActor enum LayerDeletionAlert {
  static func make(_ request: LayerDeletionRequest) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .warning
    if let group = request.group {
      alert.messageText = "Delete the group “\(group.name)”?"
      alert.informativeText =
        "Delete the group and its contents, or keep the layers and delete only the group."
      alert.addButton(withTitle: "Group and Contents").isEnabled = request.canDeleteContents
      let groupOnly = alert.addButton(withTitle: "Group Only")
      groupOnly.isEnabled = request.canDeleteGroupOnly
      if !request.canDeleteContents {
        alert.buttons[0].keyEquivalent = ""
        groupOnly.keyEquivalent = "\r"
      }
      alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
    } else {
      alert.messageText =
        request.roots.count == 1
        ? "Delete the layer “\(request.roots[0].name)”?" : "Delete the selected layers?"
      alert.addButton(withTitle: "Yes").isEnabled = request.canDeleteContents
      alert.addButton(withTitle: "No").keyEquivalent = "\u{1b}"
    }
    return alert
  }
  static func confirm(_ request: LayerDeletionRequest) -> LayerDeletionChoice {
    let response = make(request).runModal()
    if response == .alertFirstButtonReturn { return .contents }
    if response == .alertSecondButtonReturn, request.group != nil { return .groupOnly }
    return .cancel
  }
}

extension EditorStore {
  func canRequestLayerDeletion(context: UUID? = nil) -> Bool {
    guard canBeginLayerCreation else { return false }
    let request = LayerDeletionRequest(original: document, selected: layerPanelSelection(context))
    return request.canDeleteContents || request.canDeleteGroupOnly
  }
  func requestLayerDeletion(bypassingConfirmation: Bool = false) {
    finishLayerName()
    guard canRequestLayerDeletion() else { return }
    let request = LayerDeletionRequest(original: document, selected: groupSelectionIDs)
    let choice: LayerDeletionChoice
    if bypassingConfirmation {
      choice = .contents
    } else {
      confirmingLayerDeletion = true
      choice = (layerDeletionConfirmation ?? LayerDeletionAlert.confirm)(request)
      confirmingLayerDeletion = false
    }
    guard choice != .cancel else { return }
    guard canBeginLayerCreation, document == request.original, groupSelectionIDs == request.selected
    else {
      error = "The document or layer selection changed. Select the layers and try deleting again."
      return
    }
    switch choice {
    case .contents:
      if request.canDeleteContents { perform(.deleteLayers(request.selected)) }
    case .groupOnly:
      if request.canDeleteGroupOnly, let group = request.group { perform(.ungroup(group.id)) }
    case .cancel: break
    }
  }
  func deleteLayersFromFooter(modifiers: NSEvent.ModifierFlags) {
    requestLayerDeletion(bypassingConfirmation: modifiers.contains(.option))
  }
}

extension AppDelegate {
  /// Render the native alert content without presenting a modal or simulating user input.
  func layerDeletionSnapshot() {
    do {
      var model = try CraftDocument(width: 3, height: 2)
      model.layers[0].name = "Mountain study"
      if !CommandLine.arguments.contains("--snapshot-delete-only-group") {
        try Command.addLayer(Layer(name: "Color Grade", content: .fill(.white))).apply(to: &model)
      }
      if CommandLine.arguments.contains("--snapshot-delete-group") {
        try Command.newGroup(.init(name: "Artwork"), children: [model.activeLayerID!]).apply(
          to: &model)
      }
      let multiple = CommandLine.arguments.contains("--snapshot-delete-multiple")
      if multiple {
        try Command.addLayer(Layer(name: "Highlights", content: .fill(.white))).apply(to: &model)
      }
      let selected = multiple ? Set(model.layers.suffix(2).map(\.id)) : Set([model.activeLayerID!])
      let alert = LayerDeletionAlert.make(.init(original: model, selected: selected))
      alert.window.appearance = NSAppearance(named: .darkAqua)
      alert.layout()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [alert] in
        do {
          guard let view = alert.window.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
          else { throw CraftError.invalid("Delete alert snapshot allocation failed.") }
          view.layoutSubtreeIfNeeded()
          view.cacheDisplay(in: view.bounds, to: rep)
          guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CraftError.invalid("Delete alert snapshot encoding failed.")
          }
          let path = CommandLine.arguments.last ?? "/private/tmp/photato-delete.png"
          try data.write(to: URL(fileURLWithPath: path))
          print("Offscreen Delete alert content: \(path)")
        } catch { print("Delete snapshot failed: \(error)") }
        NSApp.terminate(nil)
      }
    } catch {
      print("Delete snapshot setup failed: \(error)")
      NSApp.terminate(nil)
    }
  }
}
