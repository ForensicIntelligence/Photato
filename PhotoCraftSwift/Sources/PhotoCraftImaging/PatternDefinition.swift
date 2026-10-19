import Foundation
import PhotoCraftCore

public enum PatternDefinition {
  public static func make(in document: CraftDocument, name: String) throws -> RasterPattern {
    let bounds =
      (document.selection ?? IntRect(x: 0, y: 0, width: document.width, height: document.height))
      .clipped(toWidth: document.width, height: document.height)
    guard bounds.width > 0, bounds.height > 0, bounds.width <= 4000, bounds.height <= 4000 else {
      throw CraftError.invalid(
        "Define Pattern needs a nonempty area no larger than 4000 × 4000 pixels.")
    }
    // The source defines the composite selection bounding rectangle, not its feathered mask.
    let composite = try Renderer.composite(document)
    var pixels = try Surface(width: bounds.width, height: bounds.height, depth: document.depth)
    for y in 0..<bounds.height {
      try Task.checkCancellation()
      for x in 0..<bounds.width {
        pixels.setPixel(x: x, y: y, composite.pixel(x: bounds.x + x, y: bounds.y + y))
      }
    }
    return try RasterPattern(name: name, surface: pixels)
  }
}
