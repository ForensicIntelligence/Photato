import AppKit
import PhotoCraftCore

@MainActor extension EditorStore {
  var pathPanelTargets: [PathTarget] {
    var targets = (document.paths ?? []).map { PathTarget.saved($0.id) }
    for layer in document.layers.reversed() {
      if layer.shape != nil { targets.append(.shape(layer.id)) }
      if layer.vectorMask != nil { targets.append(.vectorMask(layer.id)) }
    }
    return targets
  }

  var selectedPathChoices: [PathTransformChoice] {
    guard let target = pathTarget else { return [] }
    let companions = companionPathChoices
    if companions.isEmpty { return [.init(target, selection: pathTransformSelection)] }
    let available = Set(pathPanelTargets)
    return [.init(target, selection: pathTransformSelection)]
      + companions.filter { available.contains($0.target) }
  }

  func pathPanelIsSelected(_ target: PathTarget) -> Bool {
    target == pathTarget || companionPathChoices.contains { $0.target == target }
  }

  func choosePathPanelRow(_ target: PathTarget, modifiers: NSEvent.ModifierFlags) {
    guard !geometryBusy else { return }
    let order = pathPanelTargets
    let old = selectedPathChoices
    let known = Dictionary(uniqueKeysWithValues: old.map { ($0.target, $0) })
    var targets: Set<PathTarget> = [target]
    var focus: PathTarget? = target
    var usedRange = false
    if modifiers.contains(.shift), let anchor = pathRangeAnchor,
       let start = order.firstIndex(of: anchor), let end = order.firstIndex(of: target) {
      usedRange = true
      targets = Set(order[min(start, end)...max(start, end)])
      if modifiers.contains(.command) { targets.formUnion(known.keys) }
    } else if modifiers.contains(.command) {
      targets = Set(known.keys)
      if targets.remove(target) != nil {
        focus = pathTarget == target ? order.first(where: targets.contains) : pathTarget
      } else {
        targets.insert(target)
      }
    }
    let retainedAnchor = usedRange ? pathRangeAnchor : target
    let retainsScope = usedRange || modifiers.contains(.command)
    let next = order.filter(targets.contains).map { (retainsScope ? known[$0] : nil) ?? .init($0) }
    setPathChoices(next, focus: focus)
    pathRangeAnchor = retainedAnchor
    if !usesPathTool, focus != nil { tool = .directSelection }
  }

  func setPathChoices(_ choices: [PathTransformChoice], focus: PathTarget?) {
    let primary = choices.first { $0.target == focus } ?? choices.first
    if transformDraft?.pathTarget != nil { cancelTransform() }
    selectPath(primary?.target)
    guard let primary else { return }
    companionPathChoices = choices.filter { $0.target != primary.target }
    pathTransformSelection = primary.selection
    if case .anchors(let anchors) = primary.selection { pathAnchor = anchors.first }
  }

  func updatePathChoices(_ choices: [PathTransformChoice]) {
    guard !choices.isEmpty else { return }
    let changed = Dictionary(uniqueKeysWithValues: choices.map { ($0.target, $0.selection) })
    if let target = pathTarget, let selection = changed[target] {
      applyMarqueeSelection(selection)
    }
    companionPathChoices = companionPathChoices.map { choice in
      if let selection = changed[choice.target] { return .init(choice.target, selection: selection) }
      return choice
    }
  }

  func focusCompanionPath(at point: PathPoint, tolerance: Double, includeInterior: Bool) {
    guard !companionPathChoices.isEmpty else { return }
    let choices = selectedPathChoices
    if let path = selectedVectorPath {
      if tool == .directSelection, let anchor = pathAnchor, path.components.indices.contains(anchor.component),
         path.components[anchor.component].knots.indices.contains(anchor.knot) {
        let knot = path.components[anchor.component].knots[anchor.knot]
        if [knot.incoming, knot.outgoing].contains(where: {
          hypot($0.x - point.x, $0.y - point.y) <= tolerance
        }) { return }
      }
      if pathContainsPointer(path, point: point, tolerance: tolerance, includeInterior: includeInterior) { return }
    }
    guard let choice = choices.dropFirst().first(where: {
      guard let path = try? PathTransform.editablePath($0.target, in: document) else { return false }
      return pathContainsPointer(path, point: point, tolerance: tolerance, includeInterior: includeInterior)
    }) else { return }
    let rangeAnchor = pathRangeAnchor
    setPathChoices(choices, focus: choice.target)
    pathRangeAnchor = rangeAnchor
  }

  private func pathContainsPointer(_ path: VectorPath, point: PathPoint, tolerance: Double,
                                   includeInterior: Bool) -> Bool {
    path.components.contains { component in
      component.knots.contains { hypot($0.anchor.x - point.x, $0.anchor.y - point.y) <= tolerance }
    } || nearestSegment(in: path, to: point, tolerance: tolerance) != nil
      || (includeInterior && containingPathComponent(in: path, at: point) != nil)
  }
}
