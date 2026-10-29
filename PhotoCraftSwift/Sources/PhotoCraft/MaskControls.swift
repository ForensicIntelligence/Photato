import PhotoCraftCore
import SwiftUI

struct MaskControls: View {
  @Bindable var store: EditorStore
  let layer: Layer
  @State private var density = "100"
  @State private var feather = "0"
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Toggle(
          "Enabled",
          isOn: Binding(
            get: { layer.effectiveMaskProperties.enabled },
            set: { value in store.updateMask(layer.id) { $0.enabled = value } }))
        Toggle(
          "Linked",
          isOn: Binding(
            get: { layer.effectiveMaskProperties.linked },
            set: { value in store.updateMask(layer.id) { $0.linked = value } }))
      }.toggleStyle(.checkbox)
      HStack {
        Text("Density").frame(width: 52, alignment: .leading)
        TextField("Density", text: $density).onSubmit { commitDensity() }
          .accessibilityLabel("Mask density percent")
        Text("%")
      }
      HStack {
        Text("Feather").frame(width: 52, alignment: .leading)
        TextField("Feather", text: $feather).onSubmit { commitFeather() }
          .accessibilityLabel("Mask feather pixels")
        Text("px")
      }
      Button("Select and Mask…") { store.beginSelectMask(fromMask: true) }.disabled(!store.canBeginSelectMask)
      HStack {
        Spacer()
        Button {
          store.applyMask(layer.id)
        } label: {
          Image(systemName: "checkmark.rectangle")
        }
        .help("Apply Layer Mask").accessibilityLabel("Apply Layer Mask")
        .disabled(!store.canApplyMask(layer))
        Button {
          store.deleteMask(layer.id)
        } label: {
          Image(systemName: "trash")
        }
        .help("Delete Layer Mask").accessibilityLabel("Delete Layer Mask")
      }
    }.textFieldStyle(.roundedBorder).controlSize(.small)
      .disabled(
        store.document.isLocked(layer.id) || store.geometryBusy || store.transformDraft != nil
      )
      .onAppear { sync() }.onChange(of: layer.effectiveMaskProperties) { _, _ in sync() }
      .onChange(of: layer.id) { _, _ in sync() }
  }
  private func sync() {
    density = String(format: "%.1f", layer.effectiveMaskProperties.density * 100)
    feather = String(format: "%.1f", layer.effectiveMaskProperties.feather)
  }
  private func commitDensity() {
    if let value = Float(density), value.isFinite, (0...100).contains(value) {
      store.updateMask(layer.id) { $0.density = value / 100 }
    } else {
      store.error = "Mask density must be between 0 and 100 percent."
      sync()
    }
  }
  private func commitFeather() {
    if let value = Double(feather), value.isFinite, (0...100).contains(value) {
      store.updateMask(layer.id) { $0.feather = value }
    } else {
      store.error = "Mask feather currently supports 0–100 pixels."
      sync()
    }
  }
}
