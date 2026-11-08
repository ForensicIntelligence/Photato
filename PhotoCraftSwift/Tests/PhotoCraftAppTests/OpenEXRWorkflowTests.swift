import AppKit
import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class OpenEXRWorkflowTests:XCTestCase {
  func model()throws->CraftDocument {
    var d=try CraftDocument(width:5,height:17,depth:.f32,name:"Owned HDR")
    var s=try Surface(width:5,height:17,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<17 {for x in 0..<5 {let a:Float=[1,0.5,0,1,0.25][x];s.setLinearPixel(x:x,y:y,Pixel(Float(x-2)*0.5+Float(y)*0.125,2+Float(x)*0.25,-0.5+Float(y)*0.25,a))}}
    d.layers[0].content = .raster(s);d.resolution=144;return d
  }
  func words(_ d:CraftDocument)throws->[UInt32] {
    guard case .raster(let s)=d.layers[0].content else{throw CraftError.invalid("Expected raster")}
    return (0..<s.height).flatMap {y in (0..<s.width).flatMap {x in let p=s.linearPixel(x:x,y:y);return [p.r,p.g,p.b,p.a].map(\.bitPattern)}}
  }
  @MainActor func testNativeControlsSaveCopyOpenAndSubsequentSaveKeepSamplesAndHistory()async throws {
    let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    let c=CraftDocumentController(workspaces:WorkspaceLibrary()),doc=CraftNSDocument(model:try model());c.addDocument(doc);defer{doc.close()}
    let before=doc.store.document,word=try words(before)
    let panel=NSSavePanel();XCTAssertTrue(doc.prepareSavePanel(panel));let a=try XCTUnwrap(doc.saveAccessory)
    a.formats.selectItem(at:try XCTUnwrap(a.availableFormats.firstIndex(of:.exr)));a.updateFormat()
    XCTAssertFalse(a.exrControls.view.isHidden);XCTAssertTrue(a.jpegControls.view.isHidden);XCTAssertEqual(panel.allowedContentTypes,[OpenEXR.contentType])
    XCTAssertEqual(a.encodingOptions.exrCompression,.zip);XCTAssertEqual(a.encodingOptions.exrSample,.float)
    a.exrControls.compression.selectItem(at:1);XCTAssertEqual(a.encodingOptions.exrCompression,.zips)
    let target=folder.appendingPathComponent("hdr.exr");try await DocumentSaveWorkflowTests().save(doc,to:target,format:.exr)
    XCTAssertEqual(try Data(contentsOf:target),try DocumentIO.encode(before,format:.exr,options:a.encodingOptions))
    XCTAssertEqual(doc.persistenceFormat,.exr);XCTAssertEqual(doc.fileURL,target);XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertEqual(doc.rememberedEncodingOptions[.exr],a.encodingOptions);XCTAssertEqual(doc.store.document,before)
    try doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id,"Edited"))
    let edited=doc.store.document;try await DocumentSaveWorkflowTests().save(doc,to:target,format:.exr,operation:.saveOperation)
    XCTAssertEqual(try words(DocumentIO.read(target)),word);XCTAssertEqual(doc.store.document,edited)
    await doc.store.undo();await doc.store.redo();XCTAssertEqual(doc.store.document,edited)
    let copy=folder.appendingPathComponent("copy.exr");let opts=RasterEncodingOptions(exrCompression:OpenEXR.Compression.none,exrSample:.half,exrTransparency:false)
    let dirty=doc.isDocumentEdited,history=doc.store.session.undoStack.count
    try await doc.copyDocument(to:copy,format:.exr,options:opts)
    XCTAssertEqual(try Data(contentsOf:copy),try DocumentIO.encode(edited,format:.exr,options:opts));XCTAssertEqual(doc.fileURL,target)
    XCTAssertEqual(doc.isDocumentEdited,dirty);XCTAssertEqual(doc.store.session.undoStack.count,history)
    let misleading=folder.appendingPathComponent("image.png");try Data(contentsOf:target).write(to:misleading)
    XCTAssertEqual(DocumentOpenFormat.detect(misleading),.exr)
    let opened=try XCTUnwrap(c.makeDocument(withContentsOf:misleading,ofType:OpenEXR.contentType.identifier)as?CraftNSDocument);defer{opened.close()}
    XCTAssertEqual(opened.persistenceFormat,.exr);XCTAssertEqual(try words(opened.store.document),word)
  }
  func testSaveGuardsDepthStructureProfileHalfAndAlpha()throws {
    let d=try model();XCTAssertNil(DocumentIO.persistenceIssue(d,format:.exr))
    XCTAssertNotNil(DocumentIO.persistenceIssue(d,format:.exr,options:.init(exrSample:.half)))
    XCTAssertNotNil(DocumentIO.persistenceIssue(d,format:.exr,options:.init(exrTransparency:false)))
    XCTAssertNotNil(DocumentIO.persistenceIssue(try CraftDocument(width:2,height:2),format:.exr))
    var layered=d;layered.layers.append(Layer(name:"Other",content:.raster(try Surface(width:1,height:1,depth:.f32))))
    XCTAssertNotNil(DocumentIO.persistenceIssue(layered,format:.exr));XCTAssertNoThrow(try DocumentIO.encode(layered,format:.exr))
    var moved=d;moved.layers[0].x=1;XCTAssertNotNil(DocumentIO.persistenceIssue(moved,format:.exr))
    var large=try CraftDocument(width:10000,height:4001,depth:.f32);XCTAssertNil(DocumentIO.persistenceIssue(large,format:.exr))
    large.paths=[];XCTAssertTrue(DocumentIO.readableTypes.contains(OpenEXR.contentType.identifier));XCTAssertTrue(DocumentIO.uploadTypes.contains(OpenEXR.mediaType))
  }
  func testStrictOptionsSchemasAndOlderCodableDefaults()throws {
    let options=RasterEncodingOptions(exrCompression:OpenEXR.Compression.none,exrSample:.half,exrTransparency:false)
    XCTAssertEqual(try JSONDecoder().decode(RasterEncodingOptions.self,from:Data("{}".utf8)),.init())
    XCTAssertEqual(try JSONDecoder().decode(RasterEncodingOptions.self,from:JSONEncoder().encode(options)),options)
    XCTAssertFalse(options.isEmpty)
    let json=DocumentEncodingOptions.json(options),header=String(decoding:try JSONSerialization.data(withJSONObject:json),as:UTF8.self)
    XCTAssertEqual(try DocumentEncodingOptions.header(header,format:.exr),options)
    XCTAssertThrowsError(try DocumentEncodingOptions.header(header,format:.png))
    for bad in ["{\"exrSample\":\"uint\"}","{\"exrCompression\":\"piz\"}","{\"exrTransparency\":1}","{\"exrSample\":\"float\",\"tiffLayers\":true}"] {
      XCTAssertThrowsError(try DocumentEncodingOptions.header(bad,format:.exr))
    }
    let formats=try XCTUnwrap(DocumentEncodingOptions.capabilities["formats"]as?[String:[String]])
    XCTAssertEqual(formats["exr"],["exrCompression","exrSample","exrTransparency"])
    XCTAssertNotNil(DocumentEncodingOptions.capabilities["openEXR"])
    XCTAssertTrue(SaveDialogFormats.defaults.contains(.exr))
  }
  @MainActor func testHTTPDownloadImportOptionsRevisionAndPermissionShareNativeBytes()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}){service,doc in
      doc.store.session=EditorSession(document:try self.model());service.setDocumentTransfersEnabled(true);try service.share(doc)
      let id=try XCTUnwrap(service.shares.first?.id),before=doc.store.document,revision=service.revision(doc.store)
      let opts=RasterEncodingOptions(exrCompression:.zips,exrSample:.float,exrTransparency:true)
      let header=String(decoding:try JSONSerialization.data(withJSONObject:DocumentEncodingOptions.json(opts)),as:UTF8.self)
      let response=try await helper.request(service,path:"/v1/documents/\(id)/file.exr",headers:["X-Photato-Revision":revision,"X-Photato-Export-Options":header])
      XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1,as:UTF8.self));XCTAssertEqual(response.0.value(forHTTPHeaderField:"Content-Type"),OpenEXR.mediaType)
      XCTAssertEqual(response.1,try DocumentIO.encode(before,format:.exr,options:opts));XCTAssertEqual(try self.words(DocumentIO.decodeUpload(response.1,native:false,name:"API")),try self.words(before))
      let stale=try await helper.request(service,path:"/v1/documents/\(id)/file.exr",headers:["X-Photato-Revision":"stale"]);XCTAssertEqual(stale.0.statusCode,409)
      let invalid=try await helper.request(service,path:"/v1/documents/\(id)/file.exr",headers:["X-Photato-Export-Options":"{\"exrSample\":\"uint\"}"]);XCTAssertEqual(invalid.0.statusCode,400)
      XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let uploaded=try await files.request(service,path:"/v1/documents/import",data:response.1,type:OpenEXR.mediaType,headers:["X-Photato-Open-Format":"exr"])
      XCTAssertEqual(uploaded.0.statusCode,201,String(decoding:uploaded.1,as:UTF8.self));XCTAssertEqual(service.shares.count,2)
      let imported=try XCTUnwrap(service.shares.last?.document);XCTAssertEqual(try self.words(imported.store.document),try self.words(before))
      imported.updateChangeCount(.changeCleared);imported.close()
      service.setDocumentTransfersEnabled(false)
      let denied=try await helper.request(service,path:"/v1/documents/\(id)/file.exr");XCTAssertEqual(denied.0.statusCode,403)
    }
  }
  @MainActor func testAtomicEXRSavePreservesExistingHiddenFlagAndNoFailedReplacement()async throws {
    let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    let target=folder.appendingPathComponent("hidden.exr"),doc=CraftNSDocument(model:try model());defer{doc.close()}
    try Data([9]).write(to:target);XCTAssertEqual(chflags(target.path,UInt32(UF_HIDDEN)),0)
    try await DocumentSaveWorkflowTests().save(doc,to:target,format:.exr)
    XCTAssertEqual(try words(DocumentIO.read(target)),try words(doc.store.document))
    XCTAssertTrue(try AtomicVisibilityWorkflowTests().hidden(target))
    let original=try Data(contentsOf:target)
    do{try await doc.persistDocument(to:target,format:.exr,operation:.saveOperation,options:.init(exrSample:.half));XCTFail("Reduced ordinary Save")}catch{}
    XCTAssertEqual(try Data(contentsOf:target),original);XCTAssertFalse(doc.fileOperationBusy)
  }
  @MainActor func testHTTPFileSaveAdoptsOptionsAndPreservesHistory()async throws {
    let helper=AutomationTests(),folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    try await helper.withService(pressedMouseButtons:{0}){service,doc in
      doc.store.session=EditorSession(document:try self.model());try service.share(doc)
      service.setDocumentSavesEnabled(true);service.setSaveDirectory(folder)
      let before=doc.store.document
      let status=try await helper.edit(service,doc,"document.saveAs",["name":"hdr","format":"exr","replace":false,"options":["exrCompression":"none","exrSample":"float","exrTransparency":true]])
      XCTAssertEqual(status,200);let file=folder.appendingPathComponent("hdr.exr")
      XCTAssertEqual(try Data(contentsOf:file),try DocumentIO.encode(before,format:.exr,options:.init(exrCompression:OpenEXR.Compression.none,exrSample:.float,exrTransparency:true)))
      XCTAssertEqual(doc.persistenceFormat,.exr);XCTAssertEqual(doc.rememberedEncodingOptions[.exr]?.exrCompression,OpenEXR.Compression.none)
      XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty);XCTAssertFalse(doc.isDocumentEdited)
      let original=try Data(contentsOf:file)
      let bad=try await helper.edit(service,doc,"document.saveAs",["name":"hdr","format":"exr","replace":true,"options":["exrSample":"half"]])
      XCTAssertEqual(bad,422);XCTAssertEqual(try Data(contentsOf:file),original)
    }
  }

}
