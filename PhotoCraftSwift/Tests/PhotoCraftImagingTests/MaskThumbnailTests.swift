import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class MaskThumbnailTests: XCTestCase {
  func rectangle(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> VectorPath {
    VectorPath(components: [
      PathComponent(
        knots: [
          PathKnot(PathPoint(x, y)), PathKnot(PathPoint(x + width, y)),
          PathKnot(PathPoint(x + width, y + height)), PathKnot(PathPoint(x, y + height)),
        ], closed: true)
    ])
  }

  func testPixelMaskUsesDocumentTransformOutsideAndIgnoresSurfaceAlpha() throws {
    let document = try CraftDocument(width: 8, height: 4, depth: .f32)
    var layer = Layer(
      name: "Masked", content: .raster(try Surface(width: 2, height: 2, depth: .f32, fill: .white)))
    layer.x = 2
    layer.y = 1
    var mask = try Surface(width: 2, height: 2, depth: .f32, fill: Pixel(0, 1, 0, 0))
    mask.setPixel(x: 0, y: 0, Pixel(1, 0, 0, 0))
    layer.mask = mask
    var properties = MaskProperties()
    properties.transform = .translation(1, 0)
    properties.outside = 0.25
    properties.enabled = false
    properties.density = 0
    properties.feather = 3
    layer.maskProperties = properties
    layer.visible = false
    layer.opacity = 0
    let original = layer
    let result = try XCTUnwrap(
      Renderer.layerThumbnail(
        layer, in: document, framing: .entireDocument, maximumSize: 8, component: .pixelMask))
    for y in 0..<4 {
      for x in 0..<8 {
        let v: Float =
          (3...4).contains(x) && (1...2).contains(y) ? (x == 3 && y == 1 ? 1 : 0) : 0.25
        XCTAssertEqual(result.pixel(x: x, y: y), Pixel(v, v, v))
      }
    }
    XCTAssertEqual(layer, original)
  }

  func testLayerBoundsShareContentFrameWithoutStretchingMask() throws {
    let document = try CraftDocument(width: 8, height: 4, depth: .f32)
    var layer = Layer(
      name: "Cropped", content: .raster(try Surface(width: 2, height: 2, depth: .f32, fill: .white))
    )
    layer.x = 2
    layer.y = 1
    var mask = try Surface(width: 4, height: 4, depth: .f32)
    for y in 0..<4 {
      for x in 0..<4 {
        let v = Float(x) / 3
        mask.setPixel(x: x, y: y, Pixel(v, v, v))
      }
    }
    layer.mask = mask
    layer.maskProperties = MaskProperties()
    layer.maskProperties?.transform = .translation(-1, -1)
    let result = try XCTUnwrap(
      Renderer.layerThumbnail(
        layer, in: document, framing: .layerBounds, maximumSize: 2, component: .pixelMask))
    XCTAssertEqual(result.width, 2)
    XCTAssertEqual(result.height, 2)
    for y in 0..<2 {
      for x in 0..<2 { XCTAssertEqual(result.pixel(x: x, y: y), mask.pixel(x: x + 1, y: y + 1)) }
    }
  }

  func testPixelMaskMinificationRetainsLineAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let document = try CraftDocument(width: 32, height: 8, depth: depth)
      var layer = document.layers[0]
      var mask = try Surface(width: 32, height: 8, depth: depth)
      for x in 0..<32 { mask.setPixel(x: x, y: 0, Pixel(1, 0, 0, 0)) }
      layer.mask = mask
      let result = try XCTUnwrap(
        Renderer.layerThumbnail(
          layer, in: document, framing: .entireDocument, maximumSize: 4, component: .pixelMask))
      XCTAssertEqual(result.depth, depth)
      for x in 0..<4 {
        XCTAssertEqual(result.pixel(x: x, y: 0), Pixel(0.125, 0.125, 0.125).quantized(depth))
      }
    }
  }

  func testInversionIncludesOutsideCoverageDuringReduction() throws {
    let document = try CraftDocument(width: 4, height: 4, depth: .f32)
    var layer = document.layers[0]
    layer.mask = try Surface(width: 1, height: 1, depth: .f32, fill: .white)
    var properties = MaskProperties()
    properties.outside = 0.25
    properties.inverted = true
    layer.maskProperties = properties
    let result = try XCTUnwrap(
      Renderer.layerThumbnail(
        layer, in: document, framing: .entireDocument, maximumSize: 2, component: .pixelMask))
    XCTAssertEqual(result.pixel(x: 0, y: 0), Pixel(0.5625, 0.5625, 0.5625))
    XCTAssertEqual(result.pixel(x: 1, y: 1), Pixel(0.75, 0.75, 0.75))
  }

  func testVectorMaskShowsFilledCoverageWhileDisabledAndDoesNotApplyLayerTransformTwice() throws {
    let document = try CraftDocument(width: 4, height: 4)
    var layer = document.layers[0]
    layer.x = 100
    layer.y = 100
    var mask = VectorMask(path: rectangle(1, 1, 2, 2))
    mask.enabled = false
    mask.density = 0
    mask.feather = 3
    layer.vectorMask = mask
    let original = layer
    let result = try XCTUnwrap(
      Renderer.layerThumbnail(
        layer, in: document, framing: .entireDocument, maximumSize: 4, component: .vectorMask))
    for y in 0..<4 {
      for x in 0..<4 {
        let v: Float = (1...2).contains(x) && (1...2).contains(y) ? 1 : 128.0 / 255.0
        XCTAssertEqual(result.pixel(x: x, y: y), Pixel(v, v, v))
      }
    }
    XCTAssertEqual(layer, original)
  }

  func testEmptyAndInvertedVectorMasksOnGroupsUseCanvasFrame() throws {
    let document = try CraftDocument(width: 4, height: 2)
    var group = Layer(name: "Group", content: .group(.init()))
    group.vectorMask = VectorMask()
    for inverted in [false, true] {
      group.vectorMask?.path.inverted = inverted
      let result = try XCTUnwrap(
        Renderer.layerThumbnail(
          group, in: document, framing: .layerBounds, maximumSize: 4, component: .vectorMask))
      XCTAssertEqual(result.width, 4)
      XCTAssertEqual(result.height, 2)
      XCTAssertEqual(result.pixel(x: 0, y: 0).r, inverted ? 128.0 / 255.0 : 1)
    }
  }

  func testVectorMaskLayerBoundsAlignToRasterContent() throws {
    let document = try CraftDocument(width: 8, height: 4)
    var layer = Layer(
      name: "Vector cropped", content: .raster(try Surface(width: 2, height: 2, fill: .white)))
    layer.x = 2
    layer.y = 1
    layer.vectorMask = VectorMask(path: rectangle(2, 1, 2, 2))
    let result = try XCTUnwrap(
      Renderer.layerThumbnail(
        layer, in: document, framing: .layerBounds, maximumSize: 2, component: .vectorMask))
    XCTAssertEqual(result.width, 2)
    XCTAssertEqual(result.height, 2)
    for y in 0..<2 { for x in 0..<2 { XCTAssertEqual(result.pixel(x: x, y: y), .white) } }
  }

  func testMissingMasksAndInvalidPropertiesCannotBecomePreviews() throws {
    let document = try CraftDocument(width: 2, height: 2)
    var layer = document.layers[0]
    for component in [LayerThumbnailComponent.pixelMask, .vectorMask] {
      XCTAssertNil(
        try Renderer.layerThumbnail(
          layer, in: document, framing: .entireDocument, maximumSize: 2, component: component))
    }
    layer.mask = try Surface(width: 2, height: 2)
    layer.maskProperties = MaskProperties()
    layer.maskProperties?.transform = .scale(0, 0)
    XCTAssertThrowsError(
      try Renderer.layerThumbnail(
        layer, in: document, framing: .entireDocument, maximumSize: 2, component: .pixelMask))
  }
}
