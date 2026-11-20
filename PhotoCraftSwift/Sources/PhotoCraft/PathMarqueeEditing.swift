import AppKit
import PhotoCraftCore

struct PathMarqueeGesture {
  let target: PathTarget
  let path: VectorPath
  let selection: PathTransformSelection
  let start: PathPoint
  let extending: Bool
  var end: PathPoint
  var dragging = false
  var preview: PathTransformSelection?
}

@MainActor extension EditorStore {
  func beginPathMarquee(at point: PathPoint, path: VectorPath, extending: Bool) {
    guard let target = pathTarget else { return }
    pathMarquee = .init(target: target, path: path, selection: pathTransformSelection,
                        start: point, extending: extending, end: point)
  }

  func updatePathMarquee(to point: PathPoint, scale: Double) {
    guard var marquee = pathMarquee else { return }
    marquee.end = point
    marquee.dragging = marquee.dragging || hypot(point.x - marquee.start.x, point.y - marquee.start.y) * scale >= 3
    if marquee.dragging {
      marquee.preview = PathMarqueeSelection(start: marquee.start, end: point)
        .selection(in: marquee.path, extending: marquee.extending ? marquee.selection : nil)
    }
    pathMarquee = marquee
  }

  func finishPathMarquee() {
    guard let marquee = pathMarquee else { return }
    pathMarquee = nil
    guard tool == .directSelection, pathTarget == marquee.target, selectedVectorPath == marquee.path,
          pathTransformSelection == marquee.selection else { return }
    if let selection = marquee.preview {
      applyMarqueeSelection(selection)
    } else if !marquee.extending {
      applyMarqueeSelection(.anchors([]))
    }
    if pathTransformSelection != marquee.selection {
      if rendering { render() } else { revision += 1 }
    }
  }

  func cancelPathMarquee() { pathMarquee = nil }

  func applyMarqueeSelection(_ selection: PathTransformSelection) {
    guard selection != pathTransformSelection else { return }
    pathTransformSelection = selection
    if case .anchors(let anchors) = selection {
      if let pathAnchor, anchors.contains(pathAnchor) { return }
      pathAnchor = anchors.first
    } else {
      pathAnchor = nil
    }
  }
}

@MainActor extension CraftCanvas {
  func drawPathMarquee(in context: CGContext) {
    guard let marquee = store.pathMarquee, marquee.dragging else { return }
    let start = viewPoint(.init(x: marquee.start.x, y: marquee.start.y))
    let end = viewPoint(.init(x: marquee.end.x, y: marquee.end.y))
    let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                     width: abs(end.x - start.x), height: abs(end.y - start.y))
    context.saveGState()
    outline(box, in: context)
    context.restoreGState()
  }
}
