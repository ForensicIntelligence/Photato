import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor struct ContactSheetSource: Identifiable {
  let id = UUID()
  var model: CraftDocument
  var url: URL?
  var document: CraftNSDocument?
  var title: String { url?.lastPathComponent ?? model.name }
}
@MainActor @Observable final class ContactSheetWorkspace {
  weak var controller: CraftDocumentController?
  var sources = [ContactSheetSource]()
  var selected = Set<UUID>()
  var settings = ContactSheetSettings()
  var name = "ContactSheet"
  var loading = false
  var rendering = false
  var error: String?
  var image: CGImage?
  var result: ContactSheet.Result?
  @ObservationIgnored var task: Task<Void,Never>?
  @ObservationIgnored var loadingTask: Task<Void,Never>?
  @ObservationIgnored var panel: NSOpenPanel?
  private var generation = 0
  private var closed = false
  private var preparedSettings: ContactSheetSettings?
  private var preparedName: String?
  var ready: Bool { !closed && result != nil && !loading && !rendering && error == nil && preparedSettings == settings && preparedName == name }
  var page = 0
  var includeSubfolders = false
  init(controller: CraftDocumentController) { self.controller = controller }
  func invalidate() { generation += 1;task?.cancel();task = nil;result = nil;page = 0;image = nil;error = nil;rendering = false }
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
    guard sources.count+candidates.count <= ContactSheet.maximumSources else { error = "Choose at most 256 source images.";return }
    sources += candidates.map{ContactSheetSource(model:$0.store.document,document:$0)}
  }
  func browse(folder: Bool = false) {
    guard panel == nil,!loading else { return }
    let picker = NSOpenPanel();panel = picker;picker.canChooseFiles = !folder;picker.canChooseDirectories = folder;picker.allowsMultipleSelection = !folder
    picker.title = folder ? "Choose a photo folder":"Choose contact sheet photos";picker.prompt = "Add"
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
    let recursive = includeSubfolders
    let existing = Set(sources.compactMap{ $0.url?.standardizedFileURL.resolvingSymlinksInPath() }),remaining = ContactSheet.maximumSources-sources.count
    loadingTask = Task { [weak self] in
      let scoped = urls.filter{$0.startAccessingSecurityScopedResource()};defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
      let worker = Task.detached(priority:.userInitiated) { () throws -> [(URL,CraftDocument)] in
        var paths = urls
        if folder {
          guard urls.count == 1 else { throw CraftError.invalid("Choose one folder.") }
          let keys: [URLResourceKey] = [.isRegularFileKey,.isSymbolicLinkKey]
          let candidates: [URL]
          if recursive {
            guard let iterator = FileManager.default.enumerator(at:urls[0],includingPropertiesForKeys:keys,options:[.skipsHiddenFiles,.skipsPackageDescendants]) else { throw CraftError.invalid("Could not read that folder.") }
            var collected: [URL] = []
            while let url = iterator.nextObject() as? URL {
              try Task.checkCancellation()
              let values = try url.resourceValues(forKeys:Set(keys))
              // Enumeration never follows links; skipping their descendants can
              // accidentally suppress the next real subdirectory on macOS.
              if values.isSymbolicLink == true { continue }
              if values.isRegularFile == true,DocumentOpenFormat.detect(url) != nil { collected.append(url) }
              guard collected.count <= remaining else { throw CraftError.invalid("Choose at most256 source images.") }
            }
            candidates = collected
          } else { candidates = try FileManager.default.contentsOfDirectory(at:urls[0],includingPropertiesForKeys:keys,options:[.skipsHiddenFiles]) }
          paths = try candidates.filter { url in
            let values = try url.resourceValues(forKeys:Set(keys))
            return values.isRegularFile == true && values.isSymbolicLink != true && DocumentOpenFormat.detect(url) != nil
          }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        }
        var seen = existing;paths = paths.filter{seen.insert($0.standardizedFileURL.resolvingSymlinksInPath()).inserted}
        guard !paths.isEmpty else { throw CraftError.invalid("No new readable images were selected.") }
        guard paths.count <= remaining else { throw CraftError.invalid("Choose at most 256 source images.") }
        var bytes = 0
        return try paths.map { url in
          try Task.checkCancellation()
          let document = try PreparedLocalDocument.read(url,format:.automatic).model
          bytes += document.estimatedBytes
          guard bytes <= ContactSheet.maximumBytes else { throw CraftError.invalid("Source documents exceed512MiB.") }
          return (url,document)
        }
      }
      do {
        let loaded = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation();guard let self,!self.closed else { return }
        self.sources += loaded.map{ContactSheetSource(model:$0.1,url:$0.0)}
      } catch { if !Task.isCancelled { self?.error = error.localizedDescription } }
      self?.loading = false
    }
  }
  func refresh() {
    guard !loading,!closed else { return };invalidate()
    guard !sources.isEmpty else { error = "Add at least one source image.";return }
    for i in sources.indices { if let document = sources[i].document {
      guard controller?.documents.contains(where:{$0 === document}) == true,Self.readable(document) else { error = "A source closed or is being edited. Finish that operation, then preview again.";return }
      sources[i].model = document.store.document
    } }
    let snapshots = sources.map { ContactSheet.Source(document:$0.model,name:$0.title) },settings = settings,name = name,token = generation;rendering = true
    task = Task { [weak self] in
      let worker = Task.detached(priority:.userInitiated) { () throws -> (ContactSheet.Result,CGImage) in
        let result = try ContactSheet.prepare(snapshots,settings:settings,name:name)
        return (result,try ColorManagement.displayImage(Renderer.composite(result.documents[0]),in:result.documents[0]))
      }
      do {
        let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation();guard let self,!self.closed,self.generation == token else { return }
        self.preparedSettings = settings;self.preparedName = name;self.result = value.0;self.image = value.1;self.rendering = false
      } catch { guard let self,!self.closed,self.generation == token else { return };self.rendering = false;if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func moveSelected(_ offset: Int) {
    guard !loading,selected.count == 1,let index = sources.firstIndex(where:{selected.contains($0.id)}),sources.indices.contains(index+offset) else { return }
    invalidate();sources.swapAt(index,index+offset)
  }
  func showPage(_ index: Int) {
    guard !rendering,let result,result.documents.indices.contains(index) else { return }
    page = index;rendering = true;let document = result.documents[index],token = generation
    task = Task { [weak self] in
      let worker = Task.detached(priority:.userInitiated) { try ColorManagement.displayImage(Renderer.composite(document),in:document) }
      do {
        let image = try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation == token else {return}
        self.image = image;self.rendering = false
      } catch { guard let self,self.generation == token else{return};self.rendering = false;if !Task.isCancelled {self.error = error.localizedDescription} }
    }
  }
  @discardableResult func commit(display: Bool = true) throws -> [CraftNSDocument] {
    guard ready,let result,let controller,controller.canPublishContactSheet else { throw CraftError.invalid("Finish opening, closing or recovery before creating the contact sheet.") }
    for source in sources { if let document = source.document {
      guard controller.documents.contains(where:{$0 === document}),Self.readable(document),document.store.document == source.model else { throw CraftError.invalid("A source document changed. Preview the contact sheet again.") }
    } }
    let documents = result.documents.map { CraftNSDocument(model:$0) }
    for document in documents { controller.addDocument(document);document.updateChangeCount(.changeDone) }
    if display { for document in documents { document.makeWindowControllers();document.showWindows() } };controller.cancelContactSheet();return documents
  }
}
