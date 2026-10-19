import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct TransformDraft: Equatable {
  var layerID: UUID
  var bounds: IntRect
  var centerX: Double
  var centerY: Double
  var scaleX: Double = 100
  var scaleY: Double = 100
  var angle: Double = 0
  var proportional = true
  var interpolation = Resampling.bicubic
  init(layerID: UUID, bounds: IntRect) {
    self.layerID = layerID
    self.bounds = bounds
    centerX = Double(bounds.x) + Double(bounds.width) / 2
    centerY = Double(bounds.y) + Double(bounds.height) / 2
  }
  var delta: Transform2D {
    .translation(centerX, centerY) * .rotation(angle) * .scale(scaleX / 100, scaleY / 100)
      * .translation(
        -Double(bounds.x) - Double(bounds.width) / 2, -Double(bounds.y) - Double(bounds.height) / 2)
  }
  var handles: [CGPoint] {
    [(-1.0, -1.0), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)].map { x, y in
      let p = delta.point(
        Double(bounds.x) + Double(bounds.width) * (x + 1) / 2,
        Double(bounds.y) + Double(bounds.height) * (y + 1) / 2)
      return CGPoint(x: p.x, y: p.y)
    }
  }
  func dragging(handle: Int, from start: CGPoint, to end: CGPoint, shift: Bool, option: Bool)
    -> Self
  {
    var result = self
    if handle == -1 {
      result.centerX += end.x - start.x
      result.centerY += end.y - start.y
      return result
    }
    if handle == 8 {
      let a = atan2(start.y - centerY, start.x - centerX)
      let b = atan2(end.y - centerY, end.x - centerX)
      result.angle += (b - a) * 180 / .pi
      if shift { result.angle = (result.angle / 15).rounded() * 15 }
      return result
    }
    guard (0..<8).contains(handle) else { return result }
    let direction = [(-1.0, -1.0), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)][
      handle]
    let local = Transform2D.rotation(-angle).point(end.x - centerX, end.y - centerY)
    let width = Double(bounds.width) * scaleX / 100
    let height = Double(bounds.height) * scaleY / 100
    let anchorX = option ? 0 : -direction.0 * width / 2
    let anchorY = option ? 0 : -direction.1 * height / 2
    var w = direction.0 == 0 ? width : direction.0 * (local.x - anchorX) * (option ? 2 : 1)
    var h = direction.1 == 0 ? height : direction.1 * (local.y - anchorY) * (option ? 2 : 1)
    if proportional != shift {
      let factor =
        direction.0 == 0
        ? h / height
        : direction.1 == 0 ? w / width : abs(w / width) > abs(h / height) ? w / width : h / height
      w = width * factor
      h = height * factor
    }
    // Crossing a handle flips the content; prevent a singular zero-size transform.
    w = abs(w) < 0.1 ? (w < 0 ? -0.1 : 0.1) : w
    h = abs(h) < 0.1 ? (h < 0 ? -0.1 : 0.1) : h
    result.scaleX = w / Double(bounds.width) * 100
    result.scaleY = h / Double(bounds.height) * 100
    if !option {
      let movement = Transform2D.rotation(angle).point(
        direction.0 * (w - width) / 2, direction.1 * (h - height) / 2)
      result.centerX += movement.x
      result.centerY += movement.y
    }
    return result
  }
}

extension EditorStore {
  func layerBounds(_ layer: Layer) throws -> IntRect {
    if layer.isCanvasFill {
      return IntRect(x: 0, y: 0, width: document.width, height: document.height)
    }
    if layer.isGroup {
      let members = document.subtreeIDs(layer.id)
      let bounds = try document.layers.filter {
        members.contains($0.id) && !$0.isGroup
          && {
            if case .adjustment = $0.content { return false }
            return true
          }($0)
      }.map { try layerBounds($0) }
      guard let first = bounds.first else {
        throw CraftError.invalid("Add layers to this group before transforming it.")
      }
      let x = bounds.reduce(first.x) { min($0, $1.x) }
      let y = bounds.reduce(first.y) { min($0, $1.y) }
      let right = bounds.reduce(first.x + first.width) { max($0, $1.x + $1.width) }
      let bottom = bounds.reduce(first.y + first.height) { max($0, $1.y + $1.height) }
      return IntRect(x: x, y: y, width: right - x, height: bottom - y)
    }
    let pixels = try Renderer.layerSurface(layer, in: document)
    return try layer.coordinateTransform.bounds(width: pixels.width, height: pixels.height)
  }
  var activeLayerBounds: IntRect? { activeLayer.flatMap { try? layerBounds($0) } }
  var canTransformActiveLayer: Bool {
    guard !editingComponent, !editingMask, !geometryBusy, !hasToneDraft,
      transformDraft == nil, let layer = activeLayer, layer.canTransform
    else { return false }
    return !document.isLocked(layer.id)
  }
  func beginTransform() {
    guard !editingMask else {
      error =
        "Mask Free Transform is not available yet. Unlink the mask and use Move to reposition it, or select the layer content to transform the layer."
      return
    }
    guard !editingComponent, !geometryBusy, !hasToneDraft, transformDraft == nil,
      let layer = activeLayer,
      layer.canTransform,
      !document.isLocked(layer.id)
    else {
      return
    }
    do {
      guard document.selection == nil else {
        throw CraftError.unsupported(
          "Deselect before transforming the whole layer. Transforming selected pixels is not available yet."
        )
      }
      transformDraft = TransformDraft(layerID: layer.id, bounds: try layerBounds(layer))
      tool = .move
      status = "Free Transform · Return to apply · Escape to cancel"
    } catch { self.error = error.localizedDescription }
  }
  func updateTransform(_ draft: TransformDraft) {
    guard transformDraft?.layerID == draft.layerID else { return }
    do { try draft.delta.validated() } catch { return }
    transformDraft = draft
    render()
  }
  func cancelTransform() {
    transformDraft = nil
    render()
    status = "Transform cancelled"
  }
  func commitTransform() {
    guard let draft = transformDraft else { return }
    transformDraft = nil
    performGeometry(.transform(draft.layerID, draft.delta, draft.interpolation))
  }
  var previewDocument: CraftDocument {
    var doc = document
    if let draft = layerVisibilityDraft, draft.baseline == document {
      try? LayerOrganization.setVisibility(draft.values, in: &doc)
    }
    if let draft = transformDraft {
      let ids = doc.subtreeIDs(draft.layerID)
      for i in doc.layers.indices where ids.contains(doc.layers[i].id) {
        let old = doc.layers[i]
        let matrix = draft.delta * old.coordinateTransform
        doc.layers[i].x = 0
        doc.layers[i].y = 0
        doc.layers[i].affine = matrix
        if case .gradientFill(var fill) = old.content {
          try? fill.transform(by: draft.delta)
          doc.layers[i].content = .gradientFill(fill)
        }
        if case .patternFill(var fill) = old.content, fill.linked {
          try? fill.transform(by: draft.delta)
          doc.layers[i].content = .patternFill(fill)
        }
        try? doc.layers[i].preserveUnlinkedMask(from: old)
        if old.vectorMask?.linked == true {
          doc.layers[i].vectorMask?.path = old.vectorMask!.path.transformed(draft.delta)
        }
      }
    }
    if let gesture = pathGesture, case .vectorMask(let id) = pathTarget,
      let i = doc.layers.firstIndex(where: { $0.id == id })
    {
      doc.layers[i].vectorMask?.path = gesture.preview
    }
    return doc
  }
  func transformLayer(angle: Double = 0, horizontal: Bool = false, vertical: Bool = false) {
    guard let layer = activeLayer, layer.canTransform, !document.isLocked(layer.id) else { return }
    do {
      let box = try layerBounds(layer)
      let x = Double(box.x) + Double(box.width) / 2
      let y = Double(box.y) + Double(box.height) / 2
      let delta =
        Transform2D.translation(x, y) * .rotation(angle)
        * .scale(horizontal ? -1 : 1, vertical ? -1 : 1) * .translation(-x, -y)
      performGeometry(.transform(layer.id, delta, .bicubic))
    } catch { self.error = error.localizedDescription }
  }
  func performGeometry(_ command: Command, onSuccess: (() -> Void)? = nil) {
    performGeometry(label: command.label, prepare: { _ in command }, onSuccess: onSuccess)
  }
  func performGeometry(
    label: String, prepare: @escaping @Sendable (CraftDocument) throws -> Command,
    onSuccess: (() -> Void)? = nil
  ) {
    guard !geometryBusy, transformDraft == nil, !hasToneDraft else { return }
    guard !editingComponent else {
      error = "This operation requires the RGB editing target."
      return
    }
    let original = document
    let generation = layerPanelGeneration
    geometryBusy = true
    renderTask?.cancel()
    status = label
    geometryTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        try PreparedEdit(command: prepare(original), document: original)
      }
      do {
        let prepared = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard let self, self.layerPanelGeneration == generation else { return }
        try self.executeCompositePreparedEdit(prepared)
        if self.document != original { self.onChange?(.changeDone) }
        onSuccess?()
      } catch is CancellationError {
        if self?.layerPanelGeneration == generation { self?.status = "Operation cancelled" }
      } catch {
        if self?.layerPanelGeneration == generation { self?.error = error.localizedDescription }
      }
      guard let self, self.layerPanelGeneration == generation else { return }
      self.geometryBusy = false
      self.render()
    }
  }
}
