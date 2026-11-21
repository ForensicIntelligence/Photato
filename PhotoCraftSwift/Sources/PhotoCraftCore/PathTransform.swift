import CoreGraphics
import Foundation

public enum PathTransformTarget: Hashable, Sendable {
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

public struct PathTransformChoice: Equatable, Sendable {
  public let target: PathTransformTarget
  public var selection: PathTransformSelection

  public init(_ target: PathTransformTarget, selection: PathTransformSelection = .all) {
    self.target = target
    self.selection = selection
  }
}

public struct PathTransformGroupRequest: Equatable, Sendable {
  public static let maximumTargets = LayerLimits.maximumLayers * 2 + 256
  public let choices: [PathTransformChoice]
  public let matrix: ProjectiveTransform

  public init(choices: [PathTransformChoice], matrix: ProjectiveTransform) {
    self.choices = choices
    self.matrix = matrix
  }
}

public struct PathTransformGeometry: Equatable, Sendable {
  public let choice: PathTransformChoice
  public let path: VectorPath
  let original: VectorPath
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
    rounded(try selectedBounds(path, selection: selection))
  }

  static func selectedBounds(_ path: VectorPath, selection: PathTransformSelection) throws -> CGRect {
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
    return limits.union(curves.boundingBoxOfPath)
  }

  private static func rounded(_ limits: CGRect) -> IntRect {
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

  public static func bounds(_ choices: [PathTransformChoice], in document: CraftDocument) throws -> IntRect {
    try validateTargets(choices)
    var limits = CGRect.null
    for choice in choices {
      try Task.checkCancellation()
      let box = try selectedBounds(editablePath(choice.target, in: document), selection: choice.selection)
      limits = limits.union(box)
    }
    return rounded(limits)
  }

  static func bounds(_ geometry: [PathTransformGeometry]) throws -> IntRect {
    var limits = CGRect.null
    for item in geometry {
      let box = try selectedBounds(item.path, selection: item.choice.selection)
      limits = limits.union(box)
    }
    return rounded(limits)
  }

  public static func geometry(
    _ request: PathTransformGroupRequest, in document: CraftDocument
  ) throws -> [PathTransformGeometry] {
    try validateTargets(request.choices)
    if request.choices.count > 1, try request.matrix.affineValue() == nil {
      let box = try bounds(request.choices, in: document)
      try request.matrix.validateSharedHorizon(left: box.x, top: box.y, right: box.x + box.width,
                                              bottom: box.y + box.height)
    }
    return try request.choices.map { choice in
      try Task.checkCancellation()
      let original = try editablePath(choice.target, in: document)
      let result = try geometry(original, selection: choice.selection, matrix: request.matrix)
      return .init(choice: .init(choice.target, selection: result.selection), path: result.path, original: original)
    }
  }

  private static func validateTargets(_ choices: [PathTransformChoice]) throws {
    guard (1...PathTransformGroupRequest.maximumTargets).contains(choices.count),
          Set(choices.map(\.target)).count == choices.count else {
      throw CraftError.invalid("Supply distinct path targets for the transform.")
    }
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
    try apply(.init(choices: [.init(request.target, selection: request.selection)], matrix: request.matrix),
              to: &document)
  }

  static func apply(_ request: PathTransformGroupRequest, to document: inout CraftDocument) throws {
    try install(geometry(request, in: document), in: &document)
  }

  static func install(_ geometry: [PathTransformGeometry], in document: inout CraftDocument,
                      preservingTranslatedShapes: Bool = false) throws {
    let changes = geometry.filter { $0.path != $0.original }
    guard !changes.isEmpty else { return }
    var candidate = document
    for result in changes {
      try Task.checkCancellation()
      try install(result, in: &candidate, preservingTranslatedShapes: preservingTranslatedShapes)
    }
    try candidate.validate()
    try Task.checkCancellation()
    document = candidate
  }

  private static func install(_ result: PathTransformGeometry, in candidate: inout CraftDocument,
                              preservingTranslatedShapes: Bool) throws {
    switch result.choice.target {
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
      let definition = try layer.replacingShapePath(result.path, canvas: canvas,
                                                    preservingTranslatedComponents: preservingTranslatedShapes)
      try Command.shape(.configure(id, definition)).apply(to: &candidate)
    }
  }
}
