import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class MaskBoundaryTests: XCTestCase {
  func fixture(_ name: String) throws -> CraftDocument {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name + "-photoshop", withExtension: "psd", subdirectory: "Fixtures/MaskBoundary"))
    return try PSDCodec.read(url)
  }
  func testIndependentPhotoshopOffCanvasBoundaryAndConstantControls() throws {
    let offcanvas = try fixture("offcanvas")
    let before = try NativeArchive.encode(offcanvas)
    let image = try Renderer.composite(offcanvas)
    // This checks the independently observed boundary behavior. The separate
    // Gaussian-kernel discrepancy remains open; it is not byte-equivalence proof.
    XCTAssertEqual(image.pixel(x: 0, y: 0).r, Float(120) / 255, accuracy: 6.0 / 255)
    XCTAssertEqual(try NativeArchive.encode(offcanvas), before)
    for (name, expected) in [("canvas", Float(1)), ("canvas-gray", Float(64) / 255)] {
      let control = try Renderer.composite(fixture(name))
      for y in 0..<12 { for x in 0..<12 {
        XCTAssertEqual(control.pixel(x: x, y: y).r, expected, accuracy: 0.000001)
      }}
    }
    let cropped = try Renderer.composite(fixture("cropped"))
    XCTAssertEqual(cropped.pixel(x: 0, y: 0).r, 1, accuracy: 0.000001)
  }
  func testApplyingAndSavingOffCanvasMaskPreservesNativeCompositeAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var document = try fixture("offcanvas")
      document.depth = depth
      document.workingICC = try ColorManagement.importedProfile(document.workingICC, depth: depth)
      for index in document.layers.indices {
        if case .raster(let pixels) = document.layers[index].content {
          var converted = try Surface(width: pixels.width, height: pixels.height, depth: depth,
            colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
          for y in 0..<pixels.height { for x in 0..<pixels.width {
            converted.setPixel(x: x, y: y, pixels.pixel(x: x, y: y))
          }}
          document.layers[index].content = .raster(converted)
        }
      }
      let original = document
      let before = try Renderer.composite(document)
      try Command.applyMask(document.layers.last!.id).apply(to: &document)
      let after = try Renderer.composite(document)
      let tolerance: Float = depth == .u8 ? 1 / 255 : depth == .u16 ? 1 / 65535 : 0.000001
      for y in 0..<12 { for x in 0..<12 {
        XCTAssertEqual(before.pixel(x: x, y: y).r, after.pixel(x: x, y: y).r, accuracy: tolerance)
      }}
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(original))
      XCTAssertEqual(try Renderer.composite(reopened), before)
    }
  }
}
