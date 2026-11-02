import Foundation

/// Shared File > New / isolated resource-job document creation.
public enum DocumentCreation {
  public static func blank(width: Int = 1200, height: Int = 800,
    depth: PixelDepth = .u8, background: Pixel = .white, name: String = "Untitled-1",
    mode: DocumentColorMode? = nil, profile: Data? = nil, resolution: Double? = nil
  ) throws -> CraftDocument {
    try Task.checkCancellation()
    guard background.isFinite, (0...1).contains(background.a),
      (resolution ?? 72).isFinite, (1...100_000).contains(resolution ?? 72) else {
      throw CraftError.invalid("Choose a finite background and resolution between 1 and 100,000 pixels/inch.")
    }
    if let mode, mode != .rgb {
      guard width > 0, height > 0, width <= NativeModeRaster.maximumPixels / height else {
        throw CraftError.invalid("Native color-mode documents support up to 8,388,608 pixels.")
      }
      _ = try DocumentModeDescriptor(mode: mode, depth: depth, profile: profile)
    } else if mode == nil, profile != nil {
      throw CraftError.invalid("Choose a document color mode before assigning its profile.")
    }
    var document = try CraftDocument(width: width, height: height, depth: depth, name: name)
    document.layers[0].content = .raster(
      try Surface(width: width, height: height, depth: depth, fill: background))
    document.layers[0].name = background.a == 0 ? "Layer 1" : "Background"
    document.resolution = resolution
    if let mode {
      if mode == .rgb, width * height > NativeModeRaster.maximumPixels {
        let descriptor = try DocumentModeDescriptor(mode: mode, depth: depth, profile: profile)
        document.workingICC = descriptor.profile
        document.layers[0].content = .raster(try Surface(width: width, height: height, depth: depth,
          fill: background, colorEncoding: depth == .f32 ? .linearRGB : .sRGB))
      } else {
        document = try document.convertingMode(.init(mode: mode, depth: depth, profile: profile))
      }
    }
    if document.colorMode == .rgb,background.a==1 {document.layers[0].background=true}
    try document.validate()
    return document
  }
}
