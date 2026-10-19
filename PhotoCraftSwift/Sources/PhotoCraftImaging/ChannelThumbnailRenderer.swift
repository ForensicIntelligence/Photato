import Foundation
import PhotoCraftCore

public enum RGBChannelPreview: Int, CaseIterable, Sendable {
  case composite, red, green, blue
  public var title: String {
    switch self {
    case .composite: "RGB"
    case .red: "Red"
    case .green: "Green"
    case .blue: "Blue"
    }
  }
}

extension Renderer {
  /// Sample the unfiltered composite once, then derive independent grayscale components.
  /// These are display thumbnails; neither channel targeting nor document pixels change.
  public static func channelThumbnails(_ source: Surface, maximumSize: Int) throws -> [Surface] {
    guard (1...512).contains(maximumSize) else {
      throw CraftError.invalid("Invalid channel thumbnail size.")
    }
    try Task.checkCancellation()
    let scale = min(1, Double(maximumSize) / Double(max(source.width, source.height)))
    let width = max(1, Int((Double(source.width) * scale).rounded(.down)))
    let height = max(1, Int((Double(source.height) * scale).rounded(.down)))
    var composite: Surface
    if width == source.width && height == source.height {
      composite = source
    } else {
      composite = try Surface(width: width, height: height, depth: source.depth)
      var coverage = ThumbnailCoverage(
        mapping: .scale(
          Double(source.width) / Double(width), Double(source.height) / Double(height)))
      for y in 0..<height {
        try Task.checkCancellation()
        for x in 0..<width {
          composite.setPixel(x: x, y: y, try coverage.sample(source, x: x, y: y))
        }
      }
    }
    var result = [composite]
    for channel in [RGBChannelPreview.red, .green, .blue] {
      try Task.checkCancellation()
      var component = composite
      component.mapPixels { _, _, p in
        let value = channel == .red ? p.r : channel == .green ? p.g : p.b
        return Pixel(value, value, value, p.a)
      }
      result.append(component)
    }
    return result
  }
}
