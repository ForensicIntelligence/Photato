import Foundation
import XCTest

@testable import PhotoCraftCore

final class LayerMaskTests: XCTestCase {
  func testStreamedFeatherReusesSecondStageRowsWithinBudgetWithoutChangingWords() throws {
    let width = 79, height = 91
    let windows = [23, 19, 17, 5]
    let secondWidth = width - windows[0] - windows[1] + 2
    let requiredBytes = secondWidth * windows[1] * MemoryLayout<Double>.stride
    for integer in [true, false] {
      let input = (0..<height).map { y in
        (0..<width).map { x -> Float in
          let code = (x * 317 + y * 271 + x * y * 41) % 32769
          return integer ? Float(code) : Float(code) / 32768
        }
      }
      var replayReads = 0, retainedReads = 0
      let replay = try XCTUnwrap(StreamingAreaFeather.filter(width: width, height: height,
        widths: windows, integerSamples: integer, secondStageCacheBytes: requiredBytes - 1) { y in
        replayReads += 1
        return input[y]
      })
      let retained = try XCTUnwrap(StreamingAreaFeather.filter(width: width, height: height,
        widths: windows, integerSamples: integer, secondStageCacheBytes: requiredBytes) { y in
        retainedReads += 1
        return input[y]
      })
      XCTAssertEqual(retained.map(\.bitPattern), replay.map(\.bitPattern))
      XCTAssertEqual(retainedReads, height + height - windows[0])
      XCTAssertGreaterThan(replayReads, retainedReads)
    }
  }

  func testFeatherInputBandsRetainReplayRowsAndImplicitBands() throws {
    let region = IntRect(x: 27, y: 17, width: 171, height: 258)
    var bands = FeatherInputBands(region: region)
    var reads: [IntRect] = []
    for y in [17, 18, 81, 100, 145, 156, 209, 208, 81, 274, 17] {
      let (values, offset) = bands.samples(for: y) { band in
        reads.append(band)
        if band.y == 81 { return nil }
        return (band.y..<band.y + band.height).flatMap { row in
          (0..<band.width).map { Float(row * 256 + $0) }
        }
      }
      if (81..<145).contains(y) {
        XCTAssertNil(values)
      } else {
        let values = try XCTUnwrap(values)
        XCTAssertEqual(values[offset], Float(y * 256))
        XCTAssertEqual(values[offset + region.width - 1], Float(y * 256 + region.width - 1))
      }
    }
    XCTAssertEqual(reads.map(\.y), [17, 81, 145, 209, 273, 17])
    XCTAssertEqual(reads.map(\.height), [64, 64, 64, 64, 2, 64])
    XCTAssertTrue(reads.allSatisfy { $0.x == region.x && $0.width == region.width })

    let maximum = IntRect(x: 0, y: 0, width: Surface.maxDimension, height: 600)
    var maximumBands = FeatherInputBands(region: maximum)
    _ = maximumBands.samples(for: 220) { band in
      XCTAssertEqual(band.height, 1)
      XCTAssertEqual(band.width, maximum.width)
      return nil
    }
  }

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
  func testFeatherTilesMatchDenseOperationsAtFractionalCoordinatesAndEdges() throws {
    for depth in PixelDepth.allCases {
      for clamped in [false, true] {
        var mask = try Surface(width: 65, height: 67, depth: depth, fill: Pixel(0.27, 0, 0))
        for y in stride(from: 0, to: mask.height, by: 6) {
          for x in stride(from: 0, to: mask.width, by: 7) {
            mask.setPixel(x: x, y: y, Pixel(Float((x + y * 7) % 30) / 29, 0, 0, 0.4))
          }
        }
        if depth == .f32 { mask = try mask.spillingTiles(to: RasterTileStore()) }
        var layer = Layer(name: "Variable mask", content: .fill(.white))
        layer.mask = mask
        var props = MaskProperties()
        props.feather = 2.3
        props.outside = 0.63
        props.inverted = true
        props.density = 0.78
        if !clamped { props.transform = .translation(10.25, -3.625) * .rotation(11) * .scale(0.8, 1.5) }
        layer.maskProperties = props
        let baseline = try denseFeather(mask, radius: props.feather, outside: props.outside, clamped: clamped)
        let inverse = try (layer.maskCoordinateTransform * .translation(
          -Double(baseline.padding), -Double(baseline.padding))).inverted()
        let sampler = try MaskSampler(layer: layer, canvasSize: (mask.width, mask.height))
        for row in stride(from: -20, through: 124, by: 3) {
          for column in stride(from: -16, through: 84, by: 2) {
            for offset in [0.5, 0.8125] {
              let x = Double(column) + offset, y = Double(row) + offset
              let point = inverse.point(x, y)
              let raw = MaskSampler.sample(baseline.surface, x: point.x, y: point.y, outside: props.outside)
              let expected: Float = 1 - props.density * (1 - (1 - raw))
              XCTAssertEqual(sampler.coverage(x: x, y: y).bitPattern, expected.bitPattern,
                "\(depth), clamped: \(clamped), x: \(x), y: \(y)")
            }
          }
        }
      }
    }
  }

  func testMaximumMaskUsesBoundedFeatherAtOneHundredPixels() throws {
    let side = Surface.maxDimension
    var mask = try Surface(width: side, height: side, depth: .f32, fill: .black)
    mask.setPixel(x: side - 1, y: side - 1, .white)
    var props = MaskProperties()
    props.feather = 100
    var layer = Layer(name: "One bright corner", content: .fill(.white))
    layer.mask = mask
    layer.maskProperties = props
    let sampler = try MaskSampler(layer: layer, canvasSize: (side, side))
    XCTAssertEqual(sampler.coverage(x: 0.5, y: 0.5), 0)
    XCTAssertEqual(sampler.coverage(x: 150_000.5, y: 150_000.5), 0)
    // At the lower-right pixel center, each pass retains the full replicated half-kernel.
    let kernel = (-300...300).map { Float(exp(-Double($0 * $0) / 20_000)) }
    let normalizer = kernel.reduce(Float(0), +)
    let half = kernel[300...].map { $0 / normalizer }
    let horizontal = half.reduce(Float(0), +)
    let expected = half.reduce(Float(0)) { $0 + horizontal * $1 }
    XCTAssertEqual(sampler.coverage(x: Double(side) - 0.5, y: Double(side) - 0.5).bitPattern,
      expected.bitPattern)
    XCTAssertEqual(mask.tileCount, 1)
  }

  private func denseFeather(_ source: Surface, radius: Double, outside: Float, clamped: Bool) throws
    -> (surface: Surface, padding: Int) {
    // Retained dense algorithm from before tiling, used only on small fixtures.
    let pad = Int(ceil(3 * radius)), w = source.width + 2 * pad, h = source.height + 2 * pad
    let raw = (-pad...pad).map { Float(exp(-Double($0 * $0) / (2 * radius * radius))) }
    let sum = raw.reduce(Float(0), +), weights = raw.map { $0 / sum }
    var horizontal = [Float](repeating: outside, count: w * h)
    for y in 0..<source.height {
      for x in 0..<w {
        var sample: Float = 0
        for k in -pad...pad {
          let sx = clamped ? min(source.width - 1, max(0, x - pad + k)) : x - pad + k
          let value = sx < 0 || sx >= source.width ? outside : unit(source.pixel(x: sx, y: y).r)
          sample += value * weights[k + pad]
        }
        horizontal[(y + pad) * w + x] = sample
      }
    }
    if clamped {
      for y in 0..<h where y < pad || y >= pad + source.height {
        let nearest = min(pad + source.height - 1, max(pad, y))
        for x in 0..<w { horizontal[y * w + x] = horizontal[nearest * w + x] }
      }
    }
    var output = try Surface(width: w, height: h, depth: .f32, fill: Pixel(outside, outside, outside))
    for y in 0..<h {
      for x in 0..<w {
        var value: Float = 0
        for k in -pad...pad {
          let sy = y + k
          let sample = sy < 0 || sy >= h ? outside : horizontal[sy * w + x]
          value += sample * weights[k + pad]
        }
        if abs(value - outside) > 0.000001 { output.setPixel(x: x, y: y, Pixel(value, value, value)) }
      }
    }
    return (output, pad)
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
