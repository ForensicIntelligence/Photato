import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

@MainActor private final class CursorAdmissionWindow: NSWindow {
  // XCTest's standalone process does not become a foreground application on this host.
  // Control only the event-admission boundary; real AppKit views/events/hit testing remain in use.
  var cursorKeyState = true
  override var isKeyWindow: Bool { cursorKeyState }
}

final class ToolCursorTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run {
      // AppKit's first document-controller allocation must use the native subclass before windows/cursors.
      _ = NSApplication.shared
      _ = CraftDocumentController(workspaces:WorkspaceLibrary())
    }
  }
  @MainActor private func flags(_ value: NSEvent.ModifierFlags, window: NSWindow? = nil) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with:.flagsChanged,location:.zero,modifierFlags:value,timestamp:1,
      windowNumber:window?.windowNumber ?? 0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:58))
  }
  @MainActor private func mouse(_ type: NSEvent.EventType, _ value: NSEvent.ModifierFlags = [], window: NSWindow? = nil) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(with:type,location:.init(x:50,y:40),modifierFlags:value,timestamp:1,
      windowNumber:window?.windowNumber ?? 0,context:nil,eventNumber:1,clickCount:1,pressure:1))
  }
  @MainActor private func fixture(_ tool: EditorTool) async throws -> (EditorStore,CraftCanvas,NSWindow) {
    var doc = try CraftDocument(width:120,height:80)
    doc.layers[0].content = .raster(try Surface(width:120,height:80,fill:.white))
    let store = EditorStore(document:doc,brushes:BrushLibrary()); store.tool = tool
    let canvas = CraftCanvas(store:store); canvas.frame = .init(x:0,y:0,width:120,height:80)
    let window = CursorAdmissionWindow(contentRect:canvas.frame,styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; window.contentView = canvas
    window.makeKeyAndOrderFront(nil)
    store.updateViewport(size:canvas.bounds.size,backingScale:1); store.setZoom(1,center:true); await store.renderTask?.value
    return (store,canvas,window)
  }
  @MainActor private func close(_ store: EditorStore, _ canvas: CraftCanvas, _ window: NSWindow) {
    canvas.drawingEvents.end(); store.cancelBrush(); store.cancelClone(); store.renderTask?.cancel()
    window.contentView = nil; window.close()
  }
  @MainActor func testAllToolsAndSixteenModifierCombinationsHaveRenderableCachedCursors() throws {
    let modifiers: [NSEvent.ModifierFlags] = [.control,.command,.option,.shift]
    var rows = [[String:Any]]()
    for tool in EditorTool.allCases {
      for bits in 0..<16 {
        let flags = modifiers.enumerated().reduce(NSEvent.ModifierFlags()) { result,item in
          bits & (1 << item.offset) == 0 ? result:result.union(item.element)
        }
        let descriptor = tool.cursor(modifiers:flags)
        let cursor = descriptor.native
        XCTAssertTrue(cursor === descriptor.native,tool.id)
        // macOS can expose dynamic stock arrow/I-beam cursors without a raster image.
        // Validate our own raster artwork; AppKit owns stock pointer presentation.
        if case .symbol = descriptor {
          XCTAssertGreaterThan(cursor.image.size.width,0,tool.id)
          XCTAssertNotNil(cursor.image.tiffRepresentation,tool.id)
        }
        // These modifiers have no dispatched alternate main-tool action today. Never fake one.
        XCTAssertEqual(descriptor,tool.cursor(modifiers:flags.subtracting([.control,.command])),tool.id)
        rows.append(["tool":tool.id,"modifierBits":bits,"cursor":String(describing:descriptor)])
      }
    }
    XCTAssertEqual(rows.count,EditorTool.allCases.count*16)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let url = URL(fileURLWithPath:path); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
      try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathComponent("tool-modifier-matrix.json"))
      try contactSheet().write(to:url.appendingPathComponent("tool-cursors.png"))
    }
  }
  @MainActor private func contactSheet() throws -> Data {
    let examples: [(String,ToolCursor)] = [
      ("Zoom +",.symbol("plus.magnifyingglass")),("Zoom -",.symbol("minus.magnifyingglass")),
      ("Add",.symbol("lasso",.add)),("Subtract",.symbol("lasso",.subtract)),("Intersect",.symbol("lasso",.intersect)),
      ("Source",.symbol("scope")),("Mixer sample",.symbol("eyedropper")),("Dodge",.symbol("sun.max")),("Burn",.symbol("flame")),
      ("Constrain",.symbol("plus",.constrain)),("Center",.symbol("plus",.center)),("Both",.symbol("plus",.constrainCenter)),
      ("Hand",.openHand),("Pan",.closedHand),("Freeze",.symbol("snowflake",.add)),("Thaw",.symbol("snowflake",.subtract))]
    let image = NSImage(size:.init(width:640,height:200))
    image.lockFocus()
    for (index,item) in examples.enumerated() {
      let x = CGFloat(index%8)*80,y = CGFloat(index/8)*100
      (index%2 == 0 ? NSColor(calibratedWhite:0.2,alpha:1):.white).setFill();NSRect(x:x,y:y,width:80,height:100).fill()
      item.1.native.image.draw(in:.init(x:x+24,y:y+34,width:32,height:32))
      (item.0 as NSString).draw(at:.init(x:x+3,y:y+12),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:index%2 == 0 ? NSColor.white:NSColor.black])
    }
    image.unlockFocus()
    return try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation))?.representation(using:.png,properties:[:]))
  }
  @MainActor func testZoomModifierCursorAndActualZoomDirectionAgreeWithoutMouseMotion() async throws {
    let (store,canvas,window) = try await fixture(.zoom); defer { close(store,canvas,window) }
    let original = store.document, history = store.session.undoStack.count
    canvas.flagsChanged(with:try flags(.option,window:window))
    XCTAssertEqual(canvas.toolCursor,.symbol("minus.magnifyingglass"))
    let before = store.effectiveZoom
    canvas.mouseDown(with:try mouse(.leftMouseDown,.option,window:window))
    canvas.mouseUp(with:try mouse(.leftMouseUp,.option,window:window))
    XCTAssertLessThan(store.effectiveZoom,before)
    canvas.flagsChanged(with:try flags([.command,.control,.shift],window:window))
    XCTAssertEqual(canvas.toolCursor,.symbol("plus.magnifyingglass"))
    let smaller = store.effectiveZoom
    canvas.mouseDown(with:try mouse(.leftMouseDown,window:window)); canvas.mouseUp(with:try mouse(.leftMouseUp,window:window))
    XCTAssertGreaterThan(store.effectiveZoom,smaller)
    XCTAssertEqual(store.document,original); XCTAssertEqual(store.session.undoStack.count,history)
    XCTAssertNotEqual(ToolCursor.symbol("plus.magnifyingglass").native.image.tiffRepresentation,ToolCursor.symbol("minus.magnifyingglass").native.image.tiffRepresentation)
  }
  @MainActor func testSelectionOperationStaysCapturedWhileModifiersConstrainGeometry() async throws {
    let (store,canvas,window) = try await fixture(.marquee); defer { close(store,canvas,window) }
    canvas.mouseDown(with:try mouse(.leftMouseDown,.shift,window:window))
    XCTAssertEqual(canvas.selectionDragMode,.add)
    canvas.flagsChanged(with:try flags(.option,window:window))
    XCTAssertEqual(canvas.toolCursor,.symbol("rectangle.dashed",.add))
    canvas.mouseUp(with:try mouse(.leftMouseUp,.option,window:window))
    XCTAssertEqual(canvas.toolCursor,.symbol("rectangle.dashed",.subtract))
    canvas.flagsChanged(with:try flags([.option,.shift],window:window))
    XCTAssertEqual(canvas.toolCursor,.symbol("rectangle.dashed",.intersect))
    store.tool = .polygonLasso; canvas.synchronizeTool()
    canvas.mouseDown(with:try mouse(.leftMouseDown,.option,window:window))
    canvas.mouseUp(with:try mouse(.leftMouseUp,window:window))
    canvas.flagsChanged(with:try flags(.shift,window:window))
    XCTAssertEqual(canvas.toolCursor,.symbol("lasso",.subtract))
  }
  @MainActor func testRetouchCapturedAlternateAndHandRestoration() async throws {
    let (store,canvas,window) = try await fixture(.dodge); defer { close(store,canvas,window) }
    canvas.flagsChanged(with:try flags(.option,window:window)); XCTAssertEqual(canvas.toolCursor,.symbol("flame"))
    canvas.mouseDown(with:try mouse(.leftMouseDown,.option,window:window))
    XCTAssertEqual(try XCTUnwrap(store.cloneDraft).toning,.burn)
    canvas.flagsChanged(with:try flags([],window:window)); XCTAssertEqual(canvas.toolCursor,.symbol("flame"))
    store.cancelClone();canvas.endCursorGesture(try mouse(.leftMouseUp,window:window))
    XCTAssertEqual(canvas.toolCursor,.symbol("sun.max"))
    store.tool = .cloneStamp; canvas.synchronizeTool();canvas.flagsChanged(with:try flags(.option,window:window));XCTAssertEqual(canvas.toolCursor,.symbol("scope"))
    canvas.spaceHeld = true;XCTAssertEqual(canvas.toolCursor,.openHand)
    canvas.mouseDown(with:try mouse(.leftMouseDown,window:window));XCTAssertEqual(canvas.toolCursor,.closedHand)
    canvas.spaceHeld = false;XCTAssertEqual(canvas.toolCursor,.closedHand)
    canvas.mouseUp(with:try mouse(.leftMouseUp,window:window));XCTAssertEqual(canvas.toolCursor,.symbol("paintbrush.pointed"))
  }
  @MainActor func testWindowModifierObservationWorksWithControlFocusAndCleansUpOnDetach() async throws {
    let (store,canvas,window) = try await fixture(.zoom); defer { close(store,canvas,window) }
    let field = NSTextField(string:"Typing"); field.frame = .init(x:5,y:5,width:60,height:20);canvas.addSubview(field); window.makeFirstResponder(field)
    XCTAssertTrue(canvas.hasCursorMonitor)
    XCTAssertTrue(canvas.ownsToolCursor(atWindowPoint:canvas.convert(.init(x:100,y:60),to:nil)))
    XCTAssertFalse(canvas.ownsToolCursor(atWindowPoint:canvas.convert(.init(x:15,y:15),to:nil)))
    XCTAssertFalse(canvas.ownsToolCursor(atWindowPoint:canvas.convert(.init(x:-5,y:15),to:nil)))
    canvas.spaceHeld = true
    let release = try XCTUnwrap(NSEvent.keyEvent(with:.keyUp,location:.zero,modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,characters:" ",charactersIgnoringModifiers:" ",isARepeat:false,keyCode:49))
    canvas.observeCursorModifiers(release);XCTAssertFalse(canvas.spaceHeld)
    let admission = try XCTUnwrap(window as? CursorAdmissionWindow)
    canvas.observeCursorModifiers(try flags(.option,window:window));XCTAssertEqual(canvas.cursorModifiers,.option)
    admission.cursorKeyState = false
    canvas.observeCursorModifiers(try flags(.option,window:window));XCTAssertTrue(canvas.cursorModifiers.isEmpty)
    admission.cursorKeyState = true
    canvas.observeCursorModifiers(try flags(.option,window:window))
    XCTAssertEqual(canvas.toolCursor,.symbol("minus.magnifyingglass"))
    let other = NSWindow(contentRect:.init(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    other.isReleasedWhenClosed = false; defer { other.close() }
    canvas.observeCursorModifiers(try flags([],window:other));XCTAssertTrue(canvas.cursorModifiers.contains(.option))
    canvas.spaceHeld = true;NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:window)
    XCTAssertFalse(canvas.spaceHeld);XCTAssertTrue(canvas.cursorModifiers.isEmpty);XCTAssertFalse(canvas.cursorPointerDown)
    window.contentView = nil;XCTAssertFalse(canvas.hasCursorMonitor);XCTAssertNil(canvas.cursorGestureModifiers)
  }
  @MainActor func testEveryMaskAndLiquifyAlternateUsesSameResolverAsItsCursorAndStroke() async throws {
    let doc = try CraftDocument(width:32,height:24)
    let mask = SelectMaskWorkspace();defer {mask.close()};await mask.prepare(doc,layerID:doc.layers[0].id,fromMask:false)
    let view = SelectMaskCanvasView();view.model = mask
    let pairs: [(SelectionRefinementStroke.Tool,SelectionRefinementStroke.Tool,String)] = [(.add,.subtract,"paintbrush.pointed"),(.subtract,.add,"paintbrush.pointed"),(.refine,.eraseRefinement,"wand.and.stars"),(.eraseRefinement,.refine,"wand.and.stars"),(.lassoAdd,.lassoSubtract,"lasso"),(.lassoSubtract,.lassoAdd,"lasso")]
    for (tool,alternate,symbol) in pairs {
      mask.tool = tool;view.flagsChanged(with:try flags(.option));mask.begin(x:10,y:10,alternate:true)
      XCTAssertEqual(mask.stroke?.tool,alternate)
      XCTAssertEqual(view.toolCursor,.symbol(symbol,[.add,.refine,.lassoAdd].contains(alternate) ? .add:.subtract))
      view.flagsChanged(with:try flags([]));XCTAssertEqual(mask.stroke?.tool,alternate)
      view.beginCursorGesture(try mouse(.leftMouseDown));view.spaceHeld = true
      XCTAssertEqual(view.toolCursor,.symbol(symbol,[.add,.refine,.lassoAdd].contains(alternate) ? .add:.subtract))
      view.endCursorGesture(try mouse(.leftMouseUp));XCTAssertEqual(view.toolCursor,.openHand);view.spaceHeld = false
      mask.stroke = nil
    }
    let liquify = LiquifyWorkspace();defer {liquify.close()}
    // Input admission is independent of the preview render worker.
    liquify.input = try LiquifyInput.prepare(document:doc,layerID:doc.layers[0].id,filterID:nil)
    liquify.settings.width = 32;liquify.settings.height = 24
    let liquidView = LiquifyCanvasView();liquidView.model = liquify
    let liquidPairs: [(LiquifyTool,LiquifyTool,ToolCursor)] = [(.freeze,.thaw,ToolCursor.symbol("snowflake",.subtract)),(.thaw,.freeze,.symbol("snowflake",.add)),(.twirlCw,.twirlCcw,.symbol("arrow.counterclockwise")),(.pucker,.bloat,.symbol("arrow.up.left.and.arrow.down.right")),(.bloat,.pucker,.symbol("arrow.down.right.and.arrow.up.left"))]
    for (tool,alternate,expected) in liquidPairs {
      liquify.tool = tool;liquidView.flagsChanged(with:try flags(.option));liquify.begin(x:10,y:10,pressure:1,alternate:true)
      XCTAssertEqual(liquify.stroke?.tool,alternate);XCTAssertEqual(liquidView.toolCursor,expected)
      liquidView.flagsChanged(with:try flags([]));XCTAssertEqual(liquidView.toolCursor,expected);liquify.stroke = nil
    }
  }
  @MainActor func testContentAwareAndSkyCapturedModesAndPreviewCursor() throws {
    let fill = ContentAwareWorkspace(),view = ContentAwareCanvasView();view.model = fill;defer {fill.close()}
    fill.add = true;view.flagsChanged(with:try flags(.option));XCTAssertEqual(view.toolCursor,.symbol("paintbrush.pointed",.subtract))
    var stroke = ContentAwareStroke();stroke.add = false;fill.stroke = stroke
    view.flagsChanged(with:try flags([]));XCTAssertEqual(view.toolCursor,.symbol("paintbrush.pointed",.subtract))
    view.preview = true;XCTAssertEqual(view.toolCursor,.arrow)
    let sky = SkyWorkspace(document:try CraftDocument(width:32,height:24),library:SkyLibrary())
    defer {sky.close()};let skyView = SkyCanvasView();skyView.model = sky;sky.tool = .brush
    skyView.flagsChanged(with:try flags(.option));XCTAssertEqual(skyView.toolCursor,.symbol("paintbrush.pointed",.subtract))
    sky.tool = .zoom;XCTAssertEqual(skyView.toolCursor,.symbol("minus.magnifyingglass"))
    skyView.spaceHeld = true;XCTAssertEqual(skyView.toolCursor,.openHand)
  }
  @MainActor func testFocusLossCannotLeaveHandFeedbackOnAnyNativeCanvas() throws {
    let store = EditorStore(document:try CraftDocument(width:32,height:24))
    let main = CraftCanvas(store:store);main.panningGesture = true
    let mask = SelectMaskWorkspace(),maskView = SelectMaskCanvasView();maskView.model = mask;maskView.panning = true
    let liquid = LiquifyWorkspace(),liquidView = LiquifyCanvasView();liquidView.model = liquid;liquidView.panning = true
    let fill = ContentAwareWorkspace(),fillView = ContentAwareCanvasView();fillView.model = fill;fillView.panning = true
    let sky = SkyWorkspace(document:store.document,library:SkyLibrary()),skyView = SkyCanvasView();skyView.model = sky;skyView.panning = true
    defer {store.renderTask?.cancel();mask.close();liquid.close();fill.close();sky.close()}
    for view: ModifierCursorView in [main,maskView,liquidView,fillView,skyView] {
      view.beginCursorGesture(try mouse(.leftMouseDown));view.spaceHeld = true
      XCTAssertEqual(view.toolCursor,.closedHand)
      view.clearCursorInput()
      XCTAssertNotEqual(view.toolCursor,.closedHand);XCTAssertNotEqual(view.toolCursor,.openHand)
    }
  }
  @MainActor func testCapabilityDiscoveryNamesAllToolsAndBothInterfaceImpacts() throws {
    let capabilities = try XCTUnwrap(AutomationService.capabilities["toolCursorFeedback"] as? [String:Any])
    XCTAssertEqual(capabilities["tools"] as? [String],EditorTool.allCases.map(\.id))
    XCTAssertEqual(capabilities["presentationOnly"] as? Bool,true)
    XCTAssertEqual((capabilities["modifiers"] as? [String])?.count,4)
    XCTAssertTrue((capabilities["adobe"] as? String)?.contains("no Adobe route") == true)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(capabilities))
  }
}
