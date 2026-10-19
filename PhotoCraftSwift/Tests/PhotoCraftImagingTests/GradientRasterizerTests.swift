import Foundation
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GradientRasterizerTests: XCTestCase, @unchecked Sendable {
  func testRegionalAndFullRendersAgreeExactlyAcrossDepthsStylesMethodsAndDither() throws {
    let frame = IntRect(x: -13, y: 21, width: 47, height: 31)
    let region = IntRect(x: 2, y: 24, width: 17, height: 23)
    var cases = 0
    for style in GradientStyle.allCases {
      for method in GradientMethod.allCases {
        for depth in PixelDepth.allCases {
          for dither in [false, true] {
            var placement = GradientPlacement()
            placement.style = style
            placement.angle = 27.5
            placement.scale = 0.75
            placement.offsetX = -0.23
            placement.offsetY = 0.15
            placement.reverse = true
            let definition = GradientDefinition(
              colors: [
                .init(0, .rgb(Pixel(0.1, 0.7, 0.9))),
                .init(0.375, .rgb(Pixel(0.9, 0.3, 0.7)), midpoint: 0.25),
                .init(1, .rgb(Pixel(0.25, 0.1, 0.5)), midpoint: 0.75),
              ],
              opacity: [.init(0, 0.25), .init(0.75, 1, midpoint: 0.33), .init(1, 0.6)],
              smoothness: 0.37, method: method)
            let full = try GradientRasterizer.render(
              definition, placement: placement, frame: frame, depth: depth, dither: dither)
            let partial = try GradientRasterizer.render(
              definition, placement: placement, frame: frame, region: region, depth: depth,
              dither: dither)
            for y in 0..<region.height {
              for x in 0..<region.width {
                XCTAssertTrue(
                  partial.pixel(x: x, y: y).hasSameBits(
                    as: full.pixel(x: x + region.x - frame.x, y: y + region.y - frame.y)))
              }
            }
            cases += 1
          }
        }
      }
    }
    XCTAssertEqual(cases, 120)
  }
  func testCancelledAndHostileRegionsReturnNoPartialSurface() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try GradientRasterizer.render(
        .blackToWhite, placement: GradientPlacement(),
        frame: .init(x: 0, y: 0, width: 6000, height: 4000))
    }
    do {
      _ = try await task.value
      XCTFail("Cancellation must throw")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertThrowsError(
      try GradientRasterizer.render(
        .blackToWhite, placement: GradientPlacement(),
        frame: .init(x: 0, y: 0, width: 16, height: 16),
        region: .init(x: Int.max, y: 0, width: 16, height: 16)))
    XCTAssertThrowsError(
      try GradientRasterizer.render(
        .blackToWhite, placement: GradientPlacement(),
        frame: .init(x: 0, y: 0, width: 16, height: 16),
        region: .init(x: 0, y: 0, width: Int.max, height: 16)))
  }
  func testGeometryAndOpacityAppearInAnIndependentImageIODecode() throws {
    var gradient = GradientDefinition.blackToWhite
    gradient.method = .classic
    gradient.smoothness = 0
    gradient.opacity = [.init(0, 0.5), .init(1, 0.5)]
    var placement = GradientPlacement()
    placement.angle = 0
    let rendered = try GradientRasterizer.render(
      gradient, placement: placement,
      frame: .init(x: 0, y: 0, width: 128, height: 64), depth: .u16)
    for x in 0..<128 {
      XCTAssertEqual(rendered.pixel(x: x, y: 17).r, PixelDepth.u16.quantize(Float(x) / 128))
      XCTAssertEqual(rendered.pixel(x: x, y: 17).a, PixelDepth.u16.quantize(0.5))
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "gradient-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try RasterIO.write(rendered, to: url)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let decoded = try RasterIO.surface(
      XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)), depth: .u16)
    XCTAssertEqual(decoded.width, 128)
    XCTAssertEqual(decoded.height, 64)
    XCTAssertEqual(decoded.pixel(x: 64, y: 32).r, 0.5, accuracy: 0.0001)
    XCTAssertEqual(decoded.pixel(x: 64, y: 32).a, 0.5, accuracy: 0.0001)
  }
}
