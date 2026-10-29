import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ClassicToneWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try BlurGalleryWorkflowTests().fixture(depth,smart:smart)}
  func settings(_ kind:ClassicToneSettings.Kind)->ClassicToneSettings {
    var s=ClassicToneSettings(kind)
    if kind == .matchColor{s.neutralize=true;s.luminance=125}
    if kind == .replaceColor{s.fuzziness=200;s.hue=100;s.samples=[.init(color:Pixel(0.5,0.5,0.5))]}
    return s
  }
  func testTransactionsDepthsPersistenceAndHDRFlattenUndo()throws {
    for depth in PixelDepth.allCases {for kind in ClassicToneSettings.Kind.allCases {
      let d=try fixture(depth),request=ClassicToneRequest(settings(kind),layerID:kind == .hdrToning ? nil:d.layers[0].id);var session=EditorSession(document:d)
      try session.execute(ClassicToneInput.command(request,in:d));let edited=session.document;XCTAssertNotEqual(edited,d,"\(kind)")
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(edited)),edited)
      if kind == .hdrToning{XCTAssertEqual(edited.layers.count,1);XCTAssertEqual(edited.layers[0].name,"Background");XCTAssertNil(edited.selection);XCTAssertTrue(edited.layers[0].protection.contains(.transparency))}
      try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,edited)
    }}
    for method in HDRMergeSettings.Method.allCases {var s=ClassicToneSettings(.hdrToning);s.method=method;var d=try fixture();let cmd=try ClassicToneInput.command(.init(s),in:d);try cmd.apply(to:&d);XCTAssertNoThrow(try d.validate());XCTAssertThrowsError(try cmd.apply(to:&d))}
  }
  func testSmartNative45Actions18AndExplicitLimits()throws {
    var d=try fixture(smart:true);let original=d,id=d.layers[0].id
    try Command.toneAdjustment(.init(settings(.shadowsHighlights),layerID:id)).apply(to:&d)
    XCTAssertEqual(d.layers[0].content,original.layers[0].content);XCTAssertEqual(d.layers[0].smartObject,original.layers[0].smartObject);XCTAssertEqual(d.minimumArchiveVersion,45)
    for bytes in [try NativeArchive.encode(d),try NativeArchive.encodeChunked(d)]{XCTAssertEqual(try NativeArchive.decode(bytes),d)}
    XCTAssertThrowsError(try DocumentIO.encode(d,format:.psd))
    for kind in ClassicToneSettings.Kind.allCases where kind != .hdrToning {
      let source=try fixture(),s=settings(kind),operation=ActionOperation.toneAdjustment(.active,s),action=RecordedAction(name:kind.title,steps:[.init(name:kind.title,operation:operation)])
      let bytes=try ActionLibraryFile(actions:[action]).encoded(),loaded=try ActionLibraryFile.decode(bytes);XCTAssertEqual(loaded.version,18)
      var a=source,b=source;try Command.toneAdjustment(.init(s,layerID:source.layers[0].id)).apply(to:&a);try XCTUnwrap(loaded.actions[0].steps[0].operation.command(in:b)).apply(to:&b);XCTAssertEqual(a,b)
    }
  }
  @MainActor func testPreviewHistoryPresetsSamplingCancelAndCommit()async throws {
    for kind in ClassicToneSettings.Kind.allCases where kind != .shadowsHighlights {
      var d=try fixture();if kind == .equalize{d.selection = .init(x:3,y:3,width:15,height:12)}
      let store=EditorStore(document:d);defer{store.renderTask?.cancel();store.cancelClassicTone()};store.beginClassicTone(kind)
      let model=try XCTUnwrap(store.classicToneWorkspace);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "No preview");XCTAssertEqual(store.document,d)
      model.update{$0.settings=self.settings(kind)};if kind == .replaceColor{model.sample(.init(0.4,0.6));XCTAssertEqual(model.request.settings.samples[0].point,.init(0.4,0.6))}
      let saved=model.request;let preset=try model.presetData();model.update{$0.settings=self.settings(kind)};try model.loadPreset(preset);XCTAssertEqual(model.request,saved)
      if !model.undoStates.isEmpty{model.undo();model.redo();XCTAssertEqual(model.request,saved)}
      await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "No preview");store.commitClassicTone();await model.commitTask?.value;XCTAssertNil(model.error);XCTAssertNil(store.classicToneWorkspace)
      let edited=store.document;await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,edited)
    }
    let d=try fixture(),store=EditorStore(document:d);store.beginClassicTone(.matchColor);let model=try XCTUnwrap(store.classicToneWorkspace);model.update{$0.settings.neutralize=true};let pending=model.task;store.cancelClassicTone();await pending?.value;XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty);store.renderTask?.cancel()
  }
  @MainActor func testSourceStatisticsAndSmartReeditPreview()async throws {
    let source=try fixture(),model=ClassicToneWorkspace(document:source,request:.init(.init(.matchColor)),sources:[source]);defer{model.close()}
    model.sourceDocumentID=source.id;model.sourceLayerID=source.layers[0].id;model.calculateSource();await model.sourceTask?.value;XCTAssertEqual(model.request.settings.sourceStatistics,try ClassicToneInput.statistics(in:source,layerID:source.layers[0].id))
    model.sourceDocumentID=nil;model.calculateSource();XCTAssertNil(model.request.settings.sourceStatistics)
    let d=try fixture(smart:true),store=EditorStore(document:d);defer{store.renderTask?.cancel();store.cancelFilter()};store.beginClassicTone(.shadowsHighlights)
    let draft=try XCTUnwrap(store.filterDraft),shadow=ClassicToneWorkspace(document:d,request:.init(.init(.shadowsHighlights),layerID:draft.id),filterDraft:draft);store.shadowWorkspace=shadow;shadow.refresh();await shadow.task?.value;XCTAssertTrue(shadow.ready,shadow.error ?? "No preview")
    shadow.update{$0.settings.shadowAmount=80};await shadow.task?.value;store.filterDraft?.filter.tone=shadow.request.settings;store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error)
    let f=try XCTUnwrap(store.document.layers[0].smartFilters?.filters.first);store.beginSmartFilter(draft.id,filterID:f.id);XCTAssertEqual(store.filterDraft?.filter.tone?.shadowAmount,80)
  }
  @MainActor func testHTTPParityStatisticsSchemasArchiveAndGuards()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      for kind in ClassicToneSettings.Kind.allCases {
        let d=try self.fixture(),s=self.settings(kind);document.store.session=EditorSession(document:d);document.store.select(d.layers[0].id)
        var expected=d;try ClassicToneInput.command(.init(s),in:d).apply(to:&expected)
        let status=try await h.edit(service,document,"tone.apply",["kind":kind.rawValue,"settings":s.apiParameters]);XCTAssertEqual(status,200,kind.rawValue)
        if kind == .hdrToning {XCTAssertEqual(try Renderer.composite(document.store.document),try Renderer.composite(expected));XCTAssertEqual(document.store.document.layers.count,1)}else{XCTAssertEqual(document.store.document,expected)}
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
      }
      let d=document.store.document
      let shareID=try XCTUnwrap(service.shares.first?.id)
      let statistics=try await h.request(service,path:"/v1/documents/\(shareID)/commands",body:["command":"tone.statistics","revision":service.revision(document.store),"parameters":["useSelection":false]])
      XCTAssertEqual(statistics.0.statusCode,200);XCTAssertEqual(document.store.document,d)
      let response=try XCTUnwrap(try JSONSerialization.jsonObject(with:statistics.1) as? [String:Any])
      XCTAssertEqual(response["sourceDepth"] as? String,d.depth.rawValue)
      let values=try XCTUnwrap(response["statistics"] as? [String:Any]);XCTAssertEqual(try JSONDecoder().decode(ToneColorStatistics.self,from:JSONSerialization.data(withJSONObject:values)),try ClassicToneInput.statistics(in:d))
      let schema=try XCTUnwrap(ClassicToneAPI.capabilities["statisticsResultSchema"] as? [String:Any]),fields=try XCTUnwrap(schema["properties"] as? [String:Any]),depth=try XCTUnwrap(fields["sourceDepth"] as? [String:Any])
      XCTAssertEqual(depth["enum"] as? [String],PixelDepth.allCases.map(\.rawValue));XCTAssertEqual(depth["type"] as? String,"string")
      let stale=try await h.edit(service,document,"tone.apply",["kind":"equalize"],revision:"old");XCTAssertEqual(stale,409)
      document.store.beginClassicTone(.matchColor);XCTAssertNotNil(document.store.classicToneWorkspace);let busy=try await h.edit(service,document,"tone.statistics");XCTAssertEqual(busy,409);document.store.cancelClassicTone()
      for params in [["kind":"equalize","settings":["shadowAmount":1]],["kind":"matchColor","settings":["luminance":0]],["kind":"hdrToning","layerID":d.layers[0].id.uuidString]] as [[String:Any]] {let status=try await h.edit(service,document,"tone.apply",params);XCTAssertEqual(status,400);XCTAssertEqual(document.store.document,d)}
      let smart=try self.fixture(smart:true);document.store.session=EditorSession(document:smart)
      let apply=try await h.edit(service,document,"tone.apply",["kind":"shadowsHighlights"]);XCTAssertEqual(apply,200)
      let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
      let old=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"44"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"45"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),document.store.document)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ClassicToneAPI.capabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
    }
  }
  @MainActor func testMenuBindingsAndHostedPreviews()async throws {
    for kind in ClassicToneSettings.Kind.allCases {
      XCTAssertEqual(AppDelegate.classicToneMenus["Image > Adjustments > \(kind.title)"+(kind == .equalize ? "":"…")],kind)
      let d=try fixture(),store=EditorStore(document:d),model=ClassicToneWorkspace(document:d,request:.init(settings(kind)));defer{store.renderTask?.cancel();model.close()};XCTAssertTrue(store.canBeginClassicTone(kind));model.refresh();await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "No preview")
      let view=NSHostingView(rootView:ClassicToneSheet(store:store,model:model).background(Color(nsColor:.windowBackgroundColor))),window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:680),styleMask:[.borderless],backing:.buffered,defer:false)
      window.contentView=view;view.frame=NSRect(x:0,y:0,width:900,height:680);view.layoutSubtreeIfNeeded();view.displayIfNeeded()
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]){let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/classic-tone-offscreen");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try png.write(to:folder.appendingPathComponent(kind.rawValue+"-"+UUID().uuidString+".png"))}}
      window.contentView=nil
    }
  }
}
