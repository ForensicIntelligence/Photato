import AppKit
import CoreImage
import ImageIO
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private actor RawFixtureTransport: AdobeResourceTransport {
  let data: Data
  init(_ data: Data) { self.data = data }
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
    throw AdobeAPIError.unsupported("Fixture uses hosted output.")
  }
}
final class RawDevelopmentWorkflowTests: XCTestCase {
  func data() throws -> Data { try Data(contentsOf:Bundle.module.url(forResource:"synthetic-bayer",withExtension:"dng",subdirectory:"Fixtures/Raw")!) }
  func fixture(_ depth: PixelDepth = .u16) throws -> CraftDocument { try RawSourceIO.open(data(),fileName:"Sensor.dng",depth:depth) }
  func testActualBayerSensorDecodesWithoutPreviewAtAllDepths() throws {
    let bytes = try data(), raw = try XCTUnwrap(CIRAWFilter(imageData:bytes,identifierHint:nil))
    XCTAssertNil(raw.previewImage); XCTAssertEqual(raw.nativeSize,CGSize(width:512,height:384))
    XCTAssertEqual(DocumentOpenFormat.detect(bytes),.raw)
    for depth in PixelDepth.allCases {
      let d = try fixture(depth); XCTAssertEqual(d.depth,depth); XCTAssertEqual(d.width,512); XCTAssertEqual(d.height,384)
      let object = try XCTUnwrap(d.layers[0].smartObject); XCTAssertEqual(object.data,bytes); XCTAssertNotNil(object.rawDevelopment?.decoderVersion)
      guard case .raster(let p) = d.layers[0].content else { return XCTFail() }
      let sample = p.pixel(x:300,y:200); XCTAssertGreaterThan(max(abs(sample.r),abs(sample.g),abs(sample.b)),0); XCTAssertNotEqual(p.pixel(x:40,y:20),p.pixel(x:400,y:300))
      XCTAssertEqual(p.pixel(x:100,y:100).a,1)
      if depth == .f32 { XCTAssertEqual(p.colorEncoding,.linearRGB) }
    }
  }
  func testFloatDecodeMatchesIndependentCoreImageRowsAndOrientation() throws {
    let bytes = try data(), d = try fixture(.f32), raw = try XCTUnwrap(CIRAWFilter(imageData:bytes,identifierHint:nil))
    raw.boostShadowAmount = 1 // Match the explicit native development setting, not the camera-specific default.
    let image = try XCTUnwrap(raw.outputImage), space = CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!
    var values = [Float](repeating:0,count:512*384*4)
    CIContext(options:[.workingColorSpace:space,.outputColorSpace:space,.cacheIntermediates:false]).render(image,toBitmap:&values,rowBytes:512*16,bounds:image.extent,format:.RGBAf,colorSpace:space)
    guard case .raster(let p) = d.layers[0].content else { return XCTFail() }
    for (x,y) in [(20,30),(300,200),(490,360)] {
      let i = (y*512+x)*4,v = p.linearPixel(x:x,y:y)
      XCTAssertEqual(v.r,values[i],accuracy:0.0001); XCTAssertEqual(v.g,values[i+1],accuracy:0.0001); XCTAssertEqual(v.b,values[i+2],accuracy:0.0001)
    }
    var rotated = bytes; let count = Int(bytes[8])+Int(bytes[9])*256
    for index in 0..<count { let at = 10+index*12; if Int(bytes[at])+Int(bytes[at+1])*256 == 274 { rotated[at+8] = 6 } }
    let output = try RawSourceIO.open(rotated,fileName:"Rotated.dng",depth:.f32); XCTAssertEqual(output.width,384); XCTAssertEqual(output.height,512)
    let oriented = try RasterIO.oriented(p,orientation:6)
    guard case .raster(let actual) = output.layers[0].content else { return XCTFail() }
    for (x,y) in [(50,50),(200,300)] { let a = actual.linearPixel(x:x,y:y), b = oriented.linearPixel(x:x,y:y); XCTAssertEqual(a.r,b.r,accuracy:0.0001); XCTAssertEqual(a.g,b.g,accuracy:0.0001); XCTAssertEqual(a.b,b.b,accuracy:0.0001) }
  }
  func testSelectedDecoderMetadataAndVersionPersistence() throws {
    let bytes = try data(), defaultInfo = try RawSourceIO.inspect(bytes)
    let version = try XCTUnwrap(defaultInfo.supportedDecoders.first(where: { $0.hasPrefix("6.") }))
    let info = try RawSourceIO.inspect(bytes,decoderVersion:version); XCTAssertEqual(info.decoderVersion,version)
    var settings = RawDevelopment(); settings.decoderVersion = version
    let d = try RawSourceIO.open(bytes,fileName:"Older decoder.dng",settings:settings)
    XCTAssertEqual(d.layers[0].smartObject?.rawDevelopment?.decoderVersion,version)
    XCTAssertThrowsError(try RawSourceIO.inspect(bytes,decoderVersion:"unavailable"))
  }
  func testSettingsGuardsRejectInvalidTypesUnknownDecoderAndUnsupportedOptions() throws {
    for text in [#"{"exposure":true}"#,#"{"temperature":100}"#,#"{"boost":2}"#,#"{"highlightRecovery":1}"#,#"{"unknown":0}"#,#"{"exposure":null}"#] { XCTAssertThrowsError(try RawDevelopment.decodeJSON(Data(text.utf8))) }
    let d = try fixture(), id = d.layers[0].id
    var settings = RawDevelopment(); settings.decoderVersion = "not-a-decoder"
    XCTAssertThrowsError(try RawSourceIO.command(in:d,layerID:id,settings:settings))
    settings = .init(); settings.lensCorrection = true
    XCTAssertFalse(try RawSourceIO.inspect(data()).lensCorrectionSupported)
    XCTAssertThrowsError(try RawSourceIO.command(in:d,layerID:id,settings:settings))
    XCTAssertThrowsError(try RawSourceIO.open(Data("bad".utf8),fileName:"Fake.dng"))
    let png = try DocumentIO.encode(CraftDocument(width:8,height:8),format:.png)
    XCTAssertFalse(RawSourceIO.recognizes(png)); XCTAssertThrowsError(try RawSourceIO.open(png,fileName:"Fake.dng"))
  }
  func testRedevelopSharedAndIndependentCopiesPreservesOriginalAndHistory() throws {
    var original = try fixture(), copy = original.layers[0]; copy.id = UUID(); copy.x = 10; original.layers.append(copy)
    let id = original.layers[0].id, old = original.layers[0].smartObject!, oldRevision = old.revision
    XCTAssertEqual(oldRevision,old.revision)
    var settings = old.rawDevelopment!; settings.exposure = 0.7; settings.adjustments.vibrance = 25
    var session = EditorSession(document:original)
    try session.execute(RawSourceIO.command(in:original,layerID:id,settings:settings))
    let changed = session.document
    XCTAssertEqual(changed.layers[0].smartObject,changed.layers[1].smartObject); XCTAssertEqual(changed.layers[0].smartObject?.data,old.data)
    XCTAssertNotEqual(changed.layers[0].smartObject?.revision,oldRevision); XCTAssertEqual(changed.layers[1].x,10)
    try session.undo(); XCTAssertEqual(session.document,original); try session.redo(); XCTAssertEqual(session.document,changed)
    var detached = original; try RawSourceIO.command(in:original,layerID:id,settings:settings,allInstances:false).apply(to:&detached)
    XCTAssertNotEqual(detached.layers[0].smartObject?.sourceID,detached.layers[1].smartObject?.sourceID); XCTAssertEqual(detached.layers[1],original.layers[1])
    try detached.validate()
  }
  func testNative22SourceSettingsPersistenceAndExplicitPSDRejection() throws {
    var d = try fixture(); var settings = d.layers[0].smartObject!.rawDevelopment!; settings.temperature = 5000
    try RawSourceIO.command(in:d,layerID:d.layers[0].id,settings:settings).apply(to:&d)
    XCTAssertEqual(d.minimumArchiveVersion,22)
    for bytes in [try NativeArchive.encode(d),try NativeArchive.encodeChunked(d)] {
      let reopened = try NativeArchive.decode(bytes); XCTAssertEqual(reopened,d); XCTAssertEqual(reopened.layers[0].smartObject?.data,try data())
      XCTAssertEqual(try SmartObjectIO.sourceDocument(reopened.layers[0].smartObject!).layers[0].content,d.layers[0].content)
    }
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
    let parent = try CraftDocument(width:800,height:600,depth:.u16), placed = try SmartObjectIO.placed(data:data(),fileName:"Source.dng",in:parent)
    XCTAssertNotNil(placed.smartObject?.rawDevelopment); XCTAssertEqual(placed.smartObject?.data,try data())
  }
  @MainActor func testNativeWorkspaceSensorAndRGBUndoPreviewCancelCommit() async throws {
    let d = try fixture(), store = EditorStore(document:d), model = CameraRawWorkspace()
    defer { model.close(); store.renderTask?.cancel() }
    store.editSmartObjectContents(); let draft = try XCTUnwrap(store.filterDraft)
    XCTAssertNotNil(draft.rawDevelopment)
    model.onChange = { store.filterDraft?.filter.cameraRaw = $0 }; model.onSensorChange = { store.filterDraft?.rawDevelopment = $0 }
    await model.prepare(document:d,draft:draft); XCTAssertTrue(model.ready); XCTAssertNotNil(model.sensorInfo)
    var settings = model.sensorSettings!; settings.exposure = 0.5; model.changeSensor(settings)
    await model.task?.value; XCTAssertTrue(model.ready); XCTAssertEqual(store.document,d)
    var rgb = model.settings; rgb.vibrance = 30; model.change(rgb); await model.task?.value
    model.undo(); await model.task?.value; XCTAssertEqual(model.settings.vibrance,0); XCTAssertEqual(model.sensorSettings?.exposure,0.5)
    model.undo(); await model.task?.value; XCTAssertEqual(model.sensorSettings?.exposure,0)
    model.redo(); await model.task?.value; XCTAssertEqual(model.sensorSettings?.exposure,0.5)
    let view = NSHostingView(rootView:CameraRawSheet(store:store,workspace:model)); view.frame = NSRect(x:0,y:0,width:1000,height:700); view.layoutSubtreeIfNeeded(); XCTAssertGreaterThan(view.fittingSize.width,0)
    model.close(); store.cancelFilter(); XCTAssertEqual(store.document,d)
    store.beginRawDevelopment(); store.filterDraft?.rawDevelopment = settings
    var expected = d; try RawSourceIO.command(in:d,layerID:d.layers[0].id,settings:settings).apply(to:&expected)
    store.commitFilter(); await store.geometryTask?.value; XCTAssertNil(store.error); XCTAssertEqual(store.document,expected)
    await store.undo(); XCTAssertEqual(store.document,d); await store.redo(); XCTAssertEqual(store.document,expected)
  }
  @MainActor func testFileOpenPreservesSourceWithoutWritableRAWAssociation() throws {
    let folder = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at:folder) }
    let url = folder.appendingPathComponent("Camera.dng"); try data().write(to:url)
    let prepared = try PreparedLocalDocument.read(url,format:.raw); XCTAssertNil(prepared.format)
    let document = prepared.makeDocument(url:url); XCTAssertNil(document.fileURL); XCTAssertEqual(document.importedSourceURL,url); XCTAssertTrue(document.openRawDevelopmentOnDisplay)
    XCTAssertEqual(document.store.document.layers[0].smartObject?.data,try data()); XCTAssertTrue(DocumentIO.readableTypes.contains("public.camera-raw-image"))
  }
  @MainActor func testPhotatoRawAPIImportInspectDevelopExportAndGuards() async throws {
    let helper = AutomationTests(), bytes = try data()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      service.setDocumentTransfersEnabled(true); try service.share(shared)
      let original = try fixture(); shared.store.session = EditorSession(document:original)
      let shareID = try XCTUnwrap(service.shares.first?.id), id = original.layers[0].id
      let base = "/v1/documents/\(shareID)"
      let inspect = try await helper.request(service,path:base+"/commands",body:["command":"raw.inspect","revision":service.revision(shared.store),"parameters":["layerID":id.uuidString]])
      XCTAssertEqual(inspect.0.statusCode,200); XCTAssertEqual(shared.store.document,original)
      let params: [String:Any] = ["layerID":id.uuidString,"settings":["exposure":0.5]]
      var settings = original.layers[0].smartObject!.rawDevelopment!; settings.exposure = 0.5
      var expected = original; try RawSourceIO.command(in:original,layerID:id,settings:settings).apply(to:&expected)
      let applied = try await helper.edit(service,shared,"raw.develop",params); XCTAssertEqual(applied,200); XCTAssertEqual(shared.store.document,expected)
      let source = try await helper.request(service,path:base+"/smart-objects/\(id)/source"); XCTAssertEqual(source.0.statusCode,200); XCTAssertEqual(source.1,bytes)
      let old = try await helper.request(service,path:base+"/file.photato",headers:["X-Photato-Archive-Version":"21"]); XCTAssertEqual(old.0.statusCode,422)
      let file = try await helper.request(service,path:base+"/file.photato",headers:["X-Photato-Archive-Version":"22"]); XCTAssertEqual(file.0.statusCode,200); XCTAssertEqual(try NativeArchive.decode(file.1),expected)
      let undo = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(shared.store.document,original)
      let stale = try await helper.edit(service,shared,"raw.develop",params,revision:"stale"); XCTAssertEqual(stale,409)
      shared.store.beginRawDevelopment(); let busy = try await helper.edit(service,shared,"raw.develop",params); XCTAssertEqual(busy,409); shared.store.cancelFilter()
      let invalid = try await helper.edit(service,shared,"raw.develop",["layerID":id.uuidString,"settings":["exposure":true]]); XCTAssertEqual(invalid,400); XCTAssertEqual(shared.store.document,original)
      let imported = try await DocumentIOWorkflowTests().request(service,path:"/v1/documents/import",data:bytes,type:"image/x-adobe-dng"); XCTAssertEqual(imported.0.statusCode,201)
    }
  }
  @MainActor func testPublishedAdobeEditAcceptsRealRAWAndSharesNativeColorPipeline() async throws {
    let bytes = try data(), payload: [String:Any] = ["image":["source":["url":"https://example.test/input.dng"]],"edits":["light":["exposure":0.5],"color":["vibrance":20]],"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
    let request = try AdobeColorEditRequest(data:JSONSerialization.data(withJSONObject:payload))
    var d = try RawSourceIO.open(bytes,fileName:"input.dng")
    let layer = Layer(name:"Color Edit",content:.raster(try Renderer.composite(d))); d.layers = [layer]; d.activeLayerID = layer.id
    var filter = RasterFilter(.cameraRaw); filter.cameraRaw = request.settings; try Command.applyFilter(layer.id,filter).apply(to:&d)
    let expected = try DocumentIO.encode(d,format:.png)
    XCTAssertEqual(try request.execute(input:bytes)[0].data,expected)
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:RawFixtureTransport(bytes)) { service,shared in
      service.setResourceJobsEnabled(true)
      let before = shared.store.document
      let result = try await AutomationActionJobsTests().output(service,submit:"/v2/edit",payload:payload,expectedMediaType:"image/png")
      XCTAssertEqual(result.2,expected); XCTAssertEqual(shared.store.document,before)
    }
  }
}
