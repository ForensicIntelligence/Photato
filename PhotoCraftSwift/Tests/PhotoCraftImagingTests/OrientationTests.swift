import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class OrientationTests: XCTestCase {
  func testAllEXIFOrientations() throws {
    var source = try Surface(width: 2, height: 3, depth: .f32)
    for y in 0..<3 {
      for x in 0..<2 { source.setPixel(x: x, y: y, Pixel(Float(y * 2 + x + 1) / 10, 0, 0)) }
    }
    let expected = [
      [1, 2, 3, 4, 5, 6], [2, 1, 4, 3, 6, 5], [6, 5, 4, 3, 2, 1], [5, 6, 3, 4, 1, 2],
      [1, 3, 5, 2, 4, 6], [5, 3, 1, 6, 4, 2], [6, 4, 2, 5, 3, 1], [2, 4, 6, 1, 3, 5],
    ]
    for orientation in 1...8 {
      let result = try RasterIO.oriented(source, orientation: orientation)
      var actual: [Int] = []
      for y in 0..<result.height {
        for x in 0..<result.width {
          actual.append(Int((result.pixel(x: x, y: y).r * 10).rounded()))
        }
      }
      XCTAssertEqual(actual, expected[orientation - 1], "Orientation \(orientation)")
    }
    XCTAssertThrowsError(try RasterIO.oriented(source, orientation: 0))
  }
}
