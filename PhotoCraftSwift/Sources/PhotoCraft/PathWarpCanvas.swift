import AppKit
import PhotoCraftCore

enum PathWarpHandle {
  case mesh(Int)
  case cylinder(CylinderHandle)
}

struct PathWarpGesture {
  let modelID: UUID
  let handle: PathWarpHandle
  let start: PathPoint
  let documentStart: CGPoint
  let offset: PathPoint
}

extension CraftCanvas {
  var pathWarpCursor: ToolCursor {
    guard let model = store.pathWarp, model.showGuides else { return .arrow }
    let active = pathWarpGesture.flatMap { $0.modelID == model.id ? $0.handle : nil }
    let handle = active ?? cursorLocationInView.flatMap { pathWarpHandle(in: model, at: $0) }
    switch handle {
    case .cylinder(let handle): return .cylinderWarp(handle, dragging: active != nil, flags: cursorModifiers)
    case .mesh: return .meshWarp(overControl: true, dragging: active != nil)
    case nil: return .arrow
    }
  }

  private func warpViewPoint(_ point: PathPoint, in model: WarpWorkspace) -> CGPoint? {
    if model.pathProjection == .identity { return viewPoint(.init(x: point.x, y: point.y)) }
    guard let projected = try? model.pathProjection.point(point.x, point.y) else { return nil }
    return viewPoint(.init(x: projected.x, y: projected.y))
  }

  private func pathWarpHandle(in model: WarpWorkspace, at location: CGPoint) -> PathWarpHandle? {
    if let cylinder = model.settings.cylinder {
      return CylinderHandle.hit(location, cylinder: cylinder) {
        warpViewPoint($0, in: model)
      }.map(PathWarpHandle.cylinder)
    }
    let controls = model.controls?.points ?? []
    var closest: Int?
    var distance = 11.0
    for (index, control) in controls.enumerated() {
      guard let point = warpViewPoint(control, in: model) else { continue }
      let candidate = hypot(point.x - location.x, point.y - location.y)
      if candidate < distance { closest = index; distance = candidate }
    }
    return closest.map(PathWarpHandle.mesh)
  }

  func startPathWarpGesture(_ event: NSEvent) {
    guard let model = store.pathWarp, model.showGuides,
          let location = cursorLocationInView, let handle = pathWarpHandle(in: model, at: location) else { return }
    let documentPoint = docPoint(event)
    guard let point = try? model.inversePathProjection.point(documentPoint.x, documentPoint.y) else { return }
    var offset = PathPoint(0, 0)
    if case .mesh(let index) = handle, let control = model.controls?.points[index] {
      offset = .init(control.x - point.x, control.y - point.y)
      model.selectedPoint = index
    }
    pathWarpGesture = .init(modelID: model.id, handle: handle, start: point, documentStart: documentPoint, offset: offset)
    model.beginGesture()
    needsDisplay = true
  }

  func updatePathWarpGesture(_ event: NSEvent) {
    updatePathWarpGesture(to: docPoint(event), modifiers: event.modifierFlags)
  }

  func updatePathWarpGesture(to location: CGPoint, modifiers: NSEvent.ModifierFlags) {
    guard let model = store.pathWarp, let gesture = pathWarpGesture, gesture.modelID == model.id,
          let point = try? model.inversePathProjection.point(location.x, location.y) else { return }
    switch gesture.handle {
    case .mesh(let index):
      model.drag(index, to: .init(point.x + gesture.offset.x, point.y + gesture.offset.y))
    case .cylinder(let handle):
      model.dragCylinder(handle, from: gesture.start, to: point,
                         constrain: ToolCursor.cylinderConstrained(handle, flags: modifiers))
    }
  }

  func finishPathWarpGesture() {
    if let gesture = pathWarpGesture, let model = store.pathWarp, model.id == gesture.modelID {
      model.endGesture()
    }
    pathWarpGesture = nil
  }

  func drawPathWarp(in context: CGContext) {
    guard let model = store.pathWarp, model.showGuides else { return }
    context.saveGState()
    defer { context.restoreGState() }
    context.setStrokeColor(NSColor.systemCyan.cgColor)
    context.setLineWidth(1)
    let cylinder = model.settings.cylinder
    let surface = cylinder?.surface
    for vertical in [true, false] {
      let split = model.settings.mesh.map { vertical ? $0.us : $0.vs } ?? [0, 1.0 / 3, 2.0 / 3, 1]
      for fixed in split {
        var previousSide: FloatingPointSign?
        let projection = model.pathProjection.values
        for step in 0...48 {
          let varying = Double(step) / 48
          let u = vertical ? fixed : varying, v = vertical ? varying : fixed
          let point = surface.map { $0.point($0.firstVisibleU + u * ($0.lastVisibleU - $0.firstVisibleU), v) }
            ?? model.guidePoint(u, v)
          guard let view = warpViewPoint(point, in: model) else { previousSide = nil; continue }
          let side = (projection[6] * point.x + projection[7] * point.y + projection[8]).sign
          if previousSide == side { context.addLine(to: view) } else { context.move(to: view) }
          previousSide = side
        }
      }
    }
    context.strokePath()
    if let cylinder {
      for handle in CylinderHandle.allCases {
        guard let control = handle.point(on: cylinder), let point = warpViewPoint(control, in: model) else { continue }
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: .init(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
      }
      return
    }
    for (index, control) in (model.controls?.points ?? []).enumerated() {
      guard let point = warpViewPoint(control, in: model) else { continue }
      context.setFillColor((index == model.selectedPoint ? NSColor.systemOrange : NSColor.white).cgColor)
      context.fillEllipse(in: .init(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
    }
  }

  func pathWarpMenu() -> NSMenu? {
    guard store.pathWarp != nil else { return nil }
    let menu = NSMenu()
    menu.autoenablesItems = false
    let item = NSMenuItem(title: "Free Transform", action: #selector(returnFromWarpMenu(_:)), keyEquivalent: "")
    item.target = self
    item.isEnabled = store.canReturnToPathTransform
    menu.addItem(item)
    return menu
  }

  @objc func returnFromWarpMenu(_ item: NSMenuItem) {
    store.returnToPathTransform()
    refreshToolCursor()
  }
}
