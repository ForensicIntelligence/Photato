import AppKit
import Observation
import SwiftUI

/// Panels are presentation windows, never NSDocuments or additional image views.
@MainActor final class FloatingPanelWindow: NSPanel {
  static var titlebarHeight: Double {
    NSWindow.frameRect(
      forContentRect: .zero, styleMask: [.titled, .closable, .resizable, .utilityWindow]
    ).height
  }
  weak var documents: DocumentWindows?
  override var canBecomeMain: Bool { false }
  override var canBecomeKey: Bool { true }
  override func sendEvent(_ event: NSEvent) {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if event.type == .keyDown, event.keyCode == 48,
      modifiers == [.control] || modifiers == [.control, .shift],
      documents?.canChangeDocument == true
    {
      documents?.cycle(backwards: modifiers.contains(.shift))
      return
    }
    if event.type == .keyDown || event.type == .keyUp, firstResponder === self,
      documents?.canChangeDocument == true, let target = documents?.current?.window
    {
      target.sendEvent(event)
      return
    }
    super.sendEvent(event)
  }
}

@MainActor final class FloatingPanelController: NSWindowController, NSWindowDelegate {
  let groupID: String
  weak var coordinator: FloatingPanelWindows?
  private var applyingFrame = false
  private var hiddenHeight = 0.0
  private(set) var expandedRowHeights: [String: Double] = [:]

  init(groupID: String, coordinator: FloatingPanelWindows) {
    self.groupID = groupID
    self.coordinator = coordinator
    let panel = FloatingPanelWindow(
      contentRect: NSRect(x: 100, y: 100, width: 322, height: 300),
      styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
    panel.documents = coordinator.owner
    panel.isReleasedWhenClosed = false
    panel.autorecalculatesKeyViewLoop = true
    panel.registerForDraggedTypes([PanelDockPayload.type])
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.isExcludedFromWindowsMenu = true
    panel.tabbingMode = .disallowed
    panel.collectionBehavior = [.fullScreenAuxiliary]
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.backgroundColor = NSColor(calibratedWhite: 0.29, alpha: 1)
    super.init(window: panel)
    panel.delegate = self
    let host = NSHostingView(
      rootView: FloatingPanelRoot(owner: coordinator.owner!, groupID: groupID))
    host.sizingOptions = []
    if let owner = coordinator.owner {
      panel.contentView = PanelTearOffContainer(content: host, coordinator: owner.panelDragging)
    } else {
      panel.contentView = host
    }
  }
  required init?(coder: NSCoder) { nil }

  func apply(_ groups: [PanelDockGroup], library: WorkspaceLibrary, screens: [NSRect]) {
    guard let window, let saved = groups.first?.floatingFrame else { return }
    applyingFrame = true
    defer { applyingFrame = false }
    let dock = library.panelDock
    let shown = groups.filter {
      !dock.visiblePanels(in: $0, visibility: library.layout.visibility).isEmpty
    }
    window.title = shown.compactMap {
      dock.selectedPanel(in: $0, visibility: library.layout.visibility)?.rawValue
    }.joined(separator: " / ")
    window.isMovable = !library.workspaceLocked
    let chrome = window.frameRect(forContentRect: .zero).height
    let sizing = FloatingPanelStackSizing(
      dock: dock, hostID: groupID, visibility: library.layout.visibility,
      expandedHeight: max(0, saved.height - chrome))
    hiddenHeight = max(0, saved.height - chrome - sizing.naturalHeight)
    var visibleFrame = saved.rect
    visibleFrame.origin.y += hiddenHeight
    visibleFrame.size.height -= hiddenHeight
    let frame = FloatingPanelFrame(visibleFrame).fitted(to: screens)
    let fittedSizing = FloatingPanelStackSizing(
      dock: dock, hostID: groupID, visibility: library.layout.visibility,
      expandedHeight: max(0, saved.height - chrome), visibleHeight: max(0, frame.height - chrome))
    expandedRowHeights = sizing.expanded
    for row in fittedSizing.rows where !row.group.collapsed {
      expandedRowHeights[row.id] = row.height
    }
    let minimum =
      shown.reduce(0.0) { $0 + ($1.collapsed ? 29 : 80) }
      + Double(max(0, shown.count - 1)) * 4
    window.contentMinSize = NSSize(width: 275, height: min(minimum, max(0, frame.height - chrome)))
    window.contentMaxSize = NSSize(
      width: 4000, height: shown.allSatisfy(\.collapsed) ? minimum : 4000)
    if window.frame != frame { window.setFrame(frame, display: true) }
  }

  func windowDidMove(_ notification: Notification) { recordFrame() }
  func windowDidResize(_ notification: Notification) { recordFrame() }
  private func recordFrame() {
    guard !applyingFrame, let window else { return }
    coordinator?.owner?.activeDocument?.store.workspaceLibrary.recordFloatingStackFrame(
      groupID, frame: window.frame, hiddenHeight: hiddenHeight, expandedRows: expandedRowHeights)
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let coordinator, let library = coordinator.owner?.activeDocument?.store.workspaceLibrary,
      coordinator.owner?.canChangeDocument == true
    else { return false }
    library.closePanels(library.panelDock.floatingGroups(groupID).flatMap(\.panels))
    // Observation reconciles after this native callback; no delegate is destroyed mid-call.
    return false
  }
}

private struct FloatingPanelRoot: View {
  var owner: DocumentWindows
  let groupID: String
  var body: some View {
    if let document = owner.activeDocument {
      WorkspaceView(
        store: document.store, workspace: owner.applicationFrame?.workspace,
        floatingPanelGroup: groupID
      )
      .id(ObjectIdentifier(document))
      .disabled(!owner.canChangeDocument || document.store.workspaceLibrary.error != nil)
    }
  }
}

@MainActor final class FloatingPanelWindows: NSObject {
  weak var owner: DocumentWindows?
  private(set) var controllers: [String: FloatingPanelController] = [:]
  private var observationRevision = 0
  var presentsWindows = true
  var screenFrames: () -> [NSRect] = { NSScreen.screens.map(\.visibleFrame) }

  init(owner: DocumentWindows) {
    self.owner = owner
    super.init()
    for name in [
      NSApplication.didChangeScreenParametersNotification,
      NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(screenOrWindowChanged), name: name, object: nil)
    }
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc private func screenOrWindowChanged(_ notification: Notification) { synchronize() }

  func synchronize() {
    observationRevision &+= 1
    let revision = observationRevision
    withObservationTracking {
      reconcile()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.observationRevision == revision else { return }
        self.synchronize()
      }
    }
  }

  private func reconcile() {
    guard let owner, let document = owner.activeDocument else {
      dismissAll()
      return
    }
    let library = document.store.workspaceLibrary
    let groups = library.panelDock.visibleGroups(library.layout.visibility).filter {
      $0.floatingFrame != nil
    }
    let ids = Set(groups.map(\.floatingHostID))
    for id in Array(controllers.keys) where !ids.contains(id) {
      let controller = controllers.removeValue(forKey: id)
      controller?.window?.orderOut(nil)
      controller?.close()
    }
    for id in ids.sorted() {
      let controller =
        controllers[id] ?? FloatingPanelController(groupID: id, coordinator: self)
      controllers[id] = controller
      controller.apply(
        library.panelDock.floatingGroups(id), library: library, screens: screenFrames())
      if presentsWindows && owner.applicationFrame?.window?.isMiniaturized != true {
        // Do not steal keyboard focus from the canvas or an in-progress text edit.
        if controller.window?.isVisible != true { controller.window?.orderFront(nil) }
      } else {
        controller.window?.orderOut(nil)
      }
    }
  }

  func tearOffSize(for group: PanelDockGroup) -> NSSize? {
    guard let controller = controllers[group.floatingHostID], let window = controller.window,
      let height = controller.expandedRowHeights[group.id]
    else { return nil }
    return NSSize(
      width: window.frame.width,
      height: min(4000, max(120, height + window.frameRect(forContentRect: .zero).height)))
  }

  func dismissAll() {
    for controller in controllers.values {
      controller.window?.orderOut(nil)
      controller.close()
    }
    controllers.removeAll()
  }
}
