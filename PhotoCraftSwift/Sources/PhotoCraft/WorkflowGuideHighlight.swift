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

  case control(Control)
  case tool(EditorTool)
  case menu(String, confirmsInSheet: Bool = false)

  var label: String {
    switch self {
    case .control(let control): control.rawValue
    case .tool(let tool): "the \(tool.rawValue) tool"
    case .menu(let path, _): path.replacingOccurrences(of: " > ", with: " → ")
    }
  }

  var confirmsInSheet: Bool {
    if case .menu(_, let value) = self { return value }
    return self == .control(.modalConfirm) || self == .control(.modalFormat)
  }

  var capability: [String: String] {
    switch self {
    case .menu(let path, _): ["kind": "menu", "label": path]
    case .tool(let tool): ["kind": "tool", "label": tool.rawValue]
    case .control(let control): ["kind": "control", "label": control.rawValue]
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

  func workflowGuideSheetHighlight(_ surface: WorkflowGuideHighlighter.SheetSurface,
    control: WorkflowGuideTarget.Control, store: EditorStore) -> some View {
    overlay {
      if let highlighter = store.documentController?.workflowGuideHighlighter,
        let request = highlighter.sheetHighlight, request.surface == surface, request.control == control {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(.black.opacity(0.78), lineWidth: 5)
          .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.yellow, lineWidth: 2.5) }
          .padding(-4)
          .id(request.id)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
          .onAppear { highlighter.sheetOutlineAppeared(request.id) }
      }
    }
  }
}

@MainActor @Observable final class WorkflowGuideHighlighter {
  enum SheetSurface { case duplicateLayer, newLayer, savedSelection, imageExport }
  struct SheetHighlight {
    let id = UUID()
    let surface: SheetSurface
    let control: WorkflowGuideTarget.Control
  }

  static let saveFormatControl = NSUserInterfaceItemIdentifier("photato.workflowGuide.saveFormat")
  @ObservationIgnored private weak var windows: DocumentWindows?
  private(set) var overlay: NSPanel?
  private(set) var sheetHighlight: SheetHighlight?
  private(set) var visibleSheetHighlight: UUID?
  @ObservationIgnored private var dismissal: Task<Void, Never>?
  @ObservationIgnored private var sheetLayout: Task<Void, Never>?

  init(windows: DocumentWindows) { self.windows = windows }

  @discardableResult func show(_ target: WorkflowGuideTarget?) -> Bool {
    clear()
    guard let target, let windows, let document = windows.activeDocument else { return false }
    let editor = windows.current?.window
    if target.confirmsInSheet, let sheet = editor?.attachedSheet ?? NSApp.modalWindow, sheet !== editor,
      sheet.isVisible {
      let control: WorkflowGuideTarget.Control = target == .control(.modalFormat) ? .modalFormat : .modalConfirm
      if !(sheet is NSSavePanel), let surface = sheetSurface(for: target, store: document.store) {
        return highlightSwiftUISheet(sheet, surface: surface, control: control)
      }
      if let view = anchor(.control(control), in: sheet.contentView), show(view) { return true }
      if control == .modalConfirm, let button = sheet.defaultButtonCell?.controlView, show(button) { return true }
      guard let content = sheet.contentView else { return false }
      return show(content)
    }
    if case .menu(let path, _) = target {
      guard NSApp.isActive, let item = menuItems(path).first else { return false }
      return draw(around: item.accessibilityFrame(), parent: nil)
    }
    guard editor?.attachedSheet == nil else { return false }
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

  func showMenuItem(for target: WorkflowGuideTarget, in menu: NSMenu) {
    guard NSApp.isActive, case .menu(let path, _) = target,
      let item = menuItems(path).first(where: { $0.menu === menu }) else { return }
    let frame = item.accessibilityFrame()
    if !frame.isEmpty { _ = draw(around: frame, parent: nil) }
  }

  func clearMenuHighlight() {
    if let overlay, overlay.parent == nil { clear() }
  }

  private func highlightSwiftUISheet(_ sheet: NSWindow, surface: SheetSurface,
    control: WorkflowGuideTarget.Control) -> Bool {
    guard sheet.contentView != nil else { return false }
    let request = SheetHighlight(surface: surface, control: control)
    sheetHighlight = request
    scheduleDismissal()
    sheetLayout = Task { @MainActor [weak self, weak sheet] in
      do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
      guard self?.visibleSheetHighlight != request.id else { return }
      if let content = sheet?.contentView { _ = self?.show(content) }
    }
    return true
  }

  func sheetOutlineAppeared(_ id: UUID) {
    guard sheetHighlight?.id == id else { return }
    visibleSheetHighlight = id
  }

  private func sheetSurface(for target: WorkflowGuideTarget, store: EditorStore) -> SheetSurface? {
    switch target {
    case .menu("Layer > Duplicate Layer", _): store.duplicateLayerDraft == nil ? nil : .duplicateLayer
    case .menu("Layer > New > Layer", _): store.newLayerDraft == nil ? nil : .newLayer
    case .menu("Select > Save Selection", _), .menu("Select > Load Selection", _):
      store.channelDialog == nil ? nil : .savedSelection
    case .menu("File > Export > Export As", _), .control(.modalConfirm), .control(.modalFormat):
      store.imageExportDraft == nil ? nil : .imageExport
    default: nil
    }
  }

  private func menuItems(_ path: String) -> [NSMenuItem] {
    let names = path.components(separatedBy: " > ")
    var current = NSApp.mainMenu
    var matches: [NSMenuItem] = []
    for name in names {
      let suffix = CharacterSet(charactersIn: ".…")
      guard let item = current?.items.first(where: { $0.title.trimmingCharacters(in: suffix) == name.trimmingCharacters(in: suffix) }) else { break }
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

  private func draw(around rect: NSRect, parent: NSWindow?) -> Bool {
    guard !rect.isEmpty, let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) else { return false }
    let frame = rect.insetBy(dx: -4, dy: -4).intersection(screen.frame)
    guard !frame.isEmpty else { return false }
    clear()
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = true
    panel.isExcludedFromWindowsMenu = true
    panel.isReleasedWhenClosed = false
    panel.level = parent?.level ?? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
    panel.contentView = WorkflowGuideOutline(frame: NSRect(origin: .zero, size: frame.size))
    panel.contentView?.setAccessibilityElement(false)
    parent?.addChildWindow(panel, ordered: .above)
    panel.orderFront(nil)
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

  private func clear() {
    dismissal?.cancel()
    dismissal = nil
    sheetLayout?.cancel()
    sheetLayout = nil
    sheetHighlight = nil
    visibleSheetHighlight = nil
    if let overlay {
      overlay.parent?.removeChildWindow(overlay)
      overlay.orderOut(nil)
      self.overlay = nil
    }
  }
}

private final class WorkflowGuideOutline: NSView {
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
