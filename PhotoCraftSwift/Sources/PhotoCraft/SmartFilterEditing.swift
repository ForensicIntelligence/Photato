import AppKit
import PhotoCraftCore
import SwiftUI

extension EditorStore {
  var canEditSmartFilters: Bool { canEditSmartObject && !hasToneDraft }
  func editSmartFilters(_ id: UUID, _ edit: (inout SmartFilterStack) -> Void) {
    guard let layer = document.layers.first(where: { $0.id == id }), !geometryBusy, !hasToneDraft else { return }
    var stack = layer.smartFilters ?? SmartFilterStack(); edit(&stack)
    performGeometry(.smartFilters(id, stack.filters.isEmpty ? nil : stack))
  }
  func selectSmartFilterMask(_ id: UUID) {
    guard canBeginLayerCreation, document.layers.first(where: { $0.id == id })?.smartFilters?.mask != nil else { return }
    select(id)
    smartFilterMaskEditing = true; maskEditingLayerID = id; componentTarget = .composite; modeComponentTargets = []; modeComponentVisibility = nil
    deselectQuickMaskTarget()
    render()
  }
  func routedMaskCommand(_ command: Command) -> Command {
    guard smartFilterMaskEditing, let id = maskEditingLayerID else { return command }
    switch command {
    case .maskStroke(let target, _, _), .maskFill(let target, _), .invertMask(let target),
      .maskProperties(let target, _), .deleteMask(let target):
      return target == id ? .smartFilterMask(id, command) : command
    case .paintBucket(let target, let fill) where fill.mask:
      return .smartFilterMask(target, command)
    case .paintGradient(let target, let stroke) where stroke.mask:
      return .smartFilterMask(target, command)
    case .cloneStamp(let target, let stroke) where stroke.mask:
      return .smartFilterMask(target, command)
    case .healingBrush(let target, let stroke) where stroke.stroke.mask:
      return .smartFilterMask(target, command)
    case .spotHealing(let target, let stroke) where stroke.mask:
      return .smartFilterMask(target, command)
    case .focus(let target, let stroke) where stroke.mask:
      return .smartFilterMask(target, command)
    case .toning(let target, let stroke) where stroke.mask:
      return .smartFilterMask(target, command)
    default: return command
    }
  }
  func beginSmartFilter(_ layerID: UUID, filterID: UUID) {
    select(layerID)
    guard let item = activeLayer?.smartFilters?.filters.first(where: { $0.id == filterID }),canBeginFilterKind(item.filter.kind) else { return }
    filterDraft = FilterDraft(id: layerID, filter: item.filter, filterID: item.id,
      opacity: item.opacity, blendMode: item.blendMode)
    if item.filter.kind == .lightingEffects || item.filter.kind == .relight{filterDraft?.preview=false}
    render()
  }
  func createSmartFilterMask(_ id: UUID, selection: Bool) {
    performGeometry(label: "Add Filter Mask") { doc in
      guard let layer = doc.layers.first(where: { $0.id == id }), var stack = layer.smartFilters else {
        throw CraftError.invalid("Select a Smart Filter stack.")
      }
      try stack.createMask(in: doc, selection: selection)
      return .smartFilters(id, stack)
    }
  }
}

struct SmartFilterRows: View {
  @Bindable var store: EditorStore
  let layer: Layer
  let stack: SmartFilterStack
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 7) {
        Button { store.editSmartFilters(layer.id) { $0.enabled.toggle() } } label: {
          Image(systemName: stack.enabled ? "eye" : "eye.slash")
        }.accessibilityLabel("Toggle Smart Filters for \(layer.name)")
        if stack.mask != nil {
          Button { store.selectSmartFilterMask(layer.id) } label: {
            Image(systemName: "rectangle.lefthalf.filled")
              .padding(3).border(store.smartFilterMaskEditing && store.document.activeLayerID == layer.id ? Color.white : .clear)
          }.accessibilityLabel("Edit Smart Filter mask of \(layer.name)")
            .help("Paint black to hide the filters; white to reveal them")
        }
        Text("Smart Filters").fontWeight(.medium)
        Spacer()
      }.modifier(SmartFilterDropTarget(store: store, layerID: layer.id)).contextMenu {
        Button(stack.enabled ? "Disable Smart Filters" : "Enable Smart Filters") { store.editSmartFilters(layer.id) { $0.enabled.toggle() } }
        Button("View Filter Mask") {
          store.selectSmartFilterMask(layer.id)
          store.layerMaskView = LayerMaskView(layerID: layer.id, generation: store.layerPanelGeneration, mode: .gray, smartFilter: true)
          store.render()
        }.disabled(stack.mask == nil)
        Button("Add Filter Mask") { store.createSmartFilterMask(layer.id, selection: false) }
        Button("Filter Mask from Selection") { store.createSmartFilterMask(layer.id, selection: true) }.disabled(store.document.selection == nil)
        Button(stack.maskProperties.enabled ? "Disable Filter Mask" : "Enable Filter Mask") {
          store.editSmartFilters(layer.id) { $0.maskProperties.enabled.toggle() }
        }.disabled(stack.mask == nil)
        Button("Delete Filter Mask") { store.editSmartFilters(layer.id) { $0.mask = nil } }.disabled(stack.mask == nil)
        Button("Clear Smart Filters") { store.performGeometry(.smartFilters(layer.id, nil)) }
      }
      ForEach(Array(stack.filters.reversed())) { item in
        HStack(spacing: 7) {
          Button { store.editSmartFilters(layer.id) { s in
            if let i = s.filters.firstIndex(where: { $0.id == item.id }) { s.filters[i].enabled.toggle() }
          }} label: { Image(systemName: item.enabled ? "eye" : "eye.slash") }
            .accessibilityLabel("Toggle \(item.filter.kind.title)")
          Button(item.filter.kind.title) { store.beginSmartFilter(layer.id, filterID: item.id) }
            .help("Edit filter settings and blending")
          if let source=item.filter.distortion?.source,source.map==nil {
            Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
              .help("Original displacement map was not stored. Open Displace and choose a map to edit this filter.")
              .accessibilityLabel("Displacement map required")
          }
          Spacer()
          Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
        }.padding(.leading, 18)
          .contentShape(Rectangle())
          .onDrag { SmartFilterDrag.provider(store: store, layerID: layer.id, filterID: item.id) }
          .modifier(SmartFilterDropTarget(store: store, layerID: layer.id, filterID: item.id))
          .help("Drag to reorder; Option-drag to copy within this document")
          .contextMenu {
          Button("Edit Filter…") { store.beginSmartFilter(layer.id, filterID: item.id) }
          Button("Move Up") { move(item.id, delta: 1) }.disabled(stack.filters.last?.id == item.id)
          Button("Move Down") { move(item.id, delta: -1) }.disabled(stack.filters.first?.id == item.id)
          Button("Delete Smart Filter") { store.editSmartFilters(layer.id) { $0.filters.removeAll { $0.id == item.id } } }
        }
      }
    }.font(.system(size: 11)).buttonStyle(.plain).padding(.leading, 35).padding(.trailing, 10).padding(.vertical, 4)
      .disabled(store.geometryBusy || store.hasToneDraft || store.document.isImageLocked(layer.id))
  }
  private func move(_ id: UUID, delta: Int) {
    store.editSmartFilters(layer.id) { s in
      if let i = s.filters.firstIndex(where: { $0.id == id }), s.filters.indices.contains(i + delta) {
        s.filters.swapAt(i, i + delta)
      }
    }
  }
}

@MainActor extension AppDelegate {
  @objc func smartFilterCommand(_ sender: NSMenuItem) {
    guard let store, let layer = store.activeLayer, let path = sender.identifier?.rawValue else { return }
    if path.hasSuffix("Clear Smart Filters") { store.performGeometry(.smartFilters(layer.id, nil)) }
    else { store.editSmartFilters(layer.id) {
      if path.hasSuffix("Delete Filter Mask") { $0.mask = nil }
      else if path.hasSuffix("Disable Filter Mask") { $0.maskProperties.enabled.toggle() }
      else { $0.enabled.toggle() }
    }}
  }
}
