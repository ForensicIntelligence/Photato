import AppKit
import XCTest
@testable import PhotoCraft
import PhotoCraftCore
import PhotoCraftImaging

private actor FixedObjects: AllObjectsDetecting {
  let delay: Duration
  let empty: Bool
  var calls = 0
  var input: Surface?
  init(delay: Duration = .zero, empty: Bool = false) { self.delay = delay; self.empty = empty }
  func masks(for image: Surface) async throws -> [DetectedObjectMask] {
    calls += 1; input = image
    if delay > .zero { try await Task.sleep(for: delay) }
    if empty { return [] }
    return try [(7, 6), (2, 1)].map { id, x in
      .init(instanceID: id, mask: try .make(.rectangle(.init(x:x,y:1,width:2,height:3)), width:image.width,height:image.height,antiAlias:false))
    }
  }
}

final class MaskAllObjectsWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:10,height:6,depth:depth)
    d.layers[0].content = .raster(try Surface(width:10,height:6,depth:depth,fill:Pixel(0.2,0.4,0.8)))
    d.selection = .init(x:0,y:0,width:1,height:1)
    return d
  }
  func testSeparateEditableGroupsPreserveSourceSelectionAndArchiveAtAllDepths() async throws {
    for depth in PixelDepth.allCases {
      let original = try fixture(depth), detector = FixedObjects()
      let command = try await MaskAllObjectsInput.command(document:original,layerID:original.layers[0].id,detector:detector)
      let calls = await detector.calls; XCTAssertEqual(calls,1)
      var session = EditorSession(document:original); try session.execute(command)
      let result = session.document, groups = result.layers.filter(\.isGroup)
      XCTAssertEqual(groups.count,2); XCTAssertEqual(groups.map(\.name),["Object 1","Object 2"])
      XCTAssertEqual(result.layers[0],original.layers[0]); XCTAssertEqual(result.selection,original.selection)
      XCTAssertEqual(result.activeLayerID,groups.last?.id)
      XCTAssertEqual(groups[0].mask?.pixel(x:1,y:1).r,1); XCTAssertEqual(groups[0].mask?.pixel(x:6,y:1).r,0)
      XCTAssertEqual(groups[1].mask?.pixel(x:6,y:1).r,1); XCTAssertEqual(groups[1].mask?.pixel(x:1,y:1).r,0)
      XCTAssertEqual(try Renderer.composite(result),try Renderer.composite(original))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
      XCTAssertEqual(session.undoStack.count,1); XCTAssertEqual(session.undoStack.last?.label,"Mask All Objects")
      try session.undo(); XCTAssertEqual(session.document,original); try session.redo(); XCTAssertEqual(session.document,result)
      // Selecting a group and using the ordinary adjustment command must target that object.
      session.selectLayer(groups[0].id)
      try session.execute(.addLayer(Layer(name:"Invert",content:.adjustment(.invert))))
      XCTAssertEqual(session.document.layers.first { $0.name == "Invert" }?.parentID,groups[0].id)
      let before = try Renderer.composite(original), after = try Renderer.composite(session.document)
      XCTAssertNotEqual(after.pixel(x:1,y:1),before.pixel(x:1,y:1))
      XCTAssertEqual(after.pixel(x:6,y:1),before.pixel(x:6,y:1)); XCTAssertEqual(after.pixel(x:0,y:0),before.pixel(x:0,y:0))
      try session.undo(); XCTAssertEqual(session.document.layers,result.layers)
    }
  }
  func testClippingFamilyNestedPlacementLocksAndInputCoordinates() async throws {
    var original = try fixture(); let parent = Layer(name:"Parent",content:.group(.init()))
    original.layers[0].parentID = parent.id; original.layers[0].locked = true; original.layers[0].x = 1
    var clip = Layer(name:"Clip",content:.adjustment(.invert)); clip.parentID = parent.id; clip.clipped = true
    original.layers += [clip,parent]; let id = original.layers[0].id
    let detector = FixedObjects(), command = try await MaskAllObjectsInput.command(document:original,layerID:id,detector:detector)
    let captured = await detector.input
    let input = try XCTUnwrap(captured)
    XCTAssertEqual(input.pixel(x:0,y:0).a,0); XCTAssertEqual(input.pixel(x:1,y:0).a,1)
    var result = original; try command.apply(to:&result)
    XCTAssertEqual(result.layers.prefix(2),original.layers.prefix(2)); XCTAssertEqual(result.layers.last,parent)
    XCTAssertTrue(result.layers.filter(\.isGroup).filter { $0.id != parent.id }.allSatisfy { $0.parentID == parent.id })
    XCTAssertEqual(try Renderer.composite(result),try Renderer.composite(original))
    original.layers[2].locked = true
    XCTAssertThrowsError(try MaskAllObjectsEdit.checkTarget(original,layerID:id))
  }
  func testInvalidMasksBudgetsAndLayerLimitFailAtomically() throws {
    let original = try fixture(), id = original.layers[0].id
    let mask = try SelectionMask.make(.rectangle(.init(x:1,y:1,width:2,height:2)),width:10,height:6,antiAlias:false)
    for objects: [DetectedObjectMask] in [[],[.init(instanceID:0,mask:mask)],[.init(instanceID:1,mask:mask),.init(instanceID:1,mask:mask)], [.init(instanceID:1,mask:try SelectionMask(width:10,height:6,bytes:[UInt8](repeating:0,count:60)))], [.init(instanceID:1,mask:try SelectionMask(width:1,height:1,bytes:[255]))]] {
      var session = EditorSession(document:original)
      XCTAssertThrowsError(try session.execute(.maskAllObjects(.init(layerID:id,objects:objects))))
      XCTAssertEqual(session.document,original); XCTAssertTrue(session.undoStack.isEmpty)
    }
    XCTAssertThrowsError(try MaskAllObjectsEdit.checkBudget(width:4096,height:2048,count:3))
    XCTAssertThrowsError(try MaskAllObjectsEdit.checkBudget(width:Int.max,height:1,count:1))
    XCTAssertThrowsError(try MaskAllObjectsEdit.checkBudget(width:1,height:1,count:65))
    XCTAssertThrowsError(try MaskAllObjectsEdit.checkBudget(width:6000,height:1,count:64))
    var full = original; full.layers += (1..<511).map { Layer(name:"\($0)",content:.group(.init())) }
    XCTAssertThrowsError(try MaskAllObjectsEdit(layerID:id,objects:[.init(instanceID:1,mask:mask),.init(instanceID:2,mask:mask)]).applied(to:full))
  }
  @MainActor func testDesktopContextMenuHistoryCancellationAndReload() async throws {
    let original = try fixture(), document = CraftNSDocument(model:original,actions:ActionLibrary(),skies:SkyLibrary()), s = document.store
    defer { s.renderTask?.cancel(); document.updateChangeCount(.changeCleared); document.close() }
    s.allObjectsDetector = FixedObjects(); XCTAssertTrue(s.canMaskAllObjects())
    s.performLayerPanel(.maskAllObjects,context:original.layers[0].id); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(s.document.layers.filter(\.isGroup).count,2)
    XCTAssertEqual(s.selectedLayerIDs,Set([try XCTUnwrap(s.document.activeLayerID)])); XCTAssertFalse(s.canMaskAllObjects())
    _ = await s.requestHistory(redo:false).value; XCTAssertEqual(s.document,original)
    s.allObjectsDetector = FixedObjects(delay:.seconds(5)); s.maskAllObjects(); XCTAssertTrue(s.geometryBusy)
    s.cancelActiveOperation(); await s.geometryTask?.value
    XCTAssertEqual(s.document,original); XCTAssertTrue(s.session.undoStack.isEmpty)
    s.maskAllObjects(); let task = s.geometryTask
    var loaded = original; loaded.name = "Reloaded"
    try document.read(from:NativeArchive.encodeChunked(loaded),ofType:CraftNSDocument.nativeType)
    await task?.value; XCTAssertEqual(s.document,loaded); XCTAssertFalse(s.geometryBusy)
    try PhotoshopMenuTests().withMenus { _,menu in
      XCTAssertTrue(PhotoshopMenuTests().allItems(menu).contains { $0.identifier?.rawValue == "Layer > Mask All Objects" && $0.action == #selector(AppDelegate.maskAllObjects) && $0.keyEquivalent.isEmpty })
    }
  }
  @MainActor func testAPIEquivalentMasksResultSchemaAndUndo() async throws {
    let h = AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) { service,document in
      let original = try self.fixture(), s = document.store; s.session = EditorSession(document:original)
      s.allObjectsDetector = FixedObjects(); try service.share(document)
      let share = try XCTUnwrap(service.shares.first?.id), id = original.layers[0].id
      let reply = try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":"layer.maskAllObjects","revision":service.revision(s),"parameters":["layerID":id.uuidString]])
      XCTAssertEqual(reply.0.statusCode,200)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1) as? [String:Any])
      // Result extends the standard document-state envelope; validate the declared
      // extension fields with the strict partial-schema helper.
      let fields = object.filter { ["revision","maskAllObjects","createdGroupIDs"].contains($0.key) }
      let json = try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:fields))
      XCTAssertNoThrow(try BrushAPI.merge(json,schema:MaskAllObjectsAPI.resultSchema))
      XCTAssertEqual(object["createdGroupIDs"] as? [String],s.document.layers.filter(\.isGroup).map { $0.id.uuidString })
      var expected = original
      try await MaskAllObjectsInput.command(document:original,layerID:id,detector:FixedObjects()).apply(to:&expected)
      XCTAssertEqual(s.document.layers.map(\.mask),expected.layers.map(\.mask)); XCTAssertEqual(s.document.selection,expected.selection)
      XCTAssertEqual(s.document.layers[0],original.layers[0]); XCTAssertEqual(s.session.undoStack.count,1)
      let result = s.document
      let undo = try await h.edit(service,document,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(s.document,original)
      let redo = try await h.edit(service,document,"history.redo"); XCTAssertEqual(redo,200); XCTAssertEqual(s.document,result)
    }
  }
  @MainActor func testInvalidBusyStaleNoObjectRevokedAndCancelledAPI() async throws {
    let h = AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) { service,document in
      let original = try self.fixture(), s = document.store; s.session = EditorSession(document:original)
      s.allObjectsDetector = FixedObjects(); try service.share(document)
      let p: [String:Any] = ["layerID":original.layers[0].id.uuidString]
      for invalid: [String:Any] in [["layerID":true],p.merging(["sampleAllLayers":true]) { _,v in v }] {
        let status = try await h.edit(service,document,"layer.maskAllObjects",invalid); XCTAssertEqual(status,400)
      }
      let missing = try await h.edit(service,document,"layer.maskAllObjects",["layerID":UUID().uuidString]); XCTAssertEqual(missing,404)
      let stale = try await h.edit(service,document,"layer.maskAllObjects",p,revision:"old"); XCTAssertEqual(stale,409)
      s.geometryBusy = true; let busy = try await h.edit(service,document,"layer.maskAllObjects",p); XCTAssertEqual(busy,409); s.geometryBusy = false
      s.allObjectsDetector = FixedObjects(empty:true)
      let none = try await h.edit(service,document,"layer.maskAllObjects",p); XCTAssertEqual(none,422)
      XCTAssertEqual(s.document,original); XCTAssertTrue(s.session.undoStack.isEmpty)
      for revoke in [false,true] {
        s.allObjectsDetector = FixedObjects(delay:.milliseconds(150))
        let pending = Task { try await h.edit(service,document,"layer.maskAllObjects",p) }
        let end = Date().addingTimeInterval(3); while !s.geometryBusy && Date() < end { await Task.yield() }; XCTAssertTrue(s.geometryBusy)
        if revoke { service.revoke(try XCTUnwrap(service.shares.first?.id)) } else { s.cancelActiveOperation() }
        let status = try await pending.value; XCTAssertEqual(status,409)
        XCTAssertEqual(s.document,original); XCTAssertTrue(s.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testAPILayerBudgetAndRecordingAreExplicit() async throws {
    let h = AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) { service,document in
      var original = try self.fixture(); original.layers += (1..<63).map { Layer(name:"\($0)",content:.group(.init())) }
      let s = document.store; s.session = EditorSession(document:original); s.allObjectsDetector = FixedObjects(); try service.share(document)
      let status = try await h.edit(service,document,"layer.maskAllObjects",["layerID":original.layers[0].id.uuidString])
      XCTAssertEqual(status,413); XCTAssertEqual(s.document,original); XCTAssertTrue(s.session.undoStack.isEmpty)
      s.session = EditorSession(document:try self.fixture()); try s.session.startActionRecording(name:"Masks")
      s.maskAllObjects(); await s.geometryTask?.value
      XCTAssertEqual(s.document.layers.count,3)
      let action = try XCTUnwrap(s.session.actionRecording?.snapshot); var replay = s.document
      XCTAssertThrowsError(try action.apply(to:&replay))
    }
  }
}
