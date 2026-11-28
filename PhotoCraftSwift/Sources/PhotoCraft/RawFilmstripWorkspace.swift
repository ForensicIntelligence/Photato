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
    var marking: RawPhotoMarking
    var name: String { original.url.lastPathComponent }
    var hasChanges: Bool { settings != original.settings || marking != original.marking }
  }

  struct Editor {
    let id: UUID
    let store: EditorStore
  }

  private struct Draft: Equatable {
    let settings: RawDevelopment
    let marking: RawPhotoMarking

    init(_ photo: Photo) {
      settings = photo.settings
      marking = photo.marking
    }
  }

  private struct Edit {
    let values: [UUID: Draft]
  }

  @ObservationIgnored private weak var controller: CraftDocumentController?
  @ObservationIgnored private var previewTask: Task<Void, Never>?
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var folderPanel: NSOpenPanel?
  @ObservationIgnored private var approvedFolders: [URL: URL] = [:]
  @ObservationIgnored private var onClose: (() -> Void)?
  private(set) var photos: [Photo] = []
  private var developedThumbnails: [UUID: (image: CGImage, settings: RawDevelopment)] = [:]
  @ObservationIgnored private var thumbnailOrder: [UUID] = []
  private static let thumbnailCapacity = 48
  var order: RawFilmstripOrder = .opening
  var reverseOrder = false
  static let defaultGridSize = 150.0
  static let gridSizeRange = 96.0...280.0
  var presentation = RawFilmstripPresentation.loupe
  var hdrMergeRequest: RawFilmstripHDRRequest?
  var panoramaRequest: RawFilmstripPanoramaRequest?
  var gridThumbnailSize = defaultGridSize
  var gridDetails = RawGridDetails.all
  private(set) var ratingFilter = RawFilmstripRatingFilter.all
  private(set) var labelFilters: Set<RawFilmstripLabel> = []
  private var hiddenPhotos: Set<UUID> = []
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
  var hiddenPhotoCount: Int { hiddenPhotos.count }

  var displayedPhotos: [Photo] {
    let matching = photos.filter { photo in
      !hiddenPhotos.contains(photo.id) && ratingFilter.includes(photo.marking.rating) &&
        (labelFilters.isEmpty || labelFilters.contains(RawFilmstripLabel(marking: photo.marking)))
    }
    let sorted: [Photo]
    switch order {
    case .opening: sorted = matching
    case .name: sorted = matching.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    case .captureDate: sorted = matching.sorted {
      ($0.original.photoInformation?.captureOrder ?? .distantFuture) < ($1.original.photoInformation?.captureOrder ?? .distantFuture)
    }
    case .fileType, .camera, .lens:
      let key: KeyPath<RawPhotoInformation, String?>
      switch order {
      case .fileType: key = \.formatSortName
      case .camera: key = \.cameraSortName
      default: key = \.lens
      }
      sorted = matching.sorted {
        let first = $0.original.photoInformation?[keyPath: key] ?? ""
        let second = $1.original.photoInformation?[keyPath: key] ?? ""
        return first.localizedStandardCompare(second) == .orderedAscending
      }
    case .rating: sorted = matching.sorted { ($0.marking.rating ?? 0) < ($1.marking.rating ?? 0) }
    case .label:
      sorted = matching.sorted {
        ($0.marking.label ?? "").localizedStandardCompare($1.marking.label ?? "") == .orderedAscending
      }
    }
    return reverseOrder ? Array(sorted.reversed()) : sorted
  }

  var canUndo: Bool { !undo.isEmpty }
  var canRedo: Bool { !redo.isEmpty }
  var activeSettings: RawDevelopment? { photos.first { $0.id == activeID }?.settings }
  var activeName: String? { photos.first { $0.id == activeID }?.name }
  var activeInformation: RawPhotoInformation? { photos.first { $0.id == activeID }?.original.photoInformation }
  var defaultOpenAsObject: Bool { controller?.cameraRawPreferences.openAsSmartObject ?? false }
  var workflowOutput: RawWorkflowOutput { controller?.cameraRawPreferences.workflowOutput ?? .init() }
  var canFinish: Bool { !selection.isEmpty && !busy && !closed }
  var canWrite: Bool {
    !photos.isEmpty && !busy && !closed && photos.allSatisfy { !$0.hasChanges || $0.original.settingsSource != nil }
  }

  init(controller: CraftDocumentController, onClose: (() -> Void)? = nil) {
    self.controller = controller
    self.onClose = onClose
  }

  func setWorkflow(_ output: RawWorkflowOutput) { controller?.cameraRawPreferences.workflowOutput = output }

  func canMergeHDR(contextPhoto: UUID? = nil) -> Bool {
    !busy && !closed && hdrMergeRequest == nil && panoramaRequest == nil
      && RawHDRMerge.sourceCount.contains(visibilityTargets(contextPhoto: contextPhoto).count)
  }

  func beginHDRMerge(contextPhoto: UUID? = nil, skipPreview: Bool = false) {
    guard canMergeHDR(contextPhoto: contextPhoto) else { return }
    let ids = visibilityTargets(contextPhoto: contextPhoto)
    let inputs = displayedPhotos.filter { ids.contains($0.id) }
    guard RawHDRMerge.sourceCount.contains(inputs.count) else { return }
    let settings = controller?.cameraRawPreferences.hdrMerge ?? .init()
    hdrMergeRequest = RawFilmstripHDRRequest(photos: inputs, skipPreview: skipPreview, settings: settings)
  }

  func dismissHDRMerge() { hdrMergeRequest = nil }

  func saveHDRMerge(_ result: RawHDRMerge.Result, to url: URL, requestID: UUID) async throws -> Photo {
    guard hdrMergeRequest?.id == requestID else { throw CancellationError() }
    return try await saveMergedDNG(to: url) { try result.write(to: $0) }
  }

  func saveMergedDNG(to url: URL, write: @escaping @Sendable (URL) throws -> Void) async throws -> Photo {
    guard let controller, !closed else { throw CancellationError() }
    let destination = url.standardizedFileURL.resolvingSymlinksInPath()
    guard destination.pathExtension.lowercased() == "dng", !photos.contains(where: {
      $0.original.url.standardizedFileURL.resolvingSymlinksInPath() == destination
    }) else {
      throw CraftError.invalid("Choose a DNG destination different from the source exposures.")
    }
    let storage = controller.cameraRawPreferences.dngStorage
    let defaults = controller.cameraRawPreferences.rawDefaults
    let worker = Task.detached(priority: .userInitiated) {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      try write(url)
      let source = try RawSourceIO.prepareLocalOriginal(url, dngStorage: storage, rawDefaults: defaults)
      return Photo(id: UUID(), original: source, thumbnail: source.thumbnail(),
        settings: source.settings, marking: source.marking)
    }
    return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
  }

  func acceptHDRMerge(_ photo: Photo, requestID: UUID, settings: RawHDRMergeSettings) {
    guard !closed, hdrMergeRequest?.id == requestID else { return }
    controller?.cameraRawPreferences.hdrMerge = settings
    addMergedPhoto(photo)
    dismissHDRMerge()
  }

  func addMergedPhoto(_ photo: Photo) {
    photos.append(photo)
    if displayedPhotos.contains(where: { $0.id == photo.id }) {
      select(photo.id)
      exportStatus = nil
    } else {
      exportStatus = "Saved \(photo.name). The current filters hide it."
    }
  }

  func canMergePanorama(contextPhoto: UUID? = nil) -> Bool {
    !busy && !closed && hdrMergeRequest == nil && panoramaRequest == nil
      && RawPanorama.sourceCount.contains(visibilityTargets(contextPhoto: contextPhoto).count)
  }

  func beginPanorama(contextPhoto: UUID? = nil, skipPreview: Bool = false) {
    guard canMergePanorama(contextPhoto: contextPhoto) else { return }
    let ids = visibilityTargets(contextPhoto: contextPhoto)
    let inputs = displayedPhotos.filter { ids.contains($0.id) }
    guard RawPanorama.sourceCount.contains(inputs.count) else { return }
    panoramaRequest = RawFilmstripPanoramaRequest(photos: inputs, skipPreview: skipPreview,
      settings: controller?.cameraRawPreferences.panoramaMerge ?? .init())
  }

  func savePanorama(_ result: RawPanorama.Result, to url: URL, requestID: UUID) async throws -> Photo {
    guard panoramaRequest?.id == requestID else { throw CancellationError() }
    return try await saveMergedDNG(to: url) { try result.write(to: $0) }
  }

  func acceptPanorama(_ photo: Photo, requestID: UUID, settings: RawPanoramaSettings) {
    guard !closed, panoramaRequest?.id == requestID else { return }
    controller?.cameraRawPreferences.panoramaMerge = settings
    addMergedPhoto(photo)
    panoramaRequest = nil
  }

  func thumbnail(for photo: Photo) -> CGImage? {
    if let cached = developedThumbnails[photo.id], cached.settings == photo.settings {
      return cached.image
    }
    return photo.thumbnail
  }

  func updateThumbnail(_ image: CGImage, settings: RawDevelopment, photoID: UUID) {
    guard !closed, activeID == photoID, settings == activeSettings else { return }
    thumbnailOrder.removeAll { $0 == photoID }
    thumbnailOrder.append(photoID)
    developedThumbnails[photoID] = (image, settings)
    if thumbnailOrder.count > Self.thumbnailCapacity {
      developedThumbnails.removeValue(forKey: thumbnailOrder.removeFirst())
    }
  }

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
          return Photo(id: UUID(), original: original, thumbnail: original.thumbnail(),
            settings: original.settings, marking: original.marking)
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
    let displayed = displayedPhotos
    guard !busy, !closed, let index = displayed.firstIndex(where: { $0.id == id }) else { return }
    if extending, let anchor, let start = displayed.firstIndex(where: { $0.id == anchor }) {
      let range = Set(displayed[min(index, start)...max(index, start)].map(\.id))
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
    selection = Set(displayedPhotos.map(\.id))
  }

  func selectActive() {
    guard let activeID else { return }
    select(activeID)
  }

  func navigate(_ step: Int) {
    guard !busy, let activeID else { return }
    let displayed = displayedPhotos
    let candidates = selection.count > 1 ? displayed.filter { selection.contains($0.id) } : displayed
    guard let index = candidates.firstIndex(where: { $0.id == activeID }),
      candidates.indices.contains(index + step) else { return }
    let id = candidates[index + step].id
    if selection.count == 1 { select(id) }
    else { activate(id) }
  }

  func selectRated() {
    guard !busy, !closed else { return }
    let rated = displayedPhotos.filter { ($0.marking.rating ?? 0) > 0 }
    selection = Set(rated.map(\.id))
    reconcileFilter(selectFirst: false)
  }

  func setRating(_ rating: Int) {
    guard (0...5).contains(rating) else { return }
    editMarking { $0.rating = rating }
  }

  func changeRating(_ step: Int) {
    editMarking { $0.rating = min(5, max(0, ($0.rating ?? 0) + step)) }
  }

  func setLabel(_ label: RawFilmstripLabel) {
    guard label != .other else { return }
    editMarking { $0.label = label == .none ? "" : label.rawValue }
  }

  private func editMarking(_ change: (inout RawPhotoMarking) -> Void) {
    guard !busy, !closed, !selection.isEmpty else { return }
    let snapshot = selectedEdit
    for index in photos.indices where selection.contains(photos[index].id) {
      change(&photos[index].marking)
    }
    record(snapshot)
    reconcileFilter()
  }

  func visibilityTargets(contextPhoto: UUID?) -> Set<UUID> {
    if let contextPhoto, !selection.contains(contextPhoto) { return [contextPhoto] }
    return selection
  }

  func hidePhotos(contextPhoto: UUID? = nil) {
    guard !busy, !closed else { return }
    let displayed = displayedPhotos.map(\.id)
    let targets = visibilityTargets(contextPhoto: contextPhoto).intersection(displayed)
    guard !targets.isEmpty else { return }
    hiddenPhotos.formUnion(targets)
    let replacement: UUID?
    if let index = displayed.firstIndex(where: { $0 == activeID }), targets.contains(displayed[index]) {
      replacement = displayed.dropFirst(index + 1).first { !targets.contains($0) }
        ?? displayed.prefix(index).reversed().first { !targets.contains($0) }
    } else { replacement = nil }
    reconcileFilter(preferredID: replacement)
  }

  func showOnlyPhotos(contextPhoto: UUID? = nil) {
    guard !busy, !closed else { return }
    let targets = visibilityTargets(contextPhoto: contextPhoto).intersection(displayedPhotos.map(\.id))
    guard !targets.isEmpty else { return }
    hiddenPhotos = Set(photos.map(\.id)).subtracting(targets)
    reconcileFilter()
  }

  func showAllHiddenPhotos() {
    guard !busy, !closed, !hiddenPhotos.isEmpty else { return }
    hiddenPhotos.removeAll()
    reconcileFilter()
  }

  func setRatingFilter(_ filter: RawFilmstripRatingFilter) {
    ratingFilter = filter
    reconcileFilter()
  }

  func toggleLabelFilter(_ label: RawFilmstripLabel) {
    if labelFilters.contains(label) { labelFilters.remove(label) } else { labelFilters.insert(label) }
    reconcileFilter()
  }

  func clearFilters() {
    ratingFilter = .all
    labelFilters.removeAll()
    reconcileFilter()
  }

  private func reconcileFilter(selectFirst: Bool = true, preferredID: UUID? = nil) {
    let displayed = displayedPhotos
    selection.formIntersection(displayed.map(\.id))
    if let activeID, selection.contains(activeID) { return }
    let selected = displayed.first { selection.contains($0.id) }
    let preferred = displayed.first { $0.id == preferredID }
    if let next = selected ?? preferred ?? (selectFirst ? displayed.first : nil) {
      selection.insert(next.id)
      anchor = next.id
      activate(next.id)
    } else {
      activeID = nil
      anchor = nil
      editor?.store.renderTask?.cancel()
      previewTask?.cancel()
      editor = nil
      loadingPreview = false
    }
  }

  func waitUntilIdle() async {
    await operation?.value
    await previewTask?.value
  }

  func activate(_ id: UUID) {
    guard activeID != id, let photo = photos.first(where: { $0.id == id }) else { return }
    previewTask?.cancel()
    activeID = id
    editor?.store.renderTask?.cancel()
    editor = nil
    loadingPreview = true
    previewTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) { try photo.original.document(settings: photo.settings, marking: photo.marking) }
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
    Edit(values: Dictionary(uniqueKeysWithValues:
      photos.filter { selection.contains($0.id) }.map { ($0.id, Draft($0)) }))
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

  func resetRawCrop() {
    guard let activeID, var settings = activeSettings, settings.crop != nil else { return }
    settings.crop = nil
    apply(settings, to: activeID)
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
    guard photos.contains(where: { photo in previous.values[photo.id].map { $0 != Draft(photo) } ?? false }) else { return }
    undo.append(previous)
    if undo.count > 100 { undo.removeFirst() }
    redo.removeAll()
  }

  func undoEdit() {
    guard !busy, let edit = undo.popLast() else { return }
    redo.append(restore(edit))
    reconcileFilter()
  }

  func redoEdit() {
    guard !busy, let edit = redo.popLast() else { return }
    undo.append(restore(edit))
    reconcileFilter()
  }

  private func restore(_ edit: Edit) -> Edit {
    var inverse: [UUID: Draft] = [:]
    for index in photos.indices {
      let id = photos[index].id
      if let previous = edit.values[id] {
        inverse[id] = Draft(photos[index])
        photos[index].settings = previous.settings
        photos[index].marking = previous.marking
      }
    }
    return Edit(values: inverse)
  }

  func finish(_ mode: RawOpenMode?) {
    guard let controller, mode == nil ? canWrite : canFinish else { return }
    let output = workflowOutput
    let batch = mode == nil ? photos.filter(\.hasChanges) : displayedPhotos.filter { selection.contains($0.id) }
    if batch.isEmpty { close(); return }
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
              let input = try photo.original.document(settings: photo.settings, marking: photo.marking)
              return try mode.output(from: input, workflow: output)
            }
            developed = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          } else { developed = nil }
          let source: RawSettingsSource?
          if mode == .copy { source = nil }
          else if let original = photo.original.settingsSource {
            let settingsChanged = photo.settings != photo.original.settings
            let markingChanged = photo.marking != photo.original.marking
            let markingOnly = markingChanged && !settingsChanged
            source = try await save(markingOnly ? nil : photo.settings, marking: photo.marking, to: original)
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
      hiddenPhotos.subtract(completed)
      selection.subtract(completed)
      reconcileFilter()
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
    let batch = displayedPhotos.filter { selection.contains($0.id) }
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
          let input = try photo.original.document(settings: photo.settings, marking: photo.marking)
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

  private func save(_ settings: RawDevelopment?, marking: RawPhotoMarking, to original: RawSettingsSource) async throws -> RawSettingsSource {
    let parent = original.url.deletingLastPathComponent().standardizedFileURL
    func write(_ folder: URL?) async throws -> RawSettingsSource {
      let worker = Task.detached(priority: .userInitiated) { try original.save(settings: settings, marking: marking, authorizedFolder: folder) }
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
    dismissHDRMerge()
    panoramaRequest = nil
    previewTask?.cancel()
    operation?.cancel()
    folderPanel?.cancel(nil)
    editor?.store.renderTask?.cancel()
    editor = nil
    photos.removeAll()
    hiddenPhotos.removeAll()
    developedThumbnails.removeAll()
    thumbnailOrder.removeAll()
    let callback = onClose
    onClose = nil
    callback?()
  }
}

private extension RawPhotoInformation {
  var formatSortName: String? { formatTitle }
  var cameraSortName: String? { camera }
}
