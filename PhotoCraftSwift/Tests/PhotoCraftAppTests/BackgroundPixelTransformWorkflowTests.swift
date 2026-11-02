import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class BackgroundTransformGate:@unchecked Sendable {
  let condition=NSCondition();var ready=false
  func wait(){condition.lock();while !ready{condition.wait()};condition.unlock()}
  func release(){condition.lock();ready=true;condition.broadcast();condition.unlock()}
}
final class BackgroundPixelTransformWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {var d=try SelectedPixelTransformWorkflowTests().fixture(depth);d.layers[0].background=true;return d}
  @MainActor func testNativeCapturedSwatchPreviewCancelApplyUndoAndActions33()async throws {
    let original=try fixture(),s=EditorStore(document:original,brushes:BrushLibrary());defer{s.cancelTransform();s.renderTask?.cancel()};s.backgroundColor=Pixel(0.2,0.3,0.4);let captured=s.backgroundColor;XCTAssertTrue(s.canBeginSelectedPixelTransform);s.beginTransform();let session=try XCTUnwrap(s.selectionTransform);await SelectedPixelTransformWorkflowTests().settle(session);XCTAssertNil(session.error);XCTAssertNotNil(session.pixelPreview)
    var draft=try XCTUnwrap(s.transformDraft);XCTAssertEqual(draft.selectedPixelsBackgroundColor,captured);draft=draft.selectionApplying(.translation(3,2));s.updateTransform(draft);s.backgroundColor = .black;await SelectedPixelTransformWorkflowTests().settle(session);XCTAssertEqual(s.transformDraft?.selectedPixelsBackgroundColor,captured);XCTAssertEqual(s.document,original)
    let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.selectedPixelTransformState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:SelectedPixelTransformAPI.stateSchema));XCTAssertEqual(s.selectedPixelTransformState["background"] as? Bool,true)
    try s.session.startActionRecording(name:"Background");s.commitTransform();await session.commitTask?.value;XCTAssertNil(session.error);var expected=original;try Command.transformPixels(.init(layerID:original.layers[0].id,matrix:.init(.translation(3,2)),backgroundColor:captured)).apply(to:&expected);XCTAssertEqual(s.document,expected)
    var file=ActionLibraryFile();file.actions=[try XCTUnwrap(s.session.actionRecording?.snapshot)];XCTAssertEqual(try ActionLibraryFile.decode(file.encoded()).version,33);var downgraded=try XCTUnwrap(JSONSerialization.jsonObject(with:file.encoded()) as? [String:Any]);downgraded["version"]=32;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:downgraded)));var replay=original;try file.actions[0].apply(to:&replay);XCTAssertEqual(replay,expected);_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,original)
    s.beginTransform();let cancelled=try XCTUnwrap(s.selectionTransform);s.cancelTransform();XCTAssertTrue(cancelled.closed);XCTAssertEqual(s.document,original)
  }
  @MainActor func testAll16CapturedModifierCursorsAndDirectSelectedFlip()async throws {
    let s=EditorStore(document:try fixture(),brushes:BrushLibrary());defer{s.cancelTransform();s.renderTask?.cancel()};s.backgroundColor = .black;s.beginTransform();let draft=try XCTUnwrap(s.transformDraft)
    let expected:[SelectionTransformMode]=[.free,.free,.distort,.distort,.free,.free,.distort,.distort,.free,.free,.distort,.distort,.free,.free,.perspective,.perspective]
    let flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for bits in 0..<16 {let modifiers=flags.enumerated().reduce(NSEvent.ModifierFlags()){result,pair in bits & (1<<pair.offset) != 0 ? result.union(pair.element):result},mode=draft.selectionMode(handle:0,modifiers:modifiers);XCTAssertEqual(mode,expected[bits]);let moved=draft.selectionDragging(handle:4,from:draft.handles[4],to:.init(x:23,y:18),mode:mode,shift:modifiers.contains(.shift),option:modifiers.contains(.option));XCTAssertNoThrow(try moved.selectionProjection);XCTAssertEqual(moved.selectedPixelsBackgroundColor,.black);let canvas=CraftCanvas(store:s);canvas.updateCursorModifiers(modifiers);XCTAssertNotEqual(canvas.toolCursor,.unavailable)}
    s.cancelTransform();let original=s.document;s.transformLayer(horizontal:true);await s.geometryTask?.value;XCTAssertTrue(s.activeLayer?.isBackground ?? false);XCTAssertNotEqual(s.document,original);XCTAssertEqual(s.activeLayer?.x,0);XCTAssertEqual(s.session.undoStack.last?.label,"Free Transform")
  }
  @MainActor func testHTTPThreeDepthProfilesInterpolationsAndExplicitOrCapturedColor()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in let s=doc.store
      for depth in PixelDepth.allCases {var original=try self.fixture(depth);original.workingICC=try ColorManagement.importedProfile(XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3)?.copyICCData() as Data?),depth:depth);let id=original.layers[0].id,matrix=try ProjectiveTransform([1,0.05,2,0,1,1,0.002,0,1]);s.backgroundColor=Pixel(0.2,0.4,0.6)
        for method in Resampling.allCases {for explicit in [false,true] {s.session=EditorSession(document:original);try service.share(doc);let color:Pixel=explicit ? .black:s.backgroundColor;var params:[String:Any]=["layerID":id.uuidString,"matrix":matrix.values,"interpolation":method.rawValue];if explicit{params["backgroundColor"]=[0,0,0,1]};let status=try await h.edit(service,doc,"pixels.transform",params);XCTAssertEqual(status,200);var expected=original;try Command.transformPixels(.init(layerID:id,matrix:matrix,interpolation:method,backgroundColor:color)).apply(to:&expected);XCTAssertEqual(s.document,expected);XCTAssertEqual(try NativeArchive.encodeChunked(s.document),try NativeArchive.encodeChunked(expected));let encoded=try PSDCodec.writeRasterLayers(s.document);XCTAssertTrue(try PSDCodec.read(encoded).layers[0].isBackground);_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,original)}}
      }
    }
  }
  @MainActor func testHTTPInvalidBusyStaleRevokeAndNativeCancellation()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in let s=doc.store,original=try self.fixture();s.session=EditorSession(document:original);try service.share(doc);let params:[String:Any]=["layerID":original.layers[0].id.uuidString,"matrix":[1,0,2,0,1,0,0,0,1]]
      for color:Any in [[0,0,0,0.5],[0,0,0],[2,0,0,1],[true,0,0,1],"black"] {let code=try await h.edit(service,doc,"pixels.transform",params.merging(["backgroundColor":color]){_,b in b});XCTAssertEqual(code,400);XCTAssertEqual(s.document,original)}
      let stale=try await h.edit(service,doc,"pixels.transform",params,revision:"old");XCTAssertEqual(stale,409);s.beginTransform();let busy=try await h.edit(service,doc,"pixels.transform",params);XCTAssertEqual(busy,409);s.cancelTransform()
      let gate=BackgroundTransformGate();defer{gate.release()};s.selectedPixelTransformPreparation={_,request in gate.wait();try Task.checkCancellation();return .transformPixels(request)};let task=Task{try await h.edit(service,doc,"pixels.transform",params)};let deadline=Date().addingTimeInterval(10);while !s.geometryBusy && Date()<deadline{await Task.yield()};XCTAssertTrue(s.geometryBusy);service.revoke(try XCTUnwrap(service.shares.first?.id));gate.release();let code=try await task.value;XCTAssertEqual(code,409);XCTAssertEqual(s.document,original)
      let nativeGate=BackgroundTransformGate();defer{nativeGate.release()};s.selectedPixelTransformPreparation={_,request in nativeGate.wait();try Task.checkCancellation();return .transformPixels(request)};s.beginTransform();let session=try XCTUnwrap(s.selectionTransform);s.commitTransform();s.cancelTransform();nativeGate.release();await session.commitTask?.value;XCTAssertEqual(s.document,original);XCTAssertFalse(s.geometryBusy)
    }
  }
  @MainActor func testLocksTargetsReadCloseAndPublishedBackgroundGuards()throws {
    let doc=CraftNSDocument(model:try fixture()),s=doc.store;defer{s.cancelTransform();s.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()};let original=s.document
    s.componentTarget = .red;XCTAssertFalse(s.canBeginSelectedPixelTransform);s.componentTarget = .composite;var locked=original;locked.layers[0].protection = .image;s.session=EditorSession(document:locked);XCTAssertFalse(s.canBeginSelectedPixelTransform);s.session=EditorSession(document:original)
    s.beginTransform();let reading=try XCTUnwrap(s.selectionTransform);try doc.read(from:NativeArchive.encodeChunked(original),ofType:CraftNSDocument.nativeType);XCTAssertTrue(reading.closed);XCTAssertNil(s.selectionTransform);s.beginTransform();let closing=try XCTUnwrap(s.selectionTransform);doc.close();XCTAssertTrue(closing.closed)
    XCTAssertThrowsError(try AdobeCompositeEdit(["type":"background_layer","id":0,"operation":["type":"edit"],"transform":["position":["x":1,"y":1]]],path:"layers[0]"))
  }
  func testBoundedBackgroundPreviewRetainsSourceAndCapturedFill()async throws {
    var original=try DocumentCreation.blank(width:4096,height:2048);original.selection = .init(x:1000,y:500,width:512,height:512);let source=original
    let proxy=try await Task.detached{try SelectedPixelTransformPreviewSource.prepare(source)}.value;XCTAssertEqual(proxy.document.width,1024);XCTAssertTrue(proxy.document.layers[0].isBackground);let image=try await Task.detached{try proxy.image(layerID:source.layers[0].id,matrix:.init(.translation(200,100)),interpolation:.bilinear,backgroundColor:.black)}.value;XCTAssertEqual(image.image.width,1024);XCTAssertEqual(source,original)
  }
}
