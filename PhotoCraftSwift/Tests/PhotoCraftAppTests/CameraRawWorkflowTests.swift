import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class CameraRawWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:24,height:18,depth:depth)
    var p = try Surface(width:24,height:18,depth:depth,colorEncoding:depth == .f32 ? .linearRGB : .sRGB)
    for y in 0..<18 { for x in 0..<24 { p.setPixel(x:x,y:y,Pixel(Float(x+1)/26,Float(y+1)/20,Float((x+y)%13)/14,x == 0 ? 0 : x == 1 ? 0.4 : 1)) } }
    d.layers[0].content = .raster(p); return d
  }
  func filter() -> RasterFilter {
    var f = RasterFilter(.cameraRaw); f.cameraRaw?.exposure = 0.5; f.cameraRaw?.highlights = -25
    f.cameraRaw?.texture = 15; f.cameraRaw?.vibrance = 20; f.cameraRaw?.sharpenAmount = 40; f.cameraRaw?.vignetteAmount = -20
    return f
  }
  func testStrictSettingsPartialDefaultsAndInvalidInputs() throws {
    let s = try CameraRawSettings.decodeJSON(Data(#"{"exposure":1.2,"gradeShadows":{"hue":240,"sat":20}}"#.utf8))
    XCTAssertEqual(s.exposure,1.2); XCTAssertEqual(s.sharpenRadius,1); XCTAssertEqual(s.gradeShadows.lum,0)
    XCTAssertEqual(try CameraRawSettings.decodeJSON(JSONEncoder().encode(s)),s)
    for value in [#"{"exposure":true}"#,#"{"exposure":6}"#,#"{"grainAmount":-1}"#,#"{"hslHue":[0]}"#,#"{"pointCurve":[[10,20],[10,40]]}"#,#"{"curveSplits":[50,25,75]}"#,#"{"gradeGlobal":{"wat":1}}"#,#"{"seed":-1}"#,#"{"unknown":1}"#] {
      XCTAssertThrowsError(try CameraRawSettings.decodeJSON(Data(value.utf8)),value)
    }
    var invalid = CameraRawSettings(); invalid.exposure = .nan; XCTAssertThrowsError(try invalid.validate())
  }
  func testNeutralPreservesAllStorageBitsAndExposureMatchesLinearStops() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth); guard case .raster(let p) = d.layers[0].content else { return XCTFail() }
      XCTAssertEqual(try CameraRawEngine.develop(p,settings:.init()),p)
      var identity = d; try Command.applyFilter(d.layers[0].id,RasterFilter(.cameraRaw)).apply(to:&identity); XCTAssertEqual(identity,d)
    }
    var p = try Surface(width:2,height:1,depth:.f32,colorEncoding:.linearRGB)
    p.setLinearPixel(x:0,y:0,Pixel(0.125,0.25,2,0.5)); p.setLinearPixel(x:1,y:0,Pixel(0.4,0.3,0.2,0))
    var s = CameraRawSettings(); s.exposure = 1
    let out = try CameraRawEngine.develop(p,settings:s), v = out.linearPixel(x:0,y:0)
    XCTAssertEqual(v.r,0.25,accuracy:0.00001); XCTAssertEqual(v.g,0.5,accuracy:0.00001); XCTAssertEqual(v.b,4,accuracy:0.00001); XCTAssertEqual(v.a,0.5)
    XCTAssertEqual(out.linearPixel(x:1,y:0).a,0); XCTAssertGreaterThan(out.linearPixel(x:1,y:0).r,0.7)
  }
  func testEveryAdjustmentFamilyProducesFiniteChangedPixelsAndStableGrain() throws {
    let d = try fixture(.f32); guard case .raster(let p) = d.layers[0].content else { return XCTFail() }
    var variants = [CameraRawSettings]()
    for (key,value): (String,Float) in [("temperature",40),("tint",30),("contrast",40),("highlights",-50),("shadows",30),("whites",20),("blacks",-10),("texture",60),("clarity",45),("dehaze",40),("vibrance",50),("saturation",-25),("curveLights",40),("sharpenAmount",80),("noiseLuminance",50),("noiseColor",50),("vignetteAmount",-60),("grainAmount",60)] { var s = CameraRawSettings(); s[key] = value; variants.append(s) }
    var mixer = CameraRawSettings(); mixer.hslHue[0] = 80; mixer.hslSat[5] = -70; variants.append(mixer)
    var grade = CameraRawSettings(); grade.gradeGlobal.hue = 240; grade.gradeGlobal.sat = 35; variants.append(grade)
    var curve = CameraRawSettings(); curve.pointCurve = [[0,0],[128,180],[255,255]]; variants.append(curve)
    for s in variants {
      let out = try CameraRawEngine.develop(p,settings:s); XCTAssertNotEqual(out,p)
      for y in 0..<18 { for x in 0..<24 { XCTAssertTrue(out.pixel(x:x,y:y).isFinite); XCTAssertEqual(out.pixel(x:x,y:y).a,p.pixel(x:x,y:y).a) } }
    }
    var grain = CameraRawSettings(); grain.grainAmount = 60; grain.seed = .max
    XCTAssertEqual(try CameraRawEngine.develop(p,settings:grain),try CameraRawEngine.develop(p,settings:grain))
  }
  func testSelectionLocksSmartFilterPersistenceAndUnsupportedPSD() throws {
    for depth in PixelDepth.allCases {
      var d = try fixture(depth); d.selection = IntRect(x:8,y:5,width:10,height:8); let original = d
      try Command.applyFilter(d.layers[0].id,filter()).apply(to:&d)
      guard case .raster(let a) = original.layers[0].content,case .raster(let b) = d.layers[0].content else { return XCTFail() }
      XCTAssertEqual(a.pixel(x:4,y:4),b.pixel(x:4,y:4)); XCTAssertNotEqual(a.pixel(x:12,y:9),b.pixel(x:12,y:9))
      var smart = try fixture(depth); try SmartObjectIO.convert(in:smart,selected:[smart.layers[0].id]).apply(to:&smart)
      let content = smart.layers[0].content
      try Command.applyFilter(smart.layers[0].id,filter()).apply(to:&smart)
      XCTAssertEqual(smart.layers[0].content,content); XCTAssertEqual(smart.minimumArchiveVersion,21)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(smart)),smart)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(smart)),smart)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(smart))
      XCTAssertNotEqual(try Renderer.composite(smart),try Renderer.composite(try fixture(depth)))
    }
    var locked = try fixture(); locked.layers[0].locked = true
    XCTAssertThrowsError(try Command.applyFilter(locked.layers[0].id,filter()).apply(to:&locked))
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:#"[{"_obj":"cameraRaw"}]"#))
  }
  @MainActor func testWorkspacePreviewUndoCancelCommitAndNativeView() async throws {
    let original = try fixture(), store = EditorStore(document:original), model = CameraRawWorkspace()
    defer { model.close(); store.renderTask?.cancel() }
    store.beginFilter(.cameraRaw); let draft = try XCTUnwrap(store.filterDraft)
    model.onChange = { store.filterDraft?.filter.cameraRaw = $0 }
    await model.prepare(document:original,draft:draft); XCTAssertTrue(model.ready)
    model.change(filter().cameraRaw!); await model.task?.value; XCTAssertTrue(model.ready)
    XCTAssertEqual(store.document,original); XCTAssertTrue(store.session.undoStack.isEmpty)
    let preview = try XCTUnwrap(model.image); XCTAssertEqual(preview.width,24)
    model.undo(); await model.task?.value; XCTAssertTrue(model.settings.isIdentity)
    model.redo(); await model.task?.value; XCTAssertFalse(model.settings.isIdentity)
    let view = NSHostingView(rootView:CameraRawSheet(store:store,workspace:model)); view.frame = NSRect(x:0,y:0,width:1000,height:700); view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width,0)
    model.close(); store.cancelFilter(); XCTAssertEqual(store.document,original)
    store.beginFilter(.cameraRaw); store.filterDraft?.filter = filter()
    var expected = original; try Command.applyFilter(original.layers[0].id,filter()).apply(to:&expected)
    store.commitFilter(); await store.geometryTask?.value; XCTAssertNil(store.error); XCTAssertEqual(store.document,expected)
    await store.undo(); XCTAssertEqual(store.document,original); await store.redo(); XCTAssertEqual(store.document,expected)
  }
  @MainActor func testNewestPreviewWinsAndClosedWorkspaceDiscardsWorker() async throws {
    let d = try fixture(), model = CameraRawWorkspace(); await model.prepare(document:d,draft:FilterDraft(id:d.layers[0].id,filter:RasterFilter(.cameraRaw)))
    var s = CameraRawSettings(); s.exposure = 2; model.change(s); s.exposure = -1; model.change(s)
    await model.task?.value; XCTAssertTrue(model.ready); XCTAssertEqual(model.settings.exposure,-1)
    model.change(filter().cameraRaw!); let worker = model.task; model.close(); await worker?.value; XCTAssertFalse(model.rendering); XCTAssertNil(model.error)
  }
  @MainActor func testPhotatoAPIEquivalenceHistoryStaleBusyAndNative21Download() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      try service.share(shared); let original = try fixture(); shared.store.session = EditorSession(document:original)
      let id = original.layers[0].id, settings = filter().cameraRaw!
      let json = try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings))
      let params: [String:Any] = ["layerID":id.uuidString,"filter":["kind":"cameraRaw","cameraRaw":json]]
      var expected = original; try Command.applyFilter(id,filter()).apply(to:&expected)
      let status = try await helper.edit(service,shared,"filter.apply",params); XCTAssertEqual(status,200); XCTAssertEqual(shared.store.document,expected)
      let undo = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(shared.store.document,original)
      let stale = try await helper.edit(service,shared,"filter.apply",params,revision:"stale"); XCTAssertEqual(stale,409)
      shared.store.beginFilter(.cameraRaw); let busy = try await helper.edit(service,shared,"filter.apply",params); XCTAssertEqual(busy,409); shared.store.cancelFilter()
      var smart = original; try SmartObjectIO.convert(in:smart,selected:[id]).apply(to:&smart); shared.store.session = EditorSession(document:smart)
      let applied = try await helper.edit(service,shared,"filter.apply",["layerID":smart.layers[0].id.uuidString,"filter":["kind":"cameraRaw","cameraRaw":json]]); XCTAssertEqual(applied,200)
      service.setDocumentTransfersEnabled(true); let shareID = try XCTUnwrap(service.shares.first?.id)
      let old = try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"20"]); XCTAssertEqual(old.0.statusCode,422)
      let file = try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"21"]); XCTAssertEqual(file.0.statusCode,200); XCTAssertEqual(try NativeArchive.decode(file.1),shared.store.document)
    }
  }
  @MainActor func testFactoryShortcutAndRGBOnlyAvailability() throws {
    try PhotoshopMenuTests().withMenus { _,menu in
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first { $0.identifier?.rawValue == "Filter > Camera Raw Filter…" })
      XCTAssertEqual(item.keyEquivalent,"a"); XCTAssertEqual(item.keyEquivalentModifierMask,[.command,.shift])
      XCTAssertEqual(item.action,#selector(AppDelegate.rasterFilterDialog(_:)))
    }
    let store = EditorStore(document:try fixture()); defer { store.renderTask?.cancel() }
    XCTAssertTrue(store.canBeginFilterKind(.cameraRaw))
    store.toggleQuickMask(); XCTAssertFalse(store.canBeginFilterKind(.cameraRaw)); XCTAssertTrue(store.canBeginFilterKind(.gaussianBlur))
    store.beginFilter(.cameraRaw); XCTAssertNil(store.filterDraft)
    var d = store.document; XCTAssertThrowsError(try Command.channel(.filter(.quickMask,filter())).apply(to:&d))
  }
  func testPublishedAdobeEditMatchesNativePipelineAndValidatesContract() throws {
    let original = try fixture(), input = try DocumentIO.encode(original,format:.png)
    let edits: [String:Any] = ["light":["exposure":0.5,"highlights":-25],"color":["vibrance":20],"effects":["texture":15,"vignette":-20],"sharpness":40]
    var payload: [String:Any] = ["image":["source":["url":"https://example.test/input.png"]],"edits":edits,"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
    let request = try AdobeColorEditRequest(data:JSONSerialization.data(withJSONObject:payload))
    XCTAssertEqual(request.settings,filter().cameraRaw)
    let decoded = try RasterIO.read(input,name:"Input"); var expected = decoded
    let layer = Layer(name:"Color Edit",content:.raster(try Renderer.composite(decoded))); expected.layers = [layer]; expected.activeLayerID = layer.id
    try Command.applyFilter(layer.id,filter()).apply(to:&expected)
    XCTAssertEqual(try request.execute(input:input)[0].data,try DocumentIO.encode(expected,format:.png))
    for bad: [String:Any] in [["light":["contrast":0.5]],["light":["exposure":6]],["sharpen":["radius":0.1]],["noiseReduction":["color":true]],["autoTone":true]] {
      payload["edits"] = bad; XCTAssertThrowsError(try AdobeColorEditRequest(data:JSONSerialization.data(withJSONObject:payload)))
    }
  }
}
