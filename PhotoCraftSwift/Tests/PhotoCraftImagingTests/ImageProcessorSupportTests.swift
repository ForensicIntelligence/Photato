import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ImageProcessorSupportTests: XCTestCase {
  func testCopyrightReplacesPriorRightsAndRetainsCameraAndCustomMetadata() throws {
    let source = try RasterIO.read(MetadataPreservationTests().source()),snapshot = source
    let output = try CopyrightMetadata.applying("© 2026 Owned test artwork",to:source)
    let updatedXMP = try XCTUnwrap(RasterMetadata.xmpData(output.sourceMetadata))
    let metadata = try XCTUnwrap(CGImageMetadataCreateFromXMPData(updatedXMP as CFData))
    XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(metadata,nil,"dc:rights[x-default]" as CFString) as String?,"© 2026 Owned test artwork")
    for type in [UTType.jpeg,.tiff] {
      let bytes = try RasterIO.encoded(output,type:type),decoded = try RasterIO.read(bytes)
      let text = String(decoding:try XCTUnwrap(RasterMetadata.xmpData(decoded.sourceMetadata)),as:UTF8.self)
      XCTAssertTrue(text.contains("Owned test artwork"));XCTAssertFalse(text.contains("Original test metadata"));XCTAssertTrue(text.contains("original-value"));XCTAssertTrue(text.contains("Photato test author"))
    }
    let psd = try PSDCodec.read(PSDCodec.writeRasterLayers(output))
    XCTAssertTrue(String(decoding:try XCTUnwrap(RasterMetadata.xmpData(psd.sourceMetadata)),as:UTF8.self).contains("Owned test artwork"))
    XCTAssertEqual(source,snapshot)
    var localized = source
    localized.sourceMetadata?["imageIOXMP"] = MetadataPreservationTests().xmp
    let localizedMetadata = try XCTUnwrap(CGImageMetadataCreateFromXMPData(MetadataPreservationTests().xmp as CFData))
    let mutable = try XCTUnwrap(CGImageMetadataCreateMutableCopy(localizedMetadata))
    XCTAssertTrue(CGImageMetadataSetValueWithPath(mutable,nil,"dc:rights[fr]" as CFString,"Droits existants" as CFString))
    localized.sourceMetadata?["imageIOXMP"] = try XCTUnwrap(CGImageMetadataCreateXMPData(mutable,nil) as Data?)
    let replaced = try CopyrightMetadata.applying("Default updated",to:localized)
    let replacedMetadata = try XCTUnwrap(CGImageMetadataCreateFromXMPData(try XCTUnwrap(RasterMetadata.xmpData(replaced.sourceMetadata)) as CFData))
    XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(replacedMetadata,nil,"dc:rights[x-default]" as CFString) as String?,"Default updated")
    XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(replacedMetadata,nil,"dc:rights[fr]" as CFString) as String?,"Droits existants")
  }
  func testCopyrightCreatesMetadataAndRejectsInvalidText() throws {
    let source = try CraftDocument(width:2,height:2)
    let output = try CopyrightMetadata.applying("Original © example",to:source)
    XCTAssertTrue(String(decoding:try XCTUnwrap(output.sourceMetadata?["imageIOXMP"]),as:UTF8.self).contains("Original"))
    XCTAssertThrowsError(try CopyrightMetadata.applying(String(repeating:"x",count:4097),to:source))
    XCTAssertThrowsError(try CopyrightMetadata.applying("bad\0text",to:source))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(output)),output)
  }
  func testExplicitNestedZIPPathsRejectTraversalAndPreservePayloads() throws {
    let files = [StoredZIP.File(name:"JPEG/owned.jpg",data:Data([1,2,3])),.init(name:"TIFF/séquence.tiff",data:Data([4,5,6]))]
    XCTAssertThrowsError(try StoredZIP.encode(files,maximumBytes:4096))
    let bytes = try StoredZIP.encode(files,maximumBytes:4096,allowSubdirectories:true),archive = try PcraftZIP(bytes)
    for file in files {XCTAssertEqual(try archive.read(file.name),file.data)}
    for name in ["../escape","JPEG/../escape","/absolute","JPEG//empty","JPEG/./file","JPEG/","C:/file","JPEG/\\escape","a\0b"] {XCTAssertThrowsError(try StoredZIP.encode([.init(name:name,data:Data())],maximumBytes:4096,allowSubdirectories:true),name)}
  }
}
