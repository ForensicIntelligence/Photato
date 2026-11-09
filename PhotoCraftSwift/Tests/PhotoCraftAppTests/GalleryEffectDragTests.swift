import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

private final class GalleryTransferGate: @unchecked Sendable {
  private let condition=NSCondition()
  private var started=false, released=false
  func wait() { condition.lock();started=true;condition.broadcast();while !released { condition.wait() };condition.unlock() }
  func isStarted() -> Bool { condition.lock();defer{condition.unlock()};return started }
  func release() { condition.lock();released=true;condition.broadcast();condition.unlock() }
}
private struct GalleryTransferCompletion: @unchecked Sendable {
  let body: (Data?, Error?) -> Void
}

final class GalleryEffectDragTests: XCTestCase {
  func settings() -> ArtisticGallerySettings {
    var a=GalleryEffect(.cutout),b=GalleryEffect(.glowingEdges),c=GalleryEffect(.cutout)
    a.values["numberOfLevels"]=3;c.values["numberOfLevels"]=7;c.visible=false
    a.foreground=Pixel(0.125,0.25,0.5,0.75);b.background=Pixel(0.75,0.5,0.25,1);c.glowColor=Pixel(0.2,0.8,0.4)
    var value=ArtisticGallerySettings();value.effects=[a,b,c];return value
  }
  @MainActor func prepared(_ depth:PixelDepth = .u8,smart:Bool=false,existing:Bool=false) async throws -> (EditorStore,ArtisticGalleryWorkspace) {
    var d=try ArtisticGalleryWorkflowTests().fixture(depth,smart:smart)
    var f=RasterFilter(.filterGallery);f.artistic=settings()
    if existing { try Command.applyFilter(d.layers[0].id,f).apply(to:&d) }
    let s=EditorStore(document:d,actions:ActionLibrary())
    if existing { s.beginSmartFilter(d.layers[0].id,filterID:try XCTUnwrap(d.layers[0].smartFilters?.filters.first?.id)) }
    else { s.beginFilter(.filterGallery);s.filterDraft?.filter=f }
    let m=ArtisticGalleryWorkspace();s.artisticGalleryWorkspace=m
    await m.prepare(document:d,draft:try XCTUnwrap(s.filterDraft))
    XCTAssertTrue(m.ready,m.error ?? "Preview unavailable")
    return(s,m)
  }
  @MainActor func stop(_ s:EditorStore,_ m:ArtisticGalleryWorkspace) { m.close();s.cancelFilter();s.renderTask?.cancel();s.geometryTask?.cancel() }

  @MainActor func testAllSourceDestinationOrdersPreserveIndependentDuplicateAndHiddenEffects() async throws {
    let(s,m)=try await prepared();defer{stop(s,m)};let base=m.settings,document=s.document
    for source in base.effects.indices { for target in base.effects.indices {
      m.change(base);let before=m.undoStates.count
      let payload=try XCTUnwrap(m.beginEffectDrag(at:source))
      let moved=m.receiveEffectDrop(payload,at:target)
      if source==target { XCTAssertFalse(moved);XCTAssertEqual(m.undoStates.count,before);continue }
      var expected=base;let item=expected.effects.remove(at:source);expected.effects.insert(item,at:target)
      XCTAssertTrue(moved);XCTAssertEqual(m.settings,expected)
      XCTAssertEqual(m.selected,target);XCTAssertEqual(m.category,item.filter.category)
      XCTAssertEqual(m.undoStates.count,before+1)
      m.undo();XCTAssertEqual(m.settings,base);m.redo();XCTAssertEqual(m.settings,expected)
    } }
    XCTAssertEqual(s.document,document);XCTAssertTrue(s.session.undoStack.isEmpty)
  }

  @MainActor func testPrivateItemProviderRoundtripMovesOnceAndArrowUsesSameOperation() async throws {
    let(s,m)=try await prepared();defer{stop(s,m)};let original=m.settings
    let provider=GalleryEffectTransfer.provider(model:m,index:0)
    XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(GalleryEffectTransfer.identifier))
    XCTAssertTrue(m.canAcceptEffectDrop(at:2))
    let received=await GalleryEffectTransfer.receive(provider,model:m,target:2)
    XCTAssertTrue(received);let dragged=m.settings
    let replay=await GalleryEffectTransfer.receive(provider,model:m,target:1)
    XCTAssertFalse(replay);XCTAssertEqual(m.settings,dragged)
    m.undo();XCTAssertEqual(m.settings,original)
    m.selected=0;m.move(1);m.move(1)
    XCTAssertEqual(m.settings,dragged)
    let invalid=GalleryEffectTransfer.provider(model:m,index:32)
    XCTAssertFalse(invalid.hasItemConformingToTypeIdentifier(GalleryEffectTransfer.identifier))
  }

  @MainActor func testMalformedForeignStaleClosedAndNoOpDropsDoNotChangeSettingsOrHistory() async throws {
    let(s,a)=try await prepared();let(t,b)=try await prepared();defer{stop(s,a);stop(t,b)}
    let original=a.settings,document=s.document,bOriginal=b.settings
    let payload=try XCTUnwrap(a.beginEffectDrag(at:0));_=b.beginEffectDrag(at:0)
    for raw in ["", "photato-gallery-effect-v1:invalid:invalid:0", payload+":1",String(repeating:"x",count:161),payload.replacingOccurrences(of:":0",with:":32")] {
      XCTAssertFalse(a.receiveEffectDrop(raw,at:1));XCTAssertEqual(a.settings,original);XCTAssertTrue(a.undoStates.isEmpty)
    }
    XCTAssertFalse(b.receiveEffectDrop(payload,at:1));XCTAssertEqual(b.settings,bOriginal)
    XCTAssertFalse(a.receiveEffectDrop(payload,at:0));XCTAssertFalse(a.receiveEffectDrop(payload,at:-1))
    let nextGesture=try XCTUnwrap(a.beginEffectDrag(at:0))
    XCTAssertNotEqual(nextGesture,payload);XCTAssertFalse(a.receiveEffectDrop(payload,at:1))
    XCTAssertEqual(a.settings,original);XCTAssertTrue(a.undoStates.isEmpty)
    var changed=original;changed.effects[0].visible.toggle();a.change(changed)
    let count=a.undoStates.count;XCTAssertFalse(a.receiveEffectDrop(payload,at:1));XCTAssertEqual(a.settings,changed);XCTAssertEqual(a.undoStates.count,count)
    a.undo();XCTAssertFalse(a.receiveEffectDrop(payload,at:1));XCTAssertEqual(a.settings,original)
    let closing=try XCTUnwrap(a.beginEffectDrag(at:0));a.close()
    XCTAssertFalse(a.receiveEffectDrop(closing,at:1));XCTAssertNil(a.beginEffectDrag(at:0))
    XCTAssertEqual(s.document,document);XCTAssertTrue(s.session.undoStack.isEmpty)
  }

  @MainActor func testDelayedProviderCannotReorderAfterSettingsChangeOrCancellation() async throws {
    for close in [false,true] {
      let(s,m)=try await prepared();defer{stop(s,m)}
      let payload=try XCTUnwrap(m.beginEffectDrag(at:0)),gate=GalleryTransferGate();defer{gate.release()}
      let provider=NSItemProvider()
      provider.registerDataRepresentation(forTypeIdentifier:GalleryEffectTransfer.identifier,visibility:.ownProcess) { completion in
        let callback=GalleryTransferCompletion(body:completion)
        DispatchQueue.global().async { gate.wait();callback.body(Data(payload.utf8),nil) }
        return nil
      }
      let task=Task { await GalleryEffectTransfer.receive(provider,model:m,target:2) }
      let deadline=Date().addingTimeInterval(10)
      while !gate.isStarted() && Date()<deadline { await Task.yield() }
      XCTAssertTrue(gate.isStarted())
      if close { m.close();s.cancelFilter() } else { m.update{$0.visible.toggle()} }
      let before=m.settings,history=m.undoStates.count,document=s.document
      gate.release();let received=await task.value
      XCTAssertFalse(received);XCTAssertEqual(m.settings,before);XCTAssertEqual(m.undoStates.count,history)
      XCTAssertEqual(s.document,document);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }

  @MainActor func testNativePreviewCancelCommitUndoAndPortableRecordingKeepTheOrder() async throws {
    let(s,m)=try await prepared();defer{stop(s,m)};let source=s.document
    let provider=GalleryEffectTransfer.provider(model:m,index:0)
    let received=await GalleryEffectTransfer.receive(provider,model:m,target:2);XCTAssertTrue(received)
    await m.task?.value;XCTAssertEqual(s.document,source);XCTAssertTrue(s.session.undoStack.isEmpty)
    let ordered=m.settings
    m.close();s.cancelFilter();XCTAssertEqual(s.document,source)
    s.beginFilter(.filterGallery);s.filterDraft?.filter.artistic=ordered
    try s.session.startActionRecording(name:"Reordered Gallery")
    var expected=source,f=RasterFilter(.filterGallery);f.artistic=ordered
    try Command.applyFilter(source.layers[0].id,f).apply(to:&expected)
    s.commitFilter();await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.session.undoStack.count,1)
    let action=try XCTUnwrap(s.session.actionRecording?.snapshot)
    let library=try ActionLibraryFile.decode(ActionLibraryFile(actions:[action]).encoded())
    XCTAssertEqual(library.version,8)
    var replay=source;try library.actions[0].apply(to:&replay);XCTAssertEqual(replay,expected)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(expected)),expected)
    await s.undo();XCTAssertEqual(s.document,source);await s.redo();XCTAssertEqual(s.document,expected)
  }

  @MainActor func testHTTPOrderedArrayMatchesNativeRasterAndExistingSmartFilterAtEveryDepth() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) { service,doc in
      try service.share(doc)
      for depth in PixelDepth.allCases { for smart in [false,true] {
        let(s,m)=try await prepared(depth,smart:smart,existing:smart);defer{stop(s,m)}
        let source=s.document,provider=GalleryEffectTransfer.provider(model:m,index:0)
        let received=await GalleryEffectTransfer.receive(provider,model:m,target:2);XCTAssertTrue(received)
        let ordered=m.settings;s.filterDraft?.filter.artistic=ordered;m.close();s.commitFilter();await s.geometryTask?.value
        XCTAssertNil(s.error);let expected=s.document
        doc.store.session=EditorSession(document:source);doc.store.selectedLayerIDs=[];doc.store.componentTarget = .composite
        let code:Int
        if smart {
          var stack=try XCTUnwrap(source.layers[0].smartFilters);stack.filters[0].filter.artistic=ordered
          var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
          code=try await h.edit(service,doc,"smartFilter.set",["layerID":source.layers[0].id.uuidString,"stack":payload])
        } else {
          var filter=RasterFilter(.filterGallery);filter.artistic=ordered
          code=try await h.edit(service,doc,"filter.apply",["layerID":source.layers[0].id.uuidString,"filter":filter.apiState])
        }
        XCTAssertEqual(code,200);XCTAssertEqual(doc.store.document,expected)
        XCTAssertEqual(try NativeArchive.encodeChunked(doc.store.document),try NativeArchive.encodeChunked(expected))
        let undone=await doc.store.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(doc.store.document,source)
      } }
    }
  }

  @MainActor func testMaximumStackNoOpAndCapabilityContractRetainExistingVersions() async throws {
    let(s,m)=try await prepared();defer{stop(s,m)}
    var full=settings();full.effects=(0..<32).map { index in var e=GalleryEffect(.cutout);e.foreground=Pixel(Float(index)/32,0.25,0.5);return e }
    m.change(full);let before=m.undoStates.count
    let payload=try XCTUnwrap(m.beginEffectDrag(at:0));XCTAssertTrue(m.receiveEffectDrop(payload,at:31))
    XCTAssertEqual(m.settings.effects.count,32);XCTAssertEqual(m.settings.effects.last,full.effects.first)
    XCTAssertEqual(m.undoStates.count,before+1);m.undo();XCTAssertEqual(m.settings,full)
    XCTAssertFalse(m.moveEffect(from:0,to:0));XCTAssertFalse(m.moveEffect(from:0,to:32))
    XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,61)
    let capabilities=try XCTUnwrap(RasterFilter.apiCapabilities["filterGallery"] as? [String:Any])
    XCTAssertNotNil(capabilities["effectReordering"])
    XCTAssertEqual((GalleryEffectTransfer.apiCapabilities["commands"] as? [String]),["filter.apply","smartFilter.set"])
    let effects=try m.settings.effects.map { try JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) }
    let body=try JSONSerialization.data(withJSONObject:["effects":effects])
    XCTAssertEqual(try ArtisticGallerySettings.decodeJSON(body),m.settings)
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"filterGallery\"}]"))
  }

  @MainActor func testHostedStackAndAllModifierCursorsKeepModalAndRestoreBehavior() async throws {
    let(s,m)=try await prepared();defer{stop(s,m)};let canvas=CraftCanvas(store:s)
    let view=NSHostingView(rootView:ArtisticGallerySheet(store:s,model:m));view.frame=NSRect(x:0,y:0,width:960,height:660);view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width,800)
    let flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for bits in 0..<16 {
      let current=flags.enumerated().reduce(NSEvent.ModifierFlags()) { bits&(1 << $1.offset) != 0 ? $0.union($1.element):$0 }
      canvas.updateCursorModifiers(current);XCTAssertEqual(canvas.toolCursor,.unavailable)
      _=GalleryEffectTransfer.provider(model:m,index:0)
      canvas.updateCursorModifiers(current);XCTAssertEqual(canvas.toolCursor,.unavailable)
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
      view.cacheDisplay(in:view.bounds,to:bitmap)
      let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
      try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:folder.appendingPathComponent("gallery-drag-offscreen.png"))
    }
    m.close();s.cancelFilter();canvas.updateCursorModifiers([]);XCTAssertNotEqual(canvas.toolCursor,.unavailable)
  }
}
