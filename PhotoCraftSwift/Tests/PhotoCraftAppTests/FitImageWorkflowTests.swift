import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class FitImageWorkflowTests: XCTestCase {
  func fixture(_ width:Int = 8,_ height:Int = 4)throws->CraftDocument {try FitImageTestsFixture.make(width,height)}
  func capture(_ document:CraftDocument,_ name:String)throws {
    guard let path=ProcessInfo.processInfo.environment["PHOTATO_FIT_IMAGE_OUTPUT_DIR"]else{return}
    let directory=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try DocumentIO.encode(document,format:.png).write(to:directory.appendingPathComponent(name+".png"))
    let metadata:[String:Any] = ["file":name+".png","width":document.width,"height":document.height,"expectedRGBA":[255,255,255,255]]
    try JSONSerialization.data(withJSONObject:metadata,options:.sortedKeys).write(to:directory.appendingPathComponent(name+".json"))
  }
  @MainActor func testNativeMenuDialogCancelInvalidStaleCommitAndUndo()async throws {
    let source=try fixture(),store=EditorStore(document:source,actions:ActionLibrary());defer{store.geometryTask?.cancel();store.renderTask?.cancel()}
    XCTAssertTrue(store.canBeginFitImage);store.beginFitImage()
    let first=try XCTUnwrap(store.fitImageDraft);first.width="6";first.height="6"
    let view=NSHostingView(rootView:FitImageSheet(store:store,draft:first));view.frame=NSRect(x:0,y:0,width:400,height:320);view.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(view.fittingSize.width,420);XCTAssertEqual(store.document,source);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.cancelFitImage();XCTAssertNil(store.fitImageDraft);XCTAssertEqual(store.document,source)
    store.beginFitImage();let invalid=try XCTUnwrap(store.fitImageDraft);invalid.width="not pixels";store.commitFitImage(invalid)
    XCTAssertNotNil(invalid.error);XCTAssertTrue(store.geometrySheet == .fitImage);XCTAssertEqual(store.document,source)
    store.cancelFitImage();store.beginFitImage();let stale=try XCTUnwrap(store.fitImageDraft)
    store.session=EditorSession(document:try fixture(9,6));store.commitFitImage(stale)
    XCTAssertNotNil(stale.error);XCTAssertEqual(store.document.width,9);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.cancelFitImage();store.session=EditorSession(document:source)
    try store.session.startActionRecording(name:"Owned Fit");store.beginFitImage();let draft=try XCTUnwrap(store.fitImageDraft)
    draft.width="6";draft.height="6";store.commitFitImage(draft);await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertNil(store.geometrySheet);XCTAssertEqual(store.document.width,6);XCTAssertEqual(store.document.height,3)
    XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(store.session.actionRecording?.snapshot.steps.count,1)
    let result=store.document;let undo=await store.undo();XCTAssertTrue(undo);XCTAssertEqual(store.document,source)
    let redo=await store.redo();XCTAssertTrue(redo);XCTAssertEqual(store.document,result)
    try capture(result,"native-fit")
    try PhotoshopMenuTests().withMenus {_,menu in
      func find(_ menu:NSMenu)->NSMenuItem? {for item in menu.items {if item.identifier?.rawValue=="File > Automate > Fit Image…"{return item};if let sub=item.submenu,let result=find(sub){return result}};return nil}
      let item=try XCTUnwrap(find(menu));XCTAssertEqual(item.action,#selector(AppDelegate.fitImage));XCTAssertEqual(item.keyEquivalent,"")
    }
  }
  @MainActor func testNativeAndHTTPModesDepthsSettingsAndPersistenceMatch()async throws {
    let helper=AutomationTests()
    let modes:[(DocumentColorMode,PixelDepth)] = [(.rgb,.u8),(.rgb,.u16),(.rgb,.f32),(.grayscale,.u8),(.grayscale,.u16),(.grayscale,.f32),(.cmyk,.u8),(.cmyk,.u16),(.lab,.u8),(.lab,.u16)]
    for (mode,depth) in modes {
      let source=try EditableLifecycleModel.make(width:8,height:4,depth:depth,background:.white,mode:mode,resolution:240)
      let native=EditorStore(document:source,actions:ActionLibrary());defer{native.geometryTask?.cancel();native.renderTask?.cancel()}
      native.beginFitImage();let draft=try XCTUnwrap(native.fitImageDraft);draft.width="6";draft.height="6";native.commitFitImage(draft);await native.geometryTask?.value
      XCTAssertNil(native.error);XCTAssertEqual(native.document.width,6);XCTAssertEqual(native.document.height,3)
      XCTAssertEqual(native.document.resolution,source.resolution);XCTAssertEqual(native.document.workingICC,source.workingICC)
      try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,shared in
        shared.store.session=EditorSession(document:source);try service.share(shared);service.setDocumentTransfersEnabled(true)
        let code=try await helper.edit(service,shared,"document.fitImage",["width":6,"height":6]);XCTAssertEqual(code,200)
        XCTAssertEqual(shared.store.document,native.document);XCTAssertEqual(shared.store.session.undoStack.count,1)
        let id=try XCTUnwrap(service.shares.first?.id)
        let download=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"85"])
        XCTAssertEqual(download.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(download.1),native.document)
        try capture(shared.store.document,"api-\(mode.rawValue)-\(depth.rawValue)")
      }
    }
  }
  @MainActor func testWholeDocumentAuxiliaryAndLayerMaskTargetsKeepTheirIdentity()async throws {
    let helper=AutomationTests()
    for target in ["alpha","quickMask","layerMask","standalone"] {
      var source=try fixture();source.layers[0].mask=try Surface(width:8,height:4,fill:.white)
      source.alphaChannels=[AlphaChannel(name:"Saved",pixels:try Surface(width:8,height:4,fill:.white))]
      if target=="quickMask"{source.quickMask=AlphaChannel(name:"Quick Mask",pixels:try Surface(width:8,height:4,fill:.white))}
      if target=="standalone"{source.layers=[];source.activeLayerID=nil;source.channelOnly=true}
      try source.validate()
      try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,shared in
        let store=shared.store;store.session=EditorSession(document:source);try service.share(shared)
        if target=="layerMask"{store.selectMask(source.layers[0].id)}
        else if target=="quickMask"{try store.selectQuickMaskChannel()}
        else {try store.selectAlphaChannel(source.alphaChannels![0].id)}
        let selected=store.editingChannel,mask=store.selectedMaskPaintTarget
        XCTAssertTrue(store.canBeginFitImage)
        let code=try await helper.edit(service,shared,"document.fitImage",["width":6,"height":6]);XCTAssertEqual(code,200)
        XCTAssertEqual(store.document.width,6);XCTAssertEqual(store.document.height,3)
        XCTAssertEqual(store.editingChannel,selected);XCTAssertEqual(store.selectedMaskPaintTarget,mask)
        XCTAssertEqual(store.document.alphaChannels?.first?.id,source.alphaChannels?.first?.id)
        XCTAssertEqual(store.document.alphaChannels?.first?.pixels.width,6)
        if target=="layerMask"{XCTAssertEqual(store.document.layers[0].mask?.height,3)}
        if target=="quickMask"{XCTAssertEqual(store.document.quickMask?.pixels.height,3)}
        let undo=await store.undo();XCTAssertTrue(undo);XCTAssertEqual(store.document,source)
      }
    }
  }
  @MainActor func testHTTPStrictValidationBusyStaleNoOpAndExposedSchemas()async throws {
    let helper=AutomationTests();try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,shared in
      let source=try fixture(2,1),store=shared.store;store.session=EditorSession(document:source);try service.share(shared)
      try store.session.startActionRecording(name:"No enlargement")
      let noop=try await helper.edit(service,shared,"document.fitImage",["width":6,"height":6,"dontEnlarge":true]);XCTAssertEqual(noop,200)
      XCTAssertEqual(store.document,source);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertEqual(store.session.actionRecording?.snapshot.steps.count,1)
      for parameters:[String:Any]in [["width":0,"height":6],["width":6.5,"height":6],["width":300001,"height":6],["width":6,"height":6,"dontEnlarge":1],["width":6,"height":6,"method":"fake"],["width":6,"height":6,"resolution":300]] {
        let code=try await helper.edit(service,shared,"document.fitImage",parameters);XCTAssertEqual(code,400);XCTAssertEqual(store.document,source)
      }
      let stale=try await helper.edit(service,shared,"document.fitImage",["width":6,"height":6],revision:"old");XCTAssertEqual(stale,409)
      store.beginFitImage();let before=store.document,count=store.session.undoStack.count
      let busy=try await helper.edit(service,shared,"document.fitImage",["width":6,"height":6]);XCTAssertEqual(busy,409)
      let state=GeometryAPI.fitImageState(store);XCTAssertEqual(state["dialogOpen"]as?Bool,true)
      XCTAssertEqual(store.document,before);XCTAssertEqual(store.session.undoStack.count,count);store.cancelFitImage()
      let capability=try await helper.request(service,path:"/v1/capabilities");XCTAssertEqual(capability.0.statusCode,200)
      let json=try XCTUnwrap(JSONSerialization.jsonObject(with:capability.1)as?[String:Any]);XCTAssertNotNil((json["stateSchemas"]as?[String:Any])?["fitImage"])
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount);XCTAssertEqual(ActionLibraryFile.maximumVersion,51)
    }
  }
  @MainActor func testActionVersion45MixedBatchAndImageProcessorUseTheSameConstraint()async throws {
    let options=FitImageOptions(width:6,height:6,dontEnlarge:true,method:.nearest)
    let action=RecordedAction(name:"Fit mixed photos",steps:[.init(name:"Fit Image",operation:.fitImage(options))])
    let bytes=try ActionLibraryFile(actions:[action]).encoded();XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,45)
    var old=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes)as?[String:Any]);old["version"]=44
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:old)))
    old["version"]=ActionLibraryFile.maximumVersion+1;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:old)))
    let legacy=RecordedAction(name:"Legacy",steps:[.init(name:"Resize",operation:.imageSize(2,1,72,.nearest))])
    for version in 1...44 {XCTAssertNoThrow(try ActionLibraryFile.decode(ActionLibraryFile(version:version,actions:[legacy]).encoded()))}
    let directory=try ActionBatchTests().folder();defer{try? FileManager.default.removeItem(at:directory)}
    let originals=try [fixture(24,12),fixture(12,24),fixture(2,1)]
    let outputs=try await ActionBatch.run(sources:originals.map(ActionBatchSource.init(document:)),action:action,destination:directory,format:.native)
    XCTAssertEqual(outputs.count,3)
    for (i,result)in outputs.enumerated(){
      let name=try XCTUnwrap(result.output);XCTAssertNil(result.error)
      let read=try DocumentIO.read(directory.appendingPathComponent(name));XCTAssertEqual(read.width,[6,3,2][i]);XCTAssertEqual(read.height,[3,6,1][i])
      XCTAssertEqual(read.id,originals[i].id);try capture(read,"batch-\(i)")
    }
    var settings=ImageProcessorSettings();settings.jpeg.enabled=false;settings.psd.enabled=false
    settings.tiff = .init(enabled:true,resize:true,width:6,height:6);settings.dontEnlarge=true
    let processed=try ImageProcessor.render(originals.map(ActionBatchSource.init(document:)),settings:settings)
    XCTAssertEqual(processed.records.map(\.width),[6,3,2]);XCTAssertEqual(processed.records.map(\.height),[3,6,1])
    let library=ActionLibrary();try library.save(action)
    let helper=AutomationTests();try await helper.withService(actions:library,pressedMouseButtons:{0}){service,shared in
      shared.store.session=EditorSession(document:originals[1]);try service.share(shared);service.setDocumentSavesEnabled(true);service.setSaveDirectory(directory)
      let id=try XCTUnwrap(service.shares.first?.id)
      let parameters:[String:Any] = ["actionID":action.id.uuidString,"sources":[["id":id.uuidString,"revision":service.revision(shared.store)]],"format":"photato","suffix":"-api"]
      let reply=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"actions.batch","revision":service.revision(shared.store),"parameters":parameters])
      XCTAssertEqual(reply.0.statusCode,200)
      let body=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1)as?[String:Any]);let result=try XCTUnwrap((body["results"]as?[[String:Any]])?.first);let name=try XCTUnwrap(result["output"]as?String)
      let read=try DocumentIO.read(directory.appendingPathComponent(name));XCTAssertEqual(read.width,3);XCTAssertEqual(read.height,6)
      XCTAssertEqual(shared.store.document,originals[1]);XCTAssertTrue(shared.store.session.undoStack.isEmpty);try capture(read,"api-batch")
    }
  }
}

private enum FitImageTestsFixture {
  static func make(_ width:Int,_ height:Int)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height)
    let layer=Layer(name:"Owned white",content:.raster(try Surface(width:width,height:height,fill:.white)))
    d.layers=[layer];d.activeLayerID=layer.id;return d
  }
}
