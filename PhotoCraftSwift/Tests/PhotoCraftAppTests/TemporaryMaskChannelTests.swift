import AppKit
import SwiftUI
import ImageIO
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class TemporaryMaskChannelTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var (d,id)=try MaskTargetLifecycleWorkflowTests().fixture()
    let i=try XCTUnwrap(d.layers.firstIndex{$0.id==id})
    d.layers[i].mask=try Surface(width:8,height:8,depth:depth,fill:.black)
    d.layers[i].smartFilters?.mask=try Surface(width:8,height:8,depth:depth,fill:.black)
    return d
  }
  @MainActor func picture(_ s:EditorStore)throws->CGImage {
    try AuxiliaryChannelPresentation.image(Surface(width:s.document.width,height:s.document.height,fill:.black),document:s.document,view:s.channelPreviewView,colorManaged:false,
      request:.init(region:.init(x:0,y:0,width:2,height:2),width:2,height:2))
  }
  @MainActor func testRowsRemainAvailableWithImageAndEachMaskTarget()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()}
    let rows=s.temporaryMaskChannels;XCTAssertEqual(rows.count,2);XCTAssertFalse(rows[0].smartFilter);XCTAssertTrue(rows[1].smartFilter)
    let original=s.document
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let file=CraftNSDocument(model:original);defer{file.store.renderTask?.cancel();file.close()}
      try file.data(ofType:CraftNSDocument.nativeType).write(to:URL(fileURLWithPath:path).appendingPathComponent("owned-mask-channels.photato"))
    }
    for target in rows {try s.selectTemporaryMaskChannel(target);XCTAssertEqual(s.selectedMaskPaintTarget,target);XCTAssertEqual(s.temporaryMaskChannels,rows);XCTAssertTrue(s.visibleTemporaryMaskChannels.isEmpty);XCTAssertTrue(s.colorChannelsVisible)}
    try s.selectEditingChannel(.composite);XCTAssertNil(s.selectedMaskPaintTarget);XCTAssertEqual(s.temporaryMaskChannels,rows)
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testFilterOnlyTargetNeverInventsPixelMaskRowAndVectorStaysInPaths()throws {
    var d=try fixture();d.layers[d.layers.count-1].mask=nil
    let s=EditorStore(document:d);defer{s.renderTask?.cancel()}
    let target=try XCTUnwrap(s.temporaryMaskChannels.first);XCTAssertTrue(target.smartFilter);XCTAssertEqual(s.temporaryMaskChannels.count,1)
    try s.selectTemporaryMaskChannel(target);XCTAssertEqual(s.temporaryMaskChannels,[target]);XCTAssertEqual(s.selectedMaskPaintTarget,target)
    try s.setChannelEye(.mask(target),visible:true);XCTAssertEqual(s.visibleTemporaryMaskChannels,[target])
    let owner=try XCTUnwrap(s.document.layers.first{$0.id==target.layerID});XCTAssertNil(owner.mask)
    let vector=try MaskInteractionTests().fixture();defer{vector.renderTask?.cancel()}
    var vectorOnly=vector.document;vectorOnly.layers[0].mask=nil
    let v=EditorStore(document:vectorOnly);defer{v.renderTask?.cancel()}
    XCTAssertNotNil(v.document.layers[0].vectorMask);XCTAssertTrue(v.temporaryMaskChannels.isEmpty)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let file=CraftNSDocument(model:d);defer{file.store.renderTask?.cancel();file.close()}
      try file.data(ofType:CraftNSDocument.nativeType).write(to:URL(fileURLWithPath:path).appendingPathComponent("owned-filter-only.photato"))
    }
  }
  @MainActor func testIndependentMaskEyesLiteralBytesAndGrayWithoutRetargeting()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()};let targets=s.temporaryMaskChannels,original=s.document
    let reader=IndependentChannelVisibilityTests()
    try s.setChannelEye(.mask(targets[0]),visible:true)
    try reader.pixel(picture(s),[128,0,0,255],file:"temporary-mask-one.bin")
    try s.setChannelEye(.mask(targets[1]),visible:true)
    try reader.pixel(picture(s),[192,0,0,255],file:"temporary-mask-two.bin")
    XCTAssertNil(s.selectedMaskPaintTarget);XCTAssertNil(s.editingChannel)
    try s.setColorChannelsVisibility(false);try s.setChannelEye(.mask(targets[1]),visible:false)
    try reader.pixel(picture(s),[0,0,0,255],file:"temporary-mask-gray.bin")
    XCTAssertEqual(s.channelVisibilityState["grayscale"] as? Bool,true)
    try s.setChannelEye(.mask(targets[0]),visible:false);try reader.pixel(picture(s),[0,0,0,0])
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testMaskRowSelectionKeepsIndependentViewAndPalette()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()};let targets=s.temporaryMaskChannels
    try s.setChannelEye(.mask(targets[0]),visible:true);try s.setColorChannelsVisibility(false)
    let view=s.channelPreviewView
    for target in targets {try s.selectTemporaryMaskChannel(target);XCTAssertEqual(s.channelPreviewView,view);XCTAssertEqual(s.paintColorContext,.mask);XCTAssertEqual(s.selectedMaskPaintTarget,target)}
    let colors=s.activePaintColorPair
    try s.setChannelEye(.mask(targets[1]),visible:true);XCTAssertEqual(s.selectedMaskPaintTarget,targets[1]);XCTAssertEqual(s.activePaintColorPair,colors)
    try s.selectEditingChannel(.composite);XCTAssertTrue(s.visibleTemporaryMaskChannels.isEmpty);XCTAssertTrue(s.colorChannelsVisible);XCTAssertEqual(s.paintColorContext,.image)
  }
  @MainActor func testImageAndFilterMaskPaintWithSharedUndoDoNotMixPlanes()async throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()};let targets=s.temporaryMaskChannels,before=s.document
    try s.selectTemporaryMaskChannel(targets[1]);s.fill(color:.white);await s.renderTask?.value
    let stored=try XCTUnwrap(s.document.layers.first{$0.id==targets[1].layerID})
    XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(stored.mask,before.layers.last?.mask)
    XCTAssertNotEqual(stored.smartFilters?.mask,before.layers.last?.smartFilters?.mask)
    XCTAssertEqual(stored.content,before.layers.last?.content)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"] {
      let folder=URL(fileURLWithPath:path)
      try XCTUnwrap(stored.mask).rgbaData(depth:.u8).write(to:folder.appendingPathComponent("temporary-mask-fill-layer.rgba"))
      try XCTUnwrap(stored.smartFilters?.mask).rgbaData(depth:.u8).write(to:folder.appendingPathComponent("temporary-mask-fill-filter.rgba"))
    }
    await s.undo();XCTAssertEqual(s.document,before)
    try s.selectTemporaryMaskChannel(targets[0]);s.fill(color:.white);await s.renderTask?.value
    let pixelOwner=try XCTUnwrap(s.document.layers.first{$0.id==targets[0].layerID})
    XCTAssertEqual(pixelOwner.smartFilters?.mask,before.layers.last?.smartFilters?.mask)
    XCTAssertNotEqual(pixelOwner.mask,before.layers.last?.mask);await s.undo();XCTAssertEqual(s.document,before)
  }
  @MainActor func testLegacyGrayEyeTransitionAndSweepCancellationRestoreCapturedView()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()};let target=s.temporaryMaskChannels[0]
    s.toggleMaskView(target.layerID,mode:.gray);let legacy=s.currentMaskView,original=s.document
    XCTAssertFalse(s.channelEyeVisible(.rgb(.red)));XCTAssertTrue(s.channelEyeVisible(.mask(target)))
    let noChange=s.revision;try s.setChannelEye(.rgb(.blue),visible:false);XCTAssertEqual(s.revision,noChange);XCTAssertEqual(s.currentMaskView,legacy)
    let sweep=try XCTUnwrap(s.beginChannelVisibilitySweep(.rgb(.red)))
    XCTAssertNil(s.currentMaskView);XCTAssertTrue(s.editingMask);XCTAssertEqual(s.visibleTemporaryMaskChannels,[target]);XCTAssertTrue(s.colorChannelsVisible)
    s.finishChannelVisibilitySweep(sweep,cancel:true);XCTAssertEqual(s.currentMaskView,legacy);XCTAssertFalse(s.colorChannelsVisible)
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testDeleteUndoReopenAndForeignLayerDoNotLeaveStaleEyes()async throws {
    let d=try fixture(),file=CraftNSDocument(model:d),s=file.store;defer{s.renderTask?.cancel();file.close()}
    let target=s.temporaryMaskChannels[0];try s.setChannelEye(.mask(target),visible:true);s.perform(.deleteMask(target.layerID));XCTAssertFalse(s.temporaryMaskChannels.contains(target));XCTAssertFalse(s.isTemporaryMaskVisible(target))
    await s.undo();XCTAssertTrue(s.isTemporaryMaskVisible(target))
    let bytes=try file.data(ofType:CraftNSDocument.nativeType);try file.read(from:bytes,ofType:CraftNSDocument.nativeType)
    XCTAssertTrue(s.visibleTemporaryMaskChannels.isEmpty);XCTAssertEqual(s.temporaryMaskChannels.count,2)
    try s.setChannelEye(.mask(target),visible:true);s.select(d.layers[0].id);XCTAssertTrue(s.temporaryMaskChannels.isEmpty);XCTAssertTrue(s.visibleTemporaryMaskChannels.isEmpty)
    s.select(target.layerID);XCTAssertTrue(s.visibleTemporaryMaskChannels.isEmpty)
  }
  @MainActor func testBusyInvalidAndNoopRequestsAreAtomic()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()};let target=s.temporaryMaskChannels[0],before=s.document,revision=s.revision
    try s.setChannelEye(.mask(target),visible:false);XCTAssertEqual(s.revision,revision)
    XCTAssertThrowsError(try s.setChannelEye(.mask(.init(layerID:UUID(),smartFilter:false)),visible:true));XCTAssertEqual(s.revision,revision)
    s.geometryBusy=true;XCTAssertThrowsError(try s.setChannelEye(.mask(target),visible:true));XCTAssertThrowsError(try s.selectTemporaryMaskChannel(target));s.geometryBusy=false
    XCTAssertEqual(s.document,before);XCTAssertNil(s.selectedMaskPaintTarget);XCTAssertTrue(s.visibleTemporaryMaskChannels.isEmpty)
  }
  @MainActor func testFactoryBackslashAllModifiersAndRepeatDoNotSelectMask()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()};let before=s.document
    for bits in 0..<16 {
      var flags:NSEvent.ModifierFlags=[]
      for (i,f)in [NSEvent.ModifierFlags.control,.command,.option,.shift].enumerated()where bits&(1<<i) != 0{flags.insert(f)}
      let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:"\\",charactersIgnoringModifiers:"\\",isARepeat:false,keyCode:42))
      XCTAssertEqual(s.handleComponentShortcut(event),bits==0)
      XCTAssertEqual(s.visibleTemporaryMaskChannels.count,1);XCTAssertNil(s.selectedMaskPaintTarget)
    }
    let repeatEvent=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\\",charactersIgnoringModifiers:"\\",isARepeat:true,keyCode:42))
    XCTAssertTrue(s.handleComponentShortcut(repeatEvent));XCTAssertEqual(s.visibleTemporaryMaskChannels,[s.temporaryMaskChannels[0]])
    XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testNativeMaskEyeAllSixteenModifiersRetainImageTarget()throws {
    let helper=ChannelEyeControlTests(),(s,window,tracking,first,second)=try helper.setup()
    s.session=EditorSession(document:try fixture());let targets=s.temporaryMaskChannels
    first.channel = .mask(targets[0]);second.channel = .mask(targets[1])
    defer{tracking.cancel();s.renderTask?.cancel();window.close()}
    for bits in 0..<16 {
      var flags:NSEvent.ModifierFlags=[]
      for(i,f)in [NSEvent.ModifierFlags.control,.command,.option,.shift].enumerated()where bits&(1<<i) != 0{flags.insert(f)}
      first.mouseDown(with:try helper.event(.leftMouseDown,.init(x:13,y:96),window,flags))
      first.mouseUp(with:try helper.event(.leftMouseUp,.init(x:13,y:96),window,flags))
      XCTAssertEqual(s.isTemporaryMaskVisible(targets[0]),bits%2==0);XCTAssertNil(s.selectedMaskPaintTarget)
    }
    first.mouseDown(with:try helper.event(.leftMouseDown,.init(x:13,y:96),window))
    tracking.drag(try helper.event(.leftMouseDragged,.init(x:13,y:46),window));XCTAssertEqual(s.visibleTemporaryMaskChannels,targets)
    first.cancelOperation(nil);XCTAssertTrue(s.visibleTemporaryMaskChannels.isEmpty);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testRawMaskGrayIgnoresDensityFeatherEnabledAndRetainsStoredDepth()throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth);let i=d.layers.count-1
      d.layers[i].mask=try Surface(width:8,height:8,depth:depth,fill:Pixel(0.5,0.5,0.5))
      var properties=d.layers[i].effectiveMaskProperties;properties.enabled=false;properties.density=0;properties.feather=3;d.layers[i].maskProperties=properties
      let s=EditorStore(document:d);defer{s.renderTask?.cancel()};try s.setChannelEye(.mask(s.temporaryMaskChannels[0]),visible:true);try s.setColorChannelsVisibility(false)
      try IndependentChannelVisibilityTests().pixel(picture(s),[128,128,128,255])
      XCTAssertEqual(s.activeLayer?.mask?.depth,depth);XCTAssertEqual(s.document,d)
    }
  }
  @MainActor func testMaximumLogicalMaskROIUsesBoundedRawProjection()throws {
    var d=try fixture();d.width=300000;d.height=300000
    let s=EditorStore(document:d);defer{s.renderTask?.cancel()};let t=s.temporaryMaskChannels[0]
    try s.setChannelEye(.mask(t),visible:true);try s.setColorChannelsVisibility(false)
    let image=try picture(s);XCTAssertEqual(image.width,2);XCTAssertEqual(image.height,2)
    try IndependentChannelVisibilityTests().pixel(image,[0,0,0,255]);XCTAssertEqual(s.document,d)
  }
  @MainActor func testLegacyGrayViewReportsQuickMaskHiddenAndEyesRestoreIndependently()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()}
    s.toggleQuickMask();XCTAssertTrue(s.isQuickMaskVisible)
    let target=s.temporaryMaskChannels[0];s.toggleMaskView(target.layerID,mode:.gray)
    XCTAssertFalse(s.isQuickMaskVisible);XCTAssertEqual(s.channelVisibilityState["quickMaskVisible"]as?Bool,false)
    XCTAssertTrue(s.channelPreviewView.targets.isEmpty)
    try s.setChannelEye(.rgb(.red),visible:true);XCTAssertNil(s.currentMaskView);XCTAssertFalse(s.isQuickMaskVisible)
    try s.setChannelEye(.quickMask,visible:true);XCTAssertTrue(s.isQuickMaskVisible);XCTAssertEqual(s.selectedMaskPaintTarget,target)
  }
  @MainActor func testHTTPSelectedFilterMaskFillChangesOnlyItsStoredPlaneWithOneUndo()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      let d=try self.fixture();file.store.session=EditorSession(document:d);try service.share(file)
      let id=try XCTUnwrap(d.activeLayerID)
      let select=try await helper.edit(service,file,"channel.view",["target":"smartFilterMask","layerID":id.uuidString]);XCTAssertEqual(select,200)
      let fill=try await helper.edit(service,file,"smartFilter.maskFill",["layerID":id.uuidString,"value":1.0]);XCTAssertEqual(fill,200)
      let layer=try XCTUnwrap(file.store.document.layers.first{$0.id==id})
      XCTAssertEqual(layer.mask,d.layers.last?.mask);XCTAssertEqual(layer.content,d.layers.last?.content)
      XCTAssertNotEqual(layer.smartFilters?.mask,d.layers.last?.smartFilters?.mask);XCTAssertEqual(file.store.session.undoStack.count,1)
      let undone=try await helper.edit(service,file,"history.undo");XCTAssertEqual(undone,200);XCTAssertEqual(file.store.document,d)
    }
  }
  @MainActor func testHTTPSelectedFilterMaskStrokeKeepsTargetAndRejectsStaleAndBusy()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      let d=try self.fixture();file.store.session=EditorSession(document:d);try service.share(file)
      let s=file.store,id=try XCTUnwrap(d.activeLayerID),target=MaskPaintTarget(layerID:id,smartFilter:true)
      try s.selectTemporaryMaskChannel(target)
      let parameters:[String:Any]=["layerID":id.uuidString,"points":[["x":3.0,"y":3.0]],"size":2.0,"hardness":1.0,"opacity":1.0,"value":1.0]
      let stale=try await helper.edit(service,file,"smartFilter.maskStroke",parameters,revision:"stale");XCTAssertEqual(stale,409)
      let sweep=try XCTUnwrap(s.beginChannelVisibilitySweep(.mask(target)))
      let busy=try await helper.edit(service,file,"smartFilter.maskStroke",parameters);XCTAssertEqual(busy,409);s.finishChannelVisibilitySweep(sweep,cancel:true)
      let painted=try await helper.edit(service,file,"smartFilter.maskStroke",parameters);XCTAssertEqual(painted,200)
      let owner=try XCTUnwrap(s.document.layers.first{$0.id==id});XCTAssertEqual(owner.mask,d.layers.last?.mask);XCTAssertNotEqual(owner.smartFilters?.mask,d.layers.last?.smartFilters?.mask)
      XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(s.selectedMaskPaintTarget,target)
      let undone=try await helper.edit(service,file,"history.undo");XCTAssertEqual(undone,200);XCTAssertEqual(s.document,d)
    }
  }
  @MainActor func testHTTPMaskEyesTargetsStatePreviewAndErrorsShareNativeBehavior()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      let d=try self.fixture();file.store.session=EditorSession(document:d);try service.share(file)
      let s=file.store,t=s.temporaryMaskChannels[0],share=try XCTUnwrap(service.shares.first),base="/v1/documents/\(share.id)"
      defer{s.renderTask?.cancel()}
      let archive=try file.data(ofType:CraftNSDocument.nativeType),plain=try await helper.request(service,path:base+"/preview.png")
      let show=try await helper.edit(service,file,"channel.view",["target":"layerMask","layerID":t.layerID.uuidString,"visible":true]);XCTAssertEqual(show,200);XCTAssertNil(s.selectedMaskPaintTarget)
      let revision=service.revision(s)
      let noop=try await helper.edit(service,file,"channel.view",["target":"layerMask","layerID":t.layerID.uuidString,"visible":true]);XCTAssertEqual(noop,200);XCTAssertEqual(service.revision(s),revision)
      let selected=try await helper.edit(service,file,"channel.view",["target":"smartFilterMask","layerID":t.layerID.uuidString]);XCTAssertEqual(selected,200);XCTAssertTrue(s.smartFilterMaskEditing);XCTAssertEqual(s.visibleTemporaryMaskChannels,[t])
      let state=service.state(share,document:file),view=try XCTUnwrap(state["auxiliaryVisibility"]as?[String:Any]),rows=try XCTUnwrap(view["temporaryMaskChannels"]as?[[String:Any]])
      XCTAssertEqual(rows.count,2);XCTAssertEqual(rows[0]["visible"]as?Bool,true);XCTAssertEqual(rows[1]["selected"]as?Bool,true)
      let shown=try await helper.request(service,path:base+"/channel-preview.png")
      XCTAssertEqual(shown.1,try AutomationService.png(d,auxiliaryView:s.channelPreviewView))
      let unmodified=try await helper.request(service,path:base+"/preview.png");XCTAssertEqual(unmodified.1,plain.1)
      XCTAssertEqual(try file.data(ofType:CraftNSDocument.nativeType),archive);XCTAssertTrue(s.session.undoStack.isEmpty)
      for (parameters,status)in [(["target":"layerMask","layerID":t.layerID.uuidString,"visible":"true"]as[String:Any],400),(["target":"layerMask","layerID":UUID().uuidString,"visible":true],404),(["target":"layerMask","layerID":d.layers[0].id.uuidString,"visible":true],422),(["target":"layerMask","layerID":t.layerID.uuidString,"overlay":true],400)] {
        let result=try await helper.edit(service,file,"channel.view",parameters);XCTAssertEqual(result,status)
      }
      let stale=try await helper.edit(service,file,"channel.view",["target":"layerMask","layerID":t.layerID.uuidString,"visible":false],revision:"stale");XCTAssertEqual(stale,409)
      let sweep=try XCTUnwrap(s.beginChannelVisibilitySweep(.mask(t)))
      let busy=try await helper.edit(service,file,"channel.view",["target":"layerMask","layerID":t.layerID.uuidString,"visible":true]);XCTAssertEqual(busy,409);s.finishChannelVisibilitySweep(sweep,cancel:true)
    }
  }
}
