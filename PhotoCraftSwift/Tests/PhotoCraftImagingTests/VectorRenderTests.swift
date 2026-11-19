import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class VectorRenderTests: XCTestCase {
  func rect(
    _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ operation: PathOperation = .combine
  ) -> PathComponent {
    PathComponent(
      knots: [
        PathPoint(x, y), PathPoint(x + w, y), PathPoint(x + w, y + h),
        PathPoint(x, y + h),
      ].map { PathKnot($0) }, closed: true, operation: operation)
  }
  func testBooleanCoverageAndJoinedWindingHoles() throws {
    for operation in [PathOperation.combine, .subtract, .intersect, .exclude] {
      let path = VectorPath(components: [rect(2, 2, 8, 8), rect(6, 6, 8, 8, operation)])
      let mask = try VectorRasterizer.coverage(path, width: 16, height: 16)
      XCTAssertEqual(mask.coverage(x: 3, y: 3), operation == .intersect ? 0 : 1)
      XCTAssertEqual(mask.coverage(x: 7, y: 7), [.combine, .intersect].contains(operation) ? 1 : 0)
      XCTAssertEqual(mask.coverage(x: 12, y: 12), [.combine, .exclude].contains(operation) ? 1 : 0)
    }
    var hole = rect(4, 4, 4, 4, .join)
    hole.knots.reverse()
    var path = VectorPath(components: [rect(2, 2, 12, 12), hole])
    XCTAssertEqual(
      try VectorRasterizer.coverage(path, width: 16, height: 16).coverage(x: 6, y: 6), 0)
    path.components[1].knots.reverse()
    path.fillRule = .evenOdd
    XCTAssertEqual(
      try VectorRasterizer.coverage(path, width: 16, height: 16).coverage(x: 6, y: 6), 0)
    path.inverted = true
    XCTAssertEqual(
      try VectorRasterizer.coverage(path, width: 16, height: 16).coverage(x: 0, y: 0), 1)
  }
  func testPixelAndVectorMasksMultiplyAtEveryDepthIncludingGroups() throws {
    for depth in PixelDepth.allCases {
      for group in [false, true] {
        var d = try CraftDocument(width: 16, height: 16, depth: depth)
        var masked = Layer(name: "Masked", content: group ? .group(GroupContent()) : .fill(.white))
        masked.vectorMask = VectorMask(path: VectorPath(components: [rect(2, 2, 8, 8)]))
        masked.vectorMask!.density = 0.75
        masked.mask = try Surface(width: 16, height: 16, depth: .f32, fill: Pixel(0.4, 0.4, 0.4))
        var child = Layer(name: "White", content: .fill(.white))
        child.parentID = masked.id
        d.layers = group ? [child, masked] : [masked]
        d.activeLayerID = masked.id
        let image = try Renderer.composite(d)
        XCTAssertEqual(image.pixel(x: 3, y: 3).a, 0.4, accuracy: 1e-6)
        XCTAssertEqual(image.pixel(x: 13, y: 13).a, 0.1, accuracy: 1e-6)
        d.layers[d.layers.count - 1].vectorMask!.enabled = false
        XCTAssertEqual(try Renderer.composite(d).pixel(x: 13, y: 13).a, 0.4, accuracy: 1e-6)
      }
    }
  }
  func testEmptyMaskRevealsAllAndFeatherDoesNotClipAtCanvasEdge() throws {
    var d = try CraftDocument(width: 20, height: 16)
    d.layers[0].vectorMask = VectorMask()
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0).a, 1)
    d.layers[0].vectorMask!.path.inverted = true
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0).a, 0)
    d.layers[0].vectorMask = VectorMask(path: VectorPath(components: [rect(-40, -40, 48, 100)]))
    d.layers[0].vectorMask!.feather = 1.5
    let image = try Renderer.composite(d)
    XCTAssertEqual(image.pixel(x: 0, y: 0).a, 1, accuracy: 0.001)
    XCTAssertGreaterThan(image.pixel(x: 8, y: 5).a, 0.3)
    XCTAssertLessThan(image.pixel(x: 8, y: 5).a, 0.5)
  }
  func testBoundedVectorFeatherMatchesExistingCoverageAtEveryPixel() throws {
    var curve = rect(49.25, 19.5, 23.75, 36)
    curve.knots[0].outgoing = PathPoint(62.75, 3.5)
    curve.knots[1].incoming = PathPoint(70, 7.125)
    let parts = [rect(-9, -15, 35, 44), curve, rect(61, 33, 9, 12, .subtract)]
    for invert in [false, true] {
      var mask = VectorMask(path: VectorPath(components: parts, inverted: invert))
      mask.density = 0.71
      for radius in [0.125, 1.5, 2, 2.25, 14] {
        mask.feather = radius
        var document = try CraftDocument(width: 109, height: 86, depth: .f32)
        var layer = Layer(name: "Vector", content: .fill(.white))
        layer.vectorMask = mask
        document.layers = [layer]
        let exact = try LayerMaskSampler(layer: layer, document: document)
        let bounded = try VectorFeatherCoverage(mask: mask, width: document.width,
          height: document.height, outside: invert ? 1 : 0)
        var disagreements = 0
        for y in 0..<document.height {
          for x in 0..<document.width {
            let sample = (Double(x) + 0.5, Double(y) + 0.5)
            if bounded.coverage(x: sample.0, y: sample.1).bitPattern != exact.coverage(x: sample.0, y: sample.1).bitPattern {
              disagreements += 1
            }
          }
        }
        XCTAssertEqual(disagreements, 0, "radius \(radius), inverted \(invert)")
      }
    }
  }

  func testArchivedVectorFeatherEdgesAndCornersThroughDenseAndPagedRendering() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "photoshop-vector-32",
      withExtension: "psd", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let archived = try PSDCodec.read(data)
    let width = archived.width, height = archived.height
    var reader = PSDReader(data: data, offset: 26)
    for _ in 0..<3 { _ = try reader.section() }
    let bytes = try PSDChannelCodec.decode(reader.bytes(reader.remaining), width: width,
      height: height, depth: 32, channels: 3)
    func sample(_ x: Int, _ y: Int, channel: Int) throws -> Double {
      Double(try PSDChannelCodec.sample(bytes, (channel * height + y) * width + x, depth: 32))
    }

    // The archived merged planes contain two isolated flat-field edge pairs.
    let controls: [(radius: Double, x: Int, y: Int, rightY: Int, bottomX: Int, side: Int)] = [
      (1.5, 92, 72, 66, 50, 9), (2, 108, 34, 25, 106, 13),
    ]
    for control in controls {
      let (radius, x, y, rightY, bottomX, side) = control
      var mask = try XCTUnwrap(archived.layers.compactMap(\.vectorMask).first { $0.feather == radius })
      mask.density = 1
      let cases = [IntRect(x: x, y: rightY, width: side, height: 1),
        IntRect(x: bottomX, y: y, width: 1, height: side),
        IntRect(x: x, y: y, width: side, height: side)]
      var layer = Layer(name: "Aligned vector mask", content: .fill(.white))
      layer.vectorMask = mask
      var dense = try CraftDocument(width: width, height: height, depth: .f32)
      dense.layers = [layer]
      dense.activeLayerID = layer.id
      var paged = try CraftDocument(width: 300_000, height: 300_000, depth: .f32)
      paged.layers = [layer]
      paged.activeLayerID = layer.id
      let denseResult = try Renderer.composite(dense)
      let pagedResult = try Renderer.composite(paged)
      let plateau = try (0..<3).map { channel in
        (try sample(x - 1, rightY, channel: channel), try sample(x + side, rightY, channel: channel))
      }
      let right = try (0..<side).map { k in
        let (inside, outside) = plateau[1]
        let outer = (try sample(x + k, rightY, channel: 1) - inside) / (outside - inside)
        return Float(1 - (outer * 256).rounded() / 256)
      }
      var worst: Double = 0
      for (index, bounds) in cases.enumerated() {
        let viewport = try Renderer.composite(paged, region: bounds)
        for row in 0..<bounds.height {
          for column in 0..<bounds.width {
            let px = bounds.x + column, py = bounds.y + row
            let actual = denseResult.linearPixel(x: px, y: py).a
            let expected = index == 0 ? right[column] : index == 1 ? right[row] : right[column] * right[row]
            XCTAssertEqual(actual.bitPattern, expected.bitPattern, "\(radius) px at \(px),\(py)")
            XCTAssertEqual(pagedResult.linearPixel(x: px, y: py).a.bitPattern, actual.bitPattern)
            XCTAssertEqual(viewport.linearPixel(x: px, y: py).a.bitPattern, actual.bitPattern)
            for (channel, values) in plateau.enumerated() {
              let (inside, outside) = values
              let reference = (outside - (try sample(px, py, channel: channel))) / (outside - inside)
              worst = max(worst, abs(Double(actual) - reference))
            }
          }
        }
      }
      print("Archived RGB32 vector Feather \(radius) px: normalized residual \(worst)")
      XCTAssertLessThan(worst, 0.000001)
    }
  }

  func testMaximumVectorCanvasFeatherKeepsDistantContoursAndOffCanvasCoverage() throws {
    var document = try CraftDocument(width: 300_000, height: 300_000)
    var layer = Layer(name: "Vector", content: .fill(.white))
    var mask = VectorMask(path: VectorPath(components: [
      rect(15, -8, 22, 7), rect(59, 61, 14, 12), rect(299_905, 299_902, 20, 19)
    ]))
    mask.feather = 2
    layer.vectorMask = mask
    document.layers = [layer]
    document.activeLayerID = layer.id
    var patches = 0
    let canvas = IntRect(x: 0, y: 0, width: document.width, height: document.height)
    let raster = try PagedCanvasRenderer.composite(document, region: canvas, onPatch: { patches = $0 })
    XCTAssertGreaterThan(raster.pixel(x: 22, y: 0).a, 0)
    XCTAssertGreaterThan(raster.pixel(x: 65, y: 65).a, 0.88)
    XCTAssertGreaterThan(raster.pixel(x: 299_913, y: 299_909).a, 0.88)
    XCTAssertEqual(raster.pixel(x: 150_000, y: 150_000).a, 0)
    XCTAssertLessThanOrEqual(patches, 14)
    XCTAssertLessThan(raster.allocatedBytes, 4 * 1_024 * 1_024)
    let ordinary = try Renderer.composite(document)
    XCTAssertEqual(ordinary, raster)
    let region = IntRect(x: 58, y: 58, width: 18, height: 18)
    let local = try Renderer.composite(document, region: region)
    XCTAssertEqual(try raster.cropped(to: region).rgbaData(depth: .u8),
      try local.cropped(to: region).rgbaData(depth: .u8))
  }

  func testNonuniformThousandPixelVectorFeatherInMaximumCanvasViewport() throws {
    var document = try CraftDocument(width: 300_000, height: 300_000, depth: .f32)
    var layer = Layer(name: "Wide vector coverage", content: .fill(.white))
    var mask = VectorMask(path: VectorPath(components: [rect(149_600, 149_650, 800, 700)]))
    mask.feather = 1_000
    layer.vectorMask = mask
    document.layers = [layer]
    document.activeLayerID = layer.id
    let center = IntRect(x: 149_998, y: 149_998, width: 5, height: 5)
    let output = try Renderer.composite(document, region: center)
    let alpha = output.linearPixel(x: 150_000, y: 150_000).a
    XCTAssertGreaterThan(alpha, 0.05)
    XCTAssertLessThan(alpha, 0.5)
    XCTAssertGreaterThan(output.linearPixel(x: 149_999, y: 150_001).a, 0.05)
    let far = try Renderer.composite(document, region: .init(x: 298_000, y: 291_000, width: 1, height: 1))
    XCTAssertEqual(far.linearPixel(x: 298_000, y: 291_000).a, 0)
  }

  func testBroadVectorFeatherViewportPreservesWholeCoverageWords() throws {
    let width = 2_500, height = 1_750
    var curved = rect(-17.375, 80.25, 2_420.625, 1_540.5)
    curved.knots[0].outgoing = PathPoint(650.5, -42.25)
    curved.knots[1].incoming = PathPoint(1_710.75, 165.125)
    let shape = [curved, rect(400.25, 810.5, 333.5, 268.75, .subtract)]
    let viewport = IntRect(x: 1_083, y: 66, width: 13, height: 27)
    for (inverted, radius) in [(false, 2.0), (true, 115.25)] {
      var mask = VectorMask(path: VectorPath(components: shape, inverted: inverted))
      mask.feather = radius
      mask.density = 0.78
      let outside: Float = inverted ? 1 : 0
      let full = try VectorFeatherCoverage(mask: mask, width: width, height: height, outside: outside)
      let regional = try VectorFeatherCoverage(mask: mask, width: width, height: height, outside: outside,
        viewport: viewport)
      XCTAssertLessThan(regional.transferredInputPixels, full.transferredInputPixels / 2)
      for y in viewport.y..<viewport.y + viewport.height {
        for x in viewport.x..<viewport.x + viewport.width {
          for phase in [0.25, 0.5] {
            let px = Double(x) + phase, py = Double(y) + phase
            XCTAssertEqual(regional.coverage(x: px, y: py).bitPattern,
              full.coverage(x: px, y: py).bitPattern, "\(radius) px at \(px),\(py)")
          }
        }
      }
    }
  }

  func testMaximumCanvasBroadVectorMaskOnlyRasterizesViewportHalo() throws {
    var document = try CraftDocument(width: 300_000, height: 300_000, depth: .f32)
    let shape = rect(100_000.25, 100_000.25, 24_576, 24_576)
    var mask = VectorMask(path: VectorPath(components: [shape]))
    mask.feather = 2
    let viewport = IntRect(x: 99_995, y: 111_110, width: 12, height: 5)
    let sampler = try VectorFeatherCoverage(mask: mask, width: document.width, height: document.height,
      outside: 0, viewport: viewport)
    XCTAssertGreaterThan(sampler.transferredInputPixels, 0)
    XCTAssertLessThan(sampler.transferredInputPixels, 24_000)
    var layer = Layer(name: "Broad feathered mask", content: .fill(.white))
    layer.vectorMask = mask
    document.layers = [layer]
    document.activeLayerID = layer.id
    let publicViewport = try Renderer.composite(document, region: viewport)
    let pagedViewport = try PagedCanvasRenderer.composite(document, region: viewport)
    XCTAssertLessThan(publicViewport.linearPixel(x: viewport.x, y: viewport.y).a, 0.2)
    XCTAssertGreaterThan(publicViewport.linearPixel(x: viewport.x + viewport.width - 1, y: viewport.y).a, 0.99)
    for y in viewport.y..<viewport.y + viewport.height {
      for x in viewport.x..<viewport.x + viewport.width {
        let expected = sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5)
        XCTAssertEqual(publicViewport.linearPixel(x: x, y: y).a.bitPattern, expected.bitPattern)
        XCTAssertEqual(pagedViewport.linearPixel(x: x, y: y).a.bitPattern, expected.bitPattern)
      }
    }
    mask.path.inverted = true
    let clearCorner = IntRect(x: 20, y: 20, width: 1, height: 1)
    let localOutside = try VectorFeatherCoverage(mask: mask, width: document.width, height: document.height,
      outside: 1, viewport: clearCorner)
    XCTAssertEqual(localOutside.transferredInputPixels, 0)
    XCTAssertEqual(localOutside.coverage(x: 20.5, y: 20.5), 1)
    XCTAssertFalse(localOutside.isIdentity)
  }

  func testIntegerVectorFeatherMatchesNativeGray8CoverageAtEverySample() throws {
    for invert in [false, true] {
      var mask = VectorMask(path: VectorPath(components: [rect(-23, 33, 133, 48, .subtract)], inverted: invert))
      mask.density = 0.73
      for radius in [0.125, 1.5, 2, 2.25, 14] {
        mask.feather = radius
        let document = try CraftDocument(width: 141, height: 94, depth: .f32)
        var layer = Layer(name: "Integer vector mask", content: .fill(.white))
        layer.vectorMask = mask
        let native = try LayerMaskSampler(layer: layer, document: document)
        let virtual = try VectorFeatherCoverage(mask: mask, width: document.width,
          height: document.height, outside: invert ? 0 : 1)
        XCTAssertEqual(virtual.transferredInputPixels, 0)
        var differences = 0
        for y in 0..<document.height {
          for x in 0..<document.width {
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            if native.coverage(x: px, y: py).bitPattern != virtual.coverage(x: px, y: py).bitPattern {
              differences += 1
            }
          }
        }
        XCTAssertEqual(differences, 0, "radius \(radius), inverted \(invert)")
      }
    }
  }

  func testMaximumCanvasWholeVectorFeatherReusesPatternTiles() throws {
    let side = 300_000
    var document = try CraftDocument(width: side, height: side, depth: .f32)
    let base = Layer(name: "Canvas fill", content: .fill(Pixel(0.17, 0.28, 0.42)))
    var raster = try Surface(width: side, height: side, depth: .f32, fill: Pixel(0.72, 0.37, 0.51),
      colorEncoding: .linearRGB)
    let exception = (x: 28_010, y: 35_610)
    raster.setLinearPixel(x: exception.x, y: exception.y, Pixel(0.83, 0.06, 0.93, 0.41))
    var layer = Layer(name: "Sparse raster with broad mask", content: .raster(raster))
    var mask = VectorMask(path: VectorPath(components: [rect(27_777, 35_333, 240_000, 195_000)]))
    mask.feather = 2
    mask.density = 0.87
    layer.vectorMask = mask
    layer.opacity = 0.76
    document.layers = [base, layer]
    document.activeLayerID = layer.id
    try document.validate()
    var patches = 0
    let canvas = IntRect(x: 0, y: 0, width: side, height: side)
    let image = try PagedCanvasRenderer.composite(document, region: canvas, onPatch: { patches = $0 })
    XCTAssertLessThan(patches, 200)
    XCTAssertGreaterThan(image.mappedTileCount, 1_000_000)
    XCTAssertLessThan(image.allocatedBytes, 8 * 1_024 * 1_024)
    for (x, y) in [(0, 0), (27_773, 35_330), (27_773, 153_551), (200_050, 35_330),
      (187_109, 116_073), (267_773, 230_328), (110_090, 230_328),
      (exception.x - 3, exception.y - 2), (exception.x + 64 - 3, exception.y - 2), (299_993, 299_991)] {
      let roi = IntRect(x: x, y: y, width: 7, height: 9)
      let viewport = try Renderer.composite(document, region: roi)
      XCTAssertEqual(try image.cropped(to: roi).rgbaData(depth: .f32, colorEncoding: .linearRGB),
        try viewport.cropped(to: roi).rgbaData(depth: .f32, colorEncoding: .linearRGB), "\(x),\(y)")
    }
    print("Whole 300,000-square vector mask: \(patches) rendered tiles, \(image.mappedTileCount) index entries")
  }

  func testWholeWideRectanglesRespectFeatherPhaseAndPartialTiles() throws {
    let width = 8_097, height = 4_711
    var document = try CraftDocument(width: width, height: height, depth: .f32)
    var layer = Layer(name: "Inverted stripe", content: .fill(Pixel(0.56, 0.3, 0.75)))
    var mask = VectorMask(path: VectorPath(components: [rect(1619, -1_000, 3_513, 7_500, .subtract)]))
    mask.feather = 110.25
    mask.density = 0.8
    layer.vectorMask = mask
    document.layers = [layer]
    document.activeLayerID = layer.id
    let image = try Renderer.composite(document)
    for (x, y) in [(0, 0), (1_617, 0), (1_617, 741), (1_617, 1_118), (1_617, 3_128),
      (5_131, 741), (5_131, 1_118), (5_131, 4_704), (3_171, 2_250), (8_090, 4_704)] {
      let roi = IntRect(x: x, y: y, width: 7, height: 7)
      let viewport = try Renderer.composite(document, region: roi)
      XCTAssertEqual(try image.cropped(to: roi).rgbaData(depth: .f32, colorEncoding: .linearRGB),
        try viewport.cropped(to: roi).rgbaData(depth: .f32, colorEncoding: .linearRGB), "\(x),\(y)")
    }
  }

  func testRectangularFeatherOpacityProofMatchesEveryCanvasSample() throws {
    let width = 151, height = 131
    let cases: [(PathComponent, Bool, Double, Float)] = [
      (rect(-50, -50, 250, 235), false, 2, 1),
      (rect(-50, -50, 250, 235), false, 2.25, 1),
      (rect(12, 23, 105, 79), false, 2, 0x1p-26),
      (rect(-9, 33, 11, 81), true, 4.5, 0.82),
      (rect(177, 180, 17, 15), true, 2, 1),
      (rect(-330, -330, 811, 791), false, 110.25, 1),
      (rect(187, 177, 81, 85), true, 110.25, 0.73),
    ]
    for (index, fixture) in cases.enumerated() {
      let (path, inverted, radius, density) = fixture
      var mask = VectorMask(path: VectorPath(components: [path], inverted: inverted))
      mask.feather = radius
      mask.density = density
      let sampler = try VectorFeatherCoverage(mask: mask, width: width, height: height, outside: inverted ? 1 : 0)
      let expected = (0..<height).allSatisfy { y in
        (0..<width).allSatisfy { x in sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) == 1 }
      }
      XCTAssertEqual(try sampler.rectangleIsUnit(width: width, height: height), expected, "case \(index)")
      let clipped = try VectorFeatherCoverage(mask: mask, width: width, height: height, outside: inverted ? 1 : 0,
        viewport: IntRect(x: 90, y: 90, width: 2, height: 3))
      XCTAssertNil(try clipped.rectangleIsUnit(width: width, height: height))
    }
  }

  func testMaximumRGB32RasterStackUsesGlobalFeatheredBaseOpacity() throws {
    let side = 300_000
    let back = Pixel(0, 0.37, 0.63), front = Pixel(1, 0.31, 0.11)
    func document(size: Int, transparentReference: Bool = false) throws -> CraftDocument {
      var doc = try CraftDocument(width: size, height: size, depth: .f32)
      var backing = try Surface(width: size, height: size, depth: .f32, fill: back, colorEncoding: .linearRGB)
      if transparentReference { backing.setLinearPixel(x: 0, y: 0, Pixel(back.r, back.g, back.b, 0.5)) }
      let base = Layer(name: "Raster base", content: .raster(backing))
      var top = Layer(name: "Partial raster overlay", content: .raster(try Surface(width: size, height: size,
        depth: .f32, fill: front, colorEncoding: .linearRGB)))
      top.opacity = 119 / 255
      doc.layers = [base, top]
      doc.activeLayerID = top.id
      return doc
    }
    var full = try document(size: side)
    let opaqueControl = try Renderer.composite(document(size: 17)).linearPixel(x: 16, y: 16)
    let transparentControl = try Renderer.composite(document(size: 17, transparentReference: true))
      .linearPixel(x: 16, y: 16)
    XCTAssertFalse(opaqueControl.hasSameBits(as: transparentControl))
    let canvas = IntRect(x: 0, y: 0, width: side, height: side)
    let near = IntRect(x: 123, y: 67, width: 5, height: 7)
    let hole = rect(287_025, 294_031, 29, 39, .subtract)
    for opaque in [true, false] {
      let path = opaque ? rect(-20, -20, Double(side + 40), Double(side + 40)) : hole
      var mask = VectorMask(path: VectorPath(components: [path]))
      mask.feather = 2
      full.layers[0].vectorMask = mask
      let facts = CompositionFacts(full, vectorViewport: near)
      let localMask = try XCTUnwrap(facts.mask(full.layers[0], region: near))
      XCTAssertEqual(localMask.coverage(x: Double(near.x) + 0.5, y: Double(near.y) + 0.5), 1)
      XCTAssertEqual(try facts.opaqueBase(full.layers[0]), opaque)
      let expected = opaque ? opaqueControl : transparentControl
      let local = try Renderer.composite(full, region: near)
      XCTAssertTrue(local.linearPixel(x: near.x, y: near.y).hasSameBits(as: expected))
      var patches = 0
      let whole = try PagedCanvasRenderer.composite(full, region: canvas, onPatch: { patches = $0 })
      XCTAssertLessThan(patches, 100)
      XCTAssertTrue(whole.linearPixel(x: near.x, y: near.y).hasSameBits(as: expected))
      if !opaque {
        XCTAssertLessThanOrEqual(patches, 2)
        let remote = IntRect(x: 287_035, y: 294_043, width: 7, height: 7)
        let viewport = try Renderer.composite(full, region: remote)
        XCTAssertLessThan(whole.linearPixel(x: remote.x, y: remote.y).a, expected.a)
        XCTAssertEqual(try whole.cropped(to: remote).rgbaData(depth: .f32, colorEncoding: .linearRGB),
          try viewport.cropped(to: remote).rgbaData(depth: .f32, colorEncoding: .linearRGB))
      }
    }
    var mask = VectorMask(path: VectorPath(components: [rect(-20, -20, Double(side + 40), Double(side + 40))]))
    mask.feather = 2
    full.layers[0].vectorMask = mask
    var pixelMask = try Surface(width: side, height: side, depth: .f32, fill: .white)
    pixelMask.setPixel(x: side - 2, y: side - 2, .black)
    full.layers[0].mask = pixelMask
    XCTAssertFalse(try CompositionFacts(full, vectorViewport: near).opaqueBase(full.layers[0]))
    full.layers[0].mask = nil
    guard case .raster(var pixels) = full.layers[0].content else { return XCTFail("Raster fixture") }
    pixels.setLinearPixel(x: side - 2, y: side - 2, Pixel(back.r, back.g, back.b, 0.8))
    full.layers[0].content = .raster(pixels)
    XCTAssertFalse(try CompositionFacts(full, vectorViewport: near).opaqueBase(full.layers[0]))
  }

  func testCompactGrayTransferMatchesOriginalOnCurvesAndPartialTiles() throws {
    let width = 1_037, height = 1_031
    var curve = rect(12.25, -39.625, 1_081.375, 1_111.25)
    curve.knots[0].outgoing = PathPoint(400.125, 170.5)
    curve.knots[1].incoming = PathPoint(799.375, 88.75)
    for inverted in [false, true] {
      let path = VectorPath(components: [curve, rect(771.3, 707.75, 141.125, 139.25, .subtract)], inverted: inverted)
      let region = try VectorPathGeometry.filledRegion(path)
      let template = try Surface(width: width, height: height, fill: inverted ? .white : .black)
      let origin = PathPoint(0, 0)
      let old = try VectorRasterizer.pagedCoverage(region, template: template, origin: origin)
      let compact = try VectorRasterizer.pagedCoverage(region, template: template, origin: origin, compactTransfer: true)
      XCTAssertEqual(try compact.rgbaData(depth: .u8), try old.rgbaData(depth: .u8))
      let fullRegion = try VectorPathGeometry.filledRegion(VectorPath(
        components: [rect(-9, -11, 1_081, 1_070)], inverted: inverted))
      let uniform = try VectorRasterizer.pagedCoverage(fullRegion, template: template, origin: origin, compactTransfer: true)
      XCTAssertEqual(uniform.tileCount, 0)
      XCTAssertEqual(uniform.defaultPixel.r, inverted ? 0 : 1)
    }
  }

  func testWholeCurvedFeatherUsesStoredCoverageSupport() throws {
    let width = 8_195, height = 4_609
    var document = try CraftDocument(width: width, height: height, depth: .f32)
    let ribbon = PathComponent(knots: [
      PathKnot(PathPoint(302.25, 333.625), outgoing: PathPoint(1_220.375, 600.25)),
      PathKnot(PathPoint(3_659.5, 3_200.125), incoming: PathPoint(2_355.5, 2_570.5)),
      PathKnot(PathPoint(3_659.5, 3_222.125), outgoing: PathPoint(2_355.5, 2_592.5)),
      PathKnot(PathPoint(302.25, 355.625), incoming: PathPoint(1_220.375, 622.25)),
    ], closed: true)
    var mask = VectorMask(path: VectorPath(components: [ribbon], inverted: true))
    mask.feather = 2
    var layer = Layer(name: "Feathered curved ribbon", content: .fill(.white))
    layer.vectorMask = mask
    document.layers = [layer]
    document.activeLayerID = layer.id
    var patches = 0
    let canvas = IntRect(x: 0, y: 0, width: width, height: height)
    let image = try PagedCanvasRenderer.composite(document, region: canvas, onPatch: { patches = $0 })
    XCTAssertLessThan(patches, 90)
    XCTAssertLessThan(image.mappedTileCount, 240)
    XCTAssertLessThan(image.linearPixel(x: 307, y: 343).a, 0.1)
    XCTAssertEqual(image.linearPixel(x: 2_100, y: 500).a, 1)
    for (x, y) in [(298, 328), (304, 340), (905, 612), (1_874, 1_589), (3_652, 3_204), (2_100, 500)] {
      let roi = IntRect(x: x, y: y, width: 11, height: 13)
      let viewport = try Renderer.composite(document, region: roi)
      XCTAssertEqual(try image.cropped(to: roi).rgbaData(depth: .f32, colorEncoding: .linearRGB),
        try viewport.cropped(to: roi).rgbaData(depth: .f32, colorEncoding: .linearRGB), "\(x),\(y)")
    }
    print("Curved Feather: \(patches) output patches, \(image.mappedTileCount) stored tiles")
  }

  func testWideVectorFeatherPreservesEditablePSDAndPSBMaskProperties() throws {
    for both in [false, true] {
      for format in PSDFileFormat.allCases {
        var document = try CraftDocument(width: 64, height: 64, depth: .u16)
        var layer = Layer(name: "Vector target", content: .raster(try Surface(width: 64, height: 64,
          depth: .u16, fill: Pixel(0.75, 0.5, 0.25))))
        var mask = VectorMask(path: both ? VectorPath(components: [rect(-4, 5, 27, 34)]) : VectorPath())
        mask.density = Float(137) / 255
        mask.linked = false
        mask.feather = both ? 101.25 : 1_000
        layer.vectorMask = mask
        if both {
          layer.mask = try Surface(width: 64, height: 64, depth: .u16, fill: .white)
          layer.mask?.setPixel(x: 36, y: 14, .black)
        }
        document.layers = [layer]
        document.activeLayerID = layer.id
        let restored = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
        XCTAssertEqual(restored.layers[0].vectorMask, mask)
        if both {
          XCTAssertEqual(restored.layers[0].mask?.pixel(x: 36, y: 14).r, 0)
          XCTAssertEqual(restored.layers[0].mask?.pixel(x: 35, y: 14).r, 1)
        } else {
          XCTAssertNil(restored.layers[0].mask)
        }
        XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(document)), document)
      }
    }
  }

  func testPSDPathFixedPointRoundTripAndMalformedRecords() throws {
    var path = VectorPath(components: [
      rect(-3.125, 4.25, 20.5, 13.75), rect(5, 8, 4, 4, .subtract),
    ])
    path.components[0].knots[0].outgoing = PathPoint(4, -12)
    path.components[0].knots[0].smooth = true
    let data = try PSDPaths.write(path, width: 128, height: 64)
    XCTAssertEqual(try PSDPaths.read(data, width: 128, height: 64), path)
    XCTAssertThrowsError(try PSDPaths.read(data.dropLast(), width: 128, height: 64))
    var truncated = data
    truncated[54] = 0
    truncated[55] = 255
    XCTAssertThrowsError(try PSDPaths.read(truncated, width: 128, height: 64))
    for empty in [false, true] {
      for inverted in [false, true] {
        var mask = VectorMask(path: empty ? VectorPath() : path)
        mask.path.inverted = inverted
        mask.enabled = false
        mask.linked = false
        XCTAssertEqual(
          try PSDPaths.readMask(
            PSDPaths.writeMask(mask, width: 128, height: 64),
            width: 128, height: 64), mask)
      }
    }
    path.components[0].knots[0].anchor.x = 20_000
    XCTAssertThrowsError(try PSDPaths.write(path, width: 16, height: 16))
  }
  func assertPath(
    _ a: VectorPath, _ b: VectorPath, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(a.components.count, b.components.count, file: file, line: line)
    XCTAssertEqual(a.inverted, b.inverted, file: file, line: line)
    for (a, b) in zip(a.components, b.components) {
      XCTAssertEqual(a.operation, b.operation, file: file, line: line)
      XCTAssertEqual(a.closed, b.closed, file: file, line: line)
      XCTAssertEqual(a.knots.count, b.knots.count, file: file, line: line)
      for (a, b) in zip(a.knots, b.knots) {
        XCTAssertEqual(a.smooth, b.smooth, file: file, line: line)
        for (a, b) in zip([a.anchor, a.incoming, a.outgoing], [b.anchor, b.incoming, b.outgoing]) {
          XCTAssertEqual(a.x, b.x, accuracy: 0.00001, file: file, line: line)
          XCTAssertEqual(a.y, b.y, accuracy: 0.00001, file: file, line: line)
        }
      }
    }
  }
  func testPhotoshopVectorMasksAndPathsMatchSavedComposite() throws {
    for depth in [8, 16, 32] { try comparePhotoshopVector(depth) }
  }
  func comparePhotoshopVector(_ depth: Int) throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-vector-\(depth)", withExtension: "psd", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let d = try PSDCodec.read(data)
    let original = try fixture(depth: d.depth)
    XCTAssertEqual(d.layers.filter { $0.vectorMask != nil }.count, 2)
    XCTAssertEqual(d.layers.filter { $0.mask != nil }.count, 1)
    XCTAssertEqual(d.paths?.count, 2)
    for (a, b) in zip(original.layers, d.layers) {
      if let a = a.vectorMask, let b = b.vectorMask {
        assertPath(a.path, b.path)
        XCTAssertEqual(a.density, b.density, accuracy: 1 / 255)
        XCTAssertEqual(a.feather, b.feather)
      }
    }
    let native = try Renderer.composite(d)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let reference = try RasterIO.surface(image, depth: d.depth)
    var maximum: Float = 0
    var encodedMaximum: Float = 0
    var worst = ""
    for y in 0..<d.height {
      for x in 0..<d.width {
        var a = native.pixel(x: x, y: y)
        var b = reference.pixel(x: x, y: y)
        encodedMaximum = max(encodedMaximum, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
        if d.depth == .f32 {
          a = SRGBTransfer.linear(a)
          b = SRGBTransfer.linear(b)
        }
        let delta = max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b), abs(a.a - b.a))
        if delta > maximum {
          maximum = delta
          worst = "\(x),\(y): \(a) vs \(b)"
        }
      }
    }
    print(
      "Photoshop vector RGB/\(depth): max working-space channel difference \(maximum), encoded sRGB \(encodedMaximum) at \(worst)"
    )
    // Current Core Graphics edge rasterization/CPU feather is not pixel-identical to Photoshop.
    // Keep the measured tolerance explicit; do not relax the high-depth pixel/channel tests.
    XCTAssertLessThanOrEqual(maximum, 4 / 255)
  }
  func fixture(depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 128, height: 96, depth: depth, name: "Editable vector masks")
    var path = VectorPath(components: [rect(12, 12, 84, 64), rect(38, 30, 28, 24, .subtract)])
    path.components[0].knots[0].outgoing = PathPoint(32, -4)
    path.components[0].knots[1].incoming = PathPoint(80, 36)
    d.paths = [
      NamedPath(name: "Cutout", path: path, isWorkPath: false),
      NamedPath(path: VectorPath(components: [rect(5, 5, 7, 7)])),
    ]
    var layer = Layer(
      name: "Blue curved cutout",
      content: .raster(
        try Surface(
          width: 128, height: 96,
          depth: depth, fill: Pixel(0.1, 0.4, 0.9))))
    layer.vectorMask = VectorMask(path: path)
    layer.vectorMask!.feather = 1.5
    layer.vectorMask!.density = 0.8
    layer.mask = try Surface(width: 128, height: 96, depth: depth, fill: Pixel(0.7, 0.7, 0.7))
    d.layers.append(layer)
    var vectorOnly = Layer(
      name: "Vector only",
      content: .raster(
        try Surface(
          width: 128, height: 96,
          depth: depth, fill: Pixel(0.9, 0.2, 0.1))))
    vectorOnly.vectorMask = VectorMask(path: VectorPath(components: [rect(98, 10, 16, 30)]))
    vectorOnly.vectorMask!.density = 0.75
    vectorOnly.vectorMask!.feather = 2
    d.layers.append(vectorOnly)
    d.activeLayerID = layer.id
    return d
  }
  func testPSDVectorMetadataAndSavedPathsRoundTripAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth: depth)
      let bytes = try PSDCodec.writeRasterLayers(source)
      let decoded = try PSDCodec.read(bytes)
      for (a, b) in zip(source.layers, decoded.layers) {
        if let a = a.vectorMask?.path, let b = b.vectorMask?.path {
          assertPath(a, b)
        } else {
          XCTAssertEqual(a.vectorMask == nil, b.vectorMask == nil)
        }
        XCTAssertEqual(a.vectorMask?.feather, b.vectorMask?.feather)
        XCTAssertEqual(a.vectorMask?.enabled, b.vectorMask?.enabled)
        if let a = a.vectorMask, let b = b.vectorMask {
          XCTAssertEqual(a.density, b.density, accuracy: 1 / 255)
        }
        XCTAssertEqual(a.mask != nil, b.mask != nil)
      }
      for (a, b) in zip(source.paths ?? [], decoded.paths ?? []) { assertPath(a.path, b.path) }
      XCTAssertEqual(source.paths?.map(\.isWorkPath), decoded.paths?.map(\.isWorkPath))
      let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("artifacts/native-vector-\(depth.rawValue).psd")
      try bytes.write(to: output)
      let native = try Renderer.composite(source)
      let restored = try Renderer.composite(decoded)
      for y in 0..<96 {
        for x in 0..<128 {
          let a = native.pixel(x: x, y: y)
          let b = restored.pixel(x: x, y: y)
          XCTAssertEqual(a.r, b.r, accuracy: 0.003)
          XCTAssertEqual(a.b, b.b, accuracy: 0.003)
        }
      }
    }
  }
}
