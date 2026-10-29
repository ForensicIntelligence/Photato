import Foundation
import XCTest
@testable import PhotoCraftCore

final class RecoveryArchiveContextTests: XCTestCase {
  func testRecoveryContextSharesIntegrityAndDoesNotLeakIntoOrdinarySerialization() throws {
    let folder = try NativeChunkedArchiveTests().temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("snapshot")
    let model = try HistoryScratchTests().document()
    let plain = try NativeArchive.encodeChunked(model)
    let context = Data("private recovery source information".utf8)
    try NativeArchive.writeRecovery(model, context: context, to: url)
    let recovered = try NativeArchive.readRecovery(url)
    XCTAssertEqual(recovered.document, model)
    XCTAssertEqual(recovered.context, context)
    XCTAssertEqual(try NativeArchive.readRecoveryContext(url), context)
    XCTAssertFalse(recovered.invalidContext)
    XCTAssertEqual(try NativeArchive.read(url), model)
    XCTAssertEqual(try NativeArchive.decode(Data(contentsOf: url)), model)
    XCTAssertEqual(try NativeArchive.encodeChunked(recovered.document), plain)
    try NativeArchive.writeRecovery(model, context: nil, to: url)
    XCTAssertEqual(try Data(contentsOf: url), plain)
  }
  func testInvalidOptionalContextPreservesPixelsButNeverReturnsUsableContext() throws {
    let folder = try NativeChunkedArchiveTests().temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = try CraftDocument(width: 3, height: 2)
    let plain = try NativeArchive.encodeChunked(model)
    let url = folder.appendingPathComponent("snapshot")
    for bad: Any in ["wrong type", 23, Data(count: NativeArchive.maximumRecoveryContextBytes + 1)] {
      let data = try NativeChunkedArchiveTests().changedManifest(plain) { $0["recoveryContext"] = bad }
      try data.write(to: url)
      let recovered = try NativeArchive.readRecovery(url)
      XCTAssertEqual(recovered.document, model)
      XCTAssertNil(recovered.context)
      XCTAssertNil(try NativeArchive.readRecoveryContext(url))
      XCTAssertTrue(recovered.invalidContext)
      XCTAssertEqual(try NativeArchive.decode(data), model)
    }
  }
  func testContextLimitRejectsBeforePublicationAndLegacyArchivesRemainRecoverable() throws {
    let folder = try NativeChunkedArchiveTests().temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = try CraftDocument(width: 2, height: 1)
    let url = folder.appendingPathComponent("snapshot")
    let legacy = try NativeArchive.encode(model)
    try legacy.write(to: url)
    XCTAssertThrowsError(try NativeArchive.writeRecovery(model,
      context: Data(count: NativeArchive.maximumRecoveryContextBytes + 1), to: url))
    XCTAssertEqual(try Data(contentsOf: url), legacy)
    let recovered = try NativeArchive.readRecovery(url)
    XCTAssertEqual(recovered.document, model)
    XCTAssertNil(recovered.context)
    XCTAssertNil(try NativeArchive.readRecoveryContext(url))
    XCTAssertFalse(recovered.invalidContext)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["snapshot"])
  }
}
