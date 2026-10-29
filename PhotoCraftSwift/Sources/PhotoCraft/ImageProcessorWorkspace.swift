import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

@MainActor @Observable final class ImageProcessorWorkspace {
  weak var controller: CraftDocumentController?
  let library: ActionLibrary
  var settings = ImageProcessorSettings()
  var sources: [ActionBatchSource] = []
  var openSources: [UUID:CraftNSDocument] = [:]
  var destination: URL?
  var includeSubfolders = false
  var busy = false
  var completed = 0
  var outputs: [String] = []
  var error: String?
  @ObservationIgnored var task: Task<Void,Never>?
  @ObservationIgnored var worker: Task<ImageProcessor.Output,Error>?
  @ObservationIgnored var scopedURLs: [URL] = []
  @ObservationIgnored var operationID: UUID?
  init(controller: CraftDocumentController,library: ActionLibrary = .shared) {self.controller = controller;self.library = library}
  func hold(_ url: URL) {if url.startAccessingSecurityScopedResource() {scopedURLs.append(url)}}
  func release() {for url in scopedURLs {url.stopAccessingSecurityScopedResource()};scopedURLs = []}
  func clear() {guard !busy else{return};sources = [];openSources = [:];outputs = [];completed = 0;error = nil}
  func addOpen() {
    guard !busy,let controller else{return}
    let documents = controller.documents.compactMap{$0 as? CraftNSDocument}.filter {item in !openSources.values.contains(where:{$0 === item})}
    guard documents.allSatisfy(ContactSheetWorkspace.readable),sources.count+documents.count <= ImageProcessor.maximumSources else {error = "Finish open-document edits and choose at most256 images.";return}
    for document in documents {let source = ActionBatchSource(document:document.store.document);sources.append(source);openSources[source.id] = document}
    error = nil
  }
  func addFiles(_ urls: [URL],folder: Bool = false) throws {
    guard !busy else {throw CraftError.invalid("Image Processor is already running.")}
    var paths: [URL] = []
    if folder {
      guard urls.count == 1 else {throw CraftError.invalid("Choose one input folder.")}
      guard let iterator = FileManager.default.enumerator(at:urls[0],includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:includeSubfolders ? [.skipsHiddenFiles,.skipsPackageDescendants]:[.skipsHiddenFiles,.skipsPackageDescendants,.skipsSubdirectoryDescendants]) else {throw CraftError.invalid("Could not read that folder.")}
      while let url = iterator.nextObject() as? URL {
        let info = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
        // URL enumeration already avoids following symlinks. Calling
        // skipDescendants on a link can skip the next real directory instead.
        if info.isSymbolicLink == true {continue}
        if info.isRegularFile == true,DocumentOpenFormat.detect(url) != nil {paths.append(url)}
        guard paths.count+sources.count <= ImageProcessor.maximumSources else {throw CraftError.invalid("Choose at most256 images.")}
      }
      paths.sort{$0.path.localizedStandardCompare($1.path) == .orderedAscending}
    } else {paths = urls}
    var seen = Set(sources.compactMap{$0.url?.standardizedFileURL.resolvingSymlinksInPath()})
    paths = paths.filter{seen.insert($0.standardizedFileURL.resolvingSymlinksInPath()).inserted}
    guard sources.count+paths.count <= ImageProcessor.maximumSources else {throw CraftError.invalid("Choose at most256 images.")}
    for url in urls {hold(url)};sources += paths.map{ActionBatchSource(id:UUID(),name:$0.lastPathComponent,document:nil,url:$0)};error = nil
  }
  func browse(folder: Bool) {
    guard !busy else{return};let panel = NSOpenPanel();panel.canChooseFiles = !folder;panel.canChooseDirectories = folder;panel.allowsMultipleSelection = !folder
    if !folder {panel.allowedContentTypes = DocumentIO.readableContentTypes}
    panel.begin { [weak self] response in guard response == .OK,let self else{return};do {try self.addFiles(panel.urls,folder:folder)} catch {self.error = error.localizedDescription}}
  }
  func chooseDestination() {
    guard !busy else{return};let panel = NSOpenPanel();panel.canChooseFiles = false;panel.canChooseDirectories = true;panel.canCreateDirectories = true
    panel.begin { [weak self] response in guard response == .OK,let self,!self.busy,let url = panel.url else{return};self.hold(url);self.destination = url}
  }
  func loadSettings() {
    guard !busy else{return};let panel = NSOpenPanel();panel.allowedContentTypes = [.json]
    panel.begin { [weak self] response in guard response == .OK,let self,!self.busy,let url = panel.url else{return}
      let scoped = url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
      do {self.settings = try ImageProcessorSettings.decode(Data(contentsOf:url))} catch {self.error = error.localizedDescription}
    }
  }
  func saveSettings() {
    guard !busy else{return}
    do {
      let bytes = try settings.encoded(),panel = NSSavePanel();panel.allowedContentTypes = [.json];panel.nameFieldStringValue = "Image Processor.json"
      panel.begin { [weak self] response in guard response == .OK,let self,let url = panel.url else{return}
        let scoped = url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
        do {try bytes.write(to:url,options:.atomic)} catch {self.error = error.localizedDescription}
      }
    } catch {self.error = error.localizedDescription}
  }
  func cancel() {task?.cancel();worker?.cancel()}
  func run() {
    guard !busy,let destination else{return}
    do {
      try settings.validate();guard !sources.isEmpty else {throw CraftError.invalid("Choose images to process.")}
      for i in sources.indices {if let document = openSources[sources[i].id] {
        guard controller?.documents.contains(where:{$0 === document}) == true,ContactSheetWorkspace.readable(document) else {throw CraftError.invalid("Finish editing the open source images.")}
        let old = sources[i];sources[i] = ActionBatchSource(id:old.id,name:document.store.document.name,document:document.store.document,url:nil)
      }}
      let inputs = sources,settings = settings,action = try settings.actionID.map{try library.action($0)},id = UUID()
      operationID = id;busy = true;error = nil;completed = 0;outputs = []
      task = Task { [weak self] in
        guard let self else{return};defer {self.busy = false;self.worker = nil;self.operationID = nil}
        do {
          let worker = Task.detached(priority:.userInitiated) {
            try ImageProcessor.render(inputs,settings:settings,action:action) {done,_ in
              Task {@MainActor [weak self] in if self?.operationID == id {self?.completed = done}}
            }
          };self.worker = worker
          let output = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
          let stage = Task.detached(priority:.userInitiated) {try PreparedImageProcessorFiles.prepare(output,parent:destination)}
          let prepared = try await withTaskCancellationHandler {try await stage.value} onCancel:{stage.cancel()};defer {prepared.discard()}
          self.outputs = try prepared.commit(to:destination) {
            try Task.checkCancellation()
            for input in inputs {if let document = self.openSources[input.id] {
              guard self.controller?.documents.contains(where:{$0 === document}) == true,ContactSheetWorkspace.readable(document),document.store.document == input.document else {throw CraftError.invalid("An open source changed. Run Image Processor again.")}
            }}
          }
          self.completed = inputs.count
        } catch is CancellationError {self.error = "Image processing cancelled."} catch {self.error = error.localizedDescription}
      }
    } catch {self.error = error.localizedDescription}
  }
}
