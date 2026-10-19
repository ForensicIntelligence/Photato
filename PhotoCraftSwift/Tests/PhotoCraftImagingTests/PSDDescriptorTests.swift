import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDDescriptorTests: XCTestCase {
  func oracle() throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "descriptor-oracle", withExtension: "bin", subdirectory: "Fixtures")))
  }
  func testIndependentDescriptorOracleIsByteIdentical() throws {
    let bytes = try oracle()
    let d = try PSDDescriptor.read(bytes)
    XCTAssertEqual(d.name, Array("Oracle\0".utf16))
    XCTAssertEqual(d.items.count, 17)
    XCTAssertEqual(d["Nm  "], .text([65, 0xd800, 0, 0]))
    XCTAssertEqual(d["nan "], .doubleBits(0x7ff8_0000_0000_0042))
    XCTAssertEqual(d["comp"], .largeInteger(-(1 << 48)))
    XCTAssertEqual(
      d["Md  "], .enumerated(PSDID(bytes: Data("BlnM".utf8), isCode: false), PSDID("Mltp")))
    XCTAssertEqual(try d.encoded(), bytes)
  }
  func testTruncationCountsDepthAndUnknownTypesReject() throws {
    let bytes = try oracle()
    for n in 0..<bytes.count { XCTAssertThrowsError(try PSDDescriptor.read(bytes.prefix(n))) }
    var bad = bytes
    bad.replaceSubrange(0..<4, with: [0, 0, 0, 17])
    XCTAssertThrowsError(try PSDDescriptor.read(bad))
    var d = PSDDescriptor("null", items: [.init("bool", .boolean(true))])
    var simple = try d.encoded()
    simple[simple.count - 1] = 2
    XCTAssertThrowsError(try PSDDescriptor.read(simple))
    for _ in 0..<70 { d = PSDDescriptor("null", items: [.init("nest", .object(d))]) }
    XCTAssertThrowsError(try d.encoded())
    // A hostile list count is rejected before any element allocation.
    var w = PSDWriter()
    w.n(16, 4)
    w.n(0, 4)
    w.n(0, 4)
    w.text("null")
    w.n(1, 4)
    w.n(0, 4)
    w.text("list")
    w.text("VlLs")
    w.n(Int(UInt32.max), 4)
    XCTAssertThrowsError(try PSDDescriptor.read(w.data))
    w.data.replaceSubrange(28..<32, with: Data("what".utf8))
    XCTAssertThrowsError(try PSDDescriptor.read(w.data))
  }
  func testPaddingIsExplicitAndNonzeroTailRejects() throws {
    let bytes = try oracle()
    XCTAssertThrowsError(try PSDDescriptor.read(bytes + Data([0])))
    XCTAssertEqual(
      try PSDDescriptor.read(bytes + Data([0, 0]), padding: true), try PSDDescriptor.read(bytes))
    XCTAssertThrowsError(try PSDDescriptor.read(bytes + Data([0, 1]), padding: true))
    XCTAssertThrowsError(
      try PSDDescriptor.read(bytes + Data(repeating: 0, count: 4), padding: true))
  }
}
