import Foundation
import XCTest

@testable import PhotoCraftCore

final class HealingTests: XCTestCase {
  func testSolverAgainstExecutedRustRegions() throws {
    let data = try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "healing-oracle", withExtension: "bin", subdirectory: "Fixtures")))
    var pos = 0
    var regions = 0
    var values = 0
    var exact = 0
    func u32() -> UInt32 {
      defer { pos += 4 }
      return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[pos + $1]) << ($1 * 8) }
    }
    func floats(_ n: Int) -> [Float] { (0..<n).map { _ in Float(bitPattern: u32()) } }
    while pos < data.count {
      let w = Int(u32())
      let h = Int(u32())
      let c = Int(u32())
      let mask = (0..<w * h).map { _ -> Bool in
        defer { pos += 1 }
        return data[pos] != 0
      }
      let source = floats(w * h * c)
      let destination = floats(w * h * c)
      let expected = floats(w * h * c)
      let actual = try HealingSolver.seamlessClone(
        width: w, height: h, channels: c, source: source, destination: destination, mask: mask)
      for i in actual.indices {
        XCTAssertEqual(actual[i], expected[i], accuracy: 0.000002, "region \(regions), value \(i)")
        if actual[i].bitPattern == expected[i].bitPattern { exact += 1 }
        if !mask[i / c] { XCTAssertEqual(actual[i].bitPattern, destination[i].bitPattern) }
      }
      regions += 1
      values += actual.count
    }
    XCTAssertEqual(regions, 9)
    XCTAssertEqual(values, 68836)
    print("Healing Rust oracle: \(exact)/\(values) exact Float32 values; tolerance 2e-6")
  }

  func testLinearBoundaryAndDisconnectedHoles() throws {
    let w = 80
    let h = 60
    let truth = (0..<w * h).map { 0.2 + 0.005 * Float($0 % w) + 0.003 * Float($0 / w) }
    let mask = (0..<w * h).map { i in
      hypot(Double(i % w - 25), Double(i / w - 30)) < 13
        || hypot(Double(i % w - 60), Double(i / w - 35)) < 8
    }
    let actual = try HealingSolver.membrane(
      width: w, height: h, unknown: mask, values: mask.indices.map { mask[$0] ? 0 : truth[$0] })
    for i in actual.indices { XCTAssertEqual(actual[i], truth[i], accuracy: mask[i] ? 0.002 : 0) }
    XCTAssertEqual(
      try HealingSolver.membrane(width: 1, height: 1, unknown: [true], values: [-0.0])[0]
        .bitPattern, (-Float.zero).bitPattern)
  }

  func testMalformedAndOverflowingSolverInputsFail() {
    for (w, h, c) in [(0, 1, 1), (-1, 1, 1), (Int.max, 2, 1), (4096, 4096, 4), (1, 1, 5)] {
      XCTAssertThrowsError(
        try HealingSolver.seamlessClone(
          width: w, height: h, channels: c, source: [0], destination: [1], mask: [true]))
    }
    XCTAssertThrowsError(
      try HealingSolver.membrane(width: 1, height: 1, unknown: [false], values: [.nan]))
    XCTAssertThrowsError(
      try HealingSolver.seamlessClone(
        width: 2, height: 1, channels: 1,
        source: [-Float.greatestFiniteMagnitude, 0],
        destination: [Float.greatestFiniteMagnitude, 0], mask: [false, true]))
  }

  func testCancelledSolverAndPaintingLeaveTargetUnchanged() async throws {
    let layer = try target(.u16)
    let stroke = try paint(.u16)
    let task = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      var output = layer
      do {
        try HealingPainter.paint(stroke, on: &output, canvasWidth: 128, canvasHeight: 64)
        return false
      } catch is CancellationError { return output == layer } catch { return false }
    }
    let cancelled = await task.value
    XCTAssertTrue(cancelled)
  }

  func source(_ depth: PixelDepth) throws -> Surface {
    var s = try Surface(width: 128, height: 64, depth: depth)
    for y in 0..<64 {
      for x in 0..<128 {
        let t: Float = (x / 4) % 2 == 0 ? 0.08 : -0.08
        s.setPixel(x: x, y: y, x < 64 ? Pixel(0.2 + t, 0.25 + t, 0.5 + t) : Pixel(0.8, 0.6, 0.3))
      }
    }
    return s
  }
  func target(_ depth: PixelDepth) throws -> Layer {
    Layer(name: "Image", content: .raster(try source(depth)))
  }
  func paint(_ depth: PixelDepth) throws -> HealingStroke {
    var brush = CloneBrush()
    brush.size = 30
    brush.hardness = 1
    brush.pressureSize = false
    return HealingStroke(
      stroke: CloneStroke(
        source: .init(surface: try source(depth)),
        mapping: .init(source: .init(32, 32), anchor: .init(96, 32)), brush: brush,
        points: [.init(x: 96, y: 32)]))
  }
  func pixels(_ layer: Layer) throws -> Surface {
    guard case .raster(let pixels) = layer.content else { throw CraftError.invalid("Not raster") }
    return pixels
  }
  func testDestinationColorSourceTextureAtAllDepthsAndUndo() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 128, height: 64, depth: depth)
      d.layers = [try target(depth)]
      let id = d.layers[0].id
      d.activeLayerID = id
      var session = EditorSession(document: d)
      try session.execute(.healingBrush(id, paint(depth)))
      let result = try pixels(session.document.layers[0])
      let region = (24...40).flatMap { y in (88...104).map { x in result.pixel(x: x, y: y) } }
      let mean = region.reduce(Float(0)) { $0 + $1.r } / Float(region.count)
      let spread = try XCTUnwrap(region.map(\.r).max()) - XCTUnwrap(region.map(\.r).min())
      XCTAssertEqual(mean, 0.8, accuracy: 0.025)
      XCTAssertGreaterThan(spread, 0.12)
      XCTAssertEqual(result.pixel(x: 120, y: 4), try pixels(d.layers[0]).pixel(x: 120, y: 4))
      let healed = session.document
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(healed)), healed)
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo()
      XCTAssertEqual(session.document, d)
      try session.redo()
      XCTAssertEqual(session.document, healed)
    }
  }

  func testEmptyCroppedRetouchLayerUsesVisibleDestinationAndSelection() throws {
    for depth in PixelDepth.allCases {
      let base = try source(depth)
      var layer = Layer(
        name: "Retouch", content: .raster(try Surface(width: 2, height: 2, depth: depth)))
      layer.x = 70
      layer.y = 12
      var stroke = try paint(depth)
      stroke.destination = .init(surface: base)
      let selection = IntRect(x: 92, y: 28, width: 10, height: 10)
      let fractional = try SelectionMask(
        width: 128, height: 64, bytes: Array(repeating: 128, count: 128 * 64))
      try HealingPainter.paint(
        stroke, on: &layer, canvasWidth: 128, canvasHeight: 64, selection: selection,
        selectionMask: fractional)
      let output = try pixels(layer)
      XCTAssertGreaterThan(output.width, 2)
      for y in 0..<64 {
        for x in 0..<128 {
          let p = output.pixel(x: x - layer.x, y: y - layer.y)
          if selection.contains(x, y) {
            XCTAssertEqual(p.a, 128.0 / 255, accuracy: 1.0 / 255)
          } else {
            XCTAssertEqual(p, .clear)
          }
        }
      }
      XCTAssertEqual(base, stroke.destination?.surface)
    }
  }

  func testMaskHealingPreservesPixelsOutsideAndMaskProperties() throws {
    var layer = try target(.u16)
    var mask = try Surface(width: 16, height: 16, depth: .u16, fill: Pixel(0.7, 0.7, 0.7))
    mask.setPixel(x: 8, y: 8, .black)
    layer.mask = mask
    var props = MaskProperties()
    props.transform = .translation(88, 24)
    props.outside = 0.7
    props.linked = false
    layer.maskProperties = props
    let original = layer
    var stroke = try paint(.u16)
    stroke.stroke.mask = true
    try HealingPainter.paint(stroke, on: &layer, canvasWidth: 128, canvasHeight: 64)
    XCTAssertEqual(layer.content, original.content)
    XCTAssertEqual(layer.effectiveMaskProperties.outside, 0.7)
    XCTAssertEqual(layer.effectiveMaskProperties.linked, false)
    let at = try layer.maskCoordinateTransform.inverted().point(96.5, 32.5)
    let p = try XCTUnwrap(layer.mask).pixel(x: Int(at.x), y: Int(at.y))
    XCTAssertGreaterThan(p.r, 0.5)
    XCTAssertEqual(p.r, p.g)
    XCTAssertEqual(p.r, p.b)
    XCTAssertEqual(p.a, 1)
  }

  func testNoOpAndInvalidDestinationAreAtomic() throws {
    var layer = try target(.u8)
    let original = layer
    var stroke = try paint(.u8)
    stroke.stroke.brush.opacity = 0
    XCTAssertFalse(try HealingPainter.paint(stroke, on: &layer, canvasWidth: 128, canvasHeight: 64))
    XCTAssertEqual(layer, original)
    stroke.stroke.brush.opacity = 1
    stroke.destination = .init(surface: try source(.u8), transform: .scale(0, 1))
    XCTAssertThrowsError(
      try HealingPainter.paint(stroke, on: &layer, canvasWidth: 128, canvasHeight: 64))
    XCTAssertEqual(layer, original)
  }
  func testCoverageAtTileEdgeDoesNotAliasFollowingTile() throws {
    let surface = try Surface(width: 128, height: 128)
    var stroke = try paint(.u8).stroke
    stroke.brush.size = 1
    stroke.points = [.init(x: 127.5, y: 1.5), .init(x: 0.5, y: 65.5)]
    let coverage = try ClonePainter.strokeCoverage(stroke, surface: surface, transform: .identity)
    XCTAssertGreaterThan(coverage.value(x: 0, y: 65), 0)
    XCTAssertEqual(coverage.value(x: 128, y: 1), 0)
    XCTAssertEqual(coverage.value(x: -1, y: 65), 0)
    XCTAssertEqual(coverage.value(x: 0, y: 128), 0)
  }

  func testTranslatedLayerGridAndTransformedSourceUseDocumentCoordinates() throws {
    for depth in PixelDepth.allCases {
      var original = try target(depth)
      var moved = original
      moved.x = 40
      moved.y = 80
      var stroke = try paint(depth)
      stroke.stroke.mapping.rotation = 15
      stroke.stroke.mapping.width = 140
      try HealingPainter.paint(stroke, on: &original, canvasWidth: 240, canvasHeight: 160)
      let shift = Transform2D.translation(40, 80)
      stroke.stroke.source = .init(surface: stroke.stroke.source.surface, transform: shift)
      stroke.stroke.mapping.source = .init(72, 112)
      stroke.stroke.mapping.anchor = .init(136, 112)
      stroke.stroke.points = [.init(x: 136, y: 112)]
      try HealingPainter.paint(stroke, on: &moved, canvasWidth: 240, canvasHeight: 160)
      let a = try pixels(original)
      let b = try pixels(moved)
      for y in 0..<64 {
        for x in 0..<128 {
          let p = a.pixel(x: x, y: y)
          let q = b.pixel(x: x, y: y)
          XCTAssertEqual(p.r, q.r, accuracy: 0.000002)
          XCTAssertEqual(p.g, q.g, accuracy: 0.000002)
          XCTAssertEqual(p.b, q.b, accuracy: 0.000002)
          XCTAssertEqual(p.a, q.a)
        }
      }
      XCTAssertEqual(moved.x, 40)
      XCTAssertEqual(moved.y, 80)
    }
  }

  func testOversizedRepairFailsBeforeCommittingExpandedStorage() throws {
    var layer = Layer(name: "Retouch", content: .raster(try Surface(width: 1, height: 1)))
    let original = layer
    var stroke = try paint(.u8)
    stroke.stroke.brush.size = 1
    stroke.stroke.points = [.init(x: 100, y: 100), .init(x: 2500, y: 2200)]
    XCTAssertThrowsError(
      try HealingPainter.paint(stroke, on: &layer, canvasWidth: 3000, canvasHeight: 2400))
    XCTAssertEqual(layer, original)
  }

}
