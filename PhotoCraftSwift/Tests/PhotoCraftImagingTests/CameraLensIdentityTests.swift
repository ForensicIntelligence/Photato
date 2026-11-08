import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class CameraLensIdentityTests: XCTestCase {
  func expected() throws -> CameraLensIdentity {
    try .init(cameraMake: "PhotatoTest", cameraModel: "Photato Test Camera", lensModel: "Photato Test Lens 24mm", focalLength: 24, fNumber: 2.8)
  }
  func fixture() throws -> Data {
    try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "owned-camera", withExtension: "tif", subdirectory: "Fixtures/OwnedLensDefaults452")))
  }
  func testRealImageIOCaptureAndRasterNativeRoundTrips() throws {
    let document = try RasterIO.read(fixture(), name: "Owned camera")
    XCTAssertEqual(try CameraLensIdentity.read(from: document.sourceMetadata), try expected())
    XCTAssertEqual(try CameraLensIdentity.read(from: NativeArchive.decode(NativeArchive.encode(document)).sourceMetadata), try expected())
    for type in [UTType.jpeg, .tiff, .png] {
      let restored = try RasterIO.read(RasterIO.encoded(document, type: type), name: "Round trip")
      XCTAssertEqual(try CameraLensIdentity.read(from: restored.sourceMetadata), try expected(), type.identifier)
    }
  }
  func testPSDExifBothResourceIDsAndExifPrefix() throws {
    let data = try fixture()
    for id in [1058, 1059] {
      for bytes in [data, Data([69,120,105,102,0,0]) + data] {
        let source = ["psdResources": PSDImageResources.block(id, data: bytes)]
        XCTAssertEqual(try CameraLensIdentity.read(from: source), try expected())
      }
    }
    XCTAssertEqual(try CameraLensIdentity.read(from: ["pcraft.exif": data]), try expected())
  }
  func testXMPAliasesRationalValuesAndMissingFields() throws {
    let xml = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/" xmlns:aux="http://ns.adobe.com/exif/1.0/aux/"><tiff:Make>PhotatoTest</tiff:Make><tiff:Model>Photato Test Camera</tiff:Model><aux:Lens>Photato Test Lens 24mm</aux:Lens><exif:FocalLength>24/1</exif:FocalLength><exif:FNumber>28/10</exif:FNumber></rdf:Description></rdf:RDF></x:xmpmeta>
    """
    XCTAssertEqual(try CameraLensIdentity.read(from: ["imageIOXMP": Data(xml.utf8)]), try expected())
    XCTAssertEqual(try CameraLensIdentity.read(from: ["psdResources": PSDImageResources.block(1060, data: Data(xml.utf8))]), try expected())
    XCTAssertNil(try CameraLensIdentity.read(from: nil))
    XCTAssertNil(try CameraLensIdentity.read(from: ["imageIOXMP": Data(xml.replacingOccurrences(of: "<aux:Lens>Photato Test Lens 24mm</aux:Lens>", with: "").utf8)]))
    for bad in ["0/1", "1/0", "NaN", "-24/1"] {
      XCTAssertThrowsError(try CameraLensIdentity.read(from: ["imageIOXMP": Data(xml.replacingOccurrences(of: "24/1", with: bad).utf8)]), bad)
    }
  }
  func testStrictIdentityCanonicalKeyAndCorruptBoundedMetadata() throws {
    let a = try CameraLensIdentity(cameraMake: "Café", cameraModel: "Model", lensModel: "Lens", focalLength: 24, fNumber: 2.8)
    let b = try CameraLensIdentity(cameraMake: "Cafe\u{301}", cameraModel: "Model", lensModel: "Lens", focalLength: 24, fNumber: 2.8)
    XCTAssertEqual(a, b); XCTAssertEqual(a.matchingKey, b.matchingKey)
    XCTAssertNotEqual(a.matchingKey, try CameraLensIdentity(cameraMake: "café", cameraModel: "Model", lensModel: "Lens", focalLength: 24, fNumber: 2.8).matchingKey)
    for s in ["", String(repeating: "a", count: 257), "bad\nname"] {
      XCTAssertThrowsError(try CameraLensIdentity(cameraMake: s, cameraModel: "M", lensModel: "L", focalLength: 24, fNumber: 2.8))
    }
    for n in [0, -1, Double.nan, .infinity] {
      XCTAssertThrowsError(try CameraLensIdentity(cameraMake: "A", cameraModel: "M", lensModel: "L", focalLength: n, fNumber: 2.8))
    }
    for source in [["imageIOProperties": Data([0,1,2])], ["imageIOXMP": Data("broken".utf8)],
      ["psdResources": Data("8BIM".utf8)], ["imageIOProperties": Data(repeating: 0, count: 16*1024*1024+1)]] {
      XCTAssertThrowsError(try CameraLensIdentity.read(from: source))
    }
    let properties: [String: Any] = ["{TIFF}": ["Make": "A", "Model": "M"], "{Exif}": ["LensModel": "L", "FocalLength": true, "FNumber": 2.8]]
    XCTAssertThrowsError(try CameraLensIdentity.read(from: ["imageIOProperties": PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)]))
  }
}
