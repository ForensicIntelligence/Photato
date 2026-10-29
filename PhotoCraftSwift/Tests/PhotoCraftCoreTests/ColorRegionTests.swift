import Foundation
import XCTest

@testable import PhotoCraftCore

final class ColorRegionTests: XCTestCase {
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
      XCTAssertEqual(actual.bytes, expected, "Rust reference case \(cases)")
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
      XCTAssertEqual(coverage.bytes.filter { $0 == 255 }.count, 17)
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
    XCTAssertEqual(session.document.selectionMask?.bytes, [255, 255, 0, 0, 0])
    try session.execute(.magicWand(sample, .init(4, 0), o, .add, false))
    XCTAssertEqual(session.document.selectionMask?.bytes, [255, 255, 0, 0, 255])
    try session.execute(.magicWand(sample, .init(0, 0), o, .subtract, false))
    XCTAssertEqual(session.document.selectionMask?.bytes, [0, 0, 0, 0, 255])
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
    XCTAssertEqual(selected.bytes, [0, 255, 0, 255])
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
