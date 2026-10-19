import Foundation

/// Organization changes preserve editable layer contents and accept locked layers.
public enum LayerOrganization {
  static func indices(_ ids: Set<UUID>, in document: CraftDocument) throws -> [Int] {
    guard !ids.isEmpty, ids.isSubset(of: Set(document.layers.map(\.id))) else {
      throw CraftError.invalid("Select existing layers.")
    }
    return document.layers.indices.filter { ids.contains(document.layers[$0].id) }
  }

  public static func setColor(
    _ color: LayerColorLabel, selected: Set<UUID>, in document: inout CraftDocument
  ) throws {
    for index in try indices(selected, in: document) {
      // An absent label already means None; retain its original encoding on a no-op.
      if document.layers[index].colorLabel != color { document.layers[index].colorLabel = color }
    }
  }

  public static func setVisibility(_ values: [UUID: Bool], in document: inout CraftDocument) throws
  {
    for index in try indices(Set(values.keys), in: document) {
      document.layers[index].visible = values[document.layers[index].id]!
    }
  }

  public static func visibility(in document: CraftDocument) -> [UUID: Bool] {
    Dictionary(uniqueKeysWithValues: document.layers.map { ($0.id, $0.visible) })
  }

  /// Match the source's show_only visibility map: reveal the ancestor path, retain
  /// descendant flags, and hide other rows. Clipping does not change stored visibility.
  public static func isolatedVisibility(_ id: UUID, in document: CraftDocument) throws
    -> [UUID: Bool]
  {
    _ = try indices([id], in: document)
    let required = Set([id] + document.ancestors(of: id).map(\.id))
    let retained = document.subtreeIDs(id)
    return Dictionary(
      uniqueKeysWithValues: document.layers.map {
        ($0.id, required.contains($0.id) || (retained.contains($0.id) && $0.visible))
      })
  }
}
