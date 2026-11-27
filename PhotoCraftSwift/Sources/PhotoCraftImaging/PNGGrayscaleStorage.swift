import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore

/// Keep PNG gray and opacity samples in the document's native component planes.
enum PNGGrayscaleStorage {
  private static let maximumProviderBytes = 1_073_741_824

  static func read(_ image: CGImage, from source: CGImageSource, data: Data, name: String,
    properties: [CFString: Any]) throws -> CraftDocument? {
    guard data.count >= 33, data.starts(with: PNGRestrictedStorage.signature),
      (data[25] == 0 && [2, 4, 8, 16].contains(data[24]))
        || (data[25] == 4 && [8, 16].contains(data[24])),
      CGImageSourceGetCount(source) == 1, let space = image.colorSpace, space.model == .monochrome,
      image.decode == nil, !image.isMask, !image.bitmapInfo.contains(.floatComponents),
      image.alphaInfo == .none || image.alphaInfo == .last else { return nil }

    // ImageIO expands packed grayscale to eight bits and exposes unassociated
    // alpha for both an explicit opacity plane and a PNG transparency key.
    let depth: PixelDepth = data[24] == 16 ? .u16 : .u8
    let bytesPerSample = depth == .u16 ? 2 : 1
    let hasAlpha = image.alphaInfo == .last
    let bytesPerPixel = bytesPerSample * (hasAlpha ? 2 : 1)
    let byteOrder = image.bitmapInfo.intersection(.byteOrderMask)
    let width = image.width, height = image.height, rowBytes = image.bytesPerRow
    guard width > 0, height > 0, image.bitsPerComponent == bytesPerSample * 8,
      image.bitsPerPixel == bytesPerPixel * 8, rowBytes >= width * bytesPerPixel,
      rowBytes <= maximumProviderBytes / height,
      depth == .u8 || byteOrder == .byteOrder16Little || byteOrder == .byteOrder16Big,
      let decoded = image.dataProvider?.data as Data?,
      decoded.count >= rowBytes * (height - 1) + width * bytesPerPixel else { return nil }

    let pngProperties = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
    let gamma = pngProperties?[kCGImagePropertyPNGGamma] as? Double
    let tagged = try UntaggedOutput.hasProfile(data) == true || gamma.map { $0.isFinite && $0 > 0 } == true
    let sourceProfile = tagged ? space.copyICCData() as Data? : nil
    let profile = try sourceProfile ?? ColorSettings().profile(.grayscale, depth: depth)
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    guard (1...8).contains(orientation) else { throw CraftError.invalid("Invalid EXIF orientation.") }
    let backing = try RasterTileStore()
    let builder = try NativeModeRaster.RowBuilder(width: width, height: height, mode: .grayscale,
      depth: depth, profile: profile, backing: backing)
    if !hasAlpha { try builder.fill(component: 1, word: depth == .u16 ? 65535 : 255) }
    try decoded.withUnsafeBytes { bytes in
      func word(at index: Int) -> UInt32 {
        if bytesPerSample == 1 { return UInt32(bytes[index]) }
        let sample = bytes.loadUnaligned(fromByteOffset: index, as: UInt16.self)
        return UInt32(byteOrder == .byteOrder16Little ? UInt16(littleEndian: sample) : UInt16(bigEndian: sample))
      }
      var gray = [UInt32](repeating: 0, count: width)
      var alpha = hasAlpha ? gray : []
      for y in 0..<height {
        try Task.checkCancellation()
        let offset = y * rowBytes
        for x in 0..<width {
          let sample = offset + x * bytesPerPixel
          gray[x] = word(at: sample)
          if hasAlpha { alpha[x] = word(at: sample + bytesPerSample) }
        }
        try builder.appendRow(gray, component: 0)
        if hasAlpha { try builder.appendRow(alpha, component: 1) }
      }
    }
    var raster = try builder.finish()
    if orientation != 1 { raster = try TIFFModeStorage.oriented(raster, orientation: orientation) }
    var document = try CraftDocument(width: raster.width, height: raster.height, depth: depth, name: name)
    document.modeDescriptor = try .init(mode: .grayscale, depth: depth, profile: profile)
    document.sourceICC = sourceProfile
    document.profileIsUntagged = tagged ? nil : true
    document.sourceMetadata = try RasterMetadata.capture(source, properties: properties)
    if let dpi = properties[kCGImagePropertyDPIWidth] as? Double, dpi.isFinite, (1...100_000).contains(dpi) {
      document.resolution = dpi
    }
    var layer = Layer(name: name, content: .raster(try raster.surface(backing: backing)))
    layer.nativeMode = raster
    document.layers = [layer]
    document.activeLayerID = layer.id
    try document.validate()
    return document
  }

  static func image(_ raster: NativeModeRaster) throws -> CGImage {
    let hasAlpha = !raster.isOpaque
    let bytesPerSample = raster.bytesPerSample
    let bytesPerPixel = bytesPerSample * (hasAlpha ? 2 : 1)
    let rowBytes = raster.width * bytesPerPixel
    guard raster.mode == .grayscale, raster.depth != .f32,
      rowBytes <= maximumProviderBytes / raster.height,
      let space = CGColorSpace(iccData: raster.profile as CFData) else {
      throw CraftError.unsupported("Grayscale PNG output exceeds the supported sample layout or size.")
    }
    var samples = Data(count: rowBytes * raster.height)
    try samples.withUnsafeMutableBytes { bytes in
      for y in 0..<raster.height {
        try Task.checkCancellation()
        for x in 0..<raster.width {
          let index = y * raster.width + x
          let offset = index * bytesPerPixel
          let gray = raster.rawWord(component: 0, index: index)
          if bytesPerSample == 1 {
            bytes[offset] = UInt8(gray)
            if hasAlpha { bytes[offset + 1] = UInt8(raster.rawWord(component: 1, index: index)) }
          } else {
            bytes.storeBytes(of: UInt16(gray).littleEndian, toByteOffset: offset, as: UInt16.self)
            if hasAlpha {
              let opacity = UInt16(raster.rawWord(component: 1, index: index)).littleEndian
              bytes.storeBytes(of: opacity, toByteOffset: offset + 2, as: UInt16.self)
            }
          }
        }
      }
    }
    var info = CGBitmapInfo(rawValue: (hasAlpha ? CGImageAlphaInfo.last : .none).rawValue)
    if bytesPerSample == 2 { info.insert(.byteOrder16Little) }
    guard let provider = CGDataProvider(data: samples as CFData),
      let image = CGImage(width: raster.width, height: raster.height, bitsPerComponent: bytesPerSample * 8,
        bitsPerPixel: bytesPerPixel * 8, bytesPerRow: rowBytes, space: space, bitmapInfo: info,
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
      throw CraftError.invalid("Could not create a straight Grayscale PNG image.")
    }
    return image
  }
}
