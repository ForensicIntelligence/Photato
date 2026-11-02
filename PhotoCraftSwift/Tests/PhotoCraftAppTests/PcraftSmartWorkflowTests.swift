import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PcraftSmartWorkflowTests:XCTestCase {
  func fixture(_ name:String="affine-cached",_ bits:String="u8")throws->Data {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/PcraftSmart")
    return try Data(contentsOf:root.appendingPathComponent("\(name)-\(bits).pcraft"))
  }
  @MainActor func testNativeOriginalOpenEditContentsUndoSaveAndSourcePreservation()async throws {
    _ = NSApplication.shared;let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    for bits in ["u8","u16","f32"] {
      let bytes=try fixture("affine-cached",bits),url=folder.appendingPathComponent("Owned-\(bits).pcraft");try bytes.write(to:url)
      let prepared=try PreparedLocalDocument.read(url,format:.pcraft),parent=prepared.makeDocument(url:url)
      let controller=CraftDocumentController(workspaces:WorkspaceLibrary());controller.addDocument(parent)
      defer{for doc in controller.documents{doc.updateChangeCount(.changeCleared);doc.close()}}
      let original=parent.store.document,layer=try XCTUnwrap(parent.store.activeLayer),source=try XCTUnwrap(layer.smartObject)
      XCTAssertNil(parent.fileURL);XCTAssertEqual(parent.importedSourceURL,url);XCTAssertTrue(parent.store.canEditSmartObjectContents)
      parent.store.editSmartObjectContents();await parent.store.geometryTask?.value;XCTAssertNil(parent.store.error)
      let child=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0.smartObjectEditLink?.parent === parent})
      XCTAssertEqual(child.smartObjectEditLink?.sourceID,source.sourceID)
      let id=try XCTUnwrap(child.store.document.layers.last?.id);child.store.perform(.fill(id,Pixel(1,0,0)));try await child.commitSmartObjectContents()
      XCTAssertNotEqual(parent.store.activeLayer?.smartObject?.data,source.data);XCTAssertNil(parent.store.activeLayer?.pristineSmartAppearance)
      XCTAssertEqual(try Renderer.composite(parent.store.document).pixel(x:8,y:10).r,1)
      let edited=parent.store.document,target=folder.appendingPathComponent("Migrated-\(bits).photato")
      try await DocumentSaveWorkflowTests().save(parent,to:target,format:.native);XCTAssertTrue(try DocumentIO.read(target)==edited)
      await parent.store.undo();XCTAssertTrue(parent.store.document==original);XCTAssertEqual(try Data(contentsOf:url),bytes)
      for doc in controller.documents{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}
    }
  }
  @MainActor func testHTTPImportSourceStateNoOpRasterizeHistoryNative70AndOriginalPlacement()async throws {
    let helper=AutomationTests();for name in ["filtermask-cached","projective-cached"] {try await helper.withService(pressedMouseButtons:{0}){service,parent in
      defer{for doc in service.controller.documents where doc !== parent{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
      service.setDocumentTransfersEnabled(true)
      let input=try self.fixture(name),upload=try await AutomationOpeningTests().upload(service,bytes:input,type:PcraftImport.mediaType,format:"pcraft")
      XCTAssertEqual(upload.0.statusCode,201,String(decoding:upload.1,as:UTF8.self))
      let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),layer=try XCTUnwrap(document.store.activeLayer),source=try XCTUnwrap(layer.smartObject),original=document.store.document
      let state=service.state(share,document:document),rows=try XCTUnwrap(state["layers"]as?[[String:Any]]),sourceState=try XCTUnwrap(rows.first?["sourceSmartObject"]as?[String:Any]),appearance=try XCTUnwrap(sourceState["originalAppearance"]as?[String:Any])
      if name=="projective-cached"{XCTAssertEqual(sourceState["projection"]as?[Double],layer.sourceProjection?.values)}
      XCTAssertEqual(appearance["pristine"]as?Bool,true);XCTAssertEqual(appearance["cacheAvailable"]as?Bool,true);XCTAssertTrue(JSONSerialization.isValidJSONObject(sourceState))
      let noOp=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":["enabled":true,"filters":try XCTUnwrap(layer.smartFilters?.apiState["filters"])]])
      XCTAssertEqual(noOp,200);XCTAssertTrue(document.store.document==original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let stale=try await helper.edit(service,document,"layer.rasterize",["layerID":layer.id.uuidString],revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"layer.rasterize",["layerID":layer.id.uuidString]);document.store.geometryBusy=false;XCTAssertEqual(busy,409)
      let sourceResponse=try await helper.request(service,path:"/v1/documents/\(share.id)/smart-objects/\(layer.id)/source");XCTAssertEqual(sourceResponse.0.statusCode,200);XCTAssertEqual(sourceResponse.1,source.data)
      let old=try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"69"]);XCTAssertEqual(old.0.statusCode,422)
      let native=try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"70"]);XCTAssertEqual(native.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(native.1)==original)
      var expected=original;try SmartObjectIO.rasterizationCommand(layer,in:expected).apply(to:&expected)
      let raster=try await helper.edit(service,document,"layer.rasterize",["layerID":layer.id.uuidString]);XCTAssertEqual(raster,200);XCTAssertTrue(document.store.document==expected)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertTrue(document.store.document==original)
      try service.share(parent);let parentShare=try XCTUnwrap(service.shares.first{$0.document === parent})
      var request=URLRequest(url:URL(string:service.endpoint!+"/v1/documents/\(parentShare.id)/smart-objects/source")!);request.httpMethod="POST";request.httpBody=source.data
      request.setValue("Bearer "+service.token!,forHTTPHeaderField:"Authorization");request.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type");request.setValue("Owned.pcraft",forHTTPHeaderField:"X-Photato-Name");request.setValue(service.revision(parent.store),forHTTPHeaderField:"X-Photato-Revision")
      let(placed,response)=try await URLSession.shared.data(for:request);XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200,String(decoding:placed.prefix(1000),as:UTF8.self))
      XCTAssertEqual(parent.store.activeLayer?.smartObject?.data,source.data);XCTAssertEqual(parent.store.activeLayer?.smartObject?.mediaType,PcraftImport.mediaType)
      XCTAssertEqual(try self.fixture(name),input)
    }}
  }
  @MainActor func testImportedSourceWarpFrameUsesNativeAPITransactionAndValidatesBounds()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,parent in
      defer{for doc in service.controller.documents where doc !== parent{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
      service.setDocumentTransfersEnabled(true);let upload=try await AutomationOpeningTests().upload(service,bytes:self.fixture("warp-cached"),type:PcraftImport.mediaType,format:"pcraft");XCTAssertEqual(upload.0.statusCode,201)
      let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),layer=try XCTUnwrap(document.store.activeLayer),original=document.store.document
      var warp=try XCTUnwrap(layer.warp);warp.bend=30
      var expected=original;try Command.warp(WarpEdit.prepare(original,layerID:layer.id,warp:warp)).apply(to:&expected)
      let status=try await helper.edit(service,document,"layer.warp",["layerID":layer.id.uuidString,"settings":warp.apiState]);XCTAssertEqual(status,200);XCTAssertTrue(document.store.document==expected);XCTAssertEqual(document.store.activeLayer?.warp?.sourceBounds,warp.sourceBounds)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertTrue(document.store.document==original)
      let invalidFrames:[[String:Any]]=[["x":0,"y":0,"width":0,"height":12],["x":0,"y":0,"width":16,"height":12,"unknown":true]]
      for frame in invalidFrames {
        let invalid=try await helper.edit(service,document,"layer.warp",["layerID":layer.id.uuidString,"settings":["style":"arch","bend":30,"sourceBounds":frame]])
        XCTAssertEqual(invalid,400);XCTAssertTrue(document.store.document==original)
      }
    }
  }
  @MainActor func testImportedProjectivePropertiesAndHitTestingMatchVisibleArtwork()throws {
    let doc=try PcraftImport.read(fixture("projective-cached")),store=EditorStore(document:doc);defer{store.renderTask?.cancel()}
    let layer=try XCTUnwrap(doc.layers.first),source=try XCTUnwrap(layer.smartObject),projection=try XCTUnwrap(layer.sourceProjection)
    let full=try projection.followed(by:layer.coordinateTransform),corner=try full.point(16,12)
    XCTAssertEqual(corner.x,28.2/1.176,accuracy:1e-12);XCTAssertEqual(corner.y,23.0/1.176,accuracy:1e-12)
    XCTAssertEqual(layer.x,7);XCTAssertEqual(layer.y,9)
    let rendered=try XCTUnwrap(layer.originalSmartAppearanceLayer());guard case .raster(let pixels)=rendered.content else{return XCTFail()}
    let content=try XCTUnwrap(pixels.contentBounds()),expected=IntRect(x:rendered.x+content.x,y:rendered.y+content.y,width:content.width,height:content.height)
    XCTAssertEqual(try store.layerBounds(layer),expected);XCTAssertEqual(store.activeLayerSize,CGSize(width:expected.width,height:expected.height))
    let inverse=try layer.coordinateTransform.inverted();var point:CGPoint?
    for y in 0..<64{for x in 0..<80{
      let alpha=pixels.pixel(x:x-rendered.x,y:y-rendered.y).a,local=inverse.point(Double(x)+0.5,Double(y)+0.5)
      if alpha>0.5 && (local.x<0 || local.y<0 || local.x>=Double(source.width) || local.y>=Double(source.height)){point=CGPoint(x:Double(x)+0.5,y:Double(y)+0.5);break}
    };if point != nil{break}}
    let location=try XCTUnwrap(point),overlay=Layer(name:"Owned transparent hit-test overlay",content:.raster(try Surface(width:80,height:64)))
    store.perform(.addLayer(overlay));XCTAssertEqual(store.activeLayer?.id,overlay.id)
    store.autoSelectLayer(at:location);XCTAssertEqual(store.activeLayer?.id,layer.id)
  }
  @MainActor func testCooperativeHTTPNestedSourceBoundaryRejectsAtomically()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,parent in
      defer{for doc in service.controller.documents where doc !== parent{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
      service.setDocumentTransfersEnabled(true)
      let valid=try await AutomationOpeningTests().upload(service,bytes:self.fixture("deep-7"),type:PcraftImport.mediaType,format:"pcraft")
      XCTAssertEqual(valid.0.statusCode,201,String(decoding:valid.1.prefix(1000),as:UTF8.self))
      let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),before=document.store.document,count=service.controller.documents.count,shares=service.shares.count
      let invalid=try await AutomationOpeningTests().upload(service,bytes:self.fixture("deep-8"),type:PcraftImport.mediaType,format:"pcraft")
      XCTAssertEqual(invalid.0.statusCode,422,String(decoding:invalid.1.prefix(1000),as:UTF8.self))
      XCTAssertEqual(service.controller.documents.count,count);XCTAssertEqual(service.shares.count,shares);XCTAssertTrue(document.store.document==before)
      XCTAssertTrue(parent.store.session.undoStack.isEmpty)
    }
  }
  private actor Transport:AdobeResourceTransport {
    let data:Data
    init(_ data:Data){self.data=data}
    func fetch(_ url:URL)async throws->Data{data}
    func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws{throw AdobeAPIError.unsupported("Hosted owned output only.")}
  }
  @MainActor func testOriginalSourceResourceJobsUseSharedOutputAndKeepAdobeInputBoundary()async throws {
    let helper=AutomationTests()
    for(bits,media,format)in[("u8","image/png",DocumentIO.Format.png),("f32","image/tiff",DocumentIO.Format.tiff)] {
      let input=try fixture("affine-cached",bits),payload:[String:Any]=["image":["source":["url":"https://example.test/owned-smart.pcraft"]],"options":["actions":[["source":["contentType":"application/json","content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],"outputs":[["mediaType":media,"destination":["validityPeriod":60]]]]
      try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)){service,parent in
        service.setResourceJobsEnabled(true);let untouched=parent.store.document
        for route in ["/v1/action-jobs","/v2/execute-actions"] {
          let submitted=try await helper.request(service,path:route,body:payload);XCTAssertEqual(submitted.0.statusCode,202)
          let body=try XCTUnwrap(JSONSerialization.jsonObject(with:submitted.1)as?[String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(body["statusUrl"]as?String)))
          var terminal:[String:Any]?
          for _ in 0..<1000{let reply=try await helper.request(service,path:url.path),value=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1)as?[String:Any]);if ["succeeded","failed"].contains(value["status"]as?String ?? ""){terminal=value;break};try await Task.sleep(for:.milliseconds(10))}
          let result=try XCTUnwrap(terminal);XCTAssertEqual(result["status"]as?String,route.hasPrefix("/v1") ? "succeeded":"failed","\(result)")
          if route.hasPrefix("/v1") {
            let outputs=try XCTUnwrap((result["result"]as?[String:Any])?["outputs"]as?[[String:Any]]),destination=try XCTUnwrap(outputs.first?["destination"]as?[String:Any]),asset=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"]as?String)))
            let bytes=try await helper.request(service,path:asset.path);XCTAssertEqual(bytes.0.statusCode,200);XCTAssertEqual(bytes.1,try DocumentIO.encode(PcraftImport.read(input),format:format))
          }
        }
        XCTAssertTrue(parent.store.document==untouched);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testPublishedAdobeSmartResourceRejectsPhotoCraftWithoutChangingDocument()throws {
    let data=try fixture(),base=try CraftDocument(width:80,height:64)
    for path in ["source.pcraft","source.png"] {
      let url=URL(string:"https://example.test/"+path)!,payload=SmartObjectWorkflowTests().addPayload(source:"https://example.test/"+path),layers=try XCTUnwrap((payload["edits"]as?[String:Any])?["layers"]as?[[String:Any]])
      let edit=try AdobeSmartObjectEdit(XCTUnwrap(layers.first),path:"owned-edit");var session=EditorSession(document:base)
      XCTAssertThrowsError(try edit.apply(to:&session,resources:[url:data]));XCTAssertTrue(session.document==base)
    }
    XCTAssertEqual(PcraftImport.sourceSmartFilterCommands.count,110)
    let schema=try XCTUnwrap(SmartObject.apiLayerStateSchema["properties"]as?[String:Any]);XCTAssertNotNil(schema["sourceSmartObject"])
  }
}
