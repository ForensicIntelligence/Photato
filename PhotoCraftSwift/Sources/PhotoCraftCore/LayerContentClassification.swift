import Foundation

/// Immutable retained pixel storage for an asynchronous content query. Presentation,
/// masks, visibility and opacity do not determine whether a layer contains pixels.
public struct LayerContentSource: Sendable {
  public enum Payload: Sendable { case raster(Surface), native(NativeModeRaster), content }
  public struct Entry: Sendable {
    public let id: UUID
    public let payload: Payload
  }
  public let documentID: UUID
  public let entries: [Entry]
  public init(_ document: CraftDocument) {
    documentID = document.id
    entries = document.layers.map { layer in
      let payload: Payload
      if layer.isBackground || layer.video != nil || layer.videoTiming != nil {
        payload = .content
      } else if case .raster(let pixels) = layer.content {
        // Smart Objects retain a raster cache; transparent cached pixels also match
        // Empty in the owned Photoshop2026 reference. Never read linked source paths.
        payload = layer.nativeMode.map(Payload.native) ?? .raster(pixels)
      } else {
        // A childless group is Not Empty in Photoshop2026. Editable text, shapes,
        // fills and adjustments retain logical content independently of visibility.
        payload = .content
      }
      return Entry(id: layer.id, payload: payload)
    }
  }
  public func emptyLayerIDs() throws -> Set<UUID> {
    try Task.checkCancellation()
    var empty = Set<UUID>()
    for entry in entries {
      try Task.checkCancellation()
      switch entry.payload {
      case .raster(let pixels): if try !pixels.hasPixelContent() { empty.insert(entry.id) }
      case .native(let pixels): if try !pixels.hasAlphaContent() { empty.insert(entry.id) }
      case .content: break
      }
    }
    return empty
  }
}
