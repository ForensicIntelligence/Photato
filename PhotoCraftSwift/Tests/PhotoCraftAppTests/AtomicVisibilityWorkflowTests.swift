import AppKit
import Darwin
import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class AtomicVisibilityWorkflowTests: XCTestCase {
  func hidden(_ url: URL) throws -> Bool {
    var value = stat()
    guard lstat(url.path, &value) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return value.st_flags & UInt32(UF_HIDDEN) != 0
  }

  func testEveryPreparedFormatPreservesDestinationVisibilityAndExactBytes() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = try DocumentSaveWorkflowTests().fixture()
    for format in DocumentIO.Format.allCases where format != .exr { // Existing8-bit fixture; EXR has dedicated32-bit workflow coverage.
      let expected = try DocumentIO.encodeForPersistence(model, format: format)
      for initial in [false, true] {
        let target = folder.appendingPathComponent("\(initial).\(format.rawValue)")
        try Data([9]).write(to: target)
        XCTAssertEqual(chflags(target.path, initial ? UInt32(UF_HIDDEN) : 0), 0)
        let link = folder.appendingPathComponent(target.lastPathComponent + "-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try DocumentIO.prepareOutput(model, format: format, persistence: true).write(to: link)
        XCTAssertEqual(try Data(contentsOf: target), expected, format.rawValue)
        XCTAssertEqual(try hidden(target), initial, format.rawValue)
        XCTAssertEqual(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
      }
    }
  }

  @MainActor func testNativeSaveAsPreservesExistingVisibilityAndPublishesNewVisibleFiles() async throws {
    _ = NSApplication.shared
    let helper = DocumentSaveWorkflowTests(), folder = try helper.directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for format in DocumentIO.Format.allCases where format != .exr { // Existing8-bit fixture; EXR has dedicated32-bit workflow coverage.
      for initial in [nil, false, true] as [Bool?] {
        let target = folder.appendingPathComponent("\(String(describing: initial)).\(format.rawValue)")
        if let initial {
          try Data([9]).write(to: target)
          XCTAssertEqual(chflags(target.path, initial ? UInt32(UF_HIDDEN) : 0), 0)
        }
        let model = try helper.fixture(), document = CraftNSDocument(model: model)
        defer { document.close() }
        let beforeHistory = document.store.session.undoStack.count
        try await helper.save(document, to: target, format: format)
        XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encodeForPersistence(model, format: format))
        XCTAssertEqual(try hidden(target), initial ?? false)
        XCTAssertEqual(document.store.document, model)
        XCTAssertEqual(document.store.session.undoStack.count, beforeHistory)
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(document.fileURL, target)
        try document.store.executeEditorCommand(
          .fill(try XCTUnwrap(document.store.document.activeLayerID), .white))
        let edited = document.store.document
        try await helper.save(document, to: target, format: format, operation: .saveOperation)
        XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encodeForPersistence(edited, format: format))
        XCTAssertEqual(try hidden(target), initial ?? false)
        await document.store.undo()
        XCTAssertEqual(document.store.document, model)
        await document.store.redo()
        XCTAssertEqual(document.store.document, edited)
      }
    }
  }

  @MainActor func testNativeSaveCopyRetainsVisibilityWithoutChangingOwnership() async throws {
    _ = NSApplication.shared
    let helper = DocumentSaveWorkflowTests(), folder = try helper.directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = try helper.fixture(), document = CraftNSDocument(model: model)
    defer { document.close() }
    for format in DocumentIO.Format.allCases where format != .exr { // Existing8-bit fixture; EXR has dedicated32-bit workflow coverage.
      let target = folder.appendingPathComponent("hidden-copy.\(format.rawValue)")
      try Data([9]).write(to: target)
      XCTAssertEqual(chflags(target.path, UInt32(UF_HIDDEN)), 0)
      try await document.persistDocument(to: target, format: format, operation: .saveToOperation)
      XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encodeForPersistence(model, format: format))
      XCTAssertTrue(try hidden(target))
      XCTAssertNil(document.fileURL)
      XCTAssertEqual(document.store.document, model)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testHTTPFileSavesMatchNativeVisibilityBytesStateAndCapabilities() async throws {
    let helper = AutomationTests(), folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try document.store.executeEditorCommand(
        .fill(try XCTUnwrap(document.store.document.activeLayerID), .white))
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder)
      try service.share(document)
      let model = document.store.document, history = document.store.session.undoStack.count
      for format in DocumentIO.Format.allCases where format != .exr { // Existing8-bit fixture; EXR has dedicated32-bit workflow coverage.
        for initial in [nil, false, true] as [Bool?] {
          let name = initial.map { $0 ? "hidden" : "visible" } ?? "new"
          let target = folder.appendingPathComponent("\(name).\(format.rawValue)")
          if let initial {
            try Data([9]).write(to: target)
            XCTAssertEqual(chflags(target.path, initial ? UInt32(UF_HIDDEN) : 0), 0)
          }
          let status = try await helper.edit(service, document, "document.saveAs",
            ["name": name, "format": format.rawValue, "replace": initial != nil])
          XCTAssertEqual(status, 200, target.lastPathComponent)
          XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encodeForPersistence(model, format: format))
          XCTAssertEqual(try hidden(target), initial ?? false, target.lastPathComponent)
          XCTAssertEqual(document.store.document, model)
          XCTAssertEqual(document.store.session.undoStack.count, history)
        }
      }
      let response = try await helper.request(service, path: "/v1/capabilities")
      XCTAssertEqual(response.0.statusCode, 200)
      let caps = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let persistence = try XCTUnwrap(caps["atomicPersistence"] as? [String: Any])
      let visibility = try XCTUnwrap(persistence["visibility"] as? [String: Any])
      XCTAssertEqual(visibility["newFileHiddenFlag"] as? Bool, false)
      XCTAssertEqual(visibility["preservesExistingHiddenFlag"] as? Bool, true)
      XCTAssertEqual(visibility["preservesOtherStagingFlags"] as? Bool, true)
    }
  }
}
