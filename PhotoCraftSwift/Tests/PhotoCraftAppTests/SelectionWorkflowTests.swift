import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class SelectionWorkflowTests: XCTestCase {
  @MainActor func testFreehandLassoCommitsOnceAndToolChangeDiscardsDraft() async throws {
    let store = EditorStore(document: try CraftDocument(width: 20, height: 20))
    store.renderTask?.cancel()
    store.chooseTool(WorkspaceCatalog.tool("lasso"))
    let canvas = CraftCanvas(store: store)
    canvas.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
    func event(_ kind: NSEvent.EventType, _ x: Double, _ y: Double) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: kind, location: CGPoint(x: x, y: y),
          modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
          clickCount: 1, pressure: 1))
    }
    let before = store.document
    canvas.mouseDown(with: try event(.leftMouseDown, 80, 80))
    canvas.mouseDragged(with: try event(.leftMouseDragged, 200, 90))
    canvas.mouseDragged(with: try event(.leftMouseDragged, 130, 210))
    canvas.mouseUp(with: try event(.leftMouseUp, 80, 80))
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertNotNil(store.document.selectionMask)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.document.layers, before.layers)
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, before)
    store.chooseTool(WorkspaceCatalog.tool("polygonLasso"))
    canvas.synchronizeTool()
    canvas.polygonPoints = [.init(1, 1), .init(4, 1)]
    store.chooseTool(WorkspaceCatalog.tool("brush"))
    canvas.synchronizeTool()
    XCTAssertTrue(canvas.polygonPoints.isEmpty)
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testSelectionToolModesAndBackgroundUndo() async throws {
    let store = EditorStore(document: try CraftDocument(width: 20, height: 20))
    store.renderTask?.cancel()
    store.chooseTool(WorkspaceCatalog.tool("ellipticalMarquee"))
    XCTAssertEqual(store.tool, .ellipticalMarquee)
    XCTAssertNil(store.unavailableToolID)
    XCTAssertEqual(store.selectionMode(modifiers: [.shift]), .add)
    XCTAssertEqual(store.selectionMode(modifiers: [.option]), .subtract)
    XCTAssertEqual(store.selectionMode(modifiers: [.shift, .option]), .intersect)
    store.selectionMode = .intersect
    XCTAssertEqual(store.selectionMode(modifiers: []), .intersect)
    let before = store.document
    store.selectShape(.ellipse(.init(x: 2, y: 2, width: 16, height: 14)), mode: .replace)
    await store.geometryTask?.value
    await store.renderTask?.value
    XCTAssertNil(store.error)
    XCTAssertNotNil(store.document.selectionMask)
    XCTAssertNotNil(store.selectionPath)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.document.layers, before.layers)
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, before)
  }
  func testContourRepresentsHoleAndHalfCoverageThreshold() throws {
    let mask = try SelectionMask(
      width: 3, height: 3, bytes: [255, 255, 255, 255, 0, 255, 255, 255, 127])
    let path = try SelectionOutline.path(mask).path
    var segments = 0
    path.applyWithBlock { element in if element.pointee.type == .addLineToPoint { segments += 1 } }
    XCTAssertGreaterThan(
      segments, 4, "The hole and cut corner require more than a bounding rectangle")
    XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 3, height: 3))
    XCTAssertTrue(try SelectionOutline.path(.init(width: 1, height: 1, bytes: [127])).path.isEmpty)
  }
  @MainActor func testFractionalSelectionCreatesActualLayerMaskAndUndo() throws {
    var doc = try CraftDocument(width: 4, height: 2)
    doc.setCoverageSelection(
      try .init(width: 4, height: 2, bytes: [0, 64, 128, 255, 0, 64, 128, 255]))
    let store = EditorStore(document: doc)
    store.renderTask?.cancel()
    store.addMask()
    store.renderTask?.cancel()
    XCTAssertTrue(store.editingMask)
    let mask = try XCTUnwrap(store.activeLayer?.mask)
    XCTAssertEqual(mask.pixel(x: 2, y: 0).r, 128.0 / 255, accuracy: 0.004)
    XCTAssertEqual(
      try Renderer.composite(store.document).pixel(x: 2, y: 0).a, 128.0 / 255, accuracy: 0.004)
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, doc)
    XCTAssertFalse(store.editingMask)
  }
  @MainActor func testPolygonFinishCancelAndToolSwitchIsolation() async throws {
    let store = EditorStore(document: try CraftDocument(width: 20, height: 20))
    store.renderTask?.cancel()
    store.chooseTool(WorkspaceCatalog.tool("polygonLasso"))
    let canvas = CraftCanvas(store: store)
    canvas.polygonPoints = [.init(2, 2), .init(12, 2), .init(2, 12)]
    canvas.finishPolygon()
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertEqual(
      store.document.selectionMask?.bytes.reduce(0) { $0 + Double($1) / 255 } ?? 0, 50,
      accuracy: 0.05)
    XCTAssertTrue(canvas.polygonPoints.isEmpty)
    let before = store.document
    canvas.polygonPoints = [.init(1, 1), .init(4, 1)]
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
        keyCode: 53))
    canvas.keyDown(with: escape)
    XCTAssertTrue(canvas.polygonPoints.isEmpty)
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testMaskPaintingTargetsMaskAndLeavesShapeEditable() throws {
    var doc = try CraftDocument(width: 12, height: 12)
    var layer = Layer(
      name: "Shape", content: .shape(.init(kind: .rectangle, width: 4, height: 4, color: .black)))
    layer.affine = .translation(7, 1) * .rotation(90) * .scale(2, 2)
    layer.mask = try Surface(width: 4, height: 4, fill: .white)
    doc.layers = [layer]
    doc.activeLayerID = layer.id
    let store = EditorStore(document: doc)
    store.renderTask?.cancel()
    store.selectMask(layer.id)
    var brush = Brush()
    brush.color = .black
    brush.hardness = 1
    brush.size = 1
    let p = layer.coordinateTransform.point(1.5, 1.5)
    store.stroke([.init(x: p.x, y: p.y)], brush: brush)
    store.renderTask?.cancel()
    XCTAssertNil(store.error)
    XCTAssertEqual(store.activeLayer?.content, layer.content)
    XCTAssertEqual(store.activeLayer?.mask?.pixel(x: 1, y: 1).r, 0)
    XCTAssertEqual(store.activeLayer?.mask?.pixel(x: 0, y: 0).r, 1)
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, doc)
    store.select(layer.id)
    XCTAssertFalse(store.editingMask)
  }
  func testMaskStrokeTreatsCoverageAsGrayIndependentOfAlphaAndRespectsSelection() throws {
    var doc = try CraftDocument(width: 3, height: 1)
    let id = doc.layers[0].id
    doc.layers[0].mask = try Surface(width: 3, height: 1, fill: .clear)
    doc.setCoverageSelection(try .init(width: 3, height: 1, bytes: [0, 128, 255]))
    var brush = Brush()
    brush.color = .white
    brush.size = 20
    brush.hardness = 1
    brush.opacity = 0.5
    var session = EditorSession(document: doc)
    try session.execute(.maskStroke(id, [.init(x: 1.5, y: 0.5)], brush))
    let result = try XCTUnwrap(session.document.layers[0].mask)
    XCTAssertEqual(result.pixel(x: 0, y: 0).r, 0)
    XCTAssertEqual(result.pixel(x: 1, y: 0).r, 0.25, accuracy: 0.004)
    XCTAssertEqual(result.pixel(x: 2, y: 0).r, 0.5, accuracy: 0.004)
    XCTAssertEqual(session.document.layers[0].content, doc.layers[0].content)
    session.undo()
    try session.execute(.maskFill(id, 1))
    XCTAssertEqual(
      session.document.layers[0].mask?.pixel(x: 1, y: 0).r ?? -1, 128.0 / 255, accuracy: 0.004)
    try session.execute(.invertMask(id))
    XCTAssertEqual(
      session.document.layers[0].mask?.pixel(x: 1, y: 0).r ?? -1, 127.0 / 255, accuracy: 0.004)
    try session.execute(.lock(id, true))
    let locked = session.document
    XCTAssertThrowsError(try session.execute(.maskStroke(id, [.init(x: 1, y: 0)], brush)))
    XCTAssertEqual(session.document, locked)
  }
}
