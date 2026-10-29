import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class DocumentEncodingOptionsTests: XCTestCase {
  @MainActor func fixture() throws -> (CraftDocumentController, CraftNSDocument, URL) {
    _ = NSApplication.shared
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let c = RecoveryIndexTests().controller(RecoveryIndexStore(directoryURL: folder.appendingPathComponent("Recovery")))
    let doc = CraftNSDocument(model: try DocumentSaveWorkflowTests().fixture())
    c.addDocument(doc)
    return (c, doc, folder)
  }
  @MainActor func testNativeSavePanelOptionsReachAppKitAndSubsequentSave() async throws {
    let (c, doc, folder) = try fixture(); defer { doc.close(); _ = c }
    let panel = NSSavePanel()
    XCTAssertTrue(doc.prepareSavePanel(panel))
    let accessory = try XCTUnwrap(doc.saveAccessory)
    accessory.formats.selectItem(at: try XCTUnwrap(accessory.availableFormats.firstIndex(of: .png)))
    accessory.updateFormat()
    accessory.pngCompression.selectItem(at: 10); accessory.pngInterlaced.state = .on
    XCTAssertFalse(accessory.pngRow.isHidden); XCTAssertTrue(accessory.tiffRow.isHidden)
    let options = accessory.encodingOptions, model = doc.store.document
    let target = folder.appendingPathComponent("options.png")
    try await DocumentSaveWorkflowTests().save(doc, to: target, format: .png)
    XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(model, format: .png, options: options))
    XCTAssertEqual(doc.rememberedEncodingOptions[.png], options)
    XCTAssertFalse(doc.isDocumentEdited)
    try doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id, "Renamed"))
    let edited = doc.store.document
    // A cancelled Save As draft must not affect ordinary Save.
    accessory.pngCompression.selectItem(at: 1); accessory.pngInterlaced.state = .off
    try await DocumentSaveWorkflowTests().save(doc, to: target, format: .png, operation: .saveOperation)
    XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(edited, format: .png, options: options))
    XCTAssertEqual(doc.rememberedEncodingOptions[.png], options)
  }
  @MainActor func testCopyPreservesOwnershipHistoryAndRememberedSaveOptions() async throws {
    let (c, doc, folder) = try fixture(); defer { doc.close(); _ = c }
    let original = doc.store.document
    doc.updateChangeCount(.changeDone)
    doc.rememberedEncodingOptions[.png] = .init(pngCompression: 1)
    let history = doc.store.session.undoStack.count, target = folder.appendingPathComponent("copy.tiff")
    let options = RasterEncodingOptions(tiffCompression: .lzw)
    try await doc.copyDocument(to: target, format: .tiff, options: options)
    XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(original, format: .tiff, options: options))
    XCTAssertNil(doc.fileURL); XCTAssertTrue(doc.isDocumentEdited)
    XCTAssertEqual(doc.store.document, original); XCTAssertEqual(doc.store.session.undoStack.count, history)
    XCTAssertEqual(doc.rememberedEncodingOptions, [.png: .init(pngCompression: 1)])
  }
  @MainActor func testFailedSaveAndInvalidOptionsDoNotAdoptSettingsOrReplaceFile() async throws {
    let (c, doc, folder) = try fixture(); defer { doc.close(); _ = c }
    let target = folder.appendingPathComponent("preserved.png"), before = Data("Keep this file".utf8)
    try before.write(to: target)
    doc.rememberedEncodingOptions[.png] = .init(pngCompression: 2)
    for options in [RasterEncodingOptions(pngCompression: 9), .init(tiffCompression: .zip)] {
      do {
        try await doc.persistDocument(to: target, format: .png, operation: .saveAsOperation, options: options,
          encoder: { _, _ in throw CraftError.invalid("Owned encode failure") })
        XCTFail("Save unexpectedly succeeded")
      } catch {}
      XCTAssertEqual(try Data(contentsOf: target), before)
      XCTAssertEqual(doc.rememberedEncodingOptions[.png], .init(pngCompression: 2))
      XCTAssertNil(doc.fileURL); XCTAssertFalse(doc.fileOperationBusy)
    }
  }
  func testStrictOptionsAndBackwardCompatibleCommandSchemas() throws {
    let options: [String: Any] = ["pngCompression": 0, "pngInterlaced": true]
    let bytes = try JSONSerialization.data(withJSONObject: options)
    let parsed = try DocumentEncodingOptions.header(String(decoding: bytes, as: UTF8.self), format: .png)
    XCTAssertEqual(parsed, .init(pngCompression: 0, pngInterlaced: true))
    for raw in ["{\"pngCompression\":true}", "{\"pngCompression\":1.5}", "{\"pngCompression\":10}",
      "{\"unknown\":1}", "null", "[]", "{\"pngInterlaced\":1}", "{\"tiffCompression\":\"jpeg\"}"] {
      XCTAssertThrowsError(try DocumentEncodingOptions.header(raw, format: .png))
    }
    XCTAssertThrowsError(try DocumentEncodingOptions.header("{\"pngCompression\":1}", format: .psd))
    for parameters in [[:], ["options": options]] as [[String: Any]] {
      let command = try AutomationCommand(data: JSONSerialization.data(withJSONObject: [
        "command": "document.save", "revision": "owned", "parameters": parameters]))
      XCTAssertEqual(command.name, "document.save")
    }
    let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == "document.save" })
    let root = try XCTUnwrap(definition.schema["properties"] as? [String: Any])
    let schema = try XCTUnwrap(root["parameters"] as? [String: Any])
    XCTAssertEqual(schema["required"] as? [String], [])
  }
}
