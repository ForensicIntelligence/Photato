import Foundation

/// Full-canvas process-color output for one spot channel. The source includes
/// the exact layer stack and spot density used for the detached preparation.
public struct SpotChannelMergeEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let channelID: UUID

  public init(source: CraftDocument, result: CraftDocument, channelID: UUID) {
    self.source = source
    self.result = result
    self.channelID = channelID
  }

  func applied(to document: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation()
    guard document == source, result.id == source.id else {
      throw CraftError.invalid("The source changed before Merge Spot Channel could commit.")
    }
    try result.validate()
    return result
  }
}
