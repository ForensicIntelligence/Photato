import Foundation
import XCTest

@testable import PhotoCraftCore

final class CloneExpansionTests: XCTestCase {
  func source(_ depth: PixelDepth) throws -> Surface {
    var pixels = try Surface(width: 100, height: 80, depth: depth)
    for y in 0..<80 {
      for x in 0..<100 {
        pixels.setPixel(x: x, y: y, Pixel(Float(x) / 99, Float(y) / 79, 0.7))
      }
    }
    return pixels
  }
  func stroke(_ depth: PixelDepth, points: [StrokePoint], mask: Bool = false) throws -> CloneStroke
  {
    var brush = CloneBrush()
    brush.size = 7
    brush.hardness = 0.8
    brush.pressureSize = false
    return CloneStroke(
      source: .init(surface: try source(depth)),
      mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: brush,
      points: points, mask: mask)
  }
  func cropped(_ depth: PixelDepth) throws -> Layer {
    var s = try Surface(width: 5, height: 4, depth: depth, fill: Pixel(0.2, 0.3, 0.1, 0.4))
    s.setPixel(x: 2, y: 1, Pixel(0.6, 0.2, 0.9, 0))
    var layer = Layer(name: "Cropped", content: .raster(s))
    layer.x = 35
    layer.y = 25
    return layer
  }
  func raster(_ layer: Layer) throws -> Surface {
    guard case .raster(let pixels) = layer.content else {
      throw CraftError.invalid("Expected raster")
    }
    return pixels
  }
  func testCroppedTargetsMatchFullSizePaintingAtEveryDepthAndUndo() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 100, height: 80, depth: depth)
      document.layers = [try cropped(depth)]
      let original = document.layers[0]
      document.activeLayerID = original.id
      var expected = try Surface(width: 100, height: 80, depth: depth)
      let initial = try raster(original)
      for y in 0..<initial.height {
        for x in 0..<initial.width {
          expected.setPixel(x: original.x + x, y: original.y + y, initial.pixel(x: x, y: y))
        }
      }
      let paint = try stroke(
        depth,
        points: [
          .init(x: 12.5, y: 13.5), .init(x: 50.5, y: 50.5), .init(x: 80.5, y: 15.5),
        ])
      try ClonePainter.paint(paint, on: &expected, transform: .identity)
      var session = EditorSession(document: document)
      try session.execute(.cloneStamp(original.id, paint))
      let edited = session.document
      let layer = edited.layers[0]
      let actual = try raster(layer)
      XCTAssertLessThan(layer.x, original.x)
      XCTAssertLessThan(layer.y, original.y)
      XCTAssertGreaterThan(actual.width, initial.width)
      for y in 0..<80 {
        for x in 0..<100 {
          XCTAssertTrue(
            actual.pixel(x: x - layer.x, y: y - layer.y).hasSameBits(as: expected.pixel(x: x, y: y))
          )
        }
      }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(edited)), edited)
      XCTAssertEqual(session.undoStack.count, 1)
      session.undo()
      XCTAssertEqual(session.document, document)
      session.redo()
      XCTAssertEqual(session.document, edited)
    }
  }

  func testRasterReframingPreservesLinkedUnlinkedAndVectorMaskPositions() throws {
    for linked in [true, false] {
      var layer = try cropped(.u16)
      var mask = try Surface(width: 9, height: 7, depth: .u16, fill: .white)
      mask.setPixel(x: 2, y: 3, .black)
      layer.mask = mask
      var properties = MaskProperties()
      properties.transform = .translation(2, -1)
      properties.outside = 0.3
      properties.linked = linked
      properties.inverted = true
      properties.density = 0.6
      properties.feather = 1.3
      layer.maskProperties = properties
      layer.vectorMask = VectorMask(
        path: VectorPath(components: [
          PathComponent(
            knots: [PathKnot(.init(1, 2)), PathKnot(.init(80, 3)), PathKnot(.init(45, 70))],
            closed: true)
        ]))
      let original = layer
      let before = try MaskSampler(layer: original, canvasSize: (100, 80))
      try ClonePainter.paint(
        stroke(.u16, points: [.init(x: 8.5, y: 9.5)]), on: &layer, canvasWidth: 100,
        canvasHeight: 80)
      XCTAssertEqual(layer.mask, original.mask)
      XCTAssertEqual(layer.vectorMask, original.vectorMask)
      XCTAssertEqual(layer.maskCoordinateTransform, original.maskCoordinateTransform)
      XCTAssertEqual(layer.maskProperties?.linked, linked)
      let after = try MaskSampler(layer: layer, canvasSize: (100, 80))
      for y in 0..<80 {
        for x in 0..<100 {
          XCTAssertEqual(
            before.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5),
            after.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5))
        }
      }
    }
  }

  func testMaskExpansionUsesOutsideValueAndRetainsImagePixels() throws {
    for depth in PixelDepth.allCases {
      var layer = try cropped(depth)
      layer.mask = try Surface(width: 5, height: 4, depth: depth, fill: .black)
      var properties = MaskProperties()
      properties.transform = .translation(-2, 3)
      properties.outside = 0.65
      properties.linked = false
      properties.inverted = true
      properties.density = 0.8
      layer.maskProperties = properties
      let original = layer
      let oldTransform = layer.maskCoordinateTransform
      let paint = try stroke(
        depth, points: [.init(x: 10.5, y: 10.5), .init(x: 60.5, y: 52.5)], mask: true)
      // An independently decoded scalar default retains the continuous outside value.
      let floating = try Surface(width: 100, height: 80, depth: .f32, fill: Pixel(0.65, 0.65, 0.65))
      var plist = try XCTUnwrap(
        PropertyListSerialization.propertyList(
          from: PropertyListEncoder().encode(floating), format: nil) as? [String: Any])
      plist["depth"] = depth.rawValue
      var reference = try PropertyListDecoder().decode(
        Surface.self,
        from: PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0))
      for y in 0..<4 {
        for x in 0..<5 {
          reference.setPixel(x: Int(oldTransform.tx) + x, y: Int(oldTransform.ty) + y, .black)
        }
      }
      try ClonePainter.paint(paint, on: &reference, transform: .identity)
      try ClonePainter.paint(paint, on: &layer, canvasWidth: 100, canvasHeight: 80)
      XCTAssertEqual(layer.content, original.content)
      XCTAssertEqual(layer.coordinateTransform, original.coordinateTransform)
      XCTAssertEqual(layer.maskProperties?.outside, 0.65)
      XCTAssertEqual(layer.maskProperties?.linked, false)
      XCTAssertEqual(layer.maskProperties?.inverted, true)
      XCTAssertEqual(layer.maskProperties?.density, 0.8)
      let matrix = layer.maskCoordinateTransform
      let actual = try XCTUnwrap(layer.mask)
      for y in 0..<80 {
        for x in 0..<100 {
          let mx = x - Int(matrix.tx)
          let my = y - Int(matrix.ty)
          let p =
            mx >= 0 && my >= 0 && mx < actual.width && my < actual.height
            ? actual.pixel(x: mx, y: my) : Pixel(0.65, 0.65, 0.65)
          XCTAssertTrue(p.hasSameBits(as: reference.pixel(x: x, y: y)))
        }
      }
    }
  }

  func testCanvasAndFractionalSelectionClipPaintButRetainOffCanvasData() throws {
    var layer = try cropped(.f32)
    layer.x = -2
    layer.y = -1
    let before = layer
    let paint = try stroke(.f32, points: [.init(x: -1.5, y: -0.5), .init(x: 12.5, y: 4.5)])
    let selection = IntRect(x: 0, y: 0, width: 10, height: 8)
    let mask = try SelectionMask(width: 100, height: 80, bytes: Array(repeating: 128, count: 8000))
    try ClonePainter.paint(
      paint, on: &layer, canvasWidth: 100, canvasHeight: 80, selection: selection,
      selectionMask: mask)
    let pixels = try raster(layer)
    let old = try raster(before)
    XCTAssertEqual(layer.x, -2)
    XCTAssertEqual(layer.y, -1)
    for y in 0..<old.height {
      for x in 0..<old.width where x + before.x < 0 || y + before.y < 0 {
        XCTAssertTrue(pixels.pixel(x: x, y: y).hasSameBits(as: old.pixel(x: x, y: y)))
      }
    }
    XCTAssertLessThanOrEqual(layer.x + pixels.width, selection.x + selection.width)
    XCTAssertGreaterThan(pixels.pixel(x: 8 - layer.x, y: 3 - layer.y).a, 0)
    XCTAssertLessThan(pixels.pixel(x: 8 - layer.x, y: 3 - layer.y).a, 0.51)
  }

  func testAffineReframingRetainsExistingSampleBitsAndMaskGeometry() throws {
    var layer = try cropped(.f32)
    layer.affine = .rotation(23) * .scale(1.4, 0.8)
    layer.mask = try Surface(width: 5, height: 4, depth: .f32, fill: .white)
    let original = layer
    let originalPixels = try raster(layer)
    try ClonePainter.paint(
      stroke(.f32, points: [.init(x: 10.5, y: 10.5)]), on: &layer, canvasWidth: 100,
      canvasHeight: 80)
    let pixels = try raster(layer)
    let inverse = try layer.coordinateTransform.inverted()
    for y in 0..<originalPixels.height {
      for x in 0..<originalPixels.width {
        let world = original.coordinateTransform.point(Double(x) + 0.5, Double(y) + 0.5)
        let p = inverse.point(world.x, world.y)
        XCTAssertTrue(
          pixels.pixel(x: Int(floor(p.x)), y: Int(floor(p.y))).hasSameBits(
            as: originalPixels.pixel(x: x, y: y)))
      }
    }
    let a = original.maskCoordinateTransform.point(2.5, 1.5)
    let b = layer.maskCoordinateTransform.point(2.5, 1.5)
    XCTAssertEqual(a.x, b.x, accuracy: 1e-10)
    XCTAssertEqual(a.y, b.y, accuracy: 1e-10)
  }

  func testNoOpInvalidOversizedAndCancelledStrokesAreAtomic() async throws {
    let original = try cropped(.u8)
    var layer = original
    for variant in 0..<4 {
      var paint = try stroke(.u8, points: [.init(x: 5, y: 5)])
      switch variant {
      case 0: paint.brush.opacity = 0
      case 1: paint.source = .init(surface: try Surface(width: 100, height: 80))
      case 2: paint.points[0].pressure = 0
      default: paint.points[0].x = -100
      }
      XCTAssertFalse(try ClonePainter.paint(paint, on: &layer, canvasWidth: 100, canvasHeight: 80))
      XCTAssertEqual(layer, original)
    }
    var invalid = try stroke(.u8, points: [.init(x: .nan, y: 5)])
    XCTAssertThrowsError(
      try ClonePainter.paint(invalid, on: &layer, canvasWidth: 100, canvasHeight: 80))
    XCTAssertEqual(layer, original)
    invalid.points = [.init(x: 5, y: 5)]
    layer.x = -100_000
    let farAway = layer
    XCTAssertThrowsError(
      try ClonePainter.paint(invalid, on: &layer, canvasWidth: 100, canvasHeight: 80))
    XCTAssertEqual(layer, farAway)
    let paint = try stroke(.u8, points: [.init(x: 5, y: 5)])
    let task = Task.detached {
      var layer = original
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        try ClonePainter.paint(paint, on: &layer, canvasWidth: 100, canvasHeight: 80)
        XCTFail("Cancelled stroke must throw")
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(layer, original)
    }
    await task.value
  }
}
