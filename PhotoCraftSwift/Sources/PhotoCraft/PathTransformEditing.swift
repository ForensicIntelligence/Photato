import AppKit
import PhotoCraftCore

extension PathTransformSelection {
  var transformTitle: String {
    if case .anchors = self { return "Transform Points" }
    return "Transform Path"
  }
}

extension Array where Element == PathTransformChoice {
  var transformTitle: String? {
    guard let first else { return nil }
    if count == 1 { return first.selection.transformTitle }
    let pointsOnly = allSatisfy { choice in
      if case .anchors = choice.selection { return true }
      return false
    }
    return pointsOnly ? "Transform Points" : "Transform Paths"
  }
}

@MainActor extension EditorStore {
  var pathChoicesForTransform: [PathTransformChoice] {
    selectedPathChoices.filter { choice in
      switch choice.selection {
      case .all: return (try? PathTransform.path(choice.target, in: document))?.isEmpty == false
      case .anchors(let anchors): return !anchors.isEmpty
      case .components(let components): return !components.isEmpty
      }
    }
  }

  var canBeginPathTransform: Bool {
    guard pathTarget != nil, !editingComponent, !editingMask, !geometryBusy, !hasToneDraft,
          transformDraft == nil, pathGesture == nil, pathMarquee == nil, freeformGesture == nil else { return false }
    return (try? PathTransform.bounds(pathChoicesForTransform, in: document)) != nil
  }

  func beginPathTransform() {
    guard canBeginPathTransform, let target = pathTarget else { return }
    do {
      let choices = pathChoicesForTransform
      let bounds = try PathTransform.bounds(choices, in: document)
      finishNumericField()
      finishLayerName()
      var draft = TransformDraft(layerID: target.id, bounds: bounds)
      draft.pathTarget = target
      draft.pathSelection = pathTransformSelection
      draft.pathChoices = choices
      draft.pathSelectionContext = selectedPathChoices
      draft.selection = true
      draft.selectedPixels = choices.contains {
        if case .saved = $0.target { return false }
        return true
      }
      draft.selectionQuad = draft.selectionCorners
      let session = SelectionTransformSession(document, draft: draft)
      selectionTransform = session
      transformDraft = draft
      status = "\(draft.pathTransformTitle) · Return applies · Escape cancels"
      session.task = Task { await session.prepare() }
    } catch { self.error = error.localizedDescription }
  }

  func turnSelectedPath(angle: Double, horizontal: Bool, vertical: Bool) {
    guard canBeginPathTransform else { return }
    do {
      let choices = pathChoicesForTransform
      let bounds = try PathTransform.bounds(choices, in: document)
      let x = Double(bounds.x) + Double(bounds.width) / 2
      let y = Double(bounds.y) + Double(bounds.height) / 2
      let matrix = Transform2D.translation(x, y) * .rotation(angle)
        * .scale(horizontal ? -1 : 1, vertical ? -1 : 1) * .translation(-x, -y)
      performGeometry(PathTransformGroupRequest(choices: choices, matrix: .init(matrix)).nativeCommand)
    } catch { self.error = error.localizedDescription }
  }

  func pathAnchorHighlight(selection: PathTransformSelection, focus: PathAnchorSelection?) -> (PathAnchorSelection) -> Bool {
    switch selection {
    case .all:
      return { $0 == focus }
    case .components(let values):
      let components = Set(values)
      return { components.contains($0.component) }
    case .anchors(let values):
      let anchors = Set(values)
      return { anchors.contains($0) }
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

extension PathTransformGroupRequest {
  var nativeCommand: Command {
    if choices.count == 1, let choice = choices.first {
      return .transformPath(.init(target: choice.target, selection: choice.selection, matrix: matrix))
    }
    return .transformPaths(self)
  }
}
