import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers

public enum RasterIO {
  public static func colorSpace() throws -> CGColorSpace {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw CraftError.unavailable("The sRGB color space is unavailable.")
    }
    return space
  }
  public static func cgImage(
    _ surface: Surface, space: CGColorSpace? = nil,
    colorEncoding: SurfaceColorEncoding = .sRGB
  ) throws -> CGImage {
    let data = try surface.rgbaData(depth: .f32, colorEncoding: colorEncoding)
    guard let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(
        width: surface.width, height: surface.height, bitsPerComponent: 32, bitsPerPixel: 128,
        bytesPerRow: surface.width * 16, space: try space ?? colorSpace(),
        bitmapInfo: [
          .floatComponents, .byteOrder32Little,
          CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        ], provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric)
    else { throw CraftError.invalid("Could not create a native image.") }
    return image
  }
  // Display uses an SDR sRGB CGImage. Float working buffers remain unchanged for editing.
  // This avoids implicit EDR tone mapping of float CGImages by AppKit on HDR displays.
  public static func displayImage(_ surface: Surface) throws -> CGImage {
    let data = try surface.rgbaData(depth: .u8)
    guard let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(
        width: surface.width, height: surface.height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: surface.width * 4, space: try colorSpace(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
        decode: nil, shouldInterpolate: true, intent: .relativeColorimetric)
    else { throw CraftError.invalid("Could not create the display preview.") }
    return image
  }
  public static func surface(_ image: CGImage, depth: PixelDepth = .u8) throws -> Surface {
    var result = try Surface(width: image.width, height: image.height, depth: depth)
    var pixels = [Float](repeating: 0, count: image.width * image.height * 4)
    let space = try colorSpace()
    try pixels.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 32,
          bytesPerRow: image.width * 16, space: space,
          bitmapInfo: CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
      else { throw CraftError.invalid("Could not allocate the color conversion buffer.") }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    for y in 0..<image.height {
      for x in 0..<image.width {
        let i = (y * image.width + x) * 4
        let a = unit(pixels[i + 3])
        let f = a > 0 ? 1 / a : 0
        result.setPixel(x: x, y: y, Pixel(pixels[i] * f, pixels[i + 1] * f, pixels[i + 2] * f, a))
      }
    }
    return result
  }
  public static func read(_ url: URL) throws -> CraftDocument {
    let ext = url.pathExtension.lowercased()
    if ext == "psd" {
      return try PSDCodec.read(
        Data(contentsOf: url, options: .mappedIfSafe),
        name: url.deletingPathExtension().lastPathComponent)
    }
    if ["psb", "pcraft"].contains(ext) {
      throw CraftError.unsupported(
        "PSB and original .pcraft import are not ported yet. Export a PNG or TIFF from the source app to import a flattened copy."
      )
    }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("Image exceeds the 512 MiB input limit.")
    }
    return try read(
      Data(contentsOf: url, options: .mappedIfSafe),
      name: url.deletingPathExtension().lastPathComponent)
  }
  /// The same native import path for files and API resources. No temporary files
  /// or extension inferred from an untrusted resource URL are required.
  public static func read(_ data: Data, name: String = "Imported Image") throws -> CraftDocument {
    try Task.checkCancellation()
    guard data.count <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("Image exceeds the 512 MiB input limit.")
    }
    if data.starts(with: Data("8BPS".utf8)) {
      return try PSDCodec.read(data, name: name)
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = properties[kCGImagePropertyPixelWidth] as? Int,
      let h = properties[kCGImagePropertyPixelHeight] as? Int
    else { throw CraftError.invalid("The file is not a supported raster image.") }
    _ = try Surface(width: w, height: h)
    guard
      let image = CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { throw CraftError.invalid("Image decoding failed.") }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let depth: PixelDepth =
      image.bitsPerComponent > 16 ? .f32 : image.bitsPerComponent > 8 ? .u16 : .u8
    let pixels = try oriented(surface(image, depth: depth), orientation: orientation)
    var d = try CraftDocument(
      width: pixels.width, height: pixels.height, depth: depth,
      name: name)
    d.sourceICC = image.colorSpace?.copyICCData() as Data?
    d.sourceMetadata = try RasterMetadata.capture(source, properties: properties)
    if let resolution = properties[kCGImagePropertyDPIWidth] as? Double, resolution.isFinite,
      (1...100_000).contains(resolution)
    {
      d.resolution = resolution
    }
    let l = Layer(name: name, content: .raster(pixels))
    d.layers = [l]
    d.activeLayerID = l.id
    return d
  }
  public static func oriented(_ source: Surface, orientation: Int) throws -> Surface {
    guard (1...8).contains(orientation) else {
      throw CraftError.invalid("Invalid EXIF orientation.")
    }
    if orientation == 1 { return source }
    let swapped = orientation >= 5
    var result = try Surface(
      width: swapped ? source.height : source.width, height: swapped ? source.width : source.height,
      depth: source.depth)
    for y in 0..<result.height {
      for x in 0..<result.width {
        let sx: Int
        let sy: Int
        switch orientation {
        case 2: (sx, sy) = (source.width - 1 - x, y)
        case 3: (sx, sy) = (source.width - 1 - x, source.height - 1 - y)
        case 4: (sx, sy) = (x, source.height - 1 - y)
        case 5: (sx, sy) = (y, x)
        case 6: (sx, sy) = (y, source.height - 1 - x)
        case 7: (sx, sy) = (source.width - 1 - y, source.height - 1 - x)
        case 8: (sx, sy) = (source.width - 1 - y, x)
        default: (sx, sy) = (x, y)
        }
        result.setPixel(x: x, y: y, source.pixel(x: sx, y: sy))
      }
    }
    return result
  }
  public static func write(
    _ surface: Surface, to url: URL, type: UTType = .png, resolution: Double = 72
  ) throws {
    try encoded(surface, type: type, resolution: resolution).write(to: url, options: .atomic)
  }
  public static func encoded(
    _ surface: Surface, type: UTType = .png, resolution: Double = 72,
    outputDepth: PixelDepth? = nil, sourceMetadata: [String: Data]? = nil
  ) throws -> Data {
    try Task.checkCancellation()
    guard resolution.isFinite, (1...100_000).contains(resolution) else {
      throw CraftError.invalid("Invalid export resolution.")
    }
    guard [.png, .jpeg, .tiff].contains(type) else {
      throw CraftError.unsupported("Choose PNG, JPEG or TIFF.")
    }
    let original = try cgImage(surface)
    // PNG/TIFF retain 16-bit integer precision. JPEG is explicitly an 8-bit flattened export.
    let bits = type == .jpeg || (outputDepth ?? surface.depth) == .u8 ? 8 : 16
    let alpha = type == .jpeg ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    let info = alpha.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
    guard
      let context = CGContext(
        data: nil, width: surface.width, height: surface.height, bitsPerComponent: bits,
        bytesPerRow: 0, space: try colorSpace(), bitmapInfo: info)
    else { throw CraftError.invalid("Could not allocate an export image.") }
    if type == .jpeg {
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: surface.width, height: surface.height))
    }
    context.draw(original, in: CGRect(x: 0, y: 0, width: surface.width, height: surface.height))
    guard let image = context.makeImage() else {
      throw CraftError.invalid("Export image creation failed.")
    }
    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
    else { throw CraftError.invalid("Encoder unavailable.") }
    var properties = try RasterMetadata.properties(
      sourceMetadata, width: surface.width, height: surface.height, resolution: resolution,
      bits: bits)
    properties[kCGImageDestinationLossyCompressionQuality] = 0.95
    CGImageDestinationAddImageAndMetadata(
      dest, image,
      try RasterMetadata.metadata(
        sourceMetadata, width: surface.width, height: surface.height, resolution: resolution),
      properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      throw CraftError.invalid("Image encoding failed.")
    }
    try Task.checkCancellation()
    return output as Data
  }
  /// Composition uses a float working surface; exports retain the document depth
  /// rather than accidentally promoting every RGB8 document to 16-bit output.
  public static func encoded(_ document: CraftDocument, type: UTType = .png) throws -> Data {
    try encoded(
      Renderer.composite(document), type: type,
      resolution: document.pixelsPerInch, outputDepth: document.depth,
      sourceMetadata: document.sourceMetadata)
  }
  public static func write(_ document: CraftDocument, to url: URL, type: UTType = .png) throws {
    try encoded(document, type: type).write(to: url, options: .atomic)
  }
}
