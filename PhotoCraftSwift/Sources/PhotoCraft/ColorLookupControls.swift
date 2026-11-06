import AppKit
import PhotoCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct ColorLookupDraft: Identifiable, Sendable {
  let id: UUID
  var adjustment = ColorLookupAdjustment()
  var preview = true
}
struct ColorLookupControls: View {
  @Binding var adjustment: ColorLookupAdjustment
  @State private var importing = false
  @State private var exporting = false
  @State private var exportFile: LUTDocument?
  @State private var exportName = "Color Lookup.cube"
  @State private var error: String?
  @State private var loading = false
  @State private var task: Task<Void,Never>?
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      Text("3D LUT File").font(.headline)
      Text(adjustment.lut?.title ?? "No LUT selected").lineLimit(3).textSelection(.enabled)
      HStack {
        Button("Load LUT…") { importing = true }
        Menu("Photato Looks") {
          ForEach(ColorLUTPreset.allCases,id: \.rawValue) { preset in
            Button(preset.title) { load { try preset.makeLUT() } }
          }
        }
      }
      if let lut = adjustment.lut {
        Text("\(lut.size) × \(lut.size) × \(lut.size)\(lut.curve == nil ? "" : " + 1D shaper")")
          .font(.caption).foregroundStyle(.secondary)
      }
      Picker("Interpolation",selection:$adjustment.interpolation) {
        Text("Trilinear").tag(ColorLUT.Interpolation.trilinear)
        Text("Tetrahedral").tag(ColorLUT.Interpolation.tetrahedral)
      }
      Toggle("Dither",isOn:$adjustment.dither)
      HStack {
        Button("Export LUT…") {
          guard let lut = adjustment.lut else { return }
          do { let encoded = try ColorLUTFile.export(lut); exportName = encoded.name; exportFile = .init(data:encoded.data); exporting = true }
          catch { self.error = error.localizedDescription }
        }.disabled(adjustment.lut == nil)
        Button("Reset") { adjustment = .init() }
      }
      if loading { ProgressView("Loading LUT…").controlSize(.small) }
    }
    .disabled(loading)
    .fileImporter(isPresented:$importing,allowedContentTypes:ColorLUTFile.extensions.map { UTType(filenameExtension:$0) ?? .data }) { result in
      do { let url = try result.get(); load { try LUTDocument.load(url) } }
      catch { self.error = error.localizedDescription }
    }
    .fileExporter(isPresented:$exporting,document:exportFile,contentType:UTType(filenameExtension:URL(fileURLWithPath:exportName).pathExtension) ?? .data,defaultFilename:exportName) { result in
      if case .failure(let failure) = result { error = failure.localizedDescription }
    }
    .alert("Color Lookup",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) {
      Button("OK") { error = nil }
    } message: { Text(error ?? "") }
    .onDisappear { task?.cancel(); task = nil }
  }
  private func load(_ operation: @escaping @Sendable () throws -> ColorLUT) {
    task?.cancel(); loading = true
    task = Task { @MainActor in
      let worker = Task.detached(priority:.userInitiated,operation:operation)
      do {
        let lut = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return }
        adjustment.lut = lut
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
      loading = false
    }
  }
}
struct LUTDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  var data: Data
  var filename: String?
  init(data: Data,filename:String?=nil) { self.data = data; self.filename=filename }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CraftError.invalid("Invalid LUT file.") }; self.data = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { outputWrapper() }
  func outputWrapper()->FileWrapper { let file=FileWrapper(regularFileWithContents:data);file.preferredFilename=filename;return file }
  static func load(_ url: URL) throws -> ColorLUT {
    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
    let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
    return try ColorLUTFile.read(file.read(upToCount:ColorLUT.maximumFileBytes+1) ?? Data(),name:url.lastPathComponent)
  }
}
struct ColorLookupEditor: View {
  @Bindable var store: EditorStore
  let layerID: UUID
  var pixelLayer = false
  private var value: ColorLookupAdjustment {
    if pixelLayer { return store.colorLookupDraft?.adjustment ?? .init() }
    if case .adjustment(.colorLookup(let value)) = store.document.layers.first(where:{ $0.id == layerID })?.content { return value }
    return .init()
  }
  var body: some View {
    ColorLookupControls(adjustment:Binding(get:{ value },set:{ value in
      if pixelLayer { store.colorLookupDraft?.adjustment = value; store.render() }
      else { store.setColorLookup(layerID,value) }
    }))
  }
}
struct ColorLookupSheet: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment:.leading,spacing:18) {
      Text("Color Lookup").font(.title2.bold())
      if let draft = store.colorLookupDraft { ColorLookupEditor(store:store,layerID:draft.id,pixelLayer:true) }
      Divider()
      HStack {
        Toggle("Preview",isOn:Binding(get:{ store.colorLookupDraft?.preview ?? false },set:{ store.colorLookupDraft?.preview = $0; store.render() }))
        Spacer()
        Button("Cancel") { store.cancelColorLookup() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitColorLookup() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width:400)
  }
}
extension EditorStore {
  func beginColorLookup() {
    guard canBeginLevels, let id = activeLayer?.id else { return }
    colorLookupDraft = .init(id:id); render()
  }
  func cancelColorLookup() { colorLookupDraft = nil; render() }
  func commitColorLookup() {
    guard let draft = colorLookupDraft else { return }
    colorLookupDraft = nil; performGeometry(.applyAdjustment(draft.id,.colorLookup(draft.adjustment)))
  }
  func addColorLookup() {
    guard !geometryBusy, transformDraft == nil, !hasToneDraft else { return }
    do { perform(.addLayer(try ColorLookupAdjustment().layer(in:document))); propertiesTab = .properties }
    catch { self.error = error.localizedDescription }
  }
  func setColorLookup(_ id: UUID, _ value: ColorLookupAdjustment) {
    guard case .adjustment(.colorLookup) = document.layers.first(where:{ $0.id == id })?.content else { return }
    perform(.replaceContent(id,.adjustment(.colorLookup(value))))
  }
}
extension AppDelegate {
  @objc func colorLookup() { store?.beginColorLookup() }
  @objc func newColorLookup() { store?.addColorLookup() }
}
