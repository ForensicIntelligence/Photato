import AppKit
import Foundation
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class GalleryTextureWorkflowTests:XCTestCase {
  func url(_ name:String="owned-step-texture")->URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/OwnedGallery453/"+name+".psd")}
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try ArtisticGalleryWorkflowTests().fixture(depth,smart:smart)}
  func filter(_ kind:GalleryFilter = .texturizer)throws->RasterFilter {var f=RasterFilter(.filterGallery);var e=GalleryEffect(kind);e.texture=try GalleryTextureLoader.read(url());f.artistic?.effects=[e];return f}
  @MainActor func stop(_ store:EditorStore){store.cancelFilter();store.geometryTask?.cancel();store.renderTask?.cancel()}
  @MainActor func model(_ store:EditorStore,_ kind:GalleryFilter = .texturizer)async throws->ArtisticGalleryWorkspace {
    store.beginFilter(.filterGallery);let m=ArtisticGalleryWorkspace();store.artisticGalleryWorkspace=m;await m.prepare(document:store.document,draft:try XCTUnwrap(store.filterDraft));m.thumbnailTask?.cancel();m.choose(kind);await m.task?.value;return m
  }
  @MainActor func testNativeAllFiveTextureLoadsLocalHistoryAndCancelPreserveDocument()async throws {
    for kind in GalleryFilter.allCases.filter({GalleryTextureSource.supports($0)}) {
      let d=try fixture(),s=EditorStore(document:d,actions:ActionLibrary());defer{stop(s)}
      let m=try await model(s,kind),before=m.settings
      let load=try XCTUnwrap(m.loadTexture(url()));XCTAssertTrue(m.textureLoading);XCTAssertFalse(m.ready);await load.value;await m.task?.value
      XCTAssertTrue(m.ready,m.error ?? m.textureError ?? "Not ready");XCTAssertEqual(m.effect?.texture,try GalleryTextureLoader.read(url()));let loaded=m.settings
      XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty);m.undo();XCTAssertEqual(m.settings,before);m.redo();XCTAssertEqual(m.settings,loaded)
      m.close();s.cancelFilter();XCTAssertEqual(s.document,d)
    }
  }
  @MainActor func testCancelledClosedStaleAndFailedLoadsKeepPreviousSettingsAndUsablePreview()async throws {
    let s=EditorStore(document:try fixture(),actions:ActionLibrary());defer{stop(s)};let m=try await model(s)
    let initial=m.settings,load=try XCTUnwrap(m.loadTexture(url()));m.cancelTextureLoad();await load.value;XCTAssertEqual(m.settings,initial);XCTAssertFalse(m.textureLoading)
    m.add();await m.task?.value;m.selected=0
    let stale=try XCTUnwrap(m.loadTexture(url()));m.selected=1;await stale.value;XCTAssertFalse(m.textureLoading);XCTAssertNotNil(m.textureError);XCTAssertNil(m.settings.effects[0].texture);XCTAssertNil(m.settings.effects[1].texture)
    let failed=try XCTUnwrap(m.loadTexture(url("absent-owned-file")));await failed.value;XCTAssertNotNil(m.textureError);XCTAssertTrue(m.ready);XCTAssertTrue(s.session.undoStack.isEmpty)
    let closed=try XCTUnwrap(m.loadTexture(url()));m.close();await closed.value;XCTAssertNil(m.effect?.texture);XCTAssertFalse(m.textureLoading)
  }
  @MainActor func testNativeCommitUndoSmartReeditArchive88AndPortableActions54RetainSamples()async throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),s=EditorStore(document:d,actions:ActionLibrary());defer{stop(s)};let m=try await model(s)
      await m.loadTexture(url())?.value;await m.task?.value;XCTAssertTrue(m.ready)
      let f=try filter();s.filterDraft?.filter.artistic=m.settings;m.close();s.commitFilter();await s.geometryTask?.value
      XCTAssertNil(s.error);XCTAssertEqual(s.session.undoStack.count,1);var expected=d;try Command.applyFilter(d.layers[0].id,f).apply(to:&expected);XCTAssertEqual(s.document,expected)
      let undone=await s.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(s.document,d)
    }
    var d=try fixture(smart:true);let f=try filter(),source=d,id=d.layers[0].id
    try Command.applyFilter(id,f).apply(to:&d);XCTAssertEqual(d.minimumArchiveVersion,88);XCTAssertEqual(d.layers[0].content,source.layers[0].content)
    let encoded=try NativeArchive.encode(d);XCTAssertEqual(try NativeArchive.decode(encoded),d);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
    let action=RecordedAction(name:"Owned texture",steps:[.init(name:"Texture",operation:.filter(.active,f))]);let bytes=try ActionLibraryFile(actions:[action]).encoded();XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,54)
    var wrong=try JSONSerialization.jsonObject(with:bytes)as! [String:Any];wrong["version"]=53;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:wrong)))
    let old=RecordedAction(name:"Old",steps:[.init(name:"Gallery",operation:.filter(.active,ArtisticGalleryWorkflowTests().filter()))]);XCTAssertEqual(try ActionLibraryFile.decode(ActionLibraryFile(actions:[old]).encoded()).version,8)
    let draft=FilterDraft(id:id,filter:f,filterID:try XCTUnwrap(d.layers[0].smartFilters?.filters.first?.id)),m=ArtisticGalleryWorkspace();await m.prepare(document:d,draft:draft);m.thumbnailTask?.cancel();XCTAssertEqual(m.settings,f.artistic);m.close()
  }
  @MainActor func testRealHTTPConversionAndApplyMatchNativeAtEveryDepthWithoutConversionHistory()async throws {
    let h=AutomationTests(),data=try Data(contentsOf:url()),texture=try GalleryTextureLoader.read(url())
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document);let share=try XCTUnwrap(service.shares.first?.id)
      for depth in PixelDepth.allCases {
        let d=try self.fixture(depth);document.store.session=EditorSession(document:d);let revision=service.revision(document.store)
        let response=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":GalleryTextureAPI.name,"revision":revision,"parameters":["data":data.base64EncodedString(),"name":self.url().lastPathComponent]])
        XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1,as:UTF8.self));let object=try XCTUnwrap(try JSONSerialization.jsonObject(with:response.1)as?[String:Any]),raw=try XCTUnwrap(object["texture"])
        XCTAssertEqual(try JSONDecoder().decode(GalleryTextureSource.self,from:JSONSerialization.data(withJSONObject:raw)),texture);XCTAssertEqual(object["revision"]as?String,revision)
        XCTAssertEqual(document.store.document,d);XCTAssertEqual(service.revision(document.store),revision);XCTAssertTrue(document.store.session.undoStack.isEmpty)
        let f=try self.filter();var expected=d;try Command.applyFilter(d.layers[0].id,f).apply(to:&expected)
        let result=try await h.edit(service,document,"filter.apply",["layerID":d.layers[0].id.uuidString,"filter":["kind":"filterGallery","artistic":["effects":[["filter":"texturizer","texture":raw]]]]]);XCTAssertEqual(result,200);XCTAssertEqual(document.store.document,expected)
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
      }
    }
  }
  @MainActor func testHTTPInvalidAuthenticationBusyStaleRevocationAndMachineSchemas()async throws {
    let h=AutomationTests(),raw=try Data(contentsOf:url()).base64EncodedString()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let d=try self.fixture();document.store.session=EditorSession(document:d);try service.share(document);let id=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(id)/commands"
      let valid:[String:Any]=["data":raw]
      let unauth=try await h.request(service,path:path,body:["command":GalleryTextureAPI.name,"revision":service.revision(document.store),"parameters":valid],authenticate:false);XCTAssertEqual(unauth.0.statusCode,401)
      for bad in [[:],["data":"%%%"],["data":raw+"\n"],["data":false],["data":raw,"url":"file:///not/a/resource"],["data":raw,"name":"\n"],["data":raw,"name":42]]as[[String:Any]] {
        let status=try await h.edit(service,document,GalleryTextureAPI.name,bad);XCTAssertEqual(status,400);XCTAssertEqual(document.store.document,d)
      }
      let stale=try await h.edit(service,document,GalleryTextureAPI.name,valid,revision:"stale");XCTAssertEqual(stale,409)
      service.previewBusy=true;let busy=try await h.edit(service,document,GalleryTextureAPI.name,valid);service.previewBusy=false;XCTAssertEqual(busy,429)
      document.store.beginFilter(.filterGallery);let modal=try await h.edit(service,document,GalleryTextureAPI.name,valid);document.store.cancelFilter();XCTAssertEqual(modal,409)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:GalleryTextureAPI.capabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:GalleryTextureAPI.commandSchema))
      XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,60)
      service.revoke(id);let revoked=try await h.request(service,path:path,body:["command":GalleryTextureAPI.name,"revision":service.revision(document.store),"parameters":valid]);XCTAssertEqual(revoked.0.statusCode,404);XCTAssertEqual(document.store.document,d)
    }
  }
  @MainActor func testHTTPArchiveNegotiationPreventsTextureLossAndSmartSetRetainsSnapshots()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let d=try self.fixture(smart:true),id=d.layers[0].id;document.store.session=EditorSession(document:d);try service.share(document);service.setDocumentTransfersEnabled(true)
      let f=try self.filter();let status=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"filterGallery","artistic":BrushAPI.json(f.artistic!)] ]);XCTAssertEqual(status,200)
      let changed=document.store.document,share=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(share)/file.photato"
      for version in ["36","87"] {let old=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":version]);XCTAssertEqual(old.0.statusCode,422)}
      let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"88"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=try XCTUnwrap(changed.layers[0].smartFilters);stack.filters[0].filter.artistic?.effects[0].values["invert"]=1;var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edit=try await h.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":payload]);XCTAssertEqual(edit,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      XCTAssertThrowsError(try DocumentIO.encode(changed,format:.psd));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"filterGallery\"}]"))
    }
  }
  @MainActor func testRealHTTPLargeEmbeddedTextureExceedsFormerCommandLimitAndRemainsUndoable()async throws {
    var bytes=Data(repeating:128,count:GalleryTextureSource.maximumPixels);bytes[0]=0;bytes[1]=255;bytes[4095]=255
    let texture=try GalleryTextureSource(name:"Owned maximum texture",width:4096,height:2048,samples:bytes),h=AutomationTests()
    let path="/v1/documents/"+UUID().uuidString+"/commands"
    XCTAssertGreaterThan(AutomationRequest.maximumBodyBytes(method:"POST",path:path),GalleryTextureSource.maximumBase64)
    XCTAssertGreaterThanOrEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:path),GalleryTextureAPI.maximumBase64+65536)
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let d=try self.fixture();document.store.session=EditorSession(document:d);try service.share(document)
      let payload:[String:Any]=["layerID":d.layers[0].id.uuidString,"filter":["kind":"filterGallery","artistic":["effects":[["filter":"texturizer","texture":BrushAPI.json(texture)]]]]]
      XCTAssertGreaterThan(try JSONSerialization.data(withJSONObject:payload).count,8*1024*1024)
      let status=try await h.edit(service,document,"filter.apply",payload);XCTAssertEqual(status,200);XCTAssertNotEqual(document.store.document,d)
      XCTAssertEqual(document.store.session.undoStack.count,1);let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
    }
  }
  @MainActor func testHostedTextureControlsLightDarkAndPreferenceErrorsDoNotDisableEditing()async throws {
    let s=EditorStore(document:try fixture(),actions:ActionLibrary());defer{stop(s)}
    let root=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"].map{URL(fileURLWithPath:$0)}
    for name in [NSAppearance.Name.aqua,.darkAqua] {
      s.cancelFilter();let m=try await model(s);await m.loadTexture(url())?.value;await m.task?.value
      let view=NSHostingView(rootView:ArtisticGallerySheet(store:s,model:m));view.appearance=NSAppearance(named:name)
      let window=NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:660),styleMask:[.borderless],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=view;view.frame=NSRect(x:0,y:0,width:960,height:660);view.layoutSubtreeIfNeeded();view.displayIfNeeded()
      XCTAssertTrue(m.ready,m.error ?? "Not ready");XCTAssertGreaterThan(view.fittingSize.width,900)
      if let root,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {view.cacheDisplay(in:view.bounds,to:bitmap);if let data=bitmap.representation(using:.png,properties:[:]){try data.write(to:root.appendingPathComponent("gallery-texture-"+name.rawValue+".png"))}}
      window.contentView=nil;window.close()
    }
  }
}
