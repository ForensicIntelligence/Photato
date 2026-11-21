import Foundation

public struct PathMarqueeSelection: Equatable, Sendable {
  public var start: PathPoint
  public var end: PathPoint

  public init(start: PathPoint, end: PathPoint) {
    self.start = start
    self.end = end
  }

  public func selection(in path: VectorPath, extending prior: PathTransformSelection? = nil) -> PathTransformSelection {
    guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else {
      return prior ?? .anchors([])
    }
    let left = min(start.x, end.x), right = max(start.x, end.x)
    let top = min(start.y, end.y), bottom = max(start.y, end.y)
    var hits: [PathTransformAnchor] = []
    for (componentIndex, component) in path.components.enumerated() {
      for (knotIndex, knot) in component.knots.enumerated() {
        let point = knot.anchor
        if left <= point.x, point.x <= right, top <= point.y, point.y <= bottom {
          hits.append(.init(component: componentIndex, knot: knotIndex))
        }
      }
    }
    guard let prior else { return .anchors(hits) }
    guard !hits.isEmpty else { return prior }
    switch prior {
    case .all: return .anchors(hits)
    case .anchors(let anchors): hits.append(contentsOf: anchors)
    case .components(let indices):
      for index in Set(indices) where path.components.indices.contains(index) {
        hits.append(contentsOf: path.components[index].knots.indices.map {
          .init(component: index, knot: $0)
        })
      }
    }
    return .anchors(Set(hits).sorted { ($0.component, $0.knot) < ($1.component, $1.knot) })
  }

  public func componentSelection(in path: VectorPath, extending prior: PathTransformSelection? = nil)
    -> PathTransformSelection
  {
    let hits = selection(in: path)
    guard case .anchors(let anchors) = hits else { return .components([]) }
    var selected = Set(anchors.map(\.component))
    switch prior {
    case .components(let indices): selected.formUnion(indices)
    case .anchors(let indices): selected.formUnion(indices.map(\.component))
    case .all, nil: break
    }
    let groups = PathComponentEdit.groups(in: path)
    return .components(groups.filter { $0.contains(where: selected.contains) }.flatMap { $0 })
  }
}
