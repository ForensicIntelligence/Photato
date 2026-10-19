import Foundation
import XCTest

@testable import PhotoCraftCore

final class GradientOracleTests: XCTestCase {
  func testExecutedRustGeometryInterpolationAndDither() throws {
    var reader = try PatternOracleTests.Reader("gradient-oracle")
    var geometryCount = 0
    var geometryExact = 0
    var interpolationCount = 0
    var interpolationExact = 0
    var geometryWorst: Float = 0
    var interpolationWorst: Float = 0
    let styles: [GradientStyle] = [.linear, .radial, .angle, .reflected, .diamond]
    func geometry(_ actual: Float, _ expected: Float) {
      geometryCount += 1
      if actual.bitPattern == expected.bitPattern { geometryExact += 1 }
      geometryWorst = max(geometryWorst, abs(actual - expected))
      XCTAssertEqual(actual, expected, accuracy: max(0.000003, abs(expected) * 0.000003))
    }
    func interpolation(_ actual: Float, _ expected: Float) {
      interpolationCount += 1
      if actual.bitPattern == expected.bitPattern { interpolationExact += 1 }
      interpolationWorst = max(interpolationWorst, abs(actual - expected))
      if actual.bitPattern != expected.bitPattern {
        print("Gradient interpolation mismatch \(interpolationCount): \(actual) != \(expected)")
      }
      XCTAssertEqual(actual, expected, accuracy: 0.000003)
    }
    let cases = Int(reader.u())
    XCTAssertEqual(cases, 120)
    for _ in 0..<cases {
      var p = GradientPlacement()
      p.style = styles[Int(reader.u())]
      let frame = IntRect(
        x: Int(Int32(bitPattern: reader.u())), y: Int(Int32(bitPattern: reader.u())),
        width: Int(reader.u()), height: Int(reader.u()))
      p.angle = reader.f()
      p.scale = reader.f()
      p.offsetX = reader.f()
      p.offsetY = reader.f()
      p.reverse = reader.u() != 0
      let snapped = try p.snapped(in: frame)
      for v in [snapped.angle, snapped.scale, snapped.offsetX, snapped.offsetY] {
        geometry(v, reader.f())
      }
      let handles = try p.handles(in: frame)
      for v in [handles.start.x, handles.start.y, handles.end.x, handles.end.y] {
        geometry(Float(v), reader.f())
      }
      var inverse = p
      try inverse.setHandles(start: handles.start, end: handles.end, in: frame)
      for v in [inverse.angle, inverse.scale, inverse.offsetX, inverse.offsetY] {
        geometry(v, reader.f())
      }
      let plain = try GradientField(p, frame: frame, snapEndpoints: false)
      let field = try GradientField(p, frame: frame)
      for _ in 0..<(13 * 11) {
        let x = reader.f()
        let y = reader.f()
        geometry(plain.parameter(x: x, y: y), reader.f())
        geometry(field.parameter(x: x, y: y), reader.f())
      }
    }
    let ramps = Int(reader.u())
    XCTAssertEqual(ramps, 27)
    for _ in 0..<ramps {
      let method: GradientMethod = [.classic, .linear, .perceptual][Int(reader.u())]
      let smooth = reader.f()
      var stops: [GradientColorStop] = []
      for _ in 0..<Int(reader.u()) {
        stops.append(
          .init(reader.f(), .rgb(Pixel(reader.f(), reader.f(), reader.f())), midpoint: reader.f()))
      }
      let ramp = try GradientRamp(.init(colors: stops, smoothness: smooth, method: method))
      for _ in 0...192 {
        let p = ramp.sample(reader.f())
        for v in [p.r, p.g, p.b] { interpolation(v, reader.f()) }
      }
    }
    let ramp = try GradientRamp(
      .init(
        colors: [
          .init(0, .rgb(Pixel(0.1, 0.7, 0.9))),
          .init(0.25, .rgb(Pixel(0.9, 0.3, 0.7)), midpoint: 0.25),
          .init(1, .rgb(Pixel(0.25, 0.1, 0.5)), midpoint: 0.75),
        ],
        opacity: [.init(0, 1), .init(0.75, 0.3), .init(1, 0.6)], smoothness: 0, method: .classic))
    let ditherCount = Int(reader.u())
    XCTAssertEqual(ditherCount, 256)
    var ditherExact = 0
    for i in 0..<ditherCount {
      let p = ramp.sample(reader.f())
      for v in [p.r, p.g, p.b, p.a] {
        let expected = reader.f()
        if v.bitPattern == expected.bitPattern {
          ditherExact += 1
        } else {
          XCTAssertEqual(i, 255)
          XCTAssertEqual(v, expected, accuracy: 0.00000006)
        }
      }
      let dither = GradientRamp.dither(p, x: i - 170, y: i * 13 - 2200)
      for v in [dither.r, dither.g, dither.b, dither.a] {
        let expected = reader.f()
        if v.bitPattern == expected.bitPattern {
          ditherExact += 1
        } else {
          XCTAssertEqual(i, 255)
          XCTAssertEqual(v, expected, accuracy: 0.00000006)
        }
      }
    }
    // Legacy Ramp lerps at t=1 and loses one ULP in green. Retained-stop interpolation
    // deliberately preserves the endpoint, matching the source PSD interpolation evaluator.
    XCTAssertEqual(ditherExact, 2046)
    XCTAssertEqual(geometryExact, geometryCount)
    XCTAssertEqual(interpolationExact, interpolationCount)
    var hsbCount = 0
    XCTAssertEqual(reader.u(), 135)
    for _ in 0..<135 {
      let color = GradientColor.hsb(hue: reader.f(), saturation: reader.f(), brightness: reader.f())
      let p = color.resolved(foreground: .black, background: .white)
      for v in [p.r, p.g, p.b] {
        XCTAssertEqual(v.bitPattern, reader.f().bitPattern)
        hsbCount += 1
      }
    }
    XCTAssertEqual(reader.u(), 3)
    var alphaCount = 0
    for _ in 0..<3 {
      var definition = GradientDefinition.blackToWhite
      definition.smoothness = reader.f()
      definition.opacity = [
        .init(0, 0.2), .init(0.375, 1, midpoint: 0.25), .init(1, 0.1, midpoint: 0.75),
      ]
      let ramp = try GradientRamp(definition)
      for _ in 0...192 {
        XCTAssertEqual(ramp.sample(reader.f()).a.bitPattern, reader.f().bitPattern)
        alphaCount += 1
      }
    }
    print("Gradient Rust HSB/opacity: \(hsbCount)/405 and \(alphaCount)/579 exact values")
    XCTAssertEqual(reader.offset, reader.data.count)
    print(
      "Gradient Rust geometry: \(geometryExact)/\(geometryCount) exact; max error \(geometryWorst)")
    print(
      "Gradient Rust interpolation: \(interpolationExact)/\(interpolationCount) exact; max error \(interpolationWorst)"
    )
    print("Gradient Rust ramp/dither: \(ditherExact)/2048 exact")
  }
}
