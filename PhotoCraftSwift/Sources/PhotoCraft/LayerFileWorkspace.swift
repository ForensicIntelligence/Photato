import AppKit
import Foundation
import Observation
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class LayerFileDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  var settings = LayerFileExportSettings()
  var destination: URL?
  var error: String?
  init(_ document: CraftDocument) { original = document; settings.prefix = ImageAssetExport.safeName(document.name); while settings.prefix.utf8.count > 64 { settings.prefix.removeLast() } }
}
struct LayerFileExportResult: Sendable {
  let files: [LayerFileRecord]
  let archive: Data?
  let published: [LayerFileIdentity]
}
extension EditorStore {
  var canExportLayerFiles: Bool { canExportImages && !document.layers.isEmpty }
  func beginLayerFiles() { guard canExportLayerFiles else { return }; layerFileDraft = .init(document) }
  func cancelLayerFiles() { layerFilesWorker?.cancel(); layerFileDraft = nil; status = "Layer export cancelled" }
  func exportedLayerFiles(_ settings:LayerFileExportSettings,directory:URL,publish:Bool,draft:LayerFileDraft? = nil) async throws -> LayerFileExportResult {
    guard layerFilesID == nil, !geometryBusy, !aiBusy, (draft == nil ? canExportLayerFiles : layerFileDraft === draft) else { throw CraftError.invalid("Finish the current edit or layer export first.") }
    try settings.validate(); let source = document, generation = layerPanelGeneration, id = UUID(), prepare = layerFilePreparation
    layerFilesID = id; geometryBusy = true; layerFilesProgress = .init()
    let progress: @Sendable (LayerFileProgress) -> Void = { [weak self] value in Task { @MainActor in if let self, self.layerFilesID == id { self.layerFilesProgress = value } } }
    let worker = Task.detached(priority:.userInitiated) { [self] in
      let prepared = try prepare(source,settings,directory,progress); defer { prepared.discard() }
      var published: [LayerFileIdentity] = []
      do {
        try Task.checkCancellation()
        try await MainActor.run { try self.validateLayerFileExport(source:source,generation:generation,id:id,draft:draft) }
        let archive: Data?
        if publish { published = try prepared.publish(to:directory); archive = nil } else { archive = try prepared.archive() }
        try Task.checkCancellation()
        try await MainActor.run { try self.validateLayerFileExport(source:source,generation:generation,id:id,draft:draft) }
        return LayerFileExportResult(files:prepared.files,archive:archive,published:published)
      } catch { PreparedLayerFiles.rollback(published); throw error }
    }
    layerFilesWorker = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }; geometryTask = observer
    defer { if layerFilesID == id { layerFilesID = nil; layerFilesWorker = nil; if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil } } }
    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    do {
      try Task.checkCancellation(); try validateLayerFileExport(source:source,generation:generation,id:id,draft:draft)
      guard !worker.isCancelled, !observer.isCancelled else { throw CancellationError() }
      return result
    } catch { PreparedLayerFiles.rollback(result.published); throw error }
  }
  private func validateLayerFileExport(source:CraftDocument,generation:UUID,id:UUID,draft:LayerFileDraft?) throws {
    guard document == source, layerPanelGeneration == generation, layerFilesID == id, draft == nil || layerFileDraft === draft else { throw CraftError.invalid("Layer export was cancelled or its source changed.") }
  }
  func runLayerFiles(_ draft:LayerFileDraft) {
    guard layerFileDraft === draft, let directory = draft.destination else { draft.error = "Choose a destination folder."; return }
    let settings = draft.settings
    Task { @MainActor [weak self,weak draft] in
      guard let self, let draft else { return }
      let scoped = directory.startAccessingSecurityScopedResource(); defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
      do {
        guard document == draft.original else { throw CraftError.invalid("The document changed; reopen Layers to Files.") }
        let result = try await exportedLayerFiles(settings,directory:directory,publish:true,draft:draft)
        if layerFileDraft === draft { layerFileDraft = nil; status = "Exported \(result.files.count) layer files" }
      } catch { if layerFileDraft === draft { draft.error = error.localizedDescription } }
    }
  }
}
struct LayerFileSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: LayerFileDraft
  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Layers to Files").font(.title2.bold())
      HStack { TextField("Destination",text:.constant(draft.destination?.path ?? "Choose a folder")).disabled(true); Button("Browse…") { chooseDestination() } }.disabled(store.layerFilesID != nil)
      Form {
        TextField("File Name Prefix",text:$draft.settings.prefix)
        Toggle("Visible Layers Only",isOn:$draft.settings.visibleOnly)
        Picker("File Type",selection:$draft.settings.format) { ForEach(LayerFileExportSettings.Format.allCases,id:\.self) { Text($0.title).tag($0) } }
        Toggle("Include ICC Profile",isOn:$draft.settings.includeICC).disabled(!draft.settings.format.supportsICC || draft.settings.format == .photato)
        Toggle("Trim Layers",isOn:$draft.settings.trim)
        if [.png8,.png24,.tga].contains(draft.settings.format) { Toggle("Transparency",isOn:$draft.settings.transparency) }
        if draft.settings.format == .jpeg {
          HStack { Text("Quality"); Slider(value:Binding(get:{Double(draft.settings.jpegQuality)},set:{draft.settings.jpegQuality=Int($0)}),in:0...12,step:1); Text("\(draft.settings.jpegQuality)").monospacedDigit().frame(width:24) }
        }
        if draft.settings.format == .tiff { Picker("Compression",selection:$draft.settings.tiffCompression) { ForEach(RasterEncodingOptions.TIFFCompression.allCases,id:\.self) { Text($0.rawValue.uppercased()).tag($0) } } }
        if [.png8,.png24].contains(draft.settings.format) { Toggle("Interlaced",isOn:$draft.settings.pngInterlaced) }
        if draft.settings.format == .png8 {
          Stepper("Colors: \(draft.settings.paletteColors)",value:$draft.settings.paletteColors,in:2...256)
          Picker("Dither",selection:$draft.settings.paletteDither) { ForEach(IndexedDither.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }
          HStack { Text("Dither Amount"); Slider(value:Binding(get:{Double(draft.settings.paletteAmount)},set:{draft.settings.paletteAmount=Float($0)}),in:0...1) }
        }
        if draft.settings.format == .pdf { Text("One rasterized PDF per layer, at the document's physical size.").font(.caption).foregroundStyle(.secondary) }
      }.formStyle(.grouped).disabled(store.layerFilesID != nil)
      if store.layerFilesID != nil { ProgressView(value:Double(store.layerFilesProgress.completed),total:Double(max(1,store.layerFilesProgress.total))); Text("\(store.layerFilesProgress.completed) / \(store.layerFilesProgress.total) · \(store.layerFilesProgress.current)").font(.caption).lineLimit(1) }
      if let error = draft.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
      HStack { Spacer(); Button("Cancel") { store.cancelLayerFiles() }.keyboardShortcut(.cancelAction); Button("Run") { store.runLayerFiles(draft) }.keyboardShortcut(.defaultAction).disabled(draft.destination == nil || store.layerFilesID != nil || (try? draft.settings.validate()) == nil) }
    }.padding(22).frame(width:570).onChange(of:draft.settings.format) { _,format in if !format.supportsICC { draft.settings.includeICC=false } else if format == .photato { draft.settings.includeICC=true } }
  }
  private func chooseDestination() {
    let panel = NSOpenPanel(); panel.title = "Layer Export Destination"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
    panel.begin { response in if response == .OK { draft.destination = panel.url } }
  }
}
@MainActor extension AppDelegate { @objc func exportLayersToFiles() { store?.beginLayerFiles() } }
