import Foundation
import PhotoCraftCore

/// A bounded display buffer in top-left document coordinates. Never changes source samples.
public struct RasterPreviewRequest: Equatable, Sendable {
  public static let maximumPixels = 4_194_304
  public let region: IntRect
  public let width: Int
  public let height: Int

  public init(region: IntRect, width: Int, height: Int) throws {
    guard region.x >= 0, region.y >= 0,
      region.x <= Surface.maxDimension, region.y <= Surface.maxDimension,
      region.width > 0, region.height > 0,
      region.width <= Surface.maxDimension, region.height <= Surface.maxDimension,
      region.x + region.width <= Surface.maxDimension,
      region.y + region.height <= Surface.maxDimension,
      width > 0, height > 0, width <= region.width, height <= region.height,
      width <= Self.maximumPixels / height
    else { throw CraftError.invalid("Invalid bounded preview region or pixel budget.") }
    self.region = region; self.width = width; self.height = height
  }

  public static func overview(width: Int, height: Int) throws -> Self {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension
    else { throw CraftError.invalid("Invalid overview dimensions.") }
    let scale = min(1, 2048 / Double(max(width, height)))
    return try Self(region: .init(x: 0, y: 0, width: width, height: height),
      width: max(1, Int(Double(width) * scale)), height: max(1, Int(Double(height) * scale)))
  }

  public func reducing(_ source: Surface) throws -> Surface {
    try source.reducedPreview(in: region, width: width, height: height)
  }
}
