import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VanishingWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var d=try CraftDocument(width:64,height:48,depth:depth),s=try Surface(width:64,height:48,depth:depth)
    for y in 0..<48 { for x in 0..<64 { s.setPixel(x:x,y:y,Pixel(Float(x)/64,Float(y)/48,0.4,(x+y)%7==0 ? 0.5:1)) } };d.layers[0].content = .raster(s);return d
  }
  func program()->VanishingProgram {
    var p=VanishingProgram();p.settings.planes=[.init(corners:[.init(4,4),.init(60,4),.init(60,44),.init(4,44)])]
    var b=VanishingOperation(.brush);b.points=[.init(18,20),.init(45,28)];b.color=Pixel(1,0,0);b.diameter=8;p.operations=[b];return p
  }
  @MainActor func testNativePlanesPaintingPasteLocalHistoryCommitReopenCancel() async throws {
    let d=try fixture(),store=EditorStore(document:d,actions:ActionLibrary());defer { store.renderTask?.cancel();store.cancelVanishingPoint() }
    store.beginVanishingPoint();let model=try XCTUnwrap(store.vanishingWorkspace);await model.prepare();XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertTrue(store.hasToneDraft)
    for p in program().settings.planes[0].corners { model.addPoint(p) };await model.task?.value;XCTAssertEqual(model.program.settings.planes.count,1)
    model.beginGesture();model.moveCorner(0,0,to:.init(5,5));model.moveCorner(0,0,to:.init(6,5));model.endGesture();await model.task?.value
    model.undo();await model.task?.value;XCTAssertEqual(model.program.settings.planes[0].corners[0],.init(4,4))
    model.tool = .brush;model.color=Pixel(1,0,0);model.diameter=8;model.stroke([.init(18,20),.init(45,28)]);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Failed brush")
    let painted=model.program;model.undo();await model.task?.value;XCTAssertTrue(model.program.operations.isEmpty);model.redo();await model.task?.value;XCTAssertEqual(model.program,painted)
    let patch=try Surface(width:8,height:6,fill:Pixel(0,1,0));model.paste(patch);await model.task?.value;model.beginGesture();model.movePaste(to:.init(35,20));model.endGesture();await model.task?.value
    XCTAssertEqual(model.program.operations.count,2);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:model.apiState));XCTAssertEqual(store.document,d)
    let expected=try VanishingEdit.prepare(d,layerID:d.layers[0].id,program:model.program,sample:Renderer.composite(d)).result
    store.commitVanishingPoint();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    store.beginVanishingPoint();let reopened=try XCTUnwrap(store.vanishingWorkspace);await reopened.prepare();XCTAssertEqual(reopened.program.settings,expected.vanishingPoint);XCTAssertTrue(reopened.program.operations.isEmpty)
    reopened.tool = .brush;reopened.stroke([.init(20,20)]);let pending=reopened.task;store.cancelVanishingPoint();await pending?.value;XCTAssertEqual(store.document,expected)
    _=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,d)
  }
  @MainActor func testRelatedPlanesCloneSourceAndClipboardSnapshot() async throws {
    let d=try fixture(),model=VanishingWorkspace(document:d,layerID:d.layers[0].id);defer { model.close() };await model.prepare()
    var p=program();p.settings.planes=[.init(corners:[.init(120,120),.init(280,120),.init(360,280),.init(40,280)])];p.operations=[];model.change(p);await model.task?.value
    // Use the source camera's original800×600 canvas for a deterministic perpendicular plane.
    let large=try CraftDocument(width:800,height:600),linked=VanishingWorkspace(document:large,layerID:large.layers[0].id);defer { linked.close() };linked.change(p);linked.tear(.top)
    XCTAssertEqual(linked.program.settings.planes.count,2);XCTAssertEqual(linked.program.settings.planes[1].parent,0)
    linked.removePlane();XCTAssertEqual(linked.program.settings.planes.count,1)
    model.change(program());await model.task?.value;model.tool = .stamp;model.setSource(.init(10,10));model.diameter=4;model.stroke([.init(40,20)]);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Failed clone")
    model.stroke([.init(42,20)]);await model.task?.value;XCTAssertEqual(try XCTUnwrap(model.program.operations.last?.sourcePoint).x,12,accuracy:1e-9);XCTAssertEqual(try XCTUnwrap(model.program.operations.last?.sourcePoint).y,10,accuracy:1e-9)
    let pixels=try Surface(width:6,height:4,fill:Pixel(0,0,1)),content=try ClipboardContent.pixels(pixels)
    await model.pasteClipboard(.native(try content.encoded()));await model.task?.value;XCTAssertEqual(model.program.operations.last?.source?.width,6)
  }
  func testPlacedLayerAlphaLocksPersistenceAndExplicitActionBoundary() throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth);d.layers[0].affine = .scale(0.8,0.8);d.layers[0].x=4;d.layers[0].y=3;d.layers[0].protection=[.transparency]
      let id=d.layers[0].id,edit=try VanishingEdit.prepare(d,layerID:id,program:program(),sample:Renderer.composite(d))
      XCTAssertEqual(edit.result.layers[0].coordinateTransform,d.layers[0].coordinateTransform)
      guard case .raster(let before)=d.layers[0].content,case .raster(let after)=edit.result.layers[0].content else { return XCTFail() }
      XCTAssertNotEqual(before,after);for y in 0..<48 { for x in 0..<64 { XCTAssertEqual(after.pixel(x:x,y:y).a,before.pixel(x:x,y:y).a) } }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edit.result)),edit.result)
      // The transformed raster layer still requires the native format.
      XCTAssertThrowsError(try DocumentIO.encode(edit.result,format:.psd))
      XCTAssertNotNil(DocumentIO.persistenceIssue(edit.result,format:.png))
      XCTAssertNotNil(ActionOperation(recording:.vanishingPoint(edit),in:d).unsupportedReason)
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"vanishingPoint\"}]"))
    }
  }
  @MainActor func testHTTPMatchesNativeAllOperationsArchive32AndGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      let d=try self.fixture(),id=d.layers[0].id;document.store.session=EditorSession(document:d);try service.share(document);service.setDocumentTransfersEnabled(true)
      let settings=self.program().settings.apiValue
      let operations:[[String:Any]]=[
        ["kind":"brush","points":[["x":18,"y":20],["x":45,"y":28]],"color":["r":1,"g":0,"b":0,"a":1],"diameter":8],
        ["kind":"clone","sourcePoint":["x":12,"y":12],"points":[["x":40,"y":30]],"diameter":4],
        ["kind":"paste","sourceLayerID":id.uuidString,"at":["x":0.2,"y":0.2],"width":0.25,"angle":10]]
      let parameters:[String:Any]=["layerID":id.uuidString,"settings":settings,"operations":operations]
      var p=self.program(),clone=VanishingOperation(.clone),paste=VanishingOperation(.paste);clone.sourcePoint = .init(12,12);clone.points=[.init(40,30)];clone.diameter=4
      guard case .raster(let source)=d.layers[0].content else { return XCTFail() };paste.source=source;paste.at = .init(0.2,0.2);paste.width=0.25;paste.angle=10;p.operations += [clone,paste]
      let expected=try VanishingEdit.prepare(d,layerID:id,program:p,sample:Renderer.composite(d)).result
      let status=try await helper.edit(service,document,"filter.vanishingPoint",parameters);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
      let share=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(share)/file.photato"
      let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"31"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"32"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),expected)
      let stale=try await helper.edit(service,document,"filter.vanishingPoint",parameters,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginVanishingPoint();let busy=try await helper.edit(service,document,"filter.vanishingPoint",parameters);XCTAssertEqual(busy,409);document.store.cancelVanishingPoint()
      for bad:[String:Any] in [["layerID":id.uuidString,"settings":["planes":[],"unknown":1]],["layerID":id.uuidString,"operations":[["kind":"brush","points":[["x":true,"y":1]]]]],["layerID":id.uuidString,"operations":[["kind":"brush","points":[["x":2,"y":3]],"sourceLayerID":id.uuidString]]],["layerID":id.uuidString,"newLayer":1],["layerID":id.uuidString,"operations":[["kind":"brush","points":[["x":20,"y":20]],"color":["r":2,"g":0,"b":0,"a":1]]]]] {
        let code=try await helper.edit(service,document,"filter.vanishingPoint",bad);XCTAssertEqual(code,400)
      }
      XCTAssertEqual(document.store.document,expected);_=try await helper.edit(service,document,"history.undo");XCTAssertEqual(document.store.document,d)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:VanishingSettings.apiCapabilities))
    }
  }
  @MainActor func testPerspectiveCloneOnTwentyFourMegapixelsMatchesAuthenticatedAPI() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      var source = try CraftDocument(width: 6_000, height: 4_000)
      var pixels = try Surface(width: source.width, height: source.height, fill: Pixel(0.7, 0.6, 0.5))
      for y in 110..<131 {
        for x in 110..<131 { pixels.setPixel(x: x, y: y, Pixel(0.1, 0.5, 0.8)) }
      }
      source.layers[0].content = .raster(pixels)
      source.selection = IntRect(x: 186, y: 135, width: 12, height: 12)
      document.store.session = EditorSession(document: source)
      try service.share(document)

      var draft = VanishingProgram()
      draft.newLayer = true
      draft.settings.planes = [.init(corners: [.init(80, 80), .init(280, 80), .init(260, 220), .init(95, 220)])]
      var stamp = VanishingOperation(.clone)
      stamp.diameter = 10
      stamp.hardness = 95
      stamp.sourcePoint = .init(120, 120)
      stamp.points = [.init(192, 141)]
      draft.operations = [stamp]

      XCTAssertTrue(document.store.canBeginVanishingPoint)
      document.store.beginVanishingPoint()
      let workspace = try XCTUnwrap(document.store.vanishingWorkspace)
      workspace.change(draft)
      await workspace.task?.value
      XCTAssertTrue(workspace.ready, workspace.error ?? "Missing full-resolution preview")
      document.store.commitVanishingPoint()
      await document.store.geometryTask?.value
      let native = document.store.document
      XCTAssertNil(document.store.error)
      XCTAssertEqual(native.layers.first, source.layers.first)
      XCTAssertEqual(native.layers.count, 2)
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      _ = await document.store.requestHistory(redo: false).value
      XCTAssertEqual(document.store.document, source)

      let parameters: [String: Any] = [
        "layerID": source.layers[0].id.uuidString, "newLayer": true, "settings": draft.settings.apiValue,
        "operations": [["kind": "clone", "sourcePoint": ["x": 120, "y": 120],
                        "points": [["x": 192, "y": 141]], "diameter": 10, "hardness": 95]],
      ]
      let status = try await helper.edit(service, document, "filter.vanishingPoint", parameters)
      XCTAssertEqual(status, 200)
      let authenticated = document.store.document
      XCTAssertEqual(authenticated.layers.last?.content, native.layers.last?.content)
      XCTAssertEqual(authenticated.vanishingPoint, native.vanishingPoint)
      XCTAssertEqual(authenticated.layers.first, source.layers.first)
      XCTAssertEqual(document.store.session.undoStack.count, 1)
    }
  }

  @MainActor func testRetainedVanishingPreviewCommitAndLocalUndoMatchFullDisplay() async throws {
    let source = try fixture(.u16)
    let store = EditorStore(document: source)
    defer { store.cancelVanishingPoint(); store.renderTask?.cancel() }
    store.render()
    await store.renderTask?.value
    let canvas = try XCTUnwrap(store.canvasRasterPreview?.base)
    store.beginVanishingPoint()
    let workspace = try XCTUnwrap(store.vanishingWorkspace)
    await workspace.prepare()
    XCTAssertTrue(workspace.ready)
    XCTAssertTrue(workspace.image === canvas)
    var draft = program()
    draft.newLayer = true
    workspace.change(draft)
    await workspace.task?.value
    let first = try XCTUnwrap(workspace.preparedEdit)
    let full = try ColorManagement.conversionPreview(first.result)
    let preview = try XCTUnwrap(workspace.image)
    XCTAssertEqual(preview.dataProvider?.data as Data?, full.dataProvider?.data as Data?)
    XCTAssertFalse(preview === canvas)
    XCTAssertEqual(store.document, source)

    var different = draft
    different.operations[0].color = Pixel(0, 0, 1)
    workspace.change(different)
    let superseded = workspace.task
    workspace.undo()
    await superseded?.value
    await workspace.task?.value
    XCTAssertEqual(workspace.program, draft)
    XCTAssertEqual(workspace.image?.dataProvider?.data as Data?, full.dataProvider?.data as Data?)
    workspace.undo()
    await workspace.task?.value
    XCTAssertTrue(workspace.image === canvas)
    workspace.redo()
    await workspace.task?.value
    let accepted = try XCTUnwrap(workspace.preparedEdit?.result)
    store.commitVanishingPoint()
    await store.geometryTask?.value
    XCTAssertEqual(store.document.layers.last?.id, accepted.layers.last?.id)
    XCTAssertEqual(store.document, accepted)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(accepted)), accepted)
    XCTAssertEqual(store.session.undoStack.count, 1)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, source)
  }

  @MainActor func testStaleEditorBitmapCannotSeedVanishingPoint() async throws {
    var source = try fixture(.f32)
    source.layers[0].content = .raster(try Surface(width: source.width, height: source.height,
      depth: source.depth, fill: Pixel(0.4, 0.5, 0.6)))
    let store = EditorStore(document: source)
    defer { store.cancelVanishingPoint(); store.renderTask?.cancel() }
    store.render()
    await store.renderTask?.value
    let old = try XCTUnwrap(store.canvasRasterPreview?.base)
    source.layers[0].content = .raster(try Surface(width: source.width, height: source.height,
      depth: source.depth, fill: Pixel(0.8, 0.5, 0.2)))
    store.session = EditorSession(document: source)
    store.beginVanishingPoint()
    let workspace = try XCTUnwrap(store.vanishingWorkspace)
    await workspace.prepare()
    let current = try XCTUnwrap(workspace.image)
    let independent = try ColorManagement.conversionPreview(source)
    XCTAssertFalse(current === old)
    XCTAssertEqual(current.dataProvider?.data as Data?, independent.dataProvider?.data as Data?)
    XCTAssertNotEqual(current.dataProvider?.data as Data?, old.dataProvider?.data as Data?)
  }

  @MainActor func testTinyPerspectiveStampUsesTheSameCoverageInNativeAndAuthenticatedAPI() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let source = try self.fixture()
      let id = source.layers[0].id
      document.store.session = EditorSession(document: source)
      try service.share(document)
      var draft = self.program()
      draft.newLayer = true
      var stamp = VanishingOperation(.clone)
      stamp.sourcePoint = .init(11, 11)
      stamp.points = [.init(32, 24)]
      stamp.diameter = 1
      stamp.hardness = 95
      draft.operations = [stamp]
      document.store.beginVanishingPoint()
      let workspace = try XCTUnwrap(document.store.vanishingWorkspace)
      workspace.change(draft)
      await workspace.task?.value
      XCTAssertTrue(workspace.ready, workspace.error ?? "Missing partial-pixel preview")
      document.store.commitVanishingPoint()
      await document.store.geometryTask?.value
      let native = document.store.document
      guard case .raster(let repair) = native.layers.last?.content else { return XCTFail("Missing correction raster") }
      XCTAssertEqual(try repair.contentBounds(), IntRect(x: 31, y: 23, width: 2, height: 2))
      XCTAssertGreaterThan(repair.pixel(x: 32, y: 24).a, 0.1)
      XCTAssertLessThan(repair.pixel(x: 32, y: 24).a, 0.4)
      XCTAssertEqual(native.layers.first, source.layers.first)
      _ = await document.store.requestHistory(redo: false).value
      XCTAssertEqual(document.store.document, source)
      let request: [String: Any] = [
        "layerID": id.uuidString, "newLayer": true, "settings": draft.settings.apiValue,
        "operations": [["kind": "clone", "sourcePoint": ["x": 11, "y": 11], "points": [["x": 32, "y": 24]],
                        "diameter": 1, "hardness": 95]],
      ]
      let status = try await helper.edit(service, document, "filter.vanishingPoint", request)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(document.store.document.layers.last?.content, native.layers.last?.content)
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      XCTAssertNotNil(VanishingSettings.apiCapabilities["narrowStrokeCoverage"])
    }
  }

  @MainActor func testPhotoshopRelatedPlanesRemainEditableAndRetainTheOriginalPSDRecord() async throws {
    let p = """
    tNaF203
    1
    100
    2
    1268089504
    0
    -1
    0
    -49546.1
    200
    1480 1000 -49546.1 200 0 0 1
    1480 200 -49546.1 200 0 0 5
    1480 1000 1480 -6777.14 0 1 7
    13 977 1480 -6777.14 0 1 3
    2040590144
    1268089504
    45
    2
    1387.27
    4894.87
    1482.74 998.566 1480 -6777.14 0 1 1
    1480 1000 1480 -6777.14 0 1 5
    1482.74 998.566 -4855.6 4319.42 0 2 7
    1482.46 198.403 -4855.6 4319.42 0 2 3
    201 100 0 100 0
    """
    let record = Data((p+"\n").utf8)
    var resource=Data([56,66,73,77,15,160,0,0])
    let length = UInt32(record.count)
    resource.append(contentsOf:[UInt8(truncatingIfNeeded:length>>24),UInt8(truncatingIfNeeded:length>>16),
      UInt8(truncatingIfNeeded:length>>8),UInt8(truncatingIfNeeded:length)])
    resource.append(record)
    if record.count%2 != 0 { resource.append(0) }
    var document = try CraftDocument(width:1600,height:1200)
    document.sourceMetadata = ["psdResources":resource]
    let pose = try PSDCodec.read(DocumentIO.encode(document,format:.psd))
    let settings = try XCTUnwrap(pose.vanishingPoint)
    XCTAssertEqual(settings.planes.count,2)
    XCTAssertEqual(settings.planes[1].parent,0)
    XCTAssertEqual(settings.planes[1].edge,.right)
    XCTAssertLessThan(settings.planes[1].depth,0.01)
    let scene=try VanishingScene(settings,width:1600,height:1200)
    XCTAssertEqual(scene.frames[0].corners[1],scene.frames[1].corners[0])
    XCTAssertEqual(scene.frames[0].corners[2],scene.frames[1].corners[3])
    XCTAssertEqual(scene.frames[1].corners[2].x,1482.74,accuracy:0.005)
    XCTAssertEqual(scene.frames[1].corners[2].y,998.566,accuracy:0.005)

    let store=EditorStore(document:pose)
    defer { store.cancelVanishingPoint(); store.renderTask?.cancel() }
    store.beginVanishingPoint()
    let workspace=try XCTUnwrap(store.vanishingWorkspace)
    await workspace.prepare()
    XCTAssertTrue(workspace.ready, workspace.error ?? "Imported plane preview failed")
    XCTAssertEqual(workspace.program.settings,settings)
    let initial = try XCTUnwrap(workspace.scene)
    workspace.moveCorner(0,0,to:.init(185,220))
    await workspace.task?.value
    let moved=try XCTUnwrap(workspace.scene)
    XCTAssertEqual(moved.frames[0].corners[1],moved.frames[1].corners[0])
    XCTAssertNotEqual(moved.frames[1].corners[2],initial.frames[1].corners[2])
    XCTAssertTrue(workspace.ready)
    workspace.undo()
    await workspace.task?.value
    XCTAssertEqual(workspace.program.settings,settings)
    store.cancelVanishingPoint()

    let archive = try NativeArchive.decode(NativeArchive.encodeChunked(pose))
    XCTAssertEqual(archive.vanishingPoint,settings)
    XCTAssertNil(DocumentIO.persistenceIssue(archive,format:.psd))
    let same = try DocumentIO.encode(archive,format:.psd)
    XCTAssertNotNil(same.range(of:resource))
    var edited=archive
    edited.vanishingPoint?.planes[0].corners[0] = .init(185,220)
    let regenerated = try DocumentIO.encode(edited,format:.psb)
    XCTAssertNil(regenerated.range(of:resource))
    let psb=try PSDCodec.read(regenerated)
    let newer=try XCTUnwrap(psb.vanishingPoint)
    XCTAssertEqual(newer.planes[1].parent,0)
    XCTAssertEqual(newer.planes[1].edge,.right)
    let expected=try VanishingScene(XCTUnwrap(edited.vanishingPoint),width:1600,height:1200)
    let actual=try VanishingScene(newer,width:1600,height:1200)
    for (want,got) in zip(expected.frames[1].corners,actual.frames[1].corners) {
      XCTAssertEqual(got.x,want.x,accuracy:0.001)
      XCTAssertEqual(got.y,want.y,accuracy:0.001)
    }
    edited.vanishingPoint=nil
    let removed=try DocumentIO.encode(edited,format:.psd)
    XCTAssertNil(removed.range(of:resource))
    XCTAssertNil(try PSDCodec.read(removed).vanishingPoint)
  }

  func testNewIndependentVanishingPointPlanesRoundTripInPSD() throws {
    for version in [DocumentIO.Format.psd, .psb] {
      var input=try CraftDocument(width:120,height:96)
      var settings=VanishingSettings()
      settings.planes=[
        .init(corners:[.init(8,8),.init(55,8),.init(55,80),.init(8,80)]),
        .init(corners:[.init(61,10),.init(111,13),.init(106,78),.init(66,75)]),
      ]
      input.vanishingPoint=settings
      let encoded=try DocumentIO.encode(input,format:version)
      let opened=try PSDCodec.read(encoded)
      let resources = try XCTUnwrap(opened.sourceMetadata?["psdResources"])
      let header = try XCTUnwrap(resources.range(of:Data("tNaF203\n2\n".utf8)))
      let footer = try XCTUnwrap(resources.range(of:Data("201\n100\n100\n0\n100\n0\n100\n0\n".utf8)))
      let sceneRecord = try XCTUnwrap(String(data:resources[header.lowerBound..<footer.lowerBound],encoding:.ascii))
      XCTAssertEqual(sceneRecord.components(separatedBy:"\n\n").count-1,18)
      let recovered=try XCTUnwrap(opened.vanishingPoint)
      XCTAssertEqual(recovered.planes.count,2)
      for (a,b) in zip(settings.planes,recovered.planes) {
        XCTAssertNil(b.parent)
        for (want,got) in zip(a.corners,b.corners) {
          XCTAssertEqual(want.x,got.x,accuracy:0.00001)
          XCTAssertEqual(want.y,got.y,accuracy:0.00001)
        }
      }
    }
  }

  func testSquareToCameraUsesFiniteRaysAndPreservesFractionalGridSpacing() throws {
    var document = try CraftDocument(width: 320, height: 240)
    var settings = VanishingSettings()
    settings.planes = [.init(corners: [.init(0,0),.init(320,0),.init(320,240),.init(0,240)])]
    settings.gridSize = 43.75
    document.vanishingPoint = settings
    for format in [DocumentIO.Format.psd,.psb] {
      let file = try DocumentIO.encode(document,format:format)
      let reopened = try PSDCodec.read(file)
      let saved = try XCTUnwrap(reopened.vanishingPoint)
      XCTAssertEqual(saved.gridSize,43.75)
      let resources = try XCTUnwrap(reopened.sourceMetadata?["psdResources"])
      let start = try XCTUnwrap(resources.range(of:Data("tNaF203\n1\n43\n1\n".utf8)))
      let end = try XCTUnwrap(resources.range(of:Data("201\n43.75\n0\n100\n0\n".utf8)))
      let rays = try XCTUnwrap(String(data:resources[start.upperBound..<end.lowerBound],encoding:.ascii))
      XCTAssertTrue(rays.contains("320\n-0.25\n\n-307200\n240\n\n0\n0\n5\n"))
      XCTAssertTrue(rays.contains("-0.25\n240\n\n320\n-307200\n\n0\n1\n3\n"))
      for (expected, actual) in zip(settings.planes[0].corners,saved.planes[0].corners) {
        XCTAssertEqual(actual.x,expected.x,accuracy:1e-7)
        XCTAssertEqual(actual.y,expected.y,accuracy:1e-7)
      }
      var resized = reopened
      resized.vanishingPoint?.gridSize = 91.25
      let changed = try PSDCodec.read(DocumentIO.encode(resized,format:format))
      XCTAssertEqual(changed.vanishingPoint?.gridSize,91.25)
      let changedResources = try XCTUnwrap(changed.sourceMetadata?["psdResources"])
      let raySection = Data(rays.utf8)
      XCTAssertNotNil(changedResources.range(of:raySection))
      XCTAssertNotNil(changedResources.range(of:Data("201\n91.25\n0\n100\n0\n".utf8)))
    }
    for centerX in [135.0,185.0] {
      let quad = [PathPoint(centerX-75,36),.init(centerX+75,36),
                  .init(centerX+86,210),.init(centerX-86,210)]
      document.vanishingPoint?.planes = [.init(corners:quad)]
      let file = try DocumentIO.encode(document,format:.psd)
      let plane = try XCTUnwrap(try PSDCodec.read(file).vanishingPoint?.planes.first)
      XCTAssertNotNil(VanishingScene.inferredFocal(plane.corners,center:.init(160,120)))
      for (expected,actual) in zip(quad,plane.corners) {
        XCTAssertLessThan(hypot(expected.x-actual.x,expected.y-actual.y),0.251)
      }
    }
  }

  @MainActor func testGridSizeEditsReusePreviewAndPersistThroughNativeAndHTTP() async throws {
    var source = try fixture()
    source.vanishingPoint = program().settings
    let layer = try XCTUnwrap(source.activeLayerID)
    let workspace = VanishingWorkspace(document:source,layerID:layer)
    defer { workspace.close() }
    await workspace.prepare()
    workspace.change(program())
    await workspace.task?.value
    let preview = try XCTUnwrap(workspace.image)
    let painted = try XCTUnwrap(workspace.preparedEdit?.result.layers)
    workspace.beginGesture()
    workspace.gridSize = 73
    workspace.gridSize = 73.5
    workspace.endGesture()
    XCTAssertTrue(workspace.ready)
    XCTAssertTrue(workspace.image === preview)
    XCTAssertEqual(workspace.preparedEdit?.result.layers,painted)
    XCTAssertEqual(workspace.preparedEdit?.result.vanishingPoint?.gridSize,73.5)
    workspace.undo()
    XCTAssertEqual(workspace.gridSize,100)
    workspace.redo()
    XCTAssertEqual(workspace.gridSize,73.5)
    let edited = try XCTUnwrap(workspace.preparedEdit?.result)
    let native = try NativeArchive.decode(NativeArchive.encodeChunked(edited))
    XCTAssertEqual(native.vanishingPoint?.gridSize,73.5)

    let helper = AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service, document in
      document.store.session = EditorSession(document:source)
      try service.share(document)
      service.setDocumentTransfersEnabled(true)
      let parameters: [String:Any] = ["layerID":layer.uuidString,"settings":workspace.program.settings.apiValue]
      let status = try await helper.edit(service,document,"filter.vanishingPoint",parameters)
      XCTAssertEqual(status,200)
      XCTAssertEqual(document.store.document.vanishingPoint?.gridSize,73.5)
      let share = try XCTUnwrap(service.shares.first?.id)
      for suffix in ["psd","psb"] {
        let response = try await helper.request(service,path:"/v1/documents/\(share)/file.\(suffix)")
        XCTAssertEqual(response.0.statusCode,200)
        XCTAssertEqual(try PSDCodec.read(response.1).vanishingPoint?.gridSize,73.5)
      }
      let invalid: [String:Any] = ["layerID":layer.uuidString,"settings":["gridSize":1001]]
      let rejected = try await helper.edit(service,document,"filter.vanishingPoint",invalid)
      XCTAssertEqual(rejected,400)
      XCTAssertEqual(document.store.document.vanishingPoint?.gridSize,73.5)
      let undone = try await helper.edit(service,document,"history.undo")
      XCTAssertEqual(undone,200)
      XCTAssertEqual(document.store.document,source)
    }
  }

  func testOwnedPhotoshopMeasurementsPreserveAndUpdateEditableResource() throws {
    // Numeric record from the owned 1600×1200 Photoshop 27.2.0 square reference.
    let header = """
    tNaF203
    1
    20
    1
    925623040 0 -1 0 0 1200
    1600 1200 -7.68e+06 1200 0 0 1
    1600 -0.25 -7.68e+06 1200 0 0 5
    1600 1200 1600 -7.68e+06 0 1 7
    -0.25 1200 1600 -7.68e+06 0 1 3
    """
    let footer = "201\n20.0076\n2\n925623040\n1600\n1200\n1600\n-0.25\n925623040\n1600\n1200\n-0.25\n1200\n20.0076\n1\n"
    let record = Data((header+"\n"+footer).utf8)
    var resource = Data([56,66,73,77,15,160,0,0,0,0,UInt8(record.count>>8),UInt8(record.count&255)])
    resource.append(record)
    if record.count%2 != 0 { resource.append(0) }
    var source = try CraftDocument(width:1600,height:1200)
    source.sourceMetadata = ["psdResources":resource]
    let opened = try PSDCodec.read(DocumentIO.encode(source,format:.psd))
    let settings = try XCTUnwrap(opened.vanishingPoint)
    let lines = try XCTUnwrap(settings.measurements)
    let scene = try VanishingScene(settings,width:1600,height:1200)
    XCTAssertEqual(lines.count,2)
    XCTAssertEqual(settings.measurementScale(for:0),.init(root:0,pixelsPerUnit:20.0076,linkedToGrid:true))
    XCTAssertEqual(try XCTUnwrap(scene.measurementLength(lines[0],settings:settings)),60,accuracy:0.02)
    XCTAssertEqual(try XCTUnwrap(scene.measurementLength(lines[1],settings:settings)),80,accuracy:0.03)
    let archive = try NativeArchive.decode(NativeArchive.encodeChunked(opened))
    XCTAssertEqual(archive.vanishingPoint,settings)
    for format in [DocumentIO.Format.psd,.psb] {
      XCTAssertNotNil(try DocumentIO.encode(archive,format:format).range(of:resource))
      var edited = archive
      edited.vanishingPoint?.measurements?.removeLast()
      edited.vanishingPoint?.setMeasurementScale(.init(root:0,pixelsPerUnit:25,linkedToGrid:true))
      let bytes = try DocumentIO.encode(edited,format:format)
      XCTAssertNotNil(bytes.range(of:Data("925623040 0 -1".utf8)))
      let read = try XCTUnwrap(try PSDCodec.read(bytes).vanishingPoint)
      XCTAssertEqual(read.measurements?.count,1)
      XCTAssertEqual(read.measurementScale(for:0),.init(root:0,pixelsPerUnit:25,linkedToGrid:true))
      XCTAssertEqual(read.effectiveGridSize,25)
    }
  }

  @MainActor func testMeasureModifiersAndNativeHTTPHistory() async throws {
    var source = try fixture()
    source.vanishingPoint = program().settings
    let layer = try XCTUnwrap(source.activeLayerID)
    let workspace = VanishingWorkspace(document:source,layerID:layer)
    defer { workspace.close() }
    await workspace.prepare()
    let image = try XCTUnwrap(workspace.image)
    workspace.tool = .measure
    workspace.measurePlaneDimensions(0)
    XCTAssertEqual(workspace.measurements.count,2)
    workspace.measurementsLinked = true
    workspace.calibrateMeasurement(length:5)
    XCTAssertTrue(workspace.image === image)
    XCTAssertEqual(try XCTUnwrap(workspace.selectedMeasurementLength),5,accuracy:1e-8)
    let calibrated = workspace.program.settings
    workspace.undo()
    XCTAssertNotEqual(workspace.program.settings,calibrated)
    workspace.redo()
    XCTAssertEqual(workspace.program.settings,calibrated)

    let scene = try XCTUnwrap(workspace.scene)
    let line = workspace.measurements[0]
    let frame = scene.frames[0]
    let start = frame.point(line.end), end = frame.point(.init(0.5,0.2))
    let keys: [NSEvent.ModifierFlags] = [.control,.command,.option,.shift]
    let target = VanishingWorkspace.MeasurementTarget.end(0)
    for mask in 0..<16 {
      let flags = keys.enumerated().reduce(into:NSEvent.ModifierFlags()) { flags, key in
        if mask & (1 << key.offset) != 0 { flags.insert(key.element) }
      }
      let constraint = ToolCursor.MeasurementConstraint(flags)
      let cursor = constraint.cursor
      XCTAssertEqual(cursor,ToolCursor.MeasurementConstraint(flags.subtracting(.control)).cursor)
      XCTAssertEqual(ToolCursor.vanishingMeasurement(endpoint:constraint,moving:false,available:true,active:true),cursor)
      let resized = try XCTUnwrap(workspace.editedMeasurement(line,target:target,from:start,to:end,
        constraint:constraint,scene:scene))
      let delta = PathPoint((resized.end.x-resized.start.x)*frame.width,(resized.end.y-resized.start.y)*frame.height)
      if flags.contains(.shift) { XCTAssertEqual(hypot(delta.x,delta.y),frame.height,accuracy:1e-8) }
      if flags.contains(.option) { XCTAssertEqual(delta.x,0,accuracy:1e-8) }
      if flags.contains(.command) && !flags.contains(.option) {
        let steps = atan2(delta.y,delta.x)/(.pi/12)
        XCTAssertEqual(steps,steps.rounded(),accuracy:1e-8)
      }
    }
    XCTAssertEqual(ToolCursor.vanishingMeasurement(endpoint:nil,moving:false,available:true,active:false),.symbol("ruler"))
    let helper = AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      document.store.session = EditorSession(document:source)
      try service.share(document)
      let parameters: [String:Any] = ["layerID":layer.uuidString,"settings":calibrated.apiValue,
        "measurementCalibration":["index":0,"length":5]]
      let status = try await helper.edit(service,document,"filter.vanishingPoint",parameters)
      XCTAssertEqual(status,200)
      XCTAssertEqual(document.store.document.vanishingPoint,workspace.preparedEdit?.result.vanishingPoint)
      XCTAssertEqual(document.store.document.layers,source.layers)
      let invalid: [String:Any] = ["layerID":layer.uuidString,"measurementCalibration":["index":3,"length":5]]
      let rejected = try await helper.edit(service,document,"filter.vanishingPoint",invalid)
      XCTAssertEqual(rejected,400)
      let undone = try await helper.edit(service,document,"history.undo")
      XCTAssertEqual(undone,200)
      XCTAssertEqual(document.store.document,source)
    }
  }

  @MainActor func testNativeAndAPIGrowExistingPSDRepairLayerWithoutAddingLayer() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      var artwork = try CraftDocument(width: 64, height: 48)
      var texture = try Surface(width: 64, height: 48, fill: Pixel(0.2, 0.4, 0.65))
      for y in 25..<32 {
        for x in 39..<46 { texture.setPixel(x: x, y: y, Pixel(0.9, 0.2, 0.15)) }
      }
      artwork.layers[0].content = .raster(texture)
      let blank = try Surface(width: 1, height: 1)
      artwork.layers.append(Layer(name: "Repair", content: .raster(blank)))
      let psd = try DocumentIO.encode(artwork, format: .psd)
      var source = try DocumentIO.decode(psd, native: false, name: "Layered product")
      let repair = try XCTUnwrap(source.layers.first { $0.name == "Repair" })
      guard case .raster(let initial) = repair.content else { return XCTFail("Missing PSD repair raster") }
      XCTAssertEqual(initial.width, 1)
      XCTAssertEqual(initial.height, 1)
      source.activeLayerID = repair.id
      source.selection = IntRect(x: 39, y: 25, width: 7, height: 7)
      document.store.session = EditorSession(document: source)
      try service.share(document)
      service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first?.id)
      document.store.beginVanishingPoint()
      let workspace = try XCTUnwrap(document.store.vanishingWorkspace)
      var draft = self.program()
      draft.operations = []
      XCTAssertFalse(draft.newLayer)
      workspace.change(draft)
      await workspace.task?.value
      workspace.tool = .stamp
      workspace.diameter = 16
      workspace.hardness = 100
      workspace.heal = .on
      workspace.setSource(.init(15.5, 15.5))
      workspace.stroke([.init(42.5, 28.5)])
      await workspace.task?.value
      XCTAssertTrue(workspace.ready, workspace.error ?? "Repair preview failed")
      let prepared = try XCTUnwrap(workspace.preparedEdit?.result)
      let full = try ColorManagement.conversionPreview(prepared)
      XCTAssertEqual(workspace.image?.dataProvider?.data as Data?, full.dataProvider?.data as Data?)
      XCTAssertEqual(document.store.document, source)
      document.store.commitVanishingPoint()
      await document.store.geometryTask?.value
      let native = document.store.document
      XCTAssertEqual(native, prepared)
      XCTAssertEqual(native.layers.map(\.id), source.layers.map(\.id))
      XCTAssertEqual(native.layers.first, source.layers.first)
      XCTAssertEqual(native.activeLayerID, repair.id)
      let target = try XCTUnwrap(native.layers.first { $0.id == repair.id })
      guard case .raster(let pixels) = target.content else { return XCTFail("Missing repaired pixels") }
      XCTAssertEqual(try pixels.contentBounds(), source.selection)
      let before = try Renderer.composite(source), after = try Renderer.composite(native)
      XCTAssertNotEqual(after.pixel(x: 42, y: 28), before.pixel(x: 42, y: 28))
      XCTAssertEqual(after.pixel(x: 38, y: 28), before.pixel(x: 38, y: 28))
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      _ = await document.store.requestHistory(redo: false).value
      XCTAssertEqual(document.store.document, source)

      let request: [String: Any] = ["layerID": repair.id.uuidString, "newLayer": false,
        "settings": draft.settings.apiValue, "operations": [[
          "kind": "clone", "heal": "on", "diameter": 16, "hardness": 100,
          "sourcePoint": ["x": 15.5, "y": 15.5], "points": [["x": 42.5, "y": 28.5]],
        ]],
      ]
      let applied = try await helper.edit(service, document, "filter.vanishingPoint", request)
      XCTAssertEqual(applied, 200)
      XCTAssertEqual(document.store.document, native)
      let (status, archive) = try await helper.request(service, path: "/v1/documents/\(share)/file.photato",
        headers: ["X-Photato-Archive-Version": "32"])
      XCTAssertEqual(status.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decode(archive), native)
      let undo = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(document.store.document, source)
    }
  }

  @MainActor func testHealModesNativeControlsAndAuthenticatedAPI() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      var source = try self.fixture()
      let target = source.layers[0].id
      var paste = try Surface(width: 12, height: 8, fill: Pixel(0.2, 0.4, 0.7))
      paste.setPixel(x: 0, y: 0, .clear)
      var layer = Layer(name: "Clipboard fixture", content: .raster(paste))
      layer.visible = false
      source.layers.append(layer)
      document.store.session = EditorSession(document: source)
      try service.share(document)
      let share = try XCTUnwrap(service.shares.first?.id)
      let path = "/v1/documents/\(share)"
      document.store.beginVanishingPoint()
      let workspace = try XCTUnwrap(document.store.vanishingWorkspace)
      XCTAssertEqual(workspace.heal, .off)
      var draft = self.program()
      draft.operations = []
      draft.newLayer = true
      workspace.change(draft)
      await workspace.task?.value
      workspace.tool = .stamp
      workspace.heal = .luminance
      workspace.setSource(.init(12, 12))
      workspace.diameter = 6
      workspace.hardness = 95
      workspace.stroke([.init(40, 27)])
      await workspace.task?.value
      workspace.tool = .brush
      workspace.heal = .on
      workspace.color = Pixel(0.1, 0.5, 0.7)
      workspace.stroke([.init(35, 28)])
      await workspace.task?.value
      workspace.pasteLayer(layer.id)
      await workspace.task?.value
      XCTAssertEqual(workspace.selectedPasteHeal, .off)
      workspace.setSelectedPasteHeal(.on)
      await workspace.task?.value
      XCTAssertTrue(workspace.ready, workspace.error ?? "Missing healed preview")
      XCTAssertEqual(workspace.program.operations.compactMap(\.heal), [.luminance, .on, .on])
      let workspaceState = workspace.apiState
      XCTAssertEqual(workspaceState["heal"] as? String, "on")
      XCTAssertEqual(workspaceState["selectedPasteHeal"] as? String, "on")
      let accepted = try XCTUnwrap(workspace.preparedEdit?.result)
      let full = try ColorManagement.conversionPreview(accepted)
      XCTAssertEqual(workspace.image?.dataProvider?.data as Data?, full.dataProvider?.data as Data?)
      workspace.undo()
      await workspace.task?.value
      XCTAssertEqual(workspace.selectedPasteHeal, .off)
      workspace.redo()
      await workspace.task?.value
      XCTAssertEqual(workspace.selectedPasteHeal, .on)
      let initialRepairID = try XCTUnwrap(accepted.activeLayerID)
      let initialRepair = try XCTUnwrap(accepted.layers.first { $0.id == initialRepairID })
      let redone = try XCTUnwrap(workspace.preparedEdit?.result)
      let redoneRepairID = try XCTUnwrap(redone.activeLayerID)
      let redoneRepair = try XCTUnwrap(redone.layers.first { $0.id == redoneRepairID })
      XCTAssertEqual(redoneRepair.content, initialRepair.content)
      XCTAssertEqual(document.store.document, source)
      document.store.commitVanishingPoint()
      await document.store.geometryTask?.value
      let native = document.store.document
      let repairID = try XCTUnwrap(native.activeLayerID)
      let repaired = try XCTUnwrap(native.layers.first { $0.id == repairID })
      XCTAssertEqual(native.layers.map(\.id), [target, repairID, layer.id])
      XCTAssertEqual(native.layers.filter { $0.id != repairID }, source.layers)
      XCTAssertEqual(repaired, redoneRepair)
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      _ = await document.store.requestHistory(redo: false).value
      XCTAssertEqual(document.store.document, source)

      let operations: [[String: Any]] = [
        ["kind": "clone", "heal": "luminance", "sourcePoint": ["x": 12, "y": 12],
         "points": [["x": 40, "y": 27]], "diameter": 6, "hardness": 95],
        ["kind": "brush", "heal": "on", "points": [["x": 35, "y": 28]], "diameter": 6, "hardness": 95,
         "color": ["r": 0.1, "g": 0.5, "b": 0.7, "a": 1]],
        ["kind": "paste", "heal": "on", "sourceLayerID": layer.id.uuidString],
      ]
      var request: [String: Any] = ["layerID": target.uuidString, "newLayer": true,
                                    "settings": draft.settings.apiValue, "operations": operations]
      var bad = operations
      bad[0]["heal"] = NSNull()
      request["operations"] = bad
      let invalid = try await helper.edit(service, document, "filter.vanishingPoint", request)
      XCTAssertEqual(invalid, 400)
      XCTAssertEqual(document.store.document, source)
      request["operations"] = operations
      let applied = try await helper.edit(service, document, "filter.vanishingPoint", request)
      XCTAssertEqual(applied, 200)
      let remote = document.store.document
      let remoteRepairID = try XCTUnwrap(remote.activeLayerID)
      let remoteRepair = try XCTUnwrap(remote.layers.first { $0.id == remoteRepairID })
      XCTAssertEqual(remote.layers.map(\.id), [target, remoteRepairID, layer.id])
      XCTAssertEqual(remote.layers.filter { $0.id != remoteRepairID }, source.layers)
      XCTAssertEqual(remoteRepair.content, repaired.content)
      XCTAssertEqual(remote.vanishingPoint, native.vanishingPoint)
      service.setDocumentTransfersEnabled(true)
      let (response, archive) = try await helper.request(service, path: path + "/file.photato",
        headers: ["X-Photato-Archive-Version": "32"])
      XCTAssertEqual(response.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decode(archive), document.store.document)
      let undone = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undone, 200)
      XCTAssertEqual(document.store.document, source)
    }
  }

  @MainActor func testMaximumCanvasCameraMatchesNativeAPIExportAndReplay() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let limit = Surface.maxDimension
      var source = try CraftDocument(width: limit, height: limit)
      let id = source.layers[0].id
      source.layers[0].content = .raster(try Surface(width: limit, height: limit, fill: .white))
      document.store.session = EditorSession(document: source)
      try service.share(document)
      service.setDocumentTransfersEnabled(true)
      var draft = VanishingProgram()
      draft.newLayer = true
      draft.settings.planes = [.init(corners: [.init(80, 80), .init(280, 80), .init(280, 220), .init(80, 220)])]
      var brush = VanishingOperation(.brush)
      brush.points = [.init(185, 140)]
      brush.diameter = 10
      brush.color = Pixel(0.2, 0.5, 0.8)
      draft.operations = [brush]
      document.store.beginVanishingPoint()
      let workspace = try XCTUnwrap(document.store.vanishingWorkspace)
      workspace.change(draft)
      await workspace.task?.value
      XCTAssertTrue(workspace.ready, workspace.error ?? "Missing sparse document preview")
      XCTAssertEqual(workspace.image?.width, 2_048)
      XCTAssertEqual(workspace.image?.height, 2_048)
      document.store.commitVanishingPoint()
      await document.store.geometryTask?.value
      let native = document.store.document
      XCTAssertEqual(native.vanishingPoint?.focalLength, Double(limit))
      XCTAssertEqual(native.layers.first, source.layers.first)
      XCTAssertEqual(native.layers.count, 2)

      let share = try XCTUnwrap(service.shares.first?.id)
      let path = "/v1/documents/\(share)"
      let (summaryResponse, summaryData) = try await helper.request(service, path: path)
      XCTAssertEqual(summaryResponse.statusCode, 200)
      let summary = try XCTUnwrap(JSONSerialization.jsonObject(with: summaryData) as? [String: Any])
      let vanishing = try XCTUnwrap(summary["vanishingPoint"] as? [String: Any])
      let reported = try XCTUnwrap(vanishing["settings"] as? [String: Any])
      XCTAssertEqual((reported["focalLength"] as? NSNumber)?.doubleValue, Double(limit))
      let (_, archive) = try await helper.request(service, path: path + "/file.photato",
        headers: ["X-Photato-Archive-Version": "32"])
      XCTAssertEqual(try NativeArchive.decode(archive), native)
      _ = await document.store.requestHistory(redo: false).value
      XCTAssertEqual(document.store.document, source)

      var request: [String: Any] = [
        "layerID": id.uuidString, "newLayer": true,
        "operations": [["kind": "brush", "points": [["x": 185, "y": 140]], "diameter": 10,
                        "color": ["r": 0.2, "g": 0.5, "b": 0.8, "a": 1]]],
      ]
      for camera in [draft.settings.apiValue, reported] {
        request["settings"] = camera
        let status = try await helper.edit(service, document, "filter.vanishingPoint", request)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(document.store.document.vanishingPoint, native.vanishingPoint)
        XCTAssertEqual(document.store.document.layers.last?.content, native.layers.last?.content)
        XCTAssertEqual(document.store.session.undoStack.count, 1)
        let undo = try await helper.edit(service, document, "history.undo")
        XCTAssertEqual(undo, 200)
        XCTAssertEqual(document.store.document, source)
      }
    }
  }

  @MainActor func testFactoryMenuAndOffscreenWorkspace() async throws {
    try PhotoshopMenuTests().withMenus { app,menu in
      let item=try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first{$0.identifier?.rawValue=="Filter > Vanishing Point…"});XCTAssertEqual(item.action,#selector(AppDelegate.vanishingPoint));XCTAssertEqual(item.keyEquivalent,"v");XCTAssertEqual(item.keyEquivalentModifierMask,[.option,.command]);XCTAssertFalse(app.validateMenuItem(item))
    }
    let d=try fixture(),store=EditorStore(document:d),model=VanishingWorkspace(document:d,layerID:d.layers[0].id);defer { model.close();store.renderTask?.cancel() };model.change(program());await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
    let view=NSHostingView(rootView:VanishingSheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:980,height:740);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,900)
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();let folder=root.appendingPathComponent("artifacts/vanishing-point-offscreen");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try png.write(to:folder.appendingPathComponent(UUID().uuidString+".png")) } }
  }
}
