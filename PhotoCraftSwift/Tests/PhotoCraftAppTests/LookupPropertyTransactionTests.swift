import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LookupPropertyTransactionTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:24,height:16,depth:depth)
    d.layers[0].content = .raster(try Surface(width:24,height:16,depth:depth,fill:Pixel(0.25,0.5,0.75)))
    var layer=try ColorLookupAdjustment().layer(in:d)
    layer.mask=try Surface(width:24,height:16,depth:depth,fill:Pixel(0.7,0.7,0.7));layer.opacity=0.8
    layer.maskProperties = .init();layer.maskProperties!.density=0.65;layer.maskProperties!.feather=1
    d.layers.append(layer);d.activeLayerID=layer.id;return d
  }
  func value()throws->ColorLookupAdjustment {try ColorLookupWorkflowTests().fixture().1}
  @MainActor func testNativePreparedPropertyMatchesSynchronousReferenceAcrossDepthsAndMaskTargets()async throws {
    for depth in PixelDepth.allCases {for maskTarget in [false,true]{
      let original=try fixture(depth),id=try XCTUnwrap(original.activeLayerID),value=try value()
      var expected=original;try Command.replaceContent(id,.adjustment(.colorLookup(value))).apply(to:&expected)
      let s=EditorStore(document:original,actions:ActionLibrary(),brushes:BrushLibrary())
      defer{s.geometryTask?.cancel();s.renderTask?.cancel()}
      s.maskEditingLayerID=maskTarget ? id:nil;var changes=0;s.onChange={_ in changes+=1}
      s.setColorLookup(id,value)
      XCTAssertTrue(s.geometryBusy);XCTAssertEqual(s.document,original);XCTAssertEqual(changes,0)
      await s.geometryTask?.value
      XCTAssertNil(s.error);XCTAssertFalse(s.geometryBusy);XCTAssertEqual(s.document,expected)
      XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(changes,1)
      XCTAssertEqual(s.maskEditingLayerID,maskTarget ? id:nil)
      XCTAssertEqual(try NativeArchive.encodeChunked(s.document),try NativeArchive.encodeChunked(expected))
      XCTAssertEqual(try Renderer.composite(s.document),try Renderer.composite(expected))
      let undone=await s.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(s.document,original)
      let redone=await s.requestHistory(redo:true).value;XCTAssertTrue(redone);XCTAssertEqual(s.document,expected)
    }}
  }
  @MainActor func testCancelAndStaleSessionDiscardPreparedEditWithoutDirtyOrHistory()async throws {
    for kind in ["cancel","session","lifecycle"]{
      let original=try fixture(),id=try XCTUnwrap(original.activeLayerID),s=EditorStore(document:original,actions:ActionLibrary())
      defer{s.geometryTask?.cancel();s.renderTask?.cancel()};var changes=0;s.onChange={_ in changes+=1}
      s.setColorLookup(id,try value());XCTAssertTrue(s.geometryBusy)
      var expected=original
      if kind=="cancel"{s.geometryTask?.cancel()}
      if kind=="session"{expected.name="Replacement session";s.session=EditorSession(document:expected)}
      // Mirrors the native document close lifecycle: invalidate, cancel and release busy state.
      if kind=="lifecycle"{s.layerPanelGeneration=UUID();s.geometryTask?.cancel();s.geometryBusy=false}
      await s.geometryTask?.value
      XCTAssertEqual(s.document,expected,kind);XCTAssertTrue(s.session.undoStack.isEmpty,kind)
      XCTAssertEqual(changes,0,kind);XCTAssertFalse(s.geometryBusy,kind)
    }
  }
  @MainActor func testLockedInvalidAndWrongKindRemainAtomic()async throws {
    for kind in ["locked","invalid","wrongKind","missing"]{
      var original=try fixture();let id=try XCTUnwrap(original.activeLayerID);var value=try value()
      if kind=="locked"{original.layers[1].locked=true}
      if kind=="wrongKind"{original.layers[1].content = .adjustment(.exposure(1))}
      if kind=="invalid"{value.lut!.values[0] = .nan}
      let s=EditorStore(document:original,actions:ActionLibrary());defer{s.geometryTask?.cancel();s.renderTask?.cancel()}
      s.setColorLookup(kind=="missing" ? UUID():id,value);await s.geometryTask?.value
      XCTAssertEqual(s.document,original,kind);XCTAssertTrue(s.session.undoStack.isEmpty,kind);XCTAssertFalse(s.geometryBusy)
      if kind=="locked" || kind=="invalid"{XCTAssertNotNil(s.error)}
    }
  }
  @MainActor func testBusyModalTransformAndComponentTargetsRejectWithoutChangingContent()async throws {
    for kind in ["busy","modal","transform","component"]{
      var original=try fixture();let id=try XCTUnwrap(original.activeLayerID)
      if kind=="transform"{original.activeLayerID=original.layers[0].id}
      let s=EditorStore(document:original,actions:ActionLibrary());defer{s.geometryTask?.cancel();s.renderTask?.cancel()}
      if kind=="busy"{s.geometryBusy=true}
      if kind=="modal"{s.beginFileInfo();XCTAssertTrue(s.hasToneDraft)}
      if kind=="transform"{s.beginTransform();XCTAssertNotNil(s.transformDraft)}
      if kind=="component"{try s.selectEditingChannel(.red)}
      s.setColorLookup(id,try value());await s.geometryTask?.value
      XCTAssertEqual(s.document,original,kind);XCTAssertTrue(s.session.undoStack.isEmpty,kind)
      if kind=="transform"{XCTAssertEqual(s.error,"Apply or cancel Free Transform before another edit.")}
      if kind=="component"{XCTAssertNotNil(s.error)}
      if kind != "busy"{XCTAssertFalse(s.geometryBusy,kind)}
    }
  }
  @MainActor func testBusySecondEditAndNoOpDoNotCreateExtraHistory()async throws {
    let original=try fixture(),id=try XCTUnwrap(original.activeLayerID),s=EditorStore(document:original,actions:ActionLibrary())
    defer{s.geometryTask?.cancel();s.renderTask?.cancel()};let value=try value()
    s.setColorLookup(id,value);let first=s.geometryTask;s.setColorLookup(id,.init());await first?.value
    XCTAssertEqual(s.activeLayer?.content,.adjustment(.colorLookup(value)));XCTAssertEqual(s.session.undoStack.count,1)
    s.setColorLookup(id,value);await s.geometryTask?.value;XCTAssertEqual(s.session.undoStack.count,1)
    s.setColorLookup(id,.init());await s.geometryTask?.value;XCTAssertEqual(s.activeLayer?.content,original.layers[1].content);XCTAssertEqual(s.session.undoStack.count,2)
  }
  @MainActor func testActionRecordingRetainsEmbeddedLookupAndPortableVersion()async throws {
    let original=try fixture(),id=try XCTUnwrap(original.activeLayerID),s=EditorStore(document:original,actions:ActionLibrary())
    defer{s.geometryTask?.cancel();s.renderTask?.cancel()};try s.startRecordingAction(name:"Owned lookup properties",set:"Owned")
    s.setColorLookup(id,try value());await s.geometryTask?.value
    XCTAssertNil(s.error);let action=try s.stopRecordingAction(save:false);XCTAssertEqual(action.steps.count,1)
    var file=ActionLibraryFile();file.actions=[action];XCTAssertEqual(file.requiredVersion,3);XCTAssertEqual(ActionLibraryFile.maximumVersion,61)
    XCTAssertEqual(s.session.undoStack.count,1)
  }
  @MainActor func testHTTPSetAndNativeShareExactOutputAndHistoryAcrossDepths()async throws {
    let helper=AutomationTests(),value=ColorLookupAdjustment(lut:try ColorLUTPreset.warm.makeLUT(),dither:false)
    for depth in PixelDepth.allCases{
      let original=try fixture(depth),id=try XCTUnwrap(original.activeLayerID),s=EditorStore(document:original,actions:ActionLibrary())
      defer{s.geometryTask?.cancel();s.renderTask?.cancel()};s.setColorLookup(id,value);await s.geometryTask?.value;XCTAssertNil(s.error)
      try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,document in
        document.store.session=EditorSession(document:original);try service.share(document)
        let parameters:[String:Any]=["layerID":id.uuidString,"adjustment":["kind":"colorLookup","preset":"warm","dither":false]]
        let result=try await helper.edit(service,document,"adjustment.set",parameters);XCTAssertEqual(result,200)
        XCTAssertEqual(document.store.document,s.document);XCTAssertEqual(document.store.session.undoStack.count,1)
        XCTAssertEqual(try NativeArchive.encodeChunked(document.store.document),try NativeArchive.encodeChunked(s.document))
        let undone=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undone,200);XCTAssertEqual(document.store.document,original)
        let redone=try await helper.edit(service,document,"history.redo");XCTAssertEqual(redone,200);XCTAssertEqual(document.store.document,s.document)
      }
    }
  }
  @MainActor func testHTTPStaleBusyLockedInvalidAndPreparationMetadata()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let original=try fixture(),id=try XCTUnwrap(original.activeLayerID)
      document.store.session=EditorSession(document:original);try service.share(document)
      let parameters:[String:Any]=["layerID":id.uuidString,"adjustment":["kind":"colorLookup","preset":"warm"]]
      let stale=try await helper.edit(service,document,"adjustment.set",parameters,revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"adjustment.set",parameters);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let invalid=try await helper.edit(service,document,"adjustment.set",["layerID":id.uuidString,"adjustment":["kind":"colorLookup","dither":1]]);XCTAssertEqual(invalid,400)
      XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      var locked=original;locked.layers[1].locked=true;document.store.session=EditorSession(document:locked)
      let rejected=try await helper.edit(service,document,"adjustment.set",parameters);XCTAssertEqual(rejected,422);XCTAssertEqual(document.store.document,locked)
      XCTAssertNotNil(AutomationService.colorLookupCapabilities["propertyPreparation"])
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationService.colorLookupCapabilities))
      XCTAssertEqual(AutomationCommand.definitions.count,267)
    }
  }
}
