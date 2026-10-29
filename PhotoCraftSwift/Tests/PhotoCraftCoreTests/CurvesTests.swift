import Foundation
import XCTest

@testable import PhotoCraftCore

final class CurvesTests: XCTestCase {
  struct Vector: Decodable {
    let points: [[Int]]
    let table: [Float]
    let combined: [Float]
    let combinedTable: [Float]
  }
  func testIndependentRustSplineOracleAndComponentBeforeComposite() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "curves-oracle", withExtension: "json", subdirectory: "Fixtures"))
    let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    XCTAssertEqual(vectors.count, 9)
    let master = CurveChannel([.init(0, 0), .init(55, 20), .init(200, 240), .init(255, 255)])
    for v in vectors {
      let channel = CurveChannel(v.points.map { .init($0[0], $0[1]) })
      let table = channel.table()
      XCTAssertEqual(table.count, 4096)
      for i in table.indices {
        XCTAssertEqual(table[i], v.table[i], accuracy: 0.0000003, "Spline sample \(i)")
      }
      for depth in PixelDepth.allCases {
        let transfer = CurvesTransfer(.init(rgb: master, red: channel), depth: depth)
        for i in v.combinedTable.indices {
          XCTAssertEqual(transfer.tables[0][i], v.combinedTable[i], accuracy: 0.0000003)
        }
        for i in v.combined.indices {
          let input = Float(i - 1) / 255
          let sample = depth == .f32 ? SRGBTransfer.encoded(input) : input
          let actual = transfer.apply(Pixel(sample, 0.3, 0.6, 0.37))
          // Native float storage has passed through encode/decode. Very steep
          // curves amplify that rounding, so sample the independent Rust table
          // at the actual linear input, not its pre-encoding ideal coordinate.
          let expected: Float
          if depth == .f32 {
            let linear = SRGBTransfer.linear(sample)
            XCTAssertEqual(linear, input, accuracy: 0.0000003)
            let x = min(1, max(0, linear)) * 4095
            let j = Int(x)
            let t = x - Float(j)
            expected = SRGBTransfer.encoded(
              v.combinedTable[j] * (1 - t) + v.combinedTable[min(j + 1, 4095)] * t)
          } else {
            expected = v.combined[i]
          }
          XCTAssertEqual(actual.r, expected, accuracy: 0.000003, "\(depth) sample \(i)")
          XCTAssertEqual(actual.a.bitPattern, Float(0.37).bitPattern)
        }
      }
    }
  }
  func testIdentityHiddenColorsAndUnchangedComponentsRetainBits() {
    let samples = [Pixel(-0.0, 0.37, 2, 0.5), Pixel(-0.3, 1.5, 0.4, 0)]
    let reversed = CurveChannel([.init(0, 255), .init(255, 0)])
    for depth in PixelDepth.allCases {
      for p in samples {
        let identity = CurvesTransfer(.init(), depth: depth).apply(p)
        XCTAssertEqual(identity, p)
        XCTAssertEqual(identity.r.bitPattern, p.r.bitPattern)
        let edited = CurvesTransfer(.init(red: reversed), depth: depth).apply(p)
        XCTAssertEqual(edited.g.bitPattern, p.g.bitPattern)
        XCTAssertEqual(edited.b.bitPattern, p.b.bitPattern)
        XCTAssertEqual(edited.a.bitPattern, p.a.bitPattern)
        if p.a == 0 { XCTAssertEqual(edited.r.bitPattern, p.r.bitPattern) }
      }
    }
    let transfer = CurvesTransfer(.init(red: reversed), depth: .f32)
    XCTAssertEqual(transfer.apply(Pixel(.greatestFiniteMagnitude, 0.3, 0.4)).r, 0)
    XCTAssertEqual(transfer.apply(Pixel(-2, 0.3, 0.4)).r, 1, accuracy: 0.000001)
  }
  func testValidationPointEditingAndLimits() throws {
    for points: [CurvePoint] in [
      [], [.init(0, 0)], [.init(0, 0), .init(0, 255)],
      [.init(1, 0), .init(0, 255)], [.init(-1, 0), .init(255, 255)],
      [.init(0, 0), .init(255, 256)], (0..<20).map { .init($0, $0) },
    ] {
      XCTAssertThrowsError(try CurvesAdjustment(red: .init(points)).validate())
    }
    var curve = CurveChannel()
    let index = try curve.insert(.init(100, 140))
    XCTAssertEqual(index, 1)
    XCTAssertEqual(try curve.insert(.init(100, 200)), 1)
    XCTAssertEqual(curve.points[1].output, 140)
    curve.move(index, to: .init(300, -20))
    XCTAssertEqual(curve.points[1], .init(254, 0))
    curve.move(0, to: .init(300, 200))
    XCTAssertEqual(curve.points[0], .init(253, 200))
    curve.remove(1)
    curve.remove(0)
    XCTAssertEqual(curve.points.count, 2)
    try curve.validate()
    var full = CurveChannel((0..<19).map { .init($0 * 10, $0 * 10) })
    XCTAssertThrowsError(try full.insert(.init(255, 255)))
    XCTAssertThrowsError(try full.insert(.init(256, 255)))
  }
  func testSelectionAlphaUndoNativeStorageAndFailedEditAreAtomic() throws {
    let curves = CurvesAdjustment(red: .init([.init(0, 255), .init(255, 0)]))
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 4, height: 1, depth: depth)
      let original = try Surface(width: 4, height: 1, depth: depth, fill: Pixel(0.3, 0.4, 0.6, 0.5))
      d.layers[0].content = .raster(original)
      d.layers[0].x = 1
      try Command.selectionCoverage(
        SelectionMask(width: 4, height: 1, bytes: [0, 255, 128, 0]), .replace
      ).apply(to: &d)
      var session = EditorSession(document: d)
      try session.execute(.applyAdjustment(d.layers[0].id, .curves(curves)))
      guard case .raster(let result) = session.document.layers[0].content else { return XCTFail() }
      let p = original.pixel(x: 0, y: 0)
      let changed = CurvesTransfer(curves, depth: depth).apply(p)
      XCTAssertEqual(result.pixel(x: 0, y: 0), changed.quantized(depth))
      XCTAssertEqual(
        result.pixel(x: 1, y: 0),
        LevelsTransfer.mix(p, with: changed, coverage: 128.0 / 255, depth: depth).quantized(depth))
      XCTAssertEqual(result.pixel(x: 2, y: 0), p)
      XCTAssertEqual(result.pixel(x: 3, y: 0), p)
      try session.undo()
      XCTAssertEqual(session.document, d)
      try session.execute(.addLayer(Layer(name: "Curves", content: .adjustment(.curves(curves)))))
      XCTAssertEqual(
        try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
      let before = session.document
      let count = session.undoStack.count
      XCTAssertThrowsError(
        try session.execute(.applyAdjustment(d.layers[0].id, .curves(.init(red: .init([]))))))
      XCTAssertEqual(session.document, before)
      XCTAssertEqual(session.undoStack.count, count)
      try session.execute(.lock(d.layers[0].id, true))
      XCTAssertThrowsError(try session.execute(.applyAdjustment(d.layers[0].id, .curves(curves))))
    }
  }
}
