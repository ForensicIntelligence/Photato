import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class PathWorkflowTests: XCTestCase {
  @MainActor func store() throws -> EditorStore {
    let store = EditorStore(document: try CraftDocument(width: 100, height: 80))
    store.tool = .pen
    store.renderTask?.cancel()
    return store
  }
  @MainActor func draw(_ s: EditorStore) {
    for p in [PathPoint(10, 10), PathPoint(70, 10), PathPoint(70, 60), PathPoint(10, 60)] {
      s.beginPath(at: p, tolerance: 2)
      s.endPathGesture()
    }
    s.beginPath(at: PathPoint(10, 10), tolerance: 2)
  }
  @MainActor func testNativeTypeMatchesBundleAndVectorDocumentWritesToDisk() throws {
    let infoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("scripts/Info.plist")
    let info = try XCTUnwrap(
      try PropertyListSerialization.propertyList(
        from: Data(contentsOf: infoURL), options: [], format: nil) as? [String: Any])
    let types = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
    let native = try XCTUnwrap(types.first?["LSItemContentTypes"] as? [String])
    XCTAssertEqual(native, [CraftNSDocument.nativeType])
    let editable = types.filter { $0["CFBundleTypeRole"] as? String == "Editor" }
      .flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
    XCTAssertEqual(CraftNSDocument.writableTypes, editable)
    let s = try store()
    draw(s)
    s.makeVectorMask()
    let document = CraftNSDocument(model: s.document)
    XCTAssertEqual(document.fileType, CraftNSDocument.nativeType)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".pcswift")
    defer {
      try? FileManager.default.removeItem(at: url)
      s.renderTask?.cancel()
      document.close()
    }
    try document.write(to: url, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(try NativeArchive.decode(Data(contentsOf: url)), s.document)
  }
  @MainActor func testEmptyRevealHideVectorMasksLoadCorrectSelection() throws {
    let s = try store()
    s.addVectorMask(reveal: true)
    s.pathToSelection()
    XCTAssertEqual(s.document.selection, IntRect(x: 0, y: 0, width: 100, height: 80))
    s.addVectorMask(reveal: false)
    s.pathToSelection()
    XCTAssertNil(s.document.selection)
    s.renderTask?.cancel()
  }
  @MainActor func testPenCurvesCloseSaveAndUndo() async throws {
    let s = try store()
    s.beginPath(at: PathPoint(10, 10), tolerance: 2)
    s.dragPath(to: PathPoint(20, 15))
    s.endPathGesture()
    let first = try XCTUnwrap(s.selectedVectorPath?.components.first?.knots.first)
    XCTAssertEqual(first.incoming, PathPoint(0, 5))
    XCTAssertTrue(first.smooth)
    s.beginPath(at: PathPoint(70, 10), tolerance: 2)
    s.endPathGesture()
    s.beginPath(at: PathPoint(70, 60), tolerance: 2)
    s.endPathGesture()
    s.beginPath(at: PathPoint(10, 10), tolerance: 2)
    XCTAssertEqual(s.selectedVectorPath?.components[0].closed, true)
    await s.undo()
    XCTAssertEqual(s.selectedVectorPath?.components[0].closed, false)
    await s.redo()
    s.saveSelectedPath(name: "Contour")
    XCTAssertEqual(s.document.paths?.first?.name, "Contour")
    XCTAssertEqual(s.document.paths?.first?.isWorkPath, false)
    s.renderTask?.cancel()
  }
  @MainActor func testDirectSelectionAnchorAndHandleEditsAreUndoable() async throws {
    let s = try store()
    draw(s)
    s.tool = .directSelection
    let original = try XCTUnwrap(s.selectedVectorPath)
    s.beginPath(at: PathPoint(70, 10), tolerance: 2)
    s.dragPath(to: PathPoint(80, 15))
    s.endPathGesture()
    XCTAssertEqual(s.selectedVectorPath?.components[0].knots[1].anchor, PathPoint(80, 15))
    await s.undo()
    XCTAssertEqual(s.selectedVectorPath, original)
    s.tool = .pathSelection
    s.beginPath(at: PathPoint(40, 10), tolerance: 2)
    s.dragPath(to: PathPoint(43, 14))
    s.endPathGesture()
    XCTAssertEqual(s.selectedVectorPath, original.transformed(.translation(3, 4)))
    s.renderTask?.cancel()
  }
  @MainActor func testPenAddsAndDeletesAnchorsOnExistingContour() async throws {
    let s = try store()
    draw(s)
    let original = try XCTUnwrap(s.selectedVectorPath)
    s.beginPath(at: PathPoint(40, 10), tolerance: 2)
    XCTAssertEqual(s.selectedVectorPath?.knotCount, 5)
    s.deletePathAnchor()
    XCTAssertEqual(s.selectedVectorPath?.knotCount, 4)
    await s.undo()
    await s.undo()
    XCTAssertEqual(s.selectedVectorPath, original)
    s.renderTask?.cancel()
  }
  @MainActor func testVectorMaskFeatherThroughPropertiesHTTPStateAndUndo() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var document = try CraftDocument(width: 32, height: 24)
      let id = document.layers[0].id
      let mask = VectorMask(path: VectorPath(inverted: true))
      document.layers[0].vectorMask = mask
      let native = EditorStore(document: document)
      defer { native.renderTask?.cancel() }
      native.selectPath(.vectorMask(id))
      native.updateVectorMask(id) {
        $0.feather = 1_000
        $0.linked = false
      }
      XCTAssertNil(native.error)
      XCTAssertEqual(native.document.layers[0].vectorMask?.path, mask.path)
      XCTAssertEqual(native.document.layers[0].vectorMask?.feather, 1_000)

      shared.store.session = EditorSession(document: document)
      try service.share(shared)
      let params: [String: Any] = ["operation": "vectorMaskProperties", "layerID": id.uuidString,
        "maskProperties": ["feather": 1_000, "linked": false]]
      let applied = try await helper.edit(service, shared, "path.edit", params)
      XCTAssertEqual(applied, 200)
      XCTAssertEqual(shared.store.document, native.document)
      let share = try XCTUnwrap(service.shares.first?.id)
      let (response, data) = try await helper.request(service, path: "/v1/documents/\(share)")
      XCTAssertEqual(response.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      let layers = try XCTUnwrap(state["layers"] as? [[String: Any]])
      let properties = try XCTUnwrap(layers.first?["vectorMask"] as? [String: Any])
      XCTAssertEqual(properties["feather"] as? Double, 1_000)
      XCTAssertEqual(properties["linked"] as? Bool, false)

      var rejected = params
      rejected["maskProperties"] = ["feather": 1_000.01]
      let bad = try await helper.edit(service, shared, "path.edit", rejected)
      XCTAssertEqual(bad, 400)
      XCTAssertEqual(shared.store.document, native.document)
      let undo = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(undo, 200)
      await native.undo()
      XCTAssertEqual(shared.store.document, document)
      XCTAssertEqual(native.document, document)
    }
  }

  @MainActor func testVectorMaskPreviewCancelSelectionAndLockedEditing() throws {
    let s = try store()
    draw(s)
    s.pathToSelection()
    XCTAssertEqual(s.document.selectionCoverage(x: 20, y: 20), 1)
    XCTAssertEqual(s.document.selectionCoverage(x: 90, y: 70), 0)
    s.makeVectorMask()
    let original = try XCTUnwrap(s.activeLayer?.vectorMask)
    s.beginPath(at: PathPoint(10, 10), tolerance: 2)
    s.dragPath(to: PathPoint(25, 20))
    XCTAssertEqual(s.activeLayer?.vectorMask, original)
    XCTAssertNotEqual(s.previewDocument.layers[0].vectorMask, original)
    s.finishPath(cancelGesture: true)
    XCTAssertEqual(s.previewDocument.layers[0].vectorMask, original)
    s.perform(.lock(s.activeLayer!.id, true))
    s.beginPath(at: PathPoint(10, 10), tolerance: 2)
    XCTAssertNil(s.pathGesture)
    s.renderTask?.cancel()
  }
}
