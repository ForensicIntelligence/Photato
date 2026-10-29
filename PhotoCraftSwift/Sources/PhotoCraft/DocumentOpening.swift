import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct PreparedLocalDocument: Sendable {
  let model: CraftDocument
  let format: DocumentIO.Format?
  let fingerprint: RecoverySourceFingerprint?
  let modificationDate: Date?
  var colorPolicyChanged = false
  static func read(_ url: URL, format selection: DocumentOpenFormat) throws -> Self {
    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      try Task.checkCancellation()
      try selection.validate(PcraftImport.recognizes(url) ? .pcraft : nil)
      // PcraftDirectory checks each opened member and directory identity before
      // publication. Imported projects never become writable source associations.
      let model = try PcraftImport.read(url)
      return .init(model: model, format: nil, fingerprint: nil, modificationDate: nil)
    }
    return try RecoverySourceReader.withStableMetadata {
      try Task.checkCancellation()
      let reader = try RecoverySourceReader(url)
      let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      let actual = DocumentOpenFormat.detect(url)
      try selection.validate(actual)
      var model = try DocumentIO.read(url)
      if [.psd, .psb].contains(actual), model.sourceICC == nil { model.profileIsUntagged = true }
      let fingerprint = try reader.finish()
      return .init(model: model, format: actual?.persistenceFormat,
        fingerprint: fingerprint, modificationDate: date)
    }
  }
  @MainActor func makeDocument(url: URL) -> CraftNSDocument {
    let doc = CraftNSDocument(model: model)
    doc.openRawDevelopmentOnDisplay = format == nil && model.layers.first?.smartObject?.rawDevelopment != nil
    doc.fileType = (format ?? .native).typeIdentifier
    if let format {
      doc.fileURL = url
      doc.sourceSaveNeedsReview = format != .native && (colorPolicyChanged || CraftNSDocument.formatNeedsReview(model, format: format))
      if let fingerprint {
        doc.recoverySourceRecord = .make(url: url, format: format,
          needsReview: doc.sourceSaveNeedsReview, fingerprint: fingerprint)
      }
      // Retain the date of the read snapshot, not a later external modification.
      doc.fileModificationDate = modificationDate
    } else { doc.importedSourceURL = url.standardizedFileURL.resolvingSymlinksInPath() }
    if colorPolicyChanged { doc.updateChangeCount(.changeDone) }
    return doc
  }
}

@MainActor @Observable final class DocumentOpening {
  struct State {
    let id: UUID
    let total: Int
    let format: DocumentOpenFormat
    var opened = 0
    var alreadyOpen = 0
    var failed = 0
    var active = true
    var cancellationRequested = false
    var lastError: String?
  }
  typealias Reader = @Sendable (URL, DocumentOpenFormat) throws -> PreparedLocalDocument
  @ObservationIgnored weak var controller: CraftDocumentController?
  private(set) var state: State?
  @ObservationIgnored private(set) var task: Task<Void, Never>?
  @ObservationIgnored private var worker: Task<PreparedLocalDocument, Error>?
  @ObservationIgnored var reader: Reader = PreparedLocalDocument.read
  @ObservationIgnored var colorPolicyReviewer: ColorPolicyReviewer = ColorPolicyDialog.present
  @ObservationIgnored var progress: NSWindowController?
  var pdfWorkspace: PDFImportWorkspace?
  @ObservationIgnored var pdfWindow: PDFImportWindow?
  @ObservationIgnored var pdfPresenter: (@MainActor (PDFImportWorkspace) -> Void)?
  @ObservationIgnored private var pending: [Request] = []
  @ObservationIgnored private var queueTask: Task<Void, Never>?
  private(set) var queuedCount = 0
  private(set) var generation = UUID()
  var hasPendingRequests: Bool { queuedCount > 0 || queueTask != nil }
  private struct Request {
    let url: URL
    let display: Bool
    let recentID: UUID?
    let completion: (NSDocument?, Bool, Error?) -> Void
  }
  var isActive: Bool { state?.active == true }
  init(controller: CraftDocumentController) { self.controller = controller }
  var canStart: Bool {
    guard let controller else { return false }
    return !isActive && !hasPendingRequests && controller.documentOpenPanel == nil && !controller.documentClosing.isActive
      && !controller.recoveryIndex.isBusy && controller.initialRecoveryTask == nil
      && NSApp?.modalWindow == nil && controller.documentWindows.canChangeDocument
  }
  @discardableResult func begin(_ urls: [URL], format: DocumentOpenFormat = .automatic,
    display: Bool, showProgress: Bool = false, recentID: UUID? = nil,
    validate: @escaping () throws -> Void = {},
    completion: @escaping (NSDocument?, Bool, Error?) -> Void = { _, _, _ in },
    finished: @escaping (State) -> Void = { _ in }) throws -> UUID
  {
    try beginRequests(urls.map { Request(url: $0, display: display, recentID: recentID, completion: completion) },
      format: format, showProgress: showProgress, validate: validate, finished: finished)
  }
  private func beginRequests(_ requests: [Request], format: DocumentOpenFormat,
    showProgress: Bool, validate: @escaping () throws -> Void,
    finished: @escaping (State) -> Void) throws -> UUID
  {
    guard canStart else { throw CraftError.invalid("Finish the current opening, closing or recovery operation.") }
    guard !requests.isEmpty, requests.allSatisfy({ $0.url.isFileURL }) else { throw CraftError.invalid("Choose local document files.") }
    try validate()
    let id = UUID()
    generation = UUID()
    state = .init(id: id, total: requests.count, format: format)
    if showProgress { progress = DocumentOpeningProgress(opening: self); progress?.showWindow(nil) }
    let colorSettings = controller!.colorSettings.value
    task = Task { [weak self] in
      guard let self, let controller else { return }
      defer {
        worker = nil; state?.active = false; progress?.close(); progress = nil; task = nil
        if let state { finished(state) }
        scheduleQueue()
      }
      for (index, request) in requests.enumerated() {
        let url = request.url, display = request.display, completion = request.completion
        do {
          try Task.checkCancellation()
          try validate()
          if let doc = controller.document(for: url) {
            try format.validate(DocumentOpenFormat.detect(url))
            if display { doc.showWindows() }
            state?.alreadyOpen += 1
            controller.recoveryPreferences.remember(url, replacing: request.recentID)
            completion(doc, true, nil)
            continue
          }
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          if DocumentOpenFormat.detect(url) == .pdf {
            try format.validate(.pdf)
            progress?.window?.orderOut(nil)
            defer {if index+1 < requests.count,!Task.isCancelled {progress?.showWindow(nil)}}
            let models = try await importPDF(url)
            try Task.checkCancellation();try validate()
            guard !controller.documentClosing.isActive,!controller.recoveryIndex.isBusy,
              !models.isEmpty else {throw CraftError.invalid("Document lifecycle changed during PDF import.")}
            // A PDF can produce several documents. None is associated with the
            // source for Save/Revert; opening it again offers the chooser again.
            let documents = models.map {CraftNSDocument(model:$0)}
            for document in documents {controller.addDocument(document);document.updateChangeCount(.changeDone)}
            if display {for document in documents {document.makeWindowControllers();document.showWindows()}}
            state?.opened += 1
            controller.recoveryPreferences.remember(url,replacing:request.recentID)
            completion(documents.first,false,nil)
            continue
          }
          let reader = self.reader
          let job = Task.detached(priority: .userInitiated) { try reader(url, format) }
          worker = job
          var prepared = try await withTaskCancellationHandler(
            operation: { try await job.value }, onCancel: { job.cancel() })
          worker = nil
          if prepared.format != .native {
            let assessment = try ColorPolicyInput.openingAssessment(prepared.model, settings: colorSettings)
            let choice = assessment.requiresReview
              ? try await colorPolicyReviewer(assessment, prepared.model.colorMode, prepared.model.depth) : nil
            try Task.checkCancellation()
            let snapshot = prepared
            let conversion = Task.detached(priority: .userInitiated) {
              let model = try ColorPolicyInput.opening(snapshot.model, settings: colorSettings, choice: choice)
              return PreparedLocalDocument(model: model, format: snapshot.format, fingerprint: snapshot.fingerprint,
                modificationDate: snapshot.modificationDate, colorPolicyChanged: model != snapshot.model)
            }
            worker = conversion
            prepared = try await withTaskCancellationHandler { try await conversion.value } onCancel: { conversion.cancel() }
            worker = nil
          }
          try Task.checkCancellation()
          try validate()
          guard !controller.documentClosing.isActive, !controller.recoveryIndex.isBusy else {
            throw CraftError.invalid("Document lifecycle changed while opening.")
          }
          // Another path may have opened this exact source during decoding.
          if let doc = controller.document(for: url) {
            if display { doc.showWindows() }
            state?.alreadyOpen += 1
            controller.recoveryPreferences.remember(url, replacing: request.recentID)
            completion(doc, true, nil)
          } else {
            let doc = prepared.makeDocument(url: url)
            controller.addDocument(doc)
            if display { doc.makeWindowControllers(); doc.showWindows() }
            state?.opened += 1
            controller.recoveryPreferences.remember(url, replacing: request.recentID)
            completion(doc, false, nil)
          }
        } catch is CancellationError {
          // Every SDK request owns a callback, including files not read yet.
          for remaining in requests[index...] {
            remaining.completion(nil, false, CocoaError(.userCancelled))
          }
          break
        } catch {
          state?.failed += 1
          state?.lastError = "A document could not be opened. Use File > Open to review the file."
          completion(nil, false, error)
        }
      }
    }
    return id
  }
  func enqueue(_ url: URL, display: Bool, completion: @escaping (NSDocument?, Bool, Error?) -> Void) {
    guard let controller, url.isFileURL, !controller.documentClosing.isActive,
      controller.documentOpenPanel == nil, pending.count < 1000 else {
      completion(nil, false, CraftError.invalid("Document opening is unavailable or its queue is full."))
      return
    }
    pending.append(Request(url: url, display: display, recentID: nil, completion: completion))
    queuedCount = pending.count; generation = UUID()
    scheduleQueue()
  }
  private func scheduleQueue() {
    guard !isActive, queueTask == nil, !pending.isEmpty else { return }
    queueTask = Task { [weak self] in
      await Task.yield()
      guard let self else { return }
      if let controller {
        if !controller.initialRecoveryFinished { controller.startIndexedRecovery() }
        await controller.initialRecoveryTask?.value
        await controller.recoveryDiscovery.waitUntilIdle()
      }
      let batch = pending
      pending = []; queuedCount = 0; queueTask = nil
      do {
        _ = try beginRequests(batch, format: .automatic, showProgress: batch.contains(where: \.display),
          validate: {}, finished: { _ in })
      } catch {
        for request in batch { request.completion(nil, false, error) }
        scheduleQueue()
      }
    }
  }
  func waitUntilIdle() async {
    while let current = queueTask ?? task { await current.value }
  }
  func cancel(_ id: UUID) {
    guard state?.id == id, isActive else { return }
    state?.cancellationRequested = true
    task?.cancel(); worker?.cancel();pdfWorkspace?.cancel()
  }
}

@MainActor final class DocumentOpeningProgress: NSWindowController {
  weak var opening: DocumentOpening?
  init(opening: DocumentOpening) {
    self.opening = opening
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 350, height: 110),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Opening Documents"; window.isReleasedWhenClosed = false
    super.init(window: window)
    let spinner = NSProgressIndicator()
    spinner.style = .spinning; spinner.startAnimation(nil)
    let label = NSTextField(labelWithString: "Reading document data…")
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelOpening))
    cancel.keyEquivalent = "\u{1b}"
    let stack = NSStackView(views: [spinner, label, cancel]); stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView?.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
    ])
    window.center()
  }
  required init?(coder: NSCoder) { nil }
  @objc func cancelOpening() { if let opening, let id = opening.state?.id { opening.cancel(id) } }
}
