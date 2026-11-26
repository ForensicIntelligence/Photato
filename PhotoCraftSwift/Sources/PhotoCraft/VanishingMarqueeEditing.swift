import AppKit
import PhotoCraftCore

extension VanishingWorkspace {
  enum PasteDragAction {
    case move, scale(PathPoint), rotate

    func cursor(_ flags: NSEvent.ModifierFlags, dragging: Bool = false) -> ToolCursor {
      switch self {
      case .move:
        if flags.contains(.option) || flags.contains(.shift) {
          return .selectedPixels(copy:flags.contains(.option),constrained:flags.contains(.shift),unsnapped:false)
        }
        return dragging ? .closedHand : .openHand
      case .scale:
        return .symbol("arrow.up.left.and.arrow.down.right",ToolCursor.geometry(flags))
      case .rotate:
        return .symbol("rotate.right",flags.contains(.shift) ? .constrain : nil)
      }
    }
  }

  struct PasteDrag {
    let index: Int
    let original: VanishingOperation
    let action: PasteDragAction
    let start: PathPoint
    let flags: NSEvent.ModifierFlags
  }

  var selectedPasteOperation: VanishingOperation? {
    guard let index = selectedPaste, program.operations.indices.contains(index),
      program.operations[index].kind == .paste else { return nil }
    return program.operations[index]
  }

  func pasteTransformHandles(for operation: VanishingOperation, scene: VanishingScene, scale: Double)
    -> [(action: PasteDragAction, point: PathPoint)]
  {
    guard scene.frames.indices.contains(operation.plane), scale.isFinite, scale > 0 else { return [] }
    let frame = scene.frames[operation.plane]
    guard let geometry = VanishingPasteGeometry(operation,frame:frame),
      let corners = geometry.projectedCorners(in:frame) else { return [] }
    let units = [PathPoint(0,0),.init(1,0),.init(1,1),.init(0,1)]
    var handles = zip(units,corners).map { (PasteDragAction.scale($0.0),$0.1) }
    let top = frame.projected(geometry.point(.init(0.5,0)))
    let center = frame.projected(geometry.point(.init(0.5,0.5)))
    let dx = top.x-center.x, dy = top.y-center.y, length = hypot(dx,dy)
    if length > 1e-8 {
      let offset = 18/(scale*length)
      handles.append((.rotate,.init(top.x+dx*offset,top.y+dy*offset)))
    }
    return handles
  }

  func pasteDrag(at point: PathPoint, flags: NSEvent.ModifierFlags, scene: VanishingScene, scale: Double) -> PasteDrag? {
    guard tool == .transform || tool == .marquee,
      let index = selectedPaste,let operation = selectedPasteOperation,scene.frames.indices.contains(operation.plane) else { return nil }
    let action: PasteDragAction
    if tool == .transform, let closest = pasteTransformHandles(for:operation,scene:scene,scale:scale).map({
      ($0.action,hypot($0.point.x-point.x,$0.point.y-point.y))
    }).min(by:{ $0.1 < $1.1 }),closest.1 <= 8/scale {
      action = closest.0
    } else {
      let frame = scene.frames[operation.plane]
      guard let geometry = VanishingPasteGeometry(operation,frame:frame), !operation.clip || frame.contains(point) else { return nil }
      let unit = geometry.unit(at:frame.metric(point))
      guard (0...1).contains(unit.x), (0...1).contains(unit.y) else { return nil }
      action = .move
    }
    return .init(index:index,original:operation,action:action,start:point,flags:flags)
  }

  func projectedPaste(_ drag: PasteDrag, to point: PathPoint, scene: VanishingScene) -> VanishingOperation? {
    let original = drag.original
    guard scene.frames.indices.contains(original.plane) else { return nil }
    let frame = scene.frames[original.plane]
    guard let geometry = VanishingPasteGeometry(original,frame:frame) else { return nil }
    if point == drag.start { return original }
    var result = original
    let anchor: PathPoint
    switch drag.action {
    case .move:
      var target = point
      if drag.flags.contains(.shift) {
        let start = frame.metric(drag.start), end = frame.metric(point)
        let aligned = abs(end.x-start.x) >= abs(end.y-start.y) ? PathPoint(end.x,start.y) : .init(start.x,end.y)
        target = frame.projected(aligned)
      }
      guard let plane = scene.plane(at:target) else { return nil }
      result.plane = plane
      let destinationFrame = scene.frames[plane]
      let originalOrigin = frame.point(original.at)
      if plane == original.plane {
        let start = frame.uv(drag.start), end = frame.uv(target)
        result.at = .init(original.at.x+end.x-start.x,original.at.y+end.y-start.y)
      } else {
        result.at = destinationFrame.uv(.init(target.x+originalOrigin.x-drag.start.x,target.y+originalOrigin.y-drag.start.y))
      }
      guard let moved = VanishingPasteGeometry(result,frame:destinationFrame),
        moved.projectedCorners(in:destinationFrame) != nil else { return nil }
      return result
    case .scale(let corner):
      anchor = drag.flags.contains(.option) ? .init(0.5,0.5) : .init(1-corner.x,1-corner.y)
      let start = geometry.unit(at:frame.metric(drag.start)), end = geometry.unit(at:frame.metric(point))
      let x = 1+(end.x-start.x)/(corner.x-anchor.x), y = 1+(end.y-start.y)/(corner.y-anchor.y)
      let height = geometry.height/frame.width
      if drag.flags.contains(.shift) {
        let factor = abs(x-1) >= abs(y-1) ? x : y
        let lower = max(0.001/original.width,original.pasteHeight.map { 0.001/$0 } ?? 0)
        let upper = min(20/original.width,original.pasteHeight.map { 20/$0 } ?? .infinity)
        let ratio = min(upper,max(lower,factor))
        result.width = min(20,max(0.001,original.width*ratio))
        result.pasteHeight = original.pasteHeight.map { min(20,max(0.001,$0*ratio)) }
      } else {
        result.width = min(20,max(0.001,original.width*x))
        result.pasteHeight = min(20,max(0.001,height*y))
      }
    case .rotate:
      anchor = .init(0.5,0.5)
      let center = geometry.point(anchor), start = frame.metric(drag.start), end = frame.metric(point)
      guard hypot(start.x-center.x,start.y-center.y) > 1e-8,
        hypot(end.x-center.x,end.y-center.y) > 1e-8 else { return nil }
      let rotation = (atan2(end.y-center.y,end.x-center.x)-atan2(start.y-center.y,start.x-center.x))*180/Double.pi
      let angle = result.angle+rotation
      result.angle = (drag.flags.contains(.shift) ? (angle/15).rounded()*15 : angle).remainder(dividingBy:360)
    }
    guard let resized = VanishingPasteGeometry(result,frame:frame) else { return nil }
    let before = geometry.point(anchor), after = resized.point(anchor)
    result.at = .init(original.at.x+(before.x-after.x)/frame.width,original.at.y+(before.y-after.y)/frame.height)
    guard let projected = VanishingPasteGeometry(result,frame:frame),projected.projectedCorners(in:frame) != nil else { return nil }
    return result
  }

  func finishPasteDrag(_ drag: PasteDrag, at operation: VanishingOperation) {
    guard selectedPaste == drag.index,selectedPasteOperation == drag.original,operation != drag.original else { return }
    var draft = program
    let index: Int
    if case .move = drag.action,drag.flags.contains(.option) {
      index = draft.operations.count
      draft.operations.append(operation)
    } else {
      index = drag.index
      draft.operations[index] = operation
    }
    change(draft)
    if program == draft { selectPaste(index) }
  }

  enum MarqueeAction: Equatable {
    case draw, move, fill, copy, duplicateFloating, moveFloating
  }

  struct MarqueeDrag {
    let action: MarqueeAction
    let start: PathPoint
    let plane: Int
    let original: VanishingMarquee?
    let angle: Double
    let wrap: Bool
  }

  enum MarqueeTransformHandle: Equatable {
    case scale, rotate

    func cursor(constrained: Bool) -> ToolCursor {
      .symbol(self == .rotate ? "rotate.right" : "arrow.up.left.and.arrow.down.right",
        self == .rotate && constrained ? .constrain : nil)
    }
  }

  struct MarqueeTransformDrag {
    let handle: MarqueeTransformHandle
    let previous: VanishingOperation
    let start: PathPoint
    let scale: Double
  }

  func marqueeTransformHandles(for operation: VanishingOperation, scene: VanishingScene, scale: Double)
    -> [(handle: MarqueeTransformHandle, point: PathPoint)]
  {
    guard let rect = operation.marquee?.destination,scale.isFinite,scale > 0 else { return [] }
    let corners = [PathPoint(0,0),.init(1,0),.init(1,1),.init(0,1)]
    var result = corners.compactMap { offset -> (MarqueeTransformHandle,PathPoint)? in
      guard let point = rect.imagePoint(at:offset,in:scene,angle:operation.angle,clip:operation.clip) else { return nil }
      return (.scale,point)
    }
    if let top = rect.imagePoint(at:.init(0.5,0),in:scene,angle:operation.angle,clip:operation.clip),
      let center = rect.imageCenter(in:scene) {
      let dx = top.x-center.x, dy = top.y-center.y
      let distance = hypot(dx,dy)
      if distance > 1e-8 {
        let offset = 18/(scale*distance)
        result.append((.rotate,.init(top.x+dx*offset,top.y+dy*offset)))
      }
    }
    return result
  }

  func marqueeTransform(at point: PathPoint, scene: VanishingScene, scale: Double) -> MarqueeTransformDrag? {
    guard tool == .transform,let operation = floatingMarqueeOperation,let currentScale = floatingMarqueeScale,
      let candidate = marqueeTransformHandles(for:operation,scene:scene,scale:scale).map({
        ($0.handle,hypot(point.x-$0.point.x,point.y-$0.point.y))
      }).min(by:{ $0.1 < $1.1 }),candidate.1 <= 8/scale else { return nil }
    return .init(handle:candidate.0,previous:operation,start:point,scale:currentScale)
  }

  func projectedMarqueeTransform(_ drag: MarqueeTransformDrag, to point: PathPoint,
    constrained: Bool, scene: VanishingScene) -> VanishingOperation?
  {
    if point == drag.start { return drag.previous }
    var result = drag.previous
    guard var patch = result.marquee,
      let start = patch.destination.transformVector(at:drag.start,in:scene),
      let end = patch.destination.transformVector(at:point,in:scene) else { return nil }
    let length = hypot(start.x,start.y)
    guard length > 1e-8 else { return nil }
    switch drag.handle {
    case .scale:
      let scale = min(500,max(1,drag.scale*hypot(end.x,end.y)/length))
      patch.destination = patch.destination.scaled(by:scale/drag.scale)
      result.marquee = patch
    case .rotate:
      guard hypot(end.x,end.y) > 1e-8 else { return nil }
      let rotation = (atan2(end.y,end.x)-atan2(start.y,start.x))*180/Double.pi
      let angle = result.angle + rotation
      result.angle = (constrained ? (angle/15).rounded()*15 : angle).remainder(dividingBy:360)
    }
    guard patch.destination.outlineSegments(in:scene,angle:result.angle,clip:result.clip) != nil else { return nil }
    return result
  }

  func finishMarqueeTransform(_ drag: MarqueeTransformDrag, at operation: VanishingOperation) {
    guard let index = selectedMarqueePatch, floatingMarqueeOperation == drag.previous else { return }
    replaceMarqueePatch(operation,at:index)
  }

  var floatingMarqueeOperation: VanishingOperation? {
    guard let index = selectedMarqueePatch,program.operations.indices.contains(index),
      program.operations[index].kind == .marquee else { return nil }
    return program.operations[index]
  }

  var activeMarquee: VanishingMarquee? { floatingMarqueeOperation?.marquee?.destination ?? marquee }

  func marqueeAction(at point: PathPoint, flags: NSEvent.ModifierFlags, scene: VanishingScene) -> MarqueeAction? {
    let floating = floatingMarqueeOperation
    if let rect = activeMarquee,rect.contains(point,in:scene,angle:floating?.angle ?? 0,clip:floating?.clip ?? clip) {
      if floating != nil { return flags.contains(.option) ? .duplicateFloating : .moveFloating }
      if flags.contains(.command) && flags.contains(.option) { return .copy }
      if flags.contains(.command) { return .fill }
      if flags.contains(.option) { return .copy }
      return marqueeMoveMode == .source ? .fill : .move
    }
    return tool == .marquee && scene.plane(at:point) != nil ? .draw : nil
  }

  func startMarqueeDrag(at point: PathPoint, flags: NSEvent.ModifierFlags, scene: VanishingScene) -> MarqueeDrag? {
    guard let action = marqueeAction(at:point,flags:flags,scene:scene) else {
      if tool == .marquee { marquee = nil; selectedMarqueePatch = nil }
      return nil
    }
    let original = activeMarquee
    let angle = floatingMarqueeOperation?.angle ?? 0
    if action == .draw, let plane = scene.plane(at:point) {
      selected = plane
      marquee = nil
      selectedMarqueePatch = nil
      return .init(action:action,start:point,plane:plane,original:nil,angle:0,wrap:allowMultiSurfaceOperations)
    }
    guard let original else { return nil }
    return .init(action:action,start:point,plane:original.plane,original:original,angle:angle,wrap:original.wrap == true)
  }

  func projectedMarquee(for drag: MarqueeDrag, to point: PathPoint, constrained: Bool,
    scene: VanishingScene) -> VanishingMarquee?
  {
    if drag.action == .draw {
      return scene.marquee(plane:drag.plane,from:drag.start,to:point,square:constrained,wrap:drag.wrap)
    }
    return drag.original?.moved(from:drag.start,to:point,plane:scene.plane(at:point) ?? drag.plane,
      scene:scene,constrained:constrained,angle:drag.angle)
  }

  func finishMarqueeDrag(_ drag: MarqueeDrag, at rect: VanishingMarquee) {
    switch drag.action {
    case .draw,.move:
      marquee = rect
      selected = rect.plane
    case .fill:
      if let destination = drag.original { addMarqueePatch(source:rect,destination:destination) }
    case .copy:
      if let source = drag.original { addMarqueePatch(source:source,destination:rect) }
    case .moveFloating,.duplicateFloating:
      guard let index = selectedMarqueePatch,var operation = floatingMarqueeOperation,
        var patch = operation.marquee else { return }
      patch.destination = rect
      operation.plane = rect.plane
      operation.marquee = patch
      replaceMarqueePatch(operation,at:drag.action == .moveFloating ? index : nil)
    }
  }

  func selectMarqueePlane(_ plane: Int) {
    guard program.settings.planes.indices.contains(plane) else { return }
    beginGesture()
    selectedMarqueePatch = nil
    selected = plane
    let wraps = allowMultiSurfaceOperations && scene?.hasMarqueeNeighbors(plane) == true
    marquee = .init(plane:plane,lower:.init(0,0),upper:.init(1,1),wrap:wraps ? true : nil)
    endGesture()
  }

  func deselectMarquee() {
    beginGesture()
    selectedMarqueePatch = nil
    marquee = nil
    endGesture()
  }

  func floatMarquee() {
    guard let rect = marquee else { return }
    beginGesture()
    addMarqueePatch(source:rect,destination:rect)
    endGesture()
  }

  func nudgeMarquee(dx: Double, dy: Double) {
    guard let rect = activeMarquee,let scene,let center = rect.imageCenter(in:scene) else { return }
    let cursor = PathPoint(center.x+dx,center.y+dy)
    let face = rect.wrap == true ? scene.marqueePlane(at:cursor,relativeTo:rect.plane) ?? rect.plane : rect.plane
    guard let moved = rect.moved(from:center,to:cursor,plane:face,
      scene:scene,angle:floatingMarqueeOperation?.angle ?? 0) else { return }
    beginGesture()
    let action: MarqueeAction = floatingMarqueeOperation == nil ? .move : .moveFloating
    finishMarqueeDrag(.init(action:action,start:center,plane:rect.plane,original:rect,angle:0,wrap:rect.wrap == true),at:moved)
    endGesture()
  }

  var floatingMarqueeScale: Double? {
    guard let patch = floatingMarqueeOperation?.marquee,let scene else { return nil }
    let original = (patch.source.upper.x-patch.source.lower.x)*scene.measurementMetric(for:patch.source.plane).x
    let current = (patch.destination.upper.x-patch.destination.lower.x)*scene.measurementMetric(for:patch.destination.plane).x
    return original > 0 ? 100*current/original : nil
  }

  func resizeMarqueePatch(to scale: Double) {
    guard let current = floatingMarqueeScale,scale.isFinite,current > 0 else { return }
    updateMarqueePatch { op in
      if var patch = op.marquee {
        patch.destination = patch.destination.scaled(by:scale/current)
        op.marquee = patch
      }
    }
  }

  func updateMarqueePatch(_ edit: (inout VanishingOperation) -> Void) {
    guard let index = selectedMarqueePatch,var op = floatingMarqueeOperation else { return }
    edit(&op)
    replaceMarqueePatch(op,at:index)
  }

  private func addMarqueePatch(source: VanishingMarquee, destination: VanishingMarquee) {
    var op = VanishingOperation(.marquee)
    op.plane = destination.plane
    op.marquee = .init(source:source,destination:destination,feather:marqueeFeather)
    op.clip = clip
    op.opacity = marqueeOpacity
    op.heal = marqueeHeal == .off ? nil : marqueeHeal
    replaceMarqueePatch(op,at:nil)
  }

  private func replaceMarqueePatch(_ operation: VanishingOperation, at index: Int?) {
    guard let scene,let patch = operation.marquee,
      patch.destination.outlineSegments(in:scene,angle:operation.angle,clip:operation.clip) != nil,
      patch.source.outlineSegments(in:scene,angle:0,clip:operation.clip) != nil else { return }
    var draft = program
    let updated = index ?? draft.operations.count
    if let index { draft.operations[index] = operation } else { draft.operations.append(operation) }
    change(draft)
    guard program == draft else { return }
    selected = operation.plane
    marquee = nil
    selectedPaste = nil
    selectedMarqueePatch = updated
  }
}
