import Foundation
import XCTest

@testable import PhotoCraftCore

final class GradientTests: XCTestCase {
  func testStopsMidpointsOpacityAndCapturedColors() throws {
    var definition = GradientDefinition(
      name: "Editable",
      colors: [
        .init(1, .background, midpoint: 0.25), .init(0, .foreground),
      ], opacity: [.init(1, 0, midpoint: 0.75), .init(0, 1)], smoothness: 0, method: .classic)
    let resolved = try definition.resolved(
      foreground: Pixel(1, 0, 0, 0), background: Pixel(0, 0, 1, 0.1))
    let ramp = try GradientRamp(resolved)
    XCTAssertEqual(ramp.sample(0.25).r, 0.5)
    XCTAssertEqual(ramp.sample(0.25).b, 0.5)
    XCTAssertEqual(ramp.sample(0.75).a, 0.5)
    XCTAssertEqual(ramp.sample(-10), Pixel(1, 0, 0))
    XCTAssertEqual(ramp.sample(10), Pixel(0, 0, 1, 0))
    XCTAssertEqual(ramp.sample(.nan), .clear)
    definition.colors = [.init(0.5, .rgb(.white))]
    definition.opacity = [.init(0.5, 0.3)]
    let single = try GradientRamp(definition)
    for t: Float in [0, 0.25, 0.5, 0.75, 1] {
      XCTAssertEqual(single.sample(t), Pixel(1, 1, 1, 0.3))
    }
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    XCTAssertEqual(
      try PropertyListDecoder().decode(GradientDefinition.self, from: encoder.encode(resolved)),
      resolved)
  }
  func testDistinctInterpolationAndSmoothnessWithoutBakingStops() throws {
    var gradient = GradientDefinition.blackToWhite
    gradient.smoothness = 0
    gradient.method = .classic
    XCTAssertEqual(try GradientRamp(gradient).sample(0.5).r, 0.5)
    gradient.method = .linear
    XCTAssertEqual(try GradientRamp(gradient).sample(0.5).r, 0.7353569, accuracy: 0.000001)
    gradient.method = .perceptual
    XCTAssertEqual(try GradientRamp(gradient).sample(0.5).r, 0.3885728, accuracy: 0.000002)
    gradient.method = .classic
    gradient.smoothness = 1
    XCTAssertEqual(try GradientRamp(gradient).sample(0.25).r, 0.203125)
    XCTAssertEqual(gradient.colors.count, 2)
    gradient.colors = [
      .init(0, .rgb(.black)), .init(0.5, .rgb(Pixel(1, 0, 0))),
      .init(0.5, .rgb(Pixel(0, 0, 1))), .init(1, .rgb(.white)),
    ]
    gradient.smoothness = 0
    let hard = try GradientRamp(gradient)
    XCTAssertEqual(hard.sample(0.5), Pixel(1, 0, 0))
    XCTAssertLessThan(hard.sample(0.50001).r, 0.0001)
    XCTAssertEqual(hard.sample(0.50001).b, 1)
  }
  func testGeometryHandlesSnappingAndReverse() throws {
    let frame = IntRect(x: 0, y: 0, width: 4, height: 4)
    var placement = GradientPlacement()
    placement.style = .reflected
    placement.angle = 30
    let field = try GradientField(placement, frame: frame)
    for y in 0..<4 {
      for x in 0..<4 {
        XCTAssertEqual(
          field.parameter(x: Float(x) + 0.5, y: Float(y) + 0.5), Float(abs(x - y)) / 4,
          accuracy: 0.000001)
      }
    }
    let large = IntRect(x: -17, y: 23, width: 191, height: 73)
    for style in GradientStyle.allCases {
      placement.style = style
      let start = PathPoint(21, 31)
      let end = PathPoint(96, -15)
      try placement.setHandles(start: start, end: end, in: large)
      let handles = try placement.handles(in: large)
      XCTAssertEqual(handles.start.x, start.x, accuracy: 0.00003)
      XCTAssertEqual(handles.start.y, start.y, accuracy: 0.00003)
      XCTAssertEqual(handles.end.x, end.x, accuracy: 0.00003)
      XCTAssertEqual(handles.end.y, end.y, accuracy: 0.00003)
      placement.reverse = false
      let normal = try GradientField(placement, frame: large)
      placement.reverse = true
      let reverse = try GradientField(placement, frame: large)
      XCTAssertEqual(reverse.parameter(x: 55.5, y: 17.5), 1 - normal.parameter(x: 55.5, y: 17.5))
      try placement.setHandles(start: start, end: start, in: large)
      XCTAssertTrue(try GradientField(placement, frame: large).parameter(x: 0.5, y: 0.5).isFinite)
    }
  }
  func testInvalidDefinitionsAndGeometryRejectWithoutMutation() throws {
    var gradient = GradientDefinition.blackToWhite
    gradient.colors = []
    XCTAssertThrowsError(try GradientRamp(gradient))
    gradient = .blackToWhite
    gradient.colors[1].position = .nan
    XCTAssertThrowsError(try GradientRamp(gradient))
    gradient = .blackToWhite
    gradient.colors[0].color = .rgb(Pixel(1, 0, 0, 0.5))
    XCTAssertThrowsError(try gradient.validate())
    gradient = .blackToWhite
    gradient.opacity = [.init(1, 2)]
    XCTAssertThrowsError(try gradient.validate())
    gradient = .blackToWhite
    gradient.colors = Array(repeating: .init(0, .rgb(.black)), count: 1001)
    XCTAssertThrowsError(try gradient.validate())
    var placement = GradientPlacement()
    let before = placement
    XCTAssertThrowsError(
      try placement.setHandles(
        start: .init(.nan, 0), end: .init(1, 1),
        in: .init(x: 0, y: 0, width: 32, height: 32)))
    XCTAssertEqual(placement, before)
    XCTAssertThrowsError(
      try GradientField(placement, frame: .init(x: Int.max, y: 0, width: 32, height: 32)))
    placement.scale = .infinity
    XCTAssertThrowsError(try placement.validate())
  }
}
