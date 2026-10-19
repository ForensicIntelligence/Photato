import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class MaskCommandRenderTests: XCTestCase {
  func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var doc = try CraftDocument(width: 24, height: 16, depth: depth)
    var pixels = try Surface(width: 20, height: 12, depth: depth)
    for y in 0..<12 {
      for x in 0..<20 {
        pixels.setPixel(
          x: x, y: y, Pixel(Float(x) / 19, Float(y) / 11, 0.3, Float((x + y) % 5) / 4))
      }
    }
    var layer = Layer(name: "Apply this pixel mask", content: .raster(pixels))
    layer.x = 2
    layer.y = 1
    layer.mask = try Surface(width: 10, height: 7, depth: depth, fill: .white)
    var properties = MaskProperties()
    properties.transform = .translation(3, 2)
    properties.density = 0.75
    properties.feather = 1.5
    properties.linked = false
    layer.maskProperties = properties
    layer.opacity = 0.6
    var vector = VectorMask(
      path: VectorPath(components: [
        PathComponent(
          knots: [PathPoint(3, 2), PathPoint(21, 2), PathPoint(21, 14), PathPoint(3, 14)].map {
            PathKnot($0)
          },
          closed: true)
      ]))
    vector.density = 0.8
    layer.vectorMask = vector
    doc.layers.append(layer)
    doc.activeLayerID = layer.id
    return doc
  }

  func testApplyPreservesCompositeWithinStoragePrecisionAndPSDKeepsVectorMask() throws {
    for depth in PixelDepth.allCases {
      var document = try fixture(depth)
      let original = document
      let before = try Renderer.composite(document)
      try Command.applyMask(document.layers[1].id).apply(to: &document)
      let after = try Renderer.composite(document)
      let tolerance: Float = depth == .u8 ? 1 / 255 : depth == .u16 ? 1 / 65535 : 0.000001
      for y in 0..<document.height {
        for x in 0..<document.width {
          let a = before.pixel(x: x, y: y)
          let b = after.pixel(x: x, y: y)
          XCTAssertEqual(a.r, b.r, accuracy: tolerance)
          XCTAssertEqual(a.g, b.g, accuracy: tolerance)
          XCTAssertEqual(a.b, b.b, accuracy: tolerance)
          XCTAssertEqual(a.a, b.a, accuracy: tolerance)
        }
      }
      let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(document))
      XCTAssertNil(saved.layers[1].mask)
      XCTAssertEqual(saved.layers[1].vectorMask?.density, original.layers[1].vectorMask?.density)
      XCTAssertEqual(saved.layers[1].opacity, original.layers[1].opacity)
      // Input for independent Photoshop Apply Mask qualification; this is not a Photoshop oracle.
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      let bits = depth == .u8 ? 8 : depth == .u16 ? 16 : 32
      try PSDCodec.writeRasterLayers(original).write(
        to: root.appendingPathComponent("artifacts/native-apply-mask-\(bits).psd"))
    }
  }

  func testFromTransparencyAndApplyHandleAffineRasterWithOffCanvasContent() throws {
    var doc = try CraftDocument(width: 8, height: 8, depth: .f32)
    var pixels = try Surface(width: 6, height: 6, depth: .f32, fill: Pixel(0.2, 0.4, 0.8, 0.5))
    pixels.setPixel(x: 2, y: 2, Pixel(0.9, 0.2, 0.1, 0.1))
    var layer = Layer(name: "Affine pixels", content: .raster(pixels))
    layer.affine = .translation(1.4, -1.3) * .rotation(15)
    doc.layers = [layer]
    doc.activeLayerID = layer.id
    let before = try Renderer.composite(doc)
    try Command.createMask(layer.id, .fromTransparency).apply(to: &doc)
    XCTAssertNil(doc.layers[0].affine)
    XCTAssertLessThan(doc.layers[0].y, 0)
    let split = try Renderer.composite(doc)
    try Command.applyMask(layer.id).apply(to: &doc)
    let applied = try Renderer.composite(doc)
    for y in 0..<8 {
      for x in 0..<8 {
        let reference = before.pixel(x: x, y: y)
        for image in [split, applied] {
          let actual = image.pixel(x: x, y: y)
          XCTAssertEqual(actual.r, reference.r, accuracy: 0.000001)
          XCTAssertEqual(actual.g, reference.g, accuracy: 0.000001)
          XCTAssertEqual(actual.b, reference.b, accuracy: 0.000001)
          XCTAssertEqual(actual.a, reference.a, accuracy: 0.000001)
        }
      }
    }
  }
}
