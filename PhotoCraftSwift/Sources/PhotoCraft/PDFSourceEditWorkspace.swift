import AppKit
import Darwin
import Observation
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

/// Watch both the directory (atomic replacements) and current inode (in-place saves).
private final class PDFSourceWatch: @unchecked Sendable {
  private let source: any DispatchSourceFileSystemObject
  init(_ url: URL, changed: @escaping @Sendable () -> Void) throws {
    let fd = Darwin.open(url.path,O_EVTONLY)
    guard fd >= 0 else {throw CocoaError(.fileReadUnknown)}
    source = DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,
      eventMask:[.write,.extend,.attrib,.rename,.delete,.revoke],queue:.global(qos:.utility))
    source.setEventHandler(handler:changed);source.setCancelHandler {Darwin.close(fd)};source.resume()
  }
  deinit {source.cancel()}
}

@MainActor @Observable final class PDFSourceEditWorkspace {
  let id = UUID(),sourceID: UUID,documentID: UUID,layerID: UUID,workingURL: URL
  let fileName: String
  private(set) var stage = "opening"
  private(set) var message = "Opening PDF source…"
  private(set) var revision: String
  @ObservationIgnored weak var store: EditorStore?
  @ObservationIgnored private let lifecycle: UUID
  @ObservationIgnored private var directoryWatch: PDFSourceWatch?
  @ObservationIgnored private var fileWatch: PDFSourceWatch?
  @ObservationIgnored private var ticket = UUID()
  @ObservationIgnored private var operation: UUID?
  @ObservationIgnored private var openingTask: Task<Void,Never>?
  @ObservationIgnored private(set) var updateTask: Task<Void,Never>?
  @ObservationIgnored private var stopped = false
  @ObservationIgnored var prepare: @Sendable (Data,CraftDocument,UUID,String) async throws -> Command = {
    try PDFSmartObjectIO.sourceUpdate($0,in:$1,layerID:$2,expectedRevision:$3)
  }
  init(store: EditorStore,layer: Layer,root: URL) throws {
    guard let source = layer.smartObject,source.pdfSource != nil else {throw CraftError.invalid("Select a PDF Smart Object.")}
    self.store = store;sourceID = source.sourceID;documentID = store.document.id;layerID = layer.id
    lifecycle = store.layerPanelGeneration;revision = source.revision;fileName = source.fileName
    workingURL = root.appendingPathComponent(id.uuidString,isDirectory:true).appendingPathComponent("Contents.pdf")
  }
  static func openInAssociatedEditor(_ url: URL) async throws {
    let workspace = NSWorkspace.shared
    var app = workspace.urlForApplication(toOpen:url)
    if app == Bundle.main.bundleURL || app.flatMap({Bundle(url:$0)?.bundleIdentifier}) == Bundle.main.bundleIdentifier {
      app = workspace.urlForApplication(withBundleIdentifier:"com.apple.Preview")
    }
    guard let app else {throw CraftError.invalid("Choose a default PDF editor in Finder to edit this source.")}
    _ = try await workspace.open([url],withApplicationAt:app,configuration:NSWorkspace.OpenConfiguration())
  }
  func start() {
    guard let store,let source = store.document.layers.first(where:{$0.id == layerID})?.smartObject else {return}
    let url = workingURL,bytes = source.data
    let metadata: [String:String] = ["version":"1","documentID":documentID.uuidString,"sourceID":sourceID.uuidString,
      "layerID":layerID.uuidString,"originalFileName":fileName,"initialRevision":revision]
    openingTask = Task { [weak self] in
      guard let self else {return}
      do {
        let worker = Task.detached(priority:.userInitiated) {
          try Task.checkCancellation()
          try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,
            attributes:[.posixPermissions:0o700])
          try bytes.write(to:url,options:.atomic)
          try JSONSerialization.data(withJSONObject:metadata,options:.sortedKeys).write(to:url.deletingLastPathComponent().appendingPathComponent("source.json"),options:.atomic)
        }
        try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation();_ = try self.current()
        self.directoryWatch = try PDFSourceWatch(url.deletingLastPathComponent()) {[weak self] in Task {@MainActor in self?.saved()}}
        self.rearmFileWatch();self.stage = "watching";self.message = "Save in your PDF editor to update all instances."
        try await store.pdfSourceOpener(url)
        try Task.checkCancellation()
      } catch is CancellationError {} catch {
        if !self.stopped {self.stage = "error";self.message = error.localizedDescription}
      }
      self.openingTask = nil
    }
  }
  func waitUntilOpened() async {await openingTask?.value}
  func reopen() {
    guard !stopped,let store else {return}
    Task { [weak self] in
      guard let self else {return}
      do {try await store.pdfSourceOpener(self.workingURL)}
      catch {if !self.stopped {self.stage = "error";self.message = error.localizedDescription}}
    }
  }
  private func rearmFileWatch() {
    fileWatch = try? PDFSourceWatch(workingURL) {[weak self] in Task {@MainActor in self?.saved()}}
  }
  private func current(checkRevision: Bool = true) throws -> (EditorStore,Layer,SmartObject) {
    guard !stopped,let store,store.layerPanelGeneration == lifecycle,store.document.id == documentID,
      let layer = store.document.layers.first(where:{$0.smartObject?.sourceID == sourceID}),
      let source = layer.smartObject,source.pdfSource != nil else {throw CraftError.invalid("The parent PDF source is no longer available. The saved working copy is retained.")}
    guard !checkRevision || source.revision == revision else {
      throw CraftError.invalid("The parent source changed. Apply Saved PDF explicitly to replace it, or stop editing and reopen the current source.")
    }
    return (store,layer,source)
  }
  func saved(explicit: Bool = false) {
    guard !stopped else {return}
    updateTask?.cancel();releaseOperation();ticket = UUID();let expectedTicket = ticket
    updateTask = Task {[weak self] in
      guard let self else {return}
      defer {if self.ticket == expectedTicket {self.releaseOperation();self.updateTask = nil}}
      do {
        if !explicit {try await Task.sleep(for:.milliseconds(250))}
        let (owner,_,source) = try self.current(checkRevision:!explicit)
        if explicit {self.revision = source.revision}
        self.stage = "reading";self.message = "Reading saved PDF…";self.rearmFileWatch()
        let url = self.workingURL
        let reader = Task.detached(priority:.userInitiated) {
          var failure: (any Error)?
          for _ in 0..<3 {
            try Task.checkCancellation()
            do {return try PreparedPDFSource.read(url).data}
            catch {failure = error;try await Task.sleep(for:.milliseconds(150))}
          }
          throw failure!
        }
        let bytes = try await withTaskCancellationHandler {try await reader.value} onCancel:{reader.cancel()}
        try Task.checkCancellation()
        if bytes == source.data {self.stage = "watching";self.message = "The saved PDF is up to date.";return}
        while !owner.canApplyPDFSourceEdit {
          _ = try self.current();self.stage = "waiting";self.message = "Saved PDF is waiting for the current document edit."
          try await Task.sleep(for:.milliseconds(150))
        }
        let (_,layer,current) = try self.current();let original = owner.document,session = owner.sessionGeneration
        let operation = UUID();self.operation = operation;owner.pdfSourceEditOperationID = operation
        owner.geometryBusy = true;owner.geometryTask = self.updateTask;owner.renderTask?.cancel()
        self.stage = "updating";self.message = "Updating PDF instances…"
        let prepare = self.prepare,revision = current.revision,target = layer.id
        let worker = Task.detached(priority:.userInitiated) {
          let command = try await prepare(bytes,original,target,revision)
          return try PreparedEdit(command:command,document:original)
        }
        let prepared = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation();_ = try self.current()
        guard self.ticket == expectedTicket,owner.pdfSourceEditOperationID == operation,
          owner.document == original,owner.sessionGeneration == session else {throw CraftError.invalid("The parent changed while preparing the saved PDF.")}
        try owner.executeCompositePreparedEdit(prepared)
        self.revision = owner.document.layers.first(where:{$0.id == target})!.smartObject!.revision
        if owner.document != original {owner.onChange?(.changeDone)}
        owner.status = "PDF source updated";self.stage = "watching";self.message = "Saved PDF updated in all instances."
      } catch is CancellationError {
        if self.ticket == expectedTicket,!self.stopped {self.stage = "watching";self.message = "PDF update cancelled; saved working copy retained."}
      } catch {
        if self.ticket == expectedTicket,!self.stopped {
          self.stage = (try? self.current()) == nil ? "conflict":"error";self.message = error.localizedDescription
        }
      }
    }
  }
  private func releaseOperation() {
    if let operation,let store,store.pdfSourceEditOperationID == operation {
      store.pdfSourceEditOperationID = nil;store.geometryBusy = false;store.geometryTask = nil;store.render()
    }
    operation = nil
  }
  func stop() {
    stopped = true;ticket = UUID();openingTask?.cancel();updateTask?.cancel()
    directoryWatch = nil;fileWatch = nil;releaseOperation()
    stage = "stopped";message = "Editing stopped. The PDF working copy is retained."
  }
  var apiState: [String:Any] {
    ["sessionID":id.uuidString,"sourceID":sourceID.uuidString,"layerID":layerID.uuidString,
     "sourceRevision":revision,"fileName":fileName,"stage":stage,"message":message,"workingCopyRetained":true]
  }
}

extension EditorStore {
  var canApplyPDFSourceEdit: Bool {
    guard clipboardTargetAvailable,!smartFilterMaskEditing,historyOperation == nil,!aiBusy,!coalescingChanges,
      numericEditor == nil,layerNameDraft == nil,layerProtectionDraft == nil,pathGesture == nil,
      geometrySheet == nil,!showFeatherSelection,patternNameDraft == nil,gradientNameDraft == nil,
      !showAI,!showImagePlayground,error == nil,NSApp?.modalWindow == nil else {return false}
    if let owner = documentController?.documents.compactMap({$0 as? CraftNSDocument}).first(where:{$0.store === self}) {
      return owner.closeWorkflowID == nil && owner.recoverySourceStatus != .checking && !owner.fileOperationBusy
        && !owner.recoveryWriteBusy && owner.copyPanel == nil && owner.windowForSheet?.attachedSheet == nil
    }
    return true
  }
  func beginPDFSourceEditing() {
    guard canEditSmartObjectContents,canApplyPDFSourceEdit,let layer = activeLayer,let source = layer.smartObject,source.pdfSource != nil else {return}
    if let existing = pdfSourceEditors[source.sourceID] {existing.reopen();return}
    do {
      let editor = try PDFSourceEditWorkspace(store:self,layer:layer,root:pdfSourceEditRoot)
      pdfSourceEditors[source.sourceID] = editor;editor.start()
    } catch {self.error = error.localizedDescription}
  }
  func stopPDFSourceEditing(_ sourceID: UUID) {pdfSourceEditors.removeValue(forKey:sourceID)?.stop()}
  func closePDFSourceEditors() {for editor in pdfSourceEditors.values {editor.stop()};pdfSourceEditors.removeAll()}
  var pdfSourceEditingState: [[String:Any]] {pdfSourceEditors.values.sorted {$0.id.uuidString < $1.id.uuidString}.map(\.apiState)}
}

struct PDFSourceEditControls: View {
  @Bindable var store: EditorStore
  let sourceID: UUID
  var body: some View {
    if let editor = store.pdfSourceEditors[sourceID] {
      Text(editor.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
      Button("Apply Saved PDF") {editor.saved(explicit:true)}.disabled(editor.stage == "opening")
      Button("Show Working PDF") {NSWorkspace.shared.activateFileViewerSelecting([editor.workingURL])}
      Button("Stop Editing") {store.stopPDFSourceEditing(sourceID)}
    } else {
      Button("Show Saved Source Copies") {try? FileManager.default.createDirectory(at:store.pdfSourceEditRoot,withIntermediateDirectories:true);NSWorkspace.shared.open(store.pdfSourceEditRoot)}
        .help("Working PDFs are retained here after closing their parent document.")
    }
  }
}
