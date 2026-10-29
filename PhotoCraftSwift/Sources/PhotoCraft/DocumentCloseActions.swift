import AppKit

@MainActor extension CraftDocumentController {
  func closeTargets(excluding retained: CraftNSDocument? = nil) -> [CraftNSDocument] {
    let current = (currentDocument as? CraftNSDocument).map { [$0] } ?? []
    var seen: Set<ObjectIdentifier> = []
    return (current + documentWindows.groups.flatMap { $0.workspace.documents }
      + documents.compactMap { $0 as? CraftNSDocument }).filter {
        $0 !== retained && $0.ownerController === self && seen.insert(ObjectIdentifier($0)).inserted
      }
  }
  func requestDocumentClose(_ documents: [CraftNSDocument], scope: DocumentCloseScope,
    retained: CraftNSDocument? = nil, cancellable: Bool = true,
    completion: @escaping (DocumentCloseState?) -> Void = { _ in })
  {
    do {
      let id = try documentClosing.prepare(documents, scope: scope, retained: retained,
        cancellable: cancellable, completion: { completion($0) })
      documentClosing.start(id)
    } catch {
      (currentDocument as? CraftNSDocument)?.store.status = error.localizedDescription
      completion(nil)
    }
  }
}

@MainActor extension AppDelegate {
  @objc func closeAllDocuments() {
    controller.requestDocumentClose(controller.closeTargets(), scope: .all)
  }
  @objc func closeOtherDocuments() {
    guard let retained = controller.currentDocument as? CraftNSDocument else { return }
    controller.requestDocumentClose(controller.closeTargets(excluding: retained),
      scope: .others, retained: retained)
  }
  func validateDocumentClosingMenu(_ item: NSMenuItem) -> Bool? {
    switch item.action {
    case #selector(closeAllDocuments):
      let targets = controller.closeTargets()
      return !targets.isEmpty && controller.documentClosing.canStart(targets)
    case #selector(closeOtherDocuments):
      guard let retained = controller.currentDocument as? CraftNSDocument else { return false }
      let targets = controller.closeTargets(excluding: retained)
      return !targets.isEmpty && controller.documentClosing.canStart(targets)
    case #selector(quit):
      return controller.documentClosing.canStart(controller.closeTargets())
    case #selector(openFile):
      return controller.documentOpenPanel == nil && controller.documentOpening.canStart
    case #selector(newFile), #selector(newFromClipboard):
      return controller.documentClosing.isActive ? false : nil
    default: return nil
    }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // NSApplication has already asked the document controller to review unsaved
    // documents. A remaining operation or new document must not be abandoned.
    guard !controller.documentClosing.isActive, !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, controller.documentOpenPanel == nil,
      !controller.recoveryIndex.isBusy, controller.initialRecoveryTask == nil,
      controller.closeTargets().allSatisfy({
        !$0.isDocumentEdited && $0.canRunFileCommand && $0.store.historyOperation == nil
      })
    else { return .terminateCancel }
    return .terminateNow
  }
}

/// Public NSDocumentController delegate callbacks have arbitrary selector names
/// but this fixed Objective-C signature. Preserve the caller's context pointer.
@MainActor final class NativeDocumentControllerCloseReply {
  let delegate: NSObject?
  let selector: Selector?
  let context: UnsafeMutableRawPointer?
  init(_ delegate: Any?, selector: Selector?, context: UnsafeMutableRawPointer?) {
    self.delegate = delegate as? NSObject
    self.selector = selector
    self.context = context
  }
  func deliver(_ controller: CraftDocumentController, completed: Bool) {
    guard let delegate, let selector, delegate.responds(to: selector),
      let implementation = delegate.method(for: selector) else { return }
    typealias Callback = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
    let callback = unsafeBitCast(implementation, to: Callback.self)
    callback(delegate, selector, controller, completed, context)
  }
}
