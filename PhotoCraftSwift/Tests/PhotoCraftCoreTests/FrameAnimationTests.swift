import XCTest
@testable import PhotoCraftCore

final class FrameAnimationTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 6)
    d.layers[0].content = .raster(try Surface(width: 2, height: 2, depth: .u8, fill: Pixel(1,0,0)))
    return d
  }
  func testFramesKeepIndependentPropertiesAndSharedPixels() throws {
    let original = try fixture(); let layer = original.layers[0].id
    var s = EditorSession(document: original)
    try s.execute(.animation(.create)); let first = try XCTUnwrap(s.document.animation?.frames.first?.id)
    try s.execute(.animation(.duplicate)); let second = try XCTUnwrap(s.document.animation?.selectedFrameID)
    try s.execute(.move(layer, 4, 3)); try s.execute(.opacity(layer, 0.5)); try s.execute(.visibility(layer, false))
    let count = s.undoStack.count
    try s.selectAnimationFrame(first)
    XCTAssertEqual(s.document.layers[0].x, 0); XCTAssertEqual(s.document.layers[0].opacity, 1); XCTAssertTrue(s.document.layers[0].visible)
    XCTAssertEqual(s.undoStack.count, count)
    try s.execute(.fill(layer, Pixel(0,1,0)))
    try s.selectAnimationFrame(second)
    XCTAssertEqual(s.document.layers[0].x, 4); XCTAssertEqual(s.document.layers[0].opacity, 0.5); XCTAssertFalse(s.document.layers[0].visible)
    guard case .raster(let pixels) = s.document.layers[0].content else { return XCTFail("raster") }
    XCTAssertEqual(pixels.pixel(x:0,y:0), Pixel(0,1,0)); try s.document.validate()
  }
  func testUndoRedoAndSelectionRejectStalePreparedEdits() throws {
    var s = EditorSession(document: try fixture()); try s.execute(.animation(.create))
    let one = s.document; try s.execute(.animation(.duplicate)); let two = s.document
    let edit = try PreparedEdit(command: .animation(.delay(0.3)), document: s.document)
    try s.selectAnimationFrame(one.animation!.selectedFrameID)
    XCTAssertThrowsError(try s.executePrepared(edit))
    try s.undo(); XCTAssertEqual(s.document, one)
    try s.redo(); XCTAssertEqual(s.document, try two.animationDocument(at: one.animation!.selectedFrameID))
  }
  func testAddedDeletedLayersReconcileEveryFrame() throws {
    var s = EditorSession(document: try fixture()); try s.execute(.animation(.create)); try s.execute(.animation(.duplicate))
    let layer = Layer(name: "Second", content: .fill(.black))
    try s.execute(.addLayer(layer)); XCTAssertTrue(s.document.animation!.frames.allSatisfy{$0.layers.contains{$0.layerID==layer.id}})
    try s.execute(.deleteLayer(layer.id)); XCTAssertTrue(s.document.animation!.frames.allSatisfy{!$0.layers.contains{$0.layerID==layer.id}})
    try s.undo(); XCTAssertTrue(s.document.animation!.frames.allSatisfy{$0.layers.count==2})
  }
  func testTweenHasIndependentExpectedMidpointAndPreservesEndpoints() throws {
    var s = EditorSession(document: try fixture()); let layer = s.document.layers[0].id
    try s.execute(.animation(.create)); let first = s.document.animation!.selectedFrameID
    try s.execute(.animation(.duplicate)); try s.execute(.move(layer, 6, 4)); try s.execute(.opacity(layer, 0))
    let last = s.document.animation!.frames[1]
    try s.selectAnimationFrame(first); try s.execute(.animation(.tween(count:1,position:true,opacity:true)))
    let frames = s.document.animation!.frames
    XCTAssertEqual(frames.count,3); XCTAssertEqual(frames[1].layers[0].x,3); XCTAssertEqual(frames[1].layers[0].y,2); XCTAssertEqual(frames[1].layers[0].opacity,0.5)
    XCTAssertEqual(frames[2],last); XCTAssertEqual(s.document.layers[0].x,0)
    try s.undo(); XCTAssertEqual(s.document.animation!.frames.count,2)
  }
  func testFromLayersReorderReverseDelayAndLoop() throws {
    var d = try fixture(); d.layers.append(Layer(name:"Blue",content:.fill(Pixel(0,0,1))))
    var s = EditorSession(document:d); try s.execute(.animation(.fromLayers))
    let first=s.document.animation!.frames[0].id,second=s.document.animation!.frames[1].id
    XCTAssertEqual(s.document.layers.map(\.visible),[true,false])
    try s.selectAnimationFrame(second); XCTAssertEqual(s.document.layers.map(\.visible),[false,true])
    try s.execute(.animation(.delay(0.35)));try s.execute(.animation(.loop(3)));try s.execute(.animation(.reorder(0)))
    XCTAssertEqual(s.document.animation!.frames.map(\.id),[second,first]);XCTAssertEqual(s.document.animation!.frames[0].delay,0.35)
    try s.execute(.animation(.reverse));XCTAssertEqual(s.document.animation!.frames.map(\.id),[first,second])
    try s.execute(.animation(.delete));XCTAssertEqual(s.document.animation!.selectedFrameID,first)
    XCTAssertThrowsError(try s.execute(.animation(.delete)))
    try s.execute(.animation(.remove));XCTAssertNil(s.document.animation)
  }
  func testClockUsesDelaysFiniteLoopsAndZeroDelayFloor() throws {
    var a=FrameAnimation(layers:[]);a.frames[0].delay=0
    var second=AnimationFrame(layers:[],delay:0.3);second.id=UUID();a.frames.append(second);a.loopCount=2
    XCTAssertEqual(try a.playbackFrame(elapsed:0.019,startingAt:0).index,0)
    XCTAssertEqual(try a.playbackFrame(elapsed:0.021,startingAt:0).index,1)
    XCTAssertEqual(try a.playbackFrame(elapsed:0.321,startingAt:0).index,0)
    XCTAssertTrue(try a.playbackFrame(elapsed:0.641,startingAt:0).finished)
    a.loopCount=0;XCTAssertFalse(try a.playbackFrame(elapsed:100,startingAt:1).finished)
    XCTAssertThrowsError(try a.playbackFrame(elapsed:.nan,startingAt:0))
  }
  func testNative50AndScratchHistoryRetainAllFrames() throws {
    var s=EditorSession(document:try fixture(),historyByteLimit:0)
    try s.execute(.animation(.create));try s.execute(.animation(.duplicate));try s.execute(.animation(.delay(0.7)))
    let d=s.document;XCTAssertEqual(d.minimumArchiveVersion,50)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
    XCTAssertGreaterThan(s.historySpilledStates,0);try s.undo();try s.redo();XCTAssertEqual(s.document,d)
    var plist=try XCTUnwrap(PropertyListSerialization.propertyList(from:NativeArchive.encode(d),format:nil) as? [String:Any])
    plist["version"]=49
    XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:plist,format:.binary,options:0)))
  }
  func testPreparedReplacementCannotSilentlyDiscardAnimation() throws {
    var d=try fixture();try Command.animation(.create).apply(to:&d)
    let before=d;var flattened=d;flattened.animation=nil
    let edit=HDRToningEdit(source:d,result:flattened)
    XCTAssertThrowsError(try Command.hdrToning(edit).apply(to:&d));XCTAssertEqual(d,before)
  }
  func testMalformedFrameStateRejectsBeforeSelectionOrEditing() throws {
    var d=try fixture();try Command.animation(.create).apply(to:&d)
    let id=d.animation!.selectedFrameID
    d.animation!.frames[0].layers.append(d.animation!.frames[0].layers[0])
    XCTAssertThrowsError(try d.selectAnimationFrame(id))
    XCTAssertThrowsError(try AnimationCommand.duplicate.apply(to:&d))
    d.animation!.frames=[]
    XCTAssertThrowsError(try AnimationCommand.duplicate.apply(to:&d))
  }
  func testInvalidEditsAndUnimplementedGlobalTransformsAreAtomic() throws {
    var d=try fixture();try Command.animation(.create).apply(to:&d);let before=d
    for c:Command in [.animation(.delay(-1)),.animation(.loop(-1)),.animation(.reorder(3)),.animation(.tween(count:1,position:true,opacity:true)),.canvasSize(10,10,.center,nil)] {
      XCTAssertThrowsError(try c.apply(to:&d));XCTAssertEqual(d,before)
    }
    d.animation!.frames[0].layers[0].opacity=0.4;XCTAssertThrowsError(try d.validate())
  }
}
