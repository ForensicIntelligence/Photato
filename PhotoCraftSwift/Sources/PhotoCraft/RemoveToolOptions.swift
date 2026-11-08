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
      Text("Mode")
      RemoveModeControl(selection:setting(\.mode),enabled:store.removeDraft == nil && !store.geometryBusy)
        .frame(width:205)
      Text("Traditional processing").foregroundStyle(.secondary)
        .help("Auto currently uses the native traditional engine. Generative Remove and distraction detection are not available yet.")
      Toggle("Sample All Layers",isOn:setting(\.sampleAllLayers))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Toggle("Remove after each stroke",isOn:setting(\.removeAfterEachStroke))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Toggle("Create New Layer",isOn:setting(\.createNewLayer))
        .disabled(store.removeDraft != nil || store.geometryBusy)
      Button { store.cancelRemove() } label: { Label("Clear removal strokes",systemImage:"xmark") }
        .labelStyle(.iconOnly).help("Clear removal strokes (Escape)")
        .disabled(store.removeDraft == nil && store.removeApplying == nil)
      Button { store.applyRemove() } label: { Label("Apply removal",systemImage:"checkmark") }
        .labelStyle(.iconOnly).help("Apply removal (Return)")
        .disabled(store.geometryBusy || store.removeDraft?.strokes.isEmpty != false || store.removeStroke != nil)
      if store.removeApplying != nil {
        ProgressView().controlSize(.small).accessibilityLabel("Removing marked areas")
      }
    }.controlSize(.small).toggleStyle(.checkbox)
  }
}
