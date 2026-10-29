import Foundation
import XCTest

@testable import PhotoCraftCore

final class HueSaturationTests: XCTestCase {
  struct Vector: Decodable {
    let parameters: [Int]
    let colorize: Bool
    let ranges: [[Int]]
    let inputs, outputs, floatInputs, floatOutputs: [[Float]]
  }
  func pixel(_ values: [Float]) -> Pixel { .init(values[0], values[1], values[2], values[3]) }
  func testRetainedRustHSLRangesAndFloatStorageOracle() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "hue-saturation-oracle", withExtension: "json", subdirectory: "Fixtures"))
    let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    XCTAssertEqual(vectors.count, 12)
    XCTAssertEqual(vectors.reduce(0) { $0 + $1.inputs.count }, 8940)
    var retainedSamples = 0
    for (index, v) in vectors.enumerated() {
      // Keep the independent identity, hue-only, master desaturation and neutral
      // Colorize references. Photoshop saved composites contradict the other
      // Rust lightness, saturation and range transfers; do not enforce them.
      guard [0, 1, 2, 8].contains(index) else { continue }
      retainedSamples += v.inputs.count
      let values = HueSaturationValues(
        hue: v.parameters[0], saturation: v.parameters[1], lightness: v.parameters[2])
      let settings = HueSaturationAdjustment(
        master: v.colorize ? .init() : values,
        colorization: v.colorize ? values : .init(saturation: 25), colorize: v.colorize,
        ranges: v.ranges.map {
          .init(
            values: .init(hue: $0[4], saturation: $0[5], lightness: $0[6]),
            bounds: Array($0.prefix(4)))
        })
      try settings.validate()
      for depth in PixelDepth.allCases {
        let transfer = HueSaturationTransfer(settings, depth: depth)
        let inputs = depth == .f32 ? v.floatInputs : v.inputs
        let outputs = depth == .f32 ? v.floatOutputs : v.outputs
        for i in inputs.indices {
          let actual = transfer.apply(pixel(inputs[i]))
          let expected = pixel(outputs[i])
          // The unchanged source projects extended RGB into HSL even when no
          // setting affects the pixel. Pin this known source defect separately:
          // an identity edit / an excluded color must keep its HDR samples.
          let preserveHDR =
            (index == 0 || index == 11) && (i == 741 || i == 742)
            || index == 5 && i == 741
          if preserveHDR {
            XCTAssertNotEqual(expected, pixel(inputs[i]))
            XCTAssertEqual(actual.r.bitPattern, inputs[i][0].bitPattern)
            XCTAssertEqual(actual.g.bitPattern, inputs[i][1].bitPattern)
            XCTAssertEqual(actual.b.bitPattern, inputs[i][2].bitPattern)
            XCTAssertEqual(actual.a.bitPattern, inputs[i][3].bitPattern)
            continue
          }
          XCTAssertEqual(
            actual.r, expected.r, accuracy: 0.000005, "Case \(index) sample \(i) \(depth)")
          XCTAssertEqual(
            actual.g, expected.g, accuracy: 0.000005, "Case \(index) sample \(i) \(depth)")
          XCTAssertEqual(
            actual.b, expected.b, accuracy: 0.000005, "Case \(index) sample \(i) \(depth)")
          XCTAssertEqual(actual.a.bitPattern, inputs[i][3].bitPattern)
        }
      }
    }
    XCTAssertEqual(retainedSamples, 2980)
  }
  func testMasterAndRangeLightnessHaveDifferentEndpoints() throws {
    for depth in PixelDepth.allCases {
      let input = Pixel(0.8, 0.2, 0.2, 0.37)
      let encoded = depth == .f32 ? SRGBTransfer.encoded(input) : input
      for amount in [-100, 100] {
        var a = HueSaturationAdjustment(master: .init(lightness: amount))
        let master = HueSaturationTransfer(a, depth: depth).apply(encoded)
        let measuredMaster = depth == .f32 ? SRGBTransfer.linear(master) : master
        let masterValue: Float = amount < 0 ? 0 : 1
        XCTAssertEqual(measuredMaster.r, masterValue, accuracy: 0.000001)
        XCTAssertEqual(measuredMaster.g, masterValue, accuracy: 0.000001)
        XCTAssertEqual(measuredMaster.b, masterValue, accuracy: 0.000001)
        a.master.lightness = 0
        a.ranges[0].values.lightness = amount
        let range = HueSaturationTransfer(a, depth: depth).apply(encoded)
        let measuredRange = depth == .f32 ? SRGBTransfer.linear(range) : range
        let rangeValue: Float = amount < 0 ? 0.2 : 0.8
        XCTAssertEqual(measuredRange.r, rangeValue, accuracy: 0.000001)
        XCTAssertEqual(measuredRange.g, rangeValue, accuracy: 0.000001)
        XCTAssertEqual(measuredRange.b, rangeValue, accuracy: 0.000001)
        XCTAssertEqual(master.a.bitPattern, encoded.a.bitPattern)
        XCTAssertEqual(range.a.bitPattern, encoded.a.bitPattern)
        let gray = Pixel(0.37, 0.37, 0.37, 0.63)
        XCTAssertEqual(HueSaturationTransfer(a, depth: depth).apply(gray), gray)
      }
    }
  }
  func testNearGrayRangeLightnessAndHueRetainFullRangeWeight() throws {
    for depth in PixelDepth.allCases {
      let p = Pixel(0.52, 0.50, 0.50, 0.37)
      let input = depth == .f32 ? SRGBTransfer.encoded(p) : p
      for (values, expected) in [
        (HueSaturationValues(lightness: 50), Pixel(0.52, 0.51, 0.51)),
        (HueSaturationValues(lightness: -50), Pixel(0.51, 0.50, 0.50)),
        (HueSaturationValues(hue: 120), Pixel(0.50, 0.52, 0.50)),
      ] {
        var a = HueSaturationAdjustment()
        a.ranges[0].values = values
        let out = HueSaturationTransfer(a, depth: depth).apply(input)
        let measured = depth == .f32 ? SRGBTransfer.linear(out) : out
        XCTAssertEqual(measured.r, expected.r, accuracy: 0.000001)
        XCTAssertEqual(measured.g, expected.g, accuracy: 0.000001)
        XCTAssertEqual(measured.b, expected.b, accuracy: 0.000001)
        XCTAssertEqual(out.a.bitPattern, input.a.bitPattern)
      }
    }
  }
  func testMasterLightnessPrecedesPositiveSaturationAndExtremesStayFinite() throws {
    for depth in PixelDepth.allCases {
      let p = Pixel(0.9, 0.4, 0.4, 0.37)
      let input = depth == .f32 ? SRGBTransfer.encoded(p) : p
      let a = HueSaturationAdjustment(master: .init(saturation: 50, lightness: -50))
      let out = HueSaturationTransfer(a, depth: depth).apply(input)
      let measured = depth == .f32 ? SRGBTransfer.linear(out) : out
      XCTAssertEqual(measured.r, 0.575, accuracy: 0.000001)
      XCTAssertEqual(measured.g, 0.075, accuracy: 0.000001)
      XCTAssertEqual(measured.b, 0.075, accuracy: 0.000001)
      XCTAssertEqual(out.a.bitPattern, p.a.bitPattern)
      for amount in [-100, 100] {
        let transfer = HueSaturationTransfer(.init(master: .init(saturation: amount)), depth: depth)
        for sample in [Pixel.black, .white, Pixel(0.4, 0.4, 0.4), Pixel(1, 0, 0), input] {
          let result = transfer.apply(sample)
          XCTAssertTrue(result.isFinite)
          XCTAssertEqual(result.a.bitPattern, sample.a.bitPattern)
          if sample.r == sample.g && sample.g == sample.b { XCTAssertEqual(result, sample) }
        }
      }
    }
  }
  func testOverlappingRangeLightnessClampsInStoredOrder() throws {
    for values in [[100, 100, -100], [-100, 100, 100]] {
      var a = HueSaturationAdjustment()
      for i in values.indices {
        a.ranges[i] = HueRange(values: .init(lightness: values[i]), bounds: [-45, -15, 15, 45])
      }
      let input = Pixel(0.8, 0.2, 0.2, 0.37)
      let result = HueSaturationTransfer(a, depth: .u8).apply(input)
      XCTAssertEqual(result, values[0] == 100 ? input : Pixel(0.8, 0.8, 0.8, 0.37))
    }
  }
  func testColorizeLightnessPrecedesTintSynthesis() throws {
    for depth in PixelDepth.allCases {
      for (input, hue, lightness, expected) in [
        (Pixel.white, 0, -50, Pixel(1, 0, 0)),
        (Pixel.black, 120, 50, Pixel(0, 1, 0)),
        (Pixel(0.75, 0.25, 0.25, 0.37), 240, -50, Pixel(0, 0, 0.5, 0.37)),
      ] {
        let a = HueSaturationAdjustment(
          colorization: .init(hue: hue, saturation: 100, lightness: lightness), colorize: true)
        let p = depth == .f32 ? SRGBTransfer.encoded(input) : input
        let out = HueSaturationTransfer(a, depth: depth).apply(p)
        // Qualify float tone math in its linear domain: encoding very small
        // round-trip residuals magnifies them by 12.92 near black.
        let measured = depth == .f32 ? SRGBTransfer.linear(out) : out
        XCTAssertEqual(measured.r, expected.r, accuracy: 0.000001)
        XCTAssertEqual(measured.g, expected.g, accuracy: 0.000001)
        XCTAssertEqual(measured.b, expected.b, accuracy: 0.000001)
        XCTAssertEqual(out.a.bitPattern, p.a.bitPattern)
      }
    }
  }
  func testRangeWrappingFeatherEdgesValidationAndPointConstraints() throws {
    var reds = HueRange.neutral(0)
    XCTAssertEqual(try HueRange.fromWrapped([315, 345, 15, 45]), reds.bounds)
    for angle in [-360, 0, 360, 720] { XCTAssertEqual(reds.weight(Float(angle)), 1) }
    XCTAssertEqual(reds.weight(-45), 0)
    XCTAssertEqual(reds.weight(-30), 0.5)
    XCTAssertEqual(reds.weight(30), 0.5)
    XCTAssertEqual(reds.weight(60), 0)
    reds.moveEdge(1, to: 500)
    XCTAssertEqual(reds.bounds, [-45, 15, 15, 45])
    reds.moveEdge(0, to: -500)
    XCTAssertEqual(reds.bounds[0], -314)
    try reds.validate()
    for bounds in [[], [0, 1, 2], [0, 10, 5, 20], [0, 100, 200, 360], [Int.min, 0, 0, Int.max]] {
      XCTAssertThrowsError(try HueRange(bounds: bounds).validate())
    }
    for bounds in [[315, 345, 15], [-45, 345, 15, 45], [0, 359, 1, 359], [0, 120, 240, 0]] {
      XCTAssertThrowsError(try HueRange.fromWrapped(bounds))
    }
    XCTAssertThrowsError(try HueSaturationAdjustment(ranges: []).validate())
    for values in [HueSaturationValues(hue: 181), .init(saturation: 101), .init(lightness: -101)] {
      XCTAssertThrowsError(try HueSaturationAdjustment(master: values).validate())
    }
    XCTAssertThrowsError(
      try HueSaturationAdjustment(colorization: .init(saturation: -1)).validate())
  }
  func testColorizeHasNoHiddenSaturationFloorAndRetainsInactiveSettings() throws {
    var a = HueSaturationAdjustment(master: .init(hue: 40, saturation: -20, lightness: 8))
    a.ranges[0].values = .init(hue: -60, saturation: -100)
    let normal = a
    a.colorize = true
    a[.reds] = .init(hue: 0, saturation: 0)
    let p = Pixel(0.2, 0.4, 0.8, 0.75)
    XCTAssertEqual(HueSaturationTransfer(a, depth: .u8).apply(p), Pixel(0.5, 0.5, 0.5, 0.75))
    a.colorization.saturation = 10
    let low = HueSaturationTransfer(a, depth: .u8).apply(p)
    XCTAssertEqual(low.r, 0.55, accuracy: 0.000001)
    XCTAssertEqual(low.g, 0.45, accuracy: 0.000001)
    XCTAssertEqual(low.b, 0.45, accuracy: 0.000001)
    a.colorize = false
    XCTAssertEqual(a.master, normal.master)
    XCTAssertEqual(a.ranges, normal.ranges)
    a.colorization.hue = 360
    XCTAssertNoThrow(try a.validate())
  }
  func testIdentityExcludedColorsHiddenRGBAndFloatOverflow() throws {
    var ranges = HueRange.defaults
    ranges[0].values.saturation = -100
    let a = HueSaturationAdjustment(ranges: ranges)
    for depth in PixelDepth.allCases {
      let transfer = HueSaturationTransfer(a, depth: depth)
      for p in [Pixel(-0.0, 0.0, 1, 0.37), Pixel(0.3, 0.3, 0.3, 0.5), Pixel(-0.4, 2, 0.3, 0)] {
        let output = transfer.apply(p)
        XCTAssertEqual(output, p)
        XCTAssertEqual(output.r.bitPattern, p.r.bitPattern)
      }
      let p = Pixel(-0.0, 1.5, -0.25, 0.5)
      XCTAssertEqual(HueSaturationTransfer(.init(), depth: depth).apply(p), p)
      XCTAssertEqual(
        HueSaturationTransfer(.init(), depth: depth).apply(p).r.bitPattern, p.r.bitPattern)
    }
    var d = try CraftDocument(width: 1, height: 1, depth: .f32)
    d.layers[0].content = .raster(
      try Surface(width: 1, height: 1, depth: .f32, fill: Pixel(.greatestFiniteMagnitude, 0.2, 0.5))
    )
    var session = EditorSession(document: d)
    XCTAssertThrowsError(
      try session.execute(
        .applyAdjustment(d.layers[0].id, .hueSaturation(.init(master: .init(hue: 30))))))
    XCTAssertEqual(session.document, d)
    XCTAssertTrue(session.undoStack.isEmpty)
  }
  func testSelectedPixelEditHistoryNativeArchiveAndLegacySaturation() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 4, height: 1, depth: depth)
      let original = try Surface(width: 4, height: 1, depth: depth, fill: Pixel(0.3, 0.4, 0.6, 0.5))
      d.layers[0].content = .raster(original)
      d.layers[0].x = 1
      try Command.selectionCoverage(
        SelectionMask(width: 4, height: 1, bytes: [0, 255, 128, 0]), .replace
      ).apply(to: &d)
      let a = HueSaturationAdjustment(master: .init(hue: 120, saturation: -50, lightness: 20))
      var session = EditorSession(document: d)
      try session.execute(.applyAdjustment(d.layers[0].id, .hueSaturation(a)))
      guard case .raster(let actual) = session.document.layers[0].content else { return XCTFail() }
      let p = original.pixel(x: 0, y: 0)
      let edited = HueSaturationTransfer(a, depth: depth).apply(original.pixel(x: 0, y: 0))
      XCTAssertEqual(actual.pixel(x: 0, y: 0), edited.quantized(depth))
      XCTAssertEqual(
        actual.pixel(x: 1, y: 0),
        LevelsTransfer.mix(p, with: edited, coverage: 128.0 / 255, depth: depth).quantized(depth))
      XCTAssertEqual(actual.pixel(x: 2, y: 0), p)
      try session.undo()
      XCTAssertEqual(session.document, d)
      try session.execute(
        .addLayer(Layer(name: "Hue/Saturation", content: .adjustment(.hueSaturation(a)))))
      try session.execute(.addLayer(Layer(name: "Legacy", content: .adjustment(.saturation(0.5)))))
      XCTAssertEqual(
        try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
      let before = session.document
      XCTAssertThrowsError(
        try session.execute(.applyAdjustment(d.layers[0].id, .hueSaturation(.init(ranges: [])))))
      XCTAssertEqual(session.document, before)
    }
  }
}
