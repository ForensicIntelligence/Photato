import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor struct PhotomergeSource: Identifiable {
  let id = UUID()
  var model: CraftDocument
  var url: URL?
  var document: CraftNSDocument?
  var title: String { url?.lastPathComponent ?? model.name }
}
@MainActor @Observable final class PhotomergeWorkspace {
  weak var controller: CraftDocumentController?
  var sources = [PhotomergeSource]()
  var selected = Set<UUID>()
  var settings = PhotomergeSettings()
  var name = "Untitled Panorama"
  var loading = false
  var rendering = false
  var error: String?
  var image: CGImage?
  var result: Photomerge.Result?
  @ObservationIgnored var task: Task<Void,Never>?
  @ObservationIgnored var loadingTask: Task<Void,Never>?
  @ObservationIgnored var panel: NSOpenPanel?
  private var generation = 0
  private var closed = false
  private var preparedSettings: PhotomergeSettings?
  private var preparedName: String?
  var ready: Bool { result != nil && !loading && !rendering && error == nil && preparedSettings == settings && preparedName == name }
  init(controller: CraftDocumentController) { self.controller = controller }
  func invalidate() { generation += 1;task?.cancel();task = nil;result = nil;image = nil;error = nil;rendering = false }
  func close() { closed = true;invalidate();loadingTask?.cancel();loadingTask = nil;panel?.cancel(nil);panel = nil;loading = false }
  func removeSelected() { invalidate();sources.removeAll{selected.contains($0.id)};selected = [] }
  static func readable(_ document: CraftNSDocument) -> Bool {
    let s = document.store
    return document.closeWorkflowID == nil && !document.fileOperationBusy && !s.geometryBusy && !s.aiBusy && !s.hasToneDraft && s.transformDraft == nil && !s.coalescingChanges && s.error == nil && document.windowForSheet?.attachedSheet == nil
  }
  func addOpenDocuments() {
    guard !loading,let controller else { return };invalidate()
    let candidates = controller.documents.compactMap{$0 as? CraftNSDocument}.filter { doc in !sources.contains(where:{$0.document === doc}) }
    guard candidates.allSatisfy(Self.readable) else { error = "Finish editing the open documents before adding them.";return }
    guard sources.count+candidates.count <= PhotoAlign.maximumLayers else { error = "Choose at most sixteen source images.";return }
    sources += candidates.map{PhotomergeSource(model:$0.store.document,document:$0)}
  }
  func browse(folder: Bool = false) {
    guard panel == nil,!loading else { return }
    let picker = NSOpenPanel();panel = picker;picker.canChooseFiles = !folder;picker.canChooseDirectories = folder;picker.allowsMultipleSelection = !folder
    picker.title = folder ? "Choose a photo folder":"Choose panorama photos";picker.prompt = "Add"
    if !folder { picker.allowedContentTypes = DocumentIO.readableContentTypes }
    picker.begin { [weak self] response in
      MainActor.assumeIsolated {
        guard let self else { return };self.panel = nil;guard response == .OK else { return }
        self.load(picker.urls,folder:folder)
      }
    }
  }
  func load(_ urls: [URL],folder: Bool = false) {
    guard !loading,!closed else { return };invalidate();loading = true
    let existing = Set(sources.compactMap{ $0.url?.standardizedFileURL.resolvingSymlinksInPath() }),remaining = PhotoAlign.maximumLayers-sources.count
    loadingTask = Task { [weak self] in
      let scoped = urls.filter{$0.startAccessingSecurityScopedResource()};defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
      let worker = Task.detached(priority:.userInitiated) { () throws -> [(URL,CraftDocument)] in
        var paths = urls
        if folder {
          guard urls.count == 1 else { throw CraftError.invalid("Choose one folder.") }
          paths = try FileManager.default.contentsOfDirectory(at:urls[0],includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles]).filter { url in
            (try? url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true && DocumentOpenFormat.detect(url) != nil
          }.sorted{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}
        }
        var seen = existing;paths = paths.filter{seen.insert($0.standardizedFileURL.resolvingSymlinksInPath()).inserted}
        guard !paths.isEmpty else { throw CraftError.invalid("No new readable images were selected.") }
        guard paths.count <= remaining else { throw CraftError.invalid("Choose at most sixteen source images.") }
        return try paths.map { url in try Task.checkCancellation();return (url,try PreparedLocalDocument.read(url,format:.automatic).model) }
      }
      do {
        let loaded = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation();guard let self,!self.closed else { return }
        self.sources += loaded.map{PhotomergeSource(model:$0.1,url:$0.0)}
      } catch { if !Task.isCancelled { self?.error = error.localizedDescription } }
      self?.loading = false
    }
  }
  func refresh() {
    guard !loading,!closed else { return };invalidate()
    guard sources.count >= 2 else { error = "Add at least two overlapping photos.";return }
    for i in sources.indices { if let document = sources[i].document {
      guard controller?.documents.contains(where:{$0 === document}) == true,Self.readable(document) else { error = "A source closed or is being edited. Finish that operation, then preview again.";return }
      sources[i].model = document.store.document
    } }
    let snapshots = sources.map(\.model),settings = settings,name = name,token = generation;rendering = true
    task = Task { [weak self] in
      let worker = Task.detached(priority:.userInitiated) { () throws -> (Photomerge.Result,CGImage) in
        let result = try Photomerge.prepare(snapshots,settings:settings,name:name)
        return (result,try ColorManagement.displayImage(Renderer.composite(result.document),in:result.document))
      }
      do {
        let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation();guard let self,!self.closed,self.generation == token else { return }
        self.preparedSettings = settings;self.preparedName = name;self.result = value.0;self.image = value.1;self.rendering = false
      } catch { guard let self,!self.closed,self.generation == token else { return };self.rendering = false;if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  @discardableResult func commit(display: Bool = true) throws -> CraftNSDocument {
    guard ready,let result,let controller,controller.canPublishPhotomerge else { throw CraftError.invalid("Finish opening, closing or recovery before creating the panorama.") }
    for source in sources { if let document = source.document {
      guard controller.documents.contains(where:{$0 === document}),Self.readable(document),document.store.document == source.model else { throw CraftError.invalid("A source document changed. Preview the panorama again.") }
    } }
    let document = CraftNSDocument(model:result.document);controller.addDocument(document);document.updateChangeCount(.changeDone)
    if display { document.makeWindowControllers();document.showWindows() };controller.cancelPhotomerge();return document
  }
}
