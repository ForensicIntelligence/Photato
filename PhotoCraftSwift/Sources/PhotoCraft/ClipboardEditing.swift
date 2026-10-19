import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct ClipboardRepresentations: Sendable {
  var native: Data
  var tiff: Data
  var png: Data
  init(_ content: ClipboardContent) throws {
    native = try content.encoded()
    let preview = try ClipboardRenderer.preview(content)
    try Task.checkCancellation()
    tiff = try ClipboardRenderer.imageData(preview, type: .tiff)
    try Task.checkCancellation()
    png = try ClipboardRenderer.imageData(preview, type: .png)
  }
}
enum ClipboardInput: Sendable {
  case native(Data)
  case image(Data)
  func decoded() throws -> ClipboardContent {
    switch self {
    case .native(let data): try ClipboardContent.decode(data)
    case .image(let data): try ClipboardRenderer.readImage(data)
    }
  }
}
@MainActor protocol ClipboardAccess: AnyObject {
  var changeCount: Int { get }
  var hasImage: Bool { get }
  func read() throws -> ClipboardInput
  func write(_ value: ClipboardRepresentations) throws
}
@MainActor final class SystemClipboard: ClipboardAccess {
  static let shared = SystemClipboard(pasteboard: .general)
  static let nativeType = NSPasteboard.PasteboardType("local.photocraft.swift.clipboard")
  let pasteboard: NSPasteboard
  init(pasteboard: NSPasteboard) { self.pasteboard = pasteboard }
  var changeCount: Int { pasteboard.changeCount }
  var hasImage: Bool {
    pasteboard.availableType(from: [Self.nativeType, .tiff, .png]) != nil
  }
  func read() throws -> ClipboardInput {
    if let data = pasteboard.data(forType: Self.nativeType) { return .native(data) }
    for type in [NSPasteboard.PasteboardType.tiff, .png] {
      if let data = pasteboard.data(forType: type) { return .image(data) }
    }
    throw CraftError.invalid("The clipboard does not contain an image.")
  }
  func write(_ value: ClipboardRepresentations) throws {
    let item = NSPasteboardItem()
    guard item.setData(value.native, forType: Self.nativeType),
      item.setData(value.tiff, forType: .tiff), item.setData(value.png, forType: .png)
    else {
      throw CraftError.invalid("Could not prepare clipboard formats.")
    }
    pasteboard.clearContents()
    guard pasteboard.writeObjects([item]) else {
      throw CraftError.unavailable(
        "The system clipboard could not accept the image. Nothing was cut.")
    }
  }
}

extension EditorStore {
  var clipboardLayerIDs: Set<UUID> {
    selectedLayerIDs.isEmpty ? Set(document.activeLayerID.map { [$0] } ?? []) : selectedLayerIDs
  }
  var clipboardTargetAvailable: Bool {
    !editingComponent && !geometryBusy && !hasToneDraft && transformDraft == nil && !editingMask
      && pathTarget == nil
  }
  func canCopy(merged: Bool = false, cut: Bool = false) -> Bool {
    guard clipboardTargetAvailable else { return false }
    if merged { return !document.layers.isEmpty }
    let ids = clipboardLayerIDs
    guard !ids.isEmpty else { return false }
    if document.selection != nil {
      guard ids.count == 1, let active = activeLayer else { return false }
      if case .adjustment = active.content { return false }
      if cut {
        guard case .raster = active.content else { return false }
      }
    }
    if cut {
      let removed = ids.reduce(into: Set<UUID>()) { $0.formUnion(document.subtreeIDs($1)) }
      return removed.allSatisfy { !document.isLocked($0) }
    }
    return true
  }
  func canPaste(_ placement: PastePlacement) -> Bool {
    guard clipboardTargetAvailable, clipboard.hasImage else { return false }
    if let active = activeLayer, let parent = active.isGroup ? active.id : active.parentID,
      document.isLocked(parent)
    {
      return false
    }
    if placement == .into || placement == .outside { return document.selection != nil }
    return true
  }
  func copyImage(merged: Bool = false, cut: Bool = false) {
    guard canCopy(merged: merged, cut: cut) else { return }
    let original = document
    let ids = clipboardLayerIDs
    let clipboardRevision = clipboard.changeCount
    geometryBusy = true
    status = cut ? "Cut" : merged ? "Copy Merged" : "Copy"
    geometryTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        let content = try ClipboardRenderer.copy(original, layerIDs: ids, merged: merged)
        let prepared = try cut ? PreparedEdit(command: .cut(Array(ids)), document: original) : nil
        return try (ClipboardRepresentations(content), prepared)
      }
      do {
        let (value, prepared) = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard let self else { return }
        guard self.document == original, self.clipboard.changeCount == clipboardRevision else {
          throw CraftError.invalid(
            "The document or clipboard changed during Copy. Please try again.")
        }
        try self.clipboard.write(value)
        if let prepared {
          try self.executeCompositePreparedEdit(prepared)
          self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
          self.onChange?(.changeDone)
        }
      } catch is CancellationError { self?.status = "Operation cancelled" } catch {
        self?.error = error.localizedDescription
      }
      self?.geometryBusy = false
      if cut { self?.render() }
    }
  }
  func pasteImage(_ placement: PastePlacement = .centered) {
    guard canPaste(placement) else { return }
    do {
      let input = try clipboard.read()
      let original = document
      let scale = max(0.02, measuredZoom)
      let center = PathPoint(
        min(Double(document.width), max(0, Double(document.width) / 2 - pan.width / scale)),
        min(Double(document.height), max(0, Double(document.height) / 2 - pan.height / scale)))
      geometryBusy = true
      renderTask?.cancel()
      geometryTask = Task { [weak self] in
        let worker = Task.detached(priority: .userInitiated) {
          var content = try input.decoded()
          if placement == .into || placement == .outside {
            content = try ClipboardRenderer.flattened(content)
          }
          let command = Command.paste(content, placement, content.kind == .pixels ? center : nil)
          return try PreparedEdit(command: command, document: original)
        }
        do {
          let prepared = try await withTaskCancellationHandler(
            operation: { try await worker.value }, onCancel: { worker.cancel() })
          try Task.checkCancellation()
          guard let self else { return }
          try self.executeCompositePreparedEdit(prepared)
          self.selectedLayerIDs = Set(
            self.document.layers.filter { layer in
              !original.layers.contains { $0.id == layer.id }
            }.map(\.id))
          self.maskEditingLayerID = nil
          self.onChange?(.changeDone)
          self.status = self.session.undoStack.last?.label ?? "Paste"
        } catch is CancellationError { self?.status = "Operation cancelled" } catch {
          self?.error = error.localizedDescription
        }
        self?.geometryBusy = false
        self?.render()
      }
    } catch { self.error = error.localizedDescription }
  }
}

extension AppDelegate {
  @objc func copy(_ sender: Any?) { store?.copyImage() }
  @objc func cut(_ sender: Any?) { store?.copyImage(cut: true) }
  @objc func paste(_ sender: Any?) {
    if let store { store.pasteImage() } else { newFromClipboard() }
  }
  @objc func copyMerged() { store?.copyImage(merged: true) }
  @objc func pasteInPlace() { store?.pasteImage(.inPlace) }
  @objc func pasteInto() { store?.pasteImage(.into) }
  @objc func pasteOutside() { store?.pasteImage(.outside) }
  @objc func newFromClipboard() {
    do {
      let input = try SystemClipboard.shared.read()
      let name = controller.nextUntitledName
      Task {
        do {
          var model = try await Task.detached(priority: .userInitiated) {
            try input.decoded().newDocument(name: name)
          }.value
          model.name = controller.nextUntitledName
          let doc = CraftNSDocument(model: model)
          controller.addDocument(doc)
          doc.makeWindowControllers()
          doc.showWindows()
          doc.updateChangeCount(.changeDone)
        } catch { NSApp.presentError(error) }
      }
    } catch { NSApp.presentError(error) }
  }
}
