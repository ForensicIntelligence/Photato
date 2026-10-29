import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor extension CraftDocumentController {
  var canPublishVideoSequence: Bool { canPublishImageStack && imageStackWorkspace == nil }
  func publishVideoSequence(_ model: CraftDocument, display: Bool = true) throws -> CraftNSDocument {
    guard canPublishVideoSequence else { throw CraftError.invalid("Finish opening, closing or recovery before creating a video sequence.") }
    try model.validate(); let document = CraftNSDocument(model:model); addDocument(document);document.updateChangeCount(.changeDone)
    if display { document.makeWindowControllers();document.showWindows() };return document
  }
}
enum VideoSequenceImport {
  static func read(_ urls: [URL], frameRate: Double, name: String) throws -> CraftDocument {
    guard !urls.isEmpty, urls.count <= VideoClip.maximumFrames, Set(urls.map(\.standardizedFileURL)).count == urls.count else { throw CraftError.invalid("Choose 1–512 distinct PNG frames.") }
    var sources: [CraftDocument] = [], bytes = 0
    for url in VideoSequence.ordered(urls) {
      try Task.checkCancellation()
      guard DocumentOpenFormat.detect(url) == .png else { throw CraftError.invalid("Image sequence input currently requires PNG files.") }
      let model = try PreparedLocalDocument.read(url,format:.png).model
      let frameBytes = ((model.width+63)/64)*((model.height+63)/64)*65_536
      guard frameBytes <= 1_073_741_824 - bytes else { throw CraftError.invalid("Decoded sequence exceeds 1 GiB.") }
      bytes += frameBytes;sources.append(model)
    }
    return try VideoSequence.make(sources,frameRate:frameRate,name:name)
  }
}
extension EditorStore {
  func presentVideoSequenceImport() {
    guard canUseTimeline, let controller = documentController, controller.canPublishVideoSequence else { return }
    stopTimelinePlayback()
    let panel = NSOpenPanel();panel.title = "Import Image Sequence";panel.allowedContentTypes = [.png];panel.allowsMultipleSelection = true
    panel.message = "Choose the PNG frames. Files are ordered numerically and imported as one editable video layer."
    let rate = NSTextField(string:"30");rate.frame = NSRect(x:0,y:0,width:90,height:24)
    let row = NSStackView(views:[NSTextField(labelWithString:"Frame rate:"),rate,NSTextField(labelWithString:"fps")]);row.spacing = 8;row.setFrameSize(row.fittingSize);panel.accessoryView = row
    let window = NSApp.keyWindow
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self,weak controller] response in
      guard response == .OK, let self, let controller else { return }
      guard let fps = Double(rate.stringValue), fps.isFinite, (1...240).contains(fps), self.canUseTimeline, controller.canPublishVideoSequence else { self.error = "Choose a frame rate from 1 to 240 and finish other document operations.";return }
      let urls = panel.urls, generation = self.layerPanelGeneration, opening = controller.documentOpening.generation
      let name = urls.first?.deletingPathExtension().lastPathComponent ?? "Image Sequence"
      let progress = NSAlert();progress.messageText = "Importing Image Sequence";progress.informativeText = "Reading frames into a video layer…";progress.addButton(withTitle:"Cancel")
      let task = Task { @MainActor in
        let scoped = urls.filter{$0.startAccessingSecurityScopedResource()};defer { scoped.forEach{$0.stopAccessingSecurityScopedResource()} }
        self.geometryBusy = true
        defer { if self.layerPanelGeneration == generation { self.geometryBusy = false;self.geometryTask = nil }; if let parent = progress.window.sheetParent { parent.endSheet(progress.window,returnCode:.OK) } }
        let worker = Task.detached(priority:.userInitiated) { try VideoSequenceImport.read(urls,frameRate:fps,name:name) }
        let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel:{worker.cancel()} };self.geometryTask = observer
        do {
          let model = try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
          try Task.checkCancellation();guard !observer.isCancelled, self.layerPanelGeneration == generation,controller.documentOpening.generation == opening else { throw CancellationError() }
          _ = try controller.publishVideoSequence(model);self.status = "Imported \(urls.count) video frames"
        } catch is CancellationError { self.status = "Image sequence import cancelled" }
        catch { self.error = error.localizedDescription }
      }
      if let window { progress.beginSheetModal(for:window) { response in if response != .OK { task.cancel() } } }
    }
    if let window { panel.beginSheetModal(for:window,completionHandler:finish) } else { panel.begin(completionHandler:finish) }
  }
}
