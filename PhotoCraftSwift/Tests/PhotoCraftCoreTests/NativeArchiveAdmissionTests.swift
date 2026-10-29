import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeArchiveAdmissionTests: XCTestCase {
  func temporary() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("NativeAdmission-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  func rasterDocument() throws -> CraftDocument {
    var model = try CraftDocument(width: 128, height: 64)
    var pixels = try Surface(width: 128, height: 64)
    pixels.setPixel(x: 0, y: 0, .white)
    pixels.setPixel(x: 65, y: 0, .white)
    model.layers[0].content = .raster(pixels)
    return model
  }
  func testManifestLimitRejectsBeforeReadingTheManifestBuffer() throws {
    let data = try NativeArchive.encodeChunked(rasterDocument())
    var ranges: [(Int, Int)] = []
    XCTAssertThrowsError(try NativeChunkedArchive.manifest(count: data.count, maximumMetadataBytes: 0) {
      offset, count in
      ranges.append((offset, count))
      return data.subdata(in: offset..<offset + count)
    }) { error in
      guard let failure = error as? NativeArchiveMemoryLimit,
        case .metadata(let required, let limit) = failure else {
        return XCTFail("Expected metadata admission failure: \(error)")
      }
      XCTAssertGreaterThan(required, 0); XCTAssertEqual(limit, 0)
    }
    XCTAssertEqual(ranges.map(\.1), [NativeChunkedArchive.header.count, NativeChunkedArchive.footerSize])
  }
  func testRasterLimitHasCumulativeTypedAccountingForLegacyAndChunkedArchives() throws {
    let model = try rasterDocument(), tile = Surface.tileSide * Surface.tileSide * MemoryLayout<Pixel>.stride
    for data in [try NativeArchive.encode(model), try NativeArchive.encodeChunked(model)] {
      XCTAssertThrowsError(try NativeArchive.decode(data, rasterByteLimit: tile)) { error in
        XCTAssertEqual(error as? NativeArchiveMemoryLimit, .raster(requiredBytes: tile * 2, limitBytes: tile))
      }
      XCTAssertEqual(try NativeArchive.decode(data, rasterByteLimit: tile * 2), model)
      XCTAssertThrowsError(try NativeArchive.decode(data, rasterByteLimit: -1)) { error in
        XCTAssertNil(error as? NativeArchiveMemoryLimit, "Invalid caller limits are not capacity deferrals")
      }
    }
  }
  func testMetadataInspectionAndBoundedReadPreserveExactContextAndOutput() throws {
    let folder = try temporary()
    let url = folder.appendingPathComponent("recovery.photato"), model = try rasterDocument()
    let context = Data("opaque recovery fixture".utf8)
    try NativeArchive.writeRecovery(model, context: context, to: url)
    let original = try Data(contentsOf: url)
    let metadata = try XCTUnwrap(NativeArchive.readRecoveryMetadata(url))
    XCTAssertEqual(metadata.context, context); XCTAssertFalse(metadata.invalidContext)
    XCTAssertEqual(metadata.width, 128); XCTAssertEqual(metadata.height, 64)
    let bounded = try NativeArchive.readRecovery(url, maximumMetadataBytes: metadata.manifestBytes)
    XCTAssertEqual(bounded.document, model); XCTAssertEqual(bounded.context, context)
    XCTAssertThrowsError(try NativeArchive.readRecovery(url, maximumMetadataBytes: metadata.manifestBytes - 1)) {
      XCTAssertEqual($0 as? NativeArchiveMemoryLimit,
        .metadata(requiredBytes: metadata.manifestBytes, limitBytes: metadata.manifestBytes - 1))
    }
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertEqual(try NativeArchive.encodeChunked(bounded.document), try NativeArchive.encodeChunked(model))
    try NativeArchive.encode(model).write(to: url)
    XCTAssertNil(try NativeArchive.readRecoveryMetadata(url))
    XCTAssertThrowsError(try NativeArchive.readRecovery(url, maximumMetadataBytes: 0)) {
      guard let failure = $0 as? NativeArchiveMemoryLimit,
        case .metadata = failure else { return XCTFail("\($0)") }
    }
    XCTAssertEqual(try NativeArchive.read(url), model)
  }
  func testInvalidHeaderAndCorruptManifestAreNotMemoryDeferrals() throws {
    let folder = try temporary(), url = folder.appendingPathComponent("bad")
    var data = try NativeArchive.encodeChunked(rasterDocument())
    data[data.count - 1] ^= 1
    try data.write(to: url)
    XCTAssertThrowsError(try NativeArchive.readRecoveryMetadata(url)) {
      XCTAssertNil($0 as? NativeArchiveMemoryLimit)
    }
    data[8] ^= 1
    try data.write(to: url)
    XCTAssertThrowsError(try NativeArchive.readRecoveryMetadata(url, maximumMetadataBytes: 0)) {
      XCTAssertNil($0 as? NativeArchiveMemoryLimit)
    }
  }
  func testLightweightMetadataDoesNotClaimToValidateRasterContents() throws {
    let folder = try temporary(), url = folder.appendingPathComponent("bad-blob")
    var data = try NativeArchive.encodeChunked(rasterDocument())
    data[NativeChunkedArchive.header.count] ^= 1
    try data.write(to: url)
    XCTAssertNotNil(try NativeArchive.readRecoveryMetadata(url))
    XCTAssertThrowsError(try NativeArchive.readRecovery(url)) {
      XCTAssertNil($0 as? NativeArchiveMemoryLimit)
    }
  }
}
