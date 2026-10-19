import AppKit
import PhotoCraftCore

enum GradientToolMode: String, CaseIterable {
  case live = "Gradient"
  case classic = "Classic Gradient"
}

struct GradientToolOptions {
  var mode = GradientToolMode.live
  var gradient = GradientDefinition.foregroundToBackground
  var style = GradientStyle.linear
  var reverse = false
  var dither = true
  var transparency = true
  var opacity: Float = 1
  var blend = PhotoCraftCore.BlendMode.normal
}

enum GradientGrip: Equatable {
  case start, end
  case color(Int)
  case midpoint(Int)
  case line(Float)
}

struct GradientWidget {
  var layer: Layer
  var fill: GradientFill
  var frame: IntRect
  var start: PathPoint
  var end: PathPoint
  init(layer: Layer, fill: GradientFill, frame: IntRect) throws {
    self.layer = layer
    self.fill = fill
    // Stable ordering also makes coincident stops predictable.
    self.fill.gradient.colors = fill.gradient.colors.enumerated().sorted {
      $0.element.position == $1.element.position
        ? $0.offset < $1.offset
        : $0.element.position < $1.element.position
    }.map(\.element)
    self.frame = frame
    (start, end) = try fill.placement.handles(in: frame)
  }
  func point(_ t: Float) -> PathPoint {
    let u = Double(fill.placement.reverse ? 1 - t : t)
    return .init(start.x + (end.x - start.x) * u, start.y + (end.y - start.y) * u)
  }
  func projection(_ p: PathPoint) -> (t: Float, distance: Double) {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length2 = dx * dx + dy * dy
    let u =
      length2 > 1e-9
      ? max(0, min(1, ((p.x - start.x) * dx + (p.y - start.y) * dy) / length2)) : 0
    let distance = hypot(p.x - start.x - u * dx, p.y - start.y - u * dy)
    return (Float(fill.placement.reverse ? 1 - u : u), distance)
  }
  func midpoint(_ index: Int) -> Float? {
    let stops = fill.gradient.colors
    guard index > 0, stops.indices.contains(index) else { return nil }
    let a = stops[index - 1].position
    let b = stops[index].position
    return b - a > 1e-4 ? a + (b - a) * stops[index].midpoint : nil
  }
  func hit(_ p: PathPoint, tolerance: Double) -> GradientGrip? {
    func near(_ q: PathPoint) -> Bool { hypot(p.x - q.x, p.y - q.y) <= tolerance }
    if near(end) { return .end }
    if near(start) { return .start }
    for (i, stop) in fill.gradient.colors.enumerated() where near(point(stop.position)) {
      return .color(i)
    }
    for i in fill.gradient.colors.indices {
      if let t = midpoint(i), near(point(t)) { return .midpoint(i) }
    }
    let projection = projection(p)
    return projection.distance <= tolerance ? .line(projection.t) : nil
  }
}

struct GradientGesture {
  let down: PathPoint
  let zoom: Double
  let clickCount: Int
  let original: GradientWidget?
  let grip: GradientGrip?
  var layer: Layer
  var fill: GradientFill?
  var stroke: GradientStroke?
  var frame: IntRect
  var creating = false
  var createMask = false
  var moved = false
  var stopIndex: Int?
  var command: Command? {
    guard moved else { return nil }
    if let stroke { return .paintGradient(layer.id, stroke) }
    guard let fill else { return nil }
    if creating {
      var layer = layer
      layer.content = .gradientFill(fill)
      return .addGradientFill(layer, createMask)
    }
    return .setGradientFill(layer.id, fill)
  }
}

struct GradientStopColorDraft: Identifiable {
  let id: UUID
  var fill: GradientFill
  let index: Int
  var command: Command { .setGradientFill(id, fill) }
}

extension EditorStore {
  var liveGradientMode: Bool {
    guard gradientOptions.mode == .live else { return false }
    if !editingMask { return true }
    if case .gradientFill = activeLayer?.content { return activeLayer?.visible == true }
    return false
  }
  var activeGradientWidget: GradientWidget? {
    guard tool == .gradient, liveGradientMode, let layer = activeLayer, layer.visible,
      case .gradientFill(let fill) = layer.content
    else { return nil }
    do {
      let frame: IntRect
      if let cache = gradientFrameCache, cache.layer == layer,
        cache.width == document.width, cache.height == document.height
      {
        frame = cache.frame
      } else {
        frame = try fill.frame(for: layer, width: document.width, height: document.height)
        gradientFrameCache = (layer, document.width, document.height, frame)
      }
      return try GradientWidget(layer: layer, fill: fill, frame: frame)
    } catch { return nil }
  }
  var shownGradientWidget: GradientWidget? {
    guard tool == .gradient, gradientFillDraft == nil, patternFillDraft == nil,
      transformDraft == nil
    else { return nil }
    if let draft = gradientGesture, let fill = draft.fill, draft.moved {
      return try? GradientWidget(layer: draft.layer, fill: fill, frame: draft.frame)
    }
    return activeGradientWidget
  }
  var toolGradient: GradientDefinition {
    activeGradientWidget?.fill.gradient
      ?? ((try? gradientOptions.gradient.resolved(
        foreground: brush.color, background: backgroundColor))
        ?? .blackToWhite)
  }
  static func snapGradient(_ p: PathPoint, from origin: PathPoint) -> PathPoint {
    let dx = p.x - origin.x
    let dy = p.y - origin.y
    guard hypot(dx, dy) >= 1e-9 else { return p }
    let step = Double.pi / 4
    let angle = (atan2(dy, dx) / step).rounded() * step
    let x = cos(angle)
    let y = sin(angle)
    let length = dx * x + dy * y
    return .init(origin.x + x * length, origin.y + y * length)
  }
  func beginGradient(at point: PathPoint, zoom: Double, clickCount: Int = 1) {
    guard tool == .gradient, !geometryBusy, !hasToneDraft, transformDraft == nil,
      zoom.isFinite, zoom > 0,
      [point.x, point.y].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 })
    else { return }
    do {
      let canvas = IntRect(x: 0, y: 0, width: document.width, height: document.height)
      if liveGradientMode {
        if let widget = activeGradientWidget {
          guard !document.isLocked(widget.layer.id) else {
            throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
          }
          let grip = widget.hit(point, tolerance: 8 / zoom)
          gradientGesture = .init(
            down: point, zoom: zoom, clickCount: clickCount, original: widget, grip: grip,
            layer: widget.layer, fill: widget.fill, frame: widget.frame)
        } else {
          let parent = activeLayer.flatMap { $0.isGroup ? $0.id : $0.parentID }
          guard parent.map({ !document.isLocked($0) }) ?? true else {
            throw CraftError.invalid("Unlock this group before adding a gradient.")
          }
          var fill = GradientFill(
            gradient: try gradientOptions.gradient.resolved(
              foreground: brush.color, background: backgroundColor), aligned: false,
            dither: gradientOptions.dither)
          fill.placement.style = gradientOptions.style
          fill.placement.reverse = gradientOptions.reverse
          var layer = Layer(name: "Gradient Fill", content: .gradientFill(fill))
          layer.opacity = gradientOptions.opacity
          layer.blendMode = gradientOptions.blend
          gradientGesture = .init(
            down: point, zoom: zoom, clickCount: clickCount, original: nil, grip: nil,
            layer: layer, fill: fill, frame: canvas, creating: true,
            createMask: document.selection != nil)
        }
      } else {
        guard let layer = activeLayer else {
          throw CraftError.invalid("Select a pixel layer first.")
        }
        guard !document.isLocked(layer.id) else {
          throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
        }
        if !editingMask, case .raster = layer.content {
        } else if !editingMask {
          throw CraftError.unsupported("Rasterize this layer before using Classic Gradient.")
        }
        var stroke = GradientStroke(
          gradient: try gradientOptions.gradient.resolved(
            foreground: brush.color, background: backgroundColor), start: point, end: point)
        stroke.style = gradientOptions.style
        stroke.reverse = gradientOptions.reverse
        stroke.dither = gradientOptions.dither
        stroke.transparency = gradientOptions.transparency
        stroke.opacity = gradientOptions.opacity
        stroke.mode = gradientOptions.blend
        stroke.mask = editingMask
        gradientGesture = .init(
          down: point, zoom: zoom, clickCount: clickCount, original: nil, grip: nil,
          layer: layer, stroke: stroke, frame: canvas)
      }
      status = "Gradient · Shift constrains angle · Esc cancels"
    } catch { self.error = error.localizedDescription }
  }
  func dragGradient(to point: PathPoint, shift: Bool = false) {
    guard var draft = gradientGesture,
      [point.x, point.y].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 })
    else { return }
    do {
      draft.moved = hypot(point.x - draft.down.x, point.y - draft.down.y) * draft.zoom >= 2
      if var stroke = draft.stroke {
        stroke.end = shift ? Self.snapGradient(point, from: draft.down) : point
        draft.stroke = stroke
      } else if var fill = draft.original?.fill ?? draft.fill {
        if let widget = draft.original, let grip = draft.grip {
          switch grip {
          case .start, .end:
            let fixed = grip == .start ? widget.end : widget.start
            let p = shift ? Self.snapGradient(point, from: fixed) : point
            try fill.placement.setHandles(
              start: grip == .start ? p : fixed, end: grip == .end ? p : fixed, in: draft.frame)
          case .line:
            let dx = point.x - draft.down.x
            let dy = point.y - draft.down.y
            try fill.placement.setHandles(
              start: .init(widget.start.x + dx, widget.start.y + dy),
              end: .init(widget.end.x + dx, widget.end.y + dy), in: draft.frame)
          case .color(let index):
            let projection = widget.projection(point)
            if projection.distance * draft.zoom > 36, fill.gradient.colors.count > 2 {
              fill.gradient.colors.remove(at: index)
              draft.stopIndex = nil
            } else {
              fill.gradient.colors[index].position = projection.t
              let order = fill.gradient.colors.indices.sorted {
                let a = fill.gradient.colors[$0].position
                let b = fill.gradient.colors[$1].position
                return a == b ? $0 < $1 : a < b
              }
              draft.stopIndex = order.firstIndex(of: index)
              fill.gradient.colors = order.map { fill.gradient.colors[$0] }
            }
          case .midpoint(let index):
            let a = fill.gradient.colors[index - 1].position
            let b = fill.gradient.colors[index].position
            if b > a {
              fill.gradient.colors[index].midpoint = max(
                0.05,
                min(
                  0.95,
                  (widget.projection(point).t - a) / (b - a)))
            }
          }
        } else {
          let end = shift ? Self.snapGradient(point, from: draft.down) : point
          try fill.placement.setHandles(start: draft.down, end: end, in: draft.frame)
        }
        try fill.validate()
        draft.fill = fill
      }
      gradientGesture = draft
      render()
    } catch { self.error = error.localizedDescription }
  }
  func finishGradient() {
    guard let draft = gradientGesture else { return }
    gradientGesture = nil
    if let command = draft.command {
      gradientSelectedStop = draft.stopIndex.map { (draft.layer.id, $0) }
      performGeometry(command)
    } else if let widget = draft.original, let grip = draft.grip {
      switch grip {
      case .line(let t):
        guard widget.fill.gradient.colors.count < GradientDefinition.maxStops else { return }
        do {
          var fill = widget.fill
          let color = try GradientRamp(fill.gradient).sample(t)
          let index =
            fill.gradient.colors.firstIndex { $0.position > t } ?? fill.gradient.colors.count
          fill.gradient.colors.insert(.init(t, .rgb(Pixel(color.r, color.g, color.b))), at: index)
          gradientSelectedStop = (widget.layer.id, index)
          performGeometry(.setGradientFill(widget.layer.id, fill))
        } catch { self.error = error.localizedDescription }
      case .color(let i): selectGradientStop(widget, index: i, edit: draft.clickCount >= 2)
      case .start, .end:
        let first = (grip == .start) != widget.fill.placement.reverse
        selectGradientStop(
          widget, index: first ? 0 : widget.fill.gradient.colors.count - 1,
          edit: draft.clickCount >= 2)
      case .midpoint: break
      }
    } else {
      render()
    }
  }
  func cancelGradientGesture() {
    guard gradientGesture != nil else { return }
    gradientGesture = nil
    status = "Gradient cancelled"
    render()
  }
  private func selectGradientStop(_ widget: GradientWidget, index: Int, edit: Bool) {
    guard widget.fill.gradient.colors.indices.contains(index) else { return }
    gradientSelectedStop = (widget.layer.id, index)
    if edit {
      gradientStopColorDraft = .init(id: widget.layer.id, fill: widget.fill, index: index)
    }
  }
  func editSelectedGradientStop() {
    guard !hasToneDraft, !geometryBusy, let widget = activeGradientWidget,
      !document.isLocked(widget.layer.id), let selected = gradientSelectedStop,
      selected.id == widget.layer.id
    else { return }
    selectGradientStop(widget, index: selected.index, edit: true)
  }
  @discardableResult func deleteGradientStop() -> Bool {
    guard tool == .gradient, liveGradientMode, !hasToneDraft, !geometryBusy,
      let widget = activeGradientWidget, let selected = gradientSelectedStop,
      selected.id == widget.layer.id
    else { return false }
    guard !document.isLocked(widget.layer.id), widget.fill.gradient.colors.count > 2,
      widget.fill.gradient.colors.indices.contains(selected.index)
    else { return true }
    var fill = widget.fill
    fill.gradient.colors.remove(at: selected.index)
    gradientSelectedStop = nil
    performGeometry(.setGradientFill(widget.layer.id, fill))
    return true
  }
  func finishGradientStopColor(apply: Bool) {
    guard let draft = gradientStopColorDraft else { return }
    gradientStopColorDraft = nil
    if apply { performGeometry(draft.command) } else { render() }
  }
  func changeGradientOption<T>(_ key: WritableKeyPath<GradientToolOptions, T>, _ value: T) {
    guard !geometryBusy, !hasToneDraft else { return }
    gradientOptions[keyPath: key] = value
    guard key != \GradientToolOptions.mode, let widget = activeGradientWidget else { return }
    var fill = widget.fill
    do {
      switch key {
      case \GradientToolOptions.gradient:
        fill.gradient = try gradientOptions.gradient.resolved(
          foreground: brush.color, background: backgroundColor)
        gradientSelectedStop = nil
      case \GradientToolOptions.style:
        fill.placement.style = gradientOptions.style
        try fill.placement.setHandles(start: widget.start, end: widget.end, in: widget.frame)
      case \GradientToolOptions.reverse: fill.placement.reverse = gradientOptions.reverse
      case \GradientToolOptions.dither: fill.dither = gradientOptions.dither
      case \GradientToolOptions.opacity:
        performGeometry(.opacity(widget.layer.id, gradientOptions.opacity))
        return
      case \GradientToolOptions.blend:
        performGeometry(.blend(widget.layer.id, gradientOptions.blend))
        return
      default: return
      }
      performGeometry(.setGradientFill(widget.layer.id, fill))
    } catch { self.error = error.localizedDescription }
  }
  func changeGradientMethod(_ method: GradientMethod) {
    guard !geometryBusy, !hasToneDraft else { return }
    gradientOptions.gradient.method = method
    if let widget = activeGradientWidget {
      var fill = widget.fill
      fill.gradient.method = method
      performGeometry(.setGradientFill(widget.layer.id, fill))
    }
  }
}
