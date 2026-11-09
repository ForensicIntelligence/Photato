import PhotoCraftCore
import XCTest

final class SelectionTranslationTests: XCTestCase {
  func testIntegerTranslationRetainsEveryGrayByteForClippingAndDifferentOutputSizes() throws {
    let width = 19, height = 13
    let bytes = (0..<(width*height)).map { UInt8(($0*37+11)%256) }
    let source = try SelectionMask(width: width, height: height, bytes: bytes)
    for size in [(19,13),(31,23),(9,7)] {
      for dx in [-100,-19,-8,0,3,19,100] { for dy in [-100,-13,-4,0,5,13,100] {
        let output = try source.transformed(by: .translation(Double(dx),Double(dy)), width: size.0, height: size.1)
        for y in 0..<size.1 { for x in 0..<size.0 {
          let sx=x-dx,sy=y-dy
          let expected:UInt8 = sx>=0 && sy>=0 && sx<width && sy<height ? bytes[sy*width+sx] : 0
          XCTAssertEqual(output.byte(at:y*size.0+x), expected)
        } }
      } }
    }
    XCTAssertEqual(try source.bytes, bytes)
  }
}
