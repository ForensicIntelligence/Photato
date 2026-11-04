import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MaskTargetLifecycleWorkflowTests:XCTestCase {
  func fixture()throws->(CraftDocument,UUID) {
    var d=try CraftDocument(width:8,height:8);d.layers[0].background=nil;d.layers[0].content = .raster(try Surface(width:8,height:8,fill:Pixel(0,0,1)))
    let top=Layer(name:"Owned red artwork",content:.raster(try Surface(width:8,height:8,fill:Pixel(1,0,0))));d.layers.append(top);d.activeLayerID=top.id
    try SmartObjectIO.convert(in:d,selected:[top.id]).apply(to:&d)
    let index=try XCTUnwrap(d.layers.firstIndex{$0.smartObject != nil}),id=d.layers[index].id
    var stack=SmartFilterStack();stack.filters=[SmartFilter(filter:RasterFilter(.gaussianBlur))];try stack.createMask(in:d);d.layers[index].smartFilters=stack
    try d.validate();return(d,id)
  }
  func capture(_ d:CraftDocument,_ name:String)throws {
    guard let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else{return}
    let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try Renderer.composite(d).rgbaData(depth:.u8).write(to:folder.appendingPathComponent(name))
  }
  @MainActor func testRGBSelectionRestoresMergeAndCalculationsWithOneUndo()async throws {
    let (d,id)=try fixture(),s=EditorStore(document:d);defer{s.renderTask?.cancel()};s.selectSmartFilterMask(id)
    XCTAssertFalse(s.canMerge(.down));XCTAssertFalse(s.canBeginChannelArithmetic(.calculations))
    try s.selectEditingChannel(.composite);XCTAssertNil(s.selectedMaskPaintTarget);XCTAssertEqual(s.paintColorContext,.image)
    XCTAssertTrue(s.canMerge(.down));XCTAssertTrue(s.canBeginChannelArithmetic(.calculations));XCTAssertFalse(s.smartFilterMaskEditing)
    s.merge(.down);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document.layers.count,1);XCTAssertEqual(s.session.undoStack.count,1)
    try capture(s.document,"mask-target-native-merge.rgba");await s.undo();XCTAssertEqual(s.document,d)
  }
  @MainActor func testSelectAllLayersLeavesMasksAndEnablesSelectedMergeAndFlatten()async throws {
    let (d,id)=try fixture(),s=EditorStore(document:d);defer{s.renderTask?.cancel()};s.selectSmartFilterMask(id);s.selectAllLayers()
    XCTAssertEqual(s.selectedLayerIDs,Set(d.layers.map(\.id)));XCTAssertTrue(s.canMerge(.selected));XCTAssertTrue(s.canFlattenImage)
    s.merge(.selected);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document.layers.count,1);XCTAssertEqual(s.session.undoStack.count,1)
    await s.undo();XCTAssertEqual(s.document,d)
  }
  @MainActor func testPreviewAndPathTransitionsRestoreImageCommandAvailabilityWithoutHistory()throws {
    for usePath in [false,true] {
      let (d,id)=try fixture(),s=EditorStore(document:d);defer{s.renderTask?.cancel()};s.selectSmartFilterMask(id)
      if usePath{s.selectPath(nil)}else{s.previewChannel(.composite)}
      XCTAssertNil(s.maskEditingLayerID);XCTAssertFalse(s.smartFilterMaskEditing);XCTAssertTrue(s.canBeginChannelArithmetic(.calculations));XCTAssertTrue(s.canMerge(.down));XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testNativeDocumentReadClearsPreviousMaskModeAndRestoresImageOperations()throws {
    _ = NSApplication.shared;let(d,id)=try fixture(),file=CraftNSDocument(model:d);defer{file.close()};file.store.selectSmartFilterMask(id)
    var plain=try CraftDocument(width:8,height:8);plain.layers[0].background=nil
    try file.read(from:NativeArchive.encodeChunked(plain),ofType:CraftNSDocument.nativeType)
    XCTAssertEqual(file.store.document,plain);XCTAssertNil(file.store.maskEditingLayerID);XCTAssertFalse(file.store.smartFilterMaskEditing);XCTAssertTrue(file.store.canInvertPixels);XCTAssertTrue(file.store.canBeginChannelArithmetic(.calculations))
  }
  @MainActor func testHTTPReturnToRGBAllowsActualMergeAndSharedHistory()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      let(d,id)=try fixture();file.store.session=EditorSession(document:d);try service.share(file)
      let selected=try await helper.edit(service,file,"channel.view",["target":"smartFilterMask","layerID":id.uuidString]);XCTAssertEqual(selected,200)
      let rgb=try await helper.edit(service,file,"channel.view",["target":"RGB"]);XCTAssertEqual(rgb,200)
      let merged=try await helper.edit(service,file,"layer.merge",["operation":"down","layerIDs":[id.uuidString]]);XCTAssertEqual(merged,200)
      XCTAssertEqual(file.store.document.layers.count,1);XCTAssertEqual(file.store.session.undoStack.count,1);XCTAssertFalse(file.store.smartFilterMaskEditing)
      try capture(file.store.document,"mask-target-http-merge.rgba")
      if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let folder=URL(fileURLWithPath:path),share=try XCTUnwrap(service.shares.first)
        let response=try await helper.request(service,path:"/v1/documents/\(share.id)")
        XCTAssertEqual(response.0.statusCode,200)
        try response.1.write(to:folder.appendingPathComponent("mask-target-http-merged-state.json"))
        try JSONSerialization.data(withJSONObject:["selected":selected,"rgb":rgb,"merged":merged,"layers":file.store.document.layers.count,"undoSteps":file.store.session.undoStack.count],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("mask-target-http-statuses.json"))
      }
      let undone=try await helper.edit(service,file,"history.undo");XCTAssertEqual(undone,200);XCTAssertEqual(file.store.document,d)
    }
  }
  @MainActor func testRejectedImageSelectionKeepsValidMaskAndThenAllowsSuccessfulReturn()throws {
    let(d,id)=try fixture(),s=EditorStore(document:d);defer{s.renderTask?.cancel()};s.selectSmartFilterMask(id);let target=s.selectedMaskPaintTarget,pair=s.activePaintColorPair
    s.geometryBusy=true;XCTAssertThrowsError(try s.selectEditingChannel(.composite));s.geometryBusy=false
    XCTAssertEqual(s.selectedMaskPaintTarget,target);XCTAssertEqual(s.activePaintColorPair,pair);XCTAssertTrue(s.smartFilterMaskEditing);XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty)
    try s.selectEditingChannel(.composite);XCTAssertFalse(s.smartFilterMaskEditing);XCTAssertTrue(s.canMerge(.down))
  }
}
