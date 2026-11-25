import AppKit
import PhotoCraftCore

extension VanishingWorkspace {
  enum MarqueeAction: Equatable {
    case draw, move, fill, copy, duplicateFloating, moveFloating
  }

  struct MarqueeDrag {
    let action: MarqueeAction
    let start: PathPoint
    let plane: Int
    let original: VanishingMarquee?
    let angle: Double
  }

  var floatingMarqueeOperation: VanishingOperation? {
    guard let index = selectedMarqueePatch,program.operations.indices.contains(index),
      program.operations[index].kind == .marquee else { return nil }
    return program.operations[index]
  }

  var activeMarquee: VanishingMarquee? { floatingMarqueeOperation?.marquee?.destination ?? marquee }

  func marqueeAction(at point: PathPoint, flags: NSEvent.ModifierFlags, scene: VanishingScene) -> MarqueeAction? {
    let floating = floatingMarqueeOperation
    if let rect = activeMarquee,rect.contains(point,in:scene,angle:floating?.angle ?? 0) {
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
      return .init(action:action,start:point,plane:plane,original:nil,angle:0)
    }
    guard let original else { return nil }
    return .init(action:action,start:point,plane:original.plane,original:original,angle:angle)
  }

  func projectedMarquee(for drag: MarqueeDrag, to point: PathPoint, constrained: Bool,
    scene: VanishingScene) -> VanishingMarquee?
  {
    if drag.action == .draw {
      return scene.marquee(plane:drag.plane,from:drag.start,to:point,square:constrained)
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
    marquee = .init(plane:plane,lower:.init(0,0),upper:.init(1,1))
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
    guard let rect = activeMarquee,let scene else { return }
    let center = scene.frames[rect.plane].point(rect.center)
    guard let moved = rect.moved(from:center,to:.init(center.x+dx,center.y+dy),plane:rect.plane,
      scene:scene,angle:floatingMarqueeOperation?.angle ?? 0) else { return }
    beginGesture()
    let action: MarqueeAction = floatingMarqueeOperation == nil ? .move : .moveFloating
    finishMarqueeDrag(.init(action:action,start:center,plane:rect.plane,original:rect,angle:0),at:moved)
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
      patch.destination.projectedCorners(in:scene,angle:operation.angle) != nil,
      patch.source.projectedCorners(in:scene) != nil else { return }
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
