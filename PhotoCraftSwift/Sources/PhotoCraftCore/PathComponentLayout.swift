import CoreGraphics
import Foundation

public struct PathComponentLayoutRequest: Equatable, Sendable {
  public let target: PathTransformTarget
  public let components: [Int]?
  public let operation: LayerLayoutOperation

  public init(target: PathTransformTarget, components: [Int]? = nil, operation: LayerLayoutOperation) {
    self.target = target
    self.components = components
    self.operation = operation
  }

  public var label: String {
    switch operation {
    case .align(let edge): "Align Path \(edge.rawValue)"
    case .distribute(let edge): "Distribute Path \(edge.rawValue)"
    }
  }

  public static func minimumCount(for operation: LayerLayoutOperation) -> Int {
    switch operation {
    case .align: 2
    case .distribute: 3
    }
  }

  static func validateComponents(_ components: [Int]?, operation: LayerLayoutOperation) throws {
    guard let components else { return }
    try PathTransformSelection.components(components).validate()
    guard components.count >= minimumCount(for: operation) else {
      throw CraftError.invalid("Select more whole path components for this operation.")
    }
  }
}

public enum PathComponentLayout {
  public static func componentIndices(_ request: PathComponentLayoutRequest, in path: VectorPath) throws -> [Int] {
    try PathComponentLayoutRequest.validateComponents(request.components, operation: request.operation)
    let available = path.components.indices.filter { !path.components[$0].knots.isEmpty }
    let selected = request.components?.sorted() ?? available
    guard selected.count >= PathComponentLayoutRequest.minimumCount(for: request.operation),
          selected.allSatisfy(Set(available).contains) else {
      throw CraftError.invalid("Select enough existing, nonempty components on the same path.")
    }
    return selected
  }

  public static func geometry(_ request: PathComponentLayoutRequest, in document: CraftDocument) throws
    -> PathTransformGeometry
  {
    let original = try PathTransform.editablePath(request.target, in: document)
    let indices = try componentIndices(request, in: original)
    let bounds = try indices.map { index in
      try Task.checkCancellation()
      return try PathTransform.selectedBounds(.init(components: [original.components[index]]), selection: .all)
    }
    let (edge, offsets) = translations(bounds, operation: request.operation)
    var path = original
    for (index, offset) in zip(indices, offsets) where offset != 0 {
      try Task.checkCancellation()
      let transform = Transform2D.translation(edge.horizontal ? offset : 0, edge.horizontal ? 0 : offset)
      path.components[index].knots = original.components[index].knots.map { $0.transformed(transform) }
    }
    try path.validate()
    return .init(choice: .init(request.target, selection: .components(indices)), path: path, original: original)
  }

  private static func translations(_ bounds: [CGRect], operation: LayerLayoutOperation) -> (LayerAlignment, [Double]) {
    switch operation {
    case .align(let edge):
      let combined = bounds.reduce(CGRect.null) { $0.union($1) }
      let destination = edge.coordinate(in: combined)
      return (edge, bounds.map { destination - edge.coordinate(in: $0) })
    case .distribute(let rule):
      let edge = rule.edge
      let positions = bounds.map { edge.coordinate(in: $0) }
      let order = bounds.indices.sorted {
        positions[$0] == positions[$1] ? $0 < $1 : positions[$0] < positions[$1]
      }
      let first = positions[order[0]], last = positions[order[order.count - 1]]
      let intervals = Double(order.count - 1)
      var offsets = Array(repeating: 0.0, count: order.count)
      if rule.spacing {
        let lengths = bounds.map { Double(edge.horizontal ? $0.width : $0.height) }
        let span = last + lengths[order[order.count - 1]] - first
        let gap = (span - lengths.reduce(0, +)) / intervals
        var next = first + lengths[order[0]] + gap
        for index in order.dropFirst().dropLast() {
          offsets[index] = next - positions[index]
          next += lengths[index] + gap
        }
      } else {
        for (slot, index) in order.enumerated().dropFirst().dropLast() {
          offsets[index] = first + (last - first) * Double(slot) / intervals - positions[index]
        }
      }
      return (edge, offsets)
    }
  }

  static func apply(_ request: PathComponentLayoutRequest, to document: inout CraftDocument) throws {
    try PathTransform.install([geometry(request, in: document)], in: &document, preservingTranslatedShapes: true)
  }
}

private extension LayerAlignment {
  func coordinate(in rect: CGRect) -> Double {
    switch self {
    case .top: Double(rect.minY)
    case .verticalCenter: Double(rect.midY)
    case .bottom: Double(rect.maxY)
    case .left: Double(rect.minX)
    case .horizontalCenter: Double(rect.midX)
    case .right: Double(rect.maxX)
    }
  }
}
