import XCTest
@testable import PhotoCraftCore

final class IncrementalBrushTests: XCTestCase {
  func testEveryPrefixMatchesCompletePainterAcrossDynamicsDepthAndTransforms() throws {
    for depth in PixelDepth.allCases {
      for variant in 0..<10 {
        var source = try Surface(width: 96, height: 72, depth: depth,
          fill: Pixel(0.2, 0.4, 0.6, 0.7), colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
        source.setPixel(x: 30, y: 25, .clear)
        var brush = Brush(); brush.settings = .init(); brush.settings!.seed = 42
        brush.size = 16; brush.opacity = 0.6; brush.hardness = 0.7
        brush.color = Pixel(0.8, 0.1, 0.3, 0.8); brush.settings!.flow = 0.4
        switch variant {
        case 1: brush.settings!.smoothing.amount = 0.65; brush.settings!.smoothing.catchUpOnEnd = true
        case 2: brush.settings!.scattering.enabled = true; brush.settings!.scattering.amount.jitter = 1.2; brush.settings!.scattering.count = 3
        case 3: brush.settings!.colorDynamics.enabled = true; brush.settings!.colorDynamics.perTip = true; brush.settings!.colorDynamics.hue = 0.5
        case 4: brush.settings!.texture.enabled = true; brush.settings!.colorDynamics.enabled = true
        case 5: brush.settings!.texture.enabled = true; brush.settings!.texture.eachTip = true; brush.settings!.noise = true
        case 6: brush.erase = true
        case 7: brush.settings!.wetEdges = true; brush.settings!.mode = .multiply
        case 8: brush.settings!.shape.enabled = true; brush.settings!.shape.size.control = .penPressure; brush.settings!.shape.angle.control = .direction
        case 9: brush.settings!.buildUp = true
        default: break
        }
        let transform = variant % 2 == 0 ? Transform2D.identity : .translation(3, 5) * .rotation(8)
        let selection = IntRect(x: 5, y: 4, width: 80, height: 60)
        let incremental = try BrushStrokeSession(surface: source, brush: brush, selection: selection,
          transform: transform, grayscaleMask: variant == 8, preserveTransparency: variant == 7)
        var points: [StrokePoint] = []
        for i in 0..<12 {
          let point = StrokePoint(x: 12 + Double(i) * 5, y: 30 + sin(Double(i)) * 10,
            pressure: Float(i % 4 + 1) / 4, time: Double(i) * 40)
          points.append(point)
          let actual = try incremental.append([point])
          var expected = source
          try BrushPainter.stroke(surface: &expected, points: points, brush: brush, selection: selection,
            transform: transform, grayscaleMask: variant == 8, preserveTransparency: variant == 7)
          XCTAssertNil(try actual.changedTileBounds(comparedTo: expected), "depth=\(depth) variant=\(variant) prefix=\(i)")
          XCTAssertNil(try incremental.append([]).changedTileBounds(comparedTo: expected), "Repeated preview must be stable")
        }
      }
    }
  }
  func testInvalidInputDoesNotMutatePublishedSurfaceAndPoisonsSession() throws {
    var brush = Brush(); brush.settings = .init()
    let source = try Surface(width: 64, height: 64)
    let stroke = try BrushStrokeSession(surface: source, brush: brush)
    let first = try stroke.append([.init(x: 12, y: 12, time: 5)])
    let saved = try first.rgbaData(depth: .f32)
    XCTAssertThrowsError(try stroke.append([.init(x: 20, y: 20, time: 4)]))
    XCTAssertThrowsError(try stroke.append([.init(x: 20, y: 20, time: 6)]))
    XCTAssertEqual(try first.rgbaData(depth: .f32), saved)
    brush.settings!.dual.enabled = true
    XCTAssertFalse(BrushStrokeSession.supports(brush))
    XCTAssertThrowsError(try BrushStrokeSession(surface: source, brush: brush))
  }
}
