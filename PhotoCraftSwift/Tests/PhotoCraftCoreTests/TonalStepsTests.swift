import Foundation
import XCTest

@testable import PhotoCraftCore

final class TonalStepsTests: XCTestCase {
  func testEveryRGB8PosterizeLevelAgainstExecutedRustOracle() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "posterize-u8-oracle", withExtension: "bin", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    XCTAssertEqual(data.count, 254 * 256)
    for level in 2...255 {
      let transfer = TonalStepsTransfer(.init(kind: .posterize, level: level), depth: .u8)
      for input in 0...255 {
        let value = Float(input) / 255
        let p = transfer.apply(Pixel(value, value, value, 0.37))
        let expected = Float(data[(level - 2) * 256 + input]) / 255
        XCTAssertEqual(p, Pixel(expected, expected, expected, 0.37))
      }
    }
  }
  func testThresholdDepthBoundariesAndReferenceLuminance() throws {
    for depth in PixelDepth.allCases {
      let transfer = TonalStepsTransfer(.init(kind: .threshold), depth: depth)
      let p = Pixel(0.5, 0.5, 0.5, 0.37)
      let input = depth == .f32 ? SRGBTransfer.encoded(p) : p
      let expected: Float = depth == .u8 ? 1 : 0
      XCTAssertEqual(transfer.apply(input), Pixel(expected, expected, expected, p.a))
    }
    // Photoshop's saved (131,109,99) sample is exactly 114.5 and stays black.
    let tie = Pixel(131.0 / 255, 109.0 / 255, 99.0 / 255)
    let threshold = TonalStepsTransfer(.init(kind: .threshold, level: 115), depth: .u8)
    XCTAssertEqual(TonalStepsTransfer.luminance(tie) * 255, 114.5)
    XCTAssertEqual(threshold.apply(tie), .black)
    XCTAssertEqual(threshold.apply(Pixel(tie.r + 1.0 / 255, tie.g, tie.b)), .white)
    // Blue distinguishes the measured 0.11 weight from the source's 0.114.
    XCTAssertEqual(
      TonalStepsTransfer(.init(kind: .threshold, level: 29), depth: .u8).apply(Pixel(0, 0, 1)),
      .black)
    for level in [1, 128, 255] {
      let t = TonalStepsTransfer(.init(kind: .threshold, level: level), depth: .u16)
      XCTAssertEqual(t.apply(.black), .black)
      XCTAssertEqual(t.apply(.white), .white)
    }
  }
  func testPosterizeHighDepthDoesNotReduceInputsToRGB8AndPreservesHiddenSamples() throws {
    let a = TonalStepsAdjustment(kind: .posterize, level: 3)
    let p = Pixel(0.334, 0.334, 0.334, 0.37)
    XCTAssertEqual(TonalStepsTransfer(a, depth: .u8).apply(p), Pixel(0, 0, 0, 0.37))
    XCTAssertEqual(TonalStepsTransfer(a, depth: .u16).apply(p), Pixel(0.5, 0.5, 0.5, 0.37))
    let floating = SRGBTransfer.linear(
      TonalStepsTransfer(a, depth: .f32).apply(SRGBTransfer.encoded(p)))
    XCTAssertEqual(floating.r, 0.5, accuracy: 0.000001)
    for kind in TonalStepsAdjustment.Kind.allCases {
      for depth in PixelDepth.allCases {
        let p = Pixel(-0.0, 2, -0.25, 0)
        let out = TonalStepsTransfer(.init(kind: kind), depth: depth).apply(p)
        XCTAssertEqual(out, p)
        XCTAssertEqual(out.r.bitPattern, p.r.bitPattern)
      }
    }
  }
  func testSelectionHistoryPersistenceValidationAndThresholdHistogram() throws {
    for kind in TonalStepsAdjustment.Kind.allCases {
      var d = try CraftDocument(width: 4, height: 1, depth: .u16)
      d.layers[0].content = .raster(
        try Surface(width: 4, height: 1, depth: .u16, fill: Pixel(0.334, 0.7, 0.2, 0.7)))
      try Command.selectionCoverage(
        SelectionMask(width: 4, height: 1, bytes: [0, 128, 255, 0]), .replace
      ).apply(to: &d)
      var session = EditorSession(document: d)
      let a = TonalStepsAdjustment(kind: kind)
      try session.execute(.applyAdjustment(d.layers[0].id, .tonalSteps(a)))
      guard case .raster(let original) = d.layers[0].content,
        case .raster(let edited) = session.document.layers[0].content
      else { return XCTFail() }
      let p = original.pixel(x: 0, y: 0)
      let q = TonalStepsTransfer(a, depth: d.depth).apply(p)
      XCTAssertEqual(edited.pixel(x: 0, y: 0), p)
      XCTAssertEqual(
        edited.pixel(x: 1, y: 0),
        LevelsTransfer.mix(p, with: q, coverage: 128.0 / 255, depth: d.depth).quantized(d.depth))
      XCTAssertEqual(edited.pixel(x: 2, y: 0), q.quantized(d.depth))
      try session.undo()
      XCTAssertEqual(session.document, d)
      XCTAssertThrowsError(
        try session.execute(
          .applyAdjustment(d.layers[0].id, .tonalSteps(.init(kind: kind, level: 0)))))
      XCTAssertEqual(session.document, d)
      XCTAssertTrue(session.undoStack.isEmpty)
      try session.execute(
        .addLayer(Layer(name: kind.rawValue, content: .adjustment(.tonalSteps(a)))))
      XCTAssertEqual(
        try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
    }
    var s = try Surface(width: 4, height: 1)
    s.setPixel(x: 0, y: 0, Pixel(1, 0, 0))
    s.setPixel(x: 1, y: 0, Pixel(0, 1, 0))
    s.setPixel(x: 2, y: 0, Pixel(0, 0, 1))
    let h = try RGBHistogram.analyze(s, depth: .u8, luminance: true)
    XCTAssertEqual(h.samples, 3)
    XCTAssertEqual(h.transparent, 1)
    XCTAssertEqual(h.channels[0][76], 1)
    XCTAssertEqual(h.channels[0][150], 1)
    XCTAssertEqual(h.channels[0][28], 1)
    XCTAssertThrowsError(try TonalStepsAdjustment(kind: .posterize, level: 1).validate())
    XCTAssertThrowsError(try TonalStepsAdjustment(kind: .threshold, level: 256).validate())
  }
}
