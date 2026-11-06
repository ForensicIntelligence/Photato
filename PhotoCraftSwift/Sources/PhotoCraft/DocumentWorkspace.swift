import AppKit
import Observation
import SwiftUI

/// A native window owns the tab presentation; every tab retains its own NSDocument lifecycle.
@MainActor @Observable final class DocumentWorkspace {
  var documents: [CraftNSDocument] = []
  var activeDocument: CraftNSDocument?
  let floating: Bool
  init(floating: Bool = false) { self.floating = floating }
  var revision = 0
  @ObservationIgnored weak var owner: DocumentWindows?
  @ObservationIgnored weak var controller: DocumentWorkspaceController?

  func select(_ document: CraftNSDocument) {
    guard documents.contains(where: { $0 === document }), controller?.window?.attachedSheet == nil
    else { return }
    guard owner?.activate(document) != false else { return }
    activeDocument = document
    controller?.updateDocumentPresentation()
    controller?.window?.makeKeyAndOrderFront(nil)
  }

  func cycle(backwards: Bool) {
    guard documents.count > 1, let activeDocument,
      let index = documents.firstIndex(where: { $0 === activeDocument })
    else { return }
    select(documents[(index + (backwards ? documents.count - 1 : 1)) % documents.count])
  }
}

@MainActor final class DocumentWorkspaceWindow: PhotatoWindow {
  override func sendEvent(_ event: NSEvent) {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if event.type == .keyDown, event.keyCode == 48,
      modifiers == [.control] || modifiers == [.control, .shift], attachedSheet == nil,
      let host = windowController as? DocumentWorkspaceController
    {
      host.workspace.owner?.cycle(backwards: modifiers.contains(.shift))
      return
    }
    if event.type == .keyDown, attachedSheet == nil, NSApp.modalWindow == nil,
      firstResponder === self || firstResponder is CraftCanvas,
      let host = windowController as? DocumentWorkspaceController,
      let document = host.workspace.owner?.current?.workspace.activeDocument
        ?? host.workspace.activeDocument,
      document.store.handleComponentShortcut(event)
    {
      return
    }
    // A click in the common panels must keep keyboard canvas actions on the active document.
    // Text fields and other native controls retain their ordinary responder-chain behavior.
    if event.type == .keyDown || event.type == .keyUp,
      let host = windowController as? DocumentWorkspaceController, !host.workspace.floating,
      firstResponder === self || firstResponder is CraftCanvas,
      let active = host.workspace.owner?.current?.window, active !== self
    {
      active.sendEvent(event)
      return
    }
    super.sendEvent(event)
  }
}

@MainActor final class DocumentWorkspaceController: NSWindowController, NSWindowDelegate {
  let workspace: DocumentWorkspace

  init(workspace: DocumentWorkspace) {
    self.workspace = workspace
    let window = DocumentWorkspaceWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1380, height: 920),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.minSize =
      workspace.floating ? NSSize(width: 100, height: 100) : NSSize(width: 1000, height: 650)
    window.isReleasedWhenClosed = false
    // SwiftUI adds and replaces native fields after the window's initial layout.
    window.autorecalculatesKeyViewLoop = true
    window.registerForDraggedTypes([PanelDockPayload.type])
    window.tabbingMode = .disallowed
    window.titlebarAppearsTransparent = true
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(calibratedWhite: 0.32, alpha: 1)
    super.init(window: window)
    workspace.controller = self
    window.delegate = self
    let host = NSHostingView(rootView: DocumentWorkspaceRoot(workspace: workspace))
    // Empty-to-document transitions must not replace the user's window size with intrinsic sizing.
    host.sizingOptions = []
    if let owner = workspace.owner {
      window.contentView = PanelTearOffContainer(content: host, coordinator: owner.panelDragging)
    } else {
      window.contentView = host
    }
    window.center()
  }

  required init?(coder: NSCoder) { nil }

  func updateDocumentPresentation() {
    let document = workspace.activeDocument
    window?.title = document?.photatoWindowTitle ?? "Photato"
    window?.representedURL = document?.fileURL
    window?.isDocumentEdited = document?.isDocumentEdited ?? false
    workspace.revision &+= 1
  }

  func windowDidBecomeKey(_ notification: Notification) {
    if workspace.floating, let document = workspace.activeDocument {
      _ = workspace.owner?.activate(document)
    }
  }

  func windowWillBeginSheet(_ notification: Notification) {
    workspace.owner?.sheetStateDidChange(in: self)
  }

  func windowDidEndSheet(_ notification: Notification) {
    workspace.owner?.sheetStateDidChange(in: self)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    workspace.owner?.closeGroup(self)
    return false
  }
}

private struct DocumentWorkspaceRoot: View {
  @Bindable var workspace: DocumentWorkspace
  var body: some View {
    if workspace.floating {
      if let document = workspace.activeDocument {
        DocumentSurfaceView(
          store: document.store, compact: true,
          isActive: workspace.owner?.activeDocument === document
        ) {
          workspace.owner?.activate(document) ?? true
        }
      } else {
        Color(white: 0.245)
      }
    } else if let document = workspace.owner?.activeDocument ?? workspace.activeDocument {
      WorkspaceView(store: document.store, workspace: workspace)
    } else {
      Color(white: 0.245)
    }
  }
}

@MainActor @Observable final class DocumentWindows {
  var groups: [DocumentWorkspaceController] = []
  var activeDocument: CraftNSDocument?
  private var sheetStateRevision = 0
  @ObservationIgnored weak var lastActive: DocumentWorkspaceController?
  @ObservationIgnored lazy var floatingPanels = FloatingPanelWindows(owner: self)
  @ObservationIgnored lazy var panelDragging = PanelTearOffCoordinator(owner: self)

  var applicationFrame: DocumentWorkspaceController? { groups.first { !$0.workspace.floating } }
  var current: DocumentWorkspaceController? {
    activeDocument.flatMap { group(for: $0) } ?? applicationFrame ?? lastActive
  }

  private var deferredPresentations: [CraftNSDocument] = []

  var canChangeDocument: Bool {
    // AppKit's attachedSheet is not observable. In particular, SwiftUI can clear a draft
    // before its native sheet detaches; panel/menu/drag validation must refresh afterward.
    _ = sheetStateRevision
    guard groups.allSatisfy({ $0.window?.attachedSheet == nil }) else { return false }
    guard let store = activeDocument?.store else { return true }
    return !store.hasToneDraft && store.transformDraft == nil && !store.geometryBusy
      && store.geometrySheet == nil && !store.showAI && !store.showGaps
      && !store.showFeatherSelection && store.gradientNameDraft == nil
      && store.patternNameDraft == nil && store.error == nil
  }

  func sheetStateDidChange(in controller: DocumentWorkspaceController) {
    guard groups.contains(where: { $0 === controller }) else { return }
    sheetStateRevision &+= 1
    guard canChangeDocument else { return }
    let pending = deferredPresentations
    deferredPresentations.removeAll()
    for document in pending where group(for: document) != nil { present(document) }
  }

  @discardableResult func activate(_ document: CraftNSDocument) -> Bool {
    guard let group = group(for: document) else { return false }
    if activeDocument === document { return true }
    guard canChangeDocument else { return false }
    panelDragging.finish()
    if let previous = activeDocument, previous !== document {
      previous.store.finishNumericField()
      previous.store.finishLayerName()
      // A pending field can report a validation error during its commit.
      // Keep its document active so that error remains visible and actionable.
      guard canChangeDocument else { return false }
      transferWorkspace(from: previous, to: document)
    }
    activeDocument = document
    lastActive = group
    floatingPanels.synchronize()
    return true
  }

  private func transferWorkspace(from previous: CraftNSDocument, to document: CraftNSDocument) {
    previous.store.cancelClone()
    previous.store.cancelGradientGesture()
    previous.store.resetPathGesture()
    document.store.tool = previous.store.tool
    document.store.unavailableToolID = previous.store.unavailableToolID
    document.store.rememberedTools = previous.store.rememberedTools
    document.store.adjustmentBrushKind = previous.store.adjustmentBrushKind
    document.store.adjustmentBrushSubtract = previous.store.adjustmentBrushSubtract
    document.store.adjustmentBrushObject = previous.store.adjustmentBrushObject
    document.store.adjustmentBrushOverlay = previous.store.adjustmentBrushOverlay
    document.store.paintToolOptions = previous.store.paintToolOptions
    document.store.mixerPaint = previous.store.mixerPaint
    document.store.patternStampOrigin = previous.store.patternStampOrigin
    document.store.patternStampID = previous.store.patternStampID
    document.store.selectedBrushID = previous.store.selectedBrushID
    document.store.brush = previous.store.brush
    document.store.backgroundColor = previous.store.backgroundColor
    document.store.autoSelect = previous.store.autoSelect
    document.store.showLayerBounds = previous.store.showLayerBounds
    document.store.selectionMode = previous.store.selectionMode
    document.store.selectionFeather = previous.store.selectionFeather
    document.store.selectionPaintMode=previous.store.selectionPaintMode
    document.store.objectSelectionMode=previous.store.objectSelectionMode
    document.store.selectionSampleAllLayers=previous.store.selectionSampleAllLayers
    document.store.selectionEnhanceEdge=previous.store.selectionEnhanceEdge
    document.store.selectionOverlayColor=previous.store.selectionOverlayColor
    document.store.selectionAntiAlias = previous.store.selectionAntiAlias
    document.store.showTransformReferencePoint = previous.store.showTransformReferencePoint
    document.store.wandOptions = previous.store.wandOptions
    document.store.wandSampleAllLayers = previous.store.wandSampleAllLayers
    document.store.bucketOptions = previous.store.bucketOptions
    document.store.bucketUsesPattern = previous.store.bucketUsesPattern
    document.store.bucketPatternPlacement = previous.store.bucketPatternPlacement
    document.store.gradientOptions = previous.store.gradientOptions
    document.store.fontName = previous.store.fontName
    document.store.fontSize = previous.store.fontSize
    document.store.pathOperation = previous.store.pathOperation
  }

  func cycle(backwards: Bool) {
    let documents = groups.flatMap { $0.workspace.documents }
    guard documents.count > 1, let activeDocument,
      let index = documents.firstIndex(where: { $0 === activeDocument })
    else { return }
    let next = documents[(index + (backwards ? documents.count - 1 : 1)) % documents.count]
    group(for: next)?.workspace.select(next)
  }

  func group(for document: CraftNSDocument) -> DocumentWorkspaceController? {
    groups.first { $0.workspace.documents.contains { $0 === document } }
  }

  /// Newly created copies may finish before SwiftUI detaches their source sheet.
  func presentAfterCurrentSheet(_ document: CraftNSDocument) {
    present(document)
    if activeDocument !== document, groups.contains(where: { $0.window?.attachedSheet != nil }),
      !deferredPresentations.contains(where: { $0 === document }) {
      deferredPresentations.append(document)
    }
  }

  func present(_ document: CraftNSDocument) {
    if let group = group(for: document) {
      group.workspace.select(document)
      return
    }
    let group = applicationFrame ?? makeGroup()
    group.workspace.documents.append(document)
    group.workspace.select(document)
    lastActive = group
  }

  @discardableResult private func makeGroup(floating: Bool = false) -> DocumentWorkspaceController {
    let workspace = DocumentWorkspace(floating: floating)
    workspace.owner = self
    let group = DocumentWorkspaceController(workspace: workspace)
    groups.append(group)
    return group
  }

  func remove(_ document: CraftNSDocument) {
    deferredPresentations.removeAll { $0 === document }
    guard let group = group(for: document),
      let index = group.workspace.documents.firstIndex(where: { $0 === document })
    else { return }
    group.workspace.documents.remove(at: index)
    if group.workspace.activeDocument === document {
      group.workspace.activeDocument =
        group.workspace.documents.isEmpty
        ? nil
        : group.workspace.documents[min(index, group.workspace.documents.count - 1)]
    }
    if activeDocument === document {
      panelDragging.finish()
      activeDocument = nil
      if let next = group.workspace.activeDocument
        ?? groups.flatMap({ $0.workspace.documents }).first
      {
        // Closing changes the target even if the document being closed had transient UI state.
        transferWorkspace(from: document, to: next)
        _ = activate(next)
      }
    }
    if group.workspace.documents.isEmpty && group.workspace.floating {
      dismiss(group)
    } else {
      group.updateDocumentPresentation()
    }
    floatingPanels.synchronize()
    if groups.allSatisfy({ $0.workspace.documents.isEmpty }) {
      for remaining in groups { dismiss(remaining) }
    }
  }

  private func dismiss(_ group: DocumentWorkspaceController) {
    groups.removeAll { $0 === group }
    if lastActive === group { lastActive = groups.last }
    if let window = group.window { window.parent?.removeChildWindow(window) }
    group.window?.delegate = nil
    group.close()
    group.workspace.activeDocument = nil
  }

  func requestClose(_ document: CraftNSDocument, completion: @escaping (Bool) -> Void = { _ in }) {
    guard let controller = document.ownerController, group(for: document) != nil, canChangeDocument else {
      completion(false)
      return
    }
    controller.requestDocumentClose([document], scope: .document) {
      completion($0?.phase == .completed)
    }
  }

  func closeGroup(_ group: DocumentWorkspaceController) {
    let targets = group.workspace.floating ? group.workspace.documents : groups.flatMap { $0.workspace.documents }
    targets.first?.ownerController?.requestDocumentClose(targets, scope: .window)
  }

  func float(_ document: CraftNSDocument) {
    guard let source = group(for: document), !source.workspace.floating, canChangeDocument
    else { return }
    // Keep the frame and its controls alive even when the last docked tab is detached.
    source.workspace.documents.removeAll { $0 === document }
    if source.workspace.activeDocument === document {
      source.workspace.activeDocument = source.workspace.documents.last
    }
    source.updateDocumentPresentation()
    let destination = makeGroup(floating: true)
    destination.workspace.documents = [document]
    let scale = document.store.viewport.scale
    document.store.zoom = document.store.effectiveZoom
    let visible = source.window?.screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
    destination.window?.setContentSize(
      NSSize(
        width: min(
          max(100, CGFloat(document.store.document.width) * scale + 70), visible.width * 0.8),
        height: min(
          max(78, CGFloat(document.store.document.height) * scale + 70), visible.height * 0.8)))
    destination.window?.center()
    if let window = destination.window { source.window?.addChildWindow(window, ordered: .above) }
    destination.workspace.select(document)
  }

  func floatAll() {
    guard canChangeDocument, let frame = applicationFrame else { return }
    let selected = activeDocument
    for document in frame.workspace.documents { float(document) }
    if let selected { group(for: selected)?.workspace.select(selected) }
  }

  func consolidate() {
    guard let destination = applicationFrame, canChangeDocument else { return }
    let selected = activeDocument
    let documents = groups.flatMap { $0.workspace.documents }
    for group in groups where group !== destination {
      group.workspace.documents = []
      dismiss(group)
    }
    destination.workspace.documents = documents
    if let selected { destination.workspace.select(selected) }
  }

  func canMoveTab(_ id: String, to target: CraftNSDocument) -> Bool {
    guard
      let document = groups.flatMap({ $0.workspace.documents }).first(where: {
        $0.store.identity.uuidString == id
      }), document !== target, let source = group(for: document),
      let destination = group(for: target)
    else { return false }
    return canChangeDocument && source.window?.attachedSheet == nil
      && destination.window?.attachedSheet == nil
  }

  @discardableResult func moveTab(_ id: String, before target: CraftNSDocument) -> Bool {
    moveTab(id, relativeTo: target, after: false)
  }

  @discardableResult func moveTab(_ id: String, relativeTo target: CraftNSDocument, after: Bool)
    -> Bool
  {
    guard canMoveTab(id, to: target),
      let document = groups.flatMap({ $0.workspace.documents }).first(where: {
        $0.store.identity.uuidString == id
      }), let source = group(for: document), let destination = group(for: target)
    else { return false }
    if source === destination {
      source.workspace.documents.removeAll { $0 === document }
    } else {
      remove(document)
    }
    guard let index = destination.workspace.documents.firstIndex(where: { $0 === target }) else {
      return false
    }
    destination.workspace.documents.insert(document, at: index + (after ? 1 : 0))
    destination.workspace.select(document)
    return true
  }
}
