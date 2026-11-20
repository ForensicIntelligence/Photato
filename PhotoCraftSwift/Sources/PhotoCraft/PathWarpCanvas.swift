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

  private func warpViewPoint(_ point: PathPoint) -> CGPoint {
    viewPoint(.init(x: point.x, y: point.y))
  }

  private func pathWarpHandle(in model: WarpWorkspace, at location: CGPoint) -> PathWarpHandle? {
    if let cylinder = model.settings.cylinder {
      return CylinderHandle.hit(location, cylinder: cylinder, project: warpViewPoint).map(PathWarpHandle.cylinder)
    }
    let controls = model.controls?.points ?? []
    var closest: Int?
    var distance = 11.0
    for (index, control) in controls.enumerated() {
      let point = warpViewPoint(control)
      let candidate = hypot(point.x - location.x, point.y - location.y)
      if candidate < distance { closest = index; distance = candidate }
    }
    return closest.map(PathWarpHandle.mesh)
  }

  func startPathWarpGesture(_ event: NSEvent) {
    guard let model = store.pathWarp, model.showGuides,
          let location = cursorLocationInView, let handle = pathWarpHandle(in: model, at: location) else { return }
    let point = docPoint(event)
    var offset = PathPoint(0, 0)
    if case .mesh(let index) = handle, let control = model.controls?.points[index] {
      offset = .init(control.x - point.x, control.y - point.y)
      model.selectedPoint = index
    }
    pathWarpGesture = .init(modelID: model.id, handle: handle, start: .init(point.x, point.y), offset: offset)
    model.beginGesture()
    needsDisplay = true
  }

  func updatePathWarpGesture(_ event: NSEvent) {
    updatePathWarpGesture(to: docPoint(event), modifiers: event.modifierFlags)
  }

  func updatePathWarpGesture(to location: CGPoint, modifiers: NSEvent.ModifierFlags) {
    guard let model = store.pathWarp, let gesture = pathWarpGesture, gesture.modelID == model.id else { return }
    switch gesture.handle {
    case .mesh(let index):
      model.drag(index, to: .init(location.x + gesture.offset.x, location.y + gesture.offset.y))
    case .cylinder(let handle):
      model.dragCylinder(handle, from: gesture.start, to: .init(location.x, location.y),
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
        let points = (0...48).map { step in
          let varying = Double(step) / 48
          let u = vertical ? fixed : varying, v = vertical ? varying : fixed
          let point = surface.map { $0.point($0.firstVisibleU + u * ($0.lastVisibleU - $0.firstVisibleU), v) }
            ?? model.guidePoint(u, v)
          return warpViewPoint(point)
        }
        context.addLines(between: points)
      }
    }
    context.strokePath()
    if let cylinder {
      for handle in CylinderHandle.allCases {
        guard let control = handle.point(on: cylinder) else { continue }
        let point = warpViewPoint(control)
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: .init(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
      }
      return
    }
    for (index, control) in (model.controls?.points ?? []).enumerated() {
      let point = warpViewPoint(control)
      context.setFillColor((index == model.selectedPoint ? NSColor.systemOrange : NSColor.white).cgColor)
      context.fillEllipse(in: .init(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
    }
  }
}
