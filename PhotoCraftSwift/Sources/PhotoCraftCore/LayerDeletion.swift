import Foundation

/// Selected subtree deletion is atomic and retains at least one layer.
public enum LayerDeletion {
  public static func canDelete(in document: CraftDocument, selected: Set<UUID>) -> Bool {
    (try? removedIDs(in: document, selected: selected)) != nil
  }

  private static func removedIDs(in document: CraftDocument, selected: Set<UUID>) throws -> Set<
    UUID
  > {
    guard !selected.isEmpty, selected.isSubset(of: Set(document.layers.map(\.id))) else {
      throw CraftError.invalid("Select existing layers to delete.")
    }
    let removed = selected.reduce(into: Set<UUID>()) { $0.formUnion(document.subtreeIDs($1)) }
    guard removed.count < document.layers.count else {
      throw CraftError.invalid("Keep at least one layer in the document.")
    }
    guard removed.allSatisfy({ !document.isLocked($0) }) else {
      throw CraftError.invalid(
        "Unlock the selected layers, their contents and parent groups before deleting.")
    }
    return removed
  }

  static func apply(to document: inout CraftDocument, selected: Set<UUID>) throws {
    let removed = try removedIDs(in: document, selected: selected)
    var candidate = document
    let first = candidate.layers.firstIndex { removed.contains($0.id) }!
    let below = candidate.layers[..<first].last { !removed.contains($0.id) }?.id
    candidate.layers.removeAll { removed.contains($0.id) }
    candidate.activeLayerID = below ?? candidate.layers.last?.id
    try candidate.validate()
    document = candidate
  }
}
