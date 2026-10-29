import PhotoCraftCore

public enum InkChannelPresentation {
  /// A single visible Multichannel plate is displayed as numeric gray. Multiple
  /// visible plates use their stored printing colors in the original order.
  public static func surface(_ document: CraftDocument, visible: Set<InkChannelTarget>? = nil) throws -> Surface {
    guard let ink = document.inkMode else { throw CraftError.invalid("Ink preview requires an ink document.") }
    if let visible {
      guard !visible.isEmpty, visible.isSubset(of: Set(document.inkChannelTargets)) else { throw CraftError.invalid("Choose valid visible ink channels.") }
    }
    guard case .multichannel(let raster) = ink, let visible else { return try ink.surface() }
    let plates = raster.plates.filter { visible.contains(.plate($0.id)) }
    if plates.count == 1 { return try plates[0].samples.surface(inverted: true) }
    return try InkModeRaster.multichannel(MultichannelRaster(plates: plates)).surface()
  }
  public static func thumbnails(_ document: CraftDocument, maximumSize: Int) throws -> [Surface] {
    try document.inkChannelTargets.map { target in
      let pixels = try document.inkChannel(target).surface(inverted: target.inverted)
      return try Renderer.channelThumbnails(pixels, maximumSize: maximumSize)[0]
    }
  }
}
