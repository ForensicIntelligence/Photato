import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class RawFilmstripWorkspace {
  struct Photo: Identifiable, Sendable {
    let id: UUID
    let original: RawSourceIO.LocalOriginal
    let thumbnail: CGImage?
    var settings: RawDevelopment
    var name: String { original.url.lastPathComponent }
  }

  struct Editor {
    let id: UUID
    let store: EditorStore
  }

  private struct Edit {
    let settings: [UUID: RawDevelopment]
  }

  @ObservationIgnored private weak var controller: CraftDocumentController?
  @ObservationIgnored private var previewTask: Task<Void, Never>?
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var folderPanel: NSOpenPanel?
  @ObservationIgnored private var approvedFolders: [URL: URL] = [:]
  @ObservationIgnored private var onClose: (() -> Void)?
  private(set) var photos: [Photo] = []
  private(set) var activeID: UUID?
  private(set) var selection: Set<UUID> = []
  private var anchor: UUID?
  private(set) var editor: Editor?
  private(set) var loadingPreview = false
  private(set) var busy = false
  private(set) var finishing = false
  private(set) var closed = false
  private var undo: [Edit] = []
  private var redo: [Edit] = []
  private var sliderStart: Edit?
  var error: String?
  var progress: String?
  private(set) var exportStatus: String?
  var canUndo: Bool { !undo.isEmpty }
  var canRedo: Bool { !redo.isEmpty }
  var activeSettings: RawDevelopment? { photos.first { $0.id == activeID }?.settings }
  var activeName: String? { photos.first { $0.id == activeID }?.name }
  var defaultOpenAsObject: Bool { controller?.cameraRawPreferences.openAsSmartObject ?? false }
  var workflowOutput: RawWorkflowOutput { controller?.cameraRawPreferences.workflowOutput ?? .init() }
  var canFinish: Bool { !selection.isEmpty && !busy && !closed }
  var canWrite: Bool {
    canFinish && photos.filter { selection.contains($0.id) }.allSatisfy { $0.original.settingsSource != nil }
  }

  init(controller: CraftDocumentController, onClose: (() -> Void)? = nil) {
    self.controller = controller
    self.onClose = onClose
  }

  func setWorkflow(_ output: RawWorkflowOutput) { controller?.cameraRawPreferences.workflowOutput = output }

  func start(_ urls: [URL]) {
    guard operation == nil, let controller else { return }
    let storage = controller.cameraRawPreferences.dngStorage
    let defaults = controller.cameraRawPreferences.rawDefaults
    busy = true
    operation = Task { [weak self] in
      guard let self else { return }
      defer { busy = false; operation = nil; progress = nil }
      var failed: [String] = []
      for (index, url) in urls.enumerated() {
        if Task.isCancelled || closed { return }
        progress = "Reading photo \(index + 1) of \(urls.count)…"
        let worker = Task.detached(priority: .userInitiated) {
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          let original = try RawSourceIO.prepareLocalOriginal(url, dngStorage: storage, rawDefaults: defaults)
          return Photo(id: UUID(), original: original, thumbnail: original.thumbnail(), settings: original.settings)
        }
        do {
          let photo = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          try Task.checkCancellation()
          guard !closed else { return }
          photos.append(photo)
          if activeID == nil {
            selection = [photo.id]
            anchor = photo.id
            activate(photo.id)
          }
        } catch is CancellationError { return }
        catch { failed.append("\(url.lastPathComponent) — \(error.localizedDescription)") }
      }
      if !failed.isEmpty { error = failed.joined(separator: "\n") }
    }
  }

  func select(_ id: UUID, extending: Bool = false, toggling: Bool = false) {
    guard !busy, !closed, let index = photos.firstIndex(where: { $0.id == id }) else { return }
    if extending, let anchor, let start = photos.firstIndex(where: { $0.id == anchor }) {
      let range = Set(photos[min(index, start)...max(index, start)].map(\.id))
      selection = toggling ? selection.union(range) : range
    } else if toggling {
      anchor = id
      if selection.contains(id) {
        if selection.count > 1 { selection.remove(id) }
      } else { selection.insert(id) }
    } else {
      anchor = id
      selection = [id]
    }
    if selection.contains(id) { activate(id) }
    else if let activeID, !selection.contains(activeID), let next = photos.first(where: { selection.contains($0.id) }) {
      activate(next.id)
    }
  }

  func selectAll() {
    guard !busy else { return }
    selection = Set(photos.map(\.id))
  }

  func selectActive() {
    guard let activeID else { return }
    select(activeID)
  }

  func navigate(_ step: Int) {
    guard !busy, let activeID else { return }
    let candidates = selection.count > 1 ? photos.filter { selection.contains($0.id) } : photos
    guard let index = candidates.firstIndex(where: { $0.id == activeID }),
      candidates.indices.contains(index + step) else { return }
    let id = candidates[index + step].id
    if selection.count == 1 { select(id) }
    else { activate(id) }
  }

  func waitUntilIdle() async {
    await operation?.value
    await previewTask?.value
  }

  private func activate(_ id: UUID) {
    guard activeID != id, let photo = photos.first(where: { $0.id == id }) else { return }
    previewTask?.cancel()
    activeID = id
    editor?.store.renderTask?.cancel()
    editor = nil
    loadingPreview = true
    previewTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) { try photo.original.document(settings: photo.settings) }
      do {
        let document = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, activeID == id, !closed, let layer = document.layers.first else { return }
        let settings = activeSettings ?? photo.settings
        let store = EditorStore(document: document)
        var filter = RasterFilter(.cameraRaw)
        filter.cameraRaw = settings.adjustments
        store.filterDraft = FilterDraft(id: layer.id, filter: filter, rawDevelopment: settings)
        editor = Editor(id: id, store: store)
        loadingPreview = false
      } catch {
        guard let self, activeID == id, !closed, !Task.isCancelled else { return }
        loadingPreview = false
        self.error = "\(photo.name) — \(error.localizedDescription)"
      }
    }
  }

  private var selectedEdit: Edit {
    Edit(settings: Dictionary(uniqueKeysWithValues:
      photos.filter { selection.contains($0.id) }.map { ($0.id, $0.settings) }))
  }

  func slider(_ editing: Bool) {
    if editing { sliderStart = selectedEdit }
    else if let saved = sliderStart {
      sliderStart = nil
      record(saved)
    }
  }

  func apply(_ value: RawDevelopment, to id: UUID) {
    guard id == activeID, !busy, let before = activeSettings, before != value else { return }
    let snapshot = selectedEdit
    let groups = Set(RawSettingsGroup.allCases)
    for index in photos.indices where selection.contains(photos[index].id) {
      if photos[index].id == id {
        photos[index].settings = value
      } else {
        apply(value, at: index, groups: groups, before: before)
      }
    }
    if sliderStart == nil { record(snapshot) }
  }

  func synchronize(_ groups: Set<RawSettingsGroup>) {
    guard !groups.isEmpty, !busy, let source = activeSettings else { return }
    let snapshot = selectedEdit
    for index in photos.indices where selection.contains(photos[index].id) && photos[index].id != activeID {
      apply(source, at: index, groups: groups)
    }
    record(snapshot)
  }

  private func apply(_ value: RawDevelopment, at index: Int, groups: Set<RawSettingsGroup>,
    before: RawDevelopment? = nil) {
    let photo = photos[index]
    photos[index].settings = photo.settings.synchronizing(value, groups: groups,
      sensor: photo.original.sensorInfo, changesFrom: before)
  }

  private func record(_ previous: Edit) {
    guard photos.contains(where: { photo in previous.settings[photo.id].map { $0 != photo.settings } ?? false }) else { return }
    undo.append(previous)
    if undo.count > 100 { undo.removeFirst() }
    redo.removeAll()
  }

  func undoEdit() {
    guard !busy, let edit = undo.popLast() else { return }
    redo.append(restore(edit))
  }

  func redoEdit() {
    guard !busy, let edit = redo.popLast() else { return }
    undo.append(restore(edit))
  }

  private func restore(_ edit: Edit) -> Edit {
    var inverse: [UUID: RawDevelopment] = [:]
    for index in photos.indices {
      let id = photos[index].id
      if let previous = edit.settings[id] {
        inverse[id] = photos[index].settings
        photos[index].settings = previous
      }
    }
    return Edit(settings: inverse)
  }

  func finish(_ mode: RawOpenMode?) {
    guard canFinish, let controller, mode != nil || canWrite else { return }
    let output = workflowOutput
    let batch = photos.filter { selection.contains($0.id) }
    busy = true
    finishing = true
    error = nil
    operation = Task { [weak self, weak controller] in
      guard let self, let controller else { return }
      defer { busy = false; finishing = false; operation = nil; progress = nil }
      var completed = Set<UUID>(), failures: [String] = []
      var opened: [CraftNSDocument] = []
      for (index, photo) in batch.enumerated() {
        if Task.isCancelled || closed { break }
        progress = mode == nil ? "Saving settings \(index + 1) of \(batch.count)…"
          : "Opening photo \(index + 1) of \(batch.count)…"
        do {
          let developed: CraftDocument?
          if let mode {
            let worker = Task.detached(priority: .userInitiated) {
              let input = try photo.original.document(settings: photo.settings)
              return try mode.output(from: input, workflow: output)
            }
            developed = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          } else { developed = nil }
          let source: RawSettingsSource?
          if mode == .copy { source = nil }
          else if let original = photo.original.settingsSource {
            source = try await save(photo.settings, to: original)
          } else { source = nil }
          try Task.checkCancellation()
          if let mode, let developed {
            let document = CraftNSDocument(model: developed, actions: controller.scriptEvents.actions)
            document.fileType = CraftNSDocument.nativeType
            document.importedSourceURL = photo.original.url.standardizedFileURL.resolvingSymlinksInPath()
            document.completedRawOpenMode = mode
            document.completedRawWorkflow = output
            document.displayName = mode == .object ? "\(developed.name)-1" : photo.name
            if mode == .object, let source, let object = developed.layers.first?.smartObject,
              let layer = developed.layers.first {
              document.localRawSource = (layer.id, source, object.data)
            }
            opened.append(document)
          }
          controller.recoveryPreferences.remember(photo.original.url)
          completed.insert(photo.id)
        } catch is CancellationError { break }
        catch { failures.append("\(photo.name) — \(error.localizedDescription)") }
      }
      guard !closed else { return }
      for document in opened {
        controller.addDocument(document)
        document.updateChangeCount(.changeDone)
        document.makeWindowControllers()
        document.showWindows()
      }
      if completed == Set(batch.map(\.id)), failures.isEmpty { close(); return }
      photos.removeAll { completed.contains($0.id) }
      selection.subtract(completed)
      if let activeID, completed.contains(activeID), let first = photos.first {
        selection.insert(first.id)
        activate(first.id)
      }
      if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
  }

  func chooseExportDestination() {
    guard canFinish, folderPanel == nil,
      let model = editor?.store.document else { return }
    let panel = NSOpenPanel()
    panel.title = "Save Developed Images"
    panel.message = "Choose a folder for the selected photos. Existing files retain their names and contents."
    panel.prompt = "Save Images"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = photos.first { $0.id == activeID }?.original.url.deletingLastPathComponent()
    let workflow = workflowOutput
    let accessory = DocumentCopyAccessory(panel: nil, initial: .tiff, availableFormats: RawBatchExport.formats,
      depth: workflow.depth ?? model.depth, mode: model.colorMode,
      documentIsUntagged: model.profileIsUntagged == true, width: model.width, height: model.height)
    panel.accessoryView = accessory.view
    panel.isAccessoryViewDisclosed = true
    folderPanel = panel
    let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard let self else { return }
      self.folderPanel = nil
      if response == .OK, let folder = panel.url {
        self.exportImages(to: folder, format: accessory.format, options: accessory.encodingOptions)
      }
    }
    if let window = controller?.rawFilmstripWindow?.window {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else { panel.begin(completionHandler: completion) }
  }

  func exportImages(to folder: URL, format: DocumentIO.Format, options: RasterEncodingOptions = .init()) {
    guard canFinish, RawBatchExport.formats.contains(format), folder.isFileURL else { return }
    let batch = photos.filter { selection.contains($0.id) }
    let workflow = workflowOutput
    busy = true
    finishing = true
    progress = "Preparing \(batch.count) developed images…"
    exportStatus = nil
    error = nil
    operation = Task { [weak self] in
      guard let self else { return }
      defer { finishing = false; busy = false; progress = nil; operation = nil }
      let worker = Task.detached(priority: .userInitiated) {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let names = batch.map { RawBatchExport.name($0.name, format: format) }
        let staged = try PreparedImageProcessorFiles.stage(parent: folder, names: names) { index, url in
          let photo = batch[index]
          let input = try photo.original.document(settings: photo.settings)
          let prepared = try RawBatchExport.prepare(input, format: format, workflow: workflow, options: options)
          try prepared.write(to: url)
        }
        defer { staged.discard() }
        return try staged.commit(to: folder)
      }
      do {
        let files = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        if !closed { exportStatus = "Saved \(files.count) images." }
      } catch is CancellationError {
      } catch {
        if !closed { self.error = error.localizedDescription }
      }
    }
  }

  private func save(_ settings: RawDevelopment, to original: RawSettingsSource) async throws -> RawSettingsSource {
    let parent = original.url.deletingLastPathComponent().standardizedFileURL
    func write(_ folder: URL?) async throws -> RawSettingsSource {
      let worker = Task.detached(priority: .userInitiated) { try original.save(settings: settings, authorizedFolder: folder) }
      return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    do { return try await write(approvedFolders[parent]) }
    catch RawDNGSource.SaveError.sidecarAccessNeeded where approvedFolders[parent] == nil {
      let panel = NSOpenPanel()
      panel.title = "Allow Access to the Source Folder"
      panel.message = "Choose \(parent.lastPathComponent) to save Camera Raw settings for these photos."
      panel.directoryURL = parent
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.prompt = "Allow Access"
      folderPanel = panel
      defer { folderPanel = nil }
      guard await panel.begin() == .OK, let selected = panel.url else { throw CancellationError() }
      guard selected.standardizedFileURL.resolvingSymlinksInPath() == parent.resolvingSymlinksInPath() else {
        throw CraftError.invalid("Choose the folder containing the RAW original.")
      }
      let result = try await write(selected)
      approvedFolders[parent] = selected
      return result
    }
  }

  func close() {
    guard !closed else { return }
    closed = true
    previewTask?.cancel()
    operation?.cancel()
    folderPanel?.cancel(nil)
    editor?.store.renderTask?.cancel()
    editor = nil
    photos.removeAll()
    let callback = onClose
    onClose = nil
    callback?()
  }
}
