import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class BrushTextureGate: @unchecked Sendable {
  private let lock=NSCondition(); private var started=false,released=false
  func prepare(_ pattern:RasterPattern)throws->BrushBitmap {
    lock.lock();started=true;lock.broadcast()
    while !released { if Task.isCancelled {lock.unlock();throw CancellationError()};_ = lock.wait(until:Date(timeIntervalSinceNow:0.01)) }
    lock.unlock();try Task.checkCancellation();return try BrushTexturePreparation.bitmap(pattern)
  }
  var ready:Bool {lock.lock();defer{lock.unlock()};return started}
  func release(){lock.lock();released=true;lock.broadcast();lock.unlock()}
}
final class BrushPatternTextureTests: XCTestCase {
  func owned()throws->RasterPattern {
    var s=try Surface(width:4,height:2,fill:.white)
    for y in 0..<2 {for x in 0..<4 {s.setPixel(x:x,y:y,Pixel(Float(x)/3,Float(x)/3,Float(x)/3))}}
    return try RasterPattern(name:"Owned brush texture",surface:s,id:"owned-brush-texture")
  }
  @MainActor func library()async throws->PatternLibrary {let p=PatternLibrary();try await p.install([owned()]);return p}
  @MainActor private func wait(_ gate:BrushTextureGate)async throws {
    for _ in 0..<1000 {if gate.ready{return};try await Task.sleep(for:.milliseconds(2))}
    XCTFail("Texture worker did not start");throw CancellationError()
  }
  @MainActor func testNativeSelectionPresetPersistenceLocksAndLibraryIndependence()async throws {
    let patterns=try await library(),brushes=BrushLibrary(),doc=try CraftDocument(width:48,height:32)
    let store=EditorStore(document:doc,patterns:patterns,brushes:brushes);defer{store.renderTask?.cancel()}
    store.brushOptions.lockedSections=["texture"];store.brushOptions.texture.scale=1.5;store.brushOptions.texture.invert=true
    let before=store.brushRevision
    try await store.chooseBrushTexture("owned-brush-texture")
    let captured=try XCTUnwrap(store.brushOptions.texture.bitmap)
    XCTAssertEqual(Array(captured.bytes),[0,85,170,255,0,85,170,255]);XCTAssertTrue(store.brushOptions.texture.enabled)
    XCTAssertEqual(store.brushOptions.texture.scale,1.5);XCTAssertTrue(store.brushOptions.texture.invert)
    XCTAssertEqual(store.brushOptions.lockedSections,["texture"]);XCTAssertGreaterThan(store.brushRevision,before)
    XCTAssertEqual(store.document,doc);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertFalse(store.geometryBusy);XCTAssertFalse(store.brushTextureLoading)
    let preset=try store.saveBrush(name:"Owned textured brush",group:"Owned")
    let native=try BrushPresetFile.decode(brushes.exportData(preset.id));XCTAssertEqual(native.version,1);XCTAssertEqual(native.presets[0].brush.settings?.texture.bitmap,captured)
    let abr=try ABRCodec.read(brushes.exportData(preset.id,abr:true));XCTAssertEqual(abr.presets[0].brush.settings?.texture.bitmap,captured)
    try await patterns.remove("owned-brush-texture");XCTAssertEqual(store.brushOptions.texture.bitmap,captured)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("Brushes.photatobrushes"),disk=BrushLibrary(persistenceURL:url);try disk.save(preset)
    XCTAssertEqual(BrushLibrary(persistenceURL:url).file.presets.last?.brush.settings?.texture.bitmap,captured)
  }
  @MainActor func testNativeCancellationStaleBrushLibraryAndRejectedAuthorizationAreAtomic()async throws {
    let patterns=try await library(),store=EditorStore(document:try CraftDocument(width:32,height:24),patterns:patterns,brushes:BrushLibrary())
    defer{store.renderTask?.cancel()};let original=store.brush
    for mode in 0..<4 {
      let gate=BrushTextureGate();defer{gate.release()};store.brush=original
      let operation=Task {try await store.chooseBrushTexture("owned-brush-texture",prepare:gate.prepare)}
      try await wait(gate);XCTAssertTrue(store.brushTextureLoading);XCTAssertEqual(store.brush,original)
      switch mode {
      case 0: operation.cancel()
      case 1: store.brush.size=21
      case 2: patterns.selectedID=nil
      default: store.geometryTask?.cancel()
      }
      let expected=store.brush;gate.release()
      do {try await operation.value;XCTFail("Invalidated texture published")}catch{}
      XCTAssertEqual(store.brush,expected);XCTAssertFalse(store.geometryBusy);XCTAssertFalse(store.brushTextureLoading);XCTAssertTrue(store.session.undoStack.isEmpty)
    }
    store.brush=original
    do {try await store.chooseBrushTexture("owned-brush-texture",authorize:{throw AutomationFailure(status:409,message:"owned rejection")});XCTFail("Authorization ignored")}catch{}
    XCTAssertEqual(store.brush,original);XCTAssertFalse(store.geometryBusy)
  }
  @MainActor func testNativeReadyStrokeCancelCommitUndoActionsAndCapturedTexture()async throws {
    let patterns=try await library(),original=try CraftDocument(width:48,height:32)
    let store=EditorStore(document:original,patterns:patterns,actions:ActionLibrary(),brushes:BrushLibrary())
    defer{store.cancelBrush();store.renderTask?.cancel()};store.tool = .brush;store.brush.color = .black;store.brush.size=12
    try await store.chooseBrushTexture("owned-brush-texture");let bitmap=store.brushOptions.texture.bitmap
    store.beginBrush(.init(x:10,y:16),zoom:1);store.extendBrush(.init(x:30,y:16,time:100));store.cancelBrush();XCTAssertEqual(store.document,original)
    try store.startRecordingAction(name:"Owned texture paint",set:"Owned")
    store.beginBrush(.init(x:10,y:16),zoom:1);store.extendBrush(.init(x:30,y:16,time:100))
    let command=try XCTUnwrap(store.brushGesture?.command),captured=try XCTUnwrap(store.brushGesture?.brush)
    store.brushOptions.texture.bitmap=nil;XCTAssertEqual(captured.settings?.texture.bitmap,bitmap)
    var expected=original;try command.apply(to:&expected);store.finishBrush();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertNotEqual(expected,original);XCTAssertEqual(store.session.undoStack.count,1)
    let action=try store.stopRecordingAction();var replay=original;try action.apply(to:&replay);XCTAssertEqual(replay,expected)
    let encoded=try store.actions.exportFile(action.id);let decoded=try ActionLibraryFile.decode(encoded);XCTAssertEqual(decoded.actions.count,1)
    try await patterns.remove("owned-brush-texture");replay=original;try decoded.actions[0].apply(to:&replay);XCTAssertEqual(replay,expected)
    _=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,original);_=await store.requestHistory(redo:true).value;XCTAssertEqual(store.document,expected)
  }
  @MainActor func testHTTPConfigurationAndPaintingMatchNativeForAllDepths()async throws {
    let helper=AutomationTests(),patterns=try await library()
    try await helper.withService(brushes:BrushLibrary(),patterns:patterns,pressedMouseButtons:{0}){service,document in
      for depth in PixelDepth.allCases {
        let doc=try CraftDocument(width:40,height:32,depth:depth);document.store.session=EditorSession(document:doc);document.store.selectedLayerIDs=[doc.layers[0].id];document.store.tool = .brush
        try service.share(document)
        let native=EditorStore(document:doc,patterns:patterns,brushes:BrushLibrary());defer{native.renderTask?.cancel()}
        document.store.brush=native.brush // Compare identical initial tool state; session replacement does not recenter an existing brush.
        var configured=native.brush;configured.size=11;configured.color = .black
        try await native.chooseBrushTexture("owned-brush-texture",configured:configured)
        let revision=service.revision(document.store)
        let status=try await helper.edit(service,document,"brush.configure",["brush":["size":11,"color":["r":0,"g":0,"b":0,"a":1]],"texturePatternID":"owned-brush-texture"])
        XCTAssertEqual(status,200);XCTAssertEqual(document.store.brush,native.brush);XCTAssertNotEqual(service.revision(document.store),revision)
        XCTAssertEqual(document.store.document,doc);XCTAssertTrue(document.store.session.undoStack.isEmpty)
        let noOpRevision=service.revision(document.store)
        let noOp=try await helper.edit(service,document,"brush.configure",["brush":[:],"texturePatternID":"owned-brush-texture"])
        XCTAssertEqual(noOp,200);XCTAssertEqual(service.revision(document.store),noOpRevision)
        let points:[StrokePoint]=[.init(x:10,y:16),.init(x:28,y:16,time:100)]
        var expected=doc;try Command.stroke(doc.layers[0].id,points,native.brush).apply(to:&expected)
        let painted=try await helper.edit(service,document,"paint.stroke",["points":BrushAPI.json(points)]);XCTAssertEqual(painted,200);XCTAssertEqual(document.store.document,expected)
        let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,doc)
      }
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAuthenticationAndSchemasPreserveState()async throws {
    let helper=AutomationTests(),patterns=try await library()
    try await helper.withService(brushes:BrushLibrary(),patterns:patterns,pressedMouseButtons:{0}){service,document in
      try service.share(document);let before=document.store.brush,doc=document.store.document
      for (params,expected) in [(["brush":[:],"texturePatternID":"missing"]as[String:Any],404),(["brush":[:],"texturePatternID":true],400),(["brush":[:],"texturePatternID":String(repeating:"a",count:256)],400),(["texturePatternID":"owned-brush-texture"],400),(["brush":["size":0],"texturePatternID":"owned-brush-texture"],400)] {
        let code=try await helper.edit(service,document,"brush.configure",params);XCTAssertEqual(code,expected)
      }
      let code=try await helper.edit(service,document,"brush.configure",["brush":[:],"texturePatternID":"owned-brush-texture"],revision:"stale");XCTAssertEqual(code,409)
      let share=try XCTUnwrap(service.shares.first?.id)
      let auth=try await helper.request(service,path:"/v1/documents/\(share)/commands",body:["command":"brush.configure","revision":service.revision(document.store),"parameters":["brush":[:],"texturePatternID":"owned-brush-texture"]],authenticate:false);XCTAssertEqual(auth.0.statusCode,401)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"brush.configure",["brush":[:],"texturePatternID":"owned-brush-texture"]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      XCTAssertEqual(document.store.brush,before);XCTAssertEqual(document.store.document,doc)
      let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name=="brush.configure"});let envelope=try XCTUnwrap(definition.schema["properties"]as?[String:Any]);let params=try XCTUnwrap(envelope["parameters"]as?[String:Any]);let fields=try XCTUnwrap(params["properties"]as?[String:Any]);XCTAssertNotNil(fields["texturePatternID"])
      XCTAssertTrue(definition.optionalParameters.contains("texturePatternID"));XCTAssertEqual(document.store.brushState["textureLoading"]as?Bool,false)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:BrushAPI.capabilities));XCTAssertEqual(AutomationCommand.definitions.count,267)
    }
  }
  @MainActor func testHTTPDeferredRevocationAndLibraryChangesRejectCompletePatch()async throws {
    let helper=AutomationTests()
    for revoke in [false,true] {
      let patterns=try await library(),gate=BrushTextureGate();defer{gate.release()}
      try await helper.withService(brushes:BrushLibrary(),patterns:patterns,pressedMouseButtons:{0}){service,document in
        try service.share(document);document.store.brushTexturePreparation=gate.prepare
        let before=document.store.brush,share=try XCTUnwrap(service.shares.first?.id)
        let operation=Task {try await helper.edit(service,document,"brush.configure",["brush":["size":19,"color":["r":1,"g":0,"b":0,"a":1]],"texturePatternID":"owned-brush-texture"])}
        try await wait(gate);XCTAssertTrue(document.store.brushTextureLoading);XCTAssertEqual(document.store.brush,before)
        if revoke {service.revoke(share)}else{patterns.selectedID=nil}
        gate.release();let status=try await operation.value;XCTAssertEqual(status,409)
        XCTAssertEqual(document.store.brush,before);XCTAssertFalse(document.store.geometryBusy);XCTAssertFalse(document.store.brushTextureLoading);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testHostedTextureControlsKeepNativeAppearanceAndCancelledChoiceUsable()async throws {
    _=NSApplication.shared;let patterns=try await library()
    for name in [NSAppearance.Name.aqua,.darkAqua] {
      let store=EditorStore(document:try CraftDocument(width:32,height:24),patterns:patterns,brushes:BrushLibrary());defer{store.renderTask?.cancel()}
      try await store.chooseBrushTexture("owned-brush-texture")
      let window=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:560),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:name)
      let host=NSHostingView(rootView:BrushSettingsPanel(store:store,section:"texture"));window.contentView=host;host.layoutSubtreeIfNeeded()
      XCTAssertEqual(window.contentView?.bounds.width,540);XCTAssertTrue(store.canChooseBrushTexture)
      if let dir=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],let image=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
        host.cacheDisplay(in:host.bounds,to:image);if let png=image.representation(using:.png,properties:[:]){try png.write(to:URL(fileURLWithPath:dir).appendingPathComponent("brush-pattern-\(name.rawValue).png"))}
      }
      window.close()
    }
  }
}
