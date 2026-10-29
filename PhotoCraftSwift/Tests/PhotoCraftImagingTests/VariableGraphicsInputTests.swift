import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class VariableGraphicsInputTests: XCTestCase {
  func template() throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 4)
    try Command.variables(.define([.init(name: "photo", layerID: document.layers[0].id, kind: .pixelReplacement)])).apply(to: &document)
    return document
  }
  func image() throws -> Data {
    var source = try CraftDocument(width: 2, height: 2)
    source.layers[0].content = .raster(try Surface(width: 2, height: 2, fill: Pixel(1, 0, 0)))
    return try RasterIO.encoded(source)
  }
  func testEncodingAndBOMDetection() throws {
    let text = "title\r\nCafé 🥔\r\n"
    XCTAssertEqual(try VariableGraphicsInput.text(Data([0xef, 0xbb, 0xbf]) + Data(text.utf8)), text)
    for (choice, encoding, bom) in [(VariableTextEncoding.utf16LittleEndian, String.Encoding.utf16LittleEndian, Data([0xff, 0xfe])), (.utf16BigEndian, .utf16BigEndian, Data([0xfe, 0xff]))] {
      let bytes = try XCTUnwrap(text.data(using: encoding))
      XCTAssertEqual(try VariableGraphicsInput.text(bytes, encoding: choice), text)
      XCTAssertEqual(try VariableGraphicsInput.text(bom + bytes), text)
    }
    let legacy = "title\nCafé\n"
    for (choice, encoding) in [(VariableTextEncoding.macRoman, String.Encoding.macOSRoman), (.windowsLatin1, .windowsCP1252)] {
      XCTAssertEqual(try VariableGraphicsInput.text(XCTUnwrap(legacy.data(using: encoding)), encoding: choice), legacy)
    }
    XCTAssertThrowsError(try VariableGraphicsInput.text(Data([0xff]), encoding: .utf8))
    XCTAssertThrowsError(try VariableGraphicsInput.text(Data([0])))
  }
  func testImportedAssetsAreDeduplicatedEmbeddedAndApplyAtEveryDepth() throws {
    for depth in [PixelDepth.u8, .u16, .f32] {
      var document = try CraftDocument(width: 4, height: 4, depth: depth)
      try Command.variables(.define([.init(name: "photo", layerID: document.layers[0].id, kind: .pixelReplacement)])).apply(to: &document)
      let bytes = try image(); var reads = 0
      let settings = try VariableGraphicsInput.importing(Data("photo\nrelative/red.png\nrelative/red.png\n".utf8), into: document) { path in
        XCTAssertEqual(path, "relative/red.png"); reads += 1; return bytes
      }
      XCTAssertEqual(reads, 1); XCTAssertEqual(settings.images.count, 1); XCTAssertEqual(settings.dataSets.count, 2)
      XCTAssertEqual(settings.images[0].pixels.depth, depth)
      try Command.variables(.configure(settings, apply: settings.dataSets[0].id)).apply(to: &document)
      XCTAssertEqual(try Renderer.composite(document).pixel(x: 2, y: 2), Pixel(1, 0, 0))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(document)), document)
    }
  }
  func testLateMissingImageLeavesTemplateUnchanged() throws {
    let document = try template(), original = document, bytes = try image()
    var reads = 0
    XCTAssertThrowsError(try VariableGraphicsInput.importing(Data("photo\nred.png\nmissing.png\n".utf8), into: document) { _ in
      reads += 1; if reads == 2 { throw CraftError.invalid("Missing owned fixture") }; return bytes
    })
    XCTAssertEqual(reads, 2); XCTAssertEqual(document, original); XCTAssertTrue(document.variables!.images.isEmpty)
    XCTAssertThrowsError(try VariableGraphicsInput.image(Data([0, 1]), name: "Bad", for: document))
  }
}
