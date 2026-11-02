import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class SelectionTransformGate:@unchecked Sendable {
  let condition=NSCondition();var released=false
  func wait(){condition.lock();while !released{condition.wait()};condition.unlock()}
  func release(){condition.lock();released=true;condition.broadcast();condition.unlock()}
}
final class SelectionTransformWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {var d=try CraftDocument(width:32,height:24,depth:depth);d.selection = .init(x:6,y:5,width:12,height:10);d.layers[0].content = .raster(try Surface(width:32,height:24,depth:depth,fill:Pixel(0.2,0.4,0.8)));return d}
  @MainActor func settle(_ session:SelectionTransformSession)async {for _ in 0..<30 {await session.task?.value;if !session.loading && !session.previewBusy{return};await Task.yield()}}
  @MainActor func testPreviewCancelAndFactoryMenusWithoutPixelTransform()async throws {
    let original=try fixture(),s=EditorStore(document:original,brushes:BrushLibrary());defer{s.cancelTransform();s.renderTask?.cancel()};s.beginSelectionTransform();let session=try XCTUnwrap(s.selectionTransform);await settle(session)
    XCTAssertNotNil(session.previewPath);XCTAssertTrue(s.previewDocument==original)
    var draft=try XCTUnwrap(s.transformDraft);draft=draft.selectionNumeric(\.centerX,draft.selectionReferencePoint.x+3);s.updateTransform(draft);await settle(session)
    XCTAssertTrue(s.document==original);XCTAssertTrue(s.previewDocument==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.selectionTransformState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:SelectionTransformAPI.stateSchema))
    let menus=PhotoshopMenuTests();try menus.withMenus{_,menu in for action in [#selector(AppDelegate.transformSelection),#selector(AppDelegate.transformScaleMode),#selector(AppDelegate.transformRotateMode),#selector(AppDelegate.transformSkewMode),#selector(AppDelegate.transformDistortMode),#selector(AppDelegate.transformPerspectiveMode)] {XCTAssertNotNil(menus.allItems(menu).first{$0.action==action})}}
    s.cancelTransform();XCTAssertNil(s.selectionTransform);XCTAssertNil(s.transformDraft);XCTAssertTrue(s.document==original)
  }
  @MainActor func testAll16ModifiersCapturedGesturesReferenceAndNumericControls()async throws {
    let s=EditorStore(document:try fixture(),brushes:BrushLibrary());defer{s.cancelTransform();s.renderTask?.cancel()};s.beginSelectionTransform();let session=try XCTUnwrap(s.selectionTransform);await settle(session)
    let base=try XCTUnwrap(s.transformDraft),flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for bits in 0..<16 {let f=flags.enumerated().reduce(NSEvent.ModifierFlags()){r,v in bits & (1<<v.offset) != 0 ? r.union(v.element):r}
      let expected:SelectionTransformMode=f.contains([.command,.option,.shift]) ? .perspective:f.contains(.command) ? .distort:.free
      XCTAssertEqual(base.selectionMode(handle:4,modifiers:f),expected)
      let from=base.handles[4],to=CGPoint(x:from.x+2,y:from.y+1),next=base.selectionDragging(handle:4,from:from,to:to,mode:expected,shift:f.contains(.shift),option:f.contains(.option));XCTAssertNoThrow(try next.selectionProjection)
      let side=base.selectionMode(handle:1,modifiers:f);if f.contains([.command,.shift]) {XCTAssertEqual(side,.skew)}
      XCTAssertNotEqual(ToolCursor.selectionTransform(expected,handle:4,flags:f),.unavailable)
      for proportional in [false,true] {for mode in [SelectionTransformMode.free,.scale] {
        let constrained=proportional != f.contains(.shift),centered=f.contains(.option)
        let badge:ToolCursor.Badge?=constrained ? (centered ? .constrainCenter:.constrain):(centered ? .center:nil)
        XCTAssertEqual(ToolCursor.selectionTransform(mode,handle:4,flags:f,proportional:proportional),.symbol("arrow.up.left.and.arrow.down.right",badge))
      }}
    }
    let top=base.handles[1],corner=base.handles[0],bottom=base.handles[4]
    let skew=base.selectionDragging(handle:1,from:top,to:.init(x:top.x+3,y:top.y+2),mode:.skew,shift:false,option:false)
    XCTAssertEqual(skew.selectionCorners[0],.init(9,5));XCTAssertEqual(skew.selectionCorners[1],.init(21,5));XCTAssertEqual(skew.selectionCorners[2],base.selectionCorners[2])
    let perspective=base.selectionDragging(handle:0,from:corner,to:.init(x:corner.x+2,y:corner.y+0.5),mode:.perspective,shift:false,option:false)
    XCTAssertEqual(perspective.selectionCorners[0],.init(8,5));XCTAssertEqual(perspective.selectionCorners[1],.init(16,5));XCTAssertEqual(perspective.selectionCorners[2],base.selectionCorners[2])
    let distort=base.selectionDragging(handle:4,from:bottom,to:.init(x:bottom.x+2,y:bottom.y+1),mode:.distort,shift:false,option:false)
    XCTAssertEqual(distort.selectionCorners[2],.init(20,16));XCTAssertEqual(distort.selectionCorners[0],base.selectionCorners[0])
    let scaled=base.selectionDragging(handle:4,from:bottom,to:.init(x:30,y:25),mode:.scale,shift:false,option:false)
    XCTAssertEqual(scaled.selectionCorners[0],base.selectionCorners[0]);XCTAssertEqual(scaled.selectionCorners[2],.init(30,25));XCTAssertEqual(scaled.scaleX,200);XCTAssertEqual(scaled.scaleY,200)
    let rotated=base.selectionDragging(handle:4,from:bottom,to:.init(x:7,y:16),mode:.rotate,shift:false,option:false)
    XCTAssertEqual(rotated.angle,90,accuracy:1e-8);XCTAssertEqual(rotated.selectionCorners[2].x,7,accuracy:1e-8);XCTAssertEqual(rotated.selectionCorners[2].y,16,accuracy:1e-8)
    let moved=base.selectionDragging(handle:-1,from:.zero,to:.init(x:2,y:3),mode:.free,shift:false,option:false)
    XCTAssertEqual(moved.selectionCorners[0],.init(8,8));XCTAssertEqual(moved.selectionCorners[2],.init(20,18))
    for anchor in CanvasAnchor.allCases {var draft=base;draft.referenceAnchor=anchor;let f=anchor.fractions,p=draft.selectionReferencePoint;XCTAssertEqual(p.x,6+12*f.0,accuracy:1e-8);XCTAssertEqual(p.y,5+10*f.1,accuracy:1e-8)}
    var anchored=base;anchored.referenceAnchor = .topLeft;let pivot=anchored.selectionReferencePoint;anchored=anchored.selectionNumeric(\.scaleX,200);XCTAssertEqual(anchored.selectionReferencePoint,pivot);XCTAssertEqual(anchored.scaleY,200)
    let canvas=CraftCanvas(store:s);canvas.frame = .init(x:0,y:0,width:640,height:480);s.updateViewport(size:canvas.frame.size,backingScale:1);s.setZoom(10,center:true)
    let p=canvas.convert(canvas.viewPoint(base.handles[4]),to:nil)
    let down=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:p,modifierFlags:.command,timestamp:1,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:0));canvas.mouseDown(with:down);XCTAssertEqual(canvas.selectionTransformGestureMode,.distort)
    canvas.updateCursorModifiers([]);XCTAssertEqual(canvas.toolCursor,ToolCursor.selectionTransform(.distort,handle:4,flags:[]))
    let up=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseUp,location:p,modifierFlags:[],timestamp:2,windowNumber:0,context:nil,eventNumber:2,clickCount:1,pressure:0));canvas.mouseUp(with:up);XCTAssertNil(canvas.selectionTransformGestureMode)
    XCTAssertNotNil(canvas.selectionTransformMenu(for:down))
  }
  @MainActor func testNativeCommitUndoActionsStaleAndReadClose()async throws {
    let doc=CraftNSDocument(model:try fixture()),s=doc.store;defer{s.cancelTransform();s.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()};let original=s.document
    s.beginSelectionTransform();let session=try XCTUnwrap(s.selectionTransform);var draft=try XCTUnwrap(s.transformDraft);draft=draft.selectionApplying(.translation(3,2));s.updateTransform(draft);try s.session.startActionRecording(name:"Selection");s.commitTransform();await session.commitTask?.value
    XCTAssertNil(session.error);XCTAssertNil(s.transformDraft);XCTAssertEqual(s.session.undoStack.last?.label,"Transform Selection");XCTAssertEqual(s.document.layers,original.layers)
    var replay=original;try XCTUnwrap(s.session.actionRecording?.snapshot).apply(to:&replay);XCTAssertTrue(replay==s.document);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
    s.beginSelectionTransform();let stale=try XCTUnwrap(s.selectionTransform);try s.session.execute(.renameLayer(original.layers[0].id,"Changed"));s.commitTransform();await stale.commitTask?.value;await stale.task?.value;XCTAssertFalse(stale.previewBusy);XCTAssertNotNil(stale.error);s.cancelTransform()
    s.beginSelectionTransform();let reading=try XCTUnwrap(s.selectionTransform);try doc.read(from:NativeArchive.encodeChunked(original),ofType:CraftNSDocument.nativeType);XCTAssertTrue(reading.closed);XCTAssertNil(s.selectionTransform)
    s.beginSelectionTransform();let closing=try XCTUnwrap(s.selectionTransform);doc.close();XCTAssertTrue(closing.closed);XCTAssertNil(s.selectionTransform)
  }
  @MainActor func testHTTPMatricesMatchNativeAndPreserveMaskTarget()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      var original=try self.fixture();original.layers[0].mask=try Surface(width:32,height:24,fill:.white);let s=doc.store;s.session=EditorSession(document:original);try service.share(doc)
      let matrices=[ProjectiveTransform(.translation(2,1)),try ProjectiveTransform([1,0.1,0,0,1,0,0.005,0,1])]
      for matrix in matrices {for method in Resampling.allCases {s.session=EditorSession(document:original);s.maskEditingLayerID=original.layers[0].id
        let status=try await h.edit(service,doc,"selection.transform",["matrix":matrix.values,"interpolation":method.rawValue]);XCTAssertEqual(status,200)
        var expected=original;try SelectionTransform.command(in:original,projection:matrix,interpolation:method).apply(to:&expected);XCTAssertTrue(s.document==expected);XCTAssertEqual(s.document.layers,original.layers);XCTAssertTrue(s.editingMask);XCTAssertEqual(s.maskEditingLayerID,original.layers[0].id);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
      }}
    }
  }
  @MainActor func testInvalidBusyStaleRevokeAndNativeCancelBarrier()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try self.fixture(),s=doc.store;s.session=EditorSession(document:original);try service.share(doc);let params:[String:Any]=["matrix":[1,0,2,0,1,1,0,0,1]]
      for extra:[String:Any] in [["matrix":[1,0]],["matrix":[0,0,0,0,0,0,0,0,0]],["interpolation":"bad"]] {let status=try await h.edit(service,doc,"selection.transform",params.merging(extra){_,b in b});XCTAssertEqual(status,400);XCTAssertTrue(s.document==original)}
      let stale=try await h.edit(service,doc,"selection.transform",params,revision:"old");XCTAssertEqual(stale,409)
      s.beginSelectionTransform();let busy=try await h.edit(service,doc,"selection.transform",params);XCTAssertEqual(busy,409);s.cancelTransform()
      let gate=SelectionTransformGate();s.selectionTransformPreparation={source,matrix,method in gate.wait();try Task.checkCancellation();return try SelectionTransform.command(in:source,projection:matrix,interpolation:method)}
      let task=Task{try await h.edit(service,doc,"selection.transform",params)};let until=Date().addingTimeInterval(10);while !s.geometryBusy && Date()<until{await Task.yield()};XCTAssertTrue(s.geometryBusy);service.revoke(try XCTUnwrap(service.shares.first?.id));gate.release();let revoked=try await task.value;XCTAssertEqual(revoked,409);XCTAssertTrue(s.document==original)
      let nativeGate=SelectionTransformGate();s.selectionTransformPreparation={source,matrix,method in nativeGate.wait();try Task.checkCancellation();return try SelectionTransform.command(in:source,projection:matrix,interpolation:method)}
      s.beginSelectionTransform();let native=try XCTUnwrap(s.selectionTransform);s.commitTransform();s.cancelTransform();nativeGate.release();await native.commitTask?.value;XCTAssertTrue(s.document==original);XCTAssertFalse(s.geometryBusy)
    }
  }
  @MainActor func testAllDepthsProfilesLocksAndNumericFlips()async throws {
    for depth in PixelDepth.allCases {var original=try fixture(depth);original.layers[0].locked=true;original.workingICC=try ColorManagement.importedProfile(XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3)?.copyICCData() as Data?),depth:depth)
      let s=EditorStore(document:original,brushes:BrushLibrary());defer{s.cancelTransform();s.renderTask?.cancel()};s.componentTarget = .red;s.beginSelectionTransform();let session=try XCTUnwrap(s.selectionTransform);s.transformLayer(horizontal:true);s.commitTransform();await session.commitTask?.value
      XCTAssertNil(session.error);XCTAssertEqual(s.document.layers,original.layers);XCTAssertEqual(s.document.depth,depth);XCTAssertEqual(s.document.workingICC,original.workingICC);XCTAssertEqual(s.componentTarget,.red)
    }
  }
}
