import Foundation
import XCTest

@testable import PhotoCraftCore

final class GradientMapTests: XCTestCase {
  func testToneTablePreservesScalarOutputAndCoordinateDither() throws {
    for depth in PixelDepth.allCases {
      for method in GradientMethod.allCases {
        var gradient = GradientDefinition.blackToWhite
        gradient.method = method
        gradient.colors = [
          .init(0, .rgb(Pixel(0.02, 0.68, 0.37))),
          .init(0.6, .rgb(Pixel(0.8, 0.2, 0.07)), midpoint: 0.62),
          .init(1, .rgb(Pixel(0.82, 0.88, 0.96))),
        ]
        for reverse in [false, true] {
          let settings = GradientMapAdjustment(gradient: gradient, reverse: reverse, dither: true)
          let scalar = try GradientMapTransfer(settings, depth: depth)
          let batched = try GradientMapTransfer(settings, depth: depth, pixelCount: 1_048_576)
          var differences = 0
          for i in 0...4096 {
            let t = Float(i) / 4096
            let p = Pixel(t, t, t, i % 7 == 0 ? 0 : 0.37)
            if !batched.apply(p, x: i - 2000, y: i / 64).hasSameBits(
                as: scalar.apply(p, x: i - 2000, y: i / 64)) {
              differences += 1
            }
          }
          XCTAssertEqual(differences, 0)
        }
      }
    }
  }

  func testLuminanceReverseAndTransparency() throws {
    var g = GradientDefinition.blackToWhite
    g.method = .classic
    g.smoothness = 0
    g.opacity = [.init(0, 0), .init(1, 0)]
    var a = GradientMapAdjustment(gradient: g)
    let t = try GradientMapTransfer(a, depth: .u16)
    XCTAssertEqual(
      t.apply(Pixel(1, 0, 0, 0.37)), Pixel(9831 / 32768, 9831 / 32768, 9831 / 32768, 0.37))
    XCTAssertEqual(t.apply(Pixel(0, 1, 0)), Pixel(19335 / 32768, 19335 / 32768, 19335 / 32768))
    XCTAssertEqual(t.apply(Pixel(0, 0, 1)), Pixel(3607 / 32768, 3607 / 32768, 3607 / 32768))
    let hidden = Pixel(0.7, 0.2, 0.1, 0)
    XCTAssertEqual(t.apply(hidden), hidden)
    a.reverse = true
    XCTAssertEqual(try GradientMapTransfer(a, depth: .u8).apply(.black), .white)
  }
  func testCoordinateDitherIsPeriodicAndDepthIndependentOfPresetAlpha() throws {
    var g = GradientDefinition.blackToWhite
    g.method = .classic
    g.smoothness = 0
    let a = GradientMapAdjustment(gradient: g, dither: true)
    for depth in PixelDepth.allCases {
      let t = try GradientMapTransfer(a, depth: depth)
      for y in -4...7 {
        for x in -4...7 {
          let p = Pixel(0.5, 0.5, 0.5, 0.42)
          XCTAssertEqual(t.apply(p, x: x, y: y), t.apply(p, x: x + 4, y: y - 4))
          XCTAssertEqual(t.apply(p, x: x, y: y).a, p.a)
        }
      }
    }
  }
  func testInvalidOrDynamicControlsRejectBeforeDocumentEdit() throws {
    var document = try CraftDocument(width: 3, height: 3)
    let before = document
    var settings = GradientMapAdjustment(gradient: .foregroundToBackground)
    XCTAssertThrowsError(
      try Command.applyAdjustment(document.layers[0].id, .gradientMap(settings)).apply(
        to: &document))
    XCTAssertEqual(document, before)
    settings.gradient = .blackToWhite
    settings.gradient.colors[0].position = .nan
    XCTAssertThrowsError(try settings.validate())
  }
  func testSelectedPixelCommandAndNativeArchiveKeepUnselectedPixels() throws {
    var doc = try CraftDocument(width: 4, height: 3, depth: .u16)
    let source = Pixel(0.8, 0.3, 0.1)
    doc.layers[0].content = .raster(try Surface(width: 4, height: 3, depth: .u16, fill: source))
    doc.selection = IntRect(x: 1, y: 1, width: 2, height: 1)
    var session = EditorSession(document: doc)
    try session.execute(.applyAdjustment(doc.layers[0].id, .gradientMap(.init())))
    guard case .raster(let result) = session.document.layers[0].content else { return XCTFail() }
    XCTAssertEqual(result.pixel(x: 0, y: 0), source.quantized(.u16))
    XCTAssertNotEqual(result.pixel(x: 1, y: 1), source.quantized(.u16))
    XCTAssertEqual(
      try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
    try session.undo()
    XCTAssertEqual(session.document, doc)
  }
}
