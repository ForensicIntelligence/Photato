import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class RawCompositeTests: XCTestCase {
  private func document(_ pixels: Surface) throws -> CraftDocument {
    var document = try CraftDocument(width: pixels.width, height: pixels.height, depth: pixels.depth)
    var layer = Layer(name: "RAW cache", content: .raster(pixels))
    // The compositor consumes validated cached pixels, without reopening the source.
    layer.smartObject = try SmartObject(fileName: "Sensor.nef", mediaType: "image/x-camera-raw",
      data: Data([1]), width: pixels.width, height: pixels.height, rawDevelopment: RawDevelopment())
    document.layers = [layer]
    document.activeLayerID = layer.id
    return document
  }

  private func reference(_ document: CraftDocument, region: IntRect? = nil) throws -> Surface {
    let (prepared, transitions) = try Renderer.preparedSources(document)
    return try Renderer.compositePrepared(prepared,
      region: region ?? IntRect(x: 0, y: 0, width: document.width, height: document.height), video: transitions)
  }

  func testIntegerRawCompositeMatchesFullReferenceBeforeAndAfterIdentityTransform() throws {
    for depth in [PixelDepth.u8, .u16] {
      let levels = depth == .u8 ? 255 : 65_535
      let side = depth == .u8 ? 67 : 257
      var pixels = try Surface(width: side, height: side, depth: depth)
      for y in 0..<side {
        for x in 0..<side {
          let code = (y * side + x) & levels
          pixels.setPixel(x: x, y: y, Pixel(Float(code) / Float(levels),
            Float(levels - code) / Float(levels), Float((code * 17) & levels) / Float(levels)))
        }
      }
      XCTAssertNotNil(try pixels.opaqueFloatComposite())
      var document = try document(pixels)
      XCTAssertEqual(try Renderer.composite(document), try reference(document))
      document.layers[0].affine = .identity
      var composite = try Renderer.composite(document)
      XCTAssertEqual(composite, try reference(document))
      XCTAssertEqual(composite.depth, .f32)
      XCTAssertEqual(composite.colorEncoding, .sRGB)

      let sourceSample = pixels.pixel(x: 0, y: 0)
      composite.setPixel(x: 0, y: 0, .white)
      XCTAssertTrue(pixels.pixel(x: 0, y: 0).hasSameBits(as: sourceSample))
      XCTAssertTrue(try Renderer.composite(document).pixel(x: 0, y: 0).hasSameBits(as: sourceSample))
    }
  }

  func testRawCompositePreservesPartialAlphaIntegerOffsetsAndRegion() throws {
    var pixels = try Surface(width: 65, height: 67, depth: .u16, fill: Pixel(0.8, 0.3, 0.6))
    pixels.setPixel(x: 64, y: 66, Pixel(0.45, 0.27, 0.12, 0.65))
    XCTAssertNil(try pixels.opaqueFloatComposite())
    var document = try document(pixels)
    document.layers[0].affine = .identity
    XCTAssertEqual(try Renderer.composite(document), try reference(document))

    let opaque = try Surface(width: 65, height: 67, depth: .u16, fill: Pixel(0.6, 0.8, 0.9))
    document.layers[0].content = .raster(opaque)
    document.layers[0].affine = .translation(1, 0)
    XCTAssertEqual(try Renderer.composite(document), try reference(document))

    document.layers[0].affine = .identity
    let region = IntRect(x: 62, y: 63, width: 3, height: 4)
    XCTAssertEqual(try Renderer.composite(document, region: region), try reference(document, region: region))
    document.layers[0].opacity = 0.85
    XCTAssertEqual(try Renderer.composite(document), try reference(document))
  }
}
