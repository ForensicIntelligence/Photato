import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

@MainActor private final class SelectionInteractionWindow: NSWindow {
  var fixtureBackingScale: CGFloat = 1
  override var backingScaleFactor: CGFloat { fixtureBackingScale }
}
private final class SelectionBorderGate: @unchecked Sendable {
  let condition=NSCondition(); var released=false
  func wait() { condition.lock(); while !released { condition.wait() }; condition.unlock() }
  func release() { condition.lock(); released=true; condition.broadcast(); condition.unlock() }
}
final class SelectionInteractionTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run { _ = PhotatoApp.makeDelegate(isolatedSession: true); _ = NSApplication.shared }
  }
  @MainActor func fixture() async throws -> (EditorStore, CraftCanvas, NSWindow) {
    var d = try CraftDocument(width: 96, height: 72)
    d.layers[0].content = .raster(try Surface(width: 96, height: 72, fill: Pixel(0.3, 0.5, 0.7)))
    try Command.selectShape(.ellipse(.init(x: 10, y: 12, width: 24, height: 18)), .replace, true, 0).apply(to: &d)
    let s = EditorStore(document: d, actions: ActionLibrary()); s.tool = .ellipticalMarquee
    let c = CraftCanvas(store: s); c.frame = .init(x: 0, y: 0, width: 640, height: 480)
    let window = SelectionInteractionWindow(contentRect: c.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = c; window.makeFirstResponder(c)
    s.updateViewport(size: c.bounds.size, backingScale: 1); s.setZoom(4, center: true)
    await s.renderTask?.value; c.synchronizeSelectionAnts(); return (s, c, window)
  }
  @MainActor func close(_ s: EditorStore, _ c: CraftCanvas, _ window: NSWindow) {
    s.renderTask?.cancel(); s.geometryTask?.cancel(); window.contentView = nil; window.close()
  }
  @MainActor func mouse(_ type: NSEvent.EventType, _ point: CGPoint, _ c: CraftCanvas, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    let location = c.convert(c.viewPoint(point), to: nil)
    return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags,
      timestamp: 0, windowNumber: c.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
  }
  @MainActor func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
      timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
  }
  @MainActor func settle(_ s: EditorStore) async {
    for _ in 0..<8 { await Task.yield(); await s.selectionBorderNudgeTask?.value; await s.geometryTask?.value; await s.renderTask?.value }
  }
  @MainActor func testMouseInsideEllipseMovesBorderAndPreservesPixelsWithOneUndo() async throws {
    let (s,c,w) = try await fixture(); defer { close(s,c,w) }; let original = s.document
    c.mouseDown(with: try mouse(.leftMouseDown, .init(x: 22, y: 20), c))
    c.mouseDragged(with: try mouse(.leftMouseDragged, .init(x: 34, y: 27), c))
    XCTAssertEqual(s.document, original, "Pointer feedback must not commit before release")
    c.mouseUp(with: try mouse(.leftMouseUp, .init(x: 34, y: 27), c)); await settle(s)
    var expected = original
    try SelectionTransform.command(in: original, projection: .init(.translation(12,7)), interpolation: .nearest).apply(to: &expected)
    XCTAssertEqual(s.document, expected); XCTAssertEqual(s.document.layers, original.layers)
    XCTAssertEqual(s.session.undoStack.count, 1)
    _ = await s.requestHistory(redo: false).value; XCTAssertEqual(s.document, original)
    _ = await s.requestHistory(redo: true).value; XCTAssertEqual(s.document, expected)
  }
  @MainActor func testArrowAndShiftArrowMoveSelectionBoundaryWithoutMovingPixels() async throws {
    let (s,c,w) = try await fixture(); defer { close(s,c,w) }; let original = s.document
    c.keyDown(with: try key(124)); await settle(s)
    c.keyDown(with: try key(125, flags: .shift)); await settle(s)
    var expected = original
    try SelectionTransform.command(in: original, projection: .init(.translation(1,10)), interpolation: .nearest).apply(to: &expected)
    XCTAssertEqual(s.document, expected); XCTAssertEqual(s.document.layers, original.layers)
  }
  @MainActor func testReplacePreviewHidesOldBorderOnPressAndEscapeRestoresSelection() async throws {
    let (s,c,w) = try await fixture(); defer { close(s,c,w) }; let original = s.document
    let overlay = try XCTUnwrap(c.selectionAnts); overlay.synchronize(environment: .init())
    XCTAssertFalse(overlay.committed.layer.isHidden)
    c.mouseDown(with: try mouse(.leftMouseDown, .init(x: 65, y: 46), c)); overlay.synchronize(environment: .init())
    XCTAssertTrue(overlay.committed.layer.isHidden, "New selection replaces old feedback at pointer-down")
    c.mouseDragged(with: try mouse(.leftMouseDragged, .init(x: 86, y: 62), c)); overlay.synchronize(environment: .init())
    XCTAssertTrue(overlay.committed.layer.isHidden); XCTAssertFalse(overlay.preview.layer.isHidden)
    XCTAssertEqual(s.document, original)
    c.keyDown(with: try key(53)); overlay.synchronize(environment: .init())
    XCTAssertFalse(overlay.committed.layer.isHidden); XCTAssertTrue(overlay.preview.layer.isHidden)
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testCanvasSizeKeepsExplicitZoomAndPanInsteadOfFittingOldDimensions() async throws {
    let (s,c,w) = try await fixture(); defer { close(s,c,w) }
    s.setZoom(1.5, center: true); s.pan = .init(width: 37, height: -25)
    let original = s.document, zoom = s.effectiveZoom, pan = s.pan
    s.geometrySheet = .canvasSize
    s.applyGeometrySheetCommand(.canvasSize(180,130,.center,nil)); await settle(s)
    XCTAssertEqual(s.document.width,180); XCTAssertEqual(s.document.height,130)
    XCTAssertEqual(s.effectiveZoom,zoom); XCTAssertEqual(s.pan,pan)
    XCTAssertEqual(c.imageRect.width,180*zoom/Double(w.backingScaleFactor),accuracy:1e-9)
    _ = await s.requestHistory(redo:false).value
    XCTAssertEqual(s.document,original); XCTAssertEqual(s.effectiveZoom,zoom); XCTAssertEqual(s.pan,pan)
  }
  @MainActor func testCursorShiftConstraintAndEscapeDoNotMovePixelsOrCommitDraft() async throws {
    let (s,c,w) = try await fixture(); defer { close(s,c,w) }; let original=s.document
    let flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for tool:EditorTool in [.marquee,.ellipticalMarquee,.rowMarquee,.columnMarquee,.lasso,.polygonLasso,.magicWand] {
      s.tool=tool; c.synchronizeTool(); c.cursorLocationInView=c.viewPoint(.init(x:22,y:20))
      for bits in 0..<16 {
        let f=flags.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element) }
        c.updateCursorModifiers(f)
        let expected:ToolCursor=bits==0 ? .symbol("arrow.up.and.down.and.arrow.left.and.right") : tool.cursor(modifiers:f,selection:s.selectionMode(modifiers:f))
        XCTAssertEqual(c.toolCursor,expected,"hover \(tool) modifiers \(bits)")
        XCTAssertEqual(s.canDragSelectionBorder(at:.init(x:22,y:20),modifiers:f),bits==0)
      }
    }
    s.tool = .ellipticalMarquee; c.synchronizeTool()
    c.cursorLocationInView=c.viewPoint(.init(x:22,y:20)); c.updateCursorModifiers([])
    XCTAssertEqual(c.toolCursor,.symbol("arrow.up.and.down.and.arrow.left.and.right"))
    c.updateCursorModifiers(.option); XCTAssertNotEqual(c.toolCursor,.symbol("arrow.up.and.down.and.arrow.left.and.right"))
    c.updateCursorModifiers([])
    c.mouseDown(with:try mouse(.leftMouseDown,.init(x:22,y:20),c))
    c.mouseDragged(with:try mouse(.leftMouseDragged,.init(x:34,y:27),c))
    let unconstrained=try XCTUnwrap(s.selectionBorderDrag); XCTAssertEqual(unconstrained.dx,12); XCTAssertEqual(unconstrained.dy,7)
    c.updateCursorModifiers(.shift)
    let constrained=try XCTUnwrap(s.selectionBorderDrag); XCTAssertEqual(constrained.dx,constrained.dy)
    XCTAssertEqual(c.toolCursor,.symbol("arrow.up.and.down.and.arrow.left.and.right",.constrain))
    c.synchronizeSelectionAnts(); XCTAssertFalse(try XCTUnwrap(c.selectionAnts).committed.layer.isHidden)
    c.keyDown(with:try key(53)); c.mouseUp(with:try mouse(.leftMouseUp,.init(x:34,y:27),c)); await settle(s)
    XCTAssertTrue(s.document==original); XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertNil(s.selectionBorderDrag)
  }
  @MainActor func testRapidArrowRepeatsAreQueuedAndUndoRestoresCoverage() async throws {
    let (s,c,w) = try await fixture(); defer { close(s,c,w) }; let original=s.document
    for _ in 0..<20 { c.keyDown(with:try key(124)) }
    for _ in 0..<2 { c.keyDown(with:try key(125,flags:.shift)) }
    await settle(s)
    var expected=original
    try SelectionTransform.command(in:original,projection:.init(.translation(20,20)),interpolation:.nearest).apply(to:&expected)
    XCTAssertTrue(s.document==expected); XCTAssertEqual(s.document.layers,original.layers); XCTAssertEqual(s.session.undoStack.count,1)
    _=await s.requestHistory(redo:false).value; XCTAssertTrue(s.document==original)
    _=await s.requestHistory(redo:true).value; XCTAssertTrue(s.document==expected)
  }
  @MainActor func testStaleDragToolChangeAndDetachCannotCreateOrCommitAnotherSelection() async throws {
    for interruption in 0..<3 {
      let (s,c,w)=try await fixture(); defer {close(s,c,w)}
      c.mouseDown(with:try mouse(.leftMouseDown,.init(x:22,y:20),c))
      c.mouseDragged(with:try mouse(.leftMouseDragged,.init(x:34,y:27),c))
      if interruption==0 { try s.session.execute(.renameLayer(s.document.layers[0].id,"Changed while dragging")) }
      else if interruption==1 { s.tool = .marquee }
      else { w.contentView=nil }
      let after=s.document,history=s.session.undoStack.count
      c.mouseDragged(with:try mouse(.leftMouseDragged,.init(x:44,y:37),c))
      c.mouseUp(with:try mouse(.leftMouseUp,.init(x:44,y:37),c)); await settle(s)
      XCTAssertTrue(s.document==after); XCTAssertEqual(s.session.undoStack.count,history); XCTAssertNil(s.selectionBorderDrag)
    }
  }
  @MainActor func testReplaceAndCombinationGesturesCommitExpectedEllipseAndUndo() async throws {
    for flags:NSEvent.ModifierFlags in [[],.shift,.option,[.shift,.option]] {
      let (s,c,w)=try await fixture(); defer {close(s,c,w)}; let original=s.document
      let mode=s.selectionMode(modifiers:flags),a=CGPoint(x:65,y:46),b=CGPoint(x:86,y:62)
      c.mouseDown(with:try mouse(.leftMouseDown,a,c,flags:flags))
      c.mouseDragged(with:try mouse(.leftMouseDragged,b,c,flags:flags))
      let overlay=try XCTUnwrap(c.selectionAnts); overlay.synchronize(environment:.init())
      XCTAssertEqual(overlay.committed.layer.isHidden,mode == .replace)
      XCTAssertTrue(s.document==original)
      c.mouseUp(with:try mouse(.leftMouseUp,b,c,flags:flags)); await settle(s)
      let rect=try XCTUnwrap(CraftCanvas.dragRect(from:a,to:b,flags:[],width:original.width,height:original.height,clipToCanvas:false))
      var expected=original
      try Command.selectShape(.ellipse(rect),mode,s.selectionAntiAlias,s.selectionFeather).apply(to:&expected)
      XCTAssertTrue(s.document==expected); XCTAssertEqual(s.document.layers,original.layers)
      _=await s.requestHistory(redo:false).value; XCTAssertTrue(s.document==original)
    }
  }
  @MainActor func testCanvasSizeKeepsZoomAndPanAcrossAnchorsBackingScalesGrowShrinkAndRedo() async throws {
    for backing:Double in [1,2] { for anchor in CanvasAnchor.allCases {
      let (s,c,w)=try await fixture(); defer {close(s,c,w)}
      (w as? SelectionInteractionWindow)?.fixtureBackingScale=backing; s.updateViewport(size:c.bounds.size,backingScale:backing); s.setZoom(0.75,center:true); s.pan = .init(width:-11,height:19)
      let original=s.document,zoom=s.effectiveZoom,pan=s.pan
      for size in [(132,100),(63,49)] {
        s.applyGeometrySheetCommand(.canvasSize(size.0,size.1,anchor,nil)); await settle(s)
        XCTAssertEqual(s.effectiveZoom,zoom); XCTAssertEqual(s.pan,pan)
        XCTAssertEqual(c.imageRect.width,Double(size.0)*zoom/Double(w.backingScaleFactor),accuracy:1e-9)
      }
      _=await s.requestHistory(redo:false).value; _=await s.requestHistory(redo:false).value
      XCTAssertTrue(s.document==original); XCTAssertEqual(s.effectiveZoom,zoom); XCTAssertEqual(s.pan,pan)
      _=await s.requestHistory(redo:true).value; XCTAssertEqual(s.document.width,132); XCTAssertEqual(s.effectiveZoom,zoom); XCTAssertEqual(s.pan,pan)
    }}
  }
  @MainActor func testDirectBorderCommitUsesExistingAPIActionAndArchiveSemantics() async throws {
    let (s,c,w)=try await fixture(); defer {close(s,c,w)}; let original=s.document
    try s.session.startActionRecording(name:"Move border")
    c.mouseDown(with:try mouse(.leftMouseDown,.init(x:22,y:20),c))
    c.mouseDragged(with:try mouse(.leftMouseDragged,.init(x:29,y:25),c))
    c.mouseUp(with:try mouse(.leftMouseUp,.init(x:29,y:25),c)); await settle(s)
    var replay=original; try XCTUnwrap(s.session.actionRecording?.snapshot).apply(to:&replay)
    XCTAssertTrue(replay==s.document)
    let decoded=try NativeArchive.decode(NativeArchive.encodeChunked(s.document))
    XCTAssertTrue(decoded==s.document)
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) { service,doc in
      doc.store.session=EditorSession(document:original); try service.share(doc)
      let status=try await h.edit(service,doc,"selection.transform",["matrix":ProjectiveTransform(.translation(7,5)).values,"interpolation":Resampling.nearest.rawValue])
      XCTAssertEqual(status,200); XCTAssertTrue(doc.store.document==s.document)
    }
  }

  @MainActor func testKeysReceivedDuringPreparationAreAppliedAfterTheCurrentNudge() async throws {
    let (s,c,w)=try await fixture(); defer { close(s,c,w) }; let original=s.document,gate=SelectionBorderGate()
    s.selectionTransformPreparation={ source,matrix,method in
      gate.wait(); try Task.checkCancellation()
      return try SelectionTransform.command(in:source,projection:matrix,interpolation:method)
    }
    defer { gate.release() }
    c.keyDown(with:try key(124))
    let deadline=Date().addingTimeInterval(10)
    while !s.geometryBusy && Date()<deadline { await Task.yield() }
    XCTAssertTrue(s.geometryBusy)
    for _ in 0..<12 { c.keyDown(with:try key(124)) }
    c.keyDown(with:try key(125,flags:.shift)); gate.release(); await settle(s)
    var expected=original
    try SelectionTransform.command(in:original,projection:.init(.translation(13,10)),interpolation:.nearest).apply(to:&expected)
    XCTAssertTrue(s.document==expected); XCTAssertEqual(s.document.layers,original.layers)
    XCTAssertEqual(s.session.undoStack.count,2)
    _=await s.requestHistory(redo:false).value; _=await s.requestHistory(redo:false).value
    XCTAssertTrue(s.document==original)
  }
  @MainActor func testInitialUnresolvedFitIsResolvedBeforeCanvasSizeChanges() async throws {
    let (s,c,w)=try await fixture(); defer {close(s,c,w)}
    s.zoom=0; let oldZoom=s.effectiveZoom,oldPan=s.pan
    s.applyGeometrySheetCommand(.canvasSize(240,180,.topLeft,nil)); await settle(s)
    XCTAssertEqual(s.zoom,oldZoom); XCTAssertEqual(s.effectiveZoom,oldZoom); XCTAssertEqual(s.pan,oldPan)
    _=await s.requestHistory(redo:false).value; XCTAssertEqual(s.effectiveZoom,oldZoom)
  }

}
