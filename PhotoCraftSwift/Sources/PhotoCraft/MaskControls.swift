import PhotoCraftCore
import SwiftUI

struct MaskControls: View {
  @Bindable var store: EditorStore
  let layer: Layer
  @State private var density = "100"
  @State private var feather = "0"
  @State private var trackingSlider = false

  private var editingFilterMask: Bool {
    store.smartFilterMaskEditing && store.maskEditingLayerID == layer.id
  }
  private var removalTarget: ManagedMaskTarget { editingFilterMask ? .smartFilterMask : .layerMask }
  private var featherRange: ClosedRange<Double> {
    editingFilterMask ? MaskProperties.filterFeatherRange : MaskProperties.layerFeatherRange
  }

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
      if editingFilterMask {
        Slider(value: Binding(
          get: { Double(layer.effectiveMaskProperties.density) * 100 },
          set: { value in store.updateMask(layer.id) { $0.density = Float(value / 100) } }
        ), in: 0...100, step: 1, onEditingChanged: trackSlider)
          .accessibilityLabel("Filter mask density")
          .accessibilityValue(density + " percent")
      }
      HStack {
        Text("Feather").frame(width: 52, alignment: .leading)
        TextField("Feather", text: $feather).onSubmit { commitFeather() }
          .accessibilityLabel("Mask feather pixels")
          .help("Feather from 0 to \(Int(featherRange.upperBound)) pixels")
        Text("px")
      }
      if editingFilterMask {
        Slider(value: Binding(
          get: { layer.effectiveMaskProperties.feather },
          set: { value in store.updateMask(layer.id) { $0.feather = value } }
        ), in: featherRange, step: 0.1, onEditingChanged: trackSlider)
          .accessibilityLabel("Filter mask feather")
          .accessibilityValue(feather + " pixels")
      } else {
        Button("Select and Mask…") { store.beginSelectMask(fromMask: true) }.disabled(!store.canBeginSelectMask)
      }
      HStack {
        Spacer()
        if !editingFilterMask {
          Button {
            store.applyMask(layer.id)
          } label: {
            Image(systemName: "checkmark.rectangle")
          }
          .help("Apply Layer Mask").accessibilityLabel("Apply Layer Mask")
          .disabled(!store.canApplyMask(layer))
        }
        Button {
          store.requestMaskRemoval(removalTarget, layerID: layer.id)
        } label: {
          Image(systemName: "trash")
        }
        .help("Delete \(removalTarget.title)")
        .accessibilityLabel("Delete \(removalTarget.title)")
        .disabled(!store.canRemoveMask(removalTarget, layerID: layer.id))
      }
    }.textFieldStyle(.roundedBorder).controlSize(.small)
      .disabled(
        store.document.isLocked(layer.id) || store.geometryBusy || store.transformDraft != nil
      )
      .onAppear { sync() }.onChange(of: layer.effectiveMaskProperties) { _, _ in sync() }
      .onChange(of: layer.id) { _, _ in trackSlider(false); sync() }
      .onChange(of: editingFilterMask) { _, _ in trackSlider(false); sync() }
      .onDisappear { trackSlider(false) }
  }

  private func trackSlider(_ active: Bool) {
    guard active != trackingSlider else { return }
    trackingSlider = active
    store.coalesce(active)
  }

  private func sync() {
    density = String(format: "%.1f", layer.effectiveMaskProperties.density * 100)
    let radius = layer.effectiveMaskProperties.feather
    feather = radius == (radius * 10).rounded() / 10 ? String(format: "%.1f", radius) : String(radius)
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
    if let value = Double(feather), featherRange.contains(value) {
      store.updateMask(layer.id) { $0.feather = value }
    } else {
      store.error = "Enter a Feather value between 0 and \(Int(featherRange.upperBound)) pixels."
      sync()
    }
  }
}
