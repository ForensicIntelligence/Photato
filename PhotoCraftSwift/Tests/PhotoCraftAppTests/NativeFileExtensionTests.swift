import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class NativeFileExtensionTests: XCTestCase {
  @MainActor func testPreferredExtensionRegistrationAndCopyDefaults() throws {
    _ = NSApplication.shared
    let doc = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 4, height: 3))
    defer { doc.close() }
    for operation in [
      NSDocument.SaveOperationType.saveOperation, .saveAsOperation, .saveToOperation,
    ] {
      XCTAssertEqual(
        doc.fileNameExtension(forType: CraftNSDocument.nativeType, saveOperation: operation),
        "photato")
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Legacy copy.pcswift"
    let accessory = DocumentCopyAccessory(panel: panel, initial: .native)
    XCTAssertEqual(accessory.format, .native)
    XCTAssertEqual(panel.nameFieldStringValue, "Legacy copy.photato")
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let info = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: root.appendingPathComponent("scripts/Info.plist")), format: nil
      ) as? [String: Any])
    let types = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
    XCTAssertEqual(types[0]["CFBundleTypeExtensions"] as? [String], ["photato", "pcswift"])
    let exported = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
    let tags = try XCTUnwrap(exported[0]["UTTypeTagSpecification"] as? [String: Any])
    XCTAssertEqual(tags["public.filename-extension"] as? [String], ["photato", "pcswift"])
  }

  @MainActor func testNewAndLegacyNativeFilesOpenSaveAndRevert() async throws {
    _ = NSApplication.shared
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = try EditableLifecycleModel.make(width: 4, height: 3)
    let bytes = try NativeArchive.encode(original)
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    for ext in ["photato", "PHOTATO", "pcswift", "PCSWIFT"] {
      let source = folder.appendingPathComponent("source." + ext)
      try bytes.write(to: source)
      XCTAssertEqual(try DocumentIO.read(source), original)
      let doc = try XCTUnwrap(
        controller.makeDocument(withContentsOf: source, ofType: CraftNSDocument.nativeType)
          as? CraftNSDocument)
      defer { doc.close() }
      XCTAssertEqual(doc.fileURL, source)
      XCTAssertNil(doc.importedSourceURL)
      try doc.store.executeEditorCommand(.opacity(original.layers[0].id, 0.25))
      try await doc.revertDocument()
      XCTAssertEqual(doc.store.document, original)
      try doc.store.executeEditorCommand(.opacity(original.layers[0].id, 0.75))
      let target = folder.appendingPathComponent("saved-" + ext + ".photato")
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        doc.save(to: target, ofType: CraftNSDocument.nativeType, for: .saveAsOperation) { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
      }
      XCTAssertEqual(doc.fileURL, target)
      XCTAssertFalse(doc.isDocumentEdited)
      XCTAssertEqual(try DocumentIO.read(target), doc.store.document)
      XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
  }

  @MainActor func testAPIDownloadAliasAndRevertUseTheNativeArchive() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, doc in
      service.setDocumentTransfersEnabled(true)
      try service.share(doc)
      let share = try XCTUnwrap(service.shares.first)
      let path = "/v1/documents/\(share.id)"
      let native = try await AutomationTests().request(service, path: path + "/file.photato")
      let legacy = try await AutomationTests().request(service, path: path + "/file.pcswift")
      XCTAssertEqual(native.0.statusCode, 200)
      XCTAssertEqual(legacy.0.statusCode, 200)
      XCTAssertEqual(native.1, legacy.1)
      XCTAssertEqual(try NativeArchive.decode(native.1), doc.store.document)
      XCTAssertEqual(service.state(share, document: doc)["persistenceFormat"] as? String, "photato")
      let download = try XCTUnwrap(
        AutomationService.documentTransferCapabilities["download"] as? [String: Any])
      XCTAssertEqual(download["formatAliases"] as? [String: String], ["pcswift": "photato"])
      XCTAssertTrue((download["formats"] as? [String])?.contains("photato") == true)
      let original = doc.store.document
      for ext in ["photato", "pcswift"] {
        let source = folder.appendingPathComponent("source." + ext)
        try NativeArchive.encode(original).write(to: source)
        doc.fileURL = source
        try doc.store.executeEditorCommand(.opacity(original.layers[0].id, 0.25))
        let reply = try await AutomationTests().request(
          service, path: path + "/commands",
          body: [
            "command": "document.revert", "revision": service.revision(doc.store),
            "parameters": [:],
          ])
        XCTAssertEqual(reply.0.statusCode, 200, String(decoding: reply.1, as: UTF8.self))
        XCTAssertEqual(doc.store.document, original)
      }
    }
  }
}
