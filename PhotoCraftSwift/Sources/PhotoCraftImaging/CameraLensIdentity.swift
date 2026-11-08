import CoreFoundation
import Foundation
import ImageIO
import PhotoCraftCore

/// Only the capture fields needed for lens-default matching. No serial/GPS data.
public struct CameraLensIdentity: Codable, Hashable, Sendable {
  public let cameraMake: String
  public let cameraModel: String
  public let lensModel: String
  public let focalLength: Double
  public let fNumber: Double

  public init(cameraMake: String, cameraModel: String, lensModel: String,
    focalLength: Double, fNumber: Double) throws {
    for s in [cameraMake, cameraModel, lensModel] {
      guard !s.isEmpty, s.utf8.count <= 256,
        !s.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
      else { throw CraftError.invalid("Incomplete camera or lens metadata.") }
    }
    guard focalLength.isFinite, focalLength > 0, fNumber.isFinite, fNumber > 0 else {
      throw CraftError.invalid("Invalid focal length or aperture metadata.")
    }
    self.cameraMake = cameraMake.precomposedStringWithCanonicalMapping
    self.cameraModel = cameraModel.precomposedStringWithCanonicalMapping
    self.lensModel = lensModel.precomposedStringWithCanonicalMapping
    self.focalLength = focalLength; self.fNumber = fNumber
  }

  /// A stable identity independent of JSON key order or the process's Hashable seed.
  public var matchingKey: Data {
    var data = Data()
    for s in [cameraMake, cameraModel, lensModel] {
      let bytes = Data(s.precomposedStringWithCanonicalMapping.utf8)
      var count = UInt32(bytes.count).bigEndian
      withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }; data.append(bytes)
    }
    for value in [focalLength, fNumber] {
      var bits = value.bitPattern.bigEndian
      withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }
    return data
  }
  public func validated() throws -> Self {
    try .init(cameraMake: cameraMake, cameraModel: cameraModel, lensModel: lensModel,
      focalLength: focalLength, fNumber: fNumber)
  }

  public static func read(from source: [String: Data]?) throws -> Self? {
    func bounded(_ data: Data) throws -> Data {
      guard data.count <= RasterMetadata.maximumBytes else {
        throw CraftError.invalid("Camera metadata exceeds 16 MiB.")
      }; return data
    }
    if let data = source?[RasterMetadata.propertiesKey] {
      guard let properties = try PropertyListSerialization.propertyList(
        from: bounded(data), options: [], format: nil) as? [String: Any]
      else { throw CraftError.invalid("Invalid camera metadata.") }
      if let identity = try parse(properties) { return identity }
    }
    var exif = [Data]()
    if let data = source?["pcraft.exif"] { exif.append(try bounded(data)) }
    if let resources = source?["psdResources"] {
      for block in try PSDImageResources.blocks(bounded(resources)) where [1058, 1059].contains(block.id) {
        exif.append(block.data)
      }
    }
    for var data in exif {
      if data.starts(with: Data([69, 120, 105, 102, 0, 0])) { data.removeFirst(6) }
      if let image = CGImageSourceCreateWithData(data as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary),
        let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any],
        let identity = try parse(properties) { return identity }
    }
    if let data = try RasterMetadata.xmpData(source) {
      guard let xmp = CGImageMetadataCreateFromXMPData(try bounded(data) as CFData) else {
        throw CraftError.invalid("Invalid camera XMP metadata.")
      }
      func value(_ dictionary: CFString, _ property: CFString) -> Any? {
        CGImageMetadataCopyTagMatchingImageProperty(xmp, dictionary, property)
          .flatMap { CGImageMetadataTagCopyValue($0) }
      }
      let lens = value(kCGImagePropertyExifDictionary, kCGImagePropertyExifLensModel)
        ?? value(kCGImagePropertyExifAuxDictionary, kCGImagePropertyExifAuxLensModel)
        ?? CGImageMetadataCopyStringValueWithPath(xmp, nil, "aux:Lens" as CFString)
      return try identity(make: value(kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFMake),
        model: value(kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFModel), lens: lens,
        focal: value(kCGImagePropertyExifDictionary, kCGImagePropertyExifFocalLength),
        aperture: value(kCGImagePropertyExifDictionary, kCGImagePropertyExifFNumber))
    }
    return nil
  }
  private static func parse(_ properties: [String: Any]) throws -> Self? {
    let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
    let aux = properties[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]
    return try identity(make: tiff[kCGImagePropertyTIFFMake as String],
      model: tiff[kCGImagePropertyTIFFModel as String],
      lens: exif[kCGImagePropertyExifLensModel as String] ?? aux[kCGImagePropertyExifAuxLensModel as String],
      focal: exif[kCGImagePropertyExifFocalLength as String], aperture: exif[kCGImagePropertyExifFNumber as String])
  }
  private static func identity(make: Any?, model: Any?, lens: Any?, focal: Any?, aperture: Any?) throws -> Self? {
    guard let make = make as? String, let model = model as? String, let lens = lens as? String,
      let focal, let aperture else { return nil }
    func number(_ raw: Any) throws -> Double {
      if let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.doubleValue }
      if let text = raw as? String, text.utf8.count <= 64 {
        let pieces = text.split(separator: "/", omittingEmptySubsequences: false)
        if pieces.count == 1, let value = Double(text) { return value }
        if pieces.count == 2, let top = Double(pieces[0]), let bottom = Double(pieces[1]), bottom > 0 {
          return top / bottom
        }
      }
      throw CraftError.invalid("Invalid numeric camera metadata.")
    }
    return try .init(cameraMake: make, cameraModel: model, lensModel: lens,
      focalLength: number(focal), fNumber: number(aperture))
  }
}
