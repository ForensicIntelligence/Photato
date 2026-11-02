import AppKit
import CoreText
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PcraftTextWorkflowTests:XCTestCase {
  func fixture(_ bits:String="u8")throws->Data {let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/PcraftText");for name in ["Inter-Regular.ttf","Inter-Medium.ttf","Inter-SemiBold.ttf"]{var error:Unmanaged<CFError>?;_ = CTFontManagerRegisterFontsForURL(root.appendingPathComponent("fonts/"+name)as CFURL,.process,&error)};return try Data(contentsOf:root.appendingPathComponent("text-\(bits).pcraft"))}
  @MainActor func testNativeSourceTextOpenCancelNoOpEditUndoSaveAndOriginalPreservation()async throws {
    _ = NSApplication.shared;let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    for bits in ["u8","u16","f32"] {
      let bytes=try fixture(bits),source=folder.appendingPathComponent("owned-\(bits).pcraft");try bytes.write(to:source)
      let prepared=try PreparedLocalDocument.read(source,format:.pcraft),document=prepared.makeDocument(url:source),store=document.store;defer{store.renderTask?.cancel();document.updateChangeCount(.changeCleared);document.close()}
      XCTAssertNil(document.fileURL);XCTAssertEqual(document.importedSourceURL,source);let layer=try XCTUnwrap(store.document.layers.first{$0.name=="point"});store.select(layer.id);let original=store.document
      store.beginType(layer);XCTAssertNotNil(store.typeEditingDraft);XCTAssertTrue(store.finishType(cancel:true));XCTAssertTrue(store.document==original)
      store.beginType(layer);XCTAssertTrue(store.finishType());XCTAssertTrue(store.document==original);XCTAssertTrue(store.session.undoStack.isEmpty)
      store.formatType{s,_ in s.tracking=30};XCTAssertNil(store.error);XCTAssertNil(store.activeLayer?.typeContent?.importedAppearance);XCTAssertEqual(store.session.undoStack.count,1)
      let edited=store.document,target=folder.appendingPathComponent("migrated-\(bits).photato");try await DocumentSaveWorkflowTests().save(document,to:target,format:.native);XCTAssertTrue(try DocumentIO.read(target)==edited);XCTAssertEqual(try Data(contentsOf:source),bytes)
      try store.session.undo();XCTAssertTrue(store.document==original)
    }
  }
  @MainActor func testHTTPTypeCacheNoOpEditHistoryNative69AndDesktopEquality()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,parent in
      defer{for document in service.controller.documents where document !== parent{document.updateChangeCount(.changeCleared);document.close()}}
      service.setDocumentTransfersEnabled(true);let bytes=try self.fixture("f32"),upload=try await AutomationOpeningTests().upload(service,bytes:bytes,type:PcraftImport.mediaType,format:"pcraft");XCTAssertEqual(upload.0.statusCode,201,String(decoding:upload.1,as:UTF8.self))
      let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),layer=try XCTUnwrap(document.store.document.layers.first{$0.name=="point"});document.store.select(layer.id);let original=document.store.document,text=try XCTUnwrap(layer.typeContent)
      let noOp=try await helper.edit(service,document,"text.set",["layerID":layer.id.uuidString,"text":text.apiType]);XCTAssertEqual(noOp,200);XCTAssertTrue(document.store.document==original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      var changed=text;changed.typography?.defaultStyle.tracking=40;if let count=changed.typography?.runs.count{for i in 0..<count{changed.typography?.runs[i].style.tracking=40}}
      var expected=original;try ShapedTextLayout.replacement(layer,content:changed,document:expected).apply(to:&expected)
      let params:[String:Any]=["layerID":layer.id.uuidString,"text":changed.apiType],edited=try await helper.edit(service,document,"text.set",params);XCTAssertEqual(edited,200);XCTAssertTrue(document.store.document==expected,"Native/API type transaction equality")
      XCTAssertEqual(try Renderer.composite(document.store.document).rgbaData(depth:.u8),try Renderer.composite(expected).rgbaData(depth:.u8))
      let stale=try await helper.edit(service,document,"text.set",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginType(document.store.activeLayer!);let busy=try await helper.edit(service,document,"text.set",params);XCTAssertEqual(busy,409);_ = document.store.finishType(cancel:true)
      var invalid=changed.apiType;invalid["sourceFrame"]=["kind":"point","x":0,"y":0,"width":1,"height":1,"unknown":true];let bad=try await helper.edit(service,document,"text.set",["layerID":layer.id.uuidString,"text":invalid]);XCTAssertEqual(bad,400);XCTAssertTrue(document.store.document==expected)
      let route="/v1/documents/\(share.id)/file.photato",old=try await helper.request(service,path:route,headers:["X-Photato-Archive-Version":"68"]);XCTAssertEqual(old.0.statusCode,422)
      let file=try await helper.request(service,path:route,headers:["X-Photato-Archive-Version":"69"]);XCTAssertEqual(file.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(file.1)==expected)
      try document.store.session.undo();XCTAssertTrue(document.store.document==original)
      let state=service.state(share,document:document),rows=try XCTUnwrap(state["layers"]as?[[String:Any]]),row=try XCTUnwrap(rows.first{($0["id"]as?String)==layer.id.uuidString});XCTAssertNotNil(row["textSource"])
    }
  }
  @MainActor func testRichTypeSchemaActions25ReplayAndExplicitPSDOutputBoundary()throws {
    let model=try PcraftImport.read(fixture()),layer=try XCTUnwrap(model.layers.first{$0.name=="point"});var text=try XCTUnwrap(layer.typeContent)
    for candidate in model.layers{if let original=candidate.typeContent{let decoded=try TextContent.decodeAPIType(original.apiType);XCTAssertEqual(TextAppearanceReference(decoded),TextAppearanceReference(original))}}
    text.text="Recorded native type";text.typography?.runs=[];let command=try ShapedTextLayout.replacement(layer,content:text,document:model),action=RecordedAction(name:"Type edit",steps:[.init(name:"Edit",operation:ActionOperation(recording:command,in:model))]);let file=try ActionLibraryFile.decode(ActionLibraryFile(actions:[action]).encoded());XCTAssertEqual(file.version,25)
    var native=model,replay=model;try command.apply(to:&native);try file.actions[0].apply(to:&replay);XCTAssertTrue(native==replay)
    XCTAssertThrowsError(try DocumentIO.encode(model,format:.psd));XCTAssertNoThrow(try DocumentIO.encode(model,format:.png));XCTAssertNoThrow(try DocumentIO.encode(model,format:.tiff))
  }
  @MainActor func testFractionalFrameControlsUseSameNativeTransactionAndCancelWithoutHistory()throws {
    let model=try PcraftImport.read(fixture()),store=EditorStore(document:model);defer{store.renderTask?.cancel()}
    let layer=try XCTUnwrap(model.layers.first{$0.name=="rich-box"});store.select(layer.id);let selected=store.document
    var frame=try XCTUnwrap(layer.typeContent?.typography?.sourceFrame);frame.x=2.125;frame.y = -3.75;frame.width=141.25;frame.height=76.125
    store.setFractionalTypeFrame(frame);XCTAssertNil(store.error)
    XCTAssertEqual(store.activeLayer?.typeContent?.typography?.sourceFrame,frame);XCTAssertNil(store.activeLayer?.typeContent?.importedAppearance);XCTAssertEqual(store.session.undoStack.count,1)
    var expected=selected;var content=try XCTUnwrap(layer.typeContent);content.typography?.sourceFrame=frame;content.layoutWidth=142;content.layoutHeight=77
    try ShapedTextLayout.replacement(layer,content:content,document:expected).apply(to:&expected);XCTAssertTrue(store.document==expected)
    try store.session.undo();XCTAssertTrue(store.document==selected)
    store.beginType(layer)
    let editor=try CanvasTypeEditor(store:store,draft:XCTUnwrap(store.typeEditingDraft));store.typeEditor=editor
    store.setFractionalTypeFrame(frame);XCTAssertNil(store.error)
    XCTAssertEqual(store.typeEditor?.textContainer?.containerSize,NSSize(width:141.25,height:76.125))
    XCTAssertTrue(store.finishType(cancel:true));XCTAssertTrue(store.document==selected);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  private actor Transport:AdobeResourceTransport {
    let data:Data
    init(_ data:Data){self.data=data}
    func fetch(_ url:URL)async throws->Data{data}
    func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws{throw AdobeAPIError.unsupported("Hosted fixture output only.")}
  }
  @MainActor func testTextResourceJobsMatchNativeOutputAndKeepPublishedAdobeFormatBoundary()async throws {
    let helper=AutomationTests()
    for (bits,media,format) in [("u8","image/png",DocumentIO.Format.png),("f32","image/tiff",DocumentIO.Format.tiff)] {
      let input=try fixture(bits)
      let payload:[String:Any]=["image":["source":["url":"https://example.test/owned-type.pcraft"]],
        "options":["actions":[["source":["contentType":"application/json","content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],
        "outputs":[["mediaType":media,"destination":["validityPeriod":60]]]]
      try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)){service,parent in
        let original=parent.store.document;service.setResourceJobsEnabled(true)
        for route in ["/v1/action-jobs","/v2/execute-actions"] {
          let response=try await helper.request(service,path:route,body:payload);XCTAssertEqual(response.0.statusCode,202)
          let result=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any]),status=try XCTUnwrap(URL(string:try XCTUnwrap(result["statusUrl"]as?String)))
          var terminal:[String:Any]?
          for _ in 0..<1000 {let reply=try await helper.request(service,path:status.path),value=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1)as?[String:Any]);if ["succeeded","failed"].contains(value["status"]as?String ?? ""){terminal=value;break};try await Task.sleep(for:.milliseconds(10))}
          let value=try XCTUnwrap(terminal);XCTAssertEqual(value["status"]as?String,route.hasPrefix("/v1") ? "succeeded":"failed","\(value)")
          if route.hasPrefix("/v1") {
            let outputs=try XCTUnwrap((value["result"]as?[String:Any])?["outputs"]as?[[String:Any]]),destination=try XCTUnwrap(outputs.first?["destination"]as?[String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"]as?String)))
            let asset=try await helper.request(service,path:url.path);XCTAssertEqual(asset.0.statusCode,200);XCTAssertEqual(asset.1,try DocumentIO.encode(PcraftImport.read(input),format:format))
          }
        }
        XCTAssertTrue(parent.store.document==original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
      }
    }
  }

  func adobeRichAddition(alignment:String="justify_center",aa:String="strong")->[String:Any] {
    ["type":"text_layer","operation":["type":"add","placement":["type":"top"]],"name":"Rich caption",
      "text":["content":"Photato words\nNative caption","frame":["type":"area","bounds":["left":10,"top":20,"right":230,"bottom":150]],"antiAliasing":aa,
        "characterStyles":[["characterStyle":["font":["postScriptName":"HelveticaNeue"],"fontSize":20,"syntheticBold":true,"syntheticItalic":true,"capsOption":"all_caps"]]],
        "paragraphStyles":[["paragraphStyle":["alignment":alignment,"firstLineIndent":-2.5,"endIndent":-1.25]]]]]
  }
  func testPublishedAdobeRichTypeMappingsAndUnknownValuesAreAtomic()throws {
    let base=try CraftDocument(width:300,height:200),helper=NativeTypeWorkflowTests()
    for (alignment,last) in [("justify_left",TypeParagraphFormatting.LastLine.left),("justify_center",.center),("justify_right",.right),("justify",.justified)] {
      let doc=try helper.request([adobeRichAddition(alignment:alignment)]).applying(to:base).session.document,layer=try XCTUnwrap(doc.layers.last),text=try XCTUnwrap(layer.typeContent),style=try XCTUnwrap(text.typography?.runs.first?.style),paragraph=try XCTUnwrap(text.typography?.runs.first?.paragraph)
      XCTAssertEqual(style.characterFormatting?.caps,.allCaps);XCTAssertTrue(style.characterFormatting?.fauxBold==true);XCTAssertTrue(style.characterFormatting?.fauxItalic==true)
      XCTAssertEqual(paragraph.formatting?.lastLine ?? .left,last);XCTAssertEqual(paragraph.firstIndent,-2.5);XCTAssertEqual(paragraph.endIndent,-1.25);XCTAssertEqual(text.typography?.antialiasMode,.strong)
      XCTAssertEqual(doc.minimumArchiveVersion,69);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(doc))==doc)
      let native=try TextContent.decodeAPIType(text.apiType);XCTAssertEqual(TextAppearanceReference(native),TextAppearanceReference(text));XCTAssertGreaterThan(try Renderer.composite(doc).rgbaData(depth:.u8).count,0)
    }
    for aa in ["none","sharp","crisp","strong","smooth"] {XCTAssertNoThrow(try helper.request([adobeRichAddition(aa:aa)]).applying(to:base))}
    for aa in ["windowsLCD","invalid"] {XCTAssertThrowsError(try helper.request([adobeRichAddition(aa:aa)]).applying(to:base))}
    var bad=adobeRichAddition(),text=bad["text"]as![String:Any];text["characterStyles"]=[["characterStyle":["capsOption":"all_small_caps"]]];bad["text"]=text
    XCTAssertThrowsError(try helper.request([bad]).applying(to:base));XCTAssertEqual(base.layers.count,1)
  }
  @MainActor func testPublishedAdobeCompositeRichTextPNGMatchesSharedNativeEngine()async throws {
    let base=try CraftDocument(width:300,height:200),input=try PSDCodec.writeRasterLayers(base),edit=adobeRichAddition()
    let expected=try NativeTypeWorkflowTests().request([edit]).applying(to:base).session.document
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:Transport(input)){service,parent in
      let original=parent.store.document;service.setResourceJobsEnabled(true)
      let payload:[String:Any]=["image":["source":["url":"https://example.test/owned-rich-type.psd"]],"edits":["layers":[edit]],"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
      let output=try await AutomationActionJobsTests().output(service,submit:"/v2/create-composite",payload:payload,expectedMediaType:"image/png")
      XCTAssertEqual(output.2,try DocumentIO.encode(expected,format:.png));XCTAssertTrue(parent.store.document==original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
    }
  }

}
