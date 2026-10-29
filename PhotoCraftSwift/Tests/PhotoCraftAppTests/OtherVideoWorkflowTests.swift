import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class OtherVideoWorkflowTests:XCTestCase {
  let kinds=RasterFilter.Kind.allCases.filter(\.isOtherVideo)
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try BlurGalleryWorkflowTests().fixture(depth,smart:smart)}
  func filter(_ kind:RasterFilter.Kind)->RasterFilter {
    var f=RasterFilter(kind)
    if kind == .customFilter {f.otherVideo?.kernel[12]=2;f.otherVideo?.offset = -20}
    if kind == .offset {f.otherVideo?.horizontal=3;f.otherVideo?.vertical = -2}
    if kind == .maximum || kind == .minimum {f.otherVideo?.radius=2.5;f.otherVideo?.preserve = .roundness}
    if kind == .hsbHsl {f.otherVideo?.outputMode = .hsl}
    if kind == .deInterlace {f.otherVideo?.eliminate = .even;f.otherVideo?.createBy = .duplication}
    return f
  }
  func testAllSevenDepthsSelectionAlphaHistoryAndRasterPSD()throws {
    XCTAssertEqual(kinds.count,7)
    for kind in kinds {for depth in PixelDepth.allCases {
      let d=try fixture(depth),f=filter(kind),id=d.layers[0].id;var session=EditorSession(document:d)
      try session.execute(.applyFilter(id,f));let edited=session.document;XCTAssertNotEqual(edited,d,"\(kind) \(depth)")
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(edited)),edited)
      let reopened=try PSDCodec.read(PSDCodec.writeRasterLayers(edited));XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth:depth),try Renderer.composite(edited).rgbaData(depth:depth))
      try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,edited)
      var selected=d;selected.selection = .init(x:12,y:10,width:10,height:8);selected.layers[0].protection=[.transparency]
      try Command.applyFilter(id,f).apply(to:&selected)
      guard case .raster(let before)=d.layers[0].content,case .raster(let after)=selected.layers[0].content else {return XCTFail()}
      for y in 0..<32 {for x in 0..<40 {
        XCTAssertEqual(after.pixel(x:x,y:y).a,before.pixel(x:x,y:y).a)
        if !(12..<22).contains(x) || !(10..<18).contains(y) {XCTAssertEqual(after.pixel(x:x,y:y),before.pixel(x:x,y:y))}
      }}
    }}
  }
  func testSmartSourceNative43Actions16AndExplicitInterchangeLimits()throws {
    for kind in kinds {
      var d=try fixture(smart:true);let original=d,id=d.layers[0].id,f=filter(kind)
      try Command.applyFilter(id,f).apply(to:&d);let image=try Renderer.composite(d)
      XCTAssertEqual(d.layers[0].content,original.layers[0].content);XCTAssertEqual(d.layers[0].smartObject,original.layers[0].smartObject);XCTAssertEqual(d.minimumArchiveVersion,43)
      for bytes in [try NativeArchive.encode(d),try NativeArchive.encodeChunked(d)] {let decoded=try NativeArchive.decode(bytes);XCTAssertEqual(decoded,d);XCTAssertEqual(try Renderer.composite(decoded),image)}
      var old=try PropertyListSerialization.propertyList(from:NativeArchive.encode(d),format:nil) as! [String:Any];old["version"]=42;XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:old,format:.binary,options:0)))
      XCTAssertThrowsError(try DocumentIO.encode(d,format:.psd));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"\(kind.rawValue)\"}]"))
      for operation in [ActionOperation.filter(.active,f),.filters(.active,d.layers[0].smartFilters)] {
        let action=RecordedAction(name:kind.title,steps:[.init(name:kind.title,operation:operation)]),bytes=try ActionLibraryFile(actions:[action]).encoded(),loaded=try ActionLibraryFile.decode(bytes)
        XCTAssertEqual(loaded.version,16);var replay=original;try XCTUnwrap(loaded.actions[0].steps[0].operation.command(in:replay)).apply(to:&replay);XCTAssertEqual(try Renderer.composite(replay),image)
        var old=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];old["version"]=15;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:old)))
      }
      try Command.smartFilterMask(id,.maskFill(id,0)).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(original))
    }
  }
  @MainActor func testNativePreviewLocalHistoryCancelCommitAndReedit()async throws {
    for kind in kinds {
      let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary());defer{store.renderTask?.cancel();store.cancelFilter()}
      store.beginFilter(kind)
      if kind == .ntscColors {
        await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertNil(store.filterDraft);XCTAssertEqual(store.session.undoStack.count,1)
        store.beginSmartFilter(d.layers[0].id,filterID:try XCTUnwrap(store.document.layers[0].smartFilters?.filters.first?.id))
      }
      let source=store.document,draft=try XCTUnwrap(store.filterDraft),model=OtherVideoWorkspace();store.otherVideoWorkspace=model
      await model.prepare(document:source,draft:draft);XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(store.document,source)
      model.change(filter(kind));let changed=model.filter
      if kind != .ntscColors {model.undo();XCTAssertEqual(model.filter,draft.filter);model.redo();XCTAssertEqual(model.filter,changed)}
      await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
      store.filterDraft?.filter=model.filter;model.close();store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error)
      let edited=store.document;await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,edited)
      store.beginSmartFilter(d.layers[0].id,filterID:try XCTUnwrap(edited.layers[0].smartFilters?.filters.first?.id));XCTAssertEqual(store.filterDraft?.filter,changed);store.cancelFilter();XCTAssertEqual(store.document,edited)
    }
  }
  @MainActor func testPresetLoadingInvalidRecoveryGestureAndCancelledPreview()async throws {
    let d=try fixture(),store=EditorStore(document:d),model=OtherVideoWorkspace();defer{store.renderTask?.cancel();store.cancelFilter()}
    store.beginFilter(.customFilter);await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));let initial=model.filter
    let preset=try filter(.customFilter).otherVideo!.encodedCustomPreset();model.loadPreset(preset);XCTAssertEqual(model.filter,filter(.customFilter));XCTAssertEqual(model.undoStates.count,1)
    model.loadPreset(Data("invalid".utf8));XCTAssertNotNil(model.error);XCTAssertEqual(model.filter,filter(.customFilter))
    model.change(model.filter);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
    model.undo();XCTAssertEqual(model.filter,initial);model.beginGesture();model.update{$0.otherVideo?.scale=2};model.update{$0.otherVideo?.scale=3};model.endGesture();XCTAssertEqual(model.undoStates.count,1)
    let pending=model.task;model.close();store.cancelFilter();await pending?.value;XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPDesktopEquivalenceSmartReeditArchiveAndGuards()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      for kind in self.kinds {
        let d=try self.fixture(),id=d.layers[0].id,f=self.filter(kind);document.store.session=EditorSession(document:d);var expected=d;try Command.applyFilter(id,f).apply(to:&expected)
        let status=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":f.apiState]);XCTAssertEqual(status,200,kind.rawValue);XCTAssertEqual(document.store.document,expected)
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
      }
      let d=try self.fixture(smart:true),id=d.layers[0].id;document.store.session=EditorSession(document:d)
      let params:[String:Any]=["layerID":id.uuidString,"filter":self.filter(.maximum).apiState]
      let status=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(status,200)
      let changed=document.store.document,share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
      let old=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"42"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"43"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=changed.layers[0].smartFilters!;stack.filters[0].filter.otherVideo?.radius=3
      var value=stack.apiState;value.removeValue(forKey:"hasMask");value.removeValue(forKey:"maskTransform")
      let reedit=try await h.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":value]);XCTAssertEqual(reedit,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      let stale=try await h.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.select(id);document.store.beginFilter(.customFilter);XCTAssertNotNil(document.store.filterDraft);let busy=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let before=document.store.document
      for bad in [["kind":"maximum","otherVideo":["radius":501]],["kind":"deInterlace","otherVideo":["eliminate":"both"]],["kind":"offset","otherVideo":["kernel":[1]]]] as [[String:Any]] {
        let code=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":bad]);XCTAssertEqual(code,400);XCTAssertEqual(document.store.document,before)
      }
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
      let caps=try XCTUnwrap(RasterFilter.apiCapabilities["otherVideo"] as? [String:Any]);XCTAssertEqual(Set(caps["kinds"] as? [String] ?? []),Set(self.kinds.map(\.rawValue)))
    }
  }
  @MainActor func testFactoryMenuAvailabilityAndHostedDialogs()async throws {
    for kind in kinds {
      let group=[RasterFilter.Kind.deInterlace,.ntscColors].contains(kind) ? "Video":"Other",suffix=[RasterFilter.Kind.hsbHsl,.ntscColors].contains(kind) ? "":"…"
      XCTAssertEqual(AppDelegate.filterMenus["Filter > \(group) > \(kind.title)\(suffix)"],kind)
      let d=try fixture(),store=EditorStore(document:d);defer{store.renderTask?.cancel();store.cancelFilter()};XCTAssertTrue(store.canBeginFilterKind(kind))
      let model=OtherVideoWorkspace();store.filterDraft = .init(id:d.layers[0].id,filter:filter(kind));await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Not ready")
      let view=NSHostingView(rootView:OtherVideoSheet(store:store,model:model).background(Color(nsColor:.windowBackgroundColor)))
      let window=NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.borderless],backing:.buffered,defer:false);view.appearance=NSAppearance(named:.aqua);window.contentView=view;view.frame=NSRect(x:0,y:0,width:840,height:620);view.layoutSubtreeIfNeeded();view.displayIfNeeded()
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) {let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/other-video-offscreen");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try png.write(to:folder.appendingPathComponent(kind.rawValue+"-"+UUID().uuidString+".png"))}}
      window.contentView=nil;model.close();store.cancelFilter();var locked=d;locked.layers[0].locked=true;store.session=EditorSession(document:locked);XCTAssertFalse(store.canBeginFilterKind(kind))
    }
  }
}
