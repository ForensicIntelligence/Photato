import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension EditorStore {
  var layoutSelection: Set<UUID> {
    selectedLayerIDs.isEmpty ? Set(document.activeLayerID.map { [$0] } ?? []) : selectedLayerIDs
  }
  func canLayout(_ operation: LayerLayoutOperation) -> Bool {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil, !editingMask,
      let roots = try? LayerLayout.roots(layoutSelection, in: document), !roots.isEmpty
    else { return false }
    let members = LayerLayout.members(of: Set(roots.map(\.id)), in: document)
    guard !members.contains(where: \.isCanvasFill),
      !LayerLayout.containsLockedLayerOrAncestor(members, in: document)
    else { return false }
    let bounded = roots.filter {
      if case .adjustment = $0.content { return false }
      return true
    }
    switch operation {
    case .align:
      return !bounded.isEmpty
        && (bounded.count >= 2 || document.selection != nil || layoutTarget == .canvas)
    case .distribute: return bounded.count >= 3
    }
  }
  func arrangeLayers(_ operation: LayerLayoutOperation) {
    guard canLayout(operation) else { return }
    let selected = layoutSelection
    let target = layoutTarget
    performGeometry(
      label: operation.label,
      prepare: {
        try Renderer.layoutCommand(in: $0, selected: selected, operation: operation, target: target)
      })
  }
  func selectAllLayers() {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil else { return }
    selectedLayerIDs = Set(document.layers.map(\.id))
    maskEditingLayerID = nil
    if case .vectorMask = pathTarget { selectPath(nil) }
    if case .shape = pathTarget { selectPath(nil) }
  }
}

extension LayerAlignment {
  var symbol: String {
    switch self {
    case .left: "align.horizontal.left"
    case .horizontalCenter: "align.horizontal.center"
    case .right: "align.horizontal.right"
    case .top: "align.vertical.top"
    case .verticalCenter: "align.vertical.center"
    case .bottom: "align.vertical.bottom"
    }
  }
}

struct LayerLayoutControls: View {
  @Bindable var store: EditorStore
  @State private var expanded = false
  private let alignment: [LayerAlignment] = [
    .left, .horizontalCenter, .right, .top, .verticalCenter, .bottom,
  ]
  var body: some View {
    HStack(spacing: 4) {
      alignmentButtons
      Button {
        expanded.toggle()
      } label: {
        Image(systemName: "ellipsis").frame(width: 22, height: 24)
      }
      .buttonStyle(.plain).help("Align and Distribute").accessibilityLabel(
        "Align and Distribute options"
      )
      .popover(isPresented: $expanded) {
        VStack(alignment: .leading, spacing: 10) {
          Text("Align").fontWeight(.medium)
          HStack(spacing: 6) { alignmentButtons }
          Divider()
          Text("Distribute").fontWeight(.medium)
          ForEach(LayerDistribution.allCases, id: \.self) { kind in
            Button(kind.rawValue) { store.arrangeLayers(.distribute(kind)) }
              .disabled(!store.canLayout(.distribute(kind)))
              .accessibilityLabel("Distribute \(kind.rawValue)")
          }
          Divider()
          Picker("Align To", selection: $store.layoutTarget) {
            ForEach(LayerLayoutTarget.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.accessibilityLabel("Align To")
        }.padding(14).frame(width: 245).controlSize(.small)
      }
    }
  }
  private var alignmentButtons: some View {
    ForEach(alignment, id: \.self) { edge in
      Button {
        store.arrangeLayers(.align(edge))
      } label: {
        Image(systemName: edge.symbol).frame(width: 22, height: 24)
      }.buttonStyle(.plain).disabled(!store.canLayout(.align(edge)))
        .help("Align \(edge.rawValue)").accessibilityLabel("Align \(edge.rawValue)")
    }
  }
}
