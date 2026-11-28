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
    return try PSDFileSource.withStableMetadata(url) { source in
      let name = url.deletingPathExtension().lastPathComponent
      let header = try source.bytes(at: 0, count: min(4, source.count))
      if header == Data("8BPS".utf8) {
        return try PSDCodec.read(PSDReader(file: source), name: name, paging: PSDRasterPaging.Context())
      }
      if TIFFContainer.isBigTIFF(header) {
        let restricted = try TIFFRestrictedStorage.readBigTIFF(source, name: name)
        guard let result = try restricted ?? TIFFModeStorage.read(source, url: url, name: name) else {
          throw CraftError.unsupported("This BigTIFF sample layout is not supported.")
        }
        try source.validateUnchanged()
        return result
      }
      if source.count > TIFFContainer.byteLimit, TIFFContainer.isClassic(header) {
        guard let result = try TIFFModeStorage.read(source, url: url, name: name) else {
          throw CraftError.unsupported("Large classic TIFF files currently require supported RGB, Grayscale, CMYK or Lab strips.")
        }
        try source.validateUnchanged()
        return result
      }
      // Preserve ImageIO's existing mapped-Data path. The bounded channel reader
      // above handles Photoshop containers; other formats keep their own pipeline.
      let result = try read(Data(contentsOf: url, options: .mappedIfSafe), name: name)
      try source.validateUnchanged()
      return result
    }
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
    if OpenEXR.recognizes(data) { return try OpenEXR.read(data,name:name) }
    if AnimationGIF.recognizes(data) { return try AnimationGIF.read(data, name: name) }
    if let native = try PNGRestrictedStorage.read(data, name: name) { return native }
    if let native = try TIFFRestrictedStorage.read(data, name: name) { return native }
    if let native = try TIFFModeStorage.read(data, name: name) { return native }
    if TIFFContainer.isBigTIFF(data) { throw CraftError.unsupported("This BigTIFF sample layout is not supported.") }
    let jpegXL = JPEGXLInput.recognizes(data)
    if jpegXL {
      guard JPEGXLInput.isAvailable else {
        throw CraftError.unavailable("JPEG XL reading is unavailable on this version of macOS.")
      }
      try JPEGXLInput.requireStill(data)
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = properties[kCGImagePropertyPixelWidth] as? Int,
      let h = properties[kCGImagePropertyPixelHeight] as? Int
    else { throw CraftError.invalid("The file is not a supported raster image.") }
    _ = try Surface(width: w, height: h)
    // ImageIO may materialize the complete decoded source before paging.
    if jpegXL, w > JPEGXLInput.maximumDecodedPixels / h {
      throw CraftError.unsupported("This JPEG XL image exceeds the decoder's 1 GiB raster budget.")
    }
    if jpegXL, CGImageSourceGetCount(source) != 1 {
      throw CraftError.unsupported("Open a still JPEG XL image. Animated JPEG XL is not supported.")
    }
    guard
      let image = CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { throw CraftError.invalid("Image decoding failed.") }
    if jpegXL, CGImageSourceGetStatusAtIndex(source, 0) != .statusComplete {
      throw CraftError.invalid("The JPEG XL image is incomplete.")
    }
    let completePNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
      && CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
    if completePNG, let grayscale = try PNGGrayscaleStorage.read(image, from: source, data: data,
      name: name, properties: properties) {
      return grayscale
    }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let depth: PixelDepth =
      image.bitsPerComponent > 16 ? .f32 : image.bitsPerComponent > 8 ? .u16 : .u8
    let embedded = image.colorSpace?.model == .rgb ? image.colorSpace?.copyICCData() as Data? : nil
    let working = try ColorManagement.importedProfile(embedded, depth: depth)
    var workingDocument = try CraftDocument(width: 1, height: 1, depth: depth)
    workingDocument.workingICC = working
    let workingSpace = try ColorManagement.space(for: workingDocument)
    let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
    // ImageIO's planar Float32 path can supply NaN in place of alpha. Decode
    // supported TIFF samples directly when no profile conversion is needed.
    let nativeTIFF = embedded != nil && embedded == working
      ? try TIFFStorage.surface(data, depth: depth, encoding: encoding,
        space: workingSpace) : nil
    let straightPNG = completePNG ? try straightPNGSurface(image, depth: depth, space: workingSpace) : nil
    let pixels = try oriented(
      nativeTIFF ?? straightPNG ?? surface(image, depth: depth, space: workingSpace, colorEncoding: encoding),
      orientation: orientation)
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

  package static func tiffInputDimensions(_ data: Data) throws -> (width: Int, height: Int)? {
    guard TIFFContainer.recognizes(data) else { return nil }
    let file = try TIFFContainer(data, metadata: false)
    return try (file.scalar(256), file.scalar(257))
  }

  /// The resource server admits numerical TIFF samples using the same paged
  /// strips and editable layer model as desktop Open.
  package static func readPagedComponentTIFF(_ data: Data, name: String) throws -> CraftDocument? {
    try TIFFModeStorage.read(data, name: name, forcePaged: true)
  }

  /// The action-resource path uses this when the general unpaged PNG limit
  /// would reject an indexed source that can be expanded a tile at a time.
  package static func readPagedPalettePNG(_ data: Data, name: String) throws -> CraftDocument? {
    try PNGRestrictedStorage.read(data, name: name, requirePagedRGB: true)
  }

  /// ImageIO exposes straight integer PNG samples. Reading them directly keeps
  /// RGB under zero alpha, which drawing into a premultiplied context discards.
  private static func straightPNGSurface(_ image: CGImage, depth: PixelDepth, space: CGColorSpace) throws -> Surface? {
    guard depth == .u8 || depth == .u16, let sourceSpace = image.colorSpace,
      sourceSpace.model == .rgb, space.model == .rgb, image.decode == nil,
      !image.isMask, image.alphaInfo == .last, !image.bitmapInfo.contains(.floatComponents)
    else { return nil }
    if sourceSpace != space {
      guard let sourceProfile = sourceSpace.copyICCData() as Data?, let targetProfile = space.copyICCData() as Data?,
        sourceProfile == targetProfile else { return nil }
    }
    let componentBytes = depth == .u8 ? 1 : 2
    let pixelBytes = 4 * componentBytes
    let order = image.bitmapInfo.intersection(.byteOrderMask)
    guard image.bitsPerComponent == componentBytes * 8, image.bitsPerPixel == pixelBytes * 8,
      depth == .u8 || order == .byteOrder16Little || order == .byteOrder16Big else { return nil }
    let width = image.width, height = image.height, rowBytes = image.bytesPerRow
    // Keep ImageIO's complete provider within the existing 1 GiB budget.
    guard width > 0, height > 0, rowBytes >= width * pixelBytes,
      rowBytes <= 1_073_741_824 / height,
      let data = image.dataProvider?.data as Data?, data.count >= rowBytes * (height - 1) + width * pixelBytes
    else { return nil }

    return try data.withUnsafeBytes { bytes in
      func sample(_ offset: Int) -> Float {
        if depth == .u8 { return Float(bytes[offset]) / 255 }
        let word = bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        return Float(order == .byteOrder16Little ? UInt16(littleEndian: word) : UInt16(bigEndian: word)) / 65535
      }
      func patch(_ area: IntRect) throws -> Surface {
        var result = try Surface(width: area.width, height: area.height, depth: depth)
        for y in 0..<area.height {
          try Task.checkCancellation()
          let row = (area.y + y) * rowBytes + area.x * pixelBytes
          for x in 0..<area.width {
            let offset = row + x * pixelBytes
            let pixel = Pixel(sample(offset), sample(offset + componentBytes),
              sample(offset + 2 * componentBytes), sample(offset + 3 * componentBytes))
            if pixel != .clear { result.setPixel(x: x, y: y, pixel) }
          }
        }
        return result
      }
      if width > Surface.maximumDensePixels / height {
        return try pagedRaster(width: width, height: height, depth: depth, colorEncoding: .sRGB, patch: patch)
      }
      return try patch(IntRect(x: 0, y: 0, width: width, height: height))
    }
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
    var options = options
    if type == .tiff, options.tiffAlphaChannels == true || options.tiffSpotColors == true {
      throw CraftError.invalid("TIFF alpha and spot channel encoding requires a document.")
    }
    if type == .tiff, options.tiffEmbedProfile == nil, workingDocument?.profileIsUntagged == true {
      options.tiffEmbedProfile = false
    }
    if type == .tiff, options.tiffCompression == .jpeg {
      try options.validate(for: type)
      let mode = workingDocument?.colorMode ?? .rgb
      guard surface.depth == .u8, (outputDepth ?? surface.depth) == .u8,
        RasterEncodingOptions.supportsTIFFJPEG(width: surface.width, height: surface.height, depth: .u8, mode: mode),
        options.tiffLayers != true else {
        throw CraftError.unsupported("A flat JPEG-compressed TIFF requires 8-bit RGB or Grayscale, at most 30,000 pixels per side.")
      }
      var document = try CraftDocument(width: surface.width, height: surface.height, depth: .u8)
      document.resolution = resolution
      document.workingICC = workingDocument?.workingICC
      document.profileIsUntagged = workingDocument?.profileIsUntagged
      document.sourceMetadata = sourceMetadata
      document.layers[0].content = .raster(surface)
      if mode == .grayscale, let descriptor = workingDocument?.modeDescriptor {
        document.modeDescriptor = descriptor
        document.layers[0].nativeMode = try NativeModeRaster.converting(surface,
          to: .grayscale, depth: .u8, profile: descriptor.profile, intent: descriptor.intent, pagedOutput: true)
      }
      return try TIFFComponentExport.encoded(document, options: options)
    }
    let bytes = try encodedManaged(surface, type: type, resolution: resolution, outputDepth: outputDepth,
      sourceMetadata: sourceMetadata, workingDocument: workingDocument, options: options)
    if type == .tiff, options.tiffImagePyramid == true || options.tiffBigTIFF == true {
      return try TIFFComponentExport.encodedComposite(bytes, document: nil, resolution: resolution, options: options)
    }
    return try type != .tiff && workingDocument?.profileIsUntagged == true ? UntaggedOutput.strip(bytes, type: type) : bytes
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
      // Integer exports retain the working profile. HDR-to-integer uses explicit SDR sRGB conversion.
      exportSpace =
        try workingDocument.flatMap { $0.depth == .f32 ? nil : $0 }
        .map { try ColorManagement.space(for: $0) } ?? colorSpace()
      bits = type == .jpeg || (outputDepth ?? surface.depth) == .u8 ? 8 : 16
      if type == .png, (workingDocument?.depth ?? surface.depth) != .f32 {
        // PNG stores straight RGB. An integer premultiplied drawing surface
        // discards hidden color and rounds each partially transparent sample.
        let samples = try surface.rgbaData(depth: bits == 8 ? .u8 : .u16)
        var bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        if bits == 16 { bitmap.insert(.byteOrder16Little) }
        guard let provider = CGDataProvider(data: samples as CFData),
          let straight = CGImage(width: surface.width, height: surface.height, bitsPerComponent: bits,
            bitsPerPixel: bits * 4, bytesPerRow: surface.width * bits / 2, space: exportSpace,
            bitmapInfo: bitmap, provider: provider, decode: nil, shouldInterpolate: false,
            intent: .relativeColorimetric)
        else { throw CraftError.invalid("Could not allocate a straight-alpha PNG image.") }
        image = straight
      } else {
        let original =
          try workingDocument.map { try ColorManagement.image(surface, in: $0) } ?? cgImage(surface)
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
      }
      profileName = workingDocument.map { $0.depth == .f32 ? "sRGB" : ColorManagement.name($0) }
    }
    return try encodeImage(image, type: type, resolution: resolution, bits: bits, exportSpace: exportSpace,
      profileName: profileName, sourceMetadata: sourceMetadata, options: options, floatTIFF: floatTIFF)
  }

  private static func encodeImage(_ image: CGImage, type: UTType, resolution: Double, bits: Int,
    exportSpace: CGColorSpace, profileName: String?, sourceMetadata: [String: Data]?,
    options: RasterEncodingOptions, floatTIFF: Bool = false, photoshopMode: Int = 3) throws -> Data {
    let width = image.width, height = image.height
    let isSRGB = exportSpace == (try colorSpace())
    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
    else { throw CraftError.invalid("Encoder unavailable.") }
    var properties = try RasterMetadata.properties(
      sourceMetadata, width: width, height: height, resolution: resolution,
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
        sourceMetadata, width: width, height: height, resolution: resolution,
        linear: floatTIFF, profileName: profileName,
        isSRGB: isSRGB, photoshopMode: photoshopMode, embedsProfile: options.tiffEmbedProfile != false),
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

  static func retainedFlatRaster(in document: CraftDocument, width: Int, height: Int) -> NativeModeRaster? {
    guard document.layers.count == 1, let layer = document.layers.first,
      let stored = layer.nativeMode, layer.visible, layer.opacity == 1,
      layer.x == 0, layer.y == 0, layer.mask == nil, layer.vectorMask == nil,
      layer.style == nil, layer.smartObject == nil, layer.smartFilters == nil,
      layer.affine == nil, layer.warp == nil, layer.parentID == nil, layer.clipped != true,
      layer.blendMode == .normal, document.artboardOrigin == nil,
      stored.width == width, stored.height == height else { return nil }
    return stored
  }

  public static func supportsLayeredTIFFSavedAlpha(_ document: CraftDocument) -> Bool {
    DocumentColorMode.componentModes.contains(document.colorMode)
  }

  private static func pngComposite(_ document: CraftDocument) throws -> Surface {
    let rendered = try Renderer.composite(document)
    let visible = document.layers.filter { $0.visible && $0.opacity > 0 }
    guard rendered.width <= Surface.maximumDensePixels / rendered.height,
      Renderer.usesIntegerNormalRasterComposite(document),
      visible.allSatisfy({ $0.mask == nil }), let bottom = visible.first,
      case .raster(let samples) = bottom.content, try !rendered.isOpaque()
    else { return rendered }

    // Photoshop retains the bottom layer's hidden RGB within the visible
    // composite bounds, with transparent white where that layer does not reach.
    let white = Pixel(1, 1, 1, 0)
    guard let bounds = try rendered.contentBounds() else {
      return try Surface(width: rendered.width, height: rendered.height, depth: rendered.depth, fill: white)
    }
    let canvas = IntRect(x: 0, y: 0, width: rendered.width, height: rendered.height)
    return try rendered.compositingPixels(in: canvas) { x, y, pixel in
      guard pixel.a == 0 else { return nil }
      let localX = x - bottom.x, localY = y - bottom.y
      guard x >= bounds.x, x < bounds.x + bounds.width, y >= bounds.y, y < bounds.y + bounds.height,
        localX >= 0, localX < samples.width, localY >= 0, localY < samples.height
      else { return white }
      var hidden = samples.pixel(x: localX, y: localY)
      hidden.a = 0
      if document.depth == .u16 {
        return NormalLayerComposite.composite(backdrop: hidden, source: .clear, opacity: 0, depth: .u16)
      }
      return hidden
    }
  }

  /// Composition uses a float working surface; exports retain the document depth
  /// rather than accidentally promoting every RGB8 document to 16-bit output.
  public static func encoded(_ document: CraftDocument, type: UTType = .png,
    options: RasterEncodingOptions = .init()) throws -> Data {
    var document = document
    if type == .tiff, let embed = options.tiffEmbedProfile {
      document.profileIsUntagged = embed ? nil : true
    }
    if type == .tiff, document.inkMode != nil { throw CraftError.unsupported("Ink-mode TIFF interchange is still being implemented. Save as Photato to retain ink samples.") }
    if document.restrictedMode != nil, type == .png {
      try options.validate(for: type); return try PNGRestrictedStorage.write(document, options: options)
    }
    if document.restrictedMode != nil, type == .tiff {
      guard options.tiffImagePyramid != true else {
        throw CraftError.unsupported("Save Image Pyramid requires RGB, Grayscale, CMYK or Lab TIFF output.")
      }
      return try TIFFRestrictedStorage.write(document, options: options)
    }
    try options.validate(for: type)
    if type == .png, document.colorMode == .grayscale, document.depth != .f32,
      let descriptor = document.modeDescriptor {
      try document.validate()
      let raster: NativeModeRaster
      let visibleBounds: IntRect?
      if let retained = retainedFlatRaster(in: document, width: document.width, height: document.height) {
        raster = retained
        visibleBounds = nil
      } else if let composite = try GrayscalePNGComposite(document, descriptor: descriptor) {
        raster = composite.raster
        visibleBounds = composite.visibleBounds
      } else {
        raster = try NativeModeRaster.converting(Renderer.composite(document), to: .grayscale, depth: document.depth,
          profile: descriptor.profile, intent: descriptor.intent, pagedOutput: true)
        visibleBounds = nil
      }
      let image = try PNGGrayscaleStorage.image(raster, visibleBounds: visibleBounds)
      guard let space = image.colorSpace else { throw CraftError.invalid("Missing Grayscale PNG profile.") }
      let data = try encodeImage(image, type: type, resolution: document.pixelsPerInch,
        bits: raster.bytesPerSample * 8, exportSpace: space, profileName: ColorManagement.name(document),
        sourceMetadata: document.sourceMetadata, options: options, photoshopMode: 1)
      return try document.profileIsUntagged == true ? UntaggedOutput.strip(data, type: type) : data
    }
    if type == .tiff {
      if usesComponentTIFFWriter(document, options: options) {
        return try TIFFComponentExport.encoded(document, options: options)
      }
      let composite = try renderedTIFF(document, options: options)
      if options.tiffLayers == true || options.tiffImagePyramid == true {
        return try TIFFComponentExport.encodedComposite(composite, document: document,
          resolution: document.pixelsPerInch, options: options)
      }
      return composite
    }
    return try encoded(
      type == .png ? pngComposite(document) : Renderer.composite(document), type: type,
      resolution: document.pixelsPerInch, outputDepth: document.depth,
      sourceMetadata: document.sourceMetadata, workingDocument: document, options: options)
  }

  private static func renderedTIFF(_ document: CraftDocument, options: RasterEncodingOptions) throws -> Data {
    var compositeOptions = options
    compositeOptions.tiffLayers = nil; compositeOptions.tiffLayerCompression = nil
    compositeOptions.tiffImagePyramid = nil
    compositeOptions.tiffAlphaChannels = nil; compositeOptions.tiffSpotColors = nil
    if options.tiffLayers == true, compositeOptions.tiffByteOrder == nil {
      compositeOptions.tiffByteOrder = .bigEndian
    }
    if document.hasNativeModeStorage {
      return try TIFFModeStorage.write(Renderer.composite(document), document: document,
        resolution: document.pixelsPerInch, depth: document.depth, metadata: document.sourceMetadata,
        options: compositeOptions, useDocumentSamples: true)
    }
    return try encoded(Renderer.composite(document), type: .tiff,
      resolution: document.pixelsPerInch, outputDepth: document.depth,
      sourceMetadata: document.sourceMetadata, workingDocument: document, options: compositeOptions)
  }
  package static func supportsPagedComponentTIFFOutput(_ document: CraftDocument) -> Bool {
    guard document.inkMode == nil, document.restrictedMode == nil else { return false }
    if document.colorMode == .rgb, !document.hasNativeModeStorage {
      return document.width > Surface.maximumDensePixels / document.height
    }
    return document.hasNativeModeStorage && document.colorMode != .rgb
      && document.width > NativeModeRaster.maximumPixels / document.height
  }
  private static func usesComponentTIFFWriter(_ document: CraftDocument, options: RasterEncodingOptions) -> Bool {
    guard document.inkMode == nil, document.restrictedMode == nil else { return false }
    return supportsPagedComponentTIFFOutput(document) || options.tiffCompression == .jpeg || options.tiffBigTIFF == true
      || (options.tiffTransparency == false && TIFFRGBRows.supportsWhiteMatte(document))
      || !options.tiffSavedChannels(document).isEmpty
  }
  package static func supportsFileBackedTIFFOutput(_ document: CraftDocument, options: RasterEncodingOptions) -> Bool {
    guard document.inkMode == nil, document.restrictedMode == nil else { return false }
    return options.tiffLayers == true || options.tiffImagePyramid == true || usesComponentTIFFWriter(document, options: options)
  }
  public static func write(_ document: CraftDocument, to url: URL, type: UTType = .png,
    options: RasterEncodingOptions = .init()) throws {
    if type == .tiff, usesComponentTIFFWriter(document, options: options) {
      try TIFFComponentExport.write(document, to: url, options: options)
      return
    }
    if type == .tiff, supportsFileBackedTIFFOutput(document, options: options) {
      try options.validate(for: type)
      var source = document
      if let embed = options.tiffEmbedProfile { source.profileIsUntagged = embed ? nil : true }
      let composite = try renderedTIFF(source, options: options)
      try TIFFComponentExport.writeComposite(composite, document: source, to: url, options: options)
      return
    }
    try encoded(document, type: type, options: options).write(to: url, options: .atomic)
  }
}
