import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PlacementResolutionWorkflowTests: XCTestCase {
  @MainActor func testNativeEmbeddedPreviewAndHTTPPhysicalSizingMatchWithUndo() async throws {
    let helper = EmbeddedPlacementWorkflowTests()
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, parent in
      var source = try helper.fixture()
      source.resolution = 144
      let bytes = try DocumentIO.encode(source, format: .png)
      let root = try helper.folder()
      defer { try? FileManager.default.removeItem(at: root) }
      let url = root.appendingPathComponent("Art.png")
      try bytes.write(to: url)
      let store = parent.store
      let original = try CraftDocument(width: 16, height: 12)
      store.session = EditorSession(document: original)
      try service.share(parent)
      service.setDocumentTransfersEnabled(true)

      store.placeEmbeddedSource(url)
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.document, original)
      let preview = try XCTUnwrap(store.embeddedPlacement?.layer)
      XCTAssertEqual(preview.coordinateTransform, Transform2D(a: 0.5, d: 0.5, tx: 6, ty: 4))
      XCTAssertEqual(preview.smartObject?.resolution, 144)
      XCTAssertNotNil(store.transformDraft)
      store.commitTransform()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try XCTUnwrap(store.activeLayer)
      let composite = try Renderer.composite(store.document).rgbaData(depth: .u8)
      await store.undo()
      XCTAssertEqual(store.document, original)

      let legacy = try await helper.upload(service, parent, bytes)
      XCTAssertEqual(legacy.0.statusCode, 200)
      XCTAssertEqual(store.activeLayer?.coordinateTransform, Transform2D(tx: 4, ty: 3))
      await store.undo()
      let physical = try await helper.upload(service, parent, bytes, options: ["sizing": "physical"])
      XCTAssertEqual(physical.0.statusCode, 200)
      XCTAssertEqual(store.activeLayer?.coordinateTransform, native.coordinateTransform)
      XCTAssertEqual(store.activeLayer?.smartObject?.data, bytes)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), composite)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testLinkedNoFitPreservesNaturalPrintSizeOnDesktopAndHTTP() async throws {
    let helper = LinkedArtworkPlacementTests()
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, parent in
      var model = try EmbeddedPlacementWorkflowTests().fixture()
      model.resolution = 72
      let source = try DocumentIO.encode(model, format: .png)
      let (folder, asset, grant) = try helper.setup(service, parent, bytes: source, name: "Art.png")
      let store = parent.store
      defer { try? FileManager.default.removeItem(at: folder); store.linkedSourceController?.stop() }
      var original = try CraftDocument(width: 16, height: 12)
      original.resolution = 288
      store.session = EditorSession(document: original)
      store.artworkPlacementPreferences.settings = ArtworkPlacementSettings(resizeImageDuringPlace: false,
        skipTransformWhenPlacing: true)

      store.placeEmbeddedSource(folder.appendingPathComponent("Art.png"), linkedGrant: grant)
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertNil(store.transformDraft)
      let native = try XCTUnwrap(store.activeLayer)
      XCTAssertEqual(native.coordinateTransform, Transform2D(a: 4, d: 4, tx: -8, ty: -6))
      XCTAssertNotNil(native.smartObject?.linkedSource)
      await store.undo()
      XCTAssertEqual(store.document, original)
      var parameters = helper.parameters(asset, source, ["sizing": "physical"])
      parameters["fit"] = false
      let result = try await AutomationTests().edit(service, parent, "smartObject.linked.place", parameters)
      XCTAssertEqual(result, 200)
      XCTAssertEqual(store.activeLayer?.coordinateTransform, native.coordinateTransform)
      XCTAssertEqual(store.activeLayer?.content, native.content)
      XCTAssertEqual(store.activeLayer?.smartObject?.data, source)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testNativePDFChoosesContentBeforePhysicalPlacementAndHTTPAgrees() async throws {
    let chooser = PDFPlacementWorkflowTests()
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, parent in
      let store = parent.store
      var original = try CraftDocument(width: 600, height: 500)
      original.resolution = 144
      store.session = EditorSession(document: original)
      store.artworkPlacementPreferences.settings.skipTransformWhenPlacing = true
      try service.share(parent)
      service.setDocumentTransfersEnabled(true)
      let url = chooser.fixture()
      chooser.select(store)
      store.placePDF(url)
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      let layer = try XCTUnwrap(store.activeLayer)
      let object = try XCTUnwrap(layer.smartObject)
      let page = try XCTUnwrap(object.pdfSource)
      XCTAssertEqual(Double(object.width) * layer.coordinateTransform.a, page.width * 2, accuracy: 1e-9)
      XCTAssertEqual(Double(object.height) * layer.coordinateTransform.d, page.height * 2, accuracy: 1e-9)
      XCTAssertNil(store.transformDraft)
      await store.undo()
      XCTAssertEqual(store.document, original)

      let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await DocumentIOWorkflowTests().request(service, path: "/v1/documents/\(id)/smart-objects/pdf",
        data: Data(contentsOf: url), type: "application/pdf", headers: [
          "X-Photato-Revision": service.revision(store),
          "X-Photato-PDF-Options": #"{"crop":"media","antialias":false,"sizing":"physical"}"#,
        ])
      XCTAssertEqual(response.0.statusCode, 200, String(decoding: response.1, as: UTF8.self))
      XCTAssertEqual(store.activeLayer?.coordinateTransform, layer.coordinateTransform)
      XCTAssertEqual(store.activeLayer?.content, layer.content)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testSharedDocumentPlacementAndStrictSizingOptions() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, parent in
      var child = try CraftDocument(width: 8, height: 6)
      child.resolution = 144
      let source = CraftNSDocument(model: child)
      service.controller.addDocument(source)
      defer { source.store.renderTask?.cancel(); service.controller.removeDocument(source) }
      parent.store.session = EditorSession(document: try CraftDocument(width: 16, height: 12))
      let original = parent.store.document
      try service.share(parent)
      try service.share(source)
      let sourceID = try XCTUnwrap(service.shares.first { $0.document === source }?.id)
      var parameters: [String: Any] = ["sourceDocumentID": sourceID.uuidString,
        "sourceRevision": service.revision(source.store), "sizing": "unknown"]
      let invalid = try await helper.edit(service, parent, "smartObject.place", parameters)
      XCTAssertEqual(invalid, 400)
      XCTAssertEqual(parent.store.document, original)
      parameters["sizing"] = "physical"
      let placed = try await helper.edit(service, parent, "smartObject.place", parameters)
      XCTAssertEqual(placed, 200)
      XCTAssertEqual(parent.store.activeLayer?.coordinateTransform, Transform2D(a: 0.5, d: 0.5, tx: 6, ty: 4))
      XCTAssertEqual(parent.store.activeLayer?.smartObject?.resolution, 144)
      XCTAssertEqual(parent.store.session.undoStack.count, 1)
    }
    let layer = UUID()
    XCTAssertThrowsError(try EmbeddedSourceAPI.options("{\"frameID\":\"\(layer)\",\"sizing\":\"pixels\"}"))
    XCTAssertThrowsError(try PDFSmartObjectAPI.options("{\"layerID\":\"\(layer)\",\"sizing\":\"physical\"}"))
    XCTAssertThrowsError(try LinkedArtworkPlacementTests().parsed(["pdf": ["sizing": "physical"]]))
  }
}
