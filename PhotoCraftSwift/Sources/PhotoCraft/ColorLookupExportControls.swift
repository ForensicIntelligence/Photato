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
    colorLookupExportDraft?.cancel(); colorLookupExportWorker?.cancel(); colorLookupExportDraft = nil
  }
  func encodedColorLookup(size: Int, title: String,
    draft: ColorLookupExportDraft? = nil) async throws -> Data {
    guard colorLookupExportID == nil, !geometryBusy, !aiBusy,
      (draft != nil ? colorLookupExportDraft === draft : canExportColorLookup)
    else { throw CraftError.invalid("Finish the current edit or export first.") }
    let source = document, generation = layerPanelGeneration, id = UUID()
    if let draft, draft.original != source { throw CraftError.invalid("The document changed. Restart Color Lookup export.") }
    colorLookupExportID = id; geometryBusy = true
    let preparation = colorLookupExportPreparation
    let worker = Task.detached(priority: .userInitiated) { try preparation(source, size, title) }
    colorLookupExportWorker = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value }
      onCancel: { worker.cancel() } }; geometryTask = observer
    defer {
      if colorLookupExportID == id {
        colorLookupExportID = nil; colorLookupExportWorker = nil
        if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil }
      }
    }
    let data = try await withTaskCancellationHandler { try await worker.value }
      onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !worker.isCancelled, !observer.isCancelled, document == source,
      layerPanelGeneration == generation, draft == nil || colorLookupExportDraft === draft
    else { throw CancellationError() }
    return data
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
      Text("Format: CUBE").foregroundStyle(.secondary)
      Text("Export global color adjustments for reuse in other images and video editors.")
        .font(.callout).foregroundStyle(.secondary)
      if let error = draft.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      if draft.busy { ProgressView("Exporting color lookup table…") }
      HStack {
        Button("Cancel") { store.cancelColorLookupExport() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Export…") {
          draft.busy = true; draft.error = nil
          let size = draft.size, title = draft.title
          draft.task = Task { @MainActor in
            do {
              let data = try await store.encodedColorLookup(size: size, title: title, draft: draft)
              guard store.colorLookupExportDraft === draft, !Task.isCancelled else { return }
              draft.data = data; draft.busy = false; choosingFile = true
            } catch {
              if !Task.isCancelled { draft.error = error.localizedDescription; draft.busy = false }
            }
          }
        }.keyboardShortcut(.defaultAction)
          .disabled(draft.busy || !(2...ColorLUT.maximumSize).contains(draft.size)
            || draft.title.utf8.count > 1024 || draft.title.unicodeScalars.contains(where: { $0.value < 32 }))
      }
    }.padding(24).frame(width: 420)
      .disabled(choosingFile)
      .fileExporter(isPresented: $choosingFile, document: draft.data.map { LUTDocument(data: $0) },
        contentType: UTType(filenameExtension: "cube") ?? .data, defaultFilename: "Color Lookup.cube") { result in
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
