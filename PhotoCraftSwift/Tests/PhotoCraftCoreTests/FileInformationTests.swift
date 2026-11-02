import Foundation
import XCTest
@testable import PhotoCraftCore

final class FileInformationTests: XCTestCase {
  func testMetadataHistoryPreservesPixelsSelectionAndLayerProtection() throws {
    let base = try CraftDocument(width: 5, height: 3)
    var documents = try [PixelDepth.u8, .u16, .f32].map { try CraftDocument(width: 5, height: 3, depth: $0) }
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      documents.append(try base.convertingMode(.init(mode: mode, depth: .u8)))
    }
    documents.append(try base.replacingRestrictedMode(.indexed(IndexedRaster(width: 5, height: 3, palette: [.init(0,0,0), .init(255,255,255)], indices: Data(repeating: 0, count: 15)))))
    documents.append(try base.replacingRestrictedMode(.bitmap(BitmapRaster(width: 5, height: 3, bits: Data(repeating: 0, count: 3)))))
    for var document in documents {
      document.layers[0].locked = true; document.selection = .init(x: 1, y: 1, width: 2, height: 1)
      var session = EditorSession(document: document)
      try session.execute(.documentMetadata(["owned": Data([1, 2, 3])]))
      let edited = session.document; XCTAssertEqual(edited.layers, document.layers); XCTAssertEqual(edited.selection, document.selection)
      XCTAssertEqual(Command.documentMetadata(nil).label, "File Info")
      try session.undo(); XCTAssertEqual(session.document, document)
      try session.redo(); XCTAssertEqual(session.document, edited)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edited)), edited)
    }
  }
  func testMetadataAdmissionAndFieldValidationAreAtomic() throws {
    var document = try CraftDocument(width: 2, height: 2); let before = document
    XCTAssertThrowsError(try Command.documentMetadata([String(repeating: "x", count: 4097): Data()]).apply(to: &document))
    XCTAssertEqual(document, before)
    var info = FileInformation(); info.title = "New title"; XCTAssertEqual(info.changedFields(from: .init()), ["title"])
    info.keywords = Array(repeating: "x", count: 257); XCTAssertThrowsError(try info.validate())
  }
}
