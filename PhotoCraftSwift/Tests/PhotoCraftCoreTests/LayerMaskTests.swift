import Foundation
import XCTest

@testable import PhotoCraftCore

final class LayerMaskTests: XCTestCase {
  func layer() throws -> Layer {
    var l = Layer(name: "Masked", content: .raster(try Surface(width: 12, height: 8, fill: .white)))
    l.x = 5
    l.y = 4
    l.mask = try Surface(width: 3, height: 2, fill: .white)
    var p = MaskProperties()
    p.transform = .translation(2, 1)
    l.maskProperties = p
    return l
  }
  func testOffsetOutsideDensityDisabledAndInversion() throws {
    var l = try layer()
    var sampler = try MaskSampler(layer: l)
    XCTAssertEqual(sampler.coverage(x: 7.5, y: 5.5), 1)
    XCTAssertEqual(sampler.coverage(x: 5.5, y: 4.5), 0)
    l.maskProperties?.density = 0.4
    sampler = try MaskSampler(layer: l)
    XCTAssertEqual(sampler.coverage(x: 5.5, y: 4.5), 0.6, accuracy: 0.0001)
    l.maskProperties?.outside = 1
    l.maskProperties?.inverted = true
    sampler = try MaskSampler(layer: l)
    XCTAssertEqual(sampler.coverage(x: -100, y: -100), 0.6, accuracy: 0.0001)
    l.maskProperties?.enabled = false
    XCTAssertEqual(try MaskSampler(layer: l).coverage(x: 7.5, y: 5.5), 1)
  }
  func testFeatherUsesGaussianSigmaAndExtendsAcrossMaskBounds() throws {
    var l = try layer()
    l.mask = try Surface(width: 1, height: 1, fill: .white)
    l.maskProperties?.feather = 1
    let s = try MaskSampler(layer: l)
    // Unit impulse through a separable Gaussian with sigma 1.
    XCTAssertEqual(s.coverage(x: 7.5, y: 5.5), 0.1592, accuracy: 0.001)
    XCTAssertEqual(s.coverage(x: 8.5, y: 5.5), 0.0966, accuracy: 0.001)
    XCTAssertEqual(s.coverage(x: 8.5, y: 5.5), s.coverage(x: 6.5, y: 5.5), accuracy: 0.00001)
  }
  func testCanvasBoundaryFeatherPreservesConstantMasksAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var l = try layer()
      l.mask = try Surface(width: 8, height: 6, depth: depth, fill: Pixel(0.25, 0.25, 0.25))
      // Opposing layer/affine translations put the raster and mask at the canvas origin.
      l.content = .raster(try Surface(width: 8, height: 6, depth: depth, fill: .white))
      l.affine = .translation(-5, -4)
      l.maskProperties?.transform = .identity
      l.maskProperties?.outside = 1
      l.maskProperties?.feather = 2
      l.maskProperties?.density = 0.4
      let value = try XCTUnwrap(l.mask).pixel(x: 0, y: 0).r
      for inverted in [false, true] {
        l.maskProperties?.inverted = inverted
        let sampler = try MaskSampler(layer: l, canvasSize: (8, 6))
        let expected: Float = 1 - 0.4 * (1 - (inverted ? 1 - value : value))
        for y in 0..<6 {
          for x in 0..<8 {
            XCTAssertEqual(
              sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5), expected,
              accuracy: 0.000001, "\(depth), inverted: \(inverted), pixel: \(x),\(y)")
          }
        }
      }
      l.maskProperties?.enabled = false
      XCTAssertEqual(try MaskSampler(layer: l, canvasSize: (8, 6)).coverage(x: 0.5, y: 0.5), 1)
    }
  }
  func testFeatherExtendsCanvasEdgesButStillSoftensCroppedEdges() throws {
    var l = Layer(name: "Corner mask", content: .fill(.white))
    l.mask = try Surface(width: 4, height: 4, fill: .white)
    l.maskProperties = MaskProperties()
    l.maskProperties?.feather = 1
    let sampler = try MaskSampler(layer: l, canvasSize: (12, 12))
    // Analytic separable sigma-1 Gaussian: the cropped edges each retain 0.699525 coverage.
    XCTAssertEqual(sampler.coverage(x: 0.5, y: 0.5), 1, accuracy: 0.000001)
    XCTAssertEqual(sampler.coverage(x: 3.5, y: 3.5), 0.489335, accuracy: 0.00001)
    XCTAssertEqual(sampler.coverage(x: 4.5, y: 4.5), 0.090285, accuracy: 0.00001)
    XCTAssertEqual(sampler.coverage(x: 10.5, y: 10.5), 0)
  }
  func testFeatherRetainsOffCanvasMaskSamples() throws {
    var l = Layer(name: "Off-canvas mask", content: .fill(.white))
    l.mask = try Surface(width: 8, height: 8, fill: .white)
    for y in 0..<8 { l.mask?.setPixel(x: 0, y: y, .black) }
    l.maskProperties = MaskProperties()
    l.maskProperties?.transform = .translation(-2, -2)
    l.maskProperties?.feather = 1
    let sampler = try MaskSampler(layer: l, canvasSize: (4, 4))
    let unclipped = try MaskSampler(layer: l)
    for y in 0..<4 {
      for x in 0..<4 {
        XCTAssertEqual(
          sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5),
          unclipped.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5))
      }
    }
    XCTAssertLessThan(sampler.coverage(x: 0.5, y: 0.5), 0.99)
    XCTAssertGreaterThan(sampler.coverage(x: 0.5, y: 0.5), 0.9)
    XCTAssertEqual(try MaskSampler(layer: l, feather: false).coverage(x: 0.5, y: 0.5), 1)
  }
  func testOffCanvasRasterDoesNotClampMaskAtCanvasEdges() throws {
    // Photoshop's owned offcanvas-photoshop.psd renders the corner near 120/255,
    // versus 255 when these coincident mask/canvas edges are incorrectly clamped.
    for depth in PixelDepth.allCases {
      for offset in [0, 8] {
        var layer = Layer(name: "Beyond canvas", content: .raster(
          try Surface(width: 24, height: 24, depth: depth, fill: .white)))
        layer.x = -6; layer.y = -6
        layer.mask = try Surface(width: 4, height: 4, depth: depth, fill: .white)
        var properties = MaskProperties()
        properties.transform = .translation(Double(offset + 6), Double(offset + 6))
        properties.feather = 1
        layer.maskProperties = properties
        let canvas = try MaskSampler(layer: layer, canvasSize: (12, 12))
        let unbounded = try MaskSampler(layer: layer)
        let actual = (0..<144).map { canvas.coverage(x: Double($0 % 12) + 0.5, y: Double($0 / 12) + 0.5) }
        let expected = (0..<144).map { unbounded.coverage(x: Double($0 % 12) + 0.5, y: Double($0 / 12) + 0.5) }
        XCTAssertEqual(actual, expected, "\(depth), mask origin \(offset)")
      }
    }
  }
  func testLinkedAndUnlinkedMovesAndCanvasRotation() throws {
    var d = try CraftDocument(width: 30, height: 20)
    let l = try layer()
    d.layers = [l]
    d.activeLayerID = l.id
    try Command.move(l.id, 10, 8).apply(to: &d)
    XCTAssertEqual(d.layers[0].maskCoordinateTransform, .translation(12, 9))
    d.layers[0].maskProperties?.linked = false
    try Command.move(l.id, 15, 10).apply(to: &d)
    XCTAssertEqual(d.layers[0].maskCoordinateTransform, .translation(12, 9))
    try Command.transform(l.id, .scale(2, 2), .nearest).apply(to: &d)
    XCTAssertEqual(d.layers[0].maskCoordinateTransform, .translation(12, 9))
    let before = d.layers[0].maskCoordinateTransform
    let turn = CanvasTurn.clockwise.transform(width: d.width, height: d.height)
    try Command.rotateCanvas(.clockwise).apply(to: &d)
    XCTAssertEqual(d.layers[0].maskCoordinateTransform, turn * before)
  }
  func testMaskFillAndStrokeUseMaskCoordinates() throws {
    var d = try CraftDocument(width: 30, height: 20)
    let l = try layer()
    d.layers = [l]
    d.activeLayerID = l.id
    d.selection = IntRect(x: 8, y: 5, width: 1, height: 1)
    try Command.maskFill(l.id, 0).apply(to: &d)
    XCTAssertEqual(d.layers[0].mask?.pixel(x: 1, y: 0).r, 0)
    XCTAssertEqual(d.layers[0].mask?.pixel(x: 0, y: 0).r, 1)
    try Command.invertMask(l.id).apply(to: &d)
    XCTAssertEqual(d.layers[0].maskProperties?.outside, 1)
    XCTAssertEqual(d.layers[0].mask?.pixel(x: 1, y: 0).r, 1)
    d.selection = nil
    var b = Brush()
    b.color = .black
    b.size = 1
    b.hardness = 1
    try Command.maskStroke(l.id, [StrokePoint(x: 7.5, y: 5.5)], b).apply(to: &d)
    XCTAssertEqual(d.layers[0].mask?.pixel(x: 0, y: 0).r, 0)
  }
  func testMaskPropertiesArchiveUndoAndValidation() throws {
    var d = try CraftDocument(width: 30, height: 20)
    let l = try layer()
    d.layers = [l]
    d.activeLayerID = l.id
    var engine = EditorSession(document: d)
    var properties = l.effectiveMaskProperties
    properties.density = 0.25
    properties.feather = 2
    try engine.execute(.maskProperties(l.id, properties))
    XCTAssertEqual(engine.document.layers[0].maskProperties, properties)
    try engine.undo()
    XCTAssertEqual(engine.document.layers[0], l)
    try engine.redo()
    let data = try NativeArchive.encode(engine.document)
    XCTAssertEqual(try NativeArchive.decode(data), engine.document)
    properties.feather = .nan
    XCTAssertThrowsError(try Command.maskProperties(l.id, properties).apply(to: &d))
    d.layers[0].locked = true
    XCTAssertThrowsError(try Command.maskProperties(l.id, MaskProperties()).apply(to: &d))
  }
}

extension LayerMaskTests {
  func testPaintingExpandsCroppedMaskWithoutMovingOldSamples() throws {
    var d = try CraftDocument(width: 30, height: 20)
    let l = try layer()
    d.layers = [l]
    d.activeLayerID = l.id
    var b = Brush()
    b.size = 1
    b.hardness = 1
    b.color = .white
    try Command.maskStroke(l.id, [StrokePoint(x: 5.5, y: 4.5)], b).apply(to: &d)
    let sampler = try MaskSampler(layer: d.layers[0])
    XCTAssertEqual(sampler.coverage(x: 5.5, y: 4.5), 1)
    XCTAssertEqual(sampler.coverage(x: 7.5, y: 5.5), 1)
    XCTAssertEqual(sampler.coverage(x: 6.5, y: 4.5), 0)
    XCTAssertEqual(d.layers[0].maskCoordinateTransform, .translation(5, 4))
    d.selection = IntRect(x: 14, y: 10, width: 1, height: 1)
    try Command.maskFill(l.id, 1).apply(to: &d)
    XCTAssertEqual(try MaskSampler(layer: d.layers[0]).coverage(x: 14.5, y: 10.5), 1)
    d.selection = nil
    try Command.maskFill(l.id, 1).apply(to: &d)
    XCTAssertEqual(try MaskSampler(layer: d.layers[0]).coverage(x: -100, y: -100), 1)
  }
}
