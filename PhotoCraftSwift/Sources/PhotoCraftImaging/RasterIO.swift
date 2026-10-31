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
    colorEncoding: SurfaceColorEncoding = .sRGB,
    intent: CGColorRenderingIntent = .relativeColorimetric
  ) throws -> CGImage {
    let data = try surface.rgbaData(depth: .f32, colorEncoding: colorEncoding)
    guard let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(
        width: surface.width, height: surface.height, bitsPerComponent: 32, bitsPerPixel: 128,
        bytesPerRow: surface.width * 16, space: try space ?? colorSpace(),
        bitmapInfo: [
          .floatComponents, .byteOrder32Little,
          CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        ], provider: provider, decode: nil, shouldInterpolate: true, intent: intent)
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
  public static func surface(
    _ image: CGImage, depth: PixelDepth = .u8,
    space workingSpace: CGColorSpace? = nil, colorEncoding: SurfaceColorEncoding = .sRGB
  ) throws -> Surface {
    _ = try Surface(width: image.width, height: image.height, depth: depth, colorEncoding: colorEncoding)
    if image.width * image.height > Surface.maximumDensePixels {
      return try pagedSurface(image, depth: depth, space: workingSpace, colorEncoding: colorEncoding)
    }
    let space = try workingSpace ?? colorSpace()
    if depth == .f32, colorEncoding == .linearRGB,
      let direct = try FloatRasterSamples.surface(image, space: space)
    {
      return direct
    }
    var result = try Surface(
      width: image.width, height: image.height, depth: depth, colorEncoding: colorEncoding)
    var pixels = [Float](repeating: 0, count: image.width * image.height * 4)
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
        let p = Pixel(pixels[i] * f, pixels[i + 1] * f, pixels[i + 2] * f, a)
        if colorEncoding == .linearRGB {
          result.setLinearPixel(x: x, y: y, p)
        } else {
          result.setPixel(x: x, y: y, p)
        }
      }
    }
    return result
  }
  public static func read(_ url: URL) throws -> CraftDocument {
    let ext = url.pathExtension.lowercased()
    if ext == "pcraft" {
      throw CraftError.unsupported(
        "Original .pcraft import is not ported yet. Export a PNG or TIFF from the source app to import a flattened copy."
      )
    }
    let source = try PSDFileSource(url)
    let name = url.deletingPathExtension().lastPathComponent
    if try source.bytes(at: 0, count: min(4, source.count)) == Data("8BPS".utf8) {
      return try PSDCodec.read(PSDReader(file: source), name: name,paging:PSDRasterPaging.Context())
    }
    // Preserve ImageIO's existing mapped-Data path. The bounded channel reader
    // above handles Photoshop containers; other formats keep their own pipeline.
    let result = try read(Data(contentsOf: url, options: .mappedIfSafe), name: name)
    try source.validateUnchanged()
    return result
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
    if AnimationGIF.recognizes(data) { return try AnimationGIF.read(data, name: name) }
    if let native = try PNGRestrictedStorage.read(data, name: name) { return native }
    if let native = try TIFFRestrictedStorage.read(data, name: name) { return native }
    if let native = try TIFFModeStorage.read(data, name: name) { return native }
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
    let embedded = image.colorSpace?.model == .rgb ? image.colorSpace?.copyICCData() as Data? : nil
    let working = try ColorManagement.importedProfile(embedded, depth: depth)
    var workingDocument = try CraftDocument(width: 1, height: 1, depth: depth)
    workingDocument.workingICC = working
    let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
    // ImageIO's planar Float32 path can supply NaN in place of alpha. Decode
    // supported TIFF samples directly when no profile conversion is needed.
    let nativeTIFF = embedded != nil && embedded == working
      ? try TIFFStorage.surface(data, depth: depth, encoding: encoding,
        space: ColorManagement.space(for: workingDocument)) : nil
    let pixels = try oriented(
      nativeTIFF ?? surface(
        image, depth: depth,
        space: ColorManagement.space(for: workingDocument),
        colorEncoding: encoding), orientation: orientation)
    var d = try CraftDocument(
      width: pixels.width, height: pixels.height, depth: depth,
      name: name)
    d.sourceICC = image.colorSpace?.copyICCData() as Data?
    d.workingICC = working
    if let embedded = try? UntaggedOutput.hasProfile(data), !embedded { d.profileIsUntagged = true }
    d.sourceMetadata = try RasterMetadata.capture(source, properties: properties)
    if let resolution = properties[kCGImagePropertyDPIWidth] as? Double, resolution.isFinite,
      (1...100_000).contains(resolution)
    {
      d.resolution = resolution
    }
    let l = Layer(name: name, content: .raster(pixels))
    d.layers = [l]
    d.activeLayerID = l.id
    return try TIFFLayers.read(data, composite: d) ?? d
  }
  public static func oriented(_ source: Surface, orientation: Int) throws -> Surface {
    guard (1...8).contains(orientation) else {
      throw CraftError.invalid("Invalid EXIF orientation.")
    }
    if orientation == 1 { return source }
    if source.width * source.height > Surface.maximumDensePixels {
      return try pagedOrientation(source, orientation: orientation)
    }
    let swapped = orientation >= 5
    var result = try Surface(
      width: swapped ? source.height : source.width, height: swapped ? source.width : source.height,
      depth: source.depth, colorEncoding: source.colorEncoding)
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
        if source.colorEncoding == .linearRGB {
          result.setLinearPixel(x: x, y: y, source.linearPixel(x: sx, y: sy))
        } else {
          result.setPixel(x: x, y: y, source.pixel(x: sx, y: sy))
        }
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
    outputDepth: PixelDepth? = nil, sourceMetadata: [String: Data]? = nil,
    workingDocument: CraftDocument? = nil, options: RasterEncodingOptions = .init()
  ) throws -> Data {
    let bytes = try encodedManaged(surface, type: type, resolution: resolution, outputDepth: outputDepth,
      sourceMetadata: sourceMetadata, workingDocument: workingDocument, options: options)
    return try workingDocument?.profileIsUntagged == true ? UntaggedOutput.strip(bytes, type: type) : bytes
  }
  private static func encodedManaged(
    _ surface: Surface, type: UTType = .png, resolution: Double = 72,
    outputDepth: PixelDepth? = nil, sourceMetadata: [String: Data]? = nil,
    workingDocument: CraftDocument? = nil, options: RasterEncodingOptions = .init()
  ) throws -> Data {
    try Task.checkCancellation()
    try options.validate(for: type)
    if type == .tiff, workingDocument?.inkMode != nil { throw CraftError.unsupported("Ink-mode TIFF interchange is still being implemented. Save as Photato to retain ink samples.") }
    if type == .tiff, let document = workingDocument, document.hasNativeModeStorage {
      guard options.tiffLayers != true else { throw CraftError.invalid("Layered TIFF encoding requires a document.") }
      return try TIFFModeStorage.write(surface, document: document, resolution: resolution,
        depth: outputDepth ?? surface.depth, metadata: sourceMetadata, options: options)
    }
    guard options.tiffLayers != true else {
      throw CraftError.invalid("Layered TIFF encoding requires a document.")
    }
    guard resolution.isFinite, (1...100_000).contains(resolution) else {
      throw CraftError.invalid("Invalid export resolution.")
    }
    guard [.png, .jpeg, .tiff].contains(type) else {
      throw CraftError.unsupported("Choose PNG, JPEG or TIFF.")
    }
    let floatTIFF = type == .tiff && (outputDepth ?? surface.depth) == .f32
    let image: CGImage
    let exportSpace: CGColorSpace
    let bits: Int
    let profileName: String?
    if floatTIFF {
      var target = try CraftDocument(width: 1, height: 1, depth: .f32)
      target.workingICC = try ColorManagement.importedProfile(workingDocument?.workingICC, depth: .f32)
      exportSpace = try ColorManagement.space(for: target)
      let pixels = try workingDocument.map {
        try ColorManagement.converted(surface, from: $0, to: target)
      } ?? surface
      // ImageIO otherwise replaces the ICC rendering-intent header with the
      // CGImage intent. Default retains the source profile's own intent.
      image = try cgImage(pixels, space: exportSpace, colorEncoding: .linearRGB, intent: .defaultIntent)
      bits = 32
      profileName = ColorManagement.name(target)
    } else {
      let original =
        try workingDocument.map { try ColorManagement.image(surface, in: $0) } ?? cgImage(surface)
      // Integer exports retain the working profile. HDR-to-integer uses explicit SDR sRGB conversion.
      exportSpace =
        try workingDocument.flatMap { $0.depth == .f32 ? nil : $0 }
        .map { try ColorManagement.space(for: $0) } ?? colorSpace()
      bits = type == .jpeg || (outputDepth ?? surface.depth) == .u8 ? 8 : 16
      let alpha = type == .jpeg ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
      let info = alpha.rawValue | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
      guard
        let context = CGContext(
          data: nil, width: surface.width, height: surface.height, bitsPerComponent: bits,
          bytesPerRow: 0, space: exportSpace, bitmapInfo: info)
      else { throw CraftError.invalid("Could not allocate an export image.") }
      if type == .jpeg {
        if let matte = options.jpegMatte,
          let color = CGColor(colorSpace: try colorSpace(), components: matte.map { CGFloat($0) } + [CGFloat(1)]) {
          context.setFillColor(color)
        } else {
          context.setFillColor(CGColor(gray: 1, alpha: 1))
        }
        context.fill(CGRect(x: 0, y: 0, width: surface.width, height: surface.height))
      }
      context.draw(original, in: CGRect(x: 0, y: 0, width: surface.width, height: surface.height))
      guard let rendered = context.makeImage() else {
        throw CraftError.invalid("Export image creation failed.")
      }
      image = rendered
      profileName = workingDocument.map { $0.depth == .f32 ? "sRGB" : ColorManagement.name($0) }
    }
    let isSRGB = exportSpace == (try colorSpace())
    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
    else { throw CraftError.invalid("Encoder unavailable.") }
    var properties = try RasterMetadata.properties(
      sourceMetadata, width: surface.width, height: surface.height, resolution: resolution,
      bits: bits, isSRGB: isSRGB)
    properties[kCGImageDestinationLossyCompressionQuality] = 0.95
    if let quality = options.jpegQuality {
      properties[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 12
    }
    if let format = options.jpegFormat {
      var jfif = properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any] ?? [:]
      jfif[kCGImagePropertyJFIFIsProgressive] = format == .progressive
      properties[kCGImagePropertyJFIFDictionary] = jfif
    }
    if let interlaced = options.pngInterlaced {
      var png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]
      png[kCGImagePropertyPNGInterlaceType] = interlaced ? 1 : 0
      properties[kCGImagePropertyPNGDictionary] = png
    }
    if let compression = options.hasTIFFStorageOptions
      ? RasterEncodingOptions.TIFFCompression.none : options.tiffCompression {
      var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
      tiff[kCGImagePropertyTIFFCompression] = compression.tag
      properties[kCGImagePropertyTIFFDictionary] = tiff
    }
    CGImageDestinationAddImageAndMetadata(
      dest, image,
      try RasterMetadata.metadata(
        sourceMetadata, width: surface.width, height: surface.height, resolution: resolution,
        linear: floatTIFF, profileName: profileName,
        isSRGB: isSRGB),
      properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      throw CraftError.invalid("Image encoding failed.")
    }
    try Task.checkCancellation()
    if type == .jpeg && options.hasJPEGOptions {
      var data = output as Data
      if options.jpegFormat == .optimized { data = try JPEGEntropyOptimizer.optimize(data) }
      if options.jpegEmbedProfile == false { data = try JPEGContainer.withoutICC(data) }
      if options.jpegEmbedProfile == true {
        guard let profile = exportSpace.copyICCData() as Data? else {
          throw CraftError.invalid("The JPEG working color profile is unavailable.")
        }
        data = try JPEGContainer.embeddingICC(profile, into: data)
      }
      return data
    }
    if options.hasTIFFStorageOptions { return try TIFFStorage.rewrite(output as Data, options: options) }
    if let level = options.pngCompression {
      return try PNGCompression.rewrite(output as Data, level: level)
    }
    return output as Data
  }
  /// Composition uses a float working surface; exports retain the document depth
  /// rather than accidentally promoting every RGB8 document to 16-bit output.
  public static func encoded(_ document: CraftDocument, type: UTType = .png,
    options: RasterEncodingOptions = .init()) throws -> Data {
    if type == .tiff, document.inkMode != nil { throw CraftError.unsupported("Ink-mode TIFF interchange is still being implemented. Save as Photato to retain ink samples.") }
    if document.restrictedMode != nil, type == .png {
      try options.validate(for: type); return try PNGRestrictedStorage.write(document, options: options)
    }
    if document.restrictedMode != nil, type == .tiff {
      return try TIFFRestrictedStorage.write(document, options: options)
    }
    try options.validate(for: type)
    var compositeOptions = options
    compositeOptions.tiffLayers = nil; compositeOptions.tiffLayerCompression = nil
    if options.tiffLayers == true, compositeOptions.tiffByteOrder == nil {
      compositeOptions.tiffByteOrder = .bigEndian
    }
    if type == .tiff, document.hasNativeModeStorage {
      let composite = try TIFFModeStorage.write(Renderer.composite(document), document: document,
        resolution: document.pixelsPerInch, depth: document.depth, metadata: document.sourceMetadata,
        options: compositeOptions, preserveSingleLayer: true)
      return options.tiffLayers == true
        ? try TIFFLayers.write(document, composite: composite, compression: options.tiffLayerCompression ?? .zip)
        : composite
    }
    let composite = try encoded(
      Renderer.composite(document), type: type,
      resolution: document.pixelsPerInch, outputDepth: document.depth,
      sourceMetadata: document.sourceMetadata, workingDocument: document, options: compositeOptions)
    return options.tiffLayers == true
      ? try TIFFLayers.write(document, composite: composite, compression: options.tiffLayerCompression ?? .zip)
      : composite
  }
  public static func write(_ document: CraftDocument, to url: URL, type: UTType = .png) throws {
    try encoded(document, type: type).write(to: url, options: .atomic)
  }
}
