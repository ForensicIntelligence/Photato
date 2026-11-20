import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class SpotChannelMergeTests: XCTestCase {
  func testRGBMergesWholePlateWithSolidityAndKeepsOtherChannels() throws {
    for (solidity, expected): (Float, [Int]) in [(0, [31, 82, 31]), (1, [51, 204, 153])] {
      var source = try CraftDocument(width: 3, height: 1)
      let rgb = try Surface(width: 3, height: 1, fill: Pixel(0.6, 0.4, 0.2))
      source.layers[0].content = .raster(rgb)
      var ink = try Surface(width: 3, height: 1, fill: .black)
      ink.setPixel(x: 1, y: 0, .white)
      let spot = AlphaChannel(name: "Proof ink", pixels: ink, spot: .init(color: Pixel(0.2, 0.8, 0.6), solidity: solidity))
      let saved = AlphaChannel(name: "Keep this mask", pixels: try Surface(width: 3, height: 1, fill: .white))
      let survivor = AlphaChannel(name: "Keep this ink", pixels: ink, spot: .init(color: Pixel(0.6, 0.2, 0.8)))
      source.alphaChannels = [saved, spot, survivor]
      source.selection = .init(x: 0, y: 0, width: 1, height: 1)
      source.resolution = 240
      let cmd = try SpotChannelMerge.command(source, channelID: spot.id)
      var session = EditorSession(document: source)
      try session.execute(cmd)
      let result = session.document
      XCTAssertEqual(result.layers.count, 1)
      XCTAssertTrue(result.layers[0].isBackground)
      XCTAssertEqual(result.selection, source.selection)
      XCTAssertEqual(result.resolution, 240)
      XCTAssertEqual(result.alphaChannels, [saved, survivor])
      guard case .raster(let actual) = result.layers[0].content else { return XCTFail("Expected merged Background") }
      XCTAssertEqual(actual.pixel(x: 0, y: 0), rgb.defaultPixel)
      XCTAssertEqual(actual.pixel(x: 2, y: 0), rgb.defaultPixel)
      let merged = actual.pixel(x: 1, y: 0)
      XCTAssertEqual([merged.r, merged.g, merged.b].map { Int(($0 * 255).rounded()) }, expected)
      XCTAssertEqual(merged.a, 1)
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo()
      XCTAssertEqual(session.document, source)
    }
  }

  func testMaximumSparseCMYKRetainsIndependentProcessWordsAndOriginalCMYKSwatch() throws {
    let w = 300_000, h = 300_000, end = w * h - 1
    var source = try CraftDocument(width: w, height: h, depth: .u16)
    var raster = try NativeModeRaster(width: w, height: h, mode: .cmyk, depth: .u16)
    raster = try raster.replacingOpacity(with: Surface(width: w, height: h, depth: .u16, fill: .white))
    let base: [Int] = [16431, 1151, 15691, 50017]
    let swatch: [Int] = [654, 1950, 49099, 8765]
    for i in base.indices {
      try raster.set(Float(base[i]) / 65535, component: i, index: 2)
      try raster.set(Float(base[i]) / 65535, component: i, index: end)
    }
    source.modeDescriptor = try .init(mode: .cmyk, depth: .u16, profile: raster.profile)
    source.layers[0].content = .raster(try raster.surface())
    source.layers[0].nativeMode = raster
    source.layers[0].background = true
    var mask = try Surface(width: w, height: h, depth: .u16, fill: .black)
    mask.setPixel(x: w - 1, y: h - 1, .white)
    var bytes = Data([0, 2])
    for value in swatch {
      let encoded = 65535 - value
      bytes.append(contentsOf: [UInt8(encoded >> 8), UInt8(encoded & 255)])
    }
    bytes.append(contentsOf: [0, 100, 2])
    let display = try PSDInkChannels.display(bytes)
    var channel = AlphaChannel(name: "Original CMYK spot", pixels: mask, spot: .init(color: display.color, solidity: 1))
    channel.psdDisplay = bytes
    source.alphaChannels = [channel]
    var result = source
    try SpotChannelMerge.command(source, channelID: channel.id).apply(to: &result)
    XCTAssertNil(result.alphaChannels)
    let actual = try XCTUnwrap(result.layers[0].nativeMode)
    XCTAssertTrue(actual.isOpaque)
    for i in base.indices {
      XCTAssertEqual(actual.rawWord(component: i, index: 0), 0)
      XCTAssertEqual(actual.rawWord(component: i, index: 2), UInt32(base[i]))
      XCTAssertEqual(actual.rawWord(component: i, index: end), UInt32(swatch[i]))
    }
    XCTAssertLessThan(actual.estimatedBytes, 4_000_000)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(result)), result)
  }

  func testTransparentLayeredCMYKKeepsBlackAndCompositesAgainstPaper() throws {
    var source = try CraftDocument(width: 2, height: 1, depth: .u16)
    var bottom = try NativeModeRaster(width: 2, height: 1, mode: .cmyk, depth: .u16)
    try bottom.set(0.8, component: 3, index: 0)
    try bottom.set(1, component: 4, index: 0)
    var top = try NativeModeRaster(width: 2, height: 1, mode: .cmyk, depth: .u16)
    try top.set(0.2, component: 3, index: 0)
    try top.set(0.25, component: 4, index: 0)
    try top.set(1, component: 3, index: 1)
    try top.set(0.5, component: 4, index: 1)
    source.modeDescriptor = try .init(mode: .cmyk, depth: .u16, profile: bottom.profile)
    source.layers[0].nativeMode = bottom
    source.layers[0].content = .raster(try bottom.surface())
    var upperLayer = Layer(name: "Translucent black", content: .raster(try top.surface()))
    upperLayer.nativeMode = top
    source.layers.append(upperLayer)
    let spot = try source.newSpotChannel(name: "Unused", ink: .init(color: .black), density: 0)
    source.alphaChannels = [spot]
    var result = source
    try SpotChannelMerge.command(source, channelID: spot.id).apply(to: &result)
    let native = try XCTUnwrap(result.layers[0].nativeMode)
    XCTAssertEqual(result.layers.count, 1)
    XCTAssertEqual(native.value(component: 3, index: 0), 0.65, accuracy: 2 / 65535)
    XCTAssertEqual(native.value(component: 3, index: 1), 0.5, accuracy: 2 / 65535)
    XCTAssertTrue(native.isOpaque)
    for fileType in [PSDFileFormat.psd, .psb] {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(result, format: fileType, compositeCompression: .raw))
      XCTAssertEqual(reopened.layers[0].nativeMode?.rawWord(component: 3, index: 0), native.rawWord(component: 3, index: 0))
      XCTAssertEqual(reopened.layers[0].nativeMode?.rawWord(component: 3, index: 1), native.rawWord(component: 3, index: 1))
      XCTAssertFalse(reopened.hasSpotChannels)
    }
  }
}
