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
        Button("Wires and cables") {}.disabled(true)
        Button("People") { store.findRemovePeople() }.disabled(!store.canFindRemovePeople)
        Button("General distractions") {}.disabled(true)
      }.disabled(!store.canFindRemovePeople).help("Detect background people for review before removal. Wires and general distractions are not available yet.")
      Text("Mode")
      RemoveModeControl(selection:setting(\.mode),enabled:store.removeDraft == nil && !store.geometryBusy)
        .frame(width:205)
      Text("Traditional processing").foregroundStyle(.secondary)
        .help("Auto currently uses the native traditional engine. People detection runs on device; review its marks before applying traditional removal. Generative, wire and general-distraction removal are not available yet.")
      Toggle("Sample All Layers",isOn:setting(\.sampleAllLayers))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Toggle("Remove after each stroke",isOn:setting(\.removeAfterEachStroke))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Toggle("Create New Layer",isOn:setting(\.createNewLayer))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Button { store.cancelRemove() } label: { Label("Clear removal marks",systemImage:"xmark") }
        .labelStyle(.iconOnly).help("Clear removal marks (Escape)")
        .disabled(store.removeDraft == nil && store.removeApplying == nil)
      Button { store.applyRemove() } label: { Label("Apply removal",systemImage:"checkmark") }
        .labelStyle(.iconOnly).help("Apply removal (Return)")
        .disabled(store.geometryBusy || store.removeDraft?.hasMarks != true || store.removeStroke != nil)
      if store.removeApplying != nil || store.removeDetectionID != nil {
        ProgressView().controlSize(.small).accessibilityLabel(store.removeDetectionID != nil ? "Detecting people for removal" : "Removing marked areas")
      }
    }.controlSize(.small).toggleStyle(.checkbox)
  }
}
