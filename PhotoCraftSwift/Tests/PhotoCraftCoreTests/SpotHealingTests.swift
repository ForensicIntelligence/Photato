import Foundation
import XCTest

@testable import PhotoCraftCore

final class SpotHealingTests: XCTestCase {
  func fixture(_ depth: PixelDepth, dirty: Bool = true) throws -> Surface {
    var s = try Surface(width: 80, height: 60, depth: depth)
    for y in 0..<60 {
      for x in 0..<80 {
        let n = Float((x * 13 + y * 7) % 19) * 0.001
        let pixel =
          dirty && hypot(Double(x) - 40, Double(y) - 30) < 3
          ? Pixel(0.03, 0.03, 0.03)
          : Pixel(0.3 + Float(x) * 0.002 + n, 0.4 + Float(y) * 0.002 + n, 0.5 + n)
        s.setPixel(x: x, y: y, pixel)
      }
    }
    return s
  }
  func stroke(_ depth: PixelDepth, kind: SpotHealingType) throws -> SpotHealingStroke {
    var brush = CloneBrush()
    brush.size = 12
    brush.hardness = 1
    brush.pressureSize = false
    return SpotHealingStroke(
      sample: .init(surface: try fixture(depth)), brush: brush, points: [.init(x: 40, y: 30)],
      kind: kind)
  }
  func pixels(_ layer: Layer) throws -> Surface {
    guard case .raster(let s) = layer.content else { throw CraftError.invalid("Expected raster") }
    return s
  }
  func testAllModesRepairBlemishesAtAllDepthsAndPersistUndo() throws {
    for depth in PixelDepth.allCases {
      for kind in SpotHealingType.allCases {
        var d = try CraftDocument(width: 80, height: 60, depth: depth)
        d.layers[0].content = .raster(try fixture(depth))
        let id = d.layers[0].id
        var session = EditorSession(document: d)
        try session.execute(.spotHealing(id, stroke(depth, kind: kind)))
        let output = try pixels(session.document.layers[0])
        let clean = try fixture(depth, dirty: false)
        var error: Float = 0
        var before: Float = 0
        var count: Float = 0
        for y in 0..<60 {
          for x in 0..<80 {
            let p = output.pixel(x: x, y: y)
            let expected = clean.pixel(x: x, y: y)
            if hypot(Double(x) - 40, Double(y) - 30) < 3 {
              error += pow(p.r - expected.r, 2)
              before += pow(0.03 - expected.r, 2)
              count += 1
            }
            if hypot(Double(x) + 0.5 - 40, Double(y) + 0.5 - 30) >= 6.5 {
              XCTAssertEqual(p, try pixels(d.layers[0]).pixel(x: x, y: y))
            }
          }
        }
        XCTAssertLessThan(sqrt(error / count), 0.05, "\(kind), \(depth)")
        XCTAssertLessThan(error, before * 0.04)
        let healed = session.document
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(healed)), healed)
        XCTAssertEqual(session.undoStack.count, 1)
        session.undo()
        XCTAssertEqual(session.document, d)
        session.redo()
        XCTAssertEqual(session.document, healed)
      }
    }
  }
  func testSampledContextOntoEmptyCroppedLayerAndFractionalSelection() throws {
    for kind in SpotHealingType.allCases {
      let original = Layer(
        name: "Retouch", content: .raster(try Surface(width: 1, height: 1, depth: .u16)))
      var layer = original
      let paint = try stroke(.u16, kind: kind)
      let selection = IntRect(x: 38, y: 28, width: 5, height: 5)
      let mask = try SelectionMask(
        width: 80, height: 60, bytes: Array(repeating: 128, count: 80 * 60))
      try SpotHealingPainter.paint(
        paint, on: &layer, canvasWidth: 80, canvasHeight: 60, selection: selection,
        selectionMask: mask)
      let result = try pixels(layer)
      XCTAssertGreaterThan(result.pixel(x: 40, y: 30).r, 0.3)
      XCTAssertEqual(result.pixel(x: 40, y: 30).a, 128.0 / 255, accuracy: 1.0 / 65535)
      XCTAssertEqual(result.pixel(x: 35, y: 30), .clear)
      var noSource = paint
      noSource.sample = .init(surface: try pixels(original))
      layer = original
      XCTAssertFalse(
        try SpotHealingPainter.paint(noSource, on: &layer, canvasWidth: 80, canvasHeight: 60))
      XCTAssertEqual(layer, original)
    }
  }
  func testTranslatedSampleAndTargetHaveIdenticalLocalPixels() throws {
    for kind in SpotHealingType.allCases {
      var paint = try stroke(.u16, kind: kind)
      var a = Layer(name: "Image", content: .raster(paint.sample.surface))
      var b = a
      b.x = 30
      b.y = 50
      try SpotHealingPainter.paint(paint, on: &a, canvasWidth: 200, canvasHeight: 160)
      paint.sample = .init(surface: paint.sample.surface, transform: .translation(30, 50))
      paint.points = [.init(x: 70, y: 80)]
      try SpotHealingPainter.paint(paint, on: &b, canvasWidth: 200, canvasHeight: 160)
      XCTAssertEqual(try pixels(a), try pixels(b))
      XCTAssertEqual(b.x, 30)
      XCTAssertEqual(b.y, 50)
    }
  }
  func testMaskScalarRepairPreservesLayerAndProperties() throws {
    var mask = try Surface(width: 80, height: 60, depth: .u16, fill: Pixel(0.7, 0.7, 0.7))
    for y in 28...32 { for x in 38...42 { mask.setPixel(x: x, y: y, Pixel(0.03, 0.8, 0.2, 0)) } }
    for kind in SpotHealingType.allCases {
      var layer = Layer(name: "Image", content: .raster(try fixture(.u16)))
      layer.mask = mask
      var properties = MaskProperties()
      properties.outside = 0.7
      properties.linked = false
      layer.maskProperties = properties
      let before = layer
      var paint = try stroke(.u16, kind: kind)
      paint.mask = true
      paint.sample = .init(surface: mask, outside: Pixel(0.7, 0.7, 0.7))
      try SpotHealingPainter.paint(paint, on: &layer, canvasWidth: 80, canvasHeight: 60)
      let p = try XCTUnwrap(layer.mask).pixel(x: 40, y: 30)
      XCTAssertEqual(p.r, 0.7, accuracy: 0.01)
      XCTAssertEqual(p.r, p.g)
      XCTAssertEqual(p.r, p.b)
      XCTAssertEqual(p.a, 1)
      XCTAssertEqual(layer.content, before.content)
      XCTAssertEqual(layer.maskProperties, before.maskProperties)
    }
  }
  func testNoBoundaryInvalidInputAndOversizedRepairsAreAtomic() throws {
    var layer = Layer(
      name: "Tiny", content: .raster(try Surface(width: 2, height: 2, fill: .white)))
    let original = layer
    var paint = try stroke(.u8, kind: .contentAware)
    paint.points = [.init(x: 1, y: 1)]
    XCTAssertThrowsError(
      try SpotHealingPainter.paint(paint, on: &layer, canvasWidth: 2, canvasHeight: 2))
    XCTAssertEqual(layer, original)
    paint.points = [.init(x: .nan, y: 1)]
    XCTAssertThrowsError(
      try SpotHealingPainter.paint(paint, on: &layer, canvasWidth: 80, canvasHeight: 60))
    paint.points = [.init(x: 100, y: 100), .init(x: 2400, y: 2300)]
    XCTAssertThrowsError(
      try SpotHealingPainter.paint(paint, on: &layer, canvasWidth: 3000, canvasHeight: 2400))
    XCTAssertEqual(layer, original)
  }
  @MainActor func testCancelledRepairCannotCommit() async throws {
    let original = Layer(name: "Image", content: .raster(try fixture(.u8)))
    let paint = try stroke(.u8, kind: .contentAware)
    let task = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      var layer = original
      do {
        try SpotHealingPainter.paint(paint, on: &layer, canvasWidth: 80, canvasHeight: 60)
        return false
      } catch is CancellationError { return layer == original } catch { return false }
    }
    let cancelled = await task.value
    XCTAssertTrue(cancelled)
  }
}
