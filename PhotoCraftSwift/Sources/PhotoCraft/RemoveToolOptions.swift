import SwiftUI
import PhotoCraftCore

struct RemoveToolOptions: View {
  @Bindable var store: EditorStore
  private func setting<T>(_ key: WritableKeyPath<RemoveToolSettings,T>) -> Binding<T> {
    Binding(get:{ store.removeSettings[keyPath:key] },set:{ value in
      var settings = store.removeSettings; settings[keyPath:key] = value
      do { try store.updateRemoveSettings(settings) } catch { store.status = error.localizedDescription }
    })
  }
  var body: some View {
    HStack(spacing:10) {
      Text("Size")
      TextField("Size",value:setting(\.size),format:.number)
        .frame(width:48).accessibilityLabel("Remove brush size")
        .disabled(store.geometryBusy || store.removeStroke != nil)
      Picker("Remove marking",selection:setting(\.subtract)) {
        Label("Add",systemImage:"plus").tag(false)
        Label("Subtract",systemImage:"minus").tag(true)
      }.pickerStyle(.segmented).frame(width:100).labelsHidden()
        .disabled(store.geometryBusy || store.removeStroke != nil)
      Menu("Find distractions") {
        Button("Wires and cables") { store.removeWiresAndCables() }.disabled(!store.canRemoveWires)
        Button("People") { store.findRemovePeople() }.disabled(!store.canFindRemovePeople)
        Button("General distractions") {}.disabled(true)
      }.disabled(!store.canFindRemovePeople && !store.canRemoveWires)
        .help("Remove extended wire and cable runs, or detect background people for review.")
      Text("Mode")
      RemoveModeControl(selection:setting(\.mode),enabled:store.removeDraft == nil && !store.geometryBusy)
        .frame(width:205)
      Text("Traditional processing").foregroundStyle(.secondary)
        .help("Auto uses traditional processing. People detection and wire removal run on this Mac.")
      Toggle("Sample All Layers",isOn:setting(\.sampleAllLayers))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Toggle("Remove after each stroke",isOn:setting(\.removeAfterEachStroke))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Toggle("Create New Layer",isOn:setting(\.createNewLayer))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      let clearTitle = store.removeWiresID == nil ? "Clear removal marks" : "Cancel wire removal"
      Button { store.cancelRemove() } label: { Label(clearTitle,systemImage:"xmark") }
        .labelStyle(.iconOnly).help("\(clearTitle) (Escape)")
        .disabled(store.removeDraft == nil && store.removeApplying == nil && store.removeWiresID == nil)
      Button { store.applyRemove() } label: { Label("Apply removal",systemImage:"checkmark") }
        .labelStyle(.iconOnly).help("Apply removal (Return)")
        .disabled(store.geometryBusy || store.removeDraft?.hasMarks != true || store.removeStroke != nil)
      if store.removeApplying != nil || store.removeDetectionID != nil || store.removeWiresID != nil {
        ProgressView().controlSize(.small).accessibilityLabel(progressTitle)
      }
    }.controlSize(.small).toggleStyle(.checkbox)
  }

  private var progressTitle: String {
    if store.removeWiresID != nil { return "Removing wires and cables" }
    return store.removeDetectionID != nil ? "Detecting people for removal" : "Removing marked areas"
  }
}
