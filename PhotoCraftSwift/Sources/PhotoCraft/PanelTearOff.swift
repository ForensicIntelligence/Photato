import AppKit
import Observation

/// Floating is a committed native drop, never an interpretation of an unsuccessful drag.
@MainActor @Observable final class PanelTearOffCoordinator: NSObject {
  private struct Context {
    let id = UUID()
    let payload: PanelDockPayload
    let document: CraftNSDocument
    let library: WorkspaceLibrary
    let layout: WorkspaceLayout
    let workspaceName: String
    let size: NSSize
    let anchor: NSPoint
  }
  weak var owner: DocumentWindows?
  private var context: Context?
  private(set) var backdrops: [NSWindow] = []
  var presentsBackdrops = true
  var screenFrames: () -> [NSRect] = { NSScreen.screens.map(\.frame) }
  var activePayload: PanelDockPayload? { context?.payload }

  init(owner: DocumentWindows) {
    self.owner = owner
    super.init()
    for name in [
      NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification,
      NSApplication.didChangeScreenParametersNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(applicationChanged), name: name, object: nil)
    }
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc private func applicationChanged(_ notification: Notification) { finish() }

  @discardableResult func begin(_ payload: PanelDockPayload, anchor: NSPoint) -> Bool {
    finish()
    guard let owner, owner.canChangeDocument, let document = owner.activeDocument,
      document.store.workspaceLibrary.error == nil,
      document.store.workspaceLibrary.acceptsPanelPayload(payload),
      anchor.x.isFinite, anchor.y.isFinite
    else { return false }
    let library = document.store.workspaceLibrary
    guard let panels = library.panelDock.panels(for: payload.source), let first = panels.first,
      let group = library.panelDock.groups.first(where: { $0.panels.contains(first) })
    else { return false }
    let size =
      owner.floatingPanels.tearOffSize(for: group) ?? group.floatingFrame?.rect.size
      ?? NSSize(
        width: library.columnWidth(group.dockColumnID),
        height: min(4000, max(120, (group.preferredHeight ?? 280) + 22)))
    context = Context(
      payload: payload, document: document, library: library, layout: library.layout,
      workspaceName: library.activeName, size: size,
      anchor: NSPoint(x: min(size.width - 20, max(0, anchor.x)), y: min(60, max(0, anchor.y))))
    for screen in screenFrames() where !screen.isEmpty {
      guard [screen.minX, screen.minY, screen.width, screen.height].allSatisfy(\.isFinite) else {
        continue
      }
      let window = PanelTearOffBackdrop(
        contentRect: screen, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = false
      window.isExcludedFromWindowsMenu = true
      window.tabbingMode = .disallowed
      window.contentView = PanelTearOffContainer(
        content: NSView(frame: NSRect(origin: .zero, size: screen.size)), coordinator: self)
      backdrops.append(window)
      if presentsBackdrops, let frame = owner.applicationFrame?.window {
        window.order(.below, relativeTo: frame.windowNumber)
      }
    }
    return true
  }

  func accepts(_ payload: PanelDockPayload) -> Bool {
    guard let context, let owner, owner.activeDocument === context.document,
      owner.canChangeDocument, context.library.error == nil,
      context.document.store.workspaceLibrary === context.library,
      context.library.activeName == context.workspaceName,
      context.library.layout == context.layout,
      payload.library == context.payload.library, payload.source == context.payload.source,
      context.library.acceptsPanelPayload(payload)
    else { return false }
    return true
  }

  @discardableResult func drop(_ payload: PanelDockPayload, at point: NSPoint) -> Bool {
    guard accepts(payload), let context, point.x.isFinite, point.y.isFinite else { return false }
    let frame = FloatingPanelFrame(
      NSRect(
        x: point.x - context.anchor.x,
        y: point.y + context.anchor.y - context.size.height,
        width: context.size.width, height: context.size.height))
    guard frame.isValid else { return false }
    let committed = context.library.floatPanels(payload.source, frame: frame)
    if committed { didCommitDrop() }
    return committed
  }

  func didCommitDrop() {
    guard let id = context?.id else { return }
    Task { @MainActor [weak self] in
      // Either docking or floating can remove the source view before the session ends.
      if self?.context?.id == id { self?.finish() }
    }
  }

  func finish() {
    context = nil
    for backdrop in backdrops {
      backdrop.orderOut(nil)
      backdrop.close()
    }
    backdrops.removeAll()
  }
}

@MainActor final class PanelTearOffBackdrop: NSWindow {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// An ancestor receiver catches a panel drop over non-docking editor content.
/// Child tab and boundary receivers retain priority for actual dock placement.
@MainActor final class PanelTearOffContainer: NSView {
  weak var coordinator: PanelTearOffCoordinator?
  init(content: NSView, coordinator: PanelTearOffCoordinator) {
    self.coordinator = coordinator
    super.init(frame: content.frame)
    content.frame = bounds
    content.autoresizingMask = [.width, .height]
    addSubview(content)
    registerForDraggedTypes([PanelDockPayload.type])
  }
  required init?(coder: NSCoder) { nil }
  func payload(from pasteboard: NSPasteboard) -> PanelDockPayload? {
    guard let payload = PanelDockPayload.read(pasteboard), coordinator?.accepts(payload) == true
    else { return nil }
    return payload
  }
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    payload(from: sender.draggingPasteboard) == nil ? [] : .move
  }
  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    payload(from: sender.draggingPasteboard) != nil
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let payload = payload(from: sender.draggingPasteboard), let window else { return false }
    return coordinator?.drop(payload, at: window.convertPoint(toScreen: sender.draggingLocation))
      ?? false
  }
}

@MainActor private func tearOffPayload(
  _ sender: any NSDraggingInfo, coordinator: PanelTearOffCoordinator?
) -> PanelDockPayload? {
  guard let payload = PanelDockPayload.read(sender.draggingPasteboard),
    coordinator?.accepts(payload) == true
  else { return nil }
  return payload
}

// NSWindow receives drops over titlebar/chrome that are outside its content-view hierarchy.
extension DocumentWorkspaceWindow: NSDraggingDestination {
  private var tearOffCoordinator: PanelTearOffCoordinator? {
    (windowController as? DocumentWorkspaceController)?.workspace.owner?.panelDragging
  }
  func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
  func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    tearOffPayload(sender, coordinator: tearOffCoordinator) == nil ? [] : .move
  }
  func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    tearOffPayload(sender, coordinator: tearOffCoordinator) != nil
  }
  func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let payload = tearOffPayload(sender, coordinator: tearOffCoordinator) else {
      return false
    }
    return tearOffCoordinator?.drop(payload, at: convertPoint(toScreen: sender.draggingLocation))
      ?? false
  }
}

extension FloatingPanelWindow: NSDraggingDestination {
  func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
  func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    tearOffPayload(sender, coordinator: documents?.panelDragging) == nil ? [] : .move
  }
  func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    tearOffPayload(sender, coordinator: documents?.panelDragging) != nil
  }
  func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let payload = tearOffPayload(sender, coordinator: documents?.panelDragging) else {
      return false
    }
    return documents?.panelDragging.drop(
      payload, at: convertPoint(toScreen: sender.draggingLocation)) ?? false
  }
}
