import Foundation
import XCTest

@testable import PhotoCraftCore

final class ColorRegionTests: XCTestCase {
  func testPagedAndDenseCoverageMatchAcrossDepthsTransformsAndSettings() throws {
    let width = 139, height = 81
    for depth in PixelDepth.allCases {
      var surface = try Surface(width: width, height: height, depth: depth, fill: .white)
      for y in 0..<height {
        for x in 0..<width where (x / 7 + y / 5) % 4 == 0 || (x + y) % 57 == 0 {
          surface.setPixel(x: x, y: y, Pixel(0.17, 0.34, 0.78, x % 2 == 0 ? 0 : 0.61))
        }
      }
      for transform in [Transform2D.identity, .translation(11, -9), .translation(0.25, 0.5),
                        .rotation(8), .scale(0.000_001, 1)] {
        let source = CloneSample(surface: surface, transform: transform, outside: .white)
        for mask in [false, true] {
          for contiguous in [false, true] {
            for antiAlias in [false, true] {
              for size in [1, 5] {
                var options = ColorMatchOptions()
                options.sampleSize = size
                options.tolerance = size == 1 ? 0 : 43
                options.antiAlias = antiAlias
                options.contiguous = contiguous
                let seed = PathPoint(63.5, 62.5)
                let dense = try ColorRegion.selection(source: source, width: width, height: height,
                  seed: seed, options: options, mask: mask)
                let paged = try ColorRegion.selection(source: source, width: width, height: height,
                  seed: seed, options: options, mask: mask, densePixelLimit: 0)
                XCTAssertEqual(try dense.bytes, try paged.bytes,
                  "\(depth), \(transform), \(mask), \(contiguous), \(antiAlias), \(size)")
                XCTAssertEqual(dense.bounds, paged.bounds)
              }
            }
          }
        }
      }
    }
  }

  func testMaximumSparseForegroundAndBackgroundSelectionAndLocalBucketFill() throws {
    let side = Surface.maxDimension
    let x = side - 36, y = side - 32
    var source = try Surface(width: side, height: side, fill: .black)
    for dy in 0..<4 {
      for dx in 0..<4 { source.setPixel(x: x + dx, y: y + dy, .white) }
    }
    source.setPixel(x: 16, y: 12, .white)
    let sampling = CloneSample(surface: source)
    var options = ColorMatchOptions()
    options.tolerance = 0
    let connected = try ColorRegion.selection(source: sampling, width: side, height: side,
      seed: .init(Double(x) + 1.5, Double(y) + 1.5), options: options)
    XCTAssertTrue(connected.isPaged)
    XCTAssertEqual(connected.bounds, IntRect(x: x - 1, y: y - 1, width: 6, height: 6))
    XCTAssertEqual(connected.coverage(x: x + 1, y: y + 1), 1)
    XCTAssertEqual(connected.coverage(x: x, y: y), 184.0 / 255.0)
    XCTAssertEqual(connected.coverage(x: x - 1, y: y + 1), 43.0 / 255.0)
    XCTAssertEqual(connected.coverage(x: 16, y: 12), 0)

    options.contiguous = false
    let disconnected = try ColorRegion.selection(source: sampling, width: side, height: side,
      seed: .init(16.5, 12.5), options: options)
    XCTAssertEqual(disconnected.coverage(x: x + 1, y: y + 1), 1)
    XCTAssertEqual(disconnected.coverage(x: 16, y: 12), 142.0 / 255.0)
    XCTAssertLessThan(disconnected.mappedBytes, 20 * TileArchive.byteCount)
    let background = try ColorRegion.selection(source: sampling, width: side, height: side,
      seed: .init(0.5, 0.5), options: options)
    XCTAssertEqual(background.bounds, IntRect(x: 0, y: 0, width: side, height: side))
    XCTAssertEqual(try background.coverageSurface().defaultPixel, .white)
    XCTAssertEqual(background.coverage(x: x + 1, y: y + 1), 0)
    XCTAssertEqual(background.coverage(x: x - 1, y: y + 1), 213.0 / 255.0)
    XCTAssertLessThan(background.mappedBytes, 20 * TileArchive.byteCount)

    var bucket = BucketOptions()
    options.contiguous = true; options.antiAlias = false
    bucket.match = options
    var layer = Layer(name: "Pixels", content: .raster(source))
    let color = Pixel(1, 0, 0)
    let fill = BucketFill(source: sampling, seed: .init(Double(x), Double(y)), color: color, options: bucket)
    XCTAssertTrue(try BucketPainter.paint(fill, on: &layer, canvasWidth: side, canvasHeight: side))
    guard case .raster(let filled) = layer.content else { return XCTFail("Expected raster") }
    XCTAssertEqual(filled.pixel(x: x, y: y), color)
    XCTAssertEqual(filled.pixel(x: 16, y: 12), .white)
    XCTAssertEqual(filled.pixel(x: 0, y: 0), .black)
  }

  func testMaximumUniformSelectionAndOpaqueBucketUseImplicitSamples() throws {
    let side = Surface.maxDimension
    for depth in PixelDepth.allCases {
      let storage = try Surface(width: side, height: side, depth: depth, fill: .black,
        colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      let sample = CloneSample(surface: storage)
      let selection = try ColorRegion.selection(source: sample, width: side, height: side,
        seed: .init(Double(side) - 0.5, Double(side) - 0.5), options: .init())
      XCTAssertTrue(try selection.isFullCoverage)
      XCTAssertEqual(try selection.coverageSurface().tileCount, 0)
      XCTAssertEqual(selection.mappedBytes, 0)
      let outside = try ColorRegion.selection(source: sample, width: side, height: side,
        seed: .init(-1, 0), options: .init())
      XCTAssertNil(outside.bounds)
      XCTAssertEqual(try outside.coverageSurface().tileCount, 0)

      var layer = Layer(name: "Pixels", content: .raster(storage))
      let ink = Pixel(0.9, 0.72, 0.31)
      let fill = BucketFill(source: sample, seed: .init(1, 1), color: ink)
      XCTAssertTrue(try BucketPainter.paint(fill, on: &layer, canvasWidth: side, canvasHeight: side))
      guard case .raster(let raster) = layer.content else { return XCTFail("Expected raster") }
      var oracle = try Surface(width: 1, height: 1, depth: depth, colorEncoding: storage.colorEncoding)
      oracle.setPixel(x: 0, y: 0, ink)
      XCTAssertEqual(raster.defaultPixel, oracle.pixel(x: 0, y: 0))
      XCTAssertEqual(raster.pixel(x: side - 1, y: side - 1), raster.defaultPixel)
      XCTAssertEqual(raster.tileCount, 0)
      XCTAssertFalse(try BucketPainter.paint(fill, on: &layer, canvasWidth: side, canvasHeight: side))
    }
  }

  func testColorRegionScratchEvictsDirtyBitsAndSpillsWorkInOrder() throws {
    let marks = try ColorRegionMarks()
    let pageSpan = 16_384 * 8
    for i in 0..<34 {
      let anchor = i * pageSpan + 3
      try marks.insert(anchor...(anchor + 11))
    }
    try marks.insert((pageSpan * 66 - 2)...(pageSpan * 66 + 4))
    for i in (0..<34).reversed() {
      let anchor = i * pageSpan + 3
      XCTAssertFalse(try marks.contains(anchor - 1))
      XCTAssertTrue(try marks.contains(anchor))
      XCTAssertTrue(try marks.contains(anchor + 11))
      XCTAssertFalse(try marks.contains(anchor + 12))
    }
    XCTAssertTrue(try marks.contains(pageSpan * 66 - 2))
    XCTAssertTrue(try marks.contains(pageSpan * 66 + 4))
    XCTAssertFalse(try marks.contains(pageSpan * 66 + 5))
    let work = try ColorRegionWorklist(seed: 70_000_000_000)
    for i in 1...9_000 { try work.push(70_000_000_000 + i) }
    for i in (0...9_000).reversed() { XCTAssertEqual(try work.pop(), 70_000_000_000 + i) }
    XCTAssertNil(try work.pop())
  }

  func testBucketClearExactSelectionAndPatternAlphaAndProtectedTargets() throws {
    for depth in [PixelDepth.u8, .u16] {
      let base = Pixel(1, 0.5, 0.25, 0.8)
      let source = try Surface(width: 8, height: 4, depth: depth, fill: base)
      let selection = try SelectionMask(width: 8, height: 4,
        bytes: (0..<32).map { $0 % 8 == 0 ? 128 : ($0 % 8 < 3 ? 255 : 0) })
      var layer = Layer(name: "Editable", content: .raster(source))
      var options = BucketOptions(); options.clearsAlpha = true; options.opacity = 0.5
      var request = BucketFill(source: CloneSample(surface: source), seed: .init(0.5, 1.5),
        color: .clear, options: options)
      XCTAssertTrue(try BucketPainter.paint(request, on: &layer,
        canvasWidth: 8, canvasHeight: 4, selectionMask: selection))
      guard case .raster(let cleared) = layer.content else { return XCTFail("Expected raster") }
      var expected = source, value = source.defaultPixel
      value.a *= 1 - (Float(128)/255 * 0.5)
      expected.setPixel(x: 0, y: 1, value)
      XCTAssertEqual(cleared.pixel(x: 0, y: 1), expected.pixel(x: 0, y: 1))
      XCTAssertEqual(cleared.pixel(x: 7, y: 1), source.defaultPixel)
      XCTAssertEqual(cleared.pixel(x: 2, y: 1).a, 0.4, accuracy: 1/255)

      var texture = try Surface(width: 2, height: 1, depth: depth, fill: .white)
      texture.setPixel(x: 1, y: 0, .clear)
      request.options.opacity = 1
      request.pattern = try RasterPattern(name: "Opaque then transparent", surface: texture, id: "bucket-alpha")
      layer.content = .raster(source)
      XCTAssertTrue(try BucketPainter.paint(request, on: &layer, canvasWidth: 8, canvasHeight: 4))
      guard case .raster(let patterned) = layer.content else { return XCTFail("Expected raster") }
      XCTAssertEqual(patterned.pixel(x: 0, y: 1), .clear)
      XCTAssertEqual(patterned.pixel(x: 1, y: 1), source.defaultPixel)
      layer.content = .raster(source)
      layer.protection = .transparency
      let locked = layer
      XCTAssertThrowsError(try BucketPainter.paint(request, on: &layer, canvasWidth: 8, canvasHeight: 4))
      XCTAssertEqual(layer, locked)
      layer.protection = []
      layer.mask = source; request.mask = true
      XCTAssertThrowsError(try BucketPainter.paint(request, on: &layer, canvasWidth: 8, canvasHeight: 4))
      XCTAssertEqual(layer.mask, source)
    }
  }

  func testBucketMaximumSparseSeparatedPatternAndFullPartialClears() throws {
    let side = Surface.maxDimension
    var storage = try Surface(width: side, height: side, depth: .u16, fill: .black)
    let near = 128, far = side - 47
    storage.setPixel(x: near, y: near, .white)
    storage.setPixel(x: far, y: far, .white)
    let pattern = try RasterPattern(name: "Quarter alpha",
      surface: Surface(width: 1, height: 1, depth: .u16, fill: Pixel(1, 0, 0, 0.25)),
      id: "bucket-quarter")
    var options = BucketOptions()
    options.match.tolerance = 0; options.match.contiguous = false; options.match.antiAlias = false
    options.clearsAlpha = true
    var layer = Layer(name: "Large", content: .raster(storage))
    let separated = BucketFill(source: CloneSample(surface: storage), seed: .init(Double(near), Double(near)),
      color: .clear, options: options, pattern: pattern)
    XCTAssertTrue(try BucketPainter.paint(separated, on: &layer, canvasWidth: side, canvasHeight: side))
    guard case .raster(let sprayed) = layer.content else { return XCTFail("Expected raster") }
    XCTAssertEqual(sprayed.pixel(x: near, y: near).a, 0.75, accuracy: 1 / 65_535)
    XCTAssertEqual(sprayed.pixel(x: far, y: far).a, 0.75, accuracy: 1 / 65_535)
    XCTAssertEqual(sprayed.pixel(x: side / 2, y: side / 2), .black)
    XCTAssertEqual(sprayed.tileCount, 2)

    options.match.tolerance = 255; options.opacity = 0.5
    var cleared = BucketFill(source: CloneSample(surface: storage), seed: .init(0.5, 0.5),
      color: .clear, options: options)
    layer.content = .raster(storage)
    XCTAssertTrue(try BucketPainter.paint(cleared, on: &layer, canvasWidth: side, canvasHeight: side))
    guard case .raster(let half) = layer.content else { return XCTFail("Expected raster") }
    XCTAssertEqual(half.defaultPixel.a, 0.5, accuracy: 1 / 65_535)
    XCTAssertEqual(half.pixel(x: far, y: far).r, 1)
    XCTAssertEqual(half.tileCount, 2)
    cleared.options.opacity = 1
    XCTAssertTrue(try BucketPainter.paint(cleared, on: &layer, canvasWidth: side, canvasHeight: side))
    guard case .raster(let full) = layer.content else { return XCTFail("Expected raster") }
    XCTAssertEqual(full.defaultPixel, .clear)
    XCTAssertEqual(full.tileCount, 0)

    cleared.options.clearsAlpha = false
    cleared.color = Pixel(1, 0, 0)
    cleared.options.opacity = 0.25
    layer.content = .raster(storage)
    XCTAssertTrue(try BucketPainter.paint(cleared, on: &layer, canvasWidth: side, canvasHeight: side))
    guard case .raster(let painted) = layer.content else { return XCTFail("Expected raster") }
    XCTAssertEqual(painted.defaultPixel.r, 0.25, accuracy: 1 / 65_535)
    XCTAssertEqual(painted.pixel(x: near, y: near).g, 0.75, accuracy: 1 / 65_535)
    XCTAssertEqual(painted.tileCount, 2)
  }

  func testOriginalRustSpanFloodAndAntialiasOracle() throws {
    let data = try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "color-region-oracle", withExtension: "bin", subdirectory: "Fixtures")))
    var offset = 0
    var cases = 0
    var count = 0
    func u() -> Int {
      defer { offset += 4 }
      return (0..<4).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
    }
    while offset < data.count {
      let w = u()
      let h = u()
      let sx = u()
      let sy = u()
      var options = ColorMatchOptions()
      options.tolerance = u()
      options.contiguous = u() == 1
      options.antiAlias = u() == 1
      let pixels = (0..<w * h).map { _ -> SIMD4<UInt8> in
        defer { offset += 4 }
        return SIMD4(data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
      }
      let expected = Array(data[offset..<offset + w * h])
      offset += w * h
      let actual = try ColorRegion.selection(
        pixels: pixels, width: w, height: h,
        seedX: sx, seedY: sy, options: options)
      XCTAssertEqual(try actual.bytes, expected, "Rust reference case \(cases)")
      count += w * h
      cases += 1
    }
    XCTAssertEqual(cases, 240)
    XCTAssertEqual(count, 66_096)
    print("Color region Rust oracle: \(cases) cases; \(count) exact coverage bytes")
  }

  func testConnectivityToleranceAlphaAndHiddenColorAreIndependent() throws {
    let r = SIMD4<UInt8>(100, 120, 140, 255)
    let pixels = [
      r, SIMD4(100, 120, 140, 0), r,
      SIMD4(132, 120, 140, 255), r, SIMD4(133, 120, 140, 255),
    ]
    var o = ColorMatchOptions()
    o.antiAlias = false
    o.tolerance = 31
    func run() throws -> [UInt8] {
      try ColorRegion.selection(pixels: pixels, width: 3, height: 2, seedX: 0, seedY: 0, options: o)
        .bytes
    }
    XCTAssertEqual(try run(), [255, 0, 0, 0, 0, 0])
    o.tolerance = 32
    XCTAssertEqual(try run(), [255, 0, 0, 255, 255, 0])
    o.contiguous = false
    XCTAssertEqual(try run(), [255, 0, 255, 255, 255, 0])
    o.tolerance = 255
    XCTAssertEqual(try run(), [255, 255, 255, 255, 255, 255])
  }

  func testHighDepthSamplingQuantizesToEightBitsAndHonorsTransformsAndMaskOutside() throws {
    for depth in PixelDepth.allCases {
      var s = try Surface(width: 2, height: 1, depth: depth, fill: Pixel(100.0 / 255, 0, 0))
      s.setPixel(x: 1, y: 0, Pixel(100.0 / 255 + 0.0001, 0, 0))
      let source = CloneSample(surface: s, transform: .translation(2, 1))
      var o = ColorMatchOptions()
      o.tolerance = 0
      o.antiAlias = false
      let result = try ColorRegion.selection(
        source: source, width: 6, height: 3,
        seed: .init(2.9, 1.1), options: o)
      XCTAssertEqual(result.bounds, IntRect(x: 2, y: 1, width: 2, height: 1))
      let mask = CloneSample(
        surface: try Surface(width: 1, height: 1, depth: depth, fill: .black),
        transform: .translation(2, 1), outside: .white)
      let coverage = try ColorRegion.selection(
        source: mask, width: 6, height: 3,
        seed: .init(0.5, 0.5), options: o, mask: true)
      XCTAssertEqual(try coverage.bytes.filter { $0 == 255 }.count, 17)
      XCTAssertEqual(coverage.coverage(x: 2, y: 1), 0)
    }
  }

  func testWandCombinationUsesFullCanvasAndRoundTripsWithUndo() throws {
    var d = try CraftDocument(width: 5, height: 1)
    var source = try Surface(width: 5, height: 1, fill: .black)
    for x in [0, 1, 4] { source.setPixel(x: x, y: 0, .white) }
    var o = ColorMatchOptions()
    o.antiAlias = false
    var session = EditorSession(document: d)
    let sample = CloneSample(surface: source)
    try session.execute(.magicWand(sample, .init(0, 0), o, .replace, false))
    XCTAssertEqual(try session.document.selectionMask?.bytes, [255, 255, 0, 0, 0])
    try session.execute(.magicWand(sample, .init(4, 0), o, .add, false))
    XCTAssertEqual(try session.document.selectionMask?.bytes, [255, 255, 0, 0, 255])
    try session.execute(.magicWand(sample, .init(0, 0), o, .subtract, false))
    XCTAssertEqual(try session.document.selectionMask?.bytes, [0, 0, 0, 0, 255])
    d = session.document
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
    try session.execute(.magicWand(sample, .init(0, 0), o, .intersect, false))
    XCTAssertNil(session.document.selection)
    try session.undo()
    XCTAssertEqual(session.document, d)
    try session.redo()
    XCTAssertNil(session.document.selection)
  }

  func testTransformedFloatMaskInterpolatesCoverageWithoutGamma() throws {
    var mask = try Surface(width: 3, height: 1, depth: .f32, fill: .black)
    mask.setPixel(x: 1, y: 0, .white)
    mask.setPixel(x: 2, y: 0, Pixel(0.5, 0.5, 0.5))
    let source = CloneSample(
      surface: mask, transform: .translation(0.5, 0),
      outside: Pixel(0.5, 0.5, 0.5))
    var options = ColorMatchOptions()
    options.antiAlias = false
    options.contiguous = false
    options.tolerance = 0
    let selected = try ColorRegion.selection(
      source: source, width: 4, height: 1,
      seed: .init(1.5, 0.5), options: options, mask: true)
    XCTAssertEqual(try selected.bytes, [0, 255, 0, 255])
  }

  func testInvalidAndOutsideSeedsAndCancellationDoNotModifyDocument() async throws {
    let sample = CloneSample(surface: try Surface(width: 4, height: 3, fill: .white))
    var o = ColorMatchOptions()
    XCTAssertNil(
      try ColorRegion.selection(
        source: sample, width: 4, height: 3,
        seed: .init(-1, 0), options: o
      ).bounds)
    o.tolerance = 256
    XCTAssertThrowsError(
      try ColorRegion.selection(
        source: sample, width: 4, height: 3,
        seed: .init(0, 0), options: o))
    o.tolerance = 0
    XCTAssertThrowsError(
      try ColorRegion.selection(
        source: sample, width: 4, height: 3,
        seed: .init(.nan, 0), options: o))
    let d = try CraftDocument(width: 4, height: 3)
    let task = Task.detached {
      var copy = d
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        try Command.magicWand(sample, .init(0, 0), ColorMatchOptions(), .replace, false).apply(
          to: &copy)
        XCTFail("Expected cancellation")
      } catch is CancellationError {} catch { XCTFail("\(error)") }
      XCTAssertEqual(copy, d)
    }
    await task.value
  }
}
