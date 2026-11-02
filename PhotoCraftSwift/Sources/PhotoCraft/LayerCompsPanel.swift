import AppKit
import PhotoCraftCore
import SwiftUI

struct LayerCompsPanel: View {
  @Bindable var store: EditorStore
  @State private var selected = Set<UUID>()
  @State private var name = "Layer Comp 1"
  @State private var comment = ""
  @State private var options = LayerCompOptions()
  @State private var message: String?
  var comps: [LayerComp] { store.document.layerComps?.comps ?? [] }
  var chosen: LayerComp? { comps.first { selected.contains($0.id) } }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(store.document.name).font(.caption).foregroundStyle(.secondary)
      Button("Last Document State") { attempt { try store.editLayerComp(.restoreLast) } }
        .disabled(store.document.layerComps?.lastDocumentState == nil || !store.canEditLayerComps)
      List(selection: $selected) {
        ForEach(comps) { comp in
          HStack(alignment: .top) {
            Button { attempt { try store.editLayerComp(.apply(comp.id)) } } label: {
              Image(systemName: store.document.layerComps?.appliedID == comp.id && comp.matches(store.document) ? "checkmark.square.fill" : "square")
            }.buttonStyle(.plain).help("Apply \(comp.name)").disabled(!store.canEditLayerComps)
            VStack(alignment: .leading, spacing: 3) {
              Text(comp.name)
              if !comp.comment.isEmpty { Text(comp.comment).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
              if !comp.unavailableSmartObjectLayers(in: store.document).isEmpty { Label("Recorded Smart Object source changed", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
              if !comp.missingLayers(in: store.document).isEmpty { Label("Recorded layers are missing", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
          }.tag(comp.id)
        }
      }.frame(minHeight: 160)
      HStack {
        Button("Previous") { step(-1) }.disabled(comps.isEmpty || !store.canEditLayerComps)
        Button("Next") { step(1) }.disabled(comps.isEmpty || !store.canEditLayerComps)
        Spacer()
        Button("↑") { move(-1) }.help("Move selected comp up").disabled(selected.count != 1 || !store.canEditLayerComps)
        Button("↓") { move(1) }.help("Move selected comp down").disabled(selected.count != 1 || !store.canEditLayerComps)
      }
      TextField("Name", text: $name)
      TextField("Comment", text: $comment, axis: .vertical).lineLimit(2...4)
      HStack {
        Toggle("Visibility", isOn: $options.visibility)
        Toggle("Position", isOn: $options.position)
        Toggle("Appearance", isOn: $options.appearance)
      }.font(.caption)
      Toggle("Layer Comp Selection for Smart Objects", isOn: Binding(get: { options.recordsSmartObjects }, set: { options.smartObjects = $0 ? true : nil })).font(.caption)
      HStack {
        Button("New") { attempt { let id = UUID(); try store.editLayerComp(.capture(id: id, name: name, comment: comment, options: options)); selected = [id] } }
        Button("Update") { attempt { if let chosen { try store.editLayerComp(.update(chosen.id, name: name, comment: comment, options: options, recapture: true)) } } }.disabled(selected.count != 1)
        Button("Duplicate") { attempt { if let chosen { let id = UUID(); try store.editLayerComp(.duplicate(chosen.id, newID: id)); selected = [id] } } }.disabled(selected.count != 1)
        Button("Delete") { attempt { try store.editLayerComp(.delete(Array(selected))); selected = [] } }.disabled(selected.isEmpty)
      }.disabled(!store.canEditLayerComps)
      HStack {
        Menu("Export") {
          Button("Layer Comps to Files…") { store.presentLayerCompExport(pdf: false, selected: selected) }
          Button("Layer Comps to PDF…") { store.presentLayerCompExport(pdf: true, selected: selected) }
        }.disabled(comps.isEmpty || !store.canEditLayerComps)
        Spacer()
        if store.layerCompExportID != nil { ProgressView().controlSize(.small); Button("Cancel Export") { store.layerCompExportWorker?.cancel() } }
      }
      if let message { Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
    }.padding(12).frame(minWidth: 390, minHeight: 430)
      .onChange(of: selected) { _, _ in loadFields() }
      .onChange(of: store.document.layerComps) { _, _ in selected.formIntersection(Set(comps.map(\.id))) }
  }
  private func attempt(_ action: () throws -> Void) { do { try action(); message = nil } catch { message = error.localizedDescription } }
  private func loadFields() { if let chosen { name = chosen.name; comment = chosen.comment; options = chosen.options } }
  private func step(_ direction: Int) {
    guard !comps.isEmpty else { return }
    let current = store.document.layerComps?.appliedID.flatMap { id in comps.firstIndex { $0.id == id } }
    let i = current.map { ($0 + direction + comps.count) % comps.count } ?? (direction > 0 ? 0 : comps.count - 1)
    attempt { try store.editLayerComp(.apply(comps[i].id)); selected = [comps[i].id] }
  }
  private func move(_ delta: Int) {
    guard let id = chosen?.id, let i = comps.firstIndex(where: { $0.id == id }), comps.indices.contains(i + delta) else { return }
    var ids = comps.map(\.id); ids.swapAt(i, i + delta); attempt { try store.editLayerComp(.reorder(ids)) }
  }
}
struct LayerCompsPanelRoot: View {
  @Bindable var documents: DocumentWindows
  var body: some View {
    if let document = documents.activeDocument { LayerCompsPanel(store: document.store).id(ObjectIdentifier(document.store)) }
    else { Text("Open an image to create Layer Comps.").padding(30) }
  }
}
@MainActor extension AppDelegate {
  @objc func showLayerComps() {
    if layerCompsWindow == nil {
      let panel = FloatingPanelWindow(contentRect: .init(x: 170, y: 170, width: 430, height: 530), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
      panel.title = "Layer Comps"; panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
      panel.hidesOnDeactivate = true; panel.documents = controller.documentWindows
      panel.contentView = NSHostingView(rootView: LayerCompsPanelRoot(documents: controller.documentWindows))
      panel.appearance = NSAppearance(named: .darkAqua); panel.tabbingMode = .disallowed
      layerCompsWindow = NSWindowController(window: panel)
    }
    layerCompsWindow?.showWindow(nil)
  }
  @objc func exportLayerCompFiles() { store?.presentLayerCompExport(pdf: false) }
  @objc func exportLayerCompPDF() { store?.presentLayerCompExport(pdf: true) }
}
