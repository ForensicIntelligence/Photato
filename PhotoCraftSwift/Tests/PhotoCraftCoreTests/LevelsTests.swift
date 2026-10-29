import Foundation
import XCTest

@testable import PhotoCraftCore

final class LevelsTests: XCTestCase {
  struct Vector: Decodable {
    let caseIndex: Int
    let parameters: [Int]
    let depth: Int
    let input: Float
    let channel: Float
    let combined: Float
  }
  func testIndependentRustOracleAndChannelOrder() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "levels-oracle", withExtension: "json", subdirectory: "Fixtures"))
    let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    XCTAssertEqual(vectors.count, 5418)
    let master = LevelsChannel(
      inputBlack: 10, inputWhite: 245, gamma: 1.2, outputBlack: 7, outputWhite: 250)
    var transfers: [String: LevelsTransfer] = [:]
    for v in vectors {
      let p = v.parameters
      let record = LevelsChannel(
        inputBlack: p[0], inputWhite: p[1], gamma: Float(p[2]) / 100, outputBlack: p[3],
        outputWhite: p[4])
      let depth: PixelDepth = v.depth == 8 ? .u8 : v.depth == 16 ? .u16 : .f32
      XCTAssertEqual(record.evaluate(v.input, depth: depth), v.channel, accuracy: 0.000002)
      let key = "\(v.caseIndex)-\(v.depth)"
      if transfers[key] == nil {
        transfers[key] = LevelsTransfer(.init(rgb: master, red: record), depth: depth)
      }
      let input = depth == .f32 ? SRGBTransfer.encoded(v.input) : v.input
      let actual = transfers[key]!.apply(Pixel(input, 0.5, 0.5, 0.37))
      let expected = depth == .f32 ? SRGBTransfer.encoded(v.combined) : v.combined
      XCTAssertEqual(actual.r, expected, accuracy: 0.00001, "\(key): \(v.input)")
      XCTAssertEqual(actual.a, 0.37)
    }
  }
  func testIdentityHiddenColorAndHDRPreservation() throws {
    let pixels = [Pixel(-0.0, 0.27, 2, 0.5), Pixel(-0.3, 1.5, 0.4, 0)]
    for depth in PixelDepth.allCases {
      for pixel in pixels {
        let actual = LevelsTransfer(.init(), depth: depth).apply(pixel)
        XCTAssertEqual(actual.r.bitPattern, pixel.r.bitPattern)
        XCTAssertEqual(actual, pixel)
      }
    }
    let edit = LevelsAdjustment(
      rgb: .init(inputBlack: 15, inputWhite: 230, gamma: 1.3, outputBlack: 10, outputWhite: 245))
    let result = LevelsTransfer(edit, depth: .f32).apply(Pixel(-0.3, 2, 0.4, 0.75))
    XCTAssertLessThan(result.r, 0)
    XCTAssertGreaterThan(result.g, 1)
    XCTAssertEqual(result.a, 0.75)
    XCTAssertEqual(LevelsTransfer(edit, depth: .f32).apply(pixels[1]), pixels[1])
  }
  func testValidationRejectsInvalidAndAllowsReversedOutput() throws {
    for record in [
      LevelsChannel(inputBlack: -1), .init(inputBlack: 254), .init(inputWhite: 1),
      .init(inputBlack: 90, inputWhite: 80), .init(gamma: .nan), .init(gamma: .infinity),
      .init(gamma: 0), .init(gamma: 10), .init(outputBlack: -1), .init(outputWhite: 256),
    ] {
      XCTAssertThrowsError(try Adjustment.levels(.init(red: record)).validate())
    }
    XCTAssertNoThrow(try LevelsChannel(outputBlack: 255, outputWhite: 0).validate())
  }
  func testFloatSelectionMixUsesLinearLightAndOverflowFailsAtomically() throws {
    let before = Pixel(0.2, 0.4, 0.6, 0.37)
    let after = Pixel(0.8, 0.5, 0.1, 0.37)
    let mixed = LevelsTransfer.mix(before, with: after, coverage: 0.5, depth: .f32)
    XCTAssertEqual(
      mixed.r,
      SRGBTransfer.encoded((SRGBTransfer.linear(before.r) + SRGBTransfer.linear(after.r)) / 2),
      accuracy: 0.000001)
    XCTAssertEqual(mixed.a.bitPattern, before.a.bitPattern)
    XCTAssertEqual(LevelsTransfer.mix(before, with: before, coverage: 0.37, depth: .f32), before)
    var d = try CraftDocument(width: 1, height: 1, depth: .f32)
    d.layers[0].content = .raster(
      try Surface(width: 1, height: 1, depth: .f32, fill: Pixel(1000, 0.4, 0.5)))
    var session = EditorSession(document: d)
    XCTAssertThrowsError(
      try session.execute(.applyAdjustment(d.layers[0].id, .levels(.init(rgb: .init(gamma: 0.1))))))
    XCTAssertEqual(session.document, d)
    XCTAssertTrue(session.undoStack.isEmpty)
  }
  func testSelectedDestructiveLevelsAllDepthsUndoAndArchive() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 4, height: 2, depth: depth)
      d.layers[0].content = .raster(
        try Surface(width: 4, height: 2, depth: depth, fill: Pixel(0.3, 0.4, 0.6, 0.5)))
      d.selection = IntRect(x: 1, y: 0, width: 2, height: 2)
      var session = EditorSession(document: d)
      let levels = LevelsAdjustment(red: .init(gamma: 0.5))
      try session.execute(.applyAdjustment(d.layers[0].id, .levels(levels)))
      guard case .raster(let s) = session.document.layers[0].content,
        case .raster(let original) = d.layers[0].content
      else { return XCTFail() }
      XCTAssertEqual(s.pixel(x: 0, y: 0), original.pixel(x: 0, y: 0))
      XCTAssertLessThan(s.pixel(x: 1, y: 0).r, original.pixel(x: 1, y: 0).r)
      XCTAssertEqual(s.pixel(x: 1, y: 0).g, original.pixel(x: 1, y: 0).g)
      try session.undo()
      XCTAssertEqual(session.document, d)
      try session.execute(.addLayer(Layer(name: "Levels", content: .adjustment(.levels(levels)))))
      XCTAssertEqual(
        try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
    }
  }
}
