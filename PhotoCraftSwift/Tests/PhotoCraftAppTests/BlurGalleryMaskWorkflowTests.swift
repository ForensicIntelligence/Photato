import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class GalleryMaskGate:@unchecked Sendable {
  private let condition=NSCondition();private var open=false
  func wait(){condition.lock();while !open{condition.wait()};condition.unlock()}
  func release(){condition.lock();open=true;condition.broadcast();condition.unlock()}
}

final class BlurGalleryMaskWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try BlurGalleryWorkflowTests().fixture(depth,smart:smart)}
  @MainActor func stop(_ store:EditorStore){store.renderTask?.cancel();store.geometryTask?.cancel();store.blurGalleryWorkspace?.close()}
  @MainActor func testNativePreviewOutputOptionCommitCancelAndHistory()async throws {
    let d=try fixture(),store=EditorStore(document:d,actions:ActionLibrary());defer{stop(store)}
    store.beginFilter(.blurGallery);let model=BlurGalleryWorkspace();await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft))
    XCTAssertTrue(model.ready,model.error ?? "");XCTAssertTrue(model.canSaveMask);XCTAssertFalse(model.saveMaskToChannels)
    model.saveMaskToChannels=true;var settings=model.settings;settings.field[0].blur=5;model.change(settings);await model.task?.value
    XCTAssertTrue(model.ready);XCTAssertNotNil(model.maskImage);XCTAssertNil(model.maskError);XCTAssertEqual(store.document,d)
    model.undo();await model.task?.value;XCTAssertEqual(model.settings.field[0].blur,15);XCTAssertTrue(model.saveMaskToChannels)
    model.redo();await model.task?.value;XCTAssertEqual(model.settings,settings)
    let view=NSHostingView(rootView:BlurGallerySheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:900,height:680);view.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(view.fittingSize.width,900)
    store.filterDraft?.filter.gallery=model.settings;store.filterDraft?.saveMaskToChannels=model.saveMaskToChannels;model.close();store.commitFilter();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.document.alphaChannels?.last?.name,"Blur Mask");XCTAssertEqual(store.session.undoStack.count,1)
    let committed=store.document;await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,committed)
    store.beginFilter(.blurGallery);let cancel=BlurGalleryWorkspace();await cancel.prepare(document:committed,draft:try XCTUnwrap(store.filterDraft));cancel.saveMaskToChannels=true;cancel.close();store.cancelFilter();XCTAssertEqual(store.document,committed)
  }
  func testSmartReeditPrefixNativePersistenceAndPortableActions53AllDepths()throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth,smart:true);let id=d.layers[0].id;var filter=RasterFilter(.blurGallery);filter.gallery?.enabled=[.iris]
      try Command.applyFilter(id,filter).apply(to:&d);let before=d,filterID=try XCTUnwrap(d.layers[0].smartFilters?.filters.first?.id)
      var settings=BlurGallerySettings();settings.enabled=[.path]
      let edit=BlurGalleryMaskEdit(layerID:id,settings:settings,filterID:filterID,opacity:0.7,blendMode:.multiply),command=Command.blurGalleryMask(edit)
      let operation=ActionOperation(recording:command,in:d);XCTAssertNil(operation.unsupportedReason)
      try command.apply(to:&d);XCTAssertEqual(d.layers[0].smartFilters?.filters.count,1);XCTAssertEqual(d.layers[0].smartFilters?.filters[0].filter.gallery,settings)
      XCTAssertEqual(d.layers[0].content,before.layers[0].content);XCTAssertEqual(d.layers[0].smartObject,before.layers[0].smartObject)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      let action=RecordedAction(name:"Blur with mask",steps:[.init(name:"Blur Gallery",operation:operation)]),file=ActionLibraryFile(actions:[action])
      let bytes=try file.encoded();XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,53)
      var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes)as?[String:Any]);raw["version"]=52;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:raw)))
      var replay=before;let replayCommand=try XCTUnwrap(operation.command(in:replay));try replayCommand.apply(to:&replay)
      XCTAssertEqual(replay.layers,d.layers);XCTAssertEqual(replay.alphaChannels?.last?.pixels,d.alphaChannels?.last?.pixels)
      XCTAssertNotEqual(replay.alphaChannels?.last?.id,d.alphaChannels?.last?.id)
      let ordinary=ActionLibraryFile(actions:[.init(name:"Ordinary",steps:[.init(name:"Blur",operation:.filter(.init(id,in:before),filter))])]);XCTAssertLessThan(ordinary.requiredVersion,53)
    }
  }
  @MainActor func testHTTPNativeEquivalenceAllDepthsAndSmartReedit()async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document)
      for depth in PixelDepth.allCases {for smart in [false,true] {
        let d=try self.fixture(depth,smart:smart);document.store.session=EditorSession(document:d)
        let id=d.layers[0].id;var settings=BlurGallerySettings();settings.enabled=[.tiltShift]
        var expected=d;let edit=BlurGalleryMaskEdit(layerID:id,settings:settings);try Command.blurGalleryMask(edit).apply(to:&expected)
        let gallery=try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings))
        let code=try await helper.edit(service,document,BlurGalleryOutputAPI.name,["layerID":id.uuidString,"gallery":gallery,"saveMaskToChannels":true]);XCTAssertEqual(code,200)
        let actual=document.store.document;expected.alphaChannels?[0].id=try XCTUnwrap(actual.alphaChannels?.first?.id)
        if smart {expected.layers[0].smartFilters?.filters[0].id=try XCTUnwrap(actual.layers[0].smartFilters?.filters.first?.id)}
        XCTAssertEqual(actual,expected);XCTAssertEqual(document.store.session.undoStack.count,1)
        if smart {
          let filterID=try XCTUnwrap(actual.layers[0].smartFilters?.filters.first?.id)
          let reedit=try await helper.edit(service,document,BlurGalleryOutputAPI.name,["layerID":id.uuidString,"filterID":filterID.uuidString,"gallery":["enabled":["field"]],"saveMaskToChannels":true]);XCTAssertEqual(reedit,200)
          XCTAssertEqual(document.store.document.layers[0].smartFilters?.filters.count,1);XCTAssertEqual(document.store.document.alphaChannels?.count,2)
          XCTAssertEqual(document.store.document.alphaChannels?.last?.name,"Blur Mask 2")
          let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,actual)
        }
      }}
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(try XCTUnwrap(service.shares.first),document:document)))
    }
  }
  @MainActor func testHTTPValidationBusyStaleChannelLimitAndSchemas()async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document);let d=try self.fixture();document.store.session=EditorSession(document:d)
      let good:[String:Any]=["layerID":d.layers[0].id.uuidString,"gallery":[:],"saveMaskToChannels":true]
      var bad=good
      let invalid:[(String,Any)]=[("saveMaskToChannels",1),("gallery",["unknown":true]),("gallery",["field":[["blur":-1]]]),("layerID","invalid"),("unexpected",true)]
      for pair in invalid {
        bad=good;bad[pair.0]=pair.1;let code=try await helper.edit(service,document,BlurGalleryOutputAPI.name,bad);XCTAssertEqual(code,400);XCTAssertEqual(document.store.document,d)
      }
      let stale=try await helper.edit(service,document,BlurGalleryOutputAPI.name,good,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.blurGallery);let busy=try await helper.edit(service,document,BlurGalleryOutputAPI.name,good);XCTAssertEqual(busy,409);document.store.cancelFilter()
      var full=d;let plane=try Surface(width:d.width,height:d.height,fill:.black);full.alphaChannels=(0..<CraftDocument.maximumAlphaChannels).map{AlphaChannel(name:"A \($0)",pixels:plane)};document.store.session=EditorSession(document:full)
      let code=try await helper.edit(service,document,BlurGalleryOutputAPI.name,good);XCTAssertEqual(code,422);XCTAssertEqual(document.store.document,full)
      let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name==BlurGalleryOutputAPI.name});XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:definition.schema));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:BlurGallerySettings.apiCapabilities))
      XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,60)
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"blurGallery\"}]"))
    }
  }
  @MainActor func testPreparedOutputRevocationAndCancellationPublishNeitherPart()async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      for cancel in [false,true] {
        let d=try self.fixture();document.store.session=EditorSession(document:d);try service.share(document)
        let share=try XCTUnwrap(service.shares.first?.id),revision=service.revision(document.store),gate=GalleryMaskGate();defer{gate.release()}
        let edit=BlurGalleryMaskEdit(layerID:d.layers[0].id,settings:.init())
        let task=Task {try await service.executePreparedOperation(document:document,shareID:share,revision:revision){_ in gate.wait();return .blurGalleryMask(edit)}}
        for _ in 0..<1000 where !document.store.geometryBusy {try await Task.sleep(for:.milliseconds(1))}
        XCTAssertTrue(document.store.geometryBusy)
        if cancel {task.cancel()}else{service.revoke(share)}
        gate.release();do{try await task.value;XCTFail("Expected revoked/cancelled transaction")}catch{}
        XCTAssertEqual(document.store.document,d);XCTAssertTrue(document.store.session.undoStack.isEmpty)
        service.revoke(share)
      }
    }
  }
}
