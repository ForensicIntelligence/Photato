import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum PathTarget: Equatable {
  case saved(UUID)
  case vectorMask(UUID)
}
struct PathAnchorSelection: Equatable {
  var component: Int
  var knot: Int
}
struct PathGesture {
  enum Part { case anchor, incoming, outgoing, component, newAnchor }
  var original: VectorPath
  var preview: VectorPath
  var start: PathPoint
  var selection: PathAnchorSelection
  var part: Part
}

extension EditorStore {
  var usesPathTool: Bool { [.pen, .pathSelection, .directSelection].contains(tool) }
  var selectedVectorPath: VectorPath? {
    switch pathTarget {
    case .saved(let id): document.paths?.first { $0.id == id }?.path
    case .vectorMask(let id): document.layers.first { $0.id == id }?.vectorMask?.path
    case nil: nil
    }
  }
  var displayedVectorPath: VectorPath? { pathGesture?.preview ?? selectedVectorPath }
  var pathIsEditable: Bool {
    if case .vectorMask(let id) = pathTarget { return !document.isLocked(id) }
    return true
  }
  func selectPath(_ target: PathTarget?, revealPanel: Bool = true) {
    resetPathGesture()
    pathTarget = target
    maskEditingLayerID = nil
    clearMaskView()
    if case .vectorMask(let id) = target {
      session.selectLayer(id)
      selectedLayerIDs = [id]
    }
    if target != nil && revealPanel { layersTab = .paths }
    // A revision-only redraw would orphan a pending render's completion and leave
    // its busy flag set. Restart that request with the new presentation target.
    if rendering { render() } else { revision += 1 }
  }
  func resetPathGesture() {
    let previewing = pathGesture != nil
    pathGesture = nil
    pathAnchor = nil
    penComponent = nil
    if previewing { render() }
  }
  func commitPath(_ path: VectorPath) {
    guard pathIsEditable else {
      error = "Unlock the layer before editing its vector mask."
      return
    }
    switch pathTarget {
    case .saved(let id):
      guard var saved = document.paths?.first(where: { $0.id == id }) else { return }
      saved.path = path
      perform(.savePath(saved))
    case .vectorMask(let id):
      guard var mask = document.layers.first(where: { $0.id == id })?.vectorMask else { return }
      mask.path = path
      perform(.vectorMask(id, mask))
    case nil: break
    }
  }
  func newPath() {
    let path = NamedPath(
      name: "Path \((document.paths?.filter { !$0.isWorkPath }.count ?? 0) + 1)",
      isWorkPath: false)
    perform(.savePath(path))
    selectPath(.saved(path.id))
    tool = .pen
  }
  func ensureWorkPath() {
    guard selectedVectorPath == nil else { return }
    if let path = document.paths?.first(where: \.isWorkPath) {
      selectPath(.saved(path.id))
      return
    }
    let path = NamedPath()
    perform(.savePath(path))
    selectPath(.saved(path.id))
  }
  func saveSelectedPath(name: String) {
    guard let path = selectedVectorPath, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
      return
    }
    var saved = NamedPath(name: name, path: path, isWorkPath: false)
    if case .saved(let id) = pathTarget { saved.id = id }
    perform(.savePath(saved))
    selectPath(.saved(saved.id))
  }
  func renamePath() {
    guard selectedVectorPath != nil else { return }
    let alert = NSAlert()
    alert.messageText = "Save Path"
    let input = NSTextField(
      string: "Path \((document.paths?.filter { !$0.isWorkPath }.count ?? 0) + 1)")
    input.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
    input.setAccessibilityLabel("Path name")
    alert.accessoryView = input
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = input
    if alert.runModal() == .alertFirstButtonReturn { saveSelectedPath(name: input.stringValue) }
  }
  func deleteSelectedPath() {
    switch pathTarget {
    case .saved(let id): perform(.deletePath(id))
    case .vectorMask(let id): perform(.vectorMask(id, nil))
    case nil: return
    }
    if selectedVectorPath == nil { selectPath(nil) }
  }
  func addVectorMask(reveal: Bool) {
    guard let layer = activeLayer else { return }
    perform(.vectorMask(layer.id, VectorMask(path: VectorPath(inverted: !reveal))))
    if activeLayer?.vectorMask != nil {
      selectPath(.vectorMask(layer.id))
      tool = .directSelection
    }
  }
  func makeVectorMask() {
    guard let layer = activeLayer, let path = selectedVectorPath else { return }
    perform(.vectorMask(layer.id, VectorMask(path: path)))
    if document.layers.first(where: { $0.id == layer.id })?.vectorMask != nil {
      selectPath(.vectorMask(layer.id))
      tool = .directSelection
    }
  }
  func updateVectorMask(_ id: UUID, _ update: (inout VectorMask) -> Void) {
    guard var mask = document.layers.first(where: { $0.id == id })?.vectorMask else { return }
    update(&mask)
    perform(.vectorMask(id, mask))
  }
  func pathToSelection() {
    guard let path = selectedVectorPath else { return }
    do {
      let isVectorMask: Bool
      if case .vectorMask = pathTarget { isVectorMask = true } else { isVectorMask = false }
      let selection = try VectorRasterizer.coverage(
        path, width: document.width, height: document.height,
        antiAlias: selectionAntiAlias, emptyRevealsAll: isVectorMask
      ).feathered(radius: selectionFeather)
      perform(.selectionCoverage(selection, selectionMode))
    } catch { self.error = error.localizedDescription }
  }
  func changePathOperation(_ operation: PathOperation) {
    pathOperation = operation
    guard var path = selectedVectorPath, let anchor = pathAnchor,
      path.components.indices.contains(anchor.component)
    else { return }
    path.components[anchor.component].operation = operation
    commitPath(path)
  }
  func beginPath(at p: PathPoint, tolerance: Double, option: Bool = false) {
    guard !geometryBusy, transformDraft == nil else { return }
    if tool == .pen { ensureWorkPath() }
    guard var path = selectedVectorPath, pathIsEditable else { return }
    pathGesture = nil
    func close(_ q: PathPoint) -> Bool { hypot(q.x - p.x, q.y - p.y) <= tolerance }
    if tool == .pen, let c = penComponent, path.components.indices.contains(c),
      !path.components[c].closed, path.components[c].knots.count >= 2,
      let first = path.components[c].knots.first, close(first.anchor)
    {
      path.components[c].closed = true
      penComponent = nil
      pathAnchor = PathAnchorSelection(component: c, knot: 0)
      commitPath(path)
      return
    }
    var hit: (PathAnchorSelection, PathGesture.Part)?
    // Handles win only for the selected anchor, so nearby hidden handles cannot steal clicks.
    if tool == .directSelection, let a = pathAnchor,
      path.components.indices.contains(a.component),
      path.components[a.component].knots.indices.contains(a.knot)
    {
      let k = path.components[a.component].knots[a.knot]
      if k.incoming != k.anchor && close(k.incoming) {
        hit = (a, .incoming)
      } else if k.outgoing != k.anchor && close(k.outgoing) {
        hit = (a, .outgoing)
      }
    }
    if hit == nil {
      for (c, component) in path.components.enumerated() {
        for (k, knot) in component.knots.enumerated() where close(knot.anchor) {
          hit = (PathAnchorSelection(component: c, knot: k), .anchor)
        }
      }
    }
    if let (anchor, part) = hit {
      pathAnchor = anchor
      if tool != .pen { pathOperation = path.components[anchor.component].operation }
      if tool == .pen {
        if option {
          path.components[anchor.component].knots[anchor.knot] = PathKnot(p)
          commitPath(path)
        } else {
          deletePathAnchor()
        }
        return
      }
      pathGesture = PathGesture(
        original: path, preview: path, start: p, selection: anchor,
        part: tool == .pathSelection ? .component : part)
      return
    }
    if let segment = nearestSegment(in: path, to: p, tolerance: tolerance) {
      pathAnchor = PathAnchorSelection(component: segment.0, knot: segment.1)
      if tool == .pen {
        do {
          try path.components[segment.0].split(segment: segment.1, at: segment.2)
          pathAnchor?.knot += 1
          commitPath(path)
        } catch { self.error = error.localizedDescription }
      } else if tool == .pathSelection, let pathAnchor {
        pathGesture = PathGesture(
          original: path, preview: path, start: p,
          selection: pathAnchor, part: .component)
      }
      return
    }
    guard tool == .pen else {
      pathAnchor = nil
      return
    }
    let c: Int
    if let existing = penComponent, path.components.indices.contains(existing),
      !path.components[existing].closed
    {
      c = existing
    } else {
      c = path.components.count
      path.components.append(PathComponent(operation: pathOperation))
      penComponent = c
    }
    guard path.knotCount < VectorPath.maxKnots, path.components.count <= 256 else {
      error = "Path anchor limit reached."
      return
    }
    let anchor = PathAnchorSelection(component: c, knot: path.components[c].knots.count)
    path.components[c].knots.append(PathKnot(p))
    pathAnchor = anchor
    pathGesture = PathGesture(
      original: path, preview: path, start: p, selection: anchor, part: .newAnchor)
  }
  func nearestSegment(in path: VectorPath, to p: PathPoint, tolerance: Double) -> (
    Int, Int, Double
  )? {
    var best = tolerance * tolerance
    var result: (Int, Int, Double)?
    for (c, component) in path.components.enumerated() where component.knots.count > 1 {
      for segment in 0..<(component.closed ? component.knots.count : component.knots.count - 1) {
        // Coarse bracket then one-dimensional refinement on the original cubic.
        var t = 0.0
        var distance = Double.greatestFiniteMagnitude
        func squared(_ t: Double) -> Double {
          let q = component.point(segment: segment, at: t)!
          return (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)
        }
        for sample in 0...32 {
          let sampleT = Double(sample) / 32
          let d = squared(Double(sample) / 32)
          if d < distance {
            t = sampleT
            distance = d
          }
        }
        var low = max(0, t - 1 / 32.0)
        var high = min(1, t + 1 / 32.0)
        for _ in 0..<16 {
          let a = low + (high - low) / 3
          let b = high - (high - low) / 3
          if squared(a) < squared(b) { high = b } else { low = a }
        }
        t = (low + high) / 2
        distance = squared(t)
        if distance < best {
          best = distance
          result = (c, segment, min(0.9999, max(0.0001, t)))
        }
      }
    }
    return result
  }
  func dragPath(to p: PathPoint, option: Bool = false) {
    guard var gesture = pathGesture, pathIsEditable else { return }
    let a = gesture.selection
    var path = gesture.original
    switch gesture.part {
    case .component:
      let delta = Transform2D.translation(p.x - gesture.start.x, p.y - gesture.start.y)
      path.components[a.component].knots = path.components[a.component].knots.map {
        $0.transformed(delta)
      }
    case .anchor:
      let old = path.components[a.component].knots[a.knot].anchor
      path.components[a.component].knots[a.knot].moveAnchor(
        to: PathPoint(old.x + p.x - gesture.start.x, old.y + p.y - gesture.start.y))
    case .incoming, .outgoing:
      path.components[a.component].knots[a.knot].moveHandle(
        incoming: gesture.part == .incoming,
        to: p, independent: option)
    case .newAnchor:
      let anchor = path.components[a.component].knots[a.knot].anchor
      path.components[a.component].knots[a.knot] = PathKnot(
        anchor,
        incoming: PathPoint(2 * anchor.x - p.x, 2 * anchor.y - p.y), outgoing: p, smooth: true)
    }
    gesture.preview = path
    pathGesture = gesture
    if case .vectorMask = pathTarget { render() } else { revision += 1 }
  }
  func endPathGesture() {
    guard let gesture = pathGesture else { return }
    pathGesture = nil
    commitPath(gesture.preview)
  }
  func finishPath(cancelGesture: Bool = false) {
    if cancelGesture {
      pathGesture = nil
      render()
    } else {
      endPathGesture()
    }
    penComponent = nil
  }
  func deletePathAnchor() {
    guard var path = selectedVectorPath, let a = pathAnchor,
      path.components.indices.contains(a.component),
      path.components[a.component].knots.indices.contains(a.knot)
    else { return }
    path.components[a.component].knots.remove(at: a.knot)
    if path.components[a.component].knots.isEmpty {
      path.components.remove(at: a.component)
      penComponent = nil
    }
    pathAnchor = nil
    commitPath(path)
  }
}
