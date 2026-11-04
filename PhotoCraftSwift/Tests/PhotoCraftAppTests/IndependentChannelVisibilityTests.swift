import AppKit
import ImageIO
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class IndependentChannelVisibilityTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var document=try CraftDocument(width:4,height:3,depth:depth)
    document.layers[0].content = .raster(try Surface(width:4,height:3,depth:depth,fill:.black))
    var red=ChannelDisplayOptions();red.color=Pixel(1,0,0);red.opacity=0.5
    var green=red;green.color=Pixel(0,1,0)
    document.alphaChannels=[AlphaChannel(name:"Red mask",pixels:try Surface(width:4,height:3,depth:depth,fill:.black),options:red),AlphaChannel(name:"Green mask",pixels:try Surface(width:4,height:3,depth:depth,fill:.black),options:green)]
    return document
  }
  func pixel(_ image:CGImage,_ expected:[UInt8],file:String?=nil)throws {
    let surface=try RasterIO.surface(image)
    let p=surface.pixel(x:0,y:0)
    XCTAssertEqual([p.r,p.g,p.b,p.a].map{UInt8((unit($0)*255).rounded())},expected)
    if let file,let directory=ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"] {
      var data=Data()
      for y in 0..<surface.height {for x in 0..<surface.width {let p=surface.pixel(x:x,y:y);data.append(contentsOf:[p.r,p.g,p.b,p.a].map{UInt8((unit($0)*255).rounded())})}}
      try data.write(to:URL(fileURLWithPath:directory).appendingPathComponent(file))
    }
  }
  @MainActor func image(_ store:EditorStore)throws->CGImage {
    try AuxiliaryChannelPresentation.image(Renderer.composite(store.document),document:store.document,view:store.auxiliaryChannelView,
      request:RasterPreviewRequest(region:.init(x:0,y:0,width:2,height:2),width:2,height:2))
  }
  @MainActor func testEyesPreserveTargetDirtyHistoryArchiveAndRenderIndependentWords()async throws {
    let file=CraftNSDocument(model:try fixture());defer{file.store.renderTask?.cancel();file.close()}
    let store=file.store,original=store.document,bytes=try file.data(ofType:CraftNSDocument.nativeType)
    let ids=try XCTUnwrap(original.alphaChannels).map(\.id)
    try store.setAlphaVisibility(ids[0],true);try store.setAlphaVisibility(ids[1],true)
    await store.renderTask?.value
    XCTAssertNil(store.editingChannel);XCTAssertEqual(store.componentTarget,.composite);XCTAssertEqual(store.visibleAlphaIDs,Set(ids))
    XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertFalse(file.isDocumentEdited)
    XCTAssertEqual(try file.data(ofType:CraftNSDocument.nativeType),bytes)
    try pixel(image(store),[64,128,0,255],file:"visibility-black-rg.bin")
    let revision=store.revision;try store.setAlphaVisibility(ids[1],true);XCTAssertEqual(store.revision,revision)
  }
  @MainActor func testSingleGrayMultipleOverWhiteAndTransparentViewKeepSelectedTarget()throws {
    let store=EditorStore(document:try fixture());defer{store.renderTask?.cancel()}
    let ids=try XCTUnwrap(store.document.alphaChannels).map(\.id)
    try store.selectAlphaChannel(ids[0]);try pixel(image(store),[0,0,0,255]);XCTAssertFalse(store.colorChannelsVisible)
    try store.setAlphaVisibility(ids[1],true)
    try pixel(image(store),[128,192,64,255],file:"visibility-white-rg.bin")
    try store.setAlphaVisibility(ids[0],false);XCTAssertEqual(store.editingChannel,.alpha(ids[0]));try pixel(image(store),[0,0,0,255])
    try store.setAlphaVisibility(ids[1],false);try pixel(image(store),[0,0,0,0]);XCTAssertTrue(store.auxiliaryChannelView.targets.isEmpty)
    try store.setColorChannelsVisibility(true);XCTAssertEqual(store.editingChannel,.alpha(ids[0]));try pixel(image(store),[0,0,0,255])
  }
  @MainActor func testComponentEyesRetainMasksButImageRowSelectionClearsThem()throws {
    let store=EditorStore(document:try fixture());defer{store.renderTask?.cancel()}
    let id=try XCTUnwrap(store.document.alphaChannels?.first?.id)
    try store.selectAlphaChannel(id)
    try store.setChannelEye(.rgb(.red),visible:true);XCTAssertEqual(store.channelView.visible,[.red]);XCTAssertEqual(store.editingChannel,.alpha(id))
    try store.setChannelEye(.rgb(.green),visible:true);XCTAssertEqual(store.channelView.visible,[.red,.green])
    try store.setChannelEye(.rgb(.red),visible:false);XCTAssertEqual(store.channelView.visible,[.green])
    try store.setChannelEye(.rgb(.green),visible:false);XCTAssertFalse(store.colorChannelsVisible);XCTAssertTrue(store.isAlphaVisible(id))
    try store.setColorChannelsVisibility(true);XCTAssertEqual(store.channelView.visible,RGBChannelView.components)
    try store.selectEditingChannel(.blue);XCTAssertNil(store.editingChannel);XCTAssertFalse(store.isAlphaVisible(id));XCTAssertTrue(store.colorChannelsVisible)
    XCTAssertEqual(store.componentTarget,.blue)
  }
  @MainActor func testVisibleMasksDoNotRetargetImageBrushOrUndo()async throws {
    let store=EditorStore(document:try fixture());defer{store.renderTask?.cancel()};let before=store.document
    let ids=try XCTUnwrap(before.alphaChannels).map(\.id)
    for id in ids {try store.setAlphaVisibility(id,true)}
    var brush=Brush();brush.size=2;brush.hardness=1;brush.color = .white
    store.stroke([.init(x:1,y:1)],brush:brush)
    XCTAssertEqual(store.session.undoStack.count,1);XCTAssertNotEqual(store.document.layers,before.layers)
    XCTAssertEqual(store.document.alphaChannels,before.alphaChannels);XCTAssertNil(store.editingChannel)
    await store.undo();XCTAssertEqual(store.document,before);XCTAssertEqual(store.visibleAlphaIDs,Set(ids))
  }
  @MainActor func testModeEyesRetainAuxiliaryTargetAndRawDocumentAtAllModes()throws {
    for mode in DocumentColorMode.componentModes {
      var document=try DocumentCreation.blank(width:4,height:3,depth:.u16,background:.white,mode:mode)
      document.alphaChannels=try fixture(.u16).alphaChannels
      let store=EditorStore(document:document);defer{store.renderTask?.cancel()}
      let id=try XCTUnwrap(document.alphaChannels?.first?.id);try store.selectAlphaChannel(id)
      try store.setModeComponentVisibility([0]);XCTAssertEqual(store.modeVisibleComponents,[0]);XCTAssertEqual(store.editingChannel,.alpha(id))
      try store.setModeComponentVisibility([]);XCTAssertFalse(store.colorChannelsVisible);XCTAssertEqual(store.modeVisibleComponents,[])
      try store.setChannelEye(.mode(nil),visible:true);XCTAssertEqual(store.modeVisibleComponents,Set(0..<mode.componentCount))
      XCTAssertEqual(store.document,document);XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testQuickMaskAndSeveralSavedMasksCanRemainVisibleWhileImageIsEdited()throws {
    var document=try fixture();document.selection = .init(x:3,y:2,width:1,height:1)
    let store=EditorStore(document:document);let defaults=store.quickMaskOptions
    defer{store.quickMaskOptions=defaults;store.renderTask?.cancel()}
    var options=ChannelDisplayOptions();options.color=Pixel(0,0,1);options.opacity=0.5;store.quickMaskOptions=options
    store.toggleQuickMask();let before=store.document,history=store.session.undoStack.count
    let ids=try XCTUnwrap(document.alphaChannels).map(\.id)
    for id in ids {try store.setAlphaVisibility(id,true)}
    XCTAssertEqual(store.editingChannel,.quickMask);XCTAssertEqual(store.auxiliaryChannelView.targets.count,3)
    try pixel(image(store),[32,64,128,255],file:"visibility-quick-blue.bin")
    try store.selectEditingChannel(.composite);XCTAssertNil(store.editingChannel);XCTAssertTrue(store.isQuickMaskVisible)
    XCTAssertTrue(store.visibleAlphaIDs.isEmpty);XCTAssertEqual(store.document,before);XCTAssertEqual(store.session.undoStack.count,history)
    for id in ids {try store.setAlphaVisibility(id,true)}
    try store.setQuickMaskVisibility(false);XCTAssertEqual(store.visibleAlphaIDs,Set(ids));try pixel(image(store),[64,128,0,255])
  }
  @MainActor func testChannelOrderDeleteAndUndoRetainVisibilityMemory()async throws {
    let store=EditorStore(document:try fixture());defer{store.renderTask?.cancel()}
    let ids=try XCTUnwrap(store.document.alphaChannels).map(\.id)
    for id in ids {try store.setAlphaVisibility(id,true)}
    store.perform(.channel(.move(ids[0],1)))
    XCTAssertEqual(store.auxiliaryChannelView.targets,[.alpha(ids[1]),.alpha(ids[0])])
    try pixel(image(store),[128,64,0,255],file:"visibility-black-gr.bin")
    store.perform(.channel(.delete(ids[0])));XCTAssertEqual(store.visibleAlphaIDs,[ids[1]])
    await store.undo();XCTAssertEqual(store.visibleAlphaIDs,Set(ids));await store.undo()
    XCTAssertEqual(store.auxiliaryChannelView.targets,ids.map{.alpha($0)})
  }
  @MainActor func testVisibilityIsDocumentLocalAndResetsOnReopenAndReplacement()throws {
    let original=try fixture(),file=CraftNSDocument(model:original),other=EditorStore(document:original)
    defer{file.store.renderTask?.cancel();other.renderTask?.cancel();file.close()}
    let id=try XCTUnwrap(original.alphaChannels?.first?.id);try file.store.setAlphaVisibility(id,true)
    XCTAssertTrue(other.visibleAlphaIDs.isEmpty)
    let bytes=try file.data(ofType:CraftNSDocument.nativeType);try file.read(from:bytes,ofType:CraftNSDocument.nativeType)
    XCTAssertTrue(file.store.visibleAlphaIDs.isEmpty);XCTAssertTrue(file.store.colorChannelsVisible)
    try file.store.setAlphaVisibility(id,true)
    var replacement=original;replacement.id=UUID();file.store.session=EditorSession(document:replacement)
    XCTAssertTrue(file.store.visibleAlphaIDs.isEmpty);XCTAssertTrue(file.store.colorChannelsVisible)
  }
  @MainActor func testLayerMaskTargetAndPaletteSurviveEyeChanges()throws {
    var document=try fixture();document.layers[0].mask=try Surface(width:4,height:3,fill:.white)
    let store=EditorStore(document:document);defer{store.renderTask?.cancel()};store.selectMask(document.layers[0].id)
    let target=store.selectedMaskPaintTarget,colors=store.activePaintColorPair
    let id=try XCTUnwrap(document.alphaChannels?.first?.id);try store.setAlphaVisibility(id,true);try store.setColorChannelsVisibility(false)
    XCTAssertEqual(store.selectedMaskPaintTarget,target);XCTAssertEqual(store.activePaintColorPair,colors)
    XCTAssertTrue(store.editingMask);XCTAssertEqual(store.document,document)
  }
  @MainActor func testBusyInvalidAndSweepCancellationAreAtomicAndIdempotent()throws {
    let store=EditorStore(document:try fixture());defer{store.renderTask?.cancel()};let original=store.document
    let ids=try XCTUnwrap(original.alphaChannels).map(\.id)
    XCTAssertThrowsError(try store.setAlphaVisibility(UUID(),true));XCTAssertTrue(store.visibleAlphaIDs.isEmpty)
    store.geometryBusy=true;XCTAssertThrowsError(try store.setAlphaVisibility(ids[0],true));store.geometryBusy=false
    let draft=try XCTUnwrap(store.beginChannelVisibilitySweep(.alpha(ids[0])))
    store.extendChannelVisibilitySweep(draft,over:[.alpha(ids[1]),.alpha(ids[0])]);XCTAssertEqual(store.visibleAlphaIDs,Set(ids))
    XCTAssertFalse(store.canSelectComponentTarget);XCTAssertThrowsError(try store.setAlphaVisibility(ids[1],false))
    store.finishChannelVisibilitySweep(draft,cancel:true);XCTAssertTrue(store.visibleAlphaIDs.isEmpty);XCTAssertEqual(store.document,original)
    XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertTrue(store.canSelectComponentTarget)
  }
  @MainActor func testNoAuxiliaryRowsRetainLastVisibleProcessChannel()throws {
    var document=try fixture();document.alphaChannels=nil
    let store=EditorStore(document:document);defer{store.renderTask?.cancel()}
    store.previewChannel(.red);let revision=store.revision
    XCTAssertTrue(store.setChannelVisibility(.red,visible:false));XCTAssertEqual(store.revision,revision);XCTAssertTrue(store.colorChannelsVisible)
    XCTAssertEqual(store.channelView.visible,[.red])
  }
  @MainActor func testHTTPViewsMatchNativeAndLeavePlainPreviewAndNativeFileUnchanged()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      let original=try self.fixture();file.store.session=EditorSession(document:original);try service.share(file)
      defer{file.store.renderTask?.cancel()};let share=try XCTUnwrap(service.shares.first),base="/v1/documents/\(share.id)"
      let before=try await helper.request(service,path:base+"/preview.png"),archive=try file.data(ofType:CraftNSDocument.nativeType)
      for channel in try XCTUnwrap(original.alphaChannels) {
        let status=try await helper.edit(service,file,"channel.view",["target":channel.id.uuidString,"visible":true]);XCTAssertEqual(status,200)
      }
      XCTAssertNil(file.store.editingChannel)
      let response=try await helper.request(service,path:base+"/channel-preview.png")
      let expected=try AutomationService.png(original,auxiliaryView:file.store.auxiliaryChannelView)
      XCTAssertEqual(response.1,expected);XCTAssertNotEqual(response.1,before.1)
      let after=try await helper.request(service,path:base+"/preview.png");XCTAssertEqual(after.1,before.1)
      XCTAssertEqual(try file.data(ofType:CraftNSDocument.nativeType),archive);XCTAssertTrue(file.store.session.undoStack.isEmpty)
      let state=service.state(share,document:file),view=try XCTUnwrap(state["auxiliaryVisibility"] as? [String:Any])
      XCTAssertEqual(view["visibleAlphaIDs"] as? [String],original.alphaChannels?.map{$0.id.uuidString})
      let revision=service.revision(file.store),id=try XCTUnwrap(original.alphaChannels?.first?.id)
      let noop=try await helper.edit(service,file,"channel.view",["target":id.uuidString,"visible":true]);XCTAssertEqual(noop,200);XCTAssertEqual(service.revision(file.store),revision)
    }
  }
  @MainActor func testHTTPRGBEyeKeepsAlphaTargetAndRejectsInvalidBusyStaleRequests()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      let original=try self.fixture();file.store.session=EditorSession(document:original);try service.share(file)
      defer{file.store.renderTask?.cancel()};let id=try XCTUnwrap(original.alphaChannels?.first?.id)
      try file.store.selectAlphaChannel(id)
      let shown=try await helper.edit(service,file,"channel.view",["target":"RGB","visible":true]);XCTAssertEqual(shown,200);XCTAssertEqual(file.store.editingChannel,.alpha(id));XCTAssertTrue(file.store.colorChannelsVisible)
      let hidden=try await helper.edit(service,file,"channel.view",["target":"RGB","visible":false]);XCTAssertEqual(hidden,200);XCTAssertFalse(file.store.colorChannelsVisible)
      let missing=try await helper.edit(service,file,"channel.view",["target":UUID().uuidString,"visible":true]);XCTAssertEqual(missing,422)
      let malformed=try await helper.edit(service,file,"channel.view",["target":id.uuidString,"visible":"true"]);XCTAssertEqual(malformed,400)
      let stale=try await helper.edit(service,file,"channel.view",["target":id.uuidString,"visible":false],revision:"stale");XCTAssertEqual(stale,409)
      let sweep=try XCTUnwrap(file.store.beginChannelVisibilitySweep(.alpha(id)))
      let busy=try await helper.edit(service,file,"channel.view",["target":id.uuidString,"visible":true]);XCTAssertEqual(busy,409)
      file.store.finishChannelVisibilitySweep(sweep,cancel:true)
      XCTAssertEqual(file.store.document,original);XCTAssertEqual(file.store.editingChannel,.alpha(id))
      XCTAssertNotNil(ChannelVisibilityAPI.stateSchema["properties"]);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ChannelAPI.capabilities))
    }
  }
  @MainActor func testMaximumLogicalViewportAndHTTPComponentOverlayAreBounded()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      var document=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,background:.white,mode:.cmyk)
      var red=ChannelDisplayOptions();red.opacity=0.5;red.color=Pixel(1,0,0)
      let channel=AlphaChannel(name:"Large mask",pixels:try Surface(width:300000,height:300000,depth:.u16,fill:.black),options:red)
      document.alphaChannels=[channel];file.store.session=EditorSession(document:document);try service.share(file)
      defer{file.store.renderTask?.cancel()}
      try file.store.selectAlphaChannel(channel.id);try file.store.setModeComponentVisibility([0])
      let source=try ModeChannelPresentation.surface(document,visible:[0])
      let image=try AuxiliaryChannelPresentation.image(source,document:document,view:file.store.auxiliaryChannelView,colorManaged:false,
        request:RasterPreviewRequest(region:.init(x:299998,y:299998,width:2,height:2),width:2,height:2))
      XCTAssertEqual(image.width,2);try self.pixel(image,[255,128,128,255])
      let share=try XCTUnwrap(service.shares.first)
      let response=try await helper.request(service,path:"/v1/documents/\(share.id)/channel-preview.png")
      XCTAssertEqual(response.0.statusCode,200)
      let sourceImage=try XCTUnwrap(CGImageSourceCreateWithData(response.1 as CFData,nil))
      let decoded=try RasterIO.surface(XCTUnwrap(CGImageSourceCreateImageAtIndex(sourceImage,0,nil)))
      XCTAssertLessThanOrEqual(decoded.width,2048);XCTAssertLessThanOrEqual(decoded.height,2048)
      XCTAssertEqual(file.store.document,document);XCTAssertEqual(file.store.editingChannel,.alpha(channel.id))
    }
  }
  @MainActor func testNumericGrayIndicationAndROIAtAllDepths()throws {
    for depth in PixelDepth.allCases {
      var document=try fixture(depth);var channel=try XCTUnwrap(document.alphaChannels?.first)
      channel.pixels=try Surface(width:4,height:3,depth:depth,fill:Pixel(0.5,0.5,0.5));channel.options.indicates = .selectedAreas
      document.alphaChannels=[channel]
      let store=EditorStore(document:document);defer{store.renderTask?.cancel()};try store.selectAlphaChannel(channel.id)
      let image=try self.image(store)
      // The stored midpoint quantizes to128/255; selected-area display inverts it.
      let expected:UInt8=depth == .u8 ? 127:depth == .u16 ? 127:128
      try pixel(image,[expected,expected,expected,255])
    }
  }
  @MainActor func testPrintingInkEyesKeepSavedMaskTargetAndPlaneBytes()throws {
    for duotone in [false,true] {
      var document=try InkChannelWorkflowTests().source(duotone:duotone)
      let channel=AlphaChannel(name:"Saved mask",pixels:try Surface(width:document.width,height:document.height,depth:document.depth,fill:.black))
      document.alphaChannels=[channel];let store=EditorStore(document:document);defer{store.renderTask?.cancel()}
      try store.selectAlphaChannel(channel.id)
      let target=try XCTUnwrap(document.inkChannelTargets.first)
      try store.setInkVisibility([target]);XCTAssertEqual(store.visibleInkTargets,[target]);XCTAssertEqual(store.editingChannel,.alpha(channel.id))
      try store.setInkVisibility([]);XCTAssertFalse(store.colorChannelsVisible);XCTAssertEqual(store.visibleInkTargets,[])
      try store.setColorChannelsVisibility(true);XCTAssertEqual(store.visibleInkTargets,Set(document.inkChannelTargets))
      XCTAssertEqual(store.document,document);XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testSpotRowUsesDensityForOverlayAndGrayForIsolatedView()throws {
    var document=try fixture();var channel=try XCTUnwrap(document.alphaChannels?.first)
    channel.spot=SpotInk(color:Pixel(0,0,1),solidity:0.5)
    channel.pixels=try Surface(width:4,height:3,fill:.white);document.alphaChannels=[channel]
    let store=EditorStore(document:document);defer{store.renderTask?.cancel()}
    try store.setAlphaVisibility(channel.id,true);XCTAssertNil(store.editingChannel);try pixel(image(store),[0,0,128,255])
    try store.selectAlphaChannel(channel.id);try pixel(image(store),[0,0,0,255])
    XCTAssertEqual(store.document,document)
  }

  @MainActor func testLastAuxiliaryDeletionRestoresImageAndUndoRestoresIsolatedView()async throws {
    var original=try fixture();original.alphaChannels=Array(try XCTUnwrap(original.alphaChannels).prefix(1))
    let store=EditorStore(document:original);defer{store.renderTask?.cancel()}
    let id=try XCTUnwrap(original.alphaChannels?.first?.id);try store.selectAlphaChannel(id)
    XCTAssertFalse(store.colorChannelsVisible)
    store.perform(.channel(.delete(id)));XCTAssertTrue(store.visibleAlphaIDs.isEmpty);XCTAssertTrue(store.colorChannelsVisible)
    await store.undo();XCTAssertEqual(store.visibleAlphaIDs,[id]);XCTAssertFalse(store.colorChannelsVisible)
    XCTAssertEqual(store.document,original)
  }
  @MainActor func testReopenResetsTemporaryEyeWithoutSerializingViewState()throws {
    var original=try fixture();original.selection = .init(x:3,y:2,width:1,height:1)
    let file=CraftNSDocument(model:original),store=file.store;defer{store.renderTask?.cancel();file.close()}
    store.toggleQuickMask();let id=try XCTUnwrap(store.document.alphaChannels?.first?.id)
    try store.setAlphaVisibility(id,true);try store.setQuickMaskVisibility(false);try store.setColorChannelsVisibility(false)
    let before=store.document,bytes=try file.data(ofType:CraftNSDocument.nativeType)
    try file.read(from:bytes,ofType:CraftNSDocument.nativeType)
    XCTAssertEqual(store.document,before);XCTAssertTrue(store.isQuickMaskVisible);XCTAssertTrue(store.visibleAlphaIDs.isEmpty)
    XCTAssertTrue(store.colorChannelsVisible);XCTAssertEqual(store.editingChannel,.quickMask)
  }
  @MainActor func testNeutralFillAlphaAndDesktopOpacityUseSameComponentPrimitive()throws {
    for (mode,depth) in [(DocumentColorMode.rgb,PixelDepth.u8),(.rgb,.u16),(.cmyk,.u16)] {
      var original=try DocumentCreation.blank(width:4,height:3,depth:depth,background:.white,mode:mode)
      original.alphaChannels=try fixture(depth).alphaChannels
      let id=original.layers[0].id,mask=try XCTUnwrap(original.alphaChannels?.first?.id)
      var expected=original;try ModeComponentEdit(layerID:id,components:[0],operation:.fill(0,0.5)).apply(to:&expected)
      for generic in [false,true] {
        let store=EditorStore(document:original);defer{store.renderTask?.cancel()}
        if store.usesModeChannels {try store.selectModeComponents([0])}else{try store.selectEditingChannel(.red)}
        try store.setAlphaVisibility(mask,true)
        if generic {try store.executeEditorCommand(.fill(id,Pixel(0,0,0,0.5)))}else{store.fill(color:Pixel(0,0,0,0.5))}
        XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
        XCTAssertEqual(store.document.alphaChannels,original.alphaChannels);XCTAssertTrue(store.isAlphaVisible(mask))
      }
      let product=EditorStore(document:original);defer{product.renderTask?.cancel()}
      if product.usesModeChannels {try product.selectModeComponents([0])}else{try product.selectEditingChannel(.red)}
      product.fill(color:Pixel(0,0,0,0.5),opacity:0.5)
      var quarter=original;try ModeComponentEdit(layerID:id,components:[0],operation:.fill(0,0.25)).apply(to:&quarter)
      XCTAssertEqual(product.document,quarter)
    }
  }
  @MainActor func testHTTPNeutralAlphaFillMatchesDesktopAndKeepsNonneutralRejection()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      var original=try self.fixture();original.layers[0].content = .raster(try Surface(width:4,height:3,fill:.white))
      file.store.session=EditorSession(document:original);try service.share(file);try file.store.selectEditingChannel(.red)
      defer{file.store.renderTask?.cancel()};let id=original.layers[0].id
      let status=try await helper.edit(service,file,"layer.fill",["layerID":id.uuidString,"r":0,"g":0,"b":0,"a":0.5])
      XCTAssertEqual(status,200)
      var expected=original;try ModeComponentEdit(layerID:id,components:[0],operation:.fill(0,0.5)).apply(to:&expected)
      XCTAssertEqual(file.store.document,expected);XCTAssertEqual(file.store.session.undoStack.count,1)
      let rejected=try await helper.edit(service,file,"layer.fill",["layerID":id.uuidString,"r":1,"g":0,"b":0,"a":0.5])
      XCTAssertEqual(rejected,422);XCTAssertEqual(file.store.document,expected)
      let undo=try await helper.edit(service,file,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(file.store.document,original)
    }
  }

  @MainActor func testHTTPImageRowClearsSavedEyesWhileVisibilityCommandPreservesThem()async throws {
    let helper=AutomationTests()
    try await helper.withService {service,file in
      file.store.session=EditorSession(document:try self.fixture());try service.share(file)
      let original=file.store.document,ids=try XCTUnwrap(original.alphaChannels).map(\.id)
      for id in ids {try file.store.setAlphaVisibility(id,true)}
      // An eye retains both the current RGB target and saved-channel display.
      let hide=try await helper.edit(service,file,"channel.view",["target":"RGB","visible":false])
      XCTAssertEqual(hide,200);XCTAssertEqual(file.store.visibleAlphaIDs,Set(ids));XCTAssertNil(file.store.editingChannel)
      let show=try await helper.edit(service,file,"channel.view",["target":"RGB","visible":true])
      XCTAssertEqual(show,200);XCTAssertEqual(file.store.visibleAlphaIDs,Set(ids))
      // A row selection clears saved eyes even if RGB is already selected.
      let beforeSelectionRevision=file.store.revision
      let select=try await helper.edit(service,file,"channel.target",["channel":"RGB"])
      XCTAssertEqual(select,200);XCTAssertTrue(file.store.visibleAlphaIDs.isEmpty)
      XCTAssertGreaterThan(file.store.revision,beforeSelectionRevision)
      await file.store.renderTask?.value
      try self.pixel(XCTUnwrap(file.store.image),[0,0,0,255])
      XCTAssertTrue(file.store.colorChannelsVisible);XCTAssertEqual(file.store.document,original)
      XCTAssertTrue(file.store.session.undoStack.isEmpty)
      for id in ids {try file.store.setAlphaVisibility(id,true)}
      let red=try await helper.edit(service,file,"channel.target",["channel":"Red"])
      XCTAssertEqual(red,200);XCTAssertEqual(file.store.componentTarget,.red);XCTAssertTrue(file.store.visibleAlphaIDs.isEmpty)
    }
  }

}
