import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers
import XCTest

@testable import PhotoCraftImaging

final class MetadataPreservationTests: XCTestCase {
  let xmp = Data(
    """
    <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:probe="https://photato.example/metadata/" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"><dc:creator><rdf:Seq><rdf:li>Photato test author</rdf:li></rdf:Seq></dc:creator><dc:rights><rdf:Alt><rdf:li xml:lang="x-default">Original test metadata</rdf:li></rdf:Alt></dc:rights><probe:retained>original-value</probe:retained><tiff:ImageWidth>999</tiff:ImageWidth><tiff:ImageLength>888</tiff:ImageLength><photoshop:ICCProfile>Old profile</photoshop:ICCProfile></rdf:Description></rdf:RDF></x:xmpmeta>
    """.utf8)

  func source() throws -> Data {
    let surface = try Surface(width: 3, height: 2, depth: .u8, fill: Pixel(0.2, 0.4, 0.8))
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(bytes, UTType.tiff.identifier as CFString, 1, nil))
    let metadata = try XCTUnwrap(CGImageMetadataCreateFromXMPData(xmp as CFData))
    CGImageDestinationAddImageAndMetadata(
      destination, try RasterIO.cgImage(surface), metadata,
      [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyTIFFDictionary: [
          kCGImagePropertyTIFFArtist: "Photato test author",
          kCGImagePropertyTIFFCopyright: "Original test metadata",
        ],
        kCGImagePropertyExifDictionary: [
          kCGImagePropertyExifDateTimeOriginal: "2026:10:19 12:00:00",
          kCGImagePropertyExifFNumber: 2.8,
        ],
        kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["original", "test"]],
      ] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return bytes as Data
  }
  func properties(_ bytes: Data) throws -> [CFString: Any] {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
    return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
  }
  func testCameraCopyrightAndCustomXMPThroughNativeAndRasterFormats() throws {
    var doc = try RasterIO.read(source(), name: "Original metadata")
    XCTAssertEqual(doc.width, 2)
    XCTAssertEqual(doc.height, 3)
    let before = doc
    doc = try NativeArchive.decode(NativeArchive.encode(doc))
    XCTAssertEqual(doc, before)
    doc.resolution = 240
    for type in [UTType.png, .jpeg, .tiff] {
      let bytes = try RasterIO.encoded(doc, type: type)
      let properties = try properties(bytes)
      XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2)
      XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 3)
      XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int ?? 1, 1)
      let image = try RasterIO.read(bytes)
      XCTAssertEqual(image.width, 2)
      XCTAssertEqual(image.height, 3)
      let metadata = try XCTUnwrap(RasterMetadata.xmpData(image.sourceMetadata))
      let text = String(decoding: metadata, as: UTF8.self)
      XCTAssertTrue(text.contains("Photato test author"), type.identifier)
      XCTAssertTrue(text.contains("Original test metadata"), type.identifier)
      XCTAssertTrue(text.contains("original-value"), type.identifier)
      XCTAssertFalse(text.contains("Old profile"), type.identifier)
      XCTAssertFalse(text.contains(">999<"), type.identifier)
      XCTAssertFalse(text.contains(">888<"), type.identifier)
      let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
      XCTAssertEqual(exif?[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:10:19 12:00:00")
      XCTAssertEqual(exif?[kCGImagePropertyExifPixelXDimension] as? Int, 2)
      XCTAssertEqual(exif?[kCGImagePropertyExifPixelYDimension] as? Int, 3)
      XCTAssertEqual(image.pixelsPerInch, 240, accuracy: 0.1)
    }
  }
  func testRasterXMPMovesToPSDAndBackWithoutDroppingCustomNamespacedValues() throws {
    let original = try RasterIO.read(source())
    let psd = try PSDCodec.writeRasterLayers(original)
    if let output = ProcessInfo.processInfo.environment["PHOTATO_METADATA_PROBE"] {
      try psd.write(to: URL(fileURLWithPath: output), options: .atomic)
    }
    let read = try PSDCodec.read(psd)
    let xmp = try XCTUnwrap(RasterMetadata.xmpData(read.sourceMetadata))
    XCTAssertTrue(String(decoding: xmp, as: UTF8.self).contains("original-value"))
    let png = try RasterIO.read(RasterIO.encoded(read, type: .png))
    XCTAssertTrue(
      String(decoding: try XCTUnwrap(RasterMetadata.xmpData(png.sourceMetadata)), as: UTF8.self)
        .contains("original-value"))
  }
  func testPSDUnknownResourceBytesAndNamesSurviveWhileStaleRecordsAreRemoved() throws {
    var doc = try CraftDocument(width: 3, height: 2)
    // Public PSD block layout, with a named resource and deliberately nonzero padding.
    let unknown = Data([0x38, 0x42, 0x49, 0x4d, 0x0f, 0xa0, 1, 65, 0, 0, 0, 3, 1, 2, 3, 0x5a])
    let copyright = PSDImageResources.block(1034, data: Data([1]))
    let originalXMP = PSDImageResources.block(1060, data: xmp)
    let thumbnail = PSDImageResources.block(1036, data: Data([9, 9, 9]))
    let staleSelection = PSDImageResources.block(1069, data: Data([0, 1, 0, 0, 0, 42]))
    let untagged = PSDImageResources.block(1041, data: Data([1]))
    doc.sourceMetadata = [
      "psdResources": unknown + copyright + originalXMP + thumbnail + staleSelection + untagged
    ]
    doc.resolution = 144
    let read = try PSDCodec.read(PSDCodec.writeRasterLayers(doc))
    let blocks = try PSDImageResources.blocks(XCTUnwrap(read.sourceMetadata?["psdResources"]))
    XCTAssertEqual(blocks.first { $0.id == 4000 }?.raw, unknown)
    XCTAssertEqual(blocks.first { $0.id == 1034 }?.raw, copyright)
    let updatedXMP = String(
      decoding: try XCTUnwrap(blocks.first { $0.id == 1060 }?.data), as: UTF8.self)
    XCTAssertTrue(updatedXMP.contains("original-value"))
    XCTAssertFalse(updatedXMP.contains("Old profile"))
    XCTAssertFalse(updatedXMP.contains(">999<"))
    XCTAssertFalse(updatedXMP.contains(">888<"))
    XCTAssertFalse(blocks.contains { [1036, 1069, 1041].contains($0.id) })
    XCTAssertEqual(blocks.filter { $0.id == 1005 }.count, 1)
    XCTAssertEqual(blocks.filter { $0.id == 1039 }.count, 1)
    XCTAssertEqual(read.pixelsPerInch, 144)
  }
  func testIndependentPhotoshopResourcesRetainExactOpaqueBlocks() throws {
    for name in ["photoshop-depth-16", "photoshop-depth-32", "photoshop-mask-feather"] {
      let url = try XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: "psd", subdirectory: "Fixtures"))
      let original = try PSDCodec.read(Data(contentsOf: url))
      let retained = try PSDImageResources.preserved(
        XCTUnwrap(original.sourceMetadata?["psdResources"]))
      let exported = try PSDCodec.read(PSDCodec.writeRasterLayers(original))
      XCTAssertEqual(
        try PSDImageResources.preserved(XCTUnwrap(exported.sourceMetadata?["psdResources"])),
        retained, name)
      // Check metadata isolation and exact working composites after a PSD round trip.
      // Separate linear-storage tests compare original channel sample bits.
      var withoutResources = original
      withoutResources.sourceMetadata?.removeValue(forKey: "psdResources")
      let control = try PSDCodec.read(PSDCodec.writeRasterLayers(withoutResources))
      let actual = try Renderer.composite(exported).rgbaData(depth: exported.depth)
      XCTAssertEqual(actual, try Renderer.composite(control).rgbaData(depth: control.depth), name)
      let originalBytes = try Renderer.composite(original).rgbaData(depth: original.depth)
      let differentBytes = zip(originalBytes, actual).filter { $0 != $1 }.count
      print(
        "METADATA_FIDELITY \(name): original round-trip different bytes=\(differentBytes); metadata-only pixel delta=0"
      )
      XCTAssertEqual(actual, originalBytes, name)
    }
  }
  func testImportedTIFFCompressionCannotChangeExportPixelsOrEncodingPolicy() throws {
    var document = try CraftDocument(width: 32, height: 24)
    var pixels = try Surface(width: 32, height: 24, depth: .u8)
    for y in 0..<24 {
      for x in 0..<32 {
        pixels.setPixel(
          x: x, y: y, Pixel(Float(x % 3) / 2, Float(y % 5) / 4, Float((x * y) % 7) / 6))
      }
    }
    document.layers[0].content = .raster(pixels)
    for compression in [5, 7, 8] {
      let metadata: [CFString: Any] = [
        kCGImagePropertyTIFFDictionary: [
          kCGImagePropertyTIFFCompression: compression,
          kCGImagePropertyTIFFArtist: "Retain the author, not encoder settings",
        ]
      ]
      document.sourceMetadata = [
        RasterMetadata.propertiesKey: try PropertyListSerialization.data(
          fromPropertyList: metadata, format: .binary, options: 0)
      ]
      let output = try RasterIO.encoded(document, type: .tiff)
      let tiff = try XCTUnwrap(
        try properties(output)[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
      XCTAssertEqual(tiff[kCGImagePropertyTIFFCompression] as? Int, 1)
      XCTAssertEqual(
        tiff[kCGImagePropertyTIFFArtist] as? String, "Retain the author, not encoder settings")
      XCTAssertEqual(
        try Renderer.composite(RasterIO.read(output)).rgbaData(depth: .u8),
        try pixels.rgbaData(depth: .u8))
    }
  }

  func testMetadataBudgetsAndTruncatedResourceLengthsRejectBeforeEncoding() throws {
    let oversized = Data(repeating: 0, count: RasterMetadata.maximumBytes + 1)
    XCTAssertThrowsError(try PSDImageResources.blocks(oversized))
    XCTAssertThrowsError(try RasterMetadata.xmpData([RasterMetadata.xmpKey: oversized]))
    let badLength = Data([0x38, 0x42, 0x49, 0x4d, 0x0f, 0xa0, 0, 0, 0xff, 0xff, 0xff, 0xff])
    XCTAssertThrowsError(try PSDImageResources.blocks(badLength))
    let incompleteName = Data([0x38, 0x42, 0x49, 0x4d, 0x0f, 0xa0, 255])
    XCTAssertThrowsError(try PSDImageResources.blocks(incompleteName))
  }

  func testMalformedMetadataRejectsAndEncodedPixelsNeverUseAnOldImportProfile() throws {
    var doc = try CraftDocument(width: 2, height: 2)
    doc.sourceMetadata = [RasterMetadata.propertiesKey: Data([1, 2, 3])]
    XCTAssertThrowsError(try RasterIO.encoded(doc))
    doc.sourceMetadata = [RasterMetadata.xmpKey: Data("invalid".utf8)]
    XCTAssertThrowsError(try RasterIO.encoded(doc))
    doc.sourceMetadata = ["psdResources": Data("8BIM".utf8)]
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc))
    doc.sourceMetadata = nil
    doc.sourceICC = CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?
    let output = try PSDCodec.read(PSDCodec.writeRasterLayers(doc))
    XCTAssertNotEqual(output.sourceICC, doc.sourceICC)
    XCTAssertEqual(output.sourceICC, try RasterIO.colorSpace().copyICCData() as Data?)
  }
}
