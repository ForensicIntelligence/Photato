import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor LUTTransport: AdobeResourceTransport {
  let data: Data
  init(_ data: Data) { self.data = data }
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("No fixture upload.") }
}
final class ColorLookupWorkflowTests: XCTestCase {
  func fixture() throws -> (Data,ColorLookupAdjustment) {
    let bytes = try ColorLUTFile.writeCube(ColorLUT.generated(title:"Swap",size:3) { SIMD3($0.z,$0.x,$0.y) })
    return (bytes,.init(lut:try ColorLUTFile.read(bytes,name:"swap.cube"),dither:false))
  }
  @MainActor func testPreviewCancelCommitUndoEditableMaskAndMenus() async throws {
    _ = NSApplication.shared
    var doc = try CraftDocument(width:8,height:4)
    doc.layers[0].content = .raster(try Surface(width:8,height:4,fill:Pixel(0.8,0.2,0.4)))
    let store = EditorStore(document:doc), value = try fixture().1
    defer { store.renderTask?.cancel() }
    store.beginColorLookup(); XCTAssertTrue(store.hasToneDraft); XCTAssertFalse(store.canBeginLevels)
    store.colorLookupDraft?.adjustment = value; store.render(); await store.renderTask?.value
    XCTAssertEqual(store.document,doc); XCTAssertNotEqual(store.surface,try Renderer.composite(doc))
    store.colorLookupDraft?.preview = false; store.render(); await store.renderTask?.value
    XCTAssertEqual(store.surface,try Renderer.composite(doc))
    store.cancelColorLookup(); XCTAssertEqual(store.document,doc)
    store.beginColorLookup(); store.colorLookupDraft?.adjustment = value
    store.commitColorLookup(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count,1)
    let changed = store.document
    await store.undo(); XCTAssertEqual(store.document,doc)
    await store.redo(); XCTAssertEqual(store.document,changed); await store.undo()
    store.perform(.selection(IntRect(x:2,y:0,width:3,height:4))); store.addColorLookup()
    let layer = try XCTUnwrap(store.activeLayer)
    XCTAssertEqual(layer.mask?.pixel(x:0,y:0),.black); XCTAssertEqual(layer.mask?.pixel(x:2,y:0),.white)
    store.setColorLookup(layer.id,value); await store.geometryTask?.value; XCTAssertEqual(store.activeLayer?.content,.adjustment(.colorLookup(value)))
    store.perform(.lock(layer.id,true)); let locked = store.document
    store.setColorLookup(layer.id,.init()); await store.geometryTask?.value; XCTAssertEqual(store.document,locked)
    let old = NSApp.mainMenu, windows = NSApp.windowsMenu, help = NSApp.helpMenu
    defer { NSApp.mainMenu = old; NSApp.windowsMenu = windows; NSApp.helpMenu = help }
    AppDelegate().buildMenus()
    XCTAssertNotNil(NSApp.mainMenu?.item(withTitle:"Image")?.submenu?.item(withTitle:"Adjustments")?.submenu?.item(withTitle:"Color Lookup…")?.action)
    XCTAssertNotNil(NSApp.mainMenu?.item(withTitle:"Layer")?.submenu?.item(withTitle:"New Adjustment Layer")?.submenu?.item(withTitle:"Color Lookup…")?.action)
  }
  @MainActor func raw(_ service: AutomationService, path: String, data: Data, name: String = "swap.cube") async throws -> (HTTPURLResponse,Data) {
    var req = URLRequest(url:try XCTUnwrap(URL(string:try XCTUnwrap(service.endpoint)+path)))
    req.httpMethod = "POST"; req.httpBody = data; req.timeoutInterval = 10
    req.setValue("Bearer "+(service.token ?? ""),forHTTPHeaderField:"Authorization")
    req.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
    req.setValue(name,forHTTPHeaderField:"X-Photato-LUT-Name")
    let (data,response) = try await URLSession.shared.data(for:req)
    return (try XCTUnwrap(response as? HTTPURLResponse),data)
  }
  @MainActor func testUploadCreateSetDownloadPersistenceApplyAndErrors() async throws {
    let helper = AutomationTests(), (bytes,value) = try fixture()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      var doc = try CraftDocument(width:8,height:4)
      doc.layers[0].content = .raster(try Surface(width:8,height:4,fill:Pixel(0.8,0.2,0.4)))
      shared.store.session = EditorSession(document:doc); try service.share(shared)
      let forbidden = try await raw(service,path:"/v1/luts",data:bytes); XCTAssertEqual(forbidden.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let upload = try await raw(service,path:"/v1/luts",data:bytes); XCTAssertEqual(upload.0.statusCode,201)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with:upload.1) as? [String:Any]), id = try XCTUnwrap(body["lutID"] as? String)
      let params: [String:Any] = ["kind":"colorLookup","lutID":id,"dither":false]
      let created = try await helper.edit(service,shared,"adjustment.create",["adjustment":params]); XCTAssertEqual(created,200)
      let layer = try XCTUnwrap(shared.store.activeLayer), share = try XCTUnwrap(service.shares.first)
      XCTAssertEqual(layer.content,.adjustment(.colorLookup(value)))
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:shared)))
      let downloaded = try await helper.request(service,path:"/v1/documents/\(share.id)/layers/\(layer.id)/lut")
      XCTAssertEqual(downloaded.0.statusCode,200); XCTAssertEqual(downloaded.1,bytes)
      let staleDownload = try await helper.request(service,path:"/v1/documents/\(share.id)/layers/\(layer.id)/lut",headers:["X-Photato-Revision":"stale"]); XCTAssertEqual(staleDownload.0.statusCode,409)
      let native = try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"18"])
      XCTAssertEqual(native.0.statusCode,200); XCTAssertEqual(try NativeArchive.decode(native.1),shared.store.document)
      let old = try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"17"]); XCTAssertEqual(old.0.statusCode,422)
      let changed = try await helper.edit(service,shared,"adjustment.set",["layerID":layer.id.uuidString,"adjustment":["kind":"colorLookup","preset":"cool","dither":false]])
      XCTAssertEqual(changed,200)
      _ = try await helper.edit(service,shared,"history.undo"); _ = try await helper.edit(service,shared,"history.undo")
      XCTAssertEqual(shared.store.document,doc)
      let apply: [String:Any] = ["layerID":doc.layers[0].id.uuidString,"adjustment":params]
      let applied = try await helper.edit(service,shared,"adjustment.apply",apply); XCTAssertEqual(applied,200)
      var expected = doc; try Command.applyAdjustment(doc.layers[0].id,.colorLookup(value)).apply(to:&expected)
      XCTAssertEqual(shared.store.document,expected)
      _ = try await helper.edit(service,shared,"history.undo")
      let stale = try await helper.edit(service,shared,"adjustment.apply",apply,revision:"stale"); XCTAssertEqual(stale,409)
      shared.store.beginColorLookup()
      let busy = try await helper.edit(service,shared,"adjustment.apply",apply); XCTAssertEqual(busy,409)
      shared.store.cancelColorLookup()
      for invalid: [String:Any] in [["kind":"colorLookup","dither":1],["kind":"colorLookup","preset":"missing"],["kind":"colorLookup","lutID":id,"preset":"warm"],["kind":"colorLookup","interpolation":"cubic"],["kind":"colorLookup","dither":NSNull()]] {
        let result = try await helper.edit(service,shared,"adjustment.create",["adjustment":invalid]); XCTAssertEqual(result,400)
      }
      let badName = try await raw(service,path:"/v1/luts",data:bytes,name:"..%2Fswap.cube"); XCTAssertEqual(badName.0.statusCode,400)
      let large = try ColorLUTFile.writeCube(ColorLUTPreset.warm.makeLUT()); XCTAssertGreaterThan(large.count,65536)
      let largeUpload = try await raw(service,path:"/v1/luts",data:large,name:"warm.cube"); XCTAssertEqual(largeUpload.0.statusCode,201)
      service.documentTransferBusy = true
      let transferBusy = try await raw(service,path:"/v1/luts",data:bytes); XCTAssertEqual(transferBusy.0.statusCode,429)
      service.documentTransferBusy = false
      let clear = try await raw(service,path:"/v1/luts/clear",data:Data()); XCTAssertEqual(clear.0.statusCode,200); XCTAssertTrue(service.luts.isEmpty)
      let missing = try await helper.edit(service,shared,"adjustment.apply",apply); XCTAssertEqual(missing,404)
      _ = try await raw(service,path:"/v1/luts",data:bytes)
      service.setDocumentTransfersEnabled(false); XCTAssertTrue(service.luts.isEmpty)
      XCTAssertEqual(shared.store.document,doc)
    }
  }
  @MainActor func testAdobeActionJobUsesSameEngineAndRejectsInvalidData() async throws {
    let (bytes,value) = try fixture()
    let action: [String:Any] = ["_obj":"colorLookup","lookupType":["_enum":"colorLookupType","_value":"3DLUT"],"LUTFormat":["_enum":"LUTFormatType","_value":"LUTFormatCUBE"],"dataOrder":["_enum":"colorLookupOrder","_value":"rgbOrder"],"tableOrder":["_enum":"colorLookupOrder","_value":"bgrOrder"],"LUT3DFileName":"swap.cube","LUT3DFileData":["_rawData":"base64","_data":bytes.base64EncodedString()],"dither":false]
    let json = String(decoding:try JSONSerialization.data(withJSONObject:[action]),as:UTF8.self)
    var doc = try CraftDocument(width:6,height:4)
    doc.layers[0].content = .raster(try Surface(width:6,height:4,fill:Pixel(0.8,0.2,0.4)))
    let program = try PhotoshopActionProgram(actionJSON:json)
    var expected = doc; try Command.applyAdjustment(doc.layers[0].id,.colorLookup(value)).apply(to:&expected)
    XCTAssertEqual(try program.applying(to:doc).session.document,expected)
    let input = try DocumentIO.encode(doc,format:.png), transport = LUTTransport(input)
    let reopened = try DocumentIO.decode(input,native:false,name:"Input")
    let output = try DocumentIO.encode(program.applying(to:reopened).session.document,format:.png)
    let payload: [String:Any] = ["image":["source":["url":"https://example.test/input.png"]],"options":["actions":[["source":["content":json,"contentType":"application/json"]]]],"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport) { service,shared in
      service.setResourceJobsEnabled(true); let before = shared.store.document
      for route in ["/v2/execute-actions","/v1/action-jobs"] {
        let result = try await AutomationActionJobsTests().output(service,submit:route,payload:payload,expectedMediaType:"image/png")
        XCTAssertEqual(result.2,output); XCTAssertEqual(shared.store.document,before)
      }
    }
    var invalid = action; invalid["LUT3DFileData"] = ["_path":"/tmp/unapproved.cube","_kind":"local"]
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:String(decoding:JSONSerialization.data(withJSONObject:[invalid]),as:UTF8.self)))
  }
}
