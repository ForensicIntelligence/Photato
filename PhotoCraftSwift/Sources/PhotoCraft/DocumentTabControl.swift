import AppKit
import SwiftUI

/// AppKit owns pointer tracking so a tab click and a tab drag cannot compete for the same gesture.
struct DocumentTabControl: NSViewRepresentable {
  let title: String
  let document: CraftNSDocument
  let workspace: DocumentWorkspace
  let selected: Bool

  func makeNSView(context: Context) -> DocumentTabButton { DocumentTabButton() }
  func updateNSView(_ button: DocumentTabButton, context: Context) {
    button.title = title
    button.documentID = document.store.identity.uuidString
    button.font = .systemFont(ofSize: 10, weight: selected ? .semibold : .regular)
    button.setAccessibilityLabel(
      "Select document \(document.displayName ?? document.store.document.name)")
    button.setAccessibilityValue(selected ? "Selected" : "")
    button.selectTab = { workspace.select(document) }
    button.acceptsTab = { id in workspace.owner?.canMoveTab(id, to: document) == true }
    button.moveTab = { id, after in
      workspace.owner?.moveTab(id, relativeTo: document, after: after) == true
    }
    button.invalidateIntrinsicContentSize()
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: DocumentTabButton, context: Context)
    -> CGSize?
  {
    CGSize(width: ceil(nsView.attributedTitle.size().width) + 4, height: 26)
  }
}

@MainActor final class DocumentTabButton: NSButton, NSDraggingSource {
  static let pasteboardType = NSPasteboard.PasteboardType("local.photato.document-tab")
  var documentID = ""
  var selectTab: () -> Void = {}
  var acceptsTab: (String) -> Bool = { _ in false }
  var moveTab: (String, Bool) -> Bool = { _, _ in false }
  private var pressOrigin: NSPoint?
  private var insertionAfter: Bool?

  init() {
    super.init(frame: .zero)
    isBordered = false
    alignment = .left
    lineBreakMode = .byTruncatingTail
    contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
    target = self
    action = #selector(selectDocument)
    registerForDraggedTypes([Self.pasteboardType])
  }
  required init?(coder: NSCoder) { nil }
  @objc private func selectDocument() { selectTab() }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) { pressOrigin = event.locationInWindow }
  override func mouseUp(with event: NSEvent) {
    defer { pressOrigin = nil }
    guard pressOrigin != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else {
      return
    }
    performClick(nil)
  }
  override func mouseDragged(with event: NSEvent) {
    guard let origin = pressOrigin,
      hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 4
    else { return }
    pressOrigin = nil
    let pasteboard = NSPasteboardItem()
    pasteboard.setString(documentID, forType: Self.pasteboardType)
    let item = NSDraggingItem(pasteboardWriter: pasteboard)
    let preview = NSImage(size: bounds.size)
    preview.lockFocus()
    NSColor(calibratedWhite: 0.32, alpha: 0.95).setFill()
    bounds.fill()
    attributedTitle.draw(
      at: NSPoint(x: 2, y: max(0, (bounds.height - attributedTitle.size().height) / 2)))
    preview.unlockFocus()
    item.setDraggingFrame(bounds, contents: preview)
    beginDraggingSession(with: [item], event: event, source: self)
  }
  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  )
    -> NSDragOperation
  { context == .withinApplication ? .move : [] }
  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

  func payload(from pasteboard: NSPasteboard) -> String? {
    guard let id = pasteboard.string(forType: Self.pasteboardType), acceptsTab(id) else {
      return nil
    }
    return id
  }
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard payload(from: sender.draggingPasteboard) != nil else {
      insertionAfter = nil
      needsDisplay = true
      return []
    }
    insertionAfter = convert(sender.draggingLocation, from: nil).x >= bounds.midX
    needsDisplay = true
    return .move
  }
  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    insertionAfter = nil
    needsDisplay = true
  }
  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    payload(from: sender.draggingPasteboard) != nil
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    defer {
      insertionAfter = nil
      needsDisplay = true
    }
    guard let id = payload(from: sender.draggingPasteboard) else { return false }
    return moveTab(id, convert(sender.draggingLocation, from: nil).x >= bounds.midX)
  }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if let insertionAfter {
      NSColor.controlAccentColor.setFill()
      NSRect(
        x: insertionAfter ? bounds.maxX - 2 : bounds.minX, y: 1, width: 2,
        height: max(0, bounds.height - 2)
      ).fill()
    }
  }
}
