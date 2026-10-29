import Foundation
import XCTest

@testable import PhotoCraftCore

final class ColorBalanceTests: XCTestCase {
  struct Vector: Decodable {
    let parameters: [Int]
    let preserve: Bool
    let inputs, outputs, floatInputs, floatOutputs: [[Float]]
  }
  func pixel(_ v: [Float]) -> Pixel { .init(v[0], v[1], v[2], v[3]) }
  func testIndependentRustTonesLuminosityAndFloatOracle() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "color-balance-oracle", withExtension: "json", subdirectory: "Fixtures"))
    let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    XCTAssertEqual(vectors.count, 16)
    XCTAssertEqual(vectors.reduce(0) { $0 + $1.inputs.count }, 15840)
    for (index, v) in vectors.enumerated() {
      func values(_ offset: Int) -> ColorBalanceValues {
        .init(
          cyanRed: v.parameters[offset], magentaGreen: v.parameters[offset + 1],
          yellowBlue: v.parameters[offset + 2])
      }
      let a = ColorBalanceAdjustment(
        shadows: values(0), midtones: values(3), highlights: values(6),
        preserveLuminosity: v.preserve)
      try a.validate()
      for depth in PixelDepth.allCases {
        let transfer = ColorBalanceTransfer(a, depth: depth)
        let inputs = depth == .f32 ? v.floatInputs : v.inputs
        let outputs = depth == .f32 ? v.floatOutputs : v.outputs
        for i in inputs.indices {
          let actual = transfer.apply(pixel(inputs[i]))
          let expected = pixel(outputs[i])
          if index < 2 && (i == 986 || i == 987) {
            // Neutral settings must not reproduce Rust's HDR gamut clipping.
            XCTAssertNotEqual(expected, pixel(inputs[i]))
            XCTAssertEqual(actual, pixel(inputs[i]))
          } else {
            XCTAssertEqual(
              actual.r, expected.r, accuracy: 0.000005, "Case \(index) sample \(i) \(depth)")
            XCTAssertEqual(
              actual.g, expected.g, accuracy: 0.000005, "Case \(index) sample \(i) \(depth)")
            XCTAssertEqual(
              actual.b, expected.b, accuracy: 0.000005, "Case \(index) sample \(i) \(depth)")
          }
          XCTAssertEqual(actual.a.bitPattern, inputs[i][3].bitPattern)
        }
      }
    }
  }
  func testTonalEndpointsPreserveLuminosityAndIndependentSettings() throws {
    var settings = ColorBalanceAdjustment(preserveLuminosity: false)
    settings[.shadows] = .init(cyanRed: 100)
    XCTAssertEqual(
      ColorBalanceTransfer(settings, depth: .u8).apply(Pixel(0.25, 0.25, 0.25)),
      Pixel(0.5, 0.25, 0.25))
    XCTAssertEqual(
      ColorBalanceTransfer(settings, depth: .u8).apply(Pixel(0.75, 0.75, 0.75)),
      Pixel(0.75, 0.75, 0.75))
    settings[.midtones] = .init(magentaGreen: 50)
    settings[.highlights] = .init(yellowBlue: 100)
    XCTAssertEqual(settings.shadows.cyanRed, 100)
    XCTAssertEqual(settings.midtones.magentaGreen, 50)
    XCTAssertEqual(settings.highlights.yellowBlue, 100)
    XCTAssertEqual(
      ColorBalanceTransfer(settings, depth: .u8).apply(Pixel(0.5, 0.5, 0.5)), Pixel(0.5, 0.75, 0.5))
    settings.preserveLuminosity = true
    let output = ColorBalanceTransfer(settings, depth: .u8).apply(Pixel(0.5, 0.5, 0.5))
    XCTAssertEqual(0.299 * output.r + 0.587 * output.g + 0.114 * output.b, 0.5, accuracy: 0.000001)
    for invalid in [Int.min, -101, 101, Int.max] {
      XCTAssertThrowsError(try ColorBalanceAdjustment(shadows: .init(cyanRed: invalid)).validate())
      XCTAssertThrowsError(
        try ColorBalanceAdjustment(midtones: .init(magentaGreen: invalid)).validate())
      XCTAssertThrowsError(
        try ColorBalanceAdjustment(highlights: .init(yellowBlue: invalid)).validate())
    }
  }
  func testNeutralAndHiddenColorsPreserveBitsAndOverflowRejectsAtomically() throws {
    let adjustment = ColorBalanceAdjustment(midtones: .init(cyanRed: 30))
    for depth in PixelDepth.allCases {
      for p in [Pixel(-0.0, 1.5, -0.25, 0.37), Pixel(0.1, 0.3, 0.7, 0.8)] {
        let out = ColorBalanceTransfer(.init(), depth: depth).apply(p)
        XCTAssertEqual(out.r.bitPattern, p.r.bitPattern)
        XCTAssertEqual(out.g.bitPattern, p.g.bitPattern)
        XCTAssertEqual(out.b.bitPattern, p.b.bitPattern)
        XCTAssertEqual(out.a.bitPattern, p.a.bitPattern)
      }
      let hidden = Pixel(-0.5, 2, 0.6, 0)
      XCTAssertEqual(ColorBalanceTransfer(adjustment, depth: depth).apply(hidden), hidden)
    }
    var d = try CraftDocument(width: 1, height: 1, depth: .f32)
    d.layers[0].content = .raster(
      try Surface(width: 1, height: 1, depth: .f32, fill: Pixel(.greatestFiniteMagnitude, 0.4, 0.6))
    )
    var session = EditorSession(document: d)
    XCTAssertThrowsError(
      try session.execute(.applyAdjustment(d.layers[0].id, .colorBalance(adjustment))))
    XCTAssertEqual(session.document, d)
    XCTAssertTrue(session.undoStack.isEmpty)
  }
  func testSelectedPixelCoverageAllDepthsUndoAndNativeArchive() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 4, height: 1, depth: depth)
      let pixels = try Surface(width: 4, height: 1, depth: depth, fill: Pixel(0.3, 0.4, 0.6, 0.5))
      d.layers[0].content = .raster(pixels)
      d.layers[0].x = 1
      try Command.selectionCoverage(
        SelectionMask(width: 4, height: 1, bytes: [0, 255, 128, 0]), .replace
      ).apply(to: &d)
      let a = ColorBalanceAdjustment(shadows: .init(cyanRed: 30), midtones: .init(yellowBlue: -50))
      var session = EditorSession(document: d)
      try session.execute(.applyAdjustment(d.layers[0].id, .colorBalance(a)))
      guard case .raster(let actual) = session.document.layers[0].content else { return XCTFail() }
      let p = pixels.pixel(x: 0, y: 0)
      let edited = ColorBalanceTransfer(a, depth: depth).apply(p)
      XCTAssertEqual(actual.pixel(x: 0, y: 0), edited.quantized(depth))
      XCTAssertEqual(
        actual.pixel(x: 1, y: 0),
        LevelsTransfer.mix(p, with: edited, coverage: 128.0 / 255, depth: depth).quantized(depth))
      XCTAssertEqual(actual.pixel(x: 2, y: 0), p)
      XCTAssertEqual(session.undoStack.last?.label, "Color Balance")
      try session.undo()
      XCTAssertEqual(session.document, d)
      try session.execute(
        .addLayer(Layer(name: "Color Balance", content: .adjustment(.colorBalance(a)))))
      XCTAssertEqual(
        try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
      let before = session.document
      XCTAssertThrowsError(
        try session.execute(
          .applyAdjustment(d.layers[0].id, .colorBalance(.init(midtones: .init(cyanRed: 101))))))
      XCTAssertEqual(session.document, before)
    }
  }
}
