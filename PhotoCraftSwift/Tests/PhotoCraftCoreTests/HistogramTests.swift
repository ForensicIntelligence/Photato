import Foundation
import XCTest

@testable import PhotoCraftCore

final class HistogramTests: XCTestCase {
  struct Vector: Decodable {
    let caseIndex: Int
    let kind: String
    let samples: UInt64
    let channels: [[UInt64]]
    let underflow, overflow, shadows, highlights: [UInt64]
    let records: [[Float]]
  }
  func inputs(_ index: Int) -> [Pixel] {
    switch index {
    case 0: return []
    case 1: return (0..<256).map { Pixel(Float($0) / 255, Float(255 - $0) / 255, 0.5, 0.25) }
    case 2:
      return (0..<2000).map { i in
        if i == 0 { return .black }
        if i == 1999 { return .white }
        return Pixel(Float(40 + i % 120) / 255, Float(60 + i % 90) / 255, Float(80 + i % 100) / 255)
      }
    case 3: return [Pixel(0.0001, 0.9999, 0.5), Pixel(-0.2, 1, 0), Pixel(0.9, 0.1, 0.7, 0)]
    default: return Array(repeating: Pixel(0.3, 0.4, 0.5), count: 100)
    }
  }
  func testOriginalRustHistogramAndAutomaticCorrectionOracles() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "histogram-oracle", withExtension: "json", subdirectory: "Fixtures"))
    let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    XCTAssertEqual(vectors.count, 15)
    for v in vectors {
      var h = RGBHistogram()
      for pixel in inputs(v.caseIndex) { h.add(pixel) }
      XCTAssertEqual(h.samples, v.samples)
      XCTAssertEqual(h.channels, v.channels)
      XCTAssertEqual(h.underflow, v.underflow)
      XCTAssertEqual(h.overflow, v.overflow)
      XCTAssertEqual(h.shadows, v.shadows)
      XCTAssertEqual(h.highlights, v.highlights)
      let kind: AutoCorrection = v.kind == "tone" ? .tone : v.kind == "color" ? .color : .contrast
      let result = try kind.levels(from: h)
      for (i, channel) in [result.red, result.green, result.blue].enumerated() {
        XCTAssertEqual(channel.inputBlack, min(253, Int(v.records[i][0])))
        XCTAssertEqual(channel.inputWhite, max(2, Int(v.records[i][1])))
        XCTAssertEqual(channel.gamma, v.records[i][2], accuracy: 0.000003)
      }
    }
  }
  func testInvalidTransparentAndExactClipping() throws {
    var h = RGBHistogram()
    for p in [
      Pixel(.nan, 0, 0), Pixel(0, .infinity, 0), Pixel(0, 0, 0, .nan),
      Pixel(0.5, 0.6, 0.7, 0), Pixel(-2, 4, 0.5),
    ] { h.add(p) }
    XCTAssertEqual(h.invalid, 3)
    XCTAssertEqual(h.transparent, 1)
    XCTAssertEqual(h.samples, 1)
    XCTAssertEqual(h.underflow, [1, 0, 0])
    XCTAssertEqual(h.overflow, [0, 1, 0])
    XCTAssertEqual(h.bins(.rgb).reduce(0, +), 3)
    for bad in [-1.0, 10, .nan, .infinity] {
      XCTAssertThrowsError(try AutoCorrection.tone.levels(from: h, shadowClip: bad))
      XCTAssertThrowsError(try AutoCorrection.tone.levels(from: h, highlightClip: bad))
    }
  }
  func testHistogramHonorsSelectionHolesTransformsAndDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 5, height: 1, depth: depth)
      var s = try Surface(width: 4, height: 1, depth: depth)
      for x in 0..<4 { s.setPixel(x: x, y: 0, Pixel(Float(x + 1) / 5, 0.5, 0.6)) }
      d.layers[0].content = .raster(s)
      d.layers[0].x = 1
      try Command.selectionCoverage(
        SelectionMask(width: 5, height: 1, bytes: [0, 255, 0, 255, 0]), .replace
      ).apply(to: &d)
      let h = try RGBHistogram.pixelLayer(d.layers[0].id, in: d)
      XCTAssertEqual(h.samples, 2)
      for x in [0, 2] {
        let p = s.pixel(x: x, y: 0)
        let value = depth == .f32 ? SRGBTransfer.linear(p.r) : p.r
        XCTAssertEqual(h.channels[0][Int(unit(value) * 255 + 0.5)], 1)
      }
    }
  }
  func testAutoCommandsAreAtomicUndoableAndSelectionScoped() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 4, height: 1, depth: depth)
      var s = try Surface(width: 4, height: 1, depth: depth)
      for x in 0..<4 { s.setPixel(x: x, y: 0, Pixel(Float(x + 1) / 6, 0.3, 0.6, 0.5)) }
      d.layers[0].content = .raster(s)
      d.selection = IntRect(x: 1, y: 0, width: 2, height: 1)
      for kind in AutoCorrection.allCases {
        var session = EditorSession(document: d)
        try session.execute(.autoCorrection(d.layers[0].id, kind))
        guard case .raster(let changed) = session.document.layers[0].content else {
          return XCTFail()
        }
        XCTAssertEqual(changed.pixel(x: 0, y: 0), s.pixel(x: 0, y: 0))
        XCTAssertEqual(changed.pixel(x: 3, y: 0), s.pixel(x: 3, y: 0))
        XCTAssertEqual(changed.pixel(x: 1, y: 0).a, s.pixel(x: 1, y: 0).a)
        XCTAssertEqual(session.undoStack.last?.label, kind.rawValue)
        try session.undo()
        XCTAssertEqual(session.document, d)
      }
      d.layers[0].locked = true
      var session = EditorSession(document: d)
      XCTAssertThrowsError(try session.execute(.autoCorrection(d.layers[0].id, .tone)))
      XCTAssertEqual(session.document, d)
    }
  }
}
