import Foundation

/// Source choices are shared; the selected choice belongs to one placed instance.
public struct SmartObjectLayerComps: Codable, Equatable, Sendable {
  public struct Entry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
  }
  public var entries: [Entry]
  public var selectedID: UUID?
  public init(entries: [Entry], selectedID: UUID? = nil) throws {
    self.entries = entries; self.selectedID = selectedID; try validate()
  }
  public var estimatedBytes: Int { entries.reduce(128) { $0 + 64 + $1.name.utf8.count } }
  public func validate() throws {
    guard !entries.isEmpty, entries.count <= LayerComps.maximumComps,
      Set(entries.map(\.id)).count == entries.count, estimatedBytes <= 4 * 1024 * 1024,
      selectedID == nil || entries.contains(where: { $0.id == selectedID }),
      entries.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.utf8.count <= 1024 && !$0.name.contains("\0") })
    else { throw CraftError.invalid("Invalid Smart Object Layer Comp choices or selection.") }
  }
  public func preservingSelection(from previous: SmartObjectLayerComps?) throws -> Self {
    var value = self; value.selectedID = previous?.selectedID; try value.validate(); return value
  }
}
extension CraftDocument {
  public var requiresSmartObjectLayerCompArchive: Bool { layers.contains { $0.smartObject?.layerComps != nil } }
}
