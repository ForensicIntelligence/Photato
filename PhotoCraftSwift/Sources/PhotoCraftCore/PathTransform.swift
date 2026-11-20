import CoreGraphics
import Foundation

public enum PathTransformTarget: Equatable, Sendable {
  case saved(UUID)
  case vectorMask(UUID)
  case shape(UUID)

  public var id: UUID {
    switch self {
    case .saved(let id), .vectorMask(let id), .shape(let id): id
    }
  }
}

public struct PathTransformAnchor: Codable, Equatable, Hashable, Sendable {
  public var component: Int
  public var knot: Int

  public init(component: Int, knot: Int) {
    self.component = component
    self.knot = knot
  }
}

public enum PathTransformSelection: Codable, Equatable, Sendable {
  case all
  case components([Int])
  case anchors([PathTransformAnchor])

  func validate() throws {
    switch self {
    case .all: break
    case .components(let components):
      guard !components.isEmpty, components.count <= 256, Set(components).count == components.count,
            components.allSatisfy({ (0..<256).contains($0) }) else {
        throw CraftError.invalid("Invalid selected path components.")
      }
    case .anchors(let anchors):
      guard !anchors.isEmpty, anchors.count <= VectorPath.maxKnots, Set(anchors).count == anchors.count,
            anchors.allSatisfy({ (0..<256).contains($0.component) && (0..<VectorPath.maxKnots).contains($0.knot) })
      else { throw CraftError.invalid("Invalid selected path anchors.") }
    }
  }

  func indices(in path: VectorPath) throws -> [Set<Int>] {
    try validate()
    var indices = Array(repeating: Set<Int>(), count: path.components.count)
    switch self {
    case .all:
      for (index, component) in path.components.enumerated() {
        indices[index] = Set(component.knots.indices)
      }
    case .components(let components):
      guard components.allSatisfy({ path.components.indices.contains($0) }) else {
        throw CraftError.invalid("Invalid selected path components.")
      }
      for index in components { indices[index] = Set(path.components[index].knots.indices) }
    case .anchors(let anchors):
      for anchor in anchors {
        guard path.components.indices.contains(anchor.component),
              path.components[anchor.component].knots.indices.contains(anchor.knot) else {
          throw CraftError.invalid("Invalid selected path anchors.")
        }
        indices[anchor.component].insert(anchor.knot)
      }
    }
    guard indices.contains(where: { !$0.isEmpty }) else {
      throw CraftError.invalid("Select a path, component, or anchor before transforming.")
    }
    return indices
  }
}

public struct PathTransformRequest: Equatable, Sendable {
  public let target: PathTransformTarget
  public let selection: PathTransformSelection
  public let matrix: ProjectiveTransform

  public init(target: PathTransformTarget, selection: PathTransformSelection = .all,
              matrix: ProjectiveTransform) {
    self.target = target
    self.selection = selection
    self.matrix = matrix
  }
}

public enum PathTransform {
  public static func path(_ target: PathTransformTarget, in document: CraftDocument) throws -> VectorPath {
    switch target {
    case .saved(let id):
      if let path = document.paths?.first(where: { $0.id == id }) { return path.path }
    case .vectorMask(let id):
      if let mask = document.layers.first(where: { $0.id == id })?.vectorMask { return mask.path }
    case .shape(let id):
      if let path = try document.layers.first(where: { $0.id == id })?.shapePath() { return path }
    }
    throw CraftError.invalid("The transform path is missing.")
  }

  public static func bounds(_ path: VectorPath, selection: PathTransformSelection) throws -> IntRect {
    try path.validate()
    let indices = try selection.indices(in: path)
    let curves = CGMutablePath()
    var limits = CGRect.null
    func point(_ p: PathPoint) -> CGPoint { .init(x: p.x, y: p.y) }
    for (component, selected) in zip(path.components, indices) where !selected.isEmpty {
      for index in selected {
        let knot = component.knots[index]
        limits = limits.union(CGRect(origin: point(knot.anchor), size: .zero))
        let next = index + 1 == component.knots.count && component.closed ? 0 : index + 1
        if next != index, selected.contains(next) {
          let destination = component.knots[next]
          curves.move(to: point(knot.anchor))
          curves.addCurve(to: point(destination.anchor), control1: point(knot.outgoing),
                          control2: point(destination.incoming))
        }
      }
    }
    limits = limits.union(curves.boundingBoxOfPath)
    let x = floor(limits.minX), y = floor(limits.minY)
    return .init(x: Int(x), y: Int(y), width: max(1, Int(ceil(limits.maxX) - x)),
                 height: max(1, Int(ceil(limits.maxY) - y)))
  }

  public static func geometry(
    _ path: VectorPath, selection: PathTransformSelection, matrix: ProjectiveTransform
  ) throws -> (path: VectorPath, selection: PathTransformSelection) {
    try Task.checkCancellation()
    try path.validate()
    let indices = try selection.indices(in: path)
    if let affine = try matrix.affineValue() {
      if affine == .identity { return (path, selection) }
      var result = path
      for (component, selected) in indices.enumerated() {
        try Task.checkCancellation()
        for knot in selected {
          result.components[component].knots[knot] = path.components[component].knots[knot].transformed(affine)
        }
      }
      try result.validate()
      return (result, selection)
    }
    let result = try ProjectiveVectorPath.apply(path, matrix: matrix, selected: indices)
    if case .anchors = selection { return (result.path, .anchors(result.anchors)) }
    return (result.path, selection)
  }

  public static func editablePath(_ target: PathTransformTarget, in document: CraftDocument) throws -> VectorPath {
    let original = try path(target, in: document)
    switch target {
    case .saved: break
    case .vectorMask(let id):
      guard !document.isLocked(id) else { throw CraftError.invalid("Unlock the vector mask layer first.") }
    case .shape(let id):
      guard !document.isLocked(id), !document.isImageLocked(id), !document.isPositionLocked(id),
            document.layers.first(where: { $0.id == id })?.hasGeometryKeyframes == false else {
        throw CraftError.invalid("Unlock the shape layer or finish its geometry keyframes first.")
      }
    }
    return original
  }

  static func apply(_ request: PathTransformRequest, to document: inout CraftDocument) throws {
    let original = try editablePath(request.target, in: document)
    let result = try geometry(original, selection: request.selection, matrix: request.matrix)
    guard result.path != original else { return }
    var candidate = document
    switch request.target {
    case .saved(let id):
      guard let index = candidate.paths?.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("The saved path is missing.")
      }
      candidate.paths?[index].path = result.path
    case .vectorMask(let id):
      guard let index = candidate.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("The vector mask layer is missing.")
      }
      candidate.layers[index].vectorMask?.path = result.path
    case .shape(let id):
      guard let layer = candidate.layers.first(where: { $0.id == id }) else {
        throw CraftError.invalid("The shape layer is missing.")
      }
      let canvas = IntRect(x: 0, y: 0, width: candidate.width, height: candidate.height)
      try Command.shape(.configure(id, layer.replacingShapePath(result.path, canvas: canvas))).apply(to: &candidate)
    }
    try Task.checkCancellation()
    try candidate.validate()
    document = candidate
  }
}
