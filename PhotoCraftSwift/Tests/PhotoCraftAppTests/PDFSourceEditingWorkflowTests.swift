import AppKit
import CoreGraphics
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor PDFSourceEditingTransport: AdobeResourceTransport {
  let files: [URL:Data]
  init(_ files: [URL:Data]) {self.files = files}
  func fetch(_ url: URL) async throws -> Data {guard let data = files[url] else {throw AdobeAPIError.invalid("Missing owned fixture.")};return data}
  func upload(_ data: Data,output: AdobeActionsRequest.Output) async throws {throw AdobeAPIError.unsupported("No external uploads.")}
}

final class PDFSourceEditingWorkflowTests: XCTestCase {
  func pdf(_ green: Bool,pages: Int = 2) throws -> Data {
    let bytes = NSMutableData();var box = CGRect(x:0,y:0,width:12,height:8)
    let consumer = try XCTUnwrap(CGDataConsumer(data:bytes)),context = try XCTUnwrap(CGContext(consumer:consumer,mediaBox:&box,nil))
    for page in 1...pages {
      context.beginPDFPage(nil)
      context.setFillColor(red:page == pages && !green ? 1:0,green:page == pages && green ? 1:0,blue:page == pages ? 0:1,alpha:1)
      context.fill(box);context.endPDFPage()
    }
    context.closePDF();return bytes as Data
  }
  func model(_ data: Data,duplicates: Bool = false,page: Int = 2) throws -> CraftDocument {
    var d = try CraftDocument(width:24,height:16)
    var settings = PDFImportSettings();settings.pages = [page];settings.crop = .media;settings.resolution = 72;settings.antialias = false
    var layer = try PDFSmartObjectIO.placed(data,fileName:"Vector artwork.pdf",in:d,settings:settings,fit:false)
    layer.x = 0;layer.y = 0;layer.affine = .scale(2,2);d.layers = [layer];d.activeLayerID = layer.id
    if duplicates {var copy = layer;copy.id = UUID();copy.x = 4;copy.y = 2;copy.affine = .identity;d.layers.append(copy)}
    return d
  }
  func fixture(_ name: String) throws -> Data {
    try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/pdf/\(name).pdf"))
  }
  func folder() throws -> URL {let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url}
  func output(_ name: String,_ data: Data) throws {
    if let path = ProcessInfo.processInfo.environment["PHOTATO_PDF_EDIT_OUTPUT"] {
      let root = URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try data.write(to:root.appendingPathComponent(name))
    }
  }
  @MainActor func waitFor(_ label: String,_ condition: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<250 {if condition() {return};try await Task.sleep(for:.milliseconds(20))}
    XCTFail("Timed out: \(label)")
  }
  @MainActor func editor(_ store: EditorStore,root: URL) async throws -> PDFSourceEditWorkspace {
    store.pdfSourceEditRoot = root;store.pdfSourceOpener = {_ in};store.editSmartObjectContents()
    let model = try XCTUnwrap(store.pdfSourceEditors.values.first);await model.waitUntilOpened()
    XCTAssertEqual(model.stage,"watching",model.message);return model
  }
  func testEngineRetainsPageSharedIdentityTransformsAndImageSourceSelection() throws {
    let before = try pdf(false),after = try pdf(true);var original = try model(before,duplicates:true)
    var independent = original.layers[0];independent.id = UUID();independent.smartObject?.sourceID = UUID();original.layers.append(independent)
    let target = original.layers[0],source = try XCTUnwrap(target.smartObject)
    var session = EditorSession(document:original)
    try session.execute(PDFSmartObjectIO.sourceUpdate(after,in:original,layerID:target.id,expectedRevision:source.revision))
    XCTAssertEqual(session.undoStack.count,1)
    for i in 0...1 {
      XCTAssertEqual(session.document.layers[i].smartObject?.data,after)
      XCTAssertEqual(session.document.layers[i].smartObject?.sourceID,source.sourceID)
      XCTAssertEqual(session.document.layers[i].coordinateTransform,original.layers[i].coordinateTransform)
      XCTAssertEqual(session.document.layers[i].smartObject?.pdfSource,source.pdfSource)
    }
    XCTAssertEqual(session.document.layers[2],independent)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)),session.document)
    let imageData = try fixture("owned-images"),updatedImage = imageData+Data("\n% owned edit fixture\n".utf8)
    let (image,pixels) = try PDFSmartObjectIO.embeddedImage(imageData,fileName:"Image.pdf",in:original,image:2,antialias:false)
    var imageLayer = Layer(name:"PDF image",content:.raster(pixels));imageLayer.smartObject = image
    var imageDoc = original;imageDoc.layers = [imageLayer];imageDoc.activeLayerID = imageLayer.id
    try PDFSmartObjectIO.sourceUpdate(updatedImage,in:imageDoc,layerID:imageLayer.id,expectedRevision:image.revision).apply(to:&imageDoc)
    XCTAssertEqual(imageDoc.layers[0].smartObject?.pdfSource,image.pdfSource);XCTAssertEqual(imageDoc.layers[0].content,imageLayer.content)
    XCTAssertEqual(imageDoc.layers[0].smartObject?.data,updatedImage)
  }
  func testEngineRejectsInvalidMissingLockedAndStaleSourcesAtomically() throws {
    let before = try pdf(false),original = try model(before,duplicates:true),id = original.layers[0].id,revision = original.layers[0].smartObject!.revision
    for bytes in [Data(),Data("invalid".utf8),try pdf(true,pages:1),try fixture("owned-password")] {
      XCTAssertThrowsError(try PDFSmartObjectIO.sourceUpdate(bytes,in:original,layerID:id,expectedRevision:revision))
    }
    XCTAssertThrowsError(try PDFSmartObjectIO.sourceUpdate(pdf(true),in:original,layerID:id,expectedRevision:"stale"))
    var locked = original;locked.layers[1].locked = true;var session = EditorSession(document:locked)
    XCTAssertThrowsError(try session.execute(PDFSmartObjectIO.sourceUpdate(pdf(true),in:locked,layerID:id,expectedRevision:revision)))
    XCTAssertEqual(session.document,locked);XCTAssertTrue(session.undoStack.isEmpty)
  }
  @MainActor func testNativeAtomicAndInPlaceSavesUpdateOnceAndPreserveWorkingCopy() async throws {
    let root = try folder();defer {try? FileManager.default.removeItem(at:root)}
    let before = try pdf(false),after = try pdf(true),original = try model(before),store = EditorStore(document:original)
    defer {store.closePDFSourceEditors();store.renderTask?.cancel()}
    var changes = 0;store.onChange = {_ in changes += 1}
    let edit = try await editor(store,root:root)
    XCTAssertEqual(try Data(contentsOf:edit.workingURL),before);XCTAssertEqual(store.document,original)
    XCTAssertTrue(FileManager.default.fileExists(atPath:edit.workingURL.deletingLastPathComponent().appendingPathComponent("source.json").path))
    try after.write(to:edit.workingURL,options:.atomic)
    try await waitFor("atomic save") {store.document.layers[0].smartObject?.data == after && !store.geometryBusy}
    XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(changes,1)
    try output("updated-source.png",DocumentIO.encode(store.document,format:.png))
    edit.saved();await edit.updateTask?.value;XCTAssertEqual(store.session.undoStack.count,1)
    let file = try FileHandle(forWritingTo:edit.workingURL);try file.truncate(atOffset:0);try file.write(contentsOf:before);try file.close()
    try await waitFor("in-place save") {store.document.layers[0].smartObject?.data == before && !store.geometryBusy}
    XCTAssertEqual(store.session.undoStack.count,2);XCTAssertEqual(changes,2)
    let saved = store.document;await store.undo();XCTAssertEqual(store.document.layers[0].smartObject?.data,after)
    await store.redo();XCTAssertEqual(store.document,saved)
    store.stopPDFSourceEditing(edit.sourceID);XCTAssertEqual(edit.stage,"stopped")
    XCTAssertEqual(try Data(contentsOf:edit.workingURL),before)
  }
  @MainActor func testBusySaveQueuesAndCloseRetainsUncommittedWorkingFile() async throws {
    let root = try folder();defer {try? FileManager.default.removeItem(at:root)}
    let before = try pdf(false),after = try pdf(true),parent = CraftNSDocument(model:try model(before)),store = parent.store
    defer {store.closePDFSourceEditors();store.renderTask?.cancel()}
    let edit = try await editor(store,root:root);store.coalescingChanges = true
    try after.write(to:edit.workingURL,options:.atomic)
    try await waitFor("brush queue") {edit.stage == "waiting"}
    XCTAssertEqual(store.document.layers[0].smartObject?.data,before);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.coalescingChanges = false
    try await waitFor("brush finishes") {store.document.layers[0].smartObject?.data == after && !store.geometryBusy}
    store.geometryBusy = true;try before.write(to:edit.workingURL,options:.atomic)
    try await waitFor("queued close") {edit.stage == "waiting"}
    parent.close();await edit.updateTask?.value
    XCTAssertTrue(store.pdfSourceEditors.isEmpty);XCTAssertEqual(store.document.layers[0].smartObject?.data,after)
    XCTAssertEqual(try Data(contentsOf:edit.workingURL),before)
  }
  @MainActor func testUndoConflictRequiresExplicitApplyAndInvalidSaveCanRecover() async throws {
    let root = try folder();defer {try? FileManager.default.removeItem(at:root)}
    let before = try pdf(false),after = try pdf(true),store = EditorStore(document:try model(before))
    defer {store.closePDFSourceEditors();store.renderTask?.cancel()}
    let edit = try await editor(store,root:root);try after.write(to:edit.workingURL,options:.atomic)
    try await waitFor("initial update") {store.document.layers[0].smartObject?.data == after && !store.geometryBusy}
    await store.undo();let undone = store.document
    edit.saved();await edit.updateTask?.value;XCTAssertEqual(edit.stage,"conflict");XCTAssertEqual(store.document,undone)
    edit.saved(explicit:true);await edit.updateTask?.value
    XCTAssertEqual(edit.stage,"watching",edit.message);XCTAssertEqual(store.document.layers[0].smartObject?.data,after)
    let valid = store.document;try Data("Broken partial save".utf8).write(to:edit.workingURL,options:.atomic)
    try await waitFor("invalid saved PDF") {edit.stage == "error"};XCTAssertEqual(store.document,valid)
    try before.write(to:edit.workingURL,options:.atomic)
    try await waitFor("valid retry") {store.document.layers[0].smartObject?.data == before && !store.geometryBusy}
  }
  @MainActor func testNativePreparationCancelStaleAndOpenerFailureKeepSourceSafe() async throws {
    let root = try folder();defer {try? FileManager.default.removeItem(at:root)}
    for stale in [false,true] {
      let before = try pdf(false),after = try pdf(true),store = EditorStore(document:try model(before))
      defer {store.closePDFSourceEditors();store.renderTask?.cancel()}
      let edit = try await editor(store,root:root)
      edit.prepare = {bytes,doc,id,revision in try await Task.sleep(for:.milliseconds(200));return try PDFSmartObjectIO.sourceUpdate(bytes,in:doc,layerID:id,expectedRevision:revision)}
      let original = store.document;try after.write(to:edit.workingURL,options:.atomic)
      try await waitFor("native preparation") {edit.stage == "updating"}
      if stale {var newer = original;newer.name = "Changed during preparation";store.session = EditorSession(document:newer)}
      else {store.geometryTask?.cancel()}
      await edit.updateTask?.value;XCTAssertFalse(store.geometryBusy);XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertEqual(store.document.layers,original.layers);XCTAssertEqual(try Data(contentsOf:edit.workingURL),after)
    }
    let store = EditorStore(document:try model(pdf(false)));defer {store.closePDFSourceEditors();store.renderTask?.cancel()}
    store.pdfSourceEditRoot = root;store.pdfSourceOpener = {_ in throw CraftError.invalid("Owned opener failure")}
    store.editSmartObjectContents();let edit = try XCTUnwrap(store.pdfSourceEditors.values.first);await edit.waitUntilOpened()
    XCTAssertEqual(edit.stage,"error");XCTAssertEqual(edit.message,"Owned opener failure")
    XCTAssertTrue(FileManager.default.fileExists(atPath:edit.workingURL.path));XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func upload(_ service: AutomationService,_ doc: CraftNSDocument,_ bytes: Data,
    revision: String? = nil,sourceRevision: String? = nil,type: String = "application/pdf") async throws -> (HTTPURLResponse,Data) {
    let share = try XCTUnwrap(service.shares.first(where:{$0.document === doc})?.id),layer = try XCTUnwrap(doc.store.document.layers.first)
    var request = URLRequest(url:URL(string:try XCTUnwrap(service.endpoint)+"/v1/documents/\(share)/smart-objects/\(layer.id)/source")!)
    request.httpMethod = "POST";request.httpBody = bytes;request.timeoutInterval = 10
    request.setValue("Bearer "+(service.token ?? ""),forHTTPHeaderField:"Authorization");request.setValue(type,forHTTPHeaderField:"Content-Type")
    request.setValue(revision ?? service.revision(doc.store),forHTTPHeaderField:"X-Photato-Revision")
    request.setValue(sourceRevision ?? layer.smartObject?.revision,forHTTPHeaderField:"X-Photato-Source-Revision")
    let (data,response) = try await URLSession.shared.data(for:request);return (try XCTUnwrap(response as? HTTPURLResponse),data)
  }
  @MainActor func testHTTPUpdateDownloadNativeEqualityUndoAndValidation() async throws {
    let helper = AutomationTests(),before = try pdf(false),after = try pdf(true),original = try model(before,duplicates:true)
    var expected = original;try PDFSmartObjectIO.sourceUpdate(after,in:original,layerID:original.layers[0].id,expectedRevision:original.layers[0].smartObject!.revision).apply(to:&expected)
    try await helper.withService(pressedMouseButtons:{0}) {service,doc in
      doc.store.session = EditorSession(document:original);try service.share(doc)
      let capabilities = try await helper.request(service,path:"/v1/capabilities")
      let capabilityObject = try XCTUnwrap(JSONSerialization.jsonObject(with:capabilities.1) as? [String:Any])
      let schemas = try XCTUnwrap(capabilityObject["stateSchemas"] as? [String:Any])
      XCTAssertEqual((schemas["pdfSourceEditing"] as? [String:Any])?["type"] as? String,"array")
      var result = try await self.upload(service,doc,after);XCTAssertEqual(result.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      result = try await self.upload(service,doc,after,revision:"stale");XCTAssertEqual(result.0.statusCode,409)
      result = try await self.upload(service,doc,after,sourceRevision:"stale");XCTAssertEqual(result.0.statusCode,409)
      result = try await self.upload(service,doc,after,type:"image/png");XCTAssertEqual(result.0.statusCode,415)
      result = try await self.upload(service,doc,Data("invalid".utf8));XCTAssertEqual(result.0.statusCode,422)
      result = try await self.upload(service,doc,after);XCTAssertEqual(result.0.statusCode,200,String(decoding:result.1,as:UTF8.self))
      XCTAssertEqual(doc.store.document,expected);XCTAssertEqual(doc.store.session.undoStack.count,1)
      let shared = try XCTUnwrap(service.shares.first?.id),layer = original.layers[0].id
      let download = try await helper.request(service,path:"/v1/documents/\(shared)/smart-objects/\(layer)/source")
      XCTAssertEqual(download.1,after)
      result = try await self.upload(service,doc,after);XCTAssertEqual(result.0.statusCode,200);XCTAssertEqual(doc.store.session.undoStack.count,1)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc.store.document)),expected)
      let undo = try await helper.edit(service,doc,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(doc.store.document,original)
    }
  }
  @MainActor func testHTTPCancelRevocationAndNativeSessionStopAreAtomic() async throws {
    let helper = AutomationTests(),before = try pdf(false),after = try pdf(true),original = try model(before)
    for revoke in [false,true] {
      try await helper.withService(pressedMouseButtons:{0}) {service,doc in
        doc.store.session = EditorSession(document:original);try service.share(doc);service.setDocumentTransfersEnabled(true)
        service.pdfSourceUpdatePreparation = {data,parent,id,revision in try await Task.sleep(for:.milliseconds(200));return try PDFSmartObjectIO.sourceUpdate(data,in:parent,layerID:id,expectedRevision:revision)}
        let pending = Task {try await self.upload(service,doc,after)}
        try await self.waitFor("HTTP preparation") {doc.store.geometryBusy}
        let shared = try XCTUnwrap(service.shares.first?.id),op = try XCTUnwrap(service.pdfSourceUpdateOperations[shared])
        let path = "/v1/documents/\(shared)/smart-objects/\(original.layers[0].id)/source"
        let busy = try await self.upload(service,doc,after);XCTAssertEqual(busy.0.statusCode,409)
        if revoke {service.setDocumentTransfersEnabled(false)} else {
          let wrong = try await helper.request(service,path:path+"/cancel",body:["operationID":UUID().uuidString]);XCTAssertEqual(wrong.0.statusCode,409)
          let cancelled = try await helper.request(service,path:path+"/cancel",body:["operationID":op.id.uuidString]);XCTAssertEqual(cancelled.0.statusCode,200)
        }
        let result = try await pending.value;XCTAssertEqual(result.0.statusCode,409);XCTAssertEqual(doc.store.document,original)
        XCTAssertTrue(doc.store.session.undoStack.isEmpty);XCTAssertFalse(doc.store.geometryBusy);XCTAssertTrue(service.pdfSourceUpdateOperations.isEmpty)
        let root = try self.folder();defer {doc.store.closePDFSourceEditors();try? FileManager.default.removeItem(at:root)}
        let edit = try await self.editor(doc.store,root:root)
        let state = try await helper.request(service,path:"/v1/documents/\(shared)")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:state.1) as? [String:Any])
        XCTAssertEqual((object["pdfSourceEditing"] as? [[String:Any]])?.count,1)
        let stopped = try await helper.request(service,path:path+"/stop-editing",body:["sessionID":edit.id.uuidString]);XCTAssertEqual(stopped.0.statusCode,200)
        XCTAssertTrue(doc.store.pdfSourceEditors.isEmpty);XCTAssertTrue(FileManager.default.fileExists(atPath:edit.workingURL.path))
      }
    }
  }
  @MainActor func testAdobeResourceEditUsesSamePDFEngine() async throws {
    let old = try pdf(false,pages:1),new = try pdf(true,pages:1),initial = try CraftDocument(width:24,height:16)
    let input = URL(string:"https://owned.test/input.psd")!,first = URL(string:"https://owned.test/old.pdf")!,second = URL(string:"https://owned.test/new.pdf")!
    let add:[String:Any] = ["name":"PDF","type":"smart_object_layer","operation":["type":"add","placement":["type":"top"]],"smartObject":["smartObjectFile":["source":["url":first.absoluteString]]],"transformMode":"fit"]
    let edit:[String:Any] = ["name":"PDF","type":"smart_object_layer","operation":["type":"edit"],"smartObject":["autoResize":false,"smartObjectFile":["source":["url":second.absoluteString]]]]
    let transport = PDFSourceEditingTransport([input:try PSDCodec.writeRasterLayers(initial),first:old,second:new])
    var session = EditorSession(document:initial);try AdobeSmartObjectEdit(add,path:"add").apply(to:&session,resources:[first:old])
    let layer = try XCTUnwrap(session.document.layers.last),source = try XCTUnwrap(layer.smartObject)
    try session.execute(PDFSmartObjectIO.sourceUpdate(new,in:session.document,layerID:layer.id,expectedRevision:source.revision))
    let expected = try Renderer.composite(session.document).rgbaData(depth:.u8)
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport) {service,doc in
      service.setResourceJobsEnabled(true);let original = doc.store.document
      let payload:[String:Any] = ["image":["source":["url":input.absoluteString]],"edits":["layers":[add,edit]],"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
      let result = try await AutomationActionJobsTests().output(service,submit:"/v2/create-composite",payload:payload,expectedMediaType:"image/png")
      let actual = try RasterIO.read(result.2,name:"Adobe adapter")
      XCTAssertEqual(try Renderer.composite(actual).rgbaData(depth:.u8),expected);XCTAssertEqual(doc.store.document,original)
      try self.output("adobe-source-update.png",result.2)
    }
  }
}
