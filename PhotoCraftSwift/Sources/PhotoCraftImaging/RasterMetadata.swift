import Foundation
import ImageIO
import PhotoCraftCore

/// Retain ImageIO metadata inside native archives. Export normalizes fields that
/// describe the newly encoded pixels while preserving descriptive/camera tags.
enum RasterMetadata {
  static let propertiesKey = "imageIOProperties"
  static let xmpKey = "imageIOXMP"
  static let maximumBytes = 16 * 1024 * 1024

  static func capture(_ source: CGImageSource, properties: [CFString: Any]) throws -> [String: Data]
  {
    var result: [String: Data] = [:]
    let data = try PropertyListSerialization.data(
      fromPropertyList: properties, format: .binary, options: 0)
    guard data.count <= maximumBytes else {
      throw CraftError.invalid("Image metadata exceeds the 16 MiB limit.")
    }
    result[propertiesKey] = data
    if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
      let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data?
    {
      guard xmp.count <= maximumBytes else {
        throw CraftError.invalid("XMP metadata exceeds the 16 MiB limit.")
      }
      result[xmpKey] = xmp
    }
    return result
  }
  static func xmpData(_ source: [String: Data]?) throws -> Data? {
    if let xmp = source?[xmpKey] {
      guard xmp.count <= maximumBytes else {
        throw CraftError.invalid("XMP metadata exceeds the 16 MiB limit.")
      }
      return xmp
    }
    if let resources = source?["psdResources"] {
      return try PSDImageResources.blocks(resources).first { $0.id == 1060 }?.data
    }
    return nil
  }
  static func properties(
    _ source: [String: Data]?, width: Int, height: Int, resolution: Double, bits: Int,
    isSRGB: Bool = true
  ) throws -> [CFString: Any] {
    var result: [CFString: Any] = [:]
    if let data = source?[propertiesKey] {
      guard data.count <= maximumBytes,
        let dictionary = try PropertyListSerialization.propertyList(
          from: data, options: [], format: nil) as? [String: Any]
      else { throw CraftError.invalid("Invalid stored image metadata.") }
      result = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key as CFString, $0.value) })
    }
    for key in [
      kCGImagePropertyProfileName, kCGImagePropertyColorModel, kCGImagePropertyHasAlpha,
      kCGImagePropertyFileSize, kCGImagePropertyJFIFDictionary,
    ] {
      result.removeValue(forKey: key)
    }
    if var png = result[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
      for key in [
        kCGImagePropertyPNGGamma, kCGImagePropertyPNGChromaticities, kCGImagePropertyPNGsRGBIntent,
      ] {
        png.removeValue(forKey: key)
      }
      png[kCGImagePropertyPNGXPixelsPerMeter] = resolution / 0.0254
      png[kCGImagePropertyPNGYPixelsPerMeter] = resolution / 0.0254
      result[kCGImagePropertyPNGDictionary] = png
    }
    result[kCGImagePropertyPixelWidth] = width
    result[kCGImagePropertyPixelHeight] = height
    result[kCGImagePropertyDepth] = bits
    result[kCGImagePropertyOrientation] = 1
    result[kCGImagePropertyDPIWidth] = resolution
    result[kCGImagePropertyDPIHeight] = resolution
    var tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    // The output encoder owns compression and tile geometry. Copying input
    // tile dimensions asks ImageIO to tile a temporary uncompressed image.
    for key in [kCGImagePropertyTIFFCompression, kCGImagePropertyTIFFTileWidth, kCGImagePropertyTIFFTileLength] {
      tiff.removeValue(forKey: key)
    }
    tiff[kCGImagePropertyTIFFOrientation] = 1
    tiff[kCGImagePropertyTIFFXResolution] = resolution
    tiff[kCGImagePropertyTIFFYResolution] = resolution
    tiff[kCGImagePropertyTIFFResolutionUnit] = 2
    result[kCGImagePropertyTIFFDictionary] = tiff
    var exif = result[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
    exif[kCGImagePropertyExifPixelXDimension] = width
    exif[kCGImagePropertyExifPixelYDimension] = height
    exif[kCGImagePropertyExifColorSpace] = isSRGB ? 1 : 65535
    result[kCGImagePropertyExifDictionary] = exif
    return result
  }
  static func metadata(
    _ source: [String: Data]?, width: Int, height: Int, resolution: Double, linear: Bool = false,
    profileName: String? = nil, isSRGB: Bool = true, photoshopMode: Int = 3, embedsProfile: Bool = true
  )
    throws -> CGImageMetadata?
  {
    guard let xmp = try xmpData(source) else { return nil }
    guard let original = CGImageMetadataCreateFromXMPData(xmp as CFData),
      let metadata = CGImageMetadataCreateMutableCopy(original)
    else { throw CraftError.invalid("Invalid stored XMP metadata.") }
    for (dictionary, property, value) in [
      (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1.0),
      (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFXResolution, resolution),
      (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFYResolution, resolution),
      (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFResolutionUnit, 2.0),
      (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, Double(width)),
      (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, Double(height)),
      (
        kCGImagePropertyExifDictionary, kCGImagePropertyExifColorSpace,
        linear || !isSRGB || !embedsProfile ? 65535.0 : 1.0
      ),
    ] {
      _ = CGImageMetadataSetValueMatchingImageProperty(
        metadata, dictionary, property, NSNumber(value: value))
    }
    for (path, value) in [
      ("tiff:ImageWidth", String(width)), ("tiff:ImageLength", String(height)),
      ("photoshop:ColorMode", String(photoshopMode)),
      ("photoshop:ICCProfile", profileName ?? (linear ? "Linear sRGB" : "sRGB IEC61966-2.1")),
    ] where CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) != nil {
      _ = CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, value as CFString)
    }
    for path in ["tiff:BitsPerSample", "tiff:Compression", "tiff:TileWidth", "tiff:TileLength",
      "tiff:RowsPerStrip", "tiff:StripOffsets", "tiff:StripByteCounts", "tiff:TileOffsets", "tiff:TileByteCounts",
      "tiff:PlanarConfiguration", "tiff:YCbCrSubSampling", "tiff:YCbCrPositioning", "xmp:Thumbnails"] {
      _ = CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
    }
    if !embedsProfile { _ = CGImageMetadataRemoveTagWithPath(metadata, nil, "photoshop:ICCProfile" as CFString) }
    return metadata
  }
}
