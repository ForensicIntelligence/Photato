import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PATCodecTests: XCTestCase {
  func fixture() throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "patterns-source", withExtension: "pat", subdirectory: "Fixtures")))
  }
  func testOriginalRustPATRecordsAcrossDepthsAlphaGrayIndexedAndBitmap() throws {
    let patterns = try PATCodec.read(fixture())
    XCTAssertEqual(patterns.count, 9)
    for index in 0..<6 {
      let p = patterns[index]
      let depth = PixelDepth.allCases[index / 2]
      XCTAssertEqual(p.name, "Pattern ✓ \(index)")
      XCTAssertEqual(p.id, "pattern-\(index)")
      XCTAssertEqual(p.surface.depth, depth)
      for y in 0..<3 {
        for x in 0..<5 {
          let i = y * 5 + x
          func sample(_ c: Int) -> Float { Float((i * 3 + c * 5) % 11) / 10 }
          let expected = Pixel(sample(0), sample(1), sample(2), index % 2 == 0 ? 1 : sample(3))
            .quantized(depth)
          XCTAssertTrue(p.surface.pixel(x: x, y: y).hasSameBits(as: expected))
        }
      }
    }
    for y in 0..<3 {
      for x in 0..<5 {
        let i = y * 5 + x
        let gray = Float(i * 17) / 255
        XCTAssertEqual(patterns[6].surface.pixel(x: x, y: y), Pixel(gray, gray, gray))
        XCTAssertEqual(
          patterns[7].surface.pixel(x: x, y: y),
          Pixel(gray, Float(255 - i * 17) / 255, Float(i * 17 / 2) / 255))
        let bits: [UInt8] = [0xa8, 0x50, 0xf8]
        XCTAssertEqual(
          patterns[8].surface.pixel(x: x, y: y), bits[y] & (0x80 >> x) == 0 ? .white : .black)
      }
    }
    let exported = try PATCodec.write(patterns)
    XCTAssertEqual(try PATCodec.read(exported), patterns)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try exported.write(to: root.appendingPathComponent("artifacts/native-patterns.pat"))
  }
  func testFloatNativeSampleBitsAndTransparentHiddenColorSurviveExport() throws {
    var s = try Surface(width: 3, height: 1, depth: .f32)
    s.setPixel(x: 0, y: 0, Pixel(-0.125, 1.75, 0.33333334, 0))
    s.setPixel(x: 1, y: 0, Pixel(0.12345679, 0.9876543, 0.5555556, 0.625))
    s.setPixel(x: 2, y: 0, Pixel(2, 4, 8))
    let p = try RasterPattern(name: "Float tile", surface: s)
    let restored = try PATCodec.read(PATCodec.write([p]))
    XCTAssertEqual(restored, [p])
  }
  func testOriginalRustRGBFileBytesAndPackBitsPacketBoundaries() throws {
    for name in ["patterns-rgb-source", "patterns-packets-source"] {
      let data = try Data(
        contentsOf: XCTUnwrap(
          Bundle.module.url(
            forResource: name,
            withExtension: "pat", subdirectory: "Fixtures")))
      XCTAssertEqual(
        try PATCodec.write(PATCodec.read(data)), data, "Original Rust PAT bytes: \(name)")
    }
  }
  func testPhotoshopFolderHierarchyCanImportAsFlatPresetsWithoutAcceptingUnknownTail() throws {
    let original = try fixture()
    let group = PSDDescriptor("Grup", items: [.init("Nm  ", .text(Array("Original tiles".utf16)))])
    let entries =
      [PSDValue.object(group)]
      + (0..<9).map { _ in PSDValue.object(PSDDescriptor("preset")) }
      + [.object(PSDDescriptor("groupEnd"))]
    func library(_ entries: [PSDValue], tag: String = "phry") throws -> Data {
      var trailer = PSDWriter()
      trailer.text("8BIM")
      trailer.text(tag)
      trailer.section(
        try PSDDescriptor("null", items: [.init("hierarchy", .list(entries))]).encoded())
      return original + trailer.data
    }
    XCTAssertEqual(try PATCodec.read(library(entries)), try PATCodec.read(original))
    // The legacy read() list stays flat; readLibrary() now retains these groups.
    XCTAssertFalse(try PATCodec.readLibrary(library(entries)).foldersFlattened)
    XCTAssertEqual(try PATCodec.readLibrary(library(entries)).nodes.filter(\.isGroup).map(\.name), ["Original tiles"])
    XCTAssertFalse(try PATCodec.readLibrary(original).foldersFlattened)
    XCTAssertThrowsError(try PATCodec.read(library(entries, tag: "????")))
    XCTAssertThrowsError(try PATCodec.read(library(Array(entries.dropLast()))))
    XCTAssertThrowsError(try PATCodec.read(library([.object(PSDDescriptor("preset"))])))
    XCTAssertThrowsError(try PATCodec.read(library(entries).dropLast()))
  }
  func testRepeatedPresetReferencesMergeOnlyWhenAllSampleBitsAndNamesMatch() throws {
    var pixels = try Surface(width: 2, height: 1, depth: .f32, fill: .white)
    pixels.setPixel(x: 0, y: 0, Pixel(0, 0.5, 1))
    let pattern = try RasterPattern(name: "Same tile", surface: pixels, id: "repeated")
    func pair(_ second: RasterPattern) throws -> Data {
      var header = PSDWriter()
      header.text("8BPT")
      header.n(1, 2)
      header.n(2, 4)
      return header.data + (try PATCodec.write([pattern])).dropFirst(10)
        + (try PATCodec.write([second])).dropFirst(10)
    }
    let merged = try PATCodec.readLibrary(pair(pattern))
    // PAT preserves visible samples; its decoded sparse default need not match the source storage.
    XCTAssertEqual(merged.patterns, try PATCodec.read(PATCodec.write([pattern])))
    for x in 0..<2 {
      XCTAssertTrue(
        merged.patterns[0].surface.pixel(x: x, y: 0).hasSameBits(as: pixels.pixel(x: x, y: 0)))
    }
    XCTAssertEqual(merged.duplicateRecordsMerged, 1)
    var renamed = pattern
    renamed.name = "Conflicting name"
    XCTAssertThrowsError(try PATCodec.read(pair(renamed)))
    pixels.setPixel(x: 0, y: 0, Pixel(-0.0, 0.5, 1))
    let signedZero = try RasterPattern(name: pattern.name, surface: pixels, id: pattern.id)
    XCTAssertThrowsError(try PATCodec.read(pair(signedZero)))
  }
  func testTruncationVersionsUnsupportedModesAndMutationCorpusRejectOrValidate() throws {
    let original = try fixture()
    for end in [0, 3, 8, 10, 25, 80, original.count - 1] {
      XCTAssertThrowsError(try PATCodec.read(original.prefix(end)))
    }
    var wrong = original
    wrong[5] = 2
    XCTAssertThrowsError(try PATCodec.read(wrong))
    wrong = original
    wrong[17] = 4
    XCTAssertThrowsError(try PATCodec.read(wrong))
    wrong = original
    wrong.append(1)
    XCTAssertThrowsError(try PATCodec.read(wrong))
    for seed in 0..<100 {
      var data = original
      let i = (seed * 37 + 7) % data.count
      data[i] ^= UInt8(truncatingIfNeeded: seed * 29 + 1)
      if let decoded = try? PATCodec.read(data) {
        XCTAssertNoThrow(try PatternArchive.validate(decoded))
      }
    }
  }
  func testDefinePatternUsesCompositeSelectionBoundsAndRetainsDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 8, height: 6, depth: depth)
      d.layers[0].content = .raster(
        try Surface(width: 8, height: 6, depth: depth, fill: Pixel(0.2, 0.4, 0.6)))
      var top = Layer(
        name: "Top",
        content: .raster(try Surface(width: 3, height: 2, depth: depth, fill: Pixel(1, 0, 0, 0.5))))
      top.x = 2
      top.y = 1
      d.layers.append(top)
      d.selection = .init(x: 2, y: 1, width: 3, height: 2)
      let pattern = try PatternDefinition.make(in: d, name: "Composite")
      let full = try Renderer.composite(d)
      XCTAssertEqual(pattern.surface.width, 3)
      XCTAssertEqual(pattern.surface.height, 2)
      XCTAssertEqual(pattern.surface.depth, depth)
      // Renderer retains working float precision; a defined tile is stored at document depth.
      for y in 0..<2 {
        for x in 0..<3 {
          XCTAssertTrue(
            pattern.surface.pixel(x: x, y: y).hasSameBits(
              as: full.pixel(x: x + 2, y: y + 1).quantized(depth)))
        }
      }
      var tooLarge = try CraftDocument(width: 4001, height: 1)
      XCTAssertThrowsError(try PatternDefinition.make(in: tooLarge, name: "Too wide"))
      tooLarge.selection = .init(x: 0, y: 0, width: 2, height: 1)
      XCTAssertEqual(try PatternDefinition.make(in: tooLarge, name: "Small").surface.width, 2)
    }
  }
  func testPatternFillPSDAndRegionalRenderingAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 80, height: 64, depth: depth)
      let background = try Surface(width: 80, height: 64, depth: depth, fill: .white)
      d.layers[0].content = .raster(background)
      let before = try Renderer.render(d)
      d.selection = .init(x: 4, y: 4, width: 20, height: 20)
      let p = try PatternPresets.make()[4]
      var o = BucketOptions()
      o.match.antiAlias = false
      let fill = BucketFill(
        source: .init(surface: background), seed: .init(10, 10), color: .clear, options: o,
        pattern: p)
      try Command.paintBucket(d.layers[0].id, fill).apply(to: &d)
      let full = try Renderer.composite(d)
      let regional = try Renderer.render(d, reusing: before)
      XCTAssertEqual(try full.rgbaData(depth: .f32), try regional.surface.rgbaData(depth: .f32))
      let reopened = try Renderer.composite(PSDCodec.read(PSDCodec.writeRasterLayers(d)))
      for y in 0..<64 {
        for x in 0..<80 {
          let a = full.pixel(x: x, y: y)
          let b = reopened.pixel(x: x, y: y)
          let tolerance: Float = depth == .u8 ? 1 / 255 : depth == .u16 ? 1 / 65535 : 0.000002
          XCTAssertEqual(a.r, b.r, accuracy: tolerance)
          XCTAssertEqual(a.g, b.g, accuracy: tolerance)
          XCTAssertEqual(a.b, b.b, accuracy: tolerance)
          XCTAssertEqual(a.a, b.a, accuracy: tolerance)
        }
      }
    }
  }
}
