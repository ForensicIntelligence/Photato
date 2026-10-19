import AppKit
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class WorkflowTests: XCTestCase {
  @MainActor func testNativeDocumentSaveAndReopenPreservesLayers() throws {
    let model = try CraftDocument(width: 12, height: 12)
    let doc = CraftNSDocument(model: model)
    doc.store.renderTask?.cancel()
    doc.store.addPixelLayer()
    let id = try XCTUnwrap(doc.store.document.activeLayerID)
    doc.store.perform(.stroke(id, [StrokePoint(x: 6, y: 6)], Brush()))
    doc.store.renderTask?.cancel()
    XCTAssertTrue(doc.isDocumentEdited)
    let data = try doc.data(ofType: CraftNSDocument.nativeType)
    let reopened = CraftNSDocument(model: model)
    try reopened.read(from: data, ofType: CraftNSDocument.nativeType)
    reopened.store.renderTask?.cancel()
    XCTAssertEqual(reopened.store.document, doc.store.document)
    XCTAssertEqual(reopened.store.document.layers.count, 2)
    XCTAssertThrowsError(try doc.data(ofType: "Raster Image"))
  }
  @MainActor func testRasterOpenAssociatesSourceButRejectsSavingAddedLayersToPNG() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: url) }
    try RasterIO.write(Surface(width: 3, height: 3, fill: .white), to: url)
    let original = try Data(contentsOf: url)
    let controller = CraftDocumentController()
    let doc = try XCTUnwrap(
      controller.makeDocument(withContentsOf: url, ofType: "Raster Image") as? CraftNSDocument)
    doc.store.renderTask?.cancel()
    defer { doc.close() }
    XCTAssertEqual(doc.fileURL, url)
    XCTAssertEqual(doc.persistenceFormat, .png)
    doc.store.addPixelLayer()
    doc.store.renderTask?.cancel()
    do {
      try await doc.persistDocument(to: url, format: .png, operation: .saveOperation)
      XCTFail("Saving PNG must not flatten newly added editable layers")
    } catch {}
    XCTAssertTrue(doc.isDocumentEdited)
    XCTAssertEqual(try Data(contentsOf: url), original)
  }
  @MainActor func testLayerSelectionAndUndoRedoFromStore() throws {
    let store = EditorStore(document: try CraftDocument(width: 5, height: 5))
    store.renderTask?.cancel()
    let before = store.document
    store.addPixelLayer()
    store.renderTask?.cancel()
    let selected = try XCTUnwrap(store.document.activeLayerID)
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, before)
    store.redo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.activeLayerID, selected)
  }
  @MainActor func testNativeControllerReopensNativeURL() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".pcswift")
    defer { try? FileManager.default.removeItem(at: url) }
    let model = try CraftDocument(width: 3, height: 2)
    try NativeArchive.encode(model).write(to: url)
    let controller = CraftDocumentController()
    let doc = try XCTUnwrap(
      controller.makeDocument(withContentsOf: url, ofType: CraftNSDocument.nativeType)
        as? CraftNSDocument)
    doc.store.renderTask?.cancel()
    XCTAssertEqual(doc.fileURL, url)
    XCTAssertEqual(doc.store.document, model)
  }
}
extension WorkflowTests {
  @MainActor func testPrivateCloudImagePlaygroundCanBePresentedWhenAvailable() throws {
    let store = EditorStore(document: try CraftDocument(width: 8, height: 8))
    store.renderTask?.cancel()
    let before = store.document
    store.prompt = "  test scene  "
    store.beginImageCreation(
      capability: LocalAI.imagePlatformCapability(majorVersion: 27, isAppleSilicon: true))
    XCTAssertTrue(store.showImagePlayground)
    XCTAssertNil(store.aiError)
    XCTAssertEqual(store.prompt, "test scene")
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testUnavailableImageServiceCannotBePresented() throws {
    let store = EditorStore(document: try CraftDocument(width: 8, height: 8))
    store.renderTask?.cancel()
    let before = store.document
    store.prompt = "test scene"
    store.beginImageCreation(
      capability: AICapability(available: false, message: "Service unavailable"))
    XCTAssertFalse(store.showImagePlayground)
    XCTAssertEqual(store.aiError, "Service unavailable")
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testInvalidImagePromptCannotPresentAvailableService() throws {
    let store = EditorStore(document: try CraftDocument(width: 8, height: 8))
    store.renderTask?.cancel()
    let before = store.document
    store.prompt = " \n "
    store.beginImageCreation(capability: AICapability(available: true, message: "Ready"))
    XCTAssertFalse(store.showImagePlayground)
    XCTAssertNotNil(store.aiError)
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testGeneratedImageBecomesUndoableLayer() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: url) }
    try RasterIO.write(Surface(width: 4, height: 4, fill: Pixel(0.2, 0.7, 0.9)), to: url)
    let store = EditorStore(document: try CraftDocument(width: 8, height: 8))
    store.renderTask?.cancel()
    store.prompt = "test scene"
    store.acceptGeneratedImage(url)
    store.renderTask?.cancel()
    XCTAssertNil(store.aiError)
    XCTAssertEqual(store.status, "Created with Image Playground")
    XCTAssertEqual(store.document.layers.count, 2)
    XCTAssertEqual(store.document.layers.last?.x, 2)
    XCTAssertEqual(store.document.layers.last?.y, 2)
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.layers.count, 1)
  }
}
