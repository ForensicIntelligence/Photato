import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class ColorRegionWorkflowTests: XCTestCase {
  @MainActor func store(empty: Bool = false) throws -> EditorStore {
    var d = try CraftDocument(width: 20, height: 12, depth: .u16)
    var pixels = try Surface(width: 20, height: 12, depth: .u16, fill: .white)
    for y in 0..<12 { pixels.setPixel(x: 10, y: y, .black) }
    d.layers[0].content = .raster(pixels)
    if empty {
      let target = Layer(
        name: "Fill", content: .raster(try Surface(width: 20, height: 12, depth: .u16)))
      d.layers.append(target)
      d.activeLayerID = target.id
    }
    let s = EditorStore(document: d)
    s.wandOptions.antiAlias = false
    s.bucketOptions.match.antiAlias = false
    s.renderTask?.cancel()
    return s
  }
  @MainActor func finish(_ s: EditorStore) async {
    await s.geometryTask?.value
    await s.renderTask?.value
    XCTAssertNil(s.error)
  }
  @MainActor func testWandModifiersShortcutGroupAndReadOnlyLockedLayer() async throws {
    let s = try store()
    defer { s.renderTask?.cancel() }
    s.chooseTool(WorkspaceCatalog.tool("magicWand"))
    try s.session.execute(.lock(s.document.layers[0].id, true))
    let original = s.document
    s.colorRegionClick(at: .init(2, 2))
    await finish(s)
    XCTAssertEqual(s.document.selectionMask?.coverage(x: 2, y: 2), 1)
    XCTAssertEqual(s.document.selectionMask?.coverage(x: 15, y: 2), 0)
    s.colorRegionClick(at: .init(15, 2), modifiers: .shift)
    await finish(s)
    XCTAssertEqual(s.document.selectionMask?.coverage(x: 15, y: 2), 1)
    s.colorRegionClick(at: .init(2, 2), modifiers: .option)
    await finish(s)
    XCTAssertEqual(s.document.selectionMask?.coverage(x: 2, y: 2), 0)
    s.colorRegionClick(at: .init(15, 2), modifiers: [.shift, .option])
    await finish(s)
    XCTAssertEqual(s.document.layers, original.layers)
    XCTAssertTrue(s.chooseShortcut("v", cycle: false))
    XCTAssertTrue(s.chooseShortcut("w", cycle: false))
    XCTAssertEqual(s.tool, .magicWand)
    XCTAssertTrue(s.chooseShortcut("w", cycle: true))
    XCTAssertEqual(s.unavailableToolID, "objectSelection")
  }
  @MainActor func testBucketCapturesForegroundAndAllLayersWithoutChangingSource() async throws {
    let s = try store(empty: true)
    defer { s.renderTask?.cancel() }
    s.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    s.bucketOptions.sampleAllLayers = true
    s.brush.color = Pixel(1, 0, 0)
    let before = s.document
    s.colorRegionClick(at: .init(2, 2))
    XCTAssertTrue(s.geometryBusy)
    s.brush.color = .black
    s.bucketOptions.sampleAllLayers = false
    s.bucketOptions.match.contiguous = false
    await finish(s)
    guard case .raster(let pixels) = s.activeLayer?.content else {
      return XCTFail("Expected pixels")
    }
    XCTAssertEqual(pixels.pixel(x: 2, y: 2), Pixel(1, 0, 0))
    XCTAssertEqual(pixels.pixel(x: 15, y: 2), .clear)
    XCTAssertEqual(s.document.layers[0], before.layers[0])
    XCTAssertEqual(s.session.undoStack.count, 1)
    let after = s.document
    s.undo()
    XCTAssertEqual(s.document, before)
    s.redo()
    XCTAssertEqual(s.document, after)
    XCTAssertTrue(s.chooseShortcut("v", cycle: false))
    XCTAssertTrue(s.chooseShortcut("g", cycle: false))
    XCTAssertEqual(s.tool, .paintBucket)
    await s.renderTask?.value
    s.colorRegionClick(at: .init(15, 2), modifiers: .option)
    XCTAssertEqual(s.brush.color, .white)
    XCTAssertEqual(s.document, after)
    XCTAssertEqual(s.session.undoStack.count, 1)
  }
  @MainActor func testCanvasClickAndEscapeCancelAreSingleAtomicOperations() async throws {
    let s = try store()
    defer { s.renderTask?.cancel() }
    s.chooseTool(WorkspaceCatalog.tool("magicWand"))
    let canvas = CraftCanvas(store: s)
    canvas.frame = NSRect(x: 0, y: 0, width: 300, height: 240)
    // This interaction fixture requires 10× magnification, independent of initial-fit policy.
    s.zoom = 10
    let event = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: .init(x: 90, y: 100), modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    XCTAssertEqual(canvas.docPoint(event), CGPoint(x: 4, y: 8))
    canvas.mouseDown(with: event)
    await finish(s)
    XCTAssertNotNil(s.document.selectionMask)
    XCTAssertEqual(s.session.undoStack.count, 1)
    s.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    s.brush.color = .black
    let before = s.document
    s.colorRegionClick(at: .init(2, 2))
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    canvas.keyDown(with: escape)
    await finish(s)
    XCTAssertEqual(s.document, before)
    XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertFalse(s.geometryBusy)
  }
  @MainActor func testPixelMaskTargetAndLockedBucket() async throws {
    let s = try store()
    defer { s.renderTask?.cancel() }
    try s.session.execute(
      .mask(
        s.document.layers[0].id,
        Surface(width: 20, height: 12, depth: .u16, fill: .white)))
    s.maskEditingLayerID = s.activeLayer?.id
    s.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    s.brush.color = .black
    s.bucketOptions.sampleAllLayers = true
    let originalContent = s.document.layers[0].content
    s.colorRegionClick(at: .init(2, 2))
    await finish(s)
    XCTAssertEqual(s.document.layers[0].content, originalContent)
    XCTAssertEqual(s.activeLayer?.mask?.pixel(x: 2, y: 2), .black)
    try s.session.execute(.lock(s.document.layers[0].id, true))
    let locked = s.document
    s.brush.color = .white
    s.colorRegionClick(at: .init(2, 2))
    XCTAssertNotNil(s.error)
    XCTAssertFalse(s.geometryBusy)
    XCTAssertEqual(s.document, locked)
  }
}
