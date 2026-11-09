import AppKit
import Foundation
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GeneratedVariationTests:XCTestCase {
  func bytes(_ color:Pixel) throws->Data {
    var doc=try CraftDocument(width:4,height:3)
    doc.layers[0].content = .raster(try Surface(width:4,height:3,depth:.u8,fill:color))
    return try DocumentIO.encode(doc,format:.png)
  }
  func image(_ color:Pixel,source:CraftDocument,prompt:String) throws->Layer {
    try GeneratedImageStorage.preparedLayer(bytes(color),source:source,requestID:UUID(),sourceRevision:UUID(),
      initialPrompt:prompt,startedAt:Date(timeIntervalSince1970:100),acceptedAt:Date(timeIntervalSince1970:101),
      processing:.onDevice,resultStyle:nil)
  }
  func source(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:12,height:8,depth:depth)
    let first=try image(Pixel(1,0,0),source:d,prompt:"Owned red")
    d.layers.append(first);d.activeLayerID=first.id;return d
  }
  func append(_ color:Pixel,to d:CraftDocument)throws->(CraftDocument,GeneratedVariations.Index) {
    let target=try XCTUnwrap(d.activeLayerID),next=try image(color,source:d,prompt:"Owned alternative")
    let (_,command)=try GeneratedVariations.appending(next,to:target,in:d)
    var result=d;try command.apply(to:&result)
    return(result,try XCTUnwrap(GeneratedVariations.read(try XCTUnwrap(result.layers.first{$0.id==target}))))
  }
  func testAllRGBDepthsKeepAlternativesOriginalBytesExactPixelsHistoryAndOfflineArchive()throws {
    for depth in PixelDepth.allCases {
      let original=try source(depth),id=try XCTUnwrap(original.activeLayerID),old=try XCTUnwrap(original.layers.last)
      let before=try Renderer.composite(original).rgbaData(depth:.f32,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      let next=try image(Pixel(0,0,1),source:original,prompt:"Owned blue")
      let (layer,command)=try GeneratedVariations.appending(next,to:id,in:original)
      var session=EditorSession(document:original);try session.execute(command)
      let result=session.document,index=try XCTUnwrap(GeneratedVariations.read(layer))
      XCTAssertEqual(result.layers.count,original.layers.count);XCTAssertEqual(layer.id,id);XCTAssertEqual(index.entries.count,2)
      XCTAssertEqual(layer.x,old.x);XCTAssertEqual(layer.y,old.y)
      XCTAssertEqual(try GeneratedImageStorage.original(layer).1,try bytes(Pixel(0,0,1)))
      XCTAssertNil(try GeneratedImageStorage.record(layer)?.seed);XCTAssertNil(try GeneratedImageStorage.record(layer)?.modelIdentifier)
      let archive=try DocumentIO.encode(result,format:.native),read=try DocumentIO.decode(archive,native:true,name:"Offline")
      if depth == .u16,let directory=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        var (capture,_)=try append(Pixel(0,1,0),to:result)
        capture.name="Owned Synthetic Variations 517";capture.width=640;capture.height=480
        capture.layers[0].content = .raster(try Surface(width:640,height:480,depth:depth,fill:.white))
        let position=try XCTUnwrap(capture.layers.firstIndex{$0.id==id})
        capture.layers[position].x=160;capture.layers[position].y=120;capture.layers[position].affine = .scale(80,80)
        try capture.validate()
        try DocumentIO.encode(capture,format:.native).write(to:URL(fileURLWithPath:directory).appendingPathComponent("Owned-Synthetic-Variations-517.photato"))
      }
      XCTAssertEqual(read,result);XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(read.layers.last)).1,try bytes(Pixel(0,0,1)))
      try session.execute(SmartObjectLayerCompIO.selection(in:session.document,layerID:id,compID:index.entries[0].id))
      XCTAssertEqual(try Renderer.composite(session.document).rgbaData(depth:.f32,colorEncoding:depth == .f32 ? .linearRGB:.sRGB),before)
      XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(session.document.layers.last)).1,try bytes(Pixel(1,0,0)))
      try session.undo();XCTAssertEqual(session.document,result);try session.redo()
      try session.undo();try session.undo();XCTAssertEqual(session.document,original)
      XCTAssertNil(DocumentIO.persistenceIssue(result,format:.native))
      for format in DocumentIO.Format.allCases where format != .native {XCTAssertNotNil(DocumentIO.persistenceIssue(result,format:format))}
    }
  }
  func testAppendingIsolatesDuplicatedInstancesAndRetainsParentPresentation()throws {
    var(original,index)=try append(Pixel(0,0,1),to:source(.f32));let id=try XCTUnwrap(original.activeLayerID)
    let i=try XCTUnwrap(original.layers.firstIndex{$0.id==id})
    original.layers[i].opacity=0.6;original.layers[i].affine = .translation(2,1) * .scale(1.5,1.5)
    original.layers[i].mask=try Surface(width:4,height:3,depth:.f32,fill:Pixel(0.5,0.5,0.5))
    var copy=original.layers[i];copy.id=UUID();copy.name="Independent copy";original.layers.append(copy)
    let(target,command)=try GeneratedVariations.appending(image(Pixel(0,1,0),source:original,prompt:"Owned green"),to:id,in:original)
    var result=original;try command.apply(to:&result)
    XCTAssertEqual(target.affine,original.layers[i].affine);XCTAssertEqual(target.mask,original.layers[i].mask);XCTAssertEqual(target.opacity,0.6)
    XCTAssertEqual(result.layers.last,copy);XCTAssertNotEqual(target.smartObject?.sourceID,copy.smartObject?.sourceID)
    XCTAssertEqual(try GeneratedVariations.read(target)?.entries.prefix(2).map(\.id),index.entries.map(\.id))
    XCTAssertEqual(try GeneratedVariations.read(target)?.entries.count,3)
    var stale=original;stale.name="Changed";XCTAssertThrowsError(try command.apply(to:&stale));XCTAssertEqual(stale.name,"Changed")
  }
  func testDeleteSelectedInactiveAndLastVariationIsUndoableAndKeepsOtherOriginals()throws {
    let(two,index)=try append(Pixel(0,0,1),to:source()),id=try XCTUnwrap(two.activeLayerID)
    var session=EditorSession(document:two)
    try session.execute(GeneratedVariations.deleting(index.entries[0].id,from:id,in:session.document))
    let one=session.document,layer=try XCTUnwrap(one.layers.last)
    XCTAssertEqual(try GeneratedVariations.read(layer)?.entries.count,1)
    XCTAssertEqual(try GeneratedImageStorage.original(layer).1,try bytes(Pixel(0,0,1)))
    try session.undo();XCTAssertEqual(session.document,two)
    try session.execute(GeneratedVariations.deleting(index.entries[1].id,from:id,in:session.document))
    XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(session.document.layers.last)).1,try bytes(Pixel(1,0,0)))
    let remaining=try XCTUnwrap(GeneratedVariations.read(try XCTUnwrap(session.document.layers.last))?.entries.first)
    try session.execute(GeneratedVariations.deleting(remaining.id,from:id,in:session.document))
    XCTAssertEqual(session.document.layers.count,1);XCTAssertFalse(session.document.layers.contains{$0.id==id})
    try session.undo();XCTAssertEqual(try GeneratedVariations.read(try XCTUnwrap(session.document.layers.last))?.entries.count,1)
  }
  func testMalformedReplacedMissingOrLockedSourcesAndDuplicateResultsRejectAtomically()throws {
    let(original,index)=try append(Pixel(0,0,1),to:source()),id=try XCTUnwrap(original.activeLayerID),position=original.layers.count-1
    let next=try image(Pixel(0,1,0),source:original,prompt:"Owned green")
    for mode in 0..<5 {
      var bad=original
      if mode==0 {bad.layers[position].sourceTags?[GeneratedVariations.key]=Data("{}".utf8)}
      if mode==1 {bad.layers[position].smartObject?.data=Data("changed".utf8)}
      if mode==2 {bad.layers[position].smartObject=nil}
      if mode==3 {bad.layers[position].smartObject?.layerComps?.entries.removeLast()}
      if mode==4 {
        var fields=try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(bad.layers[position].sourceTags?[GeneratedVariations.key]))as?[String:Any])
        fields["unrepresented"]=true;bad.layers[position].sourceTags?[GeneratedVariations.key]=try JSONSerialization.data(withJSONObject:fields)
      }
      XCTAssertThrowsError(try GeneratedVariations.read(bad.layers[position]))
      XCTAssertThrowsError(try GeneratedVariations.appending(next,to:id,in:bad));XCTAssertEqual(bad.layers.count,original.layers.count)
    }
    let duplicate=try XCTUnwrap(SmartObjectIO.sourceDocument(try XCTUnwrap(original.layers.last?.smartObject)).layers.last)
    XCTAssertThrowsError(try GeneratedVariations.appending(duplicate,to:id,in:original))
    XCTAssertThrowsError(try GeneratedVariations.deleting(UUID(),from:id,in:original));XCTAssertEqual(index.entries.count,2)
  }
  @MainActor func testNativeImmutableVariationRequestCommitsOnceAndReopensWithoutModels()async throws {
    let helper=ImageGenerationLifecycleTests(),store=try helper.store();defer{store.cancelAIWork();store.renderTask?.cancel()}
    let first=try helper.complete(store,data:bytes(Pixel(1,0,0)));await first.value
    let before=store.document,id=try XCTUnwrap(store.activeLayer?.id),history=store.session.undoStack.count
    store.prepareGeneratedVariation();XCTAssertEqual(store.imageGenerationTargetLayerID,id);XCTAssertTrue(store.showAI)
    let job=try helper.begin(store,prompt:"Owned blue")
    XCTAssertEqual(job.variationTargetLayerID,id)
    store.imageGenerationTargetLayerID=nil
    try store.acceptGeneratedImageData(bytes(Pixel(0,0,1)),requestID:job.id)
    let task=try XCTUnwrap(store.aiTask);await task.value
    XCTAssertEqual(job.phase,.completed,store.aiError ?? "");XCTAssertEqual(job.resultLayerID,id)
    XCTAssertEqual(store.document.layers.count,before.layers.count);XCTAssertEqual(store.session.undoStack.count,history+1)
    let layer=try XCTUnwrap(store.activeLayer);XCTAssertEqual(try GeneratedVariations.read(layer)?.entries.count,2)
    let state=AIImageAPI.state(store),props=try XCTUnwrap(AIImageAPI.stateSchema["properties"]as?[String:Any]);XCTAssertTrue(Set(state.keys).isSubset(of:Set(props.keys)))
    XCTAssertNotNil(state["selectedVariations"]as?[String:Any])
    let result=store.document;await store.undo();XCTAssertEqual(store.document,before);await store.redo();XCTAssertEqual(store.document,result)
  }
  @MainActor func testCancelledAndStaleVariationRequestsKeepInboxOriginalAndDoNotEditTarget()async throws {
    let h=ImageGenerationLifecycleTests(),s=try h.store();defer{s.cancelAIWork();s.renderTask?.cancel()}
    let first=try h.complete(s);await first.value
    s.prepareGeneratedVariation();let job=try h.begin(s)
    try s.executeEditorCommand(.renameLayer(try XCTUnwrap(s.activeLayer?.id),"Changed"));let before=s.document
    let original=try bytes(Pixel(0,0,1));try s.acceptGeneratedImageData(original,requestID:job.id)
    XCTAssertEqual(job.phase,.stale);XCTAssertEqual(s.document,before);XCTAssertEqual(try s.generatedResultInbox.load(job.id).1,original)
    s.prepareGeneratedVariation();let cancelled=try h.begin(s);s.cancelImageGeneration(cancelled.id)
    XCTAssertThrowsError(try s.acceptGeneratedImageData(original,requestID:cancelled.id));XCTAssertEqual(s.document,before)
  }
  @MainActor func testHTTPPrepareSelectionDeleteOriginalAndRevisionGuardsUseNativeBank()async throws {
    let h=AutomationTests(),fixture=try append(Pixel(0,0,1),to:source())
    try await h.withService(pressedMouseButtons:{0}){service,doc in
      let store=doc.store;defer{store.cancelAIWork();store.renderTask?.cancel()}
      store.session=EditorSession(document:fixture.0);store.renderTask?.cancel();try service.share(doc)
      let share=try XCTUnwrap(service.shares.first),base="/v1/documents/\(share.id)",id=try XCTUnwrap(store.activeLayer?.id)
      let state=try await h.request(service,path:base+"/ai");XCTAssertEqual(state.0.statusCode,200)
      let fields=try XCTUnwrap(JSONSerialization.jsonObject(with:state.1)as?[String:Any]);XCTAssertNotNil(fields["selectedVariations"]as?[String:Any])
      let denied=try await h.request(service,path:base+"/ai/results/\(id)");XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let raw=try await h.request(service,path:base+"/ai/results/\(id)");XCTAssertEqual(raw.0.statusCode,200);XCTAssertEqual(raw.1,try self.bytes(Pixel(0,0,1)))
      let before=store.document
      let chosen=try await h.request(service,path:base+"/commands",body:["command":"smartObject.layerComp","revision":service.revision(store),"parameters":["layerID":id.uuidString,"compID":fixture.1.entries[0].id.uuidString]])
      XCTAssertEqual(chosen.0.statusCode,200,String(decoding:chosen.1,as:UTF8.self))
      XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(store.activeLayer)).1,try self.bytes(Pixel(1,0,0)))
      await store.undo();XCTAssertEqual(store.document,before)
      service.setWorkspacePanelChangesEnabled(true)
      let window=NSWindowController(window:NSWindow(contentRect:.init(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false));doc.addWindowController(window)
      defer{store.showAI=false;doc.removeWindowController(window);window.close()}
      let prepared=try await h.request(service,path:base+"/ai",body:["operation":"prepare","revision":service.revision(store),"prompt":"Owned next variation","targetLayerID":id.uuidString])
      XCTAssertEqual(prepared.0.statusCode,200,String(decoding:prepared.1,as:UTF8.self));XCTAssertEqual(store.imageGenerationTargetLayerID,id)
      XCTAssertTrue(store.showAI);XCTAssertFalse(store.aiBusy);XCTAssertNil(store.imageGenerationJob);XCTAssertEqual(store.document,before)
      let invalid=try await h.request(service,path:base+"/ai",body:["operation":"prepare","revision":service.revision(store),"prompt":"Owned","targetLayerID":"invalid"]);XCTAssertEqual(invalid.0.statusCode,400)
      let stale=try await h.request(service,path:base+"/ai",body:["operation":"deleteVariation","revision":"stale","layerID":id.uuidString,"variationID":fixture.1.entries[1].id.uuidString]);XCTAssertEqual(stale.0.statusCode,409);XCTAssertEqual(store.document,before)
      let removed=try await h.request(service,path:base+"/ai",body:["operation":"deleteVariation","revision":service.revision(store),"layerID":id.uuidString,"variationID":fixture.1.entries[1].id.uuidString]);XCTAssertEqual(removed.0.statusCode,200,String(decoding:removed.1,as:UTF8.self))
      XCTAssertEqual(try GeneratedVariations.read(try XCTUnwrap(store.activeLayer))?.entries.count,1)
      XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(store.activeLayer)).1,try self.bytes(Pixel(1,0,0)))
      await store.undo();XCTAssertEqual(store.document,before)
    }
  }
  @MainActor func testNativeOfflineChooserAndActualThumbnailPixelsRequireNoGenerationContext()async throws {
    let (document,index)=try append(Pixel(0,0,1),to:source())
    let helper=ImageGenerationLifecycleTests(),store=try helper.store();defer{store.renderTask?.cancel();store.cancelAIWork()}
    store.session=EditorSession(document:document);store.imageGenerationSourceAvailable={false}
    XCTAssertFalse(store.canStartImageGeneration);XCTAssertTrue(store.canChooseSmartObjectComp)
    let layer=try XCTUnwrap(store.activeLayer),previews=try GeneratedVariations.thumbnails(layer)
    XCTAssertEqual(previews.images.count,2)
    let red=try XCTUnwrap(previews.images[index.entries[0].id]),blue=try XCTUnwrap(previews.images[index.entries[1].id])
    XCTAssertEqual(red.width,4);XCTAssertEqual(red.height,3)
    XCTAssertEqual(try RasterIO.surface(red).pixel(x:0,y:0),Pixel(1,0,0))
    XCTAssertEqual(try RasterIO.surface(blue).pixel(x:0,y:0),Pixel(0,0,1))
    store.chooseSmartObjectComp(index.entries[0].id)
    let task=try XCTUnwrap(store.geometryTask);await task.value
    XCTAssertEqual(try GeneratedImageStorage.record(try XCTUnwrap(store.activeLayer))?.initialPrompt,"Owned red")
    XCTAssertNil(store.imageGenerationJob);XCTAssertFalse(store.aiBusy)
    await store.undo();XCTAssertEqual(store.document,document)
  }

  func testRestoringEditedNonprimaryAlphaAndHDRWorkingPixelsKeepsEveryOutputBit()throws {
    for depth in PixelDepth.allCases {
      var original=try source(depth)
      let position=original.layers.count-1,id=original.layers[position].id
      let first=try image(Pixel(0.2,0.4,0.6,0.37),source:original,prompt:"Owned translucent colors")
      guard case .raster(var pixels)=first.content else{return XCTFail("Not pixels")}
      if depth == .f32 {pixels.setLinearPixel(x:1,y:1,Pixel(-0.125,1.75,0.3125,0.375))}
      original.layers[position].content = .raster(pixels);original.layers[position].sourceTags=first.sourceTags
      original.layers[position].affine = .translation(0.25,0.5) * .scale(1.25,1.25)
      original.layers[position].opacity=0.73
      original.layers[position].mask=try Surface(width:4,height:3,depth:.f32,fill:Pixel(0.5,0.5,0.5))
      let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
      let before=try Renderer.composite(original).rgbaData(depth:.f32,colorEncoding:encoding)
      let (bank,index)=try append(Pixel(0.7,0.2,0.1,0.6),to:original)
      var restored=bank;try SmartObjectLayerCompIO.selection(in:bank,layerID:id,compID:index.entries[0].id).apply(to:&restored)
      XCTAssertEqual(try Renderer.composite(restored).rgbaData(depth:.f32,colorEncoding:encoding),before,"Every working output component at\(depth)")
      XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(restored.layers.last)).1,try bytes(Pixel(0.2,0.4,0.6,0.37)))
    }
  }

}
