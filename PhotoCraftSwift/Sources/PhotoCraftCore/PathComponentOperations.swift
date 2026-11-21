import CoreGraphics
import Foundation

public enum PathComponentOperation: String, Codable, CaseIterable, Sendable {
  case bringToFront, bringForward, sendBackward, sendToBack
  case combine, subtract, intersect, exclude, merge

  public var title: String {
    switch self {
    case .bringToFront: "Bring Shape to Front"
    case .bringForward: "Bring Shape Forward"
    case .sendBackward: "Send Shape Backward"
    case .sendToBack: "Send Shape to Back"
    case .combine: "Combine Shapes"
    case .subtract: "Subtract From Shape Area"
    case .intersect: "Intersect Shape Areas"
    case .exclude: "Exclude Overlapping Shapes"
    case .merge: "Merge Shape Components"
    }
  }

  public static let stacking: [Self] = [.bringToFront, .bringForward, .sendBackward, .sendToBack]
  public static let overlap: [Self] = [.combine, .subtract, .intersect, .exclude]
  var stackOrder: LayerStackOperation? { LayerStackOperation(rawValue: rawValue) }
  public var overlapMode: PathOperation? {
    switch self {
    case .combine: .combine
    case .subtract: .subtract
    case .intersect: .intersect
    case .exclude: .exclude
    default: nil
    }
  }
}

public struct PathComponentEditRequest: Equatable, Sendable {
  public let target: PathTransformTarget
  public let components: [Int]?
  public let operation: PathComponentOperation

  public init(target: PathTransformTarget, components: [Int]? = nil, operation: PathComponentOperation) {
    self.target = target
    self.components = components
    self.operation = operation
  }

  static func validate(_ components: [Int]?) throws {
    if let components { try PathTransformSelection.components(components).validate() }
  }
}

public struct PathComponentEdit: Sendable {
  public let request: PathComponentEditRequest
  public let selection: PathTransformSelection
  let original: VectorPath
  let result: VectorPath
  let sourceOrder: [Int]?

  public static func groups(in path: VectorPath) -> [Range<Int>] {
    var starts = path.components.indices.filter { $0 == 0 || path.components[$0].operation != .join }
    starts.append(path.components.count)
    return zip(starts, starts.dropFirst()).map { $0..<$1 }
  }

  public static func canReorder(_ path: VectorPath, components: [Int], operation: PathComponentOperation) -> Bool {
    guard let stack = operation.stackOrder else { return false }
    let groups = groups(in: path), selected = Set(components)
    let selectedGroups = Set(groups.indices.filter { groups[$0].contains(where: selected.contains) })
    return stack.arranged(Array(groups.indices), selected: selectedGroups) != Array(groups.indices)
  }

  public static func prepare(_ request: PathComponentEditRequest, in document: CraftDocument) throws -> Self {
    try PathComponentEditRequest.validate(request.components)
    let path = try PathTransform.editablePath(request.target, in: document)
    let groups = groups(in: path)
    let indices = Set(request.components ?? Array(path.components.indices))
    guard !indices.isEmpty, indices.allSatisfy(path.components.indices.contains) else {
      throw CraftError.invalid("Select existing components on one editable path.")
    }
    let selected = Set(groups.indices.filter { group in groups[group].contains(where: indices.contains) })
    var result = path
    if let operation = request.operation.stackOrder {
      let ordered = operation.arranged(Array(groups.indices), selected: selected)
      let sourceOrder = ordered.flatMap { groups[$0] }
      result.components = sourceOrder.map { path.components[$0] }
      var start = 0
      for group in ordered {
        if start > 0, result.components[start].operation == .join {
          result.components[start].operation = .combine
        }
        start += groups[group].count
      }
      let identities = Set(selected.flatMap { groups[$0] })
      let resultIndices = sourceOrder.indices.filter { identities.contains(sourceOrder[$0]) }
      return .init(request: request, selection: .components(resultIndices), original: path, result: result, sourceOrder: sourceOrder)
    }
    if let operation = request.operation.overlapMode {
      for group in selected { result.components[groups[group].lowerBound].operation = operation }
      let resultIndices = selected.sorted().flatMap { groups[$0] }
      return .init(request: request, selection: .components(resultIndices), original: path, result: result,
                   sourceOrder: Array(path.components.indices))
    }
    guard selected.count >= 2, let first = selected.min() else {
      throw CraftError.invalid("Select two or more path components to merge.")
    }
    let chosen = selected.sorted().flatMap { groups[$0].map { path.components[$0] } }
    guard chosen.allSatisfy(\.closed) else {
      throw CraftError.unsupported("Merge Shape Components requires closed contours.")
    }
    let region = try VectorPathGeometry.componentMergeRegion(.init(components: chosen, fillRule: path.fillRule))
    var contours = try VectorPathGeometry.editableContours(region.path).components
    if !contours.isEmpty { contours[0].operation = region.inverted ? .subtract : .combine }
    result.components = groups.indices.flatMap { group in
      if group == first { return contours }
      return selected.contains(group) ? [] : groups[group].map { path.components[$0] }
    }
    let before = try VectorPathGeometry.componentMergeRegion(path)
    let after = try VectorPathGeometry.componentMergeRegion(result)
    var afterInverted = after.inverted
    if case .vectorMask = request.target, result.isEmpty {
      // An empty enabled vector mask normally reveals everything.
      result.inverted = !before.inverted
      afterInverted = !result.inverted
    }
    guard before.inverted == afterInverted,
          try VectorPathGeometry.componentMergePathsMatch(before.path, after.path) else {
      throw CraftError.unsupported("Those components interact with other overlap operations. Include the affected components in the merge.")
    }
    let insertion = groups[first].lowerBound
    return .init(request: request, selection: .components(Array(insertion..<(insertion + contours.count))),
                 original: path, result: result, sourceOrder: nil)
  }

  func apply(to document: inout CraftDocument) throws {
    guard try PathTransform.editablePath(request.target, in: document) == original else {
      throw CraftError.invalid("The path changed before applying the component operation.")
    }
    guard original != result else { return }
    if case .shape(let id) = request.target, let sourceOrder,
       let layer = document.layers.first(where: { $0.id == id }),
       let live = try layer.reorderedShapeDefinition(matching: result, sourceOrder: sourceOrder) {
      var candidate = document
      try Command.shape(.configure(id, live)).apply(to: &candidate)
      try candidate.validate()
      try Task.checkCancellation()
      document = candidate
      return
    }
    let choice = PathTransformChoice(request.target, selection: selection)
    try PathTransform.install([.init(choice: choice, path: result, original: original)], in: &document)
  }
}

private extension Layer {
  func reorderedShapeDefinition(matching path: VectorPath, sourceOrder: [Int]) throws -> ShapeDefinition? {
    guard let shape else { return nil }
    let original = shape.editableDefinition
    var groups: [Range<Int>] = []
    var offset = 0
    for component in original.components {
      let next = offset + (try component.path()).components.count
      groups.append(offset..<next)
      offset = next
    }
    let byStart = Dictionary(uniqueKeysWithValues: groups.indices.compactMap { index in
      groups[index].isEmpty ? nil : (groups[index].lowerBound, index)
    })
    let order = sourceOrder.compactMap { byStart[$0] }
    guard order.count == groups.count, order.flatMap({ groups[$0] }) == sourceOrder else { return nil }
    var candidate = original
    var cursor = 0
    candidate.components = order.map { index in
      defer { cursor += groups[index].count }
      var component = original.components[index]
      let operation = path.components[cursor].operation
      if component.operation != operation {
        component.operation = operation
        if component.pathOverride?.components.isEmpty == false {
          component.pathOverride?.components[0].operation = .combine
        }
      }
      return component
    }
    guard try candidate.path().transformed(shapeTransform()) == path else { return nil }
    candidate.paintFrame = try candidate.controlPaintFrame()
    return candidate
  }
}
