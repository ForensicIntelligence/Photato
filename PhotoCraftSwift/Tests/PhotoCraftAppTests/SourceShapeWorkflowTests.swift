import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class SourceShapeWorkflowTests:XCTestCase {
  func fixture(_ bits:String="u8")throws->Data{let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/PcraftShapes");return try Data(contentsOf:root.appendingPathComponent("shapes-\(bits).pcraft"))}
  @MainActor func testNativeOpenPropertiesCancelCommitUndoPathEditingAndSave()async throws {
    _ = NSApplication.shared;let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    for bits in ["u8","u16","f32"]{let bytes=try fixture(bits),url=folder.appendingPathComponent("shapes-\(bits).pcraft");try bytes.write(to:url)
      let prepared=try PreparedLocalDocument.read(url,format:.pcraft),document=prepared.makeDocument(url:url),store=document.store;defer{store.renderTask?.cancel();document.updateChangeCount(.changeCleared);document.close()}
      XCTAssertNil(document.fileURL);XCTAssertEqual(document.importedSourceURL,url)
      let layer=try XCTUnwrap(store.document.layers.first{$0.name=="live-0"});store.selectPath(.shape(layer.id));let original=store.document
      store.beginShapeProperties(editLayer:true);let draft=try XCTUnwrap(store.shapeDraft);draft.definition.stroke.opacity=0.2;store.refreshShapePreview();XCTAssertEqual(store.document,original);XCTAssertNotNil(store.shapePreview);store.cancelShapeProperties();XCTAssertEqual(store.document,original)
      store.beginShapeProperties(editLayer:true);let commit=try XCTUnwrap(store.shapeDraft);commit.definition.stroke.opacity=0.2;store.commitShapeProperties(commit);await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertNil(store.activeLayer?.shape?.importedAppearance)
      try store.session.undo();XCTAssertEqual(store.document,original)
      store.selectPath(.shape(layer.id));XCTAssertEqual(store.pathTarget,.shape(layer.id));var path=try XCTUnwrap(store.selectedVectorPath);path.components[0].knots[0].anchor.x+=2;store.commitPath(path);await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(try store.activeLayer?.shapePath(),path);XCTAssertNil(store.activeLayer?.shape?.importedAppearance)
      let edited=store.document,target=folder.appendingPathComponent("migrated-\(bits).photato");try await DocumentSaveWorkflowTests().save(document,to:target,format:.native);XCTAssertEqual(try DocumentIO.read(target),edited);XCTAssertEqual(try Data(contentsOf:url),bytes)
      try store.session.undo();XCTAssertEqual(store.document,original)
    }
  }
  @MainActor func testHTTPSourceImportPathEditStatePersistenceAndDesktopEquality()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,parent in
      defer{for doc in service.controller.documents where doc !== parent{doc.updateChangeCount(.changeCleared);doc.close()}}
      service.setDocumentTransfersEnabled(true);let bytes=try self.fixture("f32"),response=try await AutomationOpeningTests().upload(service,bytes:bytes,type:PcraftImport.mediaType,format:"pcraft");XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      let share=try XCTUnwrap(service.shares.first),doc=try XCTUnwrap(share.document),original=doc.store.document,layer=try XCTUnwrap(original.layers.first{$0.name=="open"});let desktop=EditorStore(document:original);defer{desktop.renderTask?.cancel()}
      var path=try XCTUnwrap(layer.shapePath());path.components[0].knots[0].anchor.x+=3
      let selected=try await helper.edit(service,doc,"path.configure",["layerID":layer.id.uuidString]);XCTAssertEqual(selected,200);XCTAssertEqual(doc.store.pathTarget,.shape(layer.id));desktop.selectPath(.shape(layer.id));let selectedOriginal=doc.store.document
      let unchanged=try await helper.edit(service,doc,"shape.edit",["operation":"configure","layerID":layer.id.uuidString,"definition":BrushAPI.json(layer.shape!.editableDefinition)]);XCTAssertEqual(unchanged,200);XCTAssertTrue(doc.store.document==selectedOriginal);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      try desktop.executeEditorCommand(.shape(.configure(layer.id,layer.replacingShapePath(path,canvas:.init(x:0,y:0,width:96,height:64)))))
      let params:[String:Any]=["operation":"path","layerID":layer.id.uuidString,"path":BrushAPI.json(path)],code=try await helper.edit(service,doc,"shape.edit",params);XCTAssertEqual(code,200);XCTAssertTrue(doc.store.document==desktop.document,"API/native document equality")
      XCTAssertEqual(try Renderer.composite(doc.store.document).rgbaData(depth:.u8),try Renderer.composite(desktop.document).rgbaData(depth:.u8))
      let state=service.state(share,document:doc),rows=try XCTUnwrap(state["layers"]as?[[String:Any]]),row=try XCTUnwrap(rows.first{($0["id"]as?String)==layer.id.uuidString});XCTAssertTrue(row["shapeSource"] is NSNull)
      let stale=try await helper.edit(service,doc,"shape.edit",params,revision:"stale");XCTAssertEqual(stale,409)
      let before=doc.store.document;doc.store.beginShapeProperties(editLayer:true);let busy=try await helper.edit(service,doc,"shape.edit",params);XCTAssertEqual(busy,409);doc.store.cancelShapeProperties()
      var bad=params;bad["unexpected"]=true;let invalid=try await helper.edit(service,doc,"shape.edit",bad);XCTAssertEqual(invalid,400);XCTAssertEqual(doc.store.document,before)
      let route="/v1/documents/\(share.id)/file.photato";let rejected=try await helper.request(service,path:route,headers:["X-Photato-Archive-Version":"67"]);XCTAssertEqual(rejected.0.statusCode,422)
      let saved=try await helper.request(service,path:route,headers:["X-Photato-Archive-Version":"68"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1)==desktop.document,"Native68 download equality")
      try doc.store.session.undo();XCTAssertTrue(doc.store.document==selectedOriginal,"Undo restores imported definition/cache")
    }
  }
  @MainActor func testSourceDefinitionSchemasAndActions24PreserveLegacy5AndNewComponents()throws {
    let doc=try PcraftImport.read(fixture());for layer in doc.layers{let definition=try XCTUnwrap(layer.shape?.definition),value=try JSONDecoder().decode(AutomationValue.self,from:JSONEncoder().encode(definition));XCTAssertEqual(try ShapeAPI.decode(ShapeDefinition.self,value,schema:ShapeAPI.definition,base:.init(geometry:.init())),definition)}
    let definition=ShapeDefinition(geometry:.init(width:10,height:10)),legacy=RecordedAction(name:"Legacy",steps:[.init(name:"Shape",operation:.createShape("Legacy",definition,.identity,[]))]);XCTAssertEqual(ActionLibraryFile(actions:[legacy]).requiredVersion,5)
    var component=ShapeComponent(geometry:.init(kind:.line,width:0,height:0));component.geometry.lineWeight=0
    let action=RecordedAction(name:"New",steps:[.init(name:"Append",operation:.appendShape(.active,component))]);let file=ActionLibraryFile(actions:[action]);XCTAssertEqual(file.requiredVersion,24);XCTAssertEqual(try ActionLibraryFile.decode(file.encoded()).version,24)
    let sourceLayer=try XCTUnwrap(doc.layers.first{$0.name=="open"});var changed=sourceLayer.shape!.editableDefinition;changed.stroke.opacity=0.25
    let command=Command.shape(.configure(sourceLayer.id,changed)),recorded=RecordedAction(name:"Source shape edit",steps:[.init(name:"Edit",operation:ActionOperation(recording:command,in:doc))])
    let library=try ActionLibraryFile.decode(ActionLibraryFile(actions:[recorded]).encoded());XCTAssertEqual(library.version,24)
    var replay=doc,desktop=doc;try library.actions[0].apply(to:&replay);try command.apply(to:&desktop);XCTAssertTrue(replay==desktop,"Actions24 source path/cache/paint replay matches native command")
    XCTAssertEqual(ShapeAPI.capabilities["extendedShapeVersion"]as?Int,68);XCTAssertEqual(ShapeAPI.capabilities["extendedShapeActionVersion"]as?Int,24)
  }
  private actor Transport:AdobeResourceTransport {
    let data:Data
    init(_ data:Data){self.data=data}
    func fetch(_ url:URL)async throws->Data{data}
    func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws{throw AdobeAPIError.unsupported("Owned hosted output only.")}
  }
  @MainActor func testSourceShapeResourceJobsReuseNativeOutputsAndRejectEditablePSD()async throws {
    let input=try fixture(),helper=AutomationTests()
    let action="[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"
    try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)){service,parent in
      let original=parent.store.document;service.setResourceJobsEnabled(true)
      for (route,type,format) in [("/v1/action-jobs","image/png",DocumentIO.Format.png),("/v1/action-jobs","image/tiff",.tiff),("/v1/action-jobs","image/vnd.adobe.photoshop",.psd),("/v2/execute-actions","image/vnd.adobe.photoshop",.psd)] {
        let request:[String:Any]=["image":["source":["url":"https://example.test/owned-shapes.pcraft"]],"options":["actions":[["source":["contentType":"application/json","content":action]]]],"outputs":[["mediaType":type,"destination":["validityPeriod":60]]]]
        let response=try await helper.request(service,path:route,body:request);XCTAssertEqual(response.0.statusCode,202)
        let reply=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(reply["statusUrl"]as?String)));var terminal:[String:Any]?
        for _ in 0..<1000 {let response=try await helper.request(service,path:url.path),value=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any]);if ["succeeded","failed"].contains(value["status"]as?String ?? ""){terminal=value;break};try await Task.sleep(for:.milliseconds(10))}
        let result=try XCTUnwrap(terminal);XCTAssertEqual(result["status"]as?String,format == .psd ? "failed":"succeeded")
        if format != .psd {let outputs=try XCTUnwrap((result["result"]as?[String:Any])?["outputs"]as?[[String:Any]]),destination=try XCTUnwrap(outputs.first?["destination"]as?[String:Any]),assetURL=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"]as?String)));let asset=try await helper.request(service,path:assetURL.path);XCTAssertEqual(asset.0.statusCode,200);XCTAssertTrue(asset.1 == (try DocumentIO.encode(PcraftImport.read(input),format:format)),"Native/resource encoded equality")}
      }
      XCTAssertTrue(parent.store.document==original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
    }
  }

}
