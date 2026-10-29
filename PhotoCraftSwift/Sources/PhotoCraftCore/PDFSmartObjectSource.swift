import Foundation

/// A selected PDF page and a frozen crop in its oriented page-box coordinates.
/// Keeping the crop in points prevents raster-resolution-dependent bounds drift.
public struct PDFSmartObjectSource: Codable, Equatable, Sendable {
  public enum Crop: String, Codable, CaseIterable, Sendable {
    case bounding, media, crop, bleed, trim, art
  }
  public var page: Int
  /// Global embedded-image number, when selecting an image instead of a page.
  public var image: Int?
  public var crop: Crop
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double
  public var antialias: Bool
  public init(page: Int, crop: Crop, x: Double, y: Double,
    width: Double, height: Double, antialias: Bool = true, image: Int? = nil) throws {
    self.image = image
    self.page = page; self.crop = crop; self.x = x; self.y = y
    self.width = width; self.height = height; self.antialias = antialias
    try validate()
  }
  public func validate() throws {
    if let image {
      guard (1...4096).contains(image), crop == .media, x == 0, y == 0 else {
        throw CraftError.invalid("Invalid embedded PDF image selection.")
      }
    }
    guard (1...4096).contains(page), [x,y,width,height].allSatisfy(\.isFinite),
      x >= 0, y >= 0, width > 0, height > 0, x + width <= 1_000_000,
      y + height <= 1_000_000 else { throw CraftError.invalid("Invalid PDF Smart Object page or crop bounds.") }
  }
}
