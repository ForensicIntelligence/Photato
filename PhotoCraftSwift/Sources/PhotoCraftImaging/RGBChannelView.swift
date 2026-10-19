import PhotoCraftCore

/// Per-document display state, independent of stored pixels and channel edit targets.
/// Component editing is a separate capability; this type never changes document data.
public struct RGBChannelView: Equatable, Sendable {
  public private(set) var preview: RGBChannelPreview
  public private(set) var visible: Set<RGBChannelPreview>
  public static let components: Set<RGBChannelPreview> = [.red, .green, .blue]

  public init(preview: RGBChannelPreview = .composite) {
    self.preview = preview
    visible = preview == .composite ? Self.components : [preview]
  }

  public func isVisible(_ channel: RGBChannelPreview) -> Bool {
    channel == .composite ? visible == Self.components : visible.contains(channel)
  }

  public mutating func selectPreview(_ channel: RGBChannelPreview) {
    if channel == .composite {
      visible = Self.components
    } else if preview == .composite || !visible.contains(channel) {
      visible = [channel]
    }
    // Photoshop retains a custom combination when selecting an already-visible component.
    preview = channel
  }

  public mutating func setVisible(_ channel: RGBChannelPreview, _ value: Bool) {
    let affected = channel == .composite ? Self.components : [channel]
    let proposed = value ? visible.union(affected) : visible.subtracting(affected)
    // Without alpha/spot rows there must always be at least one visible component.
    if !proposed.isEmpty { visible = proposed }
  }

  public func applying(to source: Surface) throws -> Surface {
    try Task.checkCancellation()
    if visible == Self.components { return source }
    var result = source
    let single = visible.count == 1 ? visible.first : nil
    try result.mapPixels(in: IntRect(x: 0, y: 0, width: source.width, height: source.height)) {
      _, _, pixel in
      if let single {
        let value = single == .red ? pixel.r : single == .green ? pixel.g : pixel.b
        return Pixel(value, value, value, pixel.a)
      }
      return Pixel(
        visible.contains(.red) ? pixel.r : 0,
        visible.contains(.green) ? pixel.g : 0,
        visible.contains(.blue) ? pixel.b : 0, pixel.a)
    }
    try Task.checkCancellation()
    return result
  }
}
