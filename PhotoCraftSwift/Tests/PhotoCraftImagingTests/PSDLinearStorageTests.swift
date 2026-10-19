import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDLinearStorageTests: XCTestCase {
  let words: [UInt32] = [
    0, 0x8000_0000, 1, 0x8000_0001, 0x007f_ffff, 0x0080_0000,
    0x3dcc_cccd, 0x3eaa_aaab, 0x3f80_0001, 0xc050_0000, 0x7f7f_ffff,
  ]
  func source() -> Data {
    // Literal IEEE754 planes in a raw, flattened RGB32 PSD: no transfer helper.
    var file = PSDWriter()
    file.text("8BPS")
    file.n(1, 2)
    file.n(0, 6)
    file.n(3, 2)
    file.n(1, 4)
    file.n(words.count, 4)
    file.n(32, 2)
    file.n(3, 2)
    file.n(0, 4)
    file.n(0, 4)
    file.n(0, 4)
    file.n(0, 2)
    for _ in 0..<3 { for word in words { file.n(Int(word), 4) } }
    return file.data
  }
  func mergedWords(_ data: Data) throws -> [UInt32] {
    var reader = PSDReader(data: data)
    _ = try reader.bytes(26)
    for _ in 0..<3 { _ = try reader.bytes(reader.u32()) }
    XCTAssertEqual(try reader.u16(), 0)
    return try (0..<(words.count * 4)).map { _ in UInt32(try reader.u32()) }
  }
  func testLiteralLinearSamplesSurviveLayerAndMergedPSDOutputExactly() throws {
    let doc = try PSDCodec.read(source())
    guard case .raster(let surface) = doc.layers[0].content else { return XCTFail() }
    XCTAssertEqual(surface.colorEncoding, .linearRGB)
    for x in words.indices {
      XCTAssertEqual(surface.linearPixel(x: x, y: 0).r.bitPattern, words[x])
    }
    let native = try NativeArchive.decode(NativeArchive.encode(doc))
    for compression in PSDCompression.allCases {
      let output = try PSDCodec.writeRasterLayers(native, compression: compression)
      let read = try PSDCodec.read(output)
      guard case .raster(let pixels) = read.layers[0].content else { return XCTFail() }
      XCTAssertEqual(
        try pixels.rgbaData(depth: .f32, colorEncoding: .linearRGB),
        try surface.rgbaData(depth: .f32, colorEncoding: .linearRGB))
      XCTAssertEqual(
        try mergedWords(output),
        words + words + words + [UInt32](repeating: 0x3f80_0000, count: words.count))
    }
  }
  func testOriginalPhotoshopRGB32RepeatedSaveAndMetadataEditsKeepSampleBits() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-depth-32", withExtension: "psd", subdirectory: "Fixtures"))
    var doc = try PSDCodec.read(Data(contentsOf: url))
    let original = try doc.layers.map { layer -> Data in
      guard case .raster(let s) = layer.content else {
        throw CraftError.invalid("Reference must contain raster layers")
      }
      return try s.rgbaData(depth: .f32, colorEncoding: .linearRGB)
    }
    for index in 0..<3 {
      doc.layers[0].name = "Preserved \(index)"
      doc = try NativeArchive.decode(NativeArchive.encode(doc))
      doc = try PSDCodec.read(PSDCodec.writeRasterLayers(doc))
      for (i, layer) in doc.layers.enumerated() {
        guard case .raster(let pixels) = layer.content else { return XCTFail() }
        XCTAssertEqual(try pixels.rgbaData(depth: .f32, colorEncoding: .linearRGB), original[i])
      }
    }
  }
  func testOpaqueGroupedClippedAndRegionalCompositionKeepLinearBits() throws {
    let original = try PSDCodec.read(source())
    let expected = try Renderer.composite(original).rgbaData(depth: .f32, colorEncoding: .linearRGB)
    for passThrough in [false, true] {
      var doc = original
      var group = Layer(name: "Folder", content: .group(GroupContent(passThrough: passThrough)))
      group.mask = try Surface(width: doc.width, height: doc.height, fill: .white)
      doc.layers[0].parentID = group.id
      doc.layers.append(group)
      XCTAssertEqual(
        try Renderer.composite(doc).rgbaData(depth: .f32, colorEncoding: .linearRGB), expected)
      let region = IntRect(x: 1, y: 0, width: words.count - 2, height: 1)
      let regional = try Renderer.composite(doc, region: region)
      for x in 1..<(words.count - 1) {
        XCTAssertEqual(regional.linearPixel(x: x, y: 0).r.bitPattern, words[x])
      }
    }
    var clipped = original
    var top = Layer(name: "Clip", content: original.layers[0].content)
    top.clipped = true
    clipped.layers.append(top)
    XCTAssertEqual(
      try Renderer.composite(clipped).rgbaData(depth: .f32, colorEncoding: .linearRGB), expected)
    let baseline = try Renderer.render(original)
    var edited = original
    guard case .raster(var pixels) = edited.layers[0].content else { return XCTFail() }
    pixels.setLinearPixel(x: 0, y: 0, Pixel(Float(bitPattern: words.last!), -0.0, 0.1, 1))
    edited.layers[0].content = .raster(pixels)
    let incremental = try Renderer.render(edited, reusing: baseline)
    guard case .region = incremental.update else { return XCTFail("Expected a patch update") }
    XCTAssertEqual(
      try incremental.surface.rgbaData(depth: .f32, colorEncoding: .linearRGB),
      try Renderer.composite(edited).rgbaData(depth: .f32, colorEncoding: .linearRGB))
  }
}
