import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraft
import PhotoCraftCore
import PhotoCraftImaging

private actor FinderFixture: AllObjectsDetecting {
  var calls = 0
  var delay: Duration
  let fail: Bool
  init(delay: Duration = .zero, fail: Bool = false) { self.delay = delay; self.fail = fail }
  func masks(for image: Surface) async throws -> [DetectedObjectMask] {
    calls += 1
    if delay > .zero { try await Task.sleep(for:delay) }
    if fail { throw CraftError.unavailable("Fixture model unavailable") }
    var a = [UInt8](repeating:0,count:image.width*image.height), b = a
    for y in 4..<12 { for x in 4..<12 { a[y*image.width+x] = x==4 ? 128:255 } }
    for y in 4..<12 { for x in 20..<28 { b[y*image.width+x] = 255 } }
    return try [.init(instanceID:2,mask:SelectionMask(width:image.width,height:image.height,bytes:a)),.init(instanceID:7,mask:SelectionMask(width:image.width,height:image.height,bytes:b))]
  }
}

final class ObjectFinderWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument { try CraftDocument(width:32,height:16) }
  @MainActor private func store(_ detector: FinderFixture = FinderFixture()) throws -> EditorStore {
    let s = EditorStore(document:try fixture(),actions:ActionLibrary(),brushes:BrushLibrary(),skies:SkyLibrary())
    s.allObjectsDetector = detector; s.tool = .objectSelection; return s
  }
  @MainActor func stop(_ s: EditorStore) { s.objectFinder.cancel(); s.geometryTask?.cancel(); s.renderTask?.cancel() }
  @MainActor func testHoverUsesOneInferenceAndSameMaskForClickUndoActions() async throws {
    let detector = FinderFixture(), s = try store(detector), original = s.document
    defer { stop(s) }; s.hoverObject(at:.init(6,6)); await s.objectFinder.task?.value; await s.objectFinder.overlayTask?.value
    XCTAssertNil(s.objectFinder.error); XCTAssertEqual(s.objectFinder.hoveredID,2); XCTAssertNotNil(s.objectFinder.image)
    let identity = s.objectFinder.cacheID
    for x in [6.0,23.0,25.0,6.0] { s.hoverObject(at:.init(x,6)); await s.objectFinder.overlayTask?.value }
    let calls = await detector.calls; XCTAssertEqual(calls,1); XCTAssertEqual(s.document,original); XCTAssertTrue(s.session.undoStack.isEmpty)
    try s.session.startActionRecording(name:"Find")
    s.selectFoundObject(at:.init(6,6),mode:.replace); await s.geometryTask?.value
    XCTAssertEqual(s.objectFinder.cacheID,identity); XCTAssertEqual(try s.document.selectionMask?.bytes[6*32+4],128)
    XCTAssertEqual(s.session.undoStack.count,1)
    let selected = s.document; var replay = original
    try XCTUnwrap(s.session.actionRecording?.snapshot).apply(to:&replay); XCTAssertEqual(replay,selected)
    _ = await s.requestHistory(redo:false).value; XCTAssertEqual(s.document,original); XCTAssertEqual(s.objectFinder.cacheID,identity)
    _ = await s.requestHistory(redo:true).value; XCTAssertEqual(s.document,selected)
    s.objectFinderHardEdge = true; s.selectFoundObject(at:.init(6,6),mode:.replace); await s.geometryTask?.value
    XCTAssertEqual(try s.document.selectionMask?.bytes[6*32+4],255)
    s.hoverObject(at:nil); XCTAssertNil(s.objectFinder.image); XCTAssertNil(s.objectFinder.hoveredID)
  }
  @MainActor func testSourceChangesRefreshCancellationAndToolSwitchDiscardStaleResults() async throws {
    let detector = FinderFixture(delay:.milliseconds(100)), s = try store(detector); defer { stop(s) }
    s.requestObjectFinder(); let old = s.objectFinder.task; let oldID = s.objectFinder.cacheID
    var changed=s.document;changed.layers[0].x=1;s.session=EditorSession(document:changed); XCTAssertNotEqual(s.objectFinder.cacheID,oldID)
    await old?.value; XCTAssertNil(s.objectFinder.scene)
    s.requestObjectFinder(); await s.objectFinder.task?.value; let ready = s.objectFinder.cacheID
    s.selectionSampleAllLayers = true; await s.objectFinder.task?.value; XCTAssertNotEqual(s.objectFinder.cacheID,ready)
    s.requestObjectFinder(force:true); let cancelled = s.objectFinder.task
    let canvas=CraftCanvas(store:s),escape=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53))
    canvas.keyDown(with:escape); await cancelled?.value
    s.refreshObjectFinderIfNeeded(); XCTAssertNil(s.objectFinder.scene); XCTAssertFalse(s.objectFinder.busy)
    s.requestObjectFinder(force:true); let switching = s.objectFinder.task; s.tool = .move; await switching?.value
    XCTAssertNil(s.objectFinder.scene); XCTAssertFalse(s.objectFinder.busy)
    s.tool = .objectSelection; s.requestObjectFinder(); await s.objectFinder.task?.value; XCTAssertNotNil(s.objectFinder.scene)
  }
  @MainActor func testPendingClickAndReloadCloseCancellation() async throws {
    let document = CraftNSDocument(model:try fixture(),actions:ActionLibrary(),skies:SkyLibrary()), s = document.store
    defer { stop(s); document.updateChangeCount(.changeCleared); document.close() }
    s.allObjectsDetector = FinderFixture(delay:.milliseconds(100)); s.tool = .objectSelection
    s.selectFoundObject(at:.init(23,6),mode:.replace); await s.objectFinder.task?.value; await s.geometryTask?.value
    XCTAssertEqual(try s.document.selectionMask?.bytes[6*32+23],255); XCTAssertEqual(s.session.undoStack.count,1)
    s.requestObjectFinder(force:true); let reading = s.objectFinder.task; var loaded = try fixture(); loaded.name = "Reload"
    try document.read(from:NativeArchive.encodeChunked(loaded),ofType:CraftNSDocument.nativeType); await reading?.value
    XCTAssertEqual(s.document,loaded); XCTAssertNil(s.objectFinder.scene)
    s.requestObjectFinder(); let closing = s.objectFinder.task; document.close(); await closing?.value
    XCTAssertNil(s.objectFinder.scene); XCTAssertFalse(s.objectFinder.busy)
  }
  @MainActor func testCanvasHoverClickExitAndOptionsOffscreen() async throws {
    let s = try store(); defer { stop(s) }; s.requestObjectFinder(); await s.objectFinder.task?.value; await s.renderTask?.value
    s.zoom = 12
    let canvas = CraftCanvas(store:s); canvas.frame = .init(x:0,y:0,width:640,height:320)
    func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double) throws -> NSEvent {
      let p = canvas.viewPoint(CGPoint(x:x,y:y))
      return try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
    }
    canvas.mouseMoved(with:try event(.mouseMoved,6,6)); await s.objectFinder.overlayTask?.value
    XCTAssertEqual(s.objectFinder.hoveredID,2); XCTAssertNotNil(s.objectFinder.image)
    if let bitmap=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) {canvas.cacheDisplay(in:canvas.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/object-finder-canvas-offscreen.png"))}
    canvas.mouseDown(with:try event(.leftMouseDown,6,6)); canvas.mouseUp(with:try event(.leftMouseUp,6,6)); await s.geometryTask?.value
    XCTAssertEqual(try s.document.selectionMask?.bytes[6*32+6],255)
    canvas.mouseExited(with:try event(.mouseMoved,40,20)); XCTAssertNil(s.objectFinder.hoveredID)
    let host = NSHostingView(rootView:SelectionToolOptionsView(store:s)), window = NSWindow(contentRect:.init(x:0,y:0,width:1200,height:80),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil};host.frame = .init(x:0,y:0,width:1200,height:80);host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));window.displayIfNeeded();host.layoutSubtreeIfNeeded()
    if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/object-finder-options-offscreen.png"))}
  }
  @MainActor func testModelFailureIsVisibleAndDoesNotRetryEveryHover() async throws {
    let detector = FinderFixture(fail:true), s = try store(detector), original = s.document; defer { stop(s) }
    s.hoverObject(at:.init(6,6)); await s.objectFinder.task?.value
    for _ in 0..<10 { s.hoverObject(at:.init(6,6)) }
    let calls = await detector.calls; XCTAssertEqual(calls,1); XCTAssertNotNil(s.objectFinder.error)
    s.selectFoundObject(at:.init(6,6),mode:.replace); XCTAssertEqual(s.document,original); XCTAssertTrue(s.session.undoStack.isEmpty)
    s.objectFinderEnabled=false; XCTAssertNil(s.objectFinder.scene)
  }
  @MainActor func testAPIDetectionMasksHoverSelectionConfigurationAndHistory() async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) { service,document in
      let s=document.store; s.session=EditorSession(document:try self.fixture()); let original=s.document
      s.allObjectsDetector=FinderFixture(); try service.share(document); let share=try XCTUnwrap(service.shares.first?.id)
      let found=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":"selection.findObjects","revision":service.revision(s),"parameters":["includeMasks":true]])
      XCTAssertEqual(found.0.statusCode,200); let json=try XCTUnwrap(JSONSerialization.jsonObject(with:found.1) as? [String:Any])
      let fields=json.filter{["revision","objectFinder","objectMasks"].contains($0.key)}
      let decoded=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:fields)); XCTAssertNoThrow(try BrushAPI.merge(decoded,schema:ObjectFinderAPI.resultSchema))
      let masks=try XCTUnwrap(json["objectMasks"] as? [[String:Any]]); XCTAssertEqual(masks.count,2)
      XCTAssertEqual(Data(base64Encoded:try XCTUnwrap(masks[0]["coverageBase64"] as? String)),Data(try s.objectFinder.scene!.objects[0].mask.bytes))
      let cache=s.objectFinder.cacheID.uuidString
      let hover=try await h.edit(service,document,"selection.hoverObject",["cacheID":cache,"instanceID":2]); XCTAssertEqual(hover,200); XCTAssertEqual(s.objectFinder.hoveredID,2)
      let clear=try await h.edit(service,document,"selection.hoverObject",["cacheID":cache]); XCTAssertEqual(clear,200); XCTAssertNil(s.objectFinder.hoveredID)
      XCTAssertEqual(s.document,original); XCTAssertTrue(s.session.undoStack.isEmpty)
      let config=try await h.edit(service,document,"selection.configure",["hardEdge":true,"finderOverlayColor":["r":1,"g":0,"b":0,"a":0.6]]); XCTAssertEqual(config,200)
      let select=try await h.edit(service,document,"selection.selectFoundObject",["cacheID":cache,"instanceID":2,"mode":"replace"]); XCTAssertEqual(select,200)
      XCTAssertEqual(try s.document.selectionMask?.bytes[6*32+4],255); XCTAssertEqual(s.session.undoStack.count,1)
      let undo=try await h.edit(service,document,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(s.document,original)
      let redo=try await h.edit(service,document,"history.redo"); XCTAssertEqual(redo,200); XCTAssertEqual(try s.document.selectionMask?.bytes[6*32+4],255)
    }
  }
  @MainActor func testInvalidStaleBusyRefreshAndRevokedDetectionAPI() async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) { service,document in
      let s=document.store;s.session=EditorSession(document:try self.fixture());let original=s.document;s.allObjectsDetector=FinderFixture();try service.share(document)
      let bad=try await h.edit(service,document,"selection.findObjects",["refresh":1]);XCTAssertEqual(bad,400)
      let stale=try await h.edit(service,document,"selection.findObjects",revision:"old");XCTAssertEqual(stale,409)
      s.geometryBusy=true;let busy=try await h.edit(service,document,"selection.findObjects");XCTAssertEqual(busy,409);s.geometryBusy=false
      let ok=try await h.edit(service,document,"selection.findObjects");XCTAssertEqual(ok,200);let cache=s.objectFinder.cacheID.uuidString
      let fraction=try await h.edit(service,document,"selection.selectFoundObject",["cacheID":cache,"instanceID":2.5]);XCTAssertEqual(fraction,400)
      let missing=try await h.edit(service,document,"selection.selectFoundObject",["cacheID":cache,"instanceID":99]);XCTAssertEqual(missing,404)
      let fresh=try await h.edit(service,document,"selection.findObjects",["refresh":true]);XCTAssertEqual(fresh,200)
      let expired=try await h.edit(service,document,"selection.selectFoundObject",["cacheID":cache,"instanceID":2]);XCTAssertEqual(expired,409)
      for revoke in [false,true] {
        s.allObjectsDetector=FinderFixture(delay:.milliseconds(200))
        let pending=Task {try await h.edit(service,document,"selection.findObjects",["refresh":true])}
        let end=Date().addingTimeInterval(3);while !s.objectFinder.busy && Date()<end {await Task.yield()};XCTAssertTrue(s.objectFinder.busy)
        if revoke {service.revoke(try XCTUnwrap(service.shares.first?.id))} else {s.cancelActiveOperation()}
        let status=try await pending.value;XCTAssertEqual(status,409);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
      }
    }
  }
}
