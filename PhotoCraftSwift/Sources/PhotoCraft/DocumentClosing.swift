import AppKit
import Observation
import PhotoCraftCore

enum DocumentCloseMode: String, CaseIterable { case review, save, discard }
enum DocumentCloseScope: String, CaseIterable { case document, all, others, window, quit }
enum DocumentClosePhase: String {
  case queued, reviewing, saving, closing, completed, cancelled, failed
  var isActive: Bool {
    switch self {
    case .queued, .reviewing, .saving, .closing: true
    default: false
    }
  }
}
struct DocumentCloseState {
  let id: UUID
  let scope: DocumentCloseScope
  let mode: DocumentCloseMode
  let total: Int
  var closed = 0
  var phase: DocumentClosePhase = .queued
  var cancellationRequested = false
  var error: String?
}
struct DocumentCloseDecision {
  enum Action { case save, discard, cancel }
  let action: Action
  var applyToAll = false
}
enum DocumentCloseFailure: LocalizedError, Equatable {
  case busy, changed, save, unavailable
  var errorDescription: String? {
    switch self {
    case .busy: "Finish the current document operation before closing."
    case .changed: "The documents changed during close review. Remaining documents stay open."
    case .save: "Saving did not complete. Remaining documents stay open."
    case .unavailable: "The requested documents are no longer available."
    }
  }
}

/// One serial operation owns close review across docked, floating and headless
/// documents. Closing is intentionally not atomic: an accepted earlier close
/// stays closed if the user cancels a later document.
@MainActor @Observable final class DocumentCloseCoordinator {
  typealias Reviewer = (CraftNSDocument, Bool) async -> DocumentCloseDecision
  typealias Saver = (CraftNSDocument) async throws -> Bool
  private struct Request {
    let targets: [CraftNSDocument]
    let retained: CraftNSDocument?
    let cancellable: Bool
    let validate: (CraftNSDocument?) throws -> Void
    let save: Saver?
    let completion: (DocumentCloseState) -> Void
  }
  @ObservationIgnored weak var controller: CraftDocumentController?
  private(set) var state: DocumentCloseState?
  @ObservationIgnored private var request: Request?
  @ObservationIgnored private(set) var task: Task<Void, Never>?
  @ObservationIgnored var reviewer: Reviewer?
  @ObservationIgnored var saver: Saver?
  @ObservationIgnored private var prompt: NativeDocumentClosePrompt?
  @ObservationIgnored private var saveRequest: NativeDocumentCloseSave?
  @ObservationIgnored private var savingDocument: CraftNSDocument?
  var isActive: Bool { state?.phase.isActive == true }

  init(controller: CraftDocumentController) { self.controller = controller }
  func canStart(_ targets: [CraftNSDocument]) -> Bool {
    guard let controller, !isActive, !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, controller.documentOpenPanel == nil, !controller.recoveryIndex.isBusy,
      controller.initialRecoveryTask == nil, controller.documentWindows.canChangeDocument
    else { return false }
    return targets.allSatisfy {
      $0.ownerController === controller && $0.canRunFileCommand
        && $0.store.historyOperation == nil && $0.store.duplicateTask == nil
        && $0.closeWorkflowID == nil
    }
  }
  @discardableResult func prepare(
    _ targets: [CraftNSDocument], scope: DocumentCloseScope,
    mode: DocumentCloseMode = .review, retained: CraftNSDocument? = nil,
    commitFields: Bool = true, cancellable: Bool = true,
    validate: @escaping (CraftNSDocument?) throws -> Void = { _ in },
    save: Saver? = nil, completion: @escaping (DocumentCloseState) -> Void = { _ in }
  ) throws -> UUID {
    guard Set(targets.map(ObjectIdentifier.init)).count == targets.count,
      !targets.contains(where: { $0 === retained })
    else { throw DocumentCloseFailure.unavailable }
    guard canStart(targets) else { throw DocumentCloseFailure.busy }
    try validate(nil)
    if commitFields {
      for document in targets {
        document.store.finishNumericField()
        document.store.finishLayerName()
      }
      guard canStart(targets) else { throw DocumentCloseFailure.busy }
    }
    let id = UUID()
    for document in targets { document.closeWorkflowID = id }
    state = .init(id: id, scope: scope, mode: mode, total: targets.count)
    request = .init(targets: targets, retained: retained, cancellable: cancellable, validate: validate,
      save: save, completion: completion)
    return id
  }
  func start(_ id: UUID) {
    guard state?.id == id, state?.phase == .queued, task == nil, let request else { return }
    task = Task { [weak self] in
      guard let self else { return }
      await run(request, id: id)
    }
  }
  func cancel(_ id: UUID) {
    guard state?.id == id, isActive else { return }
    state?.cancellationRequested = true
    if state?.phase == .queued, task == nil { finish(.cancelled); return }
    prompt?.cancel()
    savingDocument?.closeSavePanel?.cancel(nil)
    // A coordinated write already in progress finishes before cancellation is
    // reported. Its saved file is not rolled back; later documents stay open.
  }
  private func check(_ document: CraftNSDocument?, request: Request, id: UUID) throws {
    guard state?.id == id, state?.cancellationRequested == false else { throw CancellationError() }
    try request.validate(document)
    if let document {
      guard document.ownerController === controller, document.closeWorkflowID == id,
        document.canRunFileCommand, document.store.historyOperation == nil
      else { throw DocumentCloseFailure.changed }
    }
  }
  private func run(_ request: Request, id: UUID) async {
    var allDecision: DocumentCloseDecision.Action?
    do {
      for (position, document) in request.targets.enumerated() {
        try check(document, request: request, id: id)
        if document.isDocumentEdited {
          let snapshot = document.store.document
          let generation = document.store.layerPanelGeneration
          let decision: DocumentCloseDecision
          switch state?.mode {
          case .discard: decision = .init(action: .discard)
          case .save: decision = .init(action: .save)
          default:
            if let allDecision { decision = .init(action: allDecision) }
            else {
              state?.phase = .reviewing
              document.makeWindowControllers()
              document.showWindows()
              let remaining = request.targets.dropFirst(position + 1).contains { $0.isDocumentEdited }
              if let reviewer { decision = await reviewer(document, remaining) }
              else {
                let prompt = NativeDocumentClosePrompt()
                self.prompt = prompt
                decision = await prompt.review(document, allowsApplyToAll: remaining,
                  cancellable: request.cancellable)
                self.prompt = nil
              }
              if decision.applyToAll, decision.action != .cancel { allDecision = decision.action }
            }
          }
          if decision.action == .cancel { throw CancellationError() }
          try check(document, request: request, id: id)
          guard document.store.document == snapshot,
            document.store.layerPanelGeneration == generation else { throw DocumentCloseFailure.changed }
          if decision.action == .save {
            state?.phase = .saving
            let saved: Bool
            if let save = request.save ?? saver { saved = try await save(document) }
            else { saved = await saveNative(document) }
            try check(document, request: request, id: id)
            guard saved else { throw CancellationError() }
            guard !document.isDocumentEdited else { throw DocumentCloseFailure.save }
          }
        }
        try check(document, request: request, id: id)
        state?.phase = .closing
        document.close()
        guard document.ownerController == nil else { throw DocumentCloseFailure.changed }
        state?.closed += 1
      }
      try check(nil, request: request, id: id)
      if state?.scope == .quit, controller?.documents.isEmpty == false {
        throw DocumentCloseFailure.changed
      }
      finish(.completed)
    } catch is CancellationError {
      finish(.cancelled)
    } catch {
      finish(.failed, error: (error as? DocumentCloseFailure)?.localizedDescription
        ?? "Closing stopped. Remaining documents stay open.")
    }
  }
  private func saveNative(_ document: CraftNSDocument) async -> Bool {
    if document.smartObjectEditLink != nil {
      do { try await document.commitSmartObjectContents(); return true }
      catch { document.store.error = error.localizedDescription; return false }
    }
    savingDocument = document
    defer { savingDocument = nil; saveRequest = nil; document.closeSavePanel = nil }
    return await withCheckedContinuation { continuation in
      let request = NativeDocumentCloseSave { continuation.resume(returning: $0) }
      saveRequest = request
      let selector = #selector(NativeDocumentCloseSave.document(_:didSave:contextInfo:))
      if document.sourceSaveNeedsReview {
        document.runModalSavePanel(for: .saveAsOperation, delegate: request,
          didSave: selector, contextInfo: nil)
      } else {
        document.save(withDelegate: request, didSave: selector, contextInfo: nil)
      }
    }
  }
  private func finish(_ phase: DocumentClosePhase, error: String? = nil) {
    guard let request, let id = state?.id else { return }
    state?.phase = phase
    state?.error = error
    for document in request.targets where document.closeWorkflowID == id {
      document.closeWorkflowID = nil
      if document.ownerController != nil { document.scheduleAutosaving() }
    }
    if let retained = request.retained, retained.ownerController === controller {
      retained.showWindows()
    }
    self.request = nil
    task = nil
    if let state { request.completion(state) }
  }
}

@MainActor final class NativeDocumentClosePrompt {
  private var alert: NSAlert?
  func review(_ document: CraftNSDocument, allowsApplyToAll: Bool,
    cancellable: Bool = true) async -> DocumentCloseDecision
  {
    guard let window = document.windowForSheet else { return .init(action: .cancel) }
    let alert = NSAlert()
    self.alert = alert
    alert.messageText = "Save changes to “\(document.displayName ?? "Untitled")” before closing?"
    alert.informativeText = "Your changes will be lost if you don’t save them."
    alert.addButton(withTitle: "Save")
    let discard = alert.addButton(withTitle: "Don’t Save")
    discard.keyEquivalent = "d"
    discard.keyEquivalentModifierMask = [.command]
    if cancellable { alert.addButton(withTitle: "Cancel") }
    alert.showsSuppressionButton = allowsApplyToAll
    alert.suppressionButton?.title = "Apply to All"
    let response = await withCheckedContinuation { continuation in
      alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
    }
    self.alert = nil
    let action: DocumentCloseDecision.Action = response == .alertFirstButtonReturn ? .save
      : response == .alertSecondButtonReturn ? .discard : .cancel
    return .init(action: action, applyToAll: alert.suppressionButton?.state == .on)
  }
  func cancel() {
    guard let alert, let parent = alert.window.sheetParent else { return }
    parent.endSheet(alert.window, returnCode: .alertThirdButtonReturn)
  }
}

@MainActor private final class NativeDocumentCloseSave: NSObject {
  private var completion: ((Bool) -> Void)?
  init(_ completion: @escaping (Bool) -> Void) { self.completion = completion }
  @objc func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
    let callback = completion
    completion = nil
    callback?(didSave)
  }
}
