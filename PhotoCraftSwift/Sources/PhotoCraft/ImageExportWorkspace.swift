import AppKit
import Observation
import SwiftUI
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

enum ImageExportPreferences {
  static let key = "photato.quickExport.preferences"
  static let lastKey = "photato.exportAs.lastSettings"
  static func loadLast(_ defaults: UserDefaults = .standard) -> ImageExportSettings {
    guard let bytes = defaults.data(forKey: lastKey), let value = try? JSONDecoder().decode(ImageExportSettings.self, from: bytes), (try? value.validate()) != nil else { return .init() }; return value
  }
  static func saveLast(_ value: ImageExportSettings, defaults: UserDefaults = .standard) throws {
    var clean = value; clean.target = .document; clean.ids = []; clean.width = nil; clean.height = nil; clean.canvasWidth = nil; clean.canvasHeight = nil
    try clean.validate(); defaults.set(try JSONEncoder().encode(clean), forKey: lastKey)
  }
  static func load(_ defaults: UserDefaults = .standard) -> ImageExportSettings {
    guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(ImageExportSettings.self, from: data), (try? value.validate()) != nil else { return .init() }
    return value
  }
  static func save(_ value: ImageExportSettings, defaults: UserDefaults = .standard) throws {
    var clean = ImageExportSettings(); clean.format = value.format; clean.quality = value.quality; clean.transparency = value.transparency
    clean.convertToSRGB = value.convertToSRGB; clean.embedProfile = value.embedProfile; clean.metadata = value.metadata
    try clean.validate(); defaults.set(try JSONEncoder().encode(clean), forKey: key)
  }
}
@MainActor @Observable final class ImageExportDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let preferences: Bool
  var settings: ImageExportSettings
  var preview: NSImage?
  var previewFiles: [ImageExportFile] = []
  var error: String?
  var busy = false
  @ObservationIgnored var previewTask: Task<Void, Never>?
  @ObservationIgnored var previewWorker: Task<ImageExportOutput, Error>?
  init(_ document: CraftDocument, settings: ImageExportSettings, preferences: Bool = false) { original = document; self.settings = settings; self.preferences = preferences }
  func refresh() {
    let previous = previewWorker; previewTask?.cancel(); previewWorker?.cancel(); previewWorker = nil; error = nil; previewFiles = []
    guard !preferences else { return }
    let value = settings, source = original
    busy = true
    previewTask = Task { [weak self] in
      do {
        // Coalesce slider/text updates before starting ImageIO encoding.
        try await Task.sleep(for: .milliseconds(120))
        if let previous { _ = try? await previous.value }
        guard !Task.isCancelled, let self, self.settings == value else { return }
        let worker = Task.detached(priority: .userInitiated) { try ImageExportPreparation.render(source, settings: value) }; self.previewWorker = worker
        let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, self.settings == value else { return }
        self.previewFiles = output.files; self.preview = output.files.first.flatMap { file in
          guard let source = CGImageSourceCreateWithData(file.data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary) else { return nil }
          return NSImage(cgImage: image, size: .init(width: image.width, height: image.height))
        }; self.busy = false
      } catch { guard !Task.isCancelled, let self, self.settings == value else { return }; self.error = error.localizedDescription; self.busy = false }
    }
  }
  func cancel() { previewTask?.cancel(); previewWorker?.cancel() }
  deinit { previewTask?.cancel(); previewWorker?.cancel() }
}
extension EditorStore {
  var canExportImages: Bool { canEditFileInfo && numericEditor == nil && !coalescingChanges && timelineTask == nil }
  func beginImageExport(layers: Bool = false, preferences: Bool = false, quick: Bool = false) {
    guard canExportImages else { return }
    var settings = preferences || quick ? ImageExportPreferences.load() : ImageExportPreferences.loadLast()
    if layers { settings.target = .layers; settings.ids = selectedLayerIDs.isEmpty ? activeLayer.map { [$0.id] } ?? [] : document.layers.filter { selectedLayerIDs.contains($0.id) }.map(\.id) }
    else if document.hasArtboards, !preferences { settings.target = .artboards; settings.ids = document.artboards.map(\.id) }
    imageExportDraft = .init(document, settings: settings, preferences: preferences)
  }
  func cancelImageExport() { imageExportDraft?.cancel(); imageExportWorker?.cancel(); imageExportDraft = nil }
  func encodedImageAssets(_ settings: ImageExportSettings, draft: ImageExportDraft? = nil) async throws -> ImageExportOutput {
    guard imageExportID == nil, !geometryBusy, !aiBusy, (draft != nil ? imageExportDraft === draft : canExportImages) else { throw CraftError.invalid("Finish the current edit or export first.") }
    try settings.validate(); let snapshot = document, generation = layerPanelGeneration, id = UUID()
    imageExportID = id; geometryBusy = true
    let preparation = imageExportPreparation
    let worker = Task.detached(priority: .userInitiated) { try preparation(snapshot, settings) }; imageExportWorker = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }; geometryTask = observer
    defer { if imageExportID == id { imageExportID = nil; imageExportWorker = nil; if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil } } }
    let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !worker.isCancelled, !observer.isCancelled, document == snapshot, layerPanelGeneration == generation, draft == nil || imageExportDraft === draft else { throw CancellationError() }
    return output
  }
  func finishNativeImageExport(_ draft: ImageExportDraft) {
    if draft.preferences {
      do { try ImageExportPreferences.save(draft.settings); cancelImageExport() } catch { draft.error = error.localizedDescription }; return
    }
    let settings = draft.settings
    Task { @MainActor [weak self, weak draft] in
      guard let self, let draft else { return }
      do {
        let output = try await encodedImageAssets(settings, draft: draft)
        guard imageExportDraft === draft, document == draft.original, draft.settings == settings else { throw CancellationError() }
        let files = output.files
        let panel: NSSavePanel = files.count == 1 ? NSSavePanel() : NSOpenPanel()
        if let directory = panel as? NSOpenPanel { directory.canChooseFiles = false; directory.canChooseDirectories = true; directory.canCreateDirectories = true }
        else { panel.nameFieldStringValue = files[0].name; panel.allowedContentTypes = [settings.format == .png ? .png : settings.format == .jpeg ? .jpeg : .gif] }
        panel.title = "Export As"; panel.prompt = files.count == 1 ? "Export" : "Export All"
        // End the SwiftUI sheet before presenting the native destination panel.
        draft.cancel(); imageExportDraft = nil
        panel.begin { [weak self] response in
          guard response == .OK, let destination = panel.url, let self else { return }
          guard self.document == draft.original else { self.error = "The source changed. Open Export As again."; return }
          Task { @MainActor in
            do {
              try await Task.detached(priority: .userInitiated) { try ImageExportPublication.write(files, to: destination, directory: files.count != 1) }.value
              try ImageExportPreferences.saveLast(settings)
              self.status = "Exported \(files.count) asset\(files.count == 1 ? "" : "s")"
            } catch { self.error = "Export stopped: \(error.localizedDescription) Files already exported are retained." }
          }
        }
      } catch { if imageExportDraft === draft { draft.error = error.localizedDescription } }
    }
  }
  func quickExportImages(layers: Bool = false) {
    guard canExportImages else { return }
    beginImageExport(layers: layers, quick: true)
    if let draft = imageExportDraft { finishNativeImageExport(draft) }
  }
}
enum ImageExportPublication {
  static func write(_ files: [ImageExportFile], to destination: URL, directory: Bool) throws {
    guard !files.isEmpty, directory || files.count == 1 else { throw CraftError.invalid("Choose an export destination.") }
    if directory {
      let paths = files.map { destination.appendingPathComponent($0.name) }
      guard paths.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) }) else { throw CraftError.invalid("An export file already exists; choose another folder or suffix.") }
      for (file, path) in zip(files, paths) { try Task.checkCancellation(); try ArtboardExport.writeNew(file.data, to: path) }
    } else {
      let writer = try AtomicFileWriter(to: destination, maximumBytes: ImageAssetExport.maximumBytes); try writer.append(files[0].data); try Task.checkCancellation(); try writer.commit()
    }
  }
}
