import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class FrameIntegrationTests: XCTestCase {
  @MainActor func testNativePropertiesTargetsGestureCancellationAndHistory() async throws {
    let original = try FrameWorkflowTests().frame(), store = EditorStore(document: original, actions: ActionLibrary())
    defer { store.renderTask?.cancel() }
    store.tool = .frame; let frame = try XCTUnwrap(store.selectedFrame)
    store.beginFrameProperties(); let draft = try XCTUnwrap(store.frameDraft)
    draft.definition.shape = .ellipse; draft.definition.strokeWidth = 2
    store.commitFrame(draft); XCTAssertNil(store.error); XCTAssertNil(store.frameDraft)
    let edited = store.document
    let undo = await store.requestHistory(redo:false).value; XCTAssertTrue(undo); XCTAssertEqual(store.document,original)
    let redo = await store.requestHistory(redo:true).value; XCTAssertTrue(redo); XCTAssertEqual(store.document,edited)
    store.selectFrameTarget(frame,target:.contents); XCTAssertEqual(store.activeLayer?.parentID,frame.id)
    store.selectFrameTarget(frame,target:.frame); XCTAssertEqual(store.activeLayer?.id,frame.id)
    let rect = frame.frameBounds!
    var geometry = ArtboardGesture(original:edited,layerID:frame.id,start:.zero,bounds:rect,corner:nil,current:rect)
    geometry.drag(to:CGPoint(x:3,y:2),square:false)
    let gesture = FrameGesture(geometry:geometry,target:.frame,definition:frame.frame!,sourceIDs:[])
    store.frameGesture = gesture; XCTAssertEqual(store.document,edited)
    store.frameGesture = nil; XCTAssertEqual(store.document,edited)
    store.frameGesture = gesture; store.finishFrameGesture(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.selectedFrame?.x,frame.x+3); XCTAssertEqual(store.document.layers[0],edited.layers[0])
    let undone = await store.requestHistory(redo:false).value; XCTAssertTrue(undone); XCTAssertEqual(store.document,edited)
  }
  @MainActor func testDrawOverImageEmbedsSourceInOneUndo() async throws {
    let d = try CraftDocument(width:20,height:15),store = EditorStore(document:d,actions:ActionLibrary())
    defer { store.renderTask?.cancel() }
    var geometry = ArtboardGesture(original:d,layerID:nil,start:CGPoint(x:2,y:3),bounds:.init(x:2,y:3,width:1,height:1),corner:nil,current:.init(x:2,y:3,width:1,height:1))
    geometry.drag(to:CGPoint(x:12,y:11),square:false)
    store.frameGesture = .init(geometry:geometry,target:.both,definition:.init(width:1,height:1,shape:.ellipse),sourceIDs:[d.layers[0].id])
    store.finishFrameGesture(); await store.geometryTask?.value
    XCTAssertNil(store.error); let frame = try XCTUnwrap(store.selectedFrame)
    XCTAssertEqual(frame.frameBounds,.init(x:2,y:3,width:10,height:8)); XCTAssertEqual(frame.frame?.shape,.ellipse)
    let child = try XCTUnwrap(store.document.children(of:frame.id).first)
    XCTAssertNotNil(child.smartObject); XCTAssertEqual(try Renderer.composite(SmartObjectIO.sourceDocument(child.smartObject!)),try Renderer.composite(d))
    let undo = await store.requestHistory(redo:false).value; XCTAssertTrue(undo); XCTAssertEqual(store.document,d)
  }
  @MainActor func testAPIConfigureMatchesNativeAndRejectsInvalidBusyStaleAndOldArchives() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let sourceID = document.store.document.layers[0].id
      let created = try await helper.edit(service,document,"frame.edit",["operation":"create","name":"Frame","bounds":["x":1,"y":1,"width":3,"height":2],"definition":["width":3,"height":2],"layerIDs":[sourceID.uuidString]])
      XCTAssertEqual(created,200)
      let before = document.store.document, frame = try XCTUnwrap(document.store.selectedFrame)
      let fields: [String:Any] = ["width":3,"height":2,"shape":"ellipse","strokeWidth":1]
      let params: [String:Any] = ["operation":"configure","layerID":frame.id.uuidString,"definition":fields]
      var expected = before; try Command.frame(.configure(frame.id,.init(width:3,height:2,shape:.ellipse,strokeWidth:1))).apply(to:&expected)
      let changed = try await helper.edit(service,document,"frame.edit",params);XCTAssertEqual(changed,200);XCTAssertEqual(document.store.document,expected)
      let undo = try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,before)
      let stale = try await helper.edit(service,document,"frame.edit",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFrameProperties()
      let busy = try await helper.edit(service,document,"frame.edit",params);XCTAssertEqual(busy,409);document.store.frameDraft = nil
      var invalid = params;invalid["contents"] = false
      let bad = try await helper.edit(service,document,"frame.edit",invalid);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,before)
      let path = "/v1/documents/\(try XCTUnwrap(service.shares.first?.id))/file.photato"
      let old = try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"27"]);XCTAssertEqual(old.0.statusCode,422)
      let file = try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"28"]);XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),before)
      let state = service.state(service.shares.first!,document:document)
      XCTAssertNotNil(state["frames"])
      for name in ["frame.edit","frame.place"] { XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationCommand.definitions.first { $0.name == name }!.schema)) }
    }
  }
  @MainActor func testAPIPlacementFitContentTransformClearAndSourceGuards() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      let source = CraftNSDocument(model:try CraftDocument(width:2,height:4));service.controller.addDocument(source)
      defer { source.store.renderTask?.cancel();service.controller.removeDocument(source) }
      try service.share(document);try service.share(source)
      let created = try await helper.edit(service,document,"frame.edit",["operation":"create","name":"Frame","bounds":["x":0,"y":0,"width":3,"height":3],"definition":["width":3,"height":3]])
      XCTAssertEqual(created,200);let frame = try XCTUnwrap(document.store.selectedFrame),before = document.store.document
      let sourceID = try XCTUnwrap(service.shares.first { $0.document === source }?.id)
      var params: [String:Any] = ["layerID":frame.id.uuidString,"sourceDocumentID":sourceID.uuidString,"sourceRevision":"stale","fit":"fill"]
      let stale = try await helper.edit(service,document,"frame.place",params);XCTAssertEqual(stale,409);XCTAssertEqual(document.store.document,before)
      params["sourceRevision"] = service.revision(source.store)
      let placed = try await helper.edit(service,document,"frame.place",params);XCTAssertEqual(placed,200)
      let child = try XCTUnwrap(document.store.document.children(of:frame.id).first);XCTAssertNotNil(child.smartObject);XCTAssertEqual(child.affine?.a,1.5)
      let fit = try await helper.edit(service,document,"frame.edit",["operation":"fit","layerID":frame.id.uuidString,"fit":"fit"]);XCTAssertEqual(fit,200);XCTAssertEqual(document.store.document.children(of:frame.id).first?.affine?.a,0.75)
      let moved = try await helper.edit(service,document,"frame.edit",["operation":"contents.transform","layerID":frame.id.uuidString,"transform":["a":1,"b":0,"c":0,"d":1,"tx":2,"ty":1]])
      XCTAssertEqual(moved,200);XCTAssertEqual(document.store.selectedFrame,frame);XCTAssertEqual(document.store.document.children(of:frame.id).first?.smartObject?.data,child.smartObject?.data)
      let clear = try await helper.edit(service,document,"frame.edit",["operation":"clear","layerID":frame.id.uuidString]);XCTAssertEqual(clear,200);XCTAssertTrue(document.store.document.children(of:frame.id).isEmpty)
      let undo = try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertNotNil(document.store.document.children(of:frame.id).first?.smartObject)
      params["sourceDocumentID"] = UUID().uuidString
      let missing = try await helper.edit(service,document,"frame.place",params);XCTAssertEqual(missing,404)
    }
  }
  func testCustomTextContourPreservesCounterAndSchemaAcceptsItsMetadata() throws {
    let text = TextContent(text:"O",size:36),path = try NativeTextLayout.outline(text,dpi:72)
    let (normalized,bounds) = try FrameRenderer.normalized(path)
    let actual = try VectorRasterizer.filledPath(normalized.transformed(.scale(Double(bounds.width),Double(bounds.height))))
    for y in stride(from:1,to:bounds.height,by:2) { for x in stride(from:1,to:bounds.width,by:2) {
      XCTAssertEqual(path.contains(CGPoint(x:bounds.x+x,y:bounds.y+y)),actual.contains(CGPoint(x:x,y:y)))
    } }
    let schema = FrameDefinition.apiSchema["properties"] as! [String:Any]
    XCTAssertNotNil(((schema["customPath"] as? [String:Any])?["properties"] as? [String:Any])?["fillRule"])
  }
}
