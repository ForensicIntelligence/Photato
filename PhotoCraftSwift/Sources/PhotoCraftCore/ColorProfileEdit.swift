import Foundation

/// Prepared assignment/conversion publishes once and refuses stale source data.
public struct ColorProfileEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let title: String
  public init(source: CraftDocument, result: CraftDocument, title: String) {
    self.source = source; self.result = result; self.title = title
  }
  public func applied(to document: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation()
    guard document == source, result.id == source.id else {
      throw CraftError.invalid("The document changed during profile processing.")
    }
    try result.validate(); return result
  }
}
