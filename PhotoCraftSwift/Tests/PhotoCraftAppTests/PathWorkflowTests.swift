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
  @MainActor func testPenCurvesCloseSaveAndUndo() throws {
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
    s.undo()
    XCTAssertEqual(s.selectedVectorPath?.components[0].closed, false)
    s.redo()
    s.saveSelectedPath(name: "Contour")
    XCTAssertEqual(s.document.paths?.first?.name, "Contour")
    XCTAssertEqual(s.document.paths?.first?.isWorkPath, false)
    s.renderTask?.cancel()
  }
  @MainActor func testDirectSelectionAnchorAndHandleEditsAreUndoable() throws {
    let s = try store()
    draw(s)
    s.tool = .directSelection
    let original = try XCTUnwrap(s.selectedVectorPath)
    s.beginPath(at: PathPoint(70, 10), tolerance: 2)
    s.dragPath(to: PathPoint(80, 15))
    s.endPathGesture()
    XCTAssertEqual(s.selectedVectorPath?.components[0].knots[1].anchor, PathPoint(80, 15))
    s.undo()
    XCTAssertEqual(s.selectedVectorPath, original)
    s.tool = .pathSelection
    s.beginPath(at: PathPoint(40, 10), tolerance: 2)
    s.dragPath(to: PathPoint(43, 14))
    s.endPathGesture()
    XCTAssertEqual(s.selectedVectorPath, original.transformed(.translation(3, 4)))
    s.renderTask?.cancel()
  }
  @MainActor func testPenAddsAndDeletesAnchorsOnExistingContour() throws {
    let s = try store()
    draw(s)
    let original = try XCTUnwrap(s.selectedVectorPath)
    s.beginPath(at: PathPoint(40, 10), tolerance: 2)
    XCTAssertEqual(s.selectedVectorPath?.knotCount, 5)
    s.deletePathAnchor()
    XCTAssertEqual(s.selectedVectorPath?.knotCount, 4)
    s.undo()
    s.undo()
    XCTAssertEqual(s.selectedVectorPath, original)
    s.renderTask?.cancel()
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
