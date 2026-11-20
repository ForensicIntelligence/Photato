import Foundation

public enum ActionPathTarget: Codable, Equatable, Sendable {
  case saved(UUID, String, Bool)
  case vectorMask(ActionLayerTarget)
  case shape(ActionLayerTarget)

  init?(_ target: PathTransformTarget, in document: CraftDocument) {
    switch target {
    case .saved(let id):
      guard let path = document.paths?.first(where: { $0.id == id }) else { return nil }
      self = .saved(id, path.name, path.isWorkPath)
    case .vectorMask(let id):
      self = .vectorMask(.init(id, in: document))
    case .shape(let id):
      self = .shape(.init(id, in: document))
    }
  }

  func resolve(in document: CraftDocument) throws -> PathTransformTarget {
    switch self {
    case .saved(let id, let name, let work):
      let paths = document.paths ?? []
      if paths.contains(where: { $0.id == id }) { return .saved(id) }
      let candidates = paths.filter { $0.name == name && $0.isWorkPath == work }
      guard candidates.count == 1, let path = candidates.first else {
        throw CraftError.invalid("The recorded path is missing or ambiguous.")
      }
      return .saved(path.id)
    case .vectorMask(let target):
      return .vectorMask(try target.resolve(in: document))
    case .shape(let target):
      return .shape(try target.resolve(in: document))
    }
  }
}

public struct RecordedPathChoice: Codable, Equatable, Sendable {
  public let target: ActionPathTarget
  public let selection: PathTransformSelection

  init?(_ choice: PathTransformChoice, in document: CraftDocument) {
    guard let target = ActionPathTarget(choice.target, in: document) else { return nil }
    self.target = target
    self.selection = choice.selection
  }

  func resolve(in document: CraftDocument) throws -> PathTransformChoice {
    try .init(target.resolve(in: document), selection: selection)
  }
}
