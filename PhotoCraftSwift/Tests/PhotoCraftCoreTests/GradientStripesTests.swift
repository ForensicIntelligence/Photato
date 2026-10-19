import Foundation
import XCTest

@testable import PhotoCraftCore

final class GradientStripesTests: XCTestCase {
  func testHeldColorsAndOpacityIgnoreMidpointsAndSmoothness() throws {
    var gradient = GradientDefinition(
      colors: [
        .init(0.875, .rgb(Pixel(0, 0, 1)), midpoint: 0.75),
        .init(0.125, .rgb(Pixel(1, 0, 0))),
        .init(0.5, .rgb(Pixel(0, 1, 0)), midpoint: 0.25),
      ], opacity: [.init(0, 0), .init(0.25, 0.5, midpoint: 0.1), .init(0.75, 1)],
      method: .stripes)
    let ramp = try GradientRamp(gradient)
    XCTAssertEqual(ramp.sample(0), Pixel(1, 0, 0, 0))
    XCTAssertEqual(ramp.sample(0.25), Pixel(1, 0, 0, 0.5))
    XCTAssertEqual(ramp.sample(Float(0.5).nextDown), Pixel(1, 0, 0, 0.5))
    XCTAssertEqual(ramp.sample(0.5), Pixel(0, 1, 0, 0.5))
    XCTAssertEqual(ramp.sample(0.75), Pixel(0, 1, 0, 1))
    XCTAssertEqual(ramp.sample(0.875), Pixel(0, 0, 1, 1))
    XCTAssertEqual(ramp.sample(1), Pixel(0, 0, 1, 1))
    XCTAssertEqual(ramp.sample(.nan), .clear)
    gradient.smoothness = 0
    gradient.colors[0].midpoint = 0
    gradient.colors[2].midpoint = 1
    let changed = try GradientRamp(gradient)
    for i in 0...4096 {
      XCTAssertEqual(ramp.sample(Float(i) / 4096), changed.sample(Float(i) / 4096))
    }
  }

  func testCoincidentStopsAndGradientMapAlphaReverseAtAllDepths() throws {
    let gradient = GradientDefinition(
      colors: [
        .init(0, .rgb(Pixel(1, 0, 0))), .init(0.5, .rgb(Pixel(0, 1, 0))),
        .init(0.5, .rgb(Pixel(0, 0, 1))), .init(1, .rgb(.white)),
      ], opacity: [.init(0, 0), .init(1, 0)], method: .stripes)
    let ramp = try GradientRamp(gradient)
    XCTAssertEqual(ramp.sample(0.5), Pixel(0, 0, 1, 0))
    for depth in PixelDepth.allCases {
      let direct = try GradientMapTransfer(.init(gradient: gradient), depth: depth)
      let reversed = try GradientMapTransfer(.init(gradient: gradient, reverse: true), depth: depth)
      XCTAssertEqual(direct.apply(Pixel(0, 0, 0, 0.25)), Pixel(1, 0, 0, 0.25))
      XCTAssertEqual(reversed.apply(Pixel(0, 0, 0, 0.25)), Pixel(1, 1, 1, 0.25))
      XCTAssertEqual(direct.apply(Pixel(0.2, 0.4, 0.6, 0)), Pixel(0.2, 0.4, 0.6, 0))
    }
  }
}
