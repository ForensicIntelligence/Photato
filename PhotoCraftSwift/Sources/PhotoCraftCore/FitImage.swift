import Foundation

/// A reusable pixel bounding box, resolved independently for each input image.
public struct FitImageOptions: Codable, Equatable, Sendable {
  public var width: Int
  public var height: Int
  public var dontEnlarge: Bool
  public var method: Resampling
  public init(width: Int = 1024, height: Int = 1024, dontEnlarge: Bool = false, method: Resampling = .bicubic) {
    self.width = width; self.height = height; self.dontEnlarge = dontEnlarge; self.method = method
  }
  public func validate() throws {
    guard (1...Surface.maxDimension).contains(width), (1...Surface.maxDimension).contains(height) else {
      throw CraftError.invalid("Enter Fit Image bounds from 1 to 300,000 pixels per side.")
    }
  }
  public func dimensions(sourceWidth: Int, sourceHeight: Int) throws -> (width: Int, height: Int) {
    try validate()
    guard (1...Surface.maxDimension).contains(sourceWidth), (1...Surface.maxDimension).contains(sourceHeight) else {
      throw CraftError.invalid("Invalid Fit Image source dimensions.")
    }
    if dontEnlarge && sourceWidth <= width && sourceHeight <= height { return (sourceWidth, sourceHeight) }
    // Products are bounded by90 billion on both supported64-bit architectures.
    // Compare ratios exactly and round only the dependent dimension, half up.
    if width * sourceHeight <= height * sourceWidth {
      return (width, max(1, (sourceHeight * width + sourceWidth / 2) / sourceWidth))
    }
    return (max(1, (sourceWidth * height + sourceHeight / 2) / sourceHeight), height)
  }
  func apply(to document: inout CraftDocument) throws {
    let size = try dimensions(sourceWidth: document.width, sourceHeight: document.height)
    let resize = Command.imageSize(size.width, size.height, document.pixelsPerInch, method)
    try resize.validateVideoContext(in: document); try resize.validateAnimationContext(in: document)
    if size.width == document.width && size.height == document.height { try document.validate(); return }
    let resolution = document.resolution
    var candidate = document
    try resize.apply(to: &candidate)
    // Keep the optional default representation as well as the effective PPI.
    candidate.resolution = resolution
    try candidate.validate(); document = candidate
  }
}
