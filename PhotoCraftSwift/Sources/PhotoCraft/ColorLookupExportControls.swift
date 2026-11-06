import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class ColorLookupExportDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  var title = "Color Lookup"
  var size = 32
  var copyright = ""
  var baseName = "Color Lookup"
  var formats: [ColorLookupFileFormat] = [.cube]
  let created = Date()
  var files: [ColorLookupEncodedFile] = []
  var request: ColorLookupExportRequest { .init(size:size,title:title,copyright:copyright,formats:formats,baseName:baseName,created:created) }
  var valid: Bool { do { try request.validate(); return true } catch { return false } }
  var busy = false
  var data: Data?
  var error: String?
  @ObservationIgnored var task: Task<Void, Never>?
  init(_ original: CraftDocument) { self.original = original }
  func cancel() { task?.cancel() }
  deinit { task?.cancel() }
}

extension EditorStore {
  var canExportColorLookup: Bool {
    canExportImages && (try? ColorLookupExport.adjustments(in: document)) != nil
  }
  func beginColorLookupExport() {
    guard canExportColorLookup else { return }
    colorLookupExportDraft = .init(document)
  }
  func cancelColorLookupExport() {
    colorLookupExportDraft?.cancel(); colorLookupExportWorker?.cancel(); colorLookupFilesWorker?.cancel(); colorLookupExportDraft = nil
  }
  func encodedColorLookup(size: Int, title: String, draft: ColorLookupExportDraft? = nil) async throws -> Data {
    let preparation = colorLookupExportPreparation
    return try await prepareColorLookup(draft:draft,formats:[.cube],prepare:{ try preparation($0,size,title) },register:{ self.colorLookupExportWorker=$0 })
  }
  func encodedColorLookupFiles(_ request:ColorLookupExportRequest,draft:ColorLookupExportDraft?=nil) async throws -> [ColorLookupEncodedFile] {
    try request.validate();let preparation=colorLookupFilesPreparation
    return try await prepareColorLookup(draft:draft,formats:request.formats,prepare:{try preparation($0,request)},register:{self.colorLookupFilesWorker=$0})
  }
  func encodedColorLookupData(_ request:ColorLookupExportRequest,archive:Bool=false) async throws -> Data {
    try request.validate()
    if !archive,request.formats == [.cube],request.copyright.isEmpty {return try await encodedColorLookup(size:request.size,title:request.title)}
    let preparation=colorLookupFilesPreparation
    return try await prepareColorLookup(draft:nil,formats:request.formats,prepare:{ source in
      let files=try preparation(source,request)
      if archive {return try ColorLookupExport.archive(files)}
      guard files.count==1 else {throw CraftError.invalid("Choose one LUT format or the ZIP endpoint.")}
      return files[0].data
    },register:{self.colorLookupExportWorker=$0})
  }
  private func prepareColorLookup<Value:Sendable>(draft:ColorLookupExportDraft?,formats:[ColorLookupFileFormat],
    prepare:@escaping @Sendable (CraftDocument)throws->Value,register:(Task<Value,Error>?)->Void) async throws -> Value {
    guard colorLookupExportID == nil, !geometryBusy, !aiBusy,
      (draft != nil ? colorLookupExportDraft === draft : canExportColorLookup)
    else { throw CraftError.invalid("Finish the current edit or export first.") }
    let source = document, generation = layerPanelGeneration, id = UUID()
    if let draft, draft.original != source { throw CraftError.invalid("The document changed. Restart Color Lookup export.") }
    colorLookupExportID = id; colorLookupExportActiveFormats=formats; geometryBusy = true
    let worker = Task.detached(priority: .userInitiated) { try prepare(source) }
    register(worker)
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value }
      onCancel: { worker.cancel() } }; geometryTask = observer
    defer {
      if colorLookupExportID == id {
        colorLookupExportID = nil; register(nil); colorLookupExportActiveFormats=[]
        if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil }
      }
    }
    let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !worker.isCancelled, !observer.isCancelled, document == source,
      layerPanelGeneration == generation, draft == nil || colorLookupExportDraft === draft
    else { throw CancellationError() }
    return value
  }

}

struct ColorLookupExportSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: ColorLookupExportDraft
  @State private var choosingFile = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Export Color Lookup Tables").font(.title2.bold())
      TextField("Description", text: $draft.title).disabled(draft.busy)
      HStack {
        Text("Grid Points:")
        TextField("Grid Points", value: $draft.size, format: .number).frame(width: 70)
        Stepper("Grid Points", value: $draft.size, in: 2...ColorLUT.maximumSize).labelsHidden()
      }.disabled(draft.busy)
      TextField("Copyright (optional)",text:$draft.copyright).disabled(draft.busy)
      TextField("Base filename",text:$draft.baseName).disabled(draft.busy)
      HStack {ForEach(ColorLookupFileFormat.allCases,id: \.rawValue) { format in
        Toggle(format.title,isOn:Binding(get:{draft.formats.contains(format)},set:{ selected in
          draft.formats=ColorLookupFileFormat.allCases.filter{$0==format ? selected:draft.formats.contains($0)}
        })).toggleStyle(.checkbox)
      }}.disabled(draft.busy)
      Text(draft.copyright.isEmpty ? "Copyright is optional.":draft.request.copyrightLine).font(.caption).foregroundStyle(.secondary)
      Text("Export global color adjustments for reuse in other images and video editors.")
        .font(.callout).foregroundStyle(.secondary)
      if let error = draft.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      if draft.busy { ProgressView("Exporting color lookup table…") }
      HStack {
        Button("Cancel") { store.cancelColorLookupExport() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Export…") {
          draft.busy = true; draft.error = nil
          let request = draft.request
          draft.task = Task { @MainActor in
            do {
              let files = try await store.encodedColorLookupFiles(request, draft: draft)
              guard store.colorLookupExportDraft === draft, !Task.isCancelled else { return }
              draft.files = files; draft.data = files.first(where:{$0.format == .cube})?.data; draft.busy = false; choosingFile = true
            } catch {
              if !Task.isCancelled { draft.error = error.localizedDescription; draft.busy = false }
            }
          }
        }.keyboardShortcut(.defaultAction)
          .disabled(draft.busy || !draft.valid)
      }
    }.padding(24).frame(width: 510)
      .disabled(choosingFile)
      .fileExporter(isPresented: $choosingFile, documents: draft.files.map { LUTDocument(data:$0.data,filename:$0.name) },
        contentType: .data) { result in
        switch result {
        case .success: store.cancelColorLookupExport()
        case .failure(let error):
          if (error as NSError).code != NSUserCancelledError { draft.error = error.localizedDescription }
        }
      }
      .onDisappear { draft.cancel() }
  }
}

extension AppDelegate {
  @objc func exportColorLookupTables() { store?.beginColorLookupExport() }
}
