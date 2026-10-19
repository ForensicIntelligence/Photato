import AppKit
import SwiftUI

struct PanelDockPayload: Codable, Equatable {
  let library: UUID
  let source: PanelDockSource
  static let type = NSPasteboard.PasteboardType("local.photato.panel-dock")

  func write(to pasteboard: NSPasteboardItem) {
    if let data = try? JSONEncoder().encode(self) { pasteboard.setData(data, forType: Self.type) }
  }
  static func read(_ pasteboard: NSPasteboard) -> PanelDockPayload? {
    guard let data = pasteboard.data(forType: type), data.count <= 2048 else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }
}

@MainActor extension WorkspaceLibrary {
  func acceptsPanelPayload(_ payload: PanelDockPayload) -> Bool {
    guard payload.library == identity, !workspaceLocked,
      let panels = panelDock.panels(for: payload.source)
    else { return false }
    return panels.contains { !panelDock.hidden.contains($0) && $0.isVisible(in: layout.visibility) }
  }
}

struct PanelDockTab: NSViewRepresentable {
  let library: WorkspaceLibrary
  let group: PanelDockGroup
  let panel: WorkspacePanel?
  let selected: Bool
  let canOrganize: Bool
  var tearOff: PanelTearOffCoordinator? = nil
  var icon: String? = nil
  var showsLabel = true
  var selectOverride: (() -> Void)? = nil

  func makeNSView(context: Context) -> PanelDockTabButton { PanelDockTabButton() }
  func updateNSView(_ button: PanelDockTabButton, context: Context) {
    button.tearOff = tearOff
    button.title = panel?.rawValue ?? ""
    button.image = icon.flatMap {
      NSImage(systemSymbolName: $0, accessibilityDescription: panel?.rawValue)
    }
    button.imagePosition = icon == nil ? .noImage : showsLabel ? .imageLeading : .imageOnly
    button.font = .systemFont(ofSize: 10, weight: selected ? .semibold : .regular)
    button.setAccessibilityLabel(panel.map { "\($0.rawValue) panel" } ?? "Move panel group")
    button.setAccessibilityValue(selected ? "Selected" : "")
    button.toolTip = panel?.rawValue ?? "Drag to move this panel group"
    button.payloadValue = .init(
      library: library.identity, source: panel.map(PanelDockSource.panel) ?? .group(group.id))
    button.canDrag = {
      canOrganize && !library.workspaceLocked && tearOff?.owner?.canChangeDocument != false
    }
    button.select = selectOverride ?? { if let panel { library.selectPanel(panel) } }
    button.collapse = { library.togglePanelGroup(group.id) }
    button.accepts = {
      canOrganize && library.acceptsPanelPayload($0)
        && (tearOff == nil || tearOff?.accepts($0) == true)
    }
    button.drop = { payload, after in
      guard canOrganize, library.acceptsPanelPayload(payload),
        let current = library.panelDock.groups.first(where: { $0.id == group.id })
      else { return false }
      let before: WorkspacePanel?
      if let panel, let index = current.panels.firstIndex(of: panel) {
        before =
          after ? (index + 1 < current.panels.count ? current.panels[index + 1] : nil) : panel
      } else {
        before = nil
      }
      return library.movePanels(payload.source, to: .group(group.id, before: before))
    }
    button.invalidateIntrinsicContentSize()
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: PanelDockTabButton, context: Context)
    -> CGSize?
  {
    if icon != nil {
      return CGSize(
        width: showsLabel ? ceil(nsView.attributedTitle.size().width) + 34 : 34, height: 29)
    }
    return CGSize(
      width: panel == nil
        ? max(20, proposal.width ?? 20) : ceil(nsView.attributedTitle.size().width) + 16, height: 29
    )
  }
}

@MainActor final class PanelDockTabButton: NSButton, NSDraggingSource {
  var payloadValue: PanelDockPayload?
  weak var tearOff: PanelTearOffCoordinator?
  var dragModifiers: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
  var canDrag: () -> Bool = { false }
  var select: () -> Void = {}
  var collapse: () -> Void = {}
  var accepts: (PanelDockPayload) -> Bool = { _ in false }
  var drop: (PanelDockPayload, Bool) -> Bool = { _, _ in false }
  private var pressOrigin: NSPoint?
  private var insertionAfter: Bool?

  init() {
    super.init(frame: .zero)
    isBordered = false
    contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
    target = self
    action = #selector(selectPanel)
    registerForDraggedTypes([PanelDockPayload.type])
  }
  required init?(coder: NSCoder) { nil }
  @objc private func selectPanel() { select() }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { pressOrigin = event.locationInWindow }
  override func mouseUp(with event: NSEvent) {
    defer { pressOrigin = nil }
    guard pressOrigin != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else {
      return
    }
    if event.clickCount == 2 { collapse() } else { performClick(nil) }
  }
  override func mouseDragged(with event: NSEvent) {
    guard canDrag(), let origin = pressOrigin, let payloadValue,
      hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 4
    else { return }
    let anchor = convert(origin, from: nil)
    if let tearOff,
      !tearOff.begin(payloadValue, anchor: NSPoint(x: anchor.x, y: bounds.maxY - anchor.y + 22))
    {
      pressOrigin = nil
      return
    }
    pressOrigin = nil
    let pasteboard = NSPasteboardItem()
    payloadValue.write(to: pasteboard)
    let item = NSDraggingItem(pasteboardWriter: pasteboard)
    let preview = NSImage(size: bounds.size)
    preview.lockFocus()
    NSColor(calibratedWhite: 0.32, alpha: 0.95).setFill()
    bounds.fill()
    attributedTitle.draw(at: NSPoint(x: 8, y: 8))
    preview.unlockFocus()
    item.setDraggingFrame(bounds, contents: preview)
    beginDraggingSession(with: [item], event: event, source: self)
  }
  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication && canDrag() ? .move : []
  }
  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    // Both cancellation and unsupported drops end here; neither changes the layout.
    tearOff?.finish()
  }
  func payload(from pasteboard: NSPasteboard) -> PanelDockPayload? {
    guard let payload = PanelDockPayload.read(pasteboard), accepts(payload) else { return nil }
    return payload
  }
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard let payload = payload(from: sender.draggingPasteboard) else {
      insertionAfter = nil
      needsDisplay = true
      return []
    }
    if dragModifiers().contains(.command) {
      insertionAfter = nil
      needsDisplay = true
      return tearOff?.accepts(payload) == true ? .move : []
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
    guard let payload = payload(from: sender.draggingPasteboard) else { return false }
    return !dragModifiers().contains(.command) || tearOff?.accepts(payload) == true
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    defer {
      insertionAfter = nil
      needsDisplay = true
    }
    guard let payload = payload(from: sender.draggingPasteboard) else { return false }
    if dragModifiers().contains(.command) {
      guard let window else { return false }
      return tearOff?.drop(payload, at: window.convertPoint(toScreen: sender.draggingLocation))
        ?? false
    }
    let committed = drop(payload, convert(sender.draggingLocation, from: nil).x >= bounds.midX)
    if committed { tearOff?.didCommitDrop() }
    return committed
  }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if let insertionAfter {
      NSColor.controlAccentColor.setFill()
      NSRect(x: insertionAfter ? bounds.maxX - 2 : 0, y: 0, width: 2, height: bounds.height).fill()
    }
  }
}

struct PanelDockDropZone: NSViewRepresentable {
  let library: WorkspaceLibrary
  let before: String?
  let canOrganize: Bool
  var tearOff: PanelTearOffCoordinator? = nil
  var floatingHostID: String? = nil
  var destination: PanelDockDestination? = nil
  var horizontalResize = false
  var accessibilityName: String? = nil
  var beginResize: (() -> Void)?
  var resize: ((CGFloat) -> Void)?
  var endResize: (() -> Void)?
  func makeNSView(context: Context) -> PanelDockDropView { PanelDockDropView() }
  func updateNSView(_ view: PanelDockDropView, context: Context) {
    view.tearOff = tearOff
    view.horizontalResize = horizontalResize
    view.setAccessibilityLabel(accessibilityName)
    view.beginResize = beginResize
    view.resize = resize
    view.endResize = endResize
    view.window?.invalidateCursorRects(for: view)
    view.accepts = {
      canOrganize && library.acceptsPanelPayload($0)
        && (tearOff == nil || tearOff?.accepts($0) == true)
    }
    view.drop = { payload in
      guard canOrganize, library.acceptsPanelPayload(payload) else { return false }
      if let floatingHostID {
        return library.stackPanels(payload.source, hostID: floatingHostID, before: before)
      }
      return library.movePanels(payload.source, to: destination ?? .beforeGroup(before))
    }
  }
}

@MainActor final class PanelDockDropView: NSView {
  weak var tearOff: PanelTearOffCoordinator?
  var dragModifiers: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
  var accepts: (PanelDockPayload) -> Bool = { _ in false }
  var drop: (PanelDockPayload) -> Bool = { _ in false }
  var highlighted = false { didSet { needsDisplay = true } }
  var beginResize: (() -> Void)?
  var resize: ((CGFloat) -> Void)?
  var endResize: (() -> Void)?
  var horizontalResize = false
  private var resizeOrigin: CGFloat?
  init() {
    super.init(frame: .zero)
    registerForDraggedTypes([PanelDockPayload.type])
  }
  required init?(coder: NSCoder) { nil }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func resetCursorRects() {
    if resize != nil {
      addCursorRect(bounds, cursor: horizontalResize ? .resizeLeftRight : .resizeUpDown)
    }
  }
  override func mouseDown(with event: NSEvent) {
    guard resize != nil else { return }
    resizeOrigin = horizontalResize ? event.locationInWindow.x : event.locationInWindow.y
    beginResize?()
  }
  override func mouseDragged(with event: NSEvent) {
    guard let resizeOrigin else { return }
    resize?(
      horizontalResize
        ? event.locationInWindow.x - resizeOrigin : resizeOrigin - event.locationInWindow.y)
  }
  override func mouseUp(with event: NSEvent) {
    if resizeOrigin != nil {
      mouseDragged(with: event)
      endResize?()
    }
    resizeOrigin = nil
  }
  func payload(from pasteboard: NSPasteboard) -> PanelDockPayload? {
    guard let payload = PanelDockPayload.read(pasteboard), accepts(payload) else { return nil }
    return payload
  }
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    let payload = payload(from: sender.draggingPasteboard)
    if dragModifiers().contains(.command) {
      highlighted = false
      return payload.map { tearOff?.accepts($0) == true } == true ? .move : []
    }
    highlighted = payload != nil
    return highlighted ? .move : []
  }
  override func draggingExited(_ sender: (any NSDraggingInfo)?) { highlighted = false }
  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let payload = payload(from: sender.draggingPasteboard) else { return false }
    return !dragModifiers().contains(.command) || tearOff?.accepts(payload) == true
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    defer { highlighted = false }
    guard let payload = payload(from: sender.draggingPasteboard) else { return false }
    if dragModifiers().contains(.command) {
      guard let window else { return false }
      return tearOff?.drop(payload, at: window.convertPoint(toScreen: sender.draggingLocation))
        ?? false
    }
    let committed = drop(payload)
    if committed { tearOff?.didCommitDrop() }
    return committed
  }
  override func draw(_ dirtyRect: NSRect) {
    if highlighted {
      NSColor.controlAccentColor.setFill()
      bounds.fill()
    }
  }
}
