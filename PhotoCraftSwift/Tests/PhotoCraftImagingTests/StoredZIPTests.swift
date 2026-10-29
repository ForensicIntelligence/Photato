import Foundation
import XCTest
@testable import PhotoCraftImaging

final class StoredZIPTests: XCTestCase {
  func testHeadersUTF8CRCAndDeterministicOutput() throws {
    let files = [StoredZIP.File(name:"frame0000.png",data:Data([0,1,255])),.init(name:"séquence.json",data:Data("owned".utf8))]
    let bytes = try StoredZIP.encode(files,maximumBytes:1024),archive = try PcraftZIP(bytes)
    XCTAssertEqual(bytes,try StoredZIP.encode(files,maximumBytes:1024));XCTAssertEqual(archive.entries.count,2)
    for file in files { XCTAssertEqual(try archive.read(file.name),file.data) }
    var corrupt = bytes;let offset = 30+files[0].name.utf8.count;corrupt[offset] ^= 1
    XCTAssertThrowsError(try PcraftZIP(corrupt).read(files[0].name))
  }
  func testLimitsAndUnsafeNamesReject() throws {
    for name in ["../frame.png","/frame.png","a\\b","..","\0"] { XCTAssertThrowsError(try StoredZIP.encode([.init(name:name,data:Data())],maximumBytes:1024)) }
    let file = StoredZIP.File(name:"frame.png",data:Data([1]))
    XCTAssertThrowsError(try StoredZIP.encode([file,file],maximumBytes:1024));XCTAssertThrowsError(try StoredZIP.encode([file],maximumBytes:10))
    let bytes = try StoredZIP.encode([file],maximumBytes:1024);XCTAssertEqual(try StoredZIP.encode([file],maximumBytes:bytes.count),bytes)
  }
}
