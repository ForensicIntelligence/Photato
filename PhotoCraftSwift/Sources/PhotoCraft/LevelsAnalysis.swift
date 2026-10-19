import Foundation
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct LevelsAnalysisRequest: Equatable, Sendable {
  var document: CraftDocument
  let layerID: UUID
  let pixelLayer: Bool
  let luminance: Bool
  init(document: CraftDocument, layerID: UUID, pixelLayer: Bool, luminance: Bool = false) {
    self.document = document
    self.layerID = layerID
    self.pixelLayer = pixelLayer
    self.luminance = luminance
    if !pixelLayer, let i = self.document.layers.firstIndex(where: { $0.id == layerID }) {
      // Input is independent of the adjustment being edited. Avoid recalculating
      // a full histogram on every slider event or canvas preview completion.
      self.document.layers[i].content = .adjustment(.levels(.init()))
    }
  }
  func analyze() throws -> RGBHistogram {
    try pixelLayer
      ? RGBHistogram.pixelLayer(layerID, in: document, luminance: luminance)
      : Renderer.levelsHistogram(layerID, in: document, luminance: luminance)
  }
}

@MainActor @Observable final class LevelsAnalysis {
  private(set) var histogram: RGBHistogram?
  private(set) var error: String?
  private(set) var busy = false
  private(set) var request: LevelsAnalysisRequest?
  var task: Task<Void, Never>?
  private var generation = UUID()
  func update(_ request: LevelsAnalysisRequest) {
    guard self.request != request else { return }
    task?.cancel()
    self.request = request
    histogram = nil
    error = nil
    busy = true
    let ticket = UUID()
    generation = ticket
    task = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) { try request.analyze() }
      do {
        let histogram = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        guard let self, !Task.isCancelled, generation == ticket else { return }
        self.histogram = histogram
        self.busy = false
      } catch is CancellationError {} catch {
        guard let self, !Task.isCancelled, generation == ticket else { return }
        self.error = error.localizedDescription
        self.busy = false
      }
    }
  }
  func cancel() {
    task?.cancel()
    generation = UUID()
    request = nil
    busy = false
  }
}

struct LevelsEditor: View {
  @Bindable var store: EditorStore
  let layerID: UUID
  var pixelLayer = false
  @State private var analysis = LevelsAnalysis()
  var request: LevelsAnalysisRequest {
    .init(document: store.document, layerID: layerID, pixelLayer: pixelLayer)
  }
  var body: some View {
    LevelsControls(
      levels: Binding(
        get: {
          if pixelLayer { return store.levelsDraft?.levels ?? .init() }
          if case .adjustment(.levels(let value)) = store.document.layers.first(where: {
            $0.id == layerID
          })?.content {
            return value
          }
          return .init()
        },
        set: { value in
          if pixelLayer {
            store.levelsDraft?.levels = value
            store.render()
          } else {
            store.setLevels(layerID, value)
          }
        }), coalesce: { if !pixelLayer { store.coalesce($0) } },
      histogram: analysis.histogram, analysisBusy: analysis.busy, analysisError: analysis.error
    )
    .onChange(of: request, initial: true) { _, value in analysis.update(value) }
    .onDisappear { analysis.cancel() }
  }
}

struct LevelsPresetFile: FileDocument {
  static let type = UTType(filenameExtension: "alv") ?? .data
  static var readableContentTypes: [UTType] { [type] }
  var levels: LevelsAdjustment
  var original: Data?
  init(levels: LevelsAdjustment, original: Data? = nil) {
    self.levels = levels
    self.original = original
  }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CraftError.invalid("Invalid Levels preset file.")
    }
    levels = try LevelsPresetCodec.read(data)
    original = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: try LevelsPresetCodec.write(levels, original: original))
  }
  static func load(_ url: URL) throws -> Self {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 4097) ?? Data()
    return .init(levels: try LevelsPresetCodec.read(data), original: data)
  }
}
