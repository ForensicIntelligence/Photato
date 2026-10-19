import Foundation
import XCTest

@testable import PhotoCraftCore

final class ToningTests: XCTestCase {
  func testIndependentRustKernelsAndDabOracle() throws {
    var exact = 0
    var count = 0
    var maximum: Float = 0
    func load(_ name: String) throws -> [UInt32] {
      let data = try Data(
        contentsOf: XCTUnwrap(
          Bundle.module.url(forResource: name, withExtension: "bin", subdirectory: "Fixtures")))
      return stride(from: 0, to: data.count, by: 4).map { p in
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[p + $1]) << ($1 * 8) }
      }
    }
    let words = try load("toning-oracle")
    for i in stride(from: 0, to: words.count, by: 10) {
      let op = words[i]
      let range = RetouchToneRange.allCases[Int(words[i + 1])]
      let flag = words[i + 2] == 1
      let c = SIMD3(
        Float(bitPattern: words[i + 3]), Float(bitPattern: words[i + 4]),
        Float(bitPattern: words[i + 5]))
      let e = Float(bitPattern: words[i + 6])
      let actual =
        op < 2
        ? ToningMath.dodgeBurn(c, exposure: e, range: range, burn: op == 1, protectTones: flag)
        : ToningMath.sponge(c, amount: e, saturate: op == 3, vibrance: flag)
      for j in 0..<3 {
        let expected = Float(bitPattern: words[i + 7 + j])
        XCTAssertEqual(actual[j], expected, accuracy: 0.000002, "case \(i/10)")
        maximum = max(maximum, abs(actual[j] - expected))
        count += 1
        if actual[j].bitPattern == expected.bitPattern { exact += 1 }
      }
    }
    let dabs = try load("toning-dab-oracle")
    for i in stride(from: 0, to: dabs.count, by: 3) {
      let actual = ToningMath.perDab(
        Float(bitPattern: dabs[i]), spacing: Float(bitPattern: dabs[i + 1]))
      let expected = Float(bitPattern: dabs[i + 2])
      XCTAssertEqual(actual, expected, accuracy: 0.000002)
      maximum = max(maximum, abs(actual - expected))
      count += 1
      if actual.bitPattern == expected.bitPattern { exact += 1 }
    }
    XCTAssertEqual(words.count / 10, 50208)
    XCTAssertEqual(dabs.count / 3, 707)
    print("Toning Rust oracle: \(exact)/\(count) exact Float32 values; maximum error \(maximum)")
  }
  func stroke(_ kind: ToningTool = .dodge) -> ToningStroke {
    var brush = CloneBrush()
    brush.size = 12
    brush.hardness = 1
    brush.pressureSize = false
    return ToningStroke(tool: kind, brush: brush, points: [.init(x: 20.5, y: 20.5)])
  }
  func pixels(_ layer: Layer) throws -> Surface {
    guard case .raster(let s) = layer.content else { throw CraftError.invalid("Expected raster") }
    return s
  }
  func testAllDepthsPreserveAlphaAndUntouchedSamplesWithUndoAndArchive() throws {
    for depth in PixelDepth.allCases {
      for kind in ToningTool.allCases {
        var d = try CraftDocument(width: 48, height: 48, depth: depth)
        var s = try Surface(width: 48, height: 48, depth: depth, fill: Pixel(0.8, 0.4, 0.3, 0.7))
        s.setPixel(x: 20, y: 19, Pixel(0.25, 0.7, 0.9, 0))
        d.layers[0].content = .raster(s)
        var session = EditorSession(document: d)
        try session.execute(.toning(d.layers[0].id, stroke(kind)))
        let output = try pixels(session.document.layers[0])
        let c = output.pixel(x: 20, y: 20)
        XCTAssertEqual(c.a, s.pixel(x: 20, y: 20).a)
        switch kind {
        case .dodge: XCTAssertGreaterThan(c.r, s.pixel(x: 20, y: 20).r)
        case .burn: XCTAssertLessThan(c.r, s.pixel(x: 20, y: 20).r)
        case .sponge:
          XCTAssertLessThan(c.r - c.b, s.pixel(x: 20, y: 20).r - s.pixel(x: 20, y: 20).b)
        }
        XCTAssertEqual(output.pixel(x: 20, y: 19), s.pixel(x: 20, y: 19))
        for y in 0..<48 {
          for x in 0..<48 where hypot(Double(x - 20), Double(y - 20)) >= 6.5 {
            XCTAssertTrue(output.pixel(x: x, y: y).hasSameBits(as: s.pixel(x: x, y: y)))
          }
        }
        let after = session.document
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(after)), after)
        XCTAssertEqual(session.undoStack.count, 1)
        session.undo()
        XCTAssertEqual(session.document, d)
        session.redo()
        XCTAssertEqual(session.document, after)
      }
    }
  }
  func testTonalRangesProtectTonesAndSpongeVibrance() {
    let gray: (Float) -> SIMD3<Float> = { SIMD3(repeating: $0) }
    let dark =
      ToningMath.dodgeBurn(
        gray(0.1), exposure: 0.5, range: .shadows, burn: false, protectTones: true
      ).x - 0.1
    let bright =
      ToningMath.dodgeBurn(
        gray(0.9), exposure: 0.5, range: .shadows, burn: false, protectTones: true
      ).x - 0.9
    XCTAssertGreaterThan(dark, bright * 10)
    let c = SIMD3<Float>(0.6, 0.3, 0.2)
    let protected = ToningMath.dodgeBurn(
      c, exposure: 0.5, range: .midtones, burn: false, protectTones: true)
    XCTAssertEqual(protected.x / protected.y, 2, accuracy: 0.00001)
    XCTAssertNotEqual(
      protected,
      ToningMath.dodgeBurn(c, exposure: 0.5, range: .midtones, burn: false, protectTones: false))
    let saturated = SIMD3<Float>(0.95, 0.1, 0.05)
    let a = ToningMath.sponge(saturated, amount: 0.5, saturate: false, vibrance: false)
    let b = ToningMath.sponge(saturated, amount: 0.5, saturate: false, vibrance: true)
    XCTAssertGreaterThan(b.x - b.z, a.x - a.z)
    XCTAssertEqual(ToningMath.luma(a), ToningMath.luma(saturated), accuracy: 0.00001)
  }
  func testSequentialDabsQuantizeOnceAndSelectionMixesOnce() throws {
    var s = try Surface(width: 48, height: 48, depth: .u8, fill: Pixel(0.5, 0.5, 0.5))
    let original = s.pixel(x: 20, y: 20)
    var layer = Layer(name: "Tones", content: .raster(s))
    var paint = stroke()
    paint.brush.opacity = 0.4
    paint.brush.spacing = 0.25
    paint.points = [.init(x: 17.5, y: 20.5), .init(x: 23.5, y: 20.5)]  // three full-coverage dabs
    let mask = try SelectionMask(
      width: 48, height: 48, bytes: Array(repeating: 128, count: 48 * 48))
    try ToningPainter.paint(
      paint, on: &layer, canvasWidth: 48, canvasHeight: 48,
      selection: .init(x: 19, y: 19, width: 3, height: 3), selectionMask: mask)
    var c = SIMD3(original.r, original.g, original.b)
    let k = ToningMath.perDab(0.5, spacing: 0.25)
    for _ in 0..<3 {
      c = ToningMath.dodgeBurn(c, exposure: k, range: .midtones, burn: false, protectTones: true)
    }
    let expected = Pixel(
      original.r + (c.x - original.r) * 0.4 * (128.0 / 255),
      original.g + (c.y - original.g) * 0.4 * (128.0 / 255),
      original.b + (c.z - original.b) * 0.4 * (128.0 / 255)
    ).quantized(.u8)
    s = try pixels(layer)
    XCTAssertEqual(s.pixel(x: 20, y: 20), expected)
    XCTAssertEqual(s.pixel(x: 18, y: 20), original)
    var split = paint
    split.points = [
      .init(x: 17.5, y: 20.5), .init(x: 18.5, y: 20.5), .init(x: 20.5, y: 20.5),
      .init(x: 23.5, y: 20.5),
    ]
    var other = Layer(
      name: "Other",
      content: .raster(try Surface(width: 48, height: 48, depth: .u8, fill: original)))
    try ToningPainter.paint(
      split, on: &other, canvasWidth: 48, canvasHeight: 48,
      selection: .init(x: 19, y: 19, width: 3, height: 3), selectionMask: mask)
    XCTAssertEqual(try pixels(other), s)
  }
  func testTransformedMaskExpansionUsesScalarAndKeepsRasterAndProperties() throws {
    var layer = Layer(
      name: "Image", content: .raster(try Surface(width: 80, height: 80, depth: .u16, fill: .white))
    )
    layer.mask = try Surface(width: 8, height: 8, depth: .u16, fill: Pixel(0.5, 0.1, 0.8, 0))
    var properties = MaskProperties()
    properties.transform = .translation(30, 30)
    properties.linked = false
    properties.outside = 0.5
    properties.feather = 2
    properties.density = 0.7
    layer.maskProperties = properties
    let before = layer
    var paint = stroke()
    paint.mask = true
    try ToningPainter.paint(paint, on: &layer, canvasWidth: 80, canvasHeight: 80)
    let at = try layer.maskCoordinateTransform.inverted().point(20.5, 20.5)
    let pixel = try XCTUnwrap(layer.mask).pixel(x: Int(at.x), y: Int(at.y))
    XCTAssertGreaterThan(pixel.r, 0.5)
    XCTAssertEqual(pixel.r, pixel.g)
    XCTAssertEqual(pixel.r, pixel.b)
    XCTAssertEqual(pixel.a, 1)
    XCTAssertEqual(layer.content, before.content)
    XCTAssertEqual(layer.effectiveMaskProperties.feather, 2)
    XCTAssertEqual(layer.effectiveMaskProperties.density, 0.7)
    let oldAt = try layer.maskCoordinateTransform.inverted().point(31.5, 31.5)
    XCTAssertEqual(
      try XCTUnwrap(layer.mask).pixel(x: Int(oldAt.x), y: Int(oldAt.y)),
      before.mask?.pixel(x: 1, y: 1))
  }
  func testEmptyZeroExposurePressureAndInvalidStrokesAreAtomic() throws {
    let empty = Layer(name: "Empty", content: .raster(try Surface(width: 1, height: 1)))
    var layer = empty
    XCTAssertFalse(try ToningPainter.paint(stroke(), on: &layer, canvasWidth: 48, canvasHeight: 48))
    XCTAssertEqual(layer, empty)
    let original = Layer(
      name: "Image",
      content: .raster(try Surface(width: 48, height: 48, fill: Pixel(0.5, 0.5, 0.5))))
    for test in 0..<5 {
      layer = original
      var paint = stroke()
      if test == 0 { paint.options.exposure = 0 }
      if test == 1 { paint.brush.flow = 0 }
      if test == 2 { paint.points = [.init(x: 20, y: 20, pressure: 0)] }
      if test == 3 { paint.options.exposure = .nan }
      if test == 4 { paint.points = [.init(x: .infinity, y: 20)] }
      if test < 3 {
        XCTAssertFalse(
          try ToningPainter.paint(paint, on: &layer, canvasWidth: 48, canvasHeight: 48))
      } else {
        XCTAssertThrowsError(
          try ToningPainter.paint(paint, on: &layer, canvasWidth: 48, canvasHeight: 48))
      }
      XCTAssertEqual(layer, original)
    }
  }
  func testPressureFlowAndTransformedTargets() throws {
    let original = try Surface(width: 48, height: 48, depth: .f32, fill: Pixel(0.5, 0.5, 0.5, 0.4))
    var a = Layer(name: "Local", content: .raster(original))
    var b = a
    b.x = 20
    b.y = 15
    b.affine = .scale(2, 2)
    var local = stroke()
    local.brush.pressureOpacity = true
    local.brush.flow = 0.4
    local.points = [.init(x: 20.5, y: 20.5, pressure: 0.5)]
    var transformed = local
    transformed.brush.size *= 2
    transformed.points = [.init(x: 61, y: 56, pressure: 0.5)]
    try ToningPainter.paint(local, on: &a, canvasWidth: 140, canvasHeight: 140)
    try ToningPainter.paint(transformed, on: &b, canvasWidth: 140, canvasHeight: 140)
    let center = try pixels(a).pixel(x: 20, y: 20)
    XCTAssertEqual(center, try pixels(b).pixel(x: 20, y: 20))
    let amount = ToningMath.perDab(0.5 * 0.4 * 0.5, spacing: 0.25)
    let expected = ToningMath.dodgeBurn(
      SIMD3(repeating: 0.5), exposure: amount, range: .midtones, burn: false, protectTones: true)
    XCTAssertEqual(center.r, expected.x, accuracy: 0.000001)
    XCTAssertEqual(center.a, 0.4)
    XCTAssertEqual(b.x, 20)
    XCTAssertEqual(b.y, 15)
    XCTAssertEqual(b.affine, .scale(2, 2))
  }
  func testRasterEdgeDoesNotExpandTransparentStorage() throws {
    var layer = Layer(
      name: "Cropped",
      content: .raster(try Surface(width: 8, height: 8, depth: .u16, fill: Pixel(0.5, 0.5, 0.5))))
    layer.x = 20
    layer.y = 20
    let before = layer
    var paint = stroke()
    paint.points = [.init(x: 20.5, y: 20.5)]
    XCTAssertTrue(try ToningPainter.paint(paint, on: &layer, canvasWidth: 80, canvasHeight: 80))
    let output = try pixels(layer)
    XCTAssertEqual(output.width, 8)
    XCTAssertEqual(output.height, 8)
    XCTAssertEqual(layer.x, before.x)
    XCTAssertEqual(layer.y, before.y)
    XCTAssertGreaterThan(output.pixel(x: 0, y: 0).r, 0.5)
  }
  @MainActor func testCancelledStrokeDoesNotCommit() async throws {
    let original = Layer(
      name: "Image",
      content: .raster(try Surface(width: 48, height: 48, fill: Pixel(0.5, 0.5, 0.5))))
    let paint = stroke()
    let task = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      var layer = original
      do {
        try ToningPainter.paint(paint, on: &layer, canvasWidth: 48, canvasHeight: 48)
        return false
      } catch is CancellationError { return layer == original } catch { return false }
    }
    let result = await task.value
    XCTAssertTrue(result)
  }
}
