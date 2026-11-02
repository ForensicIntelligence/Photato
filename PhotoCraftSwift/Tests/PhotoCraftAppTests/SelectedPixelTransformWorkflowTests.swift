import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class PixelTransformGate:@unchecked Sendable {
  let condition=NSCondition();var ready=false
  func wait(){condition.lock();while !ready{condition.wait()};condition.unlock()}
  func release(){condition.lock();ready=true;condition.broadcast();condition.unlock()}
}
final class SelectedPixelTransformWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:32,height:24,depth:depth),pixels=try Surface(width:32,height:24,depth:depth,fill:Pixel(0.2,0.4,0.8))
    pixels.setPixel(x:7,y:6,.white);d.selection = .init(x:6,y:5,width:12,height:10);d.layers[0].content = .raster(pixels);return d
  }

  @MainActor func settle(_ session:SelectionTransformSession)async{for _ in 0..<30{await session.task?.value;if !session.loading && !session.previewBusy{return};await Task.yield()}}
  @MainActor func testNativeFreeTransformImagePreviewCancelAndSchemas()async throws {
    let original=try fixture(),s=EditorStore(document:original,brushes:BrushLibrary());defer{s.cancelTransform();s.renderTask?.cancel()};s.beginTransform();let session=try XCTUnwrap(s.selectionTransform);await settle(session)
    XCTAssertTrue(s.transformDraft?.selectedPixels == true);XCTAssertNotNil(session.pixelPreview);XCTAssertNil(session.error)
    var draft=try XCTUnwrap(s.transformDraft);draft=draft.selectionApplying(.translation(3,2));s.updateTransform(draft);await settle(session);XCTAssertNotNil(session.pixelPreview);XCTAssertTrue(s.document==original);XCTAssertTrue(s.previewDocument==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.selectedPixelTransformState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:SelectedPixelTransformAPI.stateSchema));XCTAssertEqual(s.selectedPixelTransformState["target"] as? String,"pixels")
    s.cancelTransform();XCTAssertTrue(session.closed);XCTAssertNil(s.selectionTransform);XCTAssertTrue(s.document==original)
    for depth in PixelDepth.allCases {
      var source=try fixture(depth);let bytes=(0..<(32*24)).map{i->UInt8 in let x=i%32,y=i/32;return x>=6 && x<18 && y>=5 && y<15 ? 128:0};source.setCoverageSelection(try SelectionMask(width:32,height:24,bytes:bytes))
      let unchanged=EditorStore(document:source,brushes:BrushLibrary());defer{unchanged.cancelTransform();unchanged.renderTask?.cancel()};unchanged.beginTransform();let draft=try XCTUnwrap(unchanged.transformDraft),operation=try XCTUnwrap(unchanged.selectionTransform)
      XCTAssertEqual(try draft.selectionProjection,.identity);unchanged.commitTransform();await operation.commitTask?.value;XCTAssertNil(operation.error);XCTAssertTrue(unchanged.document==source);XCTAssertTrue(unchanged.session.undoStack.isEmpty)
    }
  }
  @MainActor func testAll16ModifierModesAndFactoryBindingsRemainShared()async throws {
    let s=EditorStore(document:try fixture(),brushes:BrushLibrary());defer{s.cancelTransform();s.renderTask?.cancel()};s.beginTransform();let draft=try XCTUnwrap(s.transformDraft),flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for bits in 0..<16 {let f=flags.enumerated().reduce(NSEvent.ModifierFlags()){r,v in bits & (1<<v.offset) != 0 ? r.union(v.element):r},mode=draft.selectionMode(handle:4,modifiers:f)
      let next=draft.selectionDragging(handle:4,from:draft.handles[4],to:.init(x:20,y:16),mode:mode,shift:f.contains(.shift),option:f.contains(.option));XCTAssertNoThrow(try next.selectionProjection);XCTAssertTrue(next.selectedPixels)
      let canvas=CraftCanvas(store:s);canvas.updateCursorModifiers(f);XCTAssertNotEqual(canvas.toolCursor,.unavailable)
    }
    for mode in SelectionTransformMode.allCases{s.chooseSelectionTransformMode(mode);XCTAssertEqual(s.transformDraft?.selectionMode,mode)}
    let menus=PhotoshopMenuTests();try menus.withMenus{_,menu in for selector in [#selector(AppDelegate.freeTransform),#selector(AppDelegate.transformScaleMode),#selector(AppDelegate.transformRotateMode),#selector(AppDelegate.transformSkewMode),#selector(AppDelegate.transformDistortMode),#selector(AppDelegate.transformPerspectiveMode)]{XCTAssertNotNil(menus.allItems(menu).first{$0.action==selector})}}
  }
  @MainActor func testCommitUndoActions31AndImmediateSelectedFlip()async throws {
    let original=try fixture(),s=EditorStore(document:original,brushes:BrushLibrary());defer{s.cancelTransform();s.renderTask?.cancel()};s.beginTransform();let session=try XCTUnwrap(s.selectionTransform);var draft=try XCTUnwrap(s.transformDraft);draft=draft.selectionApplying(.translation(3,2));s.updateTransform(draft);try s.session.startActionRecording(name:"Pixels");s.commitTransform();await session.commitTask?.value
    XCTAssertNil(session.error);XCTAssertNil(s.transformDraft);XCTAssertEqual(s.session.undoStack.last?.label,"Free Transform");var file=ActionLibraryFile();file.actions=[try XCTUnwrap(s.session.actionRecording?.snapshot)];let data=try file.encoded();XCTAssertEqual(try ActionLibraryFile.decode(data).version,31)
    var replay=original;try file.actions[0].apply(to:&replay);XCTAssertTrue(replay==s.document);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
    s.transformLayer(horizontal:true);await s.geometryTask?.value;XCTAssertEqual(s.session.undoStack.last?.label,"Free Transform");XCTAssertNotEqual(s.document.layers,original.layers)
  }
  @MainActor func testHTTPDepthProfileAndInterpolationMatchNative()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let s=doc.store
      for depth in PixelDepth.allCases {var original=try self.fixture(depth);original.layers[0].mask=try Surface(width:32,height:24,fill:.white);original.workingICC=try ColorManagement.importedProfile(XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3)?.copyICCData() as Data?),depth:depth);s.session=EditorSession(document:original);try service.share(doc)
        for method in Resampling.allCases {s.session=EditorSession(document:original);let matrix=try ProjectiveTransform([1,0.05,2,0,1,1,0.002,0,1]);let status=try await h.edit(service,doc,"pixels.transform",["layerID":original.layers[0].id.uuidString,"matrix":matrix.values,"interpolation":method.rawValue]);XCTAssertEqual(status,200)
          var expected=original;try Command.transformPixels(.init(layerID:original.layers[0].id,matrix:matrix,interpolation:method)).apply(to:&expected);XCTAssertTrue(s.document==expected);XCTAssertEqual(s.document.workingICC,original.workingICC);XCTAssertEqual(s.document.depth,depth);XCTAssertEqual(s.document.layers[0].maskCoordinateTransform,original.layers[0].maskCoordinateTransform);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
        }
      }
    }
  }
  @MainActor func testInvalidBusyStaleRevokeAndNativeCancelBarrier()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try self.fixture(),s=doc.store;s.session=EditorSession(document:original);try service.share(doc);let params:[String:Any]=["layerID":original.layers[0].id.uuidString,"matrix":[1,0,2,0,1,1,0,0,1]]
      for extra:[String:Any] in [["matrix":[1,2]],["layerID":"bad"],["interpolation":"bad"],["matrix":[0,0,0,0,0,0,0,0,0]]] {let code=try await h.edit(service,doc,"pixels.transform",params.merging(extra){_,b in b});XCTAssertEqual(code,400);XCTAssertTrue(s.document==original)}
      let stale=try await h.edit(service,doc,"pixels.transform",params,revision:"old");XCTAssertEqual(stale,409);s.beginTransform();let busy=try await h.edit(service,doc,"pixels.transform",params);XCTAssertEqual(busy,409);s.cancelTransform()
      let gate=PixelTransformGate();s.selectedPixelTransformPreparation={_,request in gate.wait();try Task.checkCancellation();return .transformPixels(request)};let task=Task{try await h.edit(service,doc,"pixels.transform",params)};let until=Date().addingTimeInterval(10);while !s.geometryBusy && Date()<until{await Task.yield()};XCTAssertTrue(s.geometryBusy);service.revoke(try XCTUnwrap(service.shares.first?.id));gate.release();let code=try await task.value;XCTAssertEqual(code,409);XCTAssertTrue(s.document==original)
      let nativeGate=PixelTransformGate();s.selectedPixelTransformPreparation={_,request in nativeGate.wait();try Task.checkCancellation();return .transformPixels(request)};s.beginTransform();let session=try XCTUnwrap(s.selectionTransform);s.commitTransform();s.cancelTransform();nativeGate.release();await session.commitTask?.value;XCTAssertTrue(s.document==original);XCTAssertFalse(s.geometryBusy)
    }
  }
  @MainActor func testTargetLocksStaleReadAndCloseLifecycle()async throws {
    let doc=CraftNSDocument(model:try fixture()),s=doc.store;defer{s.cancelTransform();s.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()};var original=s.document;original.layers[0].mask=try Surface(width:32,height:24,fill:.white);s.session=EditorSession(document:original)
    s.pathTarget = .saved(UUID());XCTAssertFalse(s.canBeginSelectedPixelTransform);s.pathTarget=nil
    s.componentTarget = .red;XCTAssertFalse(s.canBeginSelectedPixelTransform);s.componentTarget = .composite;s.maskEditingLayerID=original.layers[0].id;XCTAssertFalse(s.canBeginSelectedPixelTransform);s.maskEditingLayerID=nil
    var locked=original;locked.layers[0].protection = .transparency;s.session=EditorSession(document:locked);XCTAssertFalse(s.canBeginSelectedPixelTransform);s.session=EditorSession(document:original)
    s.beginTransform();let stale=try XCTUnwrap(s.selectionTransform);try s.session.execute(.renameLayer(original.layers[0].id,"Changed"));s.commitTransform();await stale.commitTask?.value;XCTAssertNotNil(stale.error);s.cancelTransform()
    s.beginTransform();let reading=try XCTUnwrap(s.selectionTransform);try doc.read(from:NativeArchive.encodeChunked(original),ofType:CraftNSDocument.nativeType);XCTAssertTrue(reading.closed);XCTAssertNil(s.selectionTransform)
    s.beginTransform();let closing=try XCTUnwrap(s.selectionTransform);doc.close();XCTAssertTrue(closing.closed)
  }
  func testBoundedPreviewProxyDoesNotChangeOriginal()async throws {
    var original=try CraftDocument(width:4096,height:2048);original.selection = .init(x:1000,y:500,width:512,height:512);let source=original
    let proxy=try await Task.detached{try SelectedPixelTransformPreviewSource.prepare(source)}.value
    XCTAssertEqual(proxy.document.width,1024);XCTAssertEqual(proxy.document.height,512);XCTAssertEqual(source.width,4096);XCTAssertEqual(source.selection,original.selection)
    let image=try await Task.detached{try proxy.image(layerID:source.layers[0].id,matrix:.init(.translation(200,100)),interpolation:.bilinear)}.value;XCTAssertEqual(image.image.width,1024);XCTAssertEqual(image.image.height,512)
  }
}
