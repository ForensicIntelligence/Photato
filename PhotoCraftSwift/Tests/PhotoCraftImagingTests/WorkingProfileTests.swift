import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers
import XCTest

@testable import PhotoCraftImaging

final class WorkingProfileTests: XCTestCase {
  func fixture(_ name: String, ext: String = "psd") throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: name, withExtension: ext,
          subdirectory: "Fixtures/layer-merge")))
  }
  func p3(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 2, height: 1, depth: depth)
    d.workingICC = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
    d.sourceICC = d.workingICC
    d.layers[0].content = .raster(
      try Surface(width: 2, height: 1, depth: depth, fill: Pixel(0.8, 0.3, 0.1, 0.5)))
    return d
  }
  func testOriginalAdobeLinearProfileMergeMatchesIndependentRawSamples() throws {
    let original = try PSDCodec.read(fixture("photoshop-source-rgb32"))
    XCTAssertEqual(original.workingICC, original.sourceICC)
    XCTAssertTrue(try ICCProfile.isLinear(XCTUnwrap(original.workingICC)))
    var session = EditorSession(document: original)
    try session.execute(.mergeLayers([try XCTUnwrap(original.activeLayerID)], .down))
    let expected = try fixture("original-profile-down-rgb32", ext: "rgba")
    XCTAssertEqual(expected.count, 256 * 7 * 16)
    for result in [
      session.document,
      try NativeArchive.decode(NativeArchive.encode(session.document)),
      try PSDCodec.read(PSDCodec.writeRasterLayers(session.document)),
    ] {
      XCTAssertEqual(result.workingICC, original.workingICC)
      guard case .raster(let pixels) = result.layers[0].content else { return XCTFail() }
      let actual = try pixels.rgbaData(depth: .f32, colorEncoding: .linearRGB)
      XCTAssertEqual(actual.count, expected.count)
      XCTAssertEqual(zip(actual, expected).filter { $0 != $1 }.count, 0)
    }
    try session.undo()
    XCTAssertEqual(session.document, original)
    try session.redo()
    XCTAssertEqual(session.document.workingICC, original.workingICC)
  }
  func testWorkingProfileArchiveMigrationAndInvalidProfiles() throws {
    let original = try p3()
    let bytes = try NativeArchive.encode(original)
    XCTAssertEqual(try NativeArchive.decode(bytes), original)
    var archive = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
    archive["version"] = 9
    let migrated = try NativeArchive.decode(
      PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0))
    XCTAssertNil(migrated.workingICC)
    XCTAssertEqual(migrated.sourceICC, original.sourceICC)
    XCTAssertEqual(migrated.layers, original.layers)
    var bad = original
    bad.workingICC = Data([1, 2, 3])
    XCTAssertThrowsError(try bad.validate())
    var profile = try XCTUnwrap(original.workingICC)
    profile[16] = 0
    bad.workingICC = profile
    XCTAssertThrowsError(try bad.validate())
    profile = try XCTUnwrap(original.workingICC)
    profile[132 + 4] = 0xff
    bad.workingICC = profile
    XCTAssertThrowsError(try bad.validate())
    bad = original
    bad.depth = .f32
    XCTAssertThrowsError(try bad.validate())
    bad.workingICC = try ColorManagement.importedProfile(original.workingICC, depth: .f32)
    XCTAssertTrue(try ICCProfile.isLinear(XCTUnwrap(bad.workingICC)))
    XCTAssertNoThrow(try bad.validate())
    // Bound descriptor count even when thousands of tags share a tiny valid payload.
    let count = ICCProfile.maximumTags + 1
    let payload = 132 + count * 12
    var excessive = Data(repeating: 0, count: payload + 8)
    func number(_ n: Int, at offset: Int) {
      for c in 0..<4 { excessive[offset + c] = UInt8(truncatingIfNeeded: n >> (24 - c * 8)) }
    }
    number(excessive.count, at: 0)
    excessive[8] = 4
    for (offset, text) in [(16, "RGB "), (20, "XYZ "), (36, "acsp")] {
      excessive.replaceSubrange(offset..<offset + 4, with: Data(text.utf8))
    }
    number(count, at: 128)
    for i in 0..<count {
      let offset = 132 + i * 12
      excessive.replaceSubrange(offset..<offset + 4, with: Data(String(format: "%04x", i).utf8))
      number(payload, at: offset + 4)
      number(8, at: offset + 8)
    }
    XCTAssertThrowsError(try ICCProfile.validate(excessive, linear: false))

  }
  func testDisplayConvertsProfileBeforeQuantizingWithoutChangingSamples() throws {
    let document = try p3(.u16)
    let surface = try Renderer.composite(document)
    let before = try surface.rgbaData(depth: .f32)
    let image = try ColorManagement.displayImage(surface, in: document)
    let raw = try XCTUnwrap(image.dataProvider?.data as Data?)
    let p = surface.pixel(x: 0, y: 0)
    let converted = try XCTUnwrap(
      ColorManagement.color(p, in: document).converted(
        to: RasterIO.colorSpace(), intent: .relativeColorimetric, options: nil)?.components)
    for i in 0..<3 {
      XCTAssertEqual(Int(raw[i]), Int((min(1, max(0, converted[i])) * 255).rounded()), accuracy: 1)
    }
    XCTAssertEqual(try surface.rgbaData(depth: .f32), before)
    XCTAssertNotEqual(
      raw.prefix(3),
      try RasterIO.displayImage(surface).dataProvider!.data.map { ($0 as Data).prefix(3) })
  }
  func testProfileTaggedRasterExportAndMetadata() throws {
    for depth in [PixelDepth.u8, .u16] {
      let document = try p3(depth)
      for type in [UTType.png, .tiff, .jpeg] {
        let bytes = try RasterIO.encoded(document, type: type)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.colorSpace, try ColorManagement.space(for: document))
        let reopened = try RasterIO.read(bytes)
        XCTAssertEqual(
          try ColorManagement.space(for: reopened), try ColorManagement.space(for: document))
      }
      let psd = try PSDCodec.read(PSDCodec.writeRasterLayers(document))
      XCTAssertEqual(psd.workingICC, document.workingICC)
      guard case .raster(let actual) = psd.layers[0].content,
        case .raster(let original) = document.layers[0].content
      else { return XCTFail() }
      XCTAssertEqual(try actual.rgbaData(depth: depth), try original.rgbaData(depth: depth))
    }
  }
  func testClipboardProfilesConversionAlphaAndNativeNewDocument() throws {
    let source = try p3(.u16)
    let copy = try ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id])
    XCTAssertEqual(try copy.newDocument(name: "Copy").workingICC, source.workingICC)
    var target = try CraftDocument(width: 2, height: 1, depth: .u16)
    let before = target
    XCTAssertThrowsError(try Command.paste(copy, .inPlace, nil).apply(to: &target))
    XCTAssertEqual(target, before)
    let converted = try ColorManagement.converted(copy, to: target)
    XCTAssertNil(converted.document.workingICC)
    guard case .raster(let pixels) = converted.document.layers[0].content,
      case .raster(let original) = source.layers[0].content
    else { return XCTFail() }
    XCTAssertEqual(pixels.pixel(x: 0, y: 0).a, original.pixel(x: 0, y: 0).a)
    XCTAssertNotEqual(pixels.pixel(x: 0, y: 0).r, original.pixel(x: 0, y: 0).r)
    try Command.paste(converted, .inPlace, nil).apply(to: &target)
    XCTAssertEqual(target.layers.count, 2)
    let preview = try ClipboardRenderer.preview(copy)
    let tiff = try ClipboardRenderer.imageData(preview, type: .tiff, document: source)
    let external = try ClipboardRenderer.readImage(tiff)
    XCTAssertEqual(
      try ColorManagement.space(for: external.document), try ColorManagement.space(for: source))
  }
}
