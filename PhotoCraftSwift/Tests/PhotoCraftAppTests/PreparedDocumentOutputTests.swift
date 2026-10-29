import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class PreparedDocumentOutputTests: XCTestCase {
  func testPreparedFileLifetimeAndCopyAreBoundedAndByteIdentical() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = try DocumentSaveWorkflowTests().fixture(depth: .f32)
    for format in [DocumentIO.Format.native, .psd, .psb] {
      let stagedDirectory: URL
      do {
        let prepared = try DocumentIO.prepareOutput(model, format: format, persistence: true)
        guard case .file(let file) = prepared else { return XCTFail("Expected staged file") }
        stagedDirectory = file.directory
        let target = folder.appendingPathComponent(format.rawValue)
        try prepared.write(to: target)
        XCTAssertEqual(prepared.count, try Data(contentsOf: target).count)
        XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(model, format: format))
      }
      XCTAssertFalse(FileManager.default.fileExists(atPath: stagedDirectory.path))
    }
  }
  @MainActor func testPreparedFileLimitFailureKeepsSaveStateAndSource() async throws {
    _ = NSApplication.shared
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let document = CraftNSDocument(model: try DocumentSaveWorkflowTests().fixture())
    defer { document.close() }
    let target = folder.appendingPathComponent("existing.psb")
    try Data([9, 8, 7]).write(to: target)
    try document.store.executeEditorCommand(
      .renameLayer(
        try XCTUnwrap(document.store.document.activeLayerID), "Changed"))
    let before = document.store.document
    do {
      try await document.persistDocument(
        to: target, format: .psb, operation: .saveAsOperation,
        maximumPreparedBytes: 1)
      XCTFail("Exceeded API output budget")
    } catch let error as AutomationFailure { XCTAssertEqual(error.status, 413) }
    XCTAssertEqual(try Data(contentsOf: target), Data([9, 8, 7]))
    XCTAssertEqual(document.store.document, before)
    XCTAssertNil(document.fileURL)
    XCTAssertNil(document.preparedSaveOutput)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertFalse(document.fileOperationBusy)
  }
}

extension PreparedDocumentOutputTests {
  @MainActor func testUnpreparedNativeAutosaveLeafPreservesDocumentAndHistory() throws {
    _ = NSApplication.shared
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let document = CraftNSDocument(model: try DocumentSaveWorkflowTests().fixture(depth: .f32))
    defer { document.close() }
    try document.store.executeEditorCommand(
      .renameLayer(try XCTUnwrap(document.store.document.activeLayerID), "Recovery"))
    let model = document.store.document
    let revision = document.store.revision
    let history = document.store.session.undoStack.count
    let target = folder.appendingPathComponent("recovery.photato")
    try document.write(to: target, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(model, format: .native))
    XCTAssertEqual(try DocumentIO.read(target), model)
    let noExtension = folder.appendingPathComponent("recovery-snapshot")
    try FileManager.default.copyItem(at: target, to: noExtension)
    let recovered = CraftNSDocument(model: try CraftDocument(width: 1, height: 1))
    defer { recovered.close() }
    try recovered.read(from: noExtension, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(recovered.store.document, model)
    XCTAssertTrue(recovered.store.session.undoStack.isEmpty)
    XCTAssertFalse(recovered.isDocumentEdited)
    try Data([0]).write(to: noExtension)
    XCTAssertThrowsError(try recovered.read(from: noExtension, ofType: CraftNSDocument.nativeType))
    XCTAssertEqual(recovered.store.document, model)
    XCTAssertEqual(document.store.document, model)
    XCTAssertEqual(document.store.revision, revision)
    XCTAssertEqual(document.store.session.undoStack.count, history)
    XCTAssertNil(document.fileURL)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertThrowsError(try document.write(to: folder, ofType: CraftNSDocument.nativeType))
    XCTAssertEqual(document.store.document, model)
  }
}
