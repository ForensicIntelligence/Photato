import AppKit
import PhotoCraftCore

extension PathTransformSelection {
  var transformTitle: String {
    if case .anchors = self { return "Transform Points" }
    return "Transform Path"
  }
}

@MainActor extension EditorStore {
  var canBeginPathTransform: Bool {
    guard let target = pathTarget, !editingComponent, !editingMask, !geometryBusy, !hasToneDraft,
          transformDraft == nil, pathGesture == nil, freeformGesture == nil,
          let path = try? PathTransform.editablePath(target, in: document) else { return false }
    return (try? PathTransform.bounds(path, selection: pathTransformSelection)) != nil
  }

  func beginPathTransform() {
    guard canBeginPathTransform, let target = pathTarget, let path = selectedVectorPath else { return }
    do {
      let bounds = try PathTransform.bounds(path, selection: pathTransformSelection)
      finishNumericField()
      finishLayerName()
      var draft = TransformDraft(layerID: target.id, bounds: bounds)
      draft.pathTarget = target
      draft.pathSelection = pathTransformSelection
      draft.selection = true
      if case .saved = target {} else { draft.selectedPixels = true }
      draft.selectionQuad = draft.selectionCorners
      let session = SelectionTransformSession(document, draft: draft)
      selectionTransform = session
      transformDraft = draft
      status = "\(draft.pathSelection.transformTitle) · Return applies · Escape cancels"
      session.task = Task { await session.prepare() }
    } catch { self.error = error.localizedDescription }
  }

  func turnSelectedPath(angle: Double, horizontal: Bool, vertical: Bool) {
    guard canBeginPathTransform, let target = pathTarget, let path = selectedVectorPath else { return }
    do {
      let bounds = try PathTransform.bounds(path, selection: pathTransformSelection)
      let x = Double(bounds.x) + Double(bounds.width) / 2
      let y = Double(bounds.y) + Double(bounds.height) / 2
      let matrix = Transform2D.translation(x, y) * .rotation(angle)
        * .scale(horizontal ? -1 : 1, vertical ? -1 : 1) * .translation(-x, -y)
      performGeometry(.transformPath(.init(target: target, selection: pathTransformSelection,
                                            matrix: .init(matrix))))
    } catch { self.error = error.localizedDescription }
  }

  func pathAnchorIsSelected(_ anchor: PathAnchorSelection) -> Bool {
    switch selectionTransform?.vectorPreview?.selection ?? pathTransformSelection {
    case .all: return pathAnchor == anchor
    case .components(let values): return values.contains(anchor.component)
    case .anchors(let values): return values.contains(anchor)
    }
  }

  @discardableResult
  func selectPathComponents(_ values: [Int], extending: Bool) -> Bool {
    var selection = Set<Int>()
    if case .components(let current) = pathTransformSelection,
       extending || values.allSatisfy(current.contains) { selection = Set(current) }
    if extending { selection.formSymmetricDifference(values) } else { selection.formUnion(values) }
    pathTransformSelection = .components(selection.sorted())
    return values.contains(where: selection.contains)
  }

  @discardableResult
  func selectPathAnchors(_ values: [PathAnchorSelection], extending: Bool) -> Bool {
    var selection = Set<PathAnchorSelection>()
    if case .anchors(let current) = pathTransformSelection,
       extending || values.allSatisfy(current.contains) { selection = Set(current) }
    if extending { selection.formSymmetricDifference(values) } else { selection.formUnion(values) }
    pathTransformSelection = .anchors(selection.sorted {
      ($0.component, $0.knot) < ($1.component, $1.knot)
    })
    return values.contains(where: selection.contains)
  }
}
