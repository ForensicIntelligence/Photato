import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class ArtboardDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let target: UUID?
  let converting: Bool
  let children: [UUID]
  var name: String
  var x: Int
  var y: Int
  var width: Int
  var height: Int
  var background: Pixel
  var preset = "Custom"
  var guides: [ArtboardGuide]
  var moveContents = true
  var error: String?
  static let presets: [(String, Int, Int)] = [("Custom", 0, 0), ("Web 1920", 1920, 1080), ("Web 1366", 1366, 768), ("Mobile 390", 390, 844), ("Tablet 1024", 1024, 1366), ("Square 1080", 1080, 1080)]
  init(document: CraftDocument, target: UUID? = nil, children: [UUID] = [], bounds: IntRect) {
    original = document; self.target = target; self.children = children
    let layer = target.flatMap { id in document.layers.first { $0.id == id } }
    converting = target != nil && layer?.artboard == nil
    name = layer?.name ?? "Artboard \(document.artboards.count + 1)"
    x = bounds.x; y = bounds.y; width = bounds.width; height = bounds.height
    background = layer?.artboard?.background ?? .white; guides = layer?.artboard?.guides ?? []
    if let value = layer?.artboard?.preset, !value.isEmpty { preset = value }
  }
  var command: Command {
    let bounds = IntRect(x: x, y: y, width: width, height: height)
    if let target {
      if converting { return .artboard(.convert(target, bounds: bounds, background: background)) }
      let board = Artboard(width: width, height: height, background: background, preset: preset == "Custom" ? "" : preset, guides: guides)
      return .artboard(.configure(target, name: name, bounds: bounds, appearance: board, moveContents: moveContents))
    }
    return .artboard(.create(name: name, bounds: bounds, background: background, children: children))
  }
}
extension EditorStore {
  var selectedArtboard: Layer? { document.activeLayerID.flatMap { document.artboard(containing: $0) } }
  var canEditArtboards: Bool { canBeginLayerCreation && isCompositeColorTarget && !editingMask }
  func beginArtboard(fromSelection: Bool = false, fromGroup: Bool = false, edit: Bool = false) {
    finishLayerName(); guard canEditArtboards else { return }
    var target: Layer?
    var children: [UUID] = []
    if edit { target = selectedArtboard; guard target != nil else { return } }
    else if fromGroup { target = activeLayer; guard target?.isGroup == true, target?.parentID == nil, target?.artboard == nil else { return } }
    else if fromSelection { children = Array(groupSelectionIDs) }
    let bounds: IntRect
    if let target, let rect = document.logicalArtboardBounds(target) { bounds = rect }
    else if !children.isEmpty || target != nil {
      let selected = target.map { [$0.id] } ?? children
      let rect = try? LayerLayout.union(selected.compactMap { id in try document.layers.first { $0.id == id }.flatMap { try Renderer.layoutBounds($0, in: document, stored: true) } })
      let r = rect ?? IntRect(x: 0, y: 0, width: document.width, height: document.height)
      bounds = .init(x: r.x + (document.artboardOrigin?.x ?? 0), y: r.y + (document.artboardOrigin?.y ?? 0), width: r.width, height: r.height)
    } else {
      let edge = document.artboards.compactMap { document.logicalArtboardBounds($0) }.map { $0.x + $0.width }.max()
      bounds = .init(x: edge.map { $0 + 100 } ?? 0, y: 0, width: min(document.width, 1920), height: min(document.height, 1080))
    }
    artboardDraft = ArtboardDraft(document: document, target: target?.id, children: children, bounds: bounds)
  }
  func commitArtboard(_ draft: ArtboardDraft) {
    guard artboardDraft === draft, document == draft.original else { draft.error = "The document changed. Reopen Artboard Properties."; return }
    artboardDraft = nil; error = nil; perform(draft.command)
    if let error { draft.error = error; self.error = nil; artboardDraft = draft }
    else { selectedLayerIDs = Set(document.activeLayerID.map { [$0] } ?? []); maskEditingLayerID = nil }
  }
  func duplicateArtboard() {
    guard canEditArtboards, let board = selectedArtboard, let bounds = document.logicalArtboardBounds(board) else { return }
    perform(.artboard(.duplicate(board.id, x: bounds.x + bounds.width + 100, y: bounds.y, name: board.name + " copy")))
  }
}
struct ArtboardSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: ArtboardDraft
  @State private var guideAxis = ArtboardGuide.Axis.vertical
  @State private var guidePosition = 0.0
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(draft.target == nil ? "New Artboard" : "Artboard Properties").font(.headline)
      TextField("Name", text: $draft.name)
      Picker("Size", selection: $draft.preset) {
        ForEach(ArtboardDraft.presets, id: \.0) { Text($0.0).tag($0.0) }
        if !ArtboardDraft.presets.contains(where: { $0.0 == draft.preset }) { Text(draft.preset).tag(draft.preset) }
      }
        .onChange(of: draft.preset) { _, value in if let preset = ArtboardDraft.presets.first(where: { $0.0 == value }), preset.1 > 0 { draft.width = preset.1; draft.height = preset.2 } }
      Grid(alignment: .trailing) {
        GridRow { Text("X:"); TextField("X", value: $draft.x, format: .number); Text("Y:"); TextField("Y", value: $draft.y, format: .number) }
        GridRow { Text("Width:"); TextField("Width", value: $draft.width, format: .number); Text("Height:"); TextField("Height", value: $draft.height, format: .number) }
      }
      Picker("Background", selection: Binding(get: { draft.background == .clear ? 0 : draft.background == .white ? 1 : draft.background == .black ? 2 : 3 }, set: { draft.background = $0 == 0 ? .clear : $0 == 1 ? .white : $0 == 2 ? .black : store.brush.color })) {
        Text("Transparent").tag(0); Text("White").tag(1); Text("Black").tag(2); Text("Foreground Color").tag(3)
      }
      if draft.target != nil && !draft.converting {
        Toggle("Move contents with artboard", isOn: $draft.moveContents)
        HStack { Picker("Guide", selection: $guideAxis) { Text("Vertical").tag(ArtboardGuide.Axis.vertical); Text("Horizontal").tag(ArtboardGuide.Axis.horizontal) }; TextField("Position", value: $guidePosition, format: .number); Button("Add") { draft.guides.append(.init(axis: guideAxis, position: guidePosition)) } }
        HStack { Text("\(draft.guides.count) artboard guides"); Spacer(); Button("Clear Guides") { draft.guides = [] } }
      }
      if let error = draft.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack { Spacer(); Button("Cancel") { store.artboardDraft = nil }.keyboardShortcut(.cancelAction); Button("OK") { store.commitArtboard(draft) }.keyboardShortcut(.defaultAction).disabled(draft.width < 1 || draft.height < 1) }
    }.padding(20).frame(width: 450)
  }
}
struct ArtboardToolOptions: View {
  @Bindable var store: EditorStore
  var body: some View {
    Button("New…") { store.beginArtboard() }.disabled(!store.canEditArtboards)
    Button("Properties…") { store.beginArtboard(edit: true) }.disabled(store.selectedArtboard == nil || !store.canEditArtboards)
    Button("Duplicate") { store.duplicateArtboard() }.disabled(store.selectedArtboard == nil || !store.canEditArtboards)
    Toggle("Names", isOn: $store.showArtboardNames).controlSize(.mini)
    Toggle("Guides", isOn: $store.showArtboardGuides).controlSize(.mini)
  }
}
@MainActor extension AppDelegate {
  @objc func newArtboard() { store?.beginArtboard() }
  @objc func artboardFromLayers() { store?.beginArtboard(fromSelection: true) }
  @objc func artboardFromGroup() { store?.beginArtboard(fromGroup: true) }
  @objc func clearArtboardGuides() { if let store, let board = store.selectedArtboard { store.perform(.artboard(.clearGuides(board.id))) } }
  @objc func toggleArtboardNames() { store?.showArtboardNames.toggle() }
  @objc func toggleArtboardGuides() { store?.showArtboardGuides.toggle() }
  @objc func fitArtboard() { if let store, let rect = store.selectedArtboard?.artboardBounds { store.fitArtboard(rect) } }
}
