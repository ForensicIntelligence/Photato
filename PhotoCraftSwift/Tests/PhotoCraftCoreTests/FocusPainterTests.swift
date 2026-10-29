import Foundation
import XCTest

@testable import PhotoCraftCore

final class FocusPainterTests: XCTestCase {
  func fixture(_ depth: PixelDepth) throws -> Surface {
    var s = try Surface(width: 72, height: 56, depth: depth)
    for y in 0..<56 {
      for x in 0..<72 { s.setPixel(x: x, y: y, Pixel(x < 30 ? 0.8 : 0.2, 0.2, 0.5)) }
    }
    return s
  }
  func stroke(_ kind: FocusTool) -> FocusStroke {
    var brush = CloneBrush()
    brush.size = 12
    brush.hardness = 1
    brush.pressureSize = false
    var options = FocusOptions()
    options.strength = 0.8
    options.protectDetail = false
    return FocusStroke(
      tool: kind, options: options, brush: brush,
      points: kind == .smudge
        ? [.init(x: 24.5, y: 24.5), .init(x: 40.5, y: 24.5)] : [.init(x: 29.5, y: 24.5)])
  }
  func pixels(_ layer: Layer) throws -> Surface {
    guard case .raster(let s) = layer.content else { throw CraftError.invalid("Expected raster") }
    return s
  }
  func testAllToolsAtEveryDepthChangeExpectedPixelsAndPersistWithOneUndo() throws {
    for depth in PixelDepth.allCases {
      for kind in FocusTool.allCases {
        var d = try CraftDocument(width: 72, height: 56, depth: depth)
        let original = try fixture(depth)
        d.layers[0].content = .raster(original)
        var session = EditorSession(document: d)
        try session.execute(.focus(d.layers[0].id, stroke(kind)))
        let output = try pixels(session.document.layers[0])
        switch kind {
        case .blur: XCTAssertLessThan(output.pixel(x: 29, y: 24).r, original.pixel(x: 29, y: 24).r)
        case .sharpen:
          XCTAssertGreaterThan(output.pixel(x: 29, y: 24).r, original.pixel(x: 29, y: 24).r)
        case .smudge:
          XCTAssertGreaterThan(output.pixel(x: 32, y: 24).r, original.pixel(x: 32, y: 24).r)
        }
        for y in 0..<56 {
          for x in 0..<72 where y < 17 || y > 32 || x < 17 || x > 47 {
            XCTAssertTrue(output.pixel(x: x, y: y).hasSameBits(as: original.pixel(x: x, y: y)))
          }
        }
        let after = session.document
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(after)), after)
        XCTAssertEqual(session.undoStack.count, 1)
        try session.undo()
        XCTAssertEqual(session.document, d)
        try session.redo()
        XCTAssertEqual(session.document, after)
      }
    }
  }
  func testSampleAllLayersWritesOnlyUnderStrokeOnEmptyLayer() throws {
    for kind in FocusTool.allCases {
      let source = try fixture(.u16)
      var layer = Layer(
        name: "Retouch", content: .raster(try Surface(width: 1, height: 1, depth: .u16)))
      var paint = stroke(kind)
      paint.options.sampleAllLayers = true
      paint.sample = .init(surface: source)
      XCTAssertTrue(try FocusPainter.paint(paint, on: &layer, canvasWidth: 72, canvasHeight: 56))
      let pixels = try pixels(layer)
      let at = try layer.coordinateTransform.inverted().point(29.5, 24.5)
      XCTAssertGreaterThan(pixels.pixel(x: Int(at.x), y: Int(at.y)).a, 0.9)
      XCTAssertEqual(pixels.pixel(x: 0, y: 0), .clear)
      var noSource = paint
      noSource.sample = nil
      let before = layer
      XCTAssertThrowsError(
        try FocusPainter.paint(noSource, on: &layer, canvasWidth: 72, canvasHeight: 56))
      XCTAssertEqual(layer, before)
    }
  }
  func testSmudgeCrossesSelectionButOnlyWritesSelectedPixelsAtFractionalOpacity() throws {
    let original = try fixture(.f32)
    var full = Layer(name: "Full", content: .raster(original))
    var selected = full
    var paint = stroke(.smudge)
    paint.brush.opacity = 0.4
    try FocusPainter.paint(paint, on: &full, canvasWidth: 72, canvasHeight: 56)
    let mask = try SelectionMask(
      width: 72, height: 56, bytes: Array(repeating: 128, count: 72 * 56))
    try FocusPainter.paint(
      paint, on: &selected, canvasWidth: 72, canvasHeight: 56,
      selection: .init(x: 30, y: 20, width: 12, height: 10), selectionMask: mask)
    let result = try pixels(selected)
    let reference = try pixels(full)
    XCTAssertGreaterThan(result.pixel(x: 32, y: 24).r, original.pixel(x: 32, y: 24).r)
    XCTAssertEqual(
      result.pixel(x: 32, y: 24).r,
      original.pixel(x: 32, y: 24).r
        + (reference.pixel(x: 32, y: 24).r - original.pixel(x: 32, y: 24).r) * (128.0 / 255),
      accuracy: 0.000002)
    XCTAssertEqual(result.pixel(x: 29, y: 24), original.pixel(x: 29, y: 24))
  }
  func testTransparentBlurHasNoHiddenGreenFringeAndCanExpandRaster() throws {
    var source = try Surface(width: 8, height: 20, depth: .f32, fill: Pixel(1, 0, 0))
    source.setPixel(x: 7, y: 10, Pixel(0, 1, 0, 0))
    var layer = Layer(name: "Red", content: .raster(source))
    layer.x = 20
    layer.y = 10
    var paint = stroke(.blur)
    paint.points = [.init(x: 27.5, y: 20.5)]
    try FocusPainter.paint(paint, on: &layer, canvasWidth: 72, canvasHeight: 56)
    let s = try pixels(layer)
    XCTAssertGreaterThan(s.width, 8)
    let at = try layer.coordinateTransform.inverted().point(28.5, 20.5)
    let p = s.pixel(x: Int(at.x), y: Int(at.y))
    XCTAssertGreaterThan(p.a, 0)
    XCTAssertEqual(p.r, 1, accuracy: 0.000001)
    XCTAssertEqual(p.g, 0, accuracy: 0.000001)
  }
  func testFingerPaintingCreatesPixelsAndCanPaintAnImplicitMask() throws {
    var layer = Layer(
      name: "Empty", content: .raster(try Surface(width: 1, height: 1, depth: .u16)))
    var paint = stroke(.smudge)
    paint.options.fingerPainting = true
    paint.foreground = Pixel(0.9, 0.2, 0.4, 0.6)
    XCTAssertTrue(try FocusPainter.paint(paint, on: &layer, canvasWidth: 72, canvasHeight: 56))
    let c = try pixels(layer).pixel(x: 24, y: 24)
    XCTAssertGreaterThan(c.a, 0)
    XCTAssertEqual(c.r, 0.9, accuracy: 0.00003)
    let raster = layer.content
    layer.mask = try Surface(width: 2, height: 2, depth: .u16, fill: Pixel(0.5, 0.1, 0.2, 0))
    var properties = MaskProperties()
    properties.outside = 0.5
    properties.feather = 2
    properties.linked = false
    layer.maskProperties = properties
    paint.mask = true
    paint.foreground = .black
    XCTAssertTrue(try FocusPainter.paint(paint, on: &layer, canvasWidth: 72, canvasHeight: 56))
    let at = try layer.maskCoordinateTransform.inverted().point(24.5, 24.5)
    let m = try XCTUnwrap(layer.mask).pixel(x: Int(at.x), y: Int(at.y))
    XCTAssertLessThan(m.r, 0.5)
    XCTAssertEqual(m.r, m.g)
    XCTAssertEqual(m.r, m.b)
    XCTAssertEqual(m.a, 1)
    XCTAssertEqual(layer.content, raster)
    XCTAssertEqual(layer.effectiveMaskProperties.feather, 2)
    XCTAssertFalse(layer.effectiveMaskProperties.linked)
  }
  func testTranslatedTargetsHaveIdenticalLocalResults() throws {
    for kind in FocusTool.allCases {
      var a = Layer(name: "A", content: .raster(try fixture(.u16)))
      var b = a
      b.x = 20
      b.y = 30
      let paint = stroke(kind)
      var shifted = paint
      shifted.points = paint.points.map { .init(x: $0.x + 20, y: $0.y + 30, pressure: $0.pressure) }
      try FocusPainter.paint(paint, on: &a, canvasWidth: 150, canvasHeight: 130)
      try FocusPainter.paint(shifted, on: &b, canvasWidth: 150, canvasHeight: 130)
      XCTAssertEqual(try pixels(a), try pixels(b))
      XCTAssertEqual(b.x - a.x, 20)
      XCTAssertEqual(b.y - a.y, 30)
    }
  }
  func testNoOpAndInvalidOrOversizedWorkNeverMutateTarget() throws {
    let original = Layer(name: "Image", content: .raster(try fixture(.u16)))
    for variant in 0..<6 {
      var layer = original
      var paint = stroke(.smudge)
      if variant == 0 { paint.options.strength = 0 }
      if variant == 1 { paint.brush.flow = 0 }
      if variant == 2 { paint.points = [.init(x: 30, y: 24, pressure: 0)] }
      if variant == 3 { paint.options.strength = .nan }
      if variant == 4 { paint.points = [.init(x: .nan, y: 24)] }
      if variant == 5 {
        paint.brush.size = 2048
        paint.points = [.init(x: 1, y: 1), .init(x: 5999, y: 3999)]
      }
      if variant < 3 {
        XCTAssertFalse(try FocusPainter.paint(paint, on: &layer, canvasWidth: 72, canvasHeight: 56))
      } else {
        XCTAssertThrowsError(
          try FocusPainter.paint(paint, on: &layer, canvasWidth: 6000, canvasHeight: 4000))
      }
      XCTAssertEqual(layer, original)
    }
    for kind in FocusTool.allCases {
      let empty = Layer(name: "Empty", content: .raster(try Surface(width: 1, height: 1)))
      var layer = empty
      XCTAssertFalse(
        try FocusPainter.paint(stroke(kind), on: &layer, canvasWidth: 72, canvasHeight: 56))
      XCTAssertEqual(layer, empty)
    }
  }
  @MainActor func testCancellationDoesNotCommit() async throws {
    let original = Layer(name: "Image", content: .raster(try fixture(.u16)))
    let paint = stroke(.blur)
    let task = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      var layer = original
      do {
        try FocusPainter.paint(paint, on: &layer, canvasWidth: 72, canvasHeight: 56)
        return false
      } catch is CancellationError { return layer == original } catch { return false }
    }
    let result = await task.value
    XCTAssertTrue(result)
  }
}
