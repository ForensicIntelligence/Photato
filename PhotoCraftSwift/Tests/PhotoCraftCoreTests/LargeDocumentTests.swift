import Foundation
import XCTest
@testable import PhotoCraftCore

final class LargeDocumentTests: XCTestCase {
  func testPhotoshopMaximumExtentSparseCornersAndCopyOnWrite() throws {
    XCTAssertEqual(Surface.maxDimension, 300_000)
    XCTAssertEqual(Surface.maxPixels, 90_000_000_000)
    for depth in PixelDepth.allCases {
      var source = try Surface(width: 300_000, height: 300_000, depth: depth, fill: .white)
      XCTAssertEqual(source.allocatedBytes, 0)
      XCTAssertEqual(try source.contentBounds(), IntRect(x: 0, y: 0, width: 300_000, height: 300_000))
      source.setPixel(x: 0, y: 0, .black)
      source.setPixel(x: 299_999, y: 299_999, Pixel(1, 0, 0))
      var copy = source; copy.setPixel(x: 299_999, y: 299_999, .clear)
      XCTAssertEqual(source.pixel(x: 299_999, y: 299_999), Pixel(1, 0, 0))
      XCTAssertEqual(copy.pixel(x: 299_999, y: 299_999), .clear)
      XCTAssertEqual(source.tileCount, 2); XCTAssertEqual(source.allocatedBytes, 131_072)
      try source.validated(); try copy.validated()
      XCTAssertEqual(try source.contentBounds(), IntRect(x: 0, y: 0, width: 300_000, height: 300_000))
      XCTAssertThrowsError(try source.rgbaData(depth: .u8))
    }
    for (w,h) in [(300_001,1),(1,300_001),(Int.max,1),(1,Int.max),(0,1)] {
      XCTAssertThrowsError(try Surface(width: w, height: h))
    }
  }
  func testMaximumSizeBrushUndoAndFileRoundTripRetainFarEdgeSamples() throws {
    for depth in PixelDepth.allCases {
      let document = try DocumentCreation.blank(width: 300_000, height: 300_000, depth: depth, mode: .rgb)
      XCTAssertEqual(document.colorMode, .rgb); XCTAssertLessThan(document.estimatedBytes, 65_536)
      var session = EditorSession(document: document)
      var brush = Brush(); brush.size = 9; brush.color = Pixel(0.9, 0.1, 0.2); brush.settings = .init()
      try session.execute(.stroke(document.layers[0].id, [.init(x: 299_994, y: 299_994), .init(x: 299_999, y: 299_999)], brush))
      let painted = session.document; XCTAssertNotEqual(painted, document)
      XCTAssertThrowsError(try session.execute(.clear(document.layers[0].id)))
      XCTAssertEqual(session.document,painted,"Unsupported dense work cannot mutate a large document")
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo(); XCTAssertEqual(session.document, document)
      try session.redo(); XCTAssertEqual(session.document, painted)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".photato")
      defer { try? FileManager.default.removeItem(at: url) }
      try NativeArchive.write(painted, to: url)
      XCTAssertLessThan(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize!, 300_000)
      XCTAssertEqual(try NativeArchive.read(url), painted)
    }
  }
  func testFractionalAreaPreviewAgainstIndependentDenseIntegral() throws {
    var source = try Surface(width: 7, height: 5, depth: .f32, fill: Pixel(0.1, 0.4, 0.8, 0.3))
    source.setPixel(x: 3, y: 2, Pixel(0.9, 0.2, 0.1, 0.8))
    source.setPixel(x: 6, y: 4, .clear)
    let output = try source.reducedPreview(in: .init(x: 1, y: 0, width: 6, height: 5), width: 4, height: 3)
    for y in 0..<3 { for x in 0..<4 {
      let l = 1 + Double(x) * 1.5, r = l + 1.5, t = Double(y) * 5 / 3, b = Double(y + 1) * 5 / 3
      var sum = SIMD4<Double>.zero
      for sy in 0..<5 { for sx in 0..<7 {
        let weight = max(0, min(r, Double(sx + 1)) - max(l, Double(sx))) * max(0, min(b, Double(sy + 1)) - max(t, Double(sy)))
        let p = source.pixel(x: sx, y: sy)
        sum += SIMD4(Double(p.r) * Double(p.a), Double(p.g) * Double(p.a), Double(p.b) * Double(p.a), Double(p.a)) * weight
      } }
      let actual = output.pixel(x: x, y: y)
      XCTAssertEqual(Double(actual.r), sum.x / sum.w, accuracy: 1e-6)
      XCTAssertEqual(Double(actual.g), sum.y / sum.w, accuracy: 1e-6)
      XCTAssertEqual(Double(actual.b), sum.z / sum.w, accuracy: 1e-6)
      XCTAssertEqual(Double(actual.a), sum.w / 2.5, accuracy: 1e-6)
    } }
  }
  func testLargeReductionIncludesImplicitPixelsAndPartialBoundaryTiles() throws {
    var source = try Surface(width: 300_000, height: 300_000, depth: .f32, fill: .white)
    source.setPixel(x: 299_999, y: 299_999, .black)
    let patch = try source.reducedPreview(in: .init(x: 299_998, y: 299_998, width: 2, height: 2), width: 1, height: 1)
    XCTAssertEqual(patch.pixel(x: 0, y: 0), Pixel(0.75, 0.75, 0.75))
    let overview = try source.reducedPreview(in: .init(x: 0, y: 0, width: 300_000, height: 300_000), width: 64, height: 64)
    XCTAssertEqual(overview.width, 64); XCTAssertEqual(source.tileCount, 1)
    XCTAssertThrowsError(try source.reducedPreview(in: .init(x: 0, y: 0, width: 300_000, height: 300_000), width: 3000, height: 3000))
    XCTAssertThrowsError(try SelectionMask.make(.rectangle(.init(x: 0, y: 0, width: 20, height: 20)), width: 300_000, height: 300_000))
  }
  func testOpaqueBoundsUseMissingTilesAndIgnorePadding() throws {
    var s = try Surface(width: 65, height: 65, fill: .white)
    try s.mapPixels(in: .init(x: 0, y: 0, width: 65, height: 1)) { _,_,_ in .clear }
    XCTAssertEqual(try s.contentBounds(), .init(x: 0, y: 1, width: 65, height: 64))
    XCTAssertFalse(try s.allStoredSamplesSatisfy { $0.a == 1 })
    let one = try Surface(width: 1, height: 1, fill: .white)
    XCTAssertTrue(try one.allStoredSamplesSatisfy { $0.a == 1 })
  }
}
