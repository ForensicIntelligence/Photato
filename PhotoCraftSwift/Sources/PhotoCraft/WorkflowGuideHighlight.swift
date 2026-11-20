import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

enum WorkflowGuideTarget: Equatable {
  enum Control: String {
    case layerList = "Layers", layerRow = "the selected layer", layerEye = "the layer visibility button"
    case opacity = "the layer Opacity control", mask = "the layer mask thumbnail", canvas = "the canvas"
    case options = "the tool options bar", tools = "the toolbar", cropDelete = "Delete Cropped Pixels"
    case foreground = "the foreground color swatch", modalConfirm = "the confirmation button", modalFormat = "the format picker"
  }

  enum Dialog: String {
    case duplicateLayer, newLayer, savedSelection, imageExport, save

    var title: String {
      switch self {
      case .duplicateLayer: "Duplicate Layer"
      case .newLayer: "New Layer"
      case .savedSelection: "the selection dialog"
      case .imageExport: "Export As"
      case .save: "Save As"
      }
    }
  }

  case control(Control)
  case tool(EditorTool)
  case menu(String, dialog: Dialog? = nil)
  case modal(Dialog, Control)

  var label: String {
    switch self {
    case .control(let control): control.rawValue
    case .tool(let tool): "the \(tool.rawValue) tool"
    case .menu(let path, _): path.replacingOccurrences(of: " > ", with: " → ")
    case .modal(let dialog, let control): "\(control.rawValue) in \(dialog.title)"
    }
  }

  var modalTarget: (dialog: Dialog, control: Control)? {
    switch self {
    case .menu(_, let dialog?):
      (dialog, dialog == .save || dialog == .imageExport ? .modalFormat : .modalConfirm)
    case .modal(let dialog, let control): (dialog, control)
    default: nil
    }
  }

  var capability: [String: String] {
    switch self {
    case .menu(let path, let dialog):
      if let dialog { ["kind": "menu", "label": path, "dialog": dialog.rawValue] }
      else { ["kind": "menu", "label": path] }
    case .tool(let tool): ["kind": "tool", "label": tool.rawValue]
    case .control(let control): ["kind": "control", "label": control.rawValue]
    case .modal(let dialog, let control): ["kind": "control", "label": control.rawValue, "dialog": dialog.rawValue]
    }
  }
}

struct WorkflowGuideAnchor: NSViewRepresentable {
  let targets: [WorkflowGuideTarget]

  final class AnchorView: NSView {
    var targets: [WorkflowGuideTarget] = []
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  func makeNSView(context: Context) -> AnchorView {
    let view = AnchorView()
    view.setAccessibilityElement(false)
    return view
  }

  func updateNSView(_ view: AnchorView, context: Context) { view.targets = targets }
}

extension View {
  func workflowGuideAnchor(_ control: WorkflowGuideTarget.Control, when available: Bool = true) -> some View {
    background {
      if available { WorkflowGuideAnchor(targets: [.control(control)]).allowsHitTesting(false) }
    }
  }

  func workflowGuideSheetHighlight(_ surface: WorkflowGuideTarget.Dialog,
    control: WorkflowGuideTarget.Control, store: EditorStore) -> some View {
    overlay {
      if let highlighter = store.documentController?.workflowGuideHighlighter,
        let request = highlighter.sheetHighlight, request.surface == surface, request.control == control {
        WorkflowGuideSheetCue()
          .padding(-4)
          .id(request.id)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
          .onAppear { highlighter.sheetOutlineAppeared(request.id) }
      }
    }
  }
}

private struct WorkflowGuideSheetCue: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false

  var body: some View {
    RoundedRectangle(cornerRadius: 6)
      .strokeBorder(.black.opacity(0.78), lineWidth: 5)
      .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.yellow, lineWidth: 2.5) }
      .opacity(revealed || reduceMotion ? 1 : 0.5)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.18)) { revealed = true }
      }
  }
}

@MainActor @Observable final class WorkflowGuideHighlighter {
  struct SheetHighlight {
    let id = UUID()
    let surface: WorkflowGuideTarget.Dialog
    let control: WorkflowGuideTarget.Control
  }

  static let saveFormatControl = NSUserInterfaceItemIdentifier("photato.workflowGuide.saveFormat")
  @ObservationIgnored private weak var windows: DocumentWindows?
  private(set) var overlay: NSPanel?
  private(set) var nativeSheetOutline: NSView?
  private(set) var sheetHighlight: SheetHighlight?
  private(set) var visibleSheetHighlight: UUID?
  @ObservationIgnored private var dismissal: Task<Void, Never>?
  @ObservationIgnored private var sheetLayout: Task<Void, Never>?
  @ObservationIgnored private var menuLayout: Timer?
  @ObservationIgnored private weak var pendingMenuItem: NSMenuItem?
  @ObservationIgnored private weak var outlinedMenu: NSMenu?
  @ObservationIgnored private weak var outlinedSheet: NSWindow?

  init(windows: DocumentWindows) { self.windows = windows }

  @discardableResult func show(_ target: WorkflowGuideTarget?) -> Bool {
    clear()
    guard let target, let windows, let document = windows.activeDocument else { return false }
    let editor = windows.current?.window
    if let sheet = editor?.attachedSheet ?? NSApp.modalWindow, sheet !== editor {
      return showInSheet(target, sheet: sheet, editor: editor, store: document.store)
    }
    if case .menu(let path, _) = target {
      guard NSApp.isActive, let item = menuItems(path).first else { return false }
      return draw(around: item.accessibilityFrame(), parent: nil)
    }
    if case .modal = target { return false }
    let floating = windows.floatingPanels.controllers.values.compactMap(\.window)
    let candidates = ([editor].compactMap { $0 } + floating).filter(\.isVisible)
    for window in candidates {
      if let view = anchor(target, in: window.contentView), show(view) { return true }
    }
    let fallback: WorkflowGuideTarget?
    switch target {
    case .tool: fallback = .control(.tools)
    case .control(.layerRow), .control(.layerEye), .control(.mask): fallback = .control(.layerList)
    default: fallback = nil
    }
    if let fallback {
      for window in candidates {
        if let view = anchor(fallback, in: window.contentView), show(view) { return true }
      }
    }
    return false
  }

  func showInAttachedSheet(_ target: WorkflowGuideTarget, of editor: NSWindow) -> Bool {
    guard editor === windows?.current?.window, let sheet = editor.attachedSheet,
      let store = windows?.activeDocument?.store else { return false }
    return showInSheet(target, sheet: sheet, editor: editor, store: store)
  }

  func showInModalWindow(_ target: WorkflowGuideTarget, sheet: NSWindow) -> Bool {
    guard let windows, let store = windows.activeDocument?.store else { return false }
    return showInSheet(target, sheet: sheet, editor: windows.current?.window, store: store)
  }

  private func showInSheet(_ target: WorkflowGuideTarget, sheet: NSWindow, editor: NSWindow?, store: EditorStore) -> Bool {
    guard sheet.isVisible, sheet.sheetParent == nil || sheet.sheetParent === editor,
      let destination = target.modalTarget else { return false }
    if destination.dialog == .save, let panel = sheet as? NSSavePanel, !(panel is NSOpenPanel),
      let format = anchor(.control(.modalFormat), in: panel.accessoryView) {
      let view = destination.control == .modalFormat ? format : panel.defaultButtonCell?.controlView
      return view.map { highlightNativeControl($0, in: panel) } ?? false
    }
    guard sheet === editor?.attachedSheet, !(sheet is NSSavePanel), matches(destination.dialog, store: store) else { return false }
    return highlightSwiftUISheet(sheet, surface: destination.dialog, control: destination.control)
  }

  func menuWillOpen(_ menu: NSMenu, for target: WorkflowGuideTarget) {
    guard case .menu(let path, _) = target,
      let item = menuItems(path).first(where: { $0.menu === menu }) else { return }
    stopMenuLayout()
    pendingMenuItem = item
    let deadline = ProcessInfo.processInfo.systemUptime + 0.45
    let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      MainActor.assumeIsolated {
        guard let item = self.pendingMenuItem, let menu = item.menu,
          ProcessInfo.processInfo.systemUptime < deadline else { self.stopMenuLayout(); return }
        // AppKit can supply a row-sized frame at the screen origin before positioning the menu.
        if let frame = self.visibleMenuItemFrame(item),
          self.draw(around: frame, parent: nil, trackingMenu: true) {
          self.outlinedMenu = menu
        }
      }
    }
    menuLayout = timer
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.add(timer, forMode: .eventTracking)
  }

  func menuDidClose(_ menu: NSMenu) {
    if pendingMenuItem?.menu === menu { stopMenuLayout() }
    if outlinedMenu === menu { clear() }
  }

  func clearMenuHighlight() {
    stopMenuLayout()
    if let overlay, overlay.parent == nil { clear() }
  }

  func clearSheetHighlight() {
    if sheetHighlight != nil || outlinedSheet != nil { clear() }
  }

  private func stopMenuLayout() {
    menuLayout?.invalidate()
    menuLayout = nil
    pendingMenuItem = nil
  }

  private func highlightNativeControl(_ view: NSView, in sheet: NSWindow) -> Bool {
    guard view.window?.isVisible == true, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty else { return false }
    clear()
    // AppKit can host the accessory in its own window. Paint on the control so the cue moves with it.
    let outline = WorkflowGuideOutline(frame: view.bounds)
    outline.autoresizingMask = [.width, .height]
    outline.setAccessibilityElement(false)
    view.addSubview(outline, positioned: .above, relativeTo: nil)
    nativeSheetOutline = outline
    outlinedSheet = sheet
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      outline.alphaValue = 0.55
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.18
        outline.animator().alphaValue = 1
      }
    }
    scheduleDismissal()
    return true
  }

  private func highlightSwiftUISheet(_ sheet: NSWindow, surface: WorkflowGuideTarget.Dialog,
    control: WorkflowGuideTarget.Control) -> Bool {
    guard sheet.contentView != nil else { return false }
    clear()
    let request = SheetHighlight(surface: surface, control: control)
    sheetHighlight = request
    scheduleDismissal()
    sheetLayout = Task { @MainActor [weak self, weak sheet] in
      do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
      guard self?.visibleSheetHighlight != request.id else { return }
      if let self, let sheet, let content = sheet.contentView, self.show(content) { self.outlinedSheet = sheet }
    }
    return true
  }

  func sheetOutlineAppeared(_ id: UUID) {
    guard sheetHighlight?.id == id else { return }
    visibleSheetHighlight = id
  }

  private func matches(_ dialog: WorkflowGuideTarget.Dialog, store: EditorStore) -> Bool {
    switch dialog {
    case .duplicateLayer: store.duplicateLayerDraft != nil
    case .newLayer: store.newLayerDraft != nil
    case .savedSelection: store.channelDialog != nil
    case .imageExport: store.imageExportDraft != nil
    case .save: false
    }
  }

  private func menuItems(_ path: String) -> [NSMenuItem] {
    let names = path.components(separatedBy: " > ")
    var current = NSApp.mainMenu
    var matches: [NSMenuItem] = []
    var prefix: [String] = []
    for name in names {
      prefix.append(name)
      let suffix = CharacterSet(charactersIn: ".…")
      let identifier = prefix.joined(separator: " > ").trimmingCharacters(in: suffix)
      guard let item = current?.items.first(where: {
        guard !$0.isHidden, !$0.isAlternate else { return false }
        if let id = $0.identifier?.rawValue { return id.trimmingCharacters(in: suffix) == identifier }
        return $0.title.trimmingCharacters(in: suffix) == name.trimmingCharacters(in: suffix)
      }) else { break }
      matches.append(item)
      current = item.submenu
    }
    return matches
  }

  private func anchor(_ target: WorkflowGuideTarget, in root: NSView?) -> NSView? {
    guard let root, !root.isHidden else { return nil }
    if target == .control(.modalFormat), root.identifier == Self.saveFormatControl,
      !root.visibleRect.isEmpty { return root }
    if let candidate = root as? WorkflowGuideAnchor.AnchorView,
      candidate.targets.contains(target), !candidate.visibleRect.isEmpty { return candidate }
    for child in root.subviews {
      if let match = anchor(target, in: child) { return match }
    }
    return nil
  }

  private func show(_ view: NSView) -> Bool {
    guard let window = view.window, window.isVisible, !view.isHiddenOrHasHiddenAncestor else { return false }
    return draw(around: window.convertToScreen(view.convert(view.visibleRect, to: nil)), parent: window)
  }

  private func visibleMenuItemFrame(_ item: NSMenuItem) -> NSRect? {
    let frame = item.accessibilityFrame()
    guard !frame.isEmpty, let screen = NSScreen.screens.first else { return nil }
    guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
      return frame.origin == .zero ? nil : frame
    }
    let popupLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
    for window in windows where window[kCGWindowOwnerPID as String] as? Int32 == getpid()
      && window[kCGWindowLayer as String] as? Int == popupLevel {
      guard let fields = window[kCGWindowBounds as String] as? [String: Any],
        let bounds = CGRect(dictionaryRepresentation: fields as CFDictionary) else { continue }
      let rect = CGRect(x: bounds.minX, y: screen.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
      if rect.insetBy(dx: -1, dy: -1).contains(frame) { return frame }
    }
    return nil
  }

  private func draw(around rect: NSRect, parent: NSWindow?, trackingMenu: Bool = false) -> Bool {
    guard !rect.isEmpty, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }) else { return false }
    let frame = rect.insetBy(dx: -4, dy: -4).intersection(screen.frame)
    guard !frame.isEmpty else { return false }
    if trackingMenu, outlinedMenu === pendingMenuItem?.menu, let overlay {
      if overlay.frame != frame { overlay.setFrame(frame, display: true) }
      return true
    }
    clear(preservingMenuLayout: trackingMenu)
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = true
    panel.isExcludedFromWindowsMenu = true
    panel.isReleasedWhenClosed = false
    let menuLevel: CGWindowLevelKey = trackingMenu ? .popUpMenuWindow : .mainMenuWindow
    panel.level = parent?.level ?? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(menuLevel)) + 1)
    panel.contentView = WorkflowGuideOutline(frame: NSRect(origin: .zero, size: frame.size))
    panel.contentView?.setAccessibilityElement(false)
    parent?.addChildWindow(panel, ordered: .above)
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if !reduceMotion && !trackingMenu { panel.alphaValue = 0.55 }
    panel.orderFront(nil)
    if trackingMenu {
      panel.setFrame(frame, display: true)
    }
    if !reduceMotion && !trackingMenu {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.18
        panel.animator().alphaValue = 1
      }
    }
    overlay = panel
    scheduleDismissal()
    return true
  }

  private func scheduleDismissal() {
    dismissal = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(1400)) } catch { return }
      self?.clear()
    }
  }

  private func clear(preservingMenuLayout: Bool = false) {
    if !preservingMenuLayout { stopMenuLayout() }
    outlinedMenu = nil
    outlinedSheet = nil
    dismissal?.cancel()
    dismissal = nil
    sheetLayout?.cancel()
    sheetLayout = nil
    sheetHighlight = nil
    visibleSheetHighlight = nil
    nativeSheetOutline?.removeFromSuperview()
    nativeSheetOutline = nil
    if let overlay {
      overlay.parent?.removeChildWindow(overlay)
      overlay.orderOut(nil)
      self.overlay = nil
    }
  }
}

private final class WorkflowGuideOutline: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 6, yRadius: 6)
    NSColor.systemYellow.withAlphaComponent(0.10).setFill()
    outline.fill()
    NSColor.black.withAlphaComponent(0.78).setStroke()
    outline.lineWidth = 5
    outline.stroke()
    NSColor.systemYellow.setStroke()
    outline.lineWidth = 2.5
    outline.stroke()
  }
}
