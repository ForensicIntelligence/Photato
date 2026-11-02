import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor ClassicTransport: AdobeResourceTransport {
  let data: Data
  init(_ data: Data) { self.data = data }
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("No fixture upload.") }
}
final class ClassicAdjustmentWorkflowTests: XCTestCase {
  @MainActor func testPreviewCancelCommitUndoEditableMaskAndMenus() async throws {
    _ = NSApplication.shared
    for kind in ClassicAdjustment.Kind.allCases {
      var d = try CraftDocument(width:8,height:4)
      d.layers[0].content = .raster(try Surface(width:8,height:4,fill:Pixel(0.8,0.2,0.4)))
      let store = EditorStore(document:d)
      defer { store.renderTask?.cancel() }
      store.beginClassicAdjustment(kind); XCTAssertTrue(store.hasToneDraft); XCTAssertFalse(store.canBeginLevels)
      store.classicAdjustmentDraft?.adjustment.vibrance = 80
      if kind == .exposure {store.classicAdjustmentDraft?.adjustment.exposureSettings = .init(exposure:0.75,offset:0.01,gammaCorrection:1.2)}
      store.classicAdjustmentDraft?.adjustment.matrix[0] = [0,100,0,0]
      store.classicAdjustmentDraft?.adjustment.adjustments[0][0] = 30
      store.render(); await store.renderTask?.value
      XCTAssertEqual(store.document,d)
      XCTAssertNotEqual(store.surface,try Renderer.composite(d))
      store.classicAdjustmentDraft?.preview = false; store.render(); await store.renderTask?.value
      XCTAssertEqual(store.surface,try Renderer.composite(d))
      store.cancelClassicAdjustment(); XCTAssertEqual(store.document,d)
      store.beginClassicAdjustment(kind)
      store.classicAdjustmentDraft?.adjustment.vibrance = 80
      if kind == .exposure {store.classicAdjustmentDraft?.adjustment.exposureSettings = .init(exposure:0.75,offset:0.01,gammaCorrection:1.2)}
      store.classicAdjustmentDraft?.adjustment.matrix[0] = [0,100,0,0]
      store.classicAdjustmentDraft?.adjustment.adjustments[0][0] = 30
      store.commitClassicAdjustment(); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count,1)
      let edited = store.document
      await store.undo(); XCTAssertEqual(store.document,d)
      await store.redo(); XCTAssertEqual(store.document,edited)
      await store.undo()
      store.perform(.selection(IntRect(x:2,y:0,width:3,height:4)))
      store.addClassicAdjustment(kind)
      let layer = try XCTUnwrap(store.activeLayer)
      XCTAssertEqual(layer.mask?.pixel(x:0,y:0),.black); XCTAssertEqual(layer.mask?.pixel(x:2,y:0),.white)
      store.perform(.lock(layer.id,true)); let locked = store.document
      var value = ClassicAdjustment(kind); value.vibrance = 20
      store.setClassicAdjustment(layer.id,value); XCTAssertEqual(store.document,locked)
    }
    let old = NSApp.mainMenu, windows = NSApp.windowsMenu, help = NSApp.helpMenu
    defer { NSApp.mainMenu = old; NSApp.windowsMenu = windows; NSApp.helpMenu = help }
    let app = AppDelegate(); app.buildMenus()
    for kind in ClassicAdjustment.Kind.allCases {
      XCTAssertNotNil(NSApp.mainMenu?.item(withTitle:"Image")?.submenu?.item(withTitle:"Adjustments")?.submenu?.item(withTitle:kind.title+"…")?.action)
      if kind != .vibrance { XCTAssertNotNil(NSApp.mainMenu?.item(withTitle:"Layer")?.submenu?.item(withTitle:"New Adjustment Layer")?.submenu?.item(withTitle:kind.title+"…")?.action) }
    }
  }
  @MainActor func testTypedHTTPCreateSetApplyStateArchiveAndRejections() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      var d = try CraftDocument(width:8,height:4); d.layers[0].content = .raster(try Surface(width:8,height:4,fill:Pixel(0.8,0.2,0.4)))
      shared.store.session = EditorSession(document:d)
      try service.share(shared); service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first)
      for kind in ClassicAdjustment.Kind.allCases {
        var v = ClassicAdjustment(kind); v.vibrance = 40; v.matrix[0] = [0,100,0,0]; v.adjustments[0][0] = 25
        let create = try await helper.edit(service,shared,"adjustment.create",["adjustment":v.apiObject]); XCTAssertEqual(create,200)
        let layer = try XCTUnwrap(shared.store.activeLayer)
        XCTAssertEqual(layer.content,.adjustment(.classic(try ClassicAdjustment.decodeAPI(v.apiObject))))
        let state = service.state(share,document:shared)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:state))
        let native = try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":kind == .exposure ? "67":"17"])
        XCTAssertEqual(native.0.statusCode,200); XCTAssertEqual(try NativeArchive.decode(native.1),shared.store.document)
        let old = try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"16"]); XCTAssertEqual(old.0.statusCode,422)
        let set = try await helper.edit(service,shared,"adjustment.set",["layerID":layer.id.uuidString,"adjustment":ClassicAdjustment(kind).apiObject]); XCTAssertEqual(set,200)
        _ = try await helper.edit(service,shared,"history.undo")
        _ = try await helper.edit(service,shared,"history.undo")
        XCTAssertEqual(shared.store.document,d)
        let apply = try await helper.edit(service,shared,"adjustment.apply",["layerID":d.layers[0].id.uuidString,"adjustment":v.apiObject]); XCTAssertEqual(apply,200)
        var expected = d; try Command.applyAdjustment(d.layers[0].id,.classic(try ClassicAdjustment.decodeAPI(v.apiObject))).apply(to:&expected)
        XCTAssertEqual(shared.store.document,expected)
        _ = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(shared.store.document,d)
      }
      let params: [String:Any] = ["layerID":d.layers[0].id.uuidString,"adjustment":["kind":"vibrance","vibrance":20]]
      let stale = try await helper.edit(service,shared,"adjustment.apply",params,revision:"old"); XCTAssertEqual(stale,409)
      shared.store.beginClassicAdjustment(.vibrance)
      let busy = try await helper.edit(service,shared,"adjustment.apply",params); XCTAssertEqual(busy,409)
      shared.store.cancelClassicAdjustment()
      for value: [String:Any] in [["kind":"vibrance","vibrance":true],["kind":"vibrance","weights":[]],["kind":"channelMixer","matrix":[[]]],["kind":"vibrance","vibrance":101]] {
        let bad = try await helper.edit(service,shared,"adjustment.create",["adjustment":value]); XCTAssertEqual(bad,400)
      }
      XCTAssertEqual(shared.store.document,d)
    }
  }
  @MainActor func testCreationLimitAndNonRGBTargetAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service,shared in
      var doc = try CraftDocument(width:1,height:1)
      doc.layers = (0..<64).map { Layer(name:"Layer \($0)",content:.fill(.white)) }; doc.activeLayerID = doc.layers[0].id
      shared.store.session = EditorSession(document:doc); try service.share(shared)
      let reply = try await helper.edit(service,shared,"adjustment.create",["adjustment":["kind":"vibrance"]])
      XCTAssertEqual(reply,413); XCTAssertEqual(shared.store.document,doc); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      shared.store.session = EditorSession(document:try CraftDocument(width:1,height:1))
      let before = shared.store.document
      let target = try await helper.edit(service,shared,"channel.target",["channel":"Red"]); XCTAssertEqual(target,200)
      let rejected = try await helper.edit(service,shared,"adjustment.create",["adjustment":["kind":"vibrance"]])
      XCTAssertEqual(rejected,422); XCTAssertEqual(shared.store.document,before)
    }
  }
  @MainActor func testAdobePublishedEditJobAndUnsupportedOptions() async throws {
    var doc = try CraftDocument(width:6,height:4); doc.layers[0].content = .raster(try Surface(width:6,height:4,fill:Pixel(0.8,0.2,0.4)))
    let input = try DocumentIO.encode(doc,format:.png), transport = ClassicTransport(input)
    let payload: [String:Any] = ["image":["source":["url":"https://example.test/input.png"]],"edits":["color":["vibrance":40,"saturation":-10]],"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
    let request = try AdobeColorEditRequest(data:JSONSerialization.data(withJSONObject:payload))
    let expected = try request.execute(input:input)[0].data
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport) { service,shared in
      service.setResourceJobsEnabled(true)
      let before = shared.store.document
      let result = try await AutomationActionJobsTests().output(service,submit:"/v2/edit",payload:payload,expectedMediaType:"image/png")
      XCTAssertEqual(result.2,expected); XCTAssertEqual(shared.store.document,before)
    }
    for edits: [String:Any] in [["color":["whiteBalance":"Auto"]],["color":["vibrance":true]],["autoTone":true]] {
      var bad = payload; bad["edits"] = edits
      XCTAssertThrowsError(try AdobeColorEditRequest(data:JSONSerialization.data(withJSONObject:bad)))
    }
  }
}
