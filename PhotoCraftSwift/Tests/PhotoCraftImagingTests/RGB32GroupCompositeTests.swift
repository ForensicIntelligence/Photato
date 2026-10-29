import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class RGB32GroupCompositeTests: XCTestCase {
  let names = [
    "01-pass-through", "02-pass-opacity", "03-isolated", "04-isolated-opacity-mask",
    "05-clipping", "07-nested-pass", "08-opaque-pass-opacity",
    "09-pass-opacity-213", "10-nested-masked", "11-isolated-first-transparent",
  ]

  func fixture(_ name: String, extension ext: String = "psd") throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: name, withExtension: ext, subdirectory: "Fixtures/rgb32-groups")))
  }

  func testIndependentPhotoshopGroupsClippingAndStraightLayerPreservation() throws {
    for name in names {
      let document = try PSDCodec.read(fixture(name))
      let before = try NativeArchive.encode(document)
      let golden = try fixture(name, extension: "merged")
      for compression in PSDCompression.allCases {
        let data = try PSDCodec.writeRasterLayers(document, compression: compression)
        let merged = try RGB32CompositeTests().merged(
          data, width: document.width, height: document.height)
        XCTAssertEqual(merged.count, golden.count)
        XCTAssertEqual(zip(merged, golden).filter { $0 != $1 }.count, 0, name)
        let reopened = try PSDCodec.read(data)
        XCTAssertEqual(reopened.layers.count, document.layers.count, name)
        for (a, b) in zip(document.layers, reopened.layers) {
          XCTAssertEqual(a.content, b.content, name)
          XCTAssertEqual(a.mask, b.mask, name)
          XCTAssertEqual(a.opacity.bitPattern, b.opacity.bitPattern, name)
          XCTAssertEqual(a.isClipped, b.isClipped, name)
          XCTAssertEqual(a.clipsBlendAsGroup, b.clipsBlendAsGroup, name)
          XCTAssertEqual(
            document.ancestors(of: a.id).map(\.name),
            reopened.ancestors(of: b.id).map(\.name), name)
        }
      }
      XCTAssertEqual(try NativeArchive.encode(document), before)
    }
  }

  func testRegionalRenderingUsesWholeCanvasOpacityClassification() throws {
    for name in names {
      let document = try PSDCodec.read(fixture(name))
      let full = try Renderer.composite(document)
      let partial = try Renderer.composite(
        document, region: IntRect(x: 7, y: 9, width: 31, height: 27))
      for y in 9..<36 {
        for x in 7..<38 {
          XCTAssertTrue(
            full.linearPixel(x: x, y: y).hasSameBits(
              as: partial.linearPixel(x: x, y: y)), name)
        }
      }
      XCTAssertEqual(partial.linearPixel(x: 0, y: 0), .clear)
    }
  }

  func testEmptyAndHiddenGroupsDoNotAlterTheVisibleNormalStack() throws {
    var document = try PSDCodec.read(fixture("01-pass-through"))
    let expected = try Renderer.composite(document)
    let empty = Layer(name: "Empty", content: .group(GroupContent()))
    document.layers.insert(empty, at: 0)
    var hidden = Layer(name: "Hidden", content: .group(GroupContent(passThrough: false)))
    hidden.visible = false
    var fill = Layer(name: "Hidden fill", content: .fill(.white))
    fill.parentID = hidden.id
    document.layers.append(contentsOf: [fill, hidden])
    XCTAssertEqual(
      try Renderer.composite(document).rgbaData(depth: .f32, colorEncoding: .linearRGB),
      try expected.rgbaData(depth: .f32, colorEncoding: .linearRGB))
  }
}
