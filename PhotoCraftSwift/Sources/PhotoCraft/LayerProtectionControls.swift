import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class LayerProtectionDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let generation: UUID
  let selected: Set<UUID>
  var values: [UUID: LayerProtection]
  var error: String?
  init(store: EditorStore) {
    original = store.document
    generation = store.layerPanelGeneration
    selected = store.groupSelectionIDs
    values = Dictionary(uniqueKeysWithValues: store.document.layers.filter { store.groupSelectionIDs.contains($0.id) }
      .map { ($0.id, $0.protection) })
  }
  func state(_ flag: LayerProtection) -> NSControl.StateValue {
    let count = values.values.filter { flag == .transparency ? $0.locksTransparency : ($0.contains(flag) || $0.fullyLocks) }.count
    return count == 0 ? .off : count == values.count ? .on : .mixed
  }
  func set(_ flag: LayerProtection, enabled: Bool) {
    do { values = try values.mapValues { try $0.setting(flag, enabled: enabled) } }
    catch { self.error = error.localizedDescription }
  }
}

extension EditorStore {
  var canChangeLayerProtection: Bool {
    canBeginLayerCreation && !groupSelectionIDs.isEmpty
      && groupSelectionIDs.isSubset(of: Set(document.layers.map(\.id)))
  }
  func beginLayerProtection() {
    finishLayerName()
    guard canChangeLayerProtection else { return }
    layerProtectionDraft = LayerProtectionDraft(store: self)
  }
  func toggleFullLayerProtection() {
    guard canChangeLayerProtection else { return }
    let layers = document.layers.filter { groupSelectionIDs.contains($0.id) }
    if layers.count==1,layers[0].isBackground {convertBackgroundImmediately(layers[0].id);return}
    let value: LayerProtection = layers.allSatisfy { $0.protection.fullyLocks } ? [] : .fullyLocked
    perform(.protection(Dictionary(uniqueKeysWithValues: layers.map { ($0.id, value) })))
  }
  func toggleLayerProtection(_ flag: LayerProtection) {
    guard canChangeLayerProtection else { return }
    let layers = document.layers.filter { groupSelectionIDs.contains($0.id) }
    let enabled = !layers.allSatisfy { flag == .transparency
      ? $0.protection.locksTransparency : ($0.protection.contains(flag) || $0.protection.fullyLocks) }
    do {
      let values = try Dictionary(uniqueKeysWithValues: layers.map {
        ($0.id, try $0.protection.setting(flag, enabled: enabled))
      })
      perform(.protection(values))
    } catch { self.error = error.localizedDescription }
  }
  func commitLayerProtection(_ draft: LayerProtectionDraft) {
    guard layerProtectionDraft === draft else { return }
    guard document == draft.original, layerPanelGeneration == draft.generation,
      groupSelectionIDs == draft.selected, !geometryBusy, transformDraft == nil else {
      draft.error = "The document or selection changed. Cancel and reopen Lock Layers."
      return
    }
    layerProtectionDraft = nil
    perform(.protection(draft.values))
  }
}

struct LayerProtectionSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: LayerProtectionDraft
  private let choices: [(String, LayerProtection)] = [
    ("Transparency", .transparency), ("Image", .image), ("Position", .position),
    ("Prevent auto-nest", .autoNest), ("All", .all),
  ]
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Lock Layers").font(.headline)
      HStack(alignment: .top, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(choices, id: \.0) { title, flag in
            let enabled = flag == .all || (draft.state(.all) != .on
              && (flag != .transparency || draft.state(.image) != .on))
            ProtectionCheckbox(title: title, state: draft.state(flag),
              enabled: enabled) {
                draft.set(flag, enabled: $0)
              }.disabled(!enabled).frame(width: 155, height: 20)
          }
        }
        VStack(spacing: 10) {
          Button("OK") { store.commitLayerProtection(draft) }.keyboardShortcut(.defaultAction)
          Button("Cancel") { store.layerProtectionDraft = nil }.keyboardShortcut(.cancelAction)
        }.frame(width: 75)
      }
      if let error = draft.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
    }.padding(20).frame(width: 310)
  }
}

private struct ProtectionCheckbox: NSViewRepresentable {
  let title: String
  let state: NSControl.StateValue
  let enabled: Bool
  let changed: (Bool) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(changed) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(checkboxWithTitle: title, target: context.coordinator,
      action: #selector(Coordinator.change(_:)))
    button.allowsMixedState = true
    button.setAccessibilityIdentifier("layer.protection." + title)
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.changed = changed
    context.coordinator.previous = state
    button.title = title
    button.state = state
    button.isEnabled = enabled
  }
  @MainActor final class Coordinator: NSObject {
    var changed: (Bool) -> Void
    var previous: NSControl.StateValue = .off
    init(_ changed: @escaping (Bool) -> Void) { self.changed = changed }
    @objc func change(_ sender: NSButton) { changed(previous != .on) }
  }
}
