import Foundation

/// Portable settings shared by native preview, HTTP and recorded actions.
public struct InkModeRequest: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable { case duotone, multichannel }
  public var kind: Kind
  public var settings: DuotoneSettings
  public var mergeVisible: Bool
  /// IDs are captured once, so repeated previews and the committed result agree.
  public var plateIDs: [UUID]
  public init(_ kind: Kind, document: CraftDocument) {
    self.kind = kind; mergeVisible = false; settings = .init(); plateIDs = []
    if case .duotone(let raster) = document.inkMode { settings = raster.settings }
    if kind == .multichannel {
      switch document.inkMode {
      case .duotone(let raster): plateIDs = raster.settings.inks.map(\.id)
      case .multichannel(let raster): plateIDs = raster.plates.map(\.id)
      case nil: plateIDs = (0..<document.colorMode.componentCount).map { _ in UUID() }
      }
    }
  }
  public var title: String { kind == .duotone ? "Duotone Options" : "Multichannel" }
  public func validate() throws {
    if kind == .duotone {
      try settings.validate()
      guard plateIDs.isEmpty else { throw CraftError.invalid("Duotone inks carry their own identities.") }
    } else {
      guard (1...MultichannelRaster.maximumChannels).contains(plateIDs.count), Set(plateIDs).count == plateIDs.count else {
        throw CraftError.invalid("Multichannel needs distinct identities for every resulting ink plate.")
      }
    }
  }
}
