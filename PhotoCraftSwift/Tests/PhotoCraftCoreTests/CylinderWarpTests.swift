import XCTest
@testable import PhotoCraftCore

final class CylinderWarpTests: XCTestCase {
  func testMeasuredCylinderFrontRimsAndExactMeshConversion() throws {
    for (wrap, first) in [(0.0, 0.166169), (0.5, 0.039295), (1.0, 0.005686)] {
      let cylinder = try CylinderWarp(photoshopValues: [12, 73, 112, 13, -0.3, 0.4, wrap])
      let shape = cylinder.surface
      XCTAssertEqual(shape.firstVisibleU, first, accuracy: 1e-12)
      XCTAssertEqual(shape.point(first, 0), .init(12, 13))
      XCTAssertEqual(shape.point(1 - first, 1), .init(112, 73))
      XCTAssertEqual(shape.point(0.5, 0), .init(62, -2))
      XCTAssertEqual(shape.point(0.5, 1), .init(62, 93))
      var warp = WarpDefinition()
      warp.style = .cylinder; warp.cylinder = cylinder
      let custom = try warp.custom(width: 112, height: 90)
      XCTAssertNil(custom.cylinder)
      XCTAssertEqual(custom.mesh?.columns, 13)
      try custom.validate()
      for row in 0...12 {
        for column in 0...24 {
          let u = Double(column) / 24, v = Double(row) / 12
          let a = shape.point(u, v), b = try XCTUnwrap(custom.mesh).point(u, v)
          XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
          XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
      }
    }
    XCTAssertThrowsError(try CylinderWarp(photoshopValues: [0, 10, 100, 0, 1, -1, 0.15]))
    XCTAssertThrowsError(try CylinderWarp(photoshopValues: [0, 80, 100, 0, 0, 0, 1.1]))
  }

  func testDenseAndPagedRenderHideBackArtworkAndRetainProjection() throws {
    let width = 193, height = 67
    var source = try Surface(width: width, height: height, depth: .u16, fill: Pixel(0, 1, 0))
    for y in 0..<height {
      for x in 0..<27 { source.setPixel(x: x, y: y, Pixel(1, 0, 0)) }
      for x in (width - 27)..<width { source.setPixel(x: x, y: y, Pixel(0, 0, 1)) }
    }
    var warp = WarpDefinition()
    warp.style = .cylinder
    warp.cylinder = try .init(photoshopValues: [0, 61, 193, 4, -0.2, 0.2, 0])
    let projection = try SelectionTransform.projection(bounds: .init(x: 0, y: 0, width: width, height: height),
      corners: [.init(3, 2), .init(209, 0), .init(192, 76), .init(0, 70)])
    let transform = Transform2D.translation(11, 8)
    let dense = try WarpRaster.mapping(warp, width: width, height: height, transform: transform, projection: projection)
    let paged = try PagedWarpRaster.mapping(warp, width: width, height: height, transform: transform, projection: projection)
    let pixels = try PagedWarpRaster.render(source, using: paged, method: .nearest)
    XCTAssertEqual(try WarpRaster.render(source, using: dense, method: .nearest), pixels)
    var visible = 0
    for y in 0..<pixels.height {
      for x in 0..<pixels.width {
        let p = pixels.pixel(x: x, y: y)
        if p.a > 0 {
          visible += 1
          XCTAssertEqual(p, Pixel(0, 1, 0))
        }
      }
    }
    XCTAssertGreaterThan(visible, 8_000)
    XCTAssertEqual(pixels.pixel(x: 0, y: 0).a, 0)
  }
}
