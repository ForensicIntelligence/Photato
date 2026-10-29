import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

enum FrameTarget: String, CaseIterable { case frame = "Frame", contents = "Contents", both = "Frame & Contents" }
@MainActor @Observable final class FrameDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let layerID: UUID
  var definition: FrameDefinition
  var error: String?
  init(document: CraftDocument, layer: Layer) { original = document; layerID = layer.id; definition = layer.frame! }
}
extension EditorStore {
  var selectedFrame: Layer? { document.activeLayerID.flatMap { document.frame(containing: $0) } }
  var canEditFrames: Bool { canBeginLayerCreation && isCompositeColorTarget && !editingMask }
  var canConvertFrame: Bool {
    guard canEditFrames, let layer = activeLayer, !document.isImageLocked(layer.id), !document.isPositionLocked(layer.id) else { return false }
    switch layer.content { case .shape, .text: return true; default: return false }
  }
  func frameFromLayers() {
    guard canEditFrames else { return }; let ids = Array(groupSelectionIDs)
    performGeometry(label: "Frame from Layers", prepare: { original in try FrameRenderer.fromLayers(ids, name: "Frame", in: original) }, onSuccess: { [weak self] in self?.selectActiveFrame() })
  }
  func convertToFrame() {
    guard canConvertFrame, let id = activeLayer?.id else { return }
    performGeometry(label: "Convert to Frame", prepare: { original in try FrameRenderer.conversion(id, in: original) }, onSuccess: { [weak self] in self?.selectActiveFrame() })
  }
  func selectActiveFrame() { selectedLayerIDs = Set(document.activeLayerID.map { [$0] } ?? []); maskEditingLayerID = nil; tool = .frame }
  func selectFrameTarget(_ frame: Layer, target: FrameTarget) {
    frameTarget = target
    select(target == .contents ? document.children(of: frame.id).last?.id ?? frame.id : frame.id)
  }
  func beginFrameProperties() { guard canEditFrames, let frame = selectedFrame else { return }; frameDraft = FrameDraft(document: document, layer: frame) }
  func commitFrame(_ draft: FrameDraft) {
    guard frameDraft === draft, document == draft.original else { draft.error = "The document changed. Reopen Frame Properties."; return }
    frameDraft = nil; error = nil; perform(.frame(.configure(draft.layerID, draft.definition)))
    if let error { draft.error = error; self.error = nil; frameDraft = draft }
  }
  func fitFrameContents(_ fit: FrameFit) { guard canEditFrames, let frame = selectedFrame else { return }; perform(.frame(.fit(frame.id, fit))) }
}
struct FrameSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: FrameDraft
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Frame Properties").font(.headline)
      Picker("Shape", selection: $draft.definition.shape) { ForEach(FrameDefinition.Shape.allCases, id: \.self) { shape in if shape != .custom || draft.definition.customPath != nil { Text(shape.rawValue.capitalized).tag(shape) } } }
        .onChange(of: draft.definition.shape) { _, value in if value != .custom { draft.definition.customPath = nil } }
      HStack { Text("Width"); TextField("Width", value: $draft.definition.width, format: .number); Text("Height"); TextField("Height", value: $draft.definition.height, format: .number) }
      if draft.definition.shape == .polygon { Stepper("Sides: \(draft.definition.sides)", value: $draft.definition.sides, in: 3...64) }
      HStack { Text("Stroke"); TextField("Pixels", value: $draft.definition.strokeWidth, format: .number); Picker("Align", selection: $draft.definition.strokeAlignment) { ForEach(FrameDefinition.Alignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } } }
      ColorPicker("Stroke Color", selection: Binding(get: { Color(red: Double(draft.definition.strokeColor.r), green: Double(draft.definition.strokeColor.g), blue: Double(draft.definition.strokeColor.b), opacity: Double(draft.definition.strokeColor.a)) }, set: { color in if let c = NSColor(color).usingColorSpace(.deviceRGB) { draft.definition.strokeColor = Pixel(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), Float(c.alphaComponent)) } }))
      if let error = draft.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack { Spacer(); Button("Cancel") { store.frameDraft = nil }.keyboardShortcut(.cancelAction); Button("OK") { store.commitFrame(draft) }.keyboardShortcut(.defaultAction) }
    }.padding(20).frame(width: 430)
  }
}
struct FrameToolOptions: View {
  @Bindable var store: EditorStore
  var body: some View {
    Picker("Shape", selection: $store.frameShape) { ForEach(FrameDefinition.Shape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.frame(width: 115)
    if store.frameShape == .polygon { Stepper("\(store.frameSides) sides", value: $store.frameSides, in: 3...64).frame(width: 105) }
    Picker("Target", selection: Binding(get: { store.frameTarget }, set: { value in if let frame = store.selectedFrame { store.selectFrameTarget(frame, target: value) } else { store.frameTarget = value } })) { ForEach(FrameTarget.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 150)
    Button("Properties…") { store.beginFrameProperties() }.disabled(!store.canEditFrames || store.selectedFrame == nil)
    Button("Place…") { store.placeEmbedded() }.disabled(!store.canEditFrames || store.selectedFrame == nil)
    Menu("Fit") { ForEach(FrameFit.allCases, id: \.self) { fit in Button(fit.rawValue.capitalized) { store.fitFrameContents(fit) } } }.disabled(!store.canEditFrames || store.selectedFrame == nil)
  }
}
@MainActor extension AppDelegate {
  @objc func frameFromLayers() { store?.frameFromLayers() }
  @objc func convertToFrame() { store?.convertToFrame() }
  func validateFrameMenu(_ item: NSMenuItem) -> Bool? {
    switch item.action {
    case #selector(frameFromLayers): return store?.canEditFrames == true && store?.groupSelectionIDs.isEmpty == false
    case #selector(convertToFrame): return store?.canConvertFrame == true
    default: return nil
    }
  }
}
