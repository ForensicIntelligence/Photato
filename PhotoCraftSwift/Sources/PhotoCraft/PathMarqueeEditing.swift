import AppKit
import PhotoCraftCore

struct PathMarqueeGesture {
  struct Input {
    let choice: PathTransformChoice
    let path: VectorPath
  }

  let target: PathTarget
  let selectionContext: [PathTransformChoice]
  let inputs: [Input]
  let start: PathPoint
  let extending: Bool
  let tool: EditorTool
  var end: PathPoint
  var dragging = false
  var previewChoices: [PathTransformChoice]?
  var preview: PathTransformSelection? {
    previewChoices?.first { $0.target == target }?.selection
  }
}

@MainActor extension EditorStore {
  func beginPathMarquee(at point: PathPoint, path: VectorPath, extending: Bool) {
    guard let target = pathTarget else { return }
    let choices = selectedPathChoices
    let inputs = choices.compactMap { choice -> PathMarqueeGesture.Input? in
      let shape = choice.target == target ? path : try? PathTransform.editablePath(choice.target, in: document)
      return shape.map { .init(choice: choice, path: $0) }
    }
    pathMarquee = .init(target: target, selectionContext: choices, inputs: inputs,
                        start: point, extending: extending, tool: tool, end: point)
  }

  func updatePathMarquee(to point: PathPoint, scale: Double) {
    guard var marquee = pathMarquee else { return }
    marquee.end = point
    marquee.dragging = marquee.dragging || hypot(point.x - marquee.start.x, point.y - marquee.start.y) * scale >= 3
    if marquee.dragging {
      let rectangle = PathMarqueeSelection(start: marquee.start, end: point)
      marquee.previewChoices = marquee.inputs.map { input in
        let prior = marquee.extending ? input.choice.selection : nil
        let selection = marquee.tool == .pathSelection
          ? rectangle.componentSelection(in: input.path, extending: prior)
          : rectangle.selection(in: input.path, extending: prior)
        return .init(input.choice.target, selection: selection)
      }
    }
    pathMarquee = marquee
  }

  func finishPathMarquee() {
    guard let marquee = pathMarquee else { return }
    pathMarquee = nil
    guard tool == marquee.tool, pathTarget == marquee.target,
          selectedPathChoices == marquee.selectionContext,
          marquee.inputs.allSatisfy({
            (try? PathTransform.editablePath($0.choice.target, in: document)) == $0.path
          }) else { return }
    if let choices = marquee.previewChoices {
      updatePathChoices(choices)
    } else if !marquee.extending {
      let empty: PathTransformSelection = marquee.tool == .pathSelection ? .components([]) : .anchors([])
      updatePathChoices(marquee.inputs.map { .init($0.choice.target, selection: empty) })
    }
    if selectedPathChoices != marquee.selectionContext {
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
