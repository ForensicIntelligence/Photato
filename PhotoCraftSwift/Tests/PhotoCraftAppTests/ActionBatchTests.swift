import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ActionBatchTests: XCTestCase {
  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
  }
  func action() -> RecordedAction { .init(name: "Black", steps: [.init(name: "Fill", operation: .fill(.active, .black))]) }
  @MainActor func testFilesAndSnapshotsProduceIndependentCopiesWithPerFileErrors() async throws {
    let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
    let model = try CraftDocument(width: 5, height: 4, name: "Source")
    let input = root.appendingPathComponent("input.photato"), bytes = try NativeArchive.encodeChunked(model)
    try bytes.write(to: input)
    let sources = [ActionBatchSource(url: input), .init(url: root.appendingPathComponent("missing.png")), .init(document: model)]
    let results = try await ActionBatch.run(sources: sources, action: action(), destination: root, format: .native)
    XCTAssertEqual(results.count, 3); XCTAssertEqual(results.filter { $0.output != nil }.count, 2); XCTAssertNotNil(results[1].error)
    XCTAssertEqual(try Data(contentsOf: input), bytes)
    for result in results where result.output != nil {
      let output = try DocumentIO.read(root.appendingPathComponent(result.output!))
      var expected = model; try action().apply(to: &expected)
      XCTAssertEqual(output, expected)
    }
    let again = try await ActionBatch.run(sources: sources, action: action(), destination: root, format: .native)
    XCTAssertTrue(again.allSatisfy { $0.error != nil }); XCTAssertFalse(again.contains { $0.output != nil })
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".photato-batch-") })
  }
  @MainActor func testCancellationAndRevocationPreserveCompletedCopies() async throws {
    let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
    let source = ActionBatchSource(document: try CraftDocument(width: 2, height: 2))
    let sources = [source, source, source], action = action()
    let task = Task { @MainActor in
      try await ActionBatch.run(sources: sources, action: action, destination: root, format: .png, progress: { results in
        if results.count == 1 { withUnsafeCurrentTask { $0?.cancel() } }
      })
    }
    let results = try await task.value
    XCTAssertNotNil(results[0].output); XCTAssertTrue(results[1].cancelled); XCTAssertTrue(results[2].cancelled)
    var validations = 0
    let revoked = try await ActionBatch.run(sources: sources, action: action, destination: root, format: .png, suffix: "-revoked", validatePublication: {
      validations += 1; if validations >= 3 { throw CraftError.invalid("Revoked") }
    })
    XCTAssertNotNil(revoked[0].output); XCTAssertTrue(revoked[1].cancelled); XCTAssertTrue(revoked[2].cancelled)
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".photato-batch-") })
  }
  @MainActor func testStopOnErrorAndOutputBounds() async throws {
    let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
    let sources = [ActionBatchSource(url: root.appendingPathComponent("missing.png")), .init(document: try CraftDocument(width: 2, height: 2))]
    let results = try await ActionBatch.run(sources: sources, action: action(), destination: root, format: .png, stopOnError: true)
    XCTAssertNotNil(results[0].error); XCTAssertTrue(results[1].cancelled)
    XCTAssertThrowsError(try ActionBatch.outputName("test", index: 0, suffix: "../escape", format: .png))
    XCTAssertFalse(try ActionBatch.outputName("../../escape", index: 0, suffix: "", format: .png).contains("/"))
    var resized = action(); resized.steps.insert(.init(name: "Large", operation: .imageSize(10, 10, 72, .nearest)), at: 0)
    let bounded = try await ActionBatch.run(sources: [.init(document: try CraftDocument(width: 2, height: 2))], action: resized, destination: root, format: .png, validateOutput: { document in
      guard document.width * document.height <= 4 else { throw CraftError.invalid("Too large") }
    })
    XCTAssertNil(bounded[0].output); XCTAssertNotNil(bounded[0].error)
  }
  @MainActor func testAPIBatchPermissionAndSharedSourceParity() async throws {
    let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
    let library = ActionLibrary(), action = action(); try library.save(action)
    let helper = AutomationTests()
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let source = document.store.document, id = try XCTUnwrap(service.shares.first?.id)
      let parameters: [String: Any] = ["actionID": action.id.uuidString, "sources": [["id": id.uuidString, "revision": service.revision(document.store)]], "format": "photato"]
      let forbidden = try await helper.edit(service, document, "actions.batch", parameters); XCTAssertEqual(forbidden, 403)
      service.setDocumentSavesEnabled(true); service.setSaveDirectory(root)
      let response = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "actions.batch", "revision": service.revision(document.store), "parameters": parameters])
      XCTAssertEqual(response.0.statusCode, 200)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any]); XCTAssertEqual(body["completed"] as? Int, 1)
      let result = try XCTUnwrap((body["results"] as? [[String: Any]])?.first), filename = try XCTUnwrap(result["output"] as? String)
      var expected = source; try action.apply(to: &expected)
      XCTAssertEqual(try DocumentIO.read(root.appendingPathComponent(filename)), expected)
      XCTAssertEqual(document.store.document, source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertNil(service.actionBatchTask)
      let cancel = try await helper.edit(service, document, "actions.batch.cancel", ["operationID": UUID().uuidString]); XCTAssertEqual(cancel, 409)
    }
  }
  @MainActor func testNativeBatchPanelAndMenus() throws {
    _ = NSApplication.shared
    let delegate = AppDelegate(workspaces: WorkspaceLibrary()); delegate.installPhotoshopMenus()
    let library = ActionLibrary(); try library.save(action())
    let model = BatchWorkspace(controller: delegate.controller, library: library)
    model.sources = [.init(document: try CraftDocument(width: 3, height: 2, name: "Example"))]
    let view = NSHostingView(rootView: BatchPanel(model: model)); view.frame = NSRect(x: 0, y: 0, width: 680, height: 620); view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width, 500)
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: bitmap)
      if let png = bitmap.representation(using: .png, properties: [:]) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try png.write(to: root.appendingPathComponent("artifacts/batch-offscreen.png"))
      }
    }
    let actions = NSMenuItem(title: "Actions", action: #selector(AppDelegate.showActions), keyEquivalent: "")
    let batch = NSMenuItem(title: "Batch…", action: #selector(AppDelegate.showBatch), keyEquivalent: "")
    XCTAssertTrue(delegate.validateMenuItem(actions)); XCTAssertTrue(delegate.validateMenuItem(batch))
  }
}
