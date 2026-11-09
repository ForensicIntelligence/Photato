import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MagicWandSamplingWorkflowTests: XCTestCase {
  func fixture(_ depth:PixelDepth = .u8, mask:Bool = false) throws -> CraftDocument {
    var d = try CraftDocument(width:4,height:1,depth:depth)
    var surface = try Surface(width:4,height:1,depth:depth,fill:Pixel(64.0/255,64.0/255,64.0/255))
    surface.setPixel(x:0,y:0,.black); surface.setPixel(x:1,y:0,Pixel(128.0/255,128.0/255,128.0/255))
    if mask { d.layers[0].mask = surface } else { d.layers[0].content = .raster(surface) }
    return d
  }
  @MainActor func testNativeAverageCapturesOptionsAndHasOneUndo() async throws {
    let original = try fixture(.u16), store = EditorStore(document:try fixture(.u16))
    defer { store.renderTask?.cancel() }; store.session = .init(document:original)
    store.chooseTool(WorkspaceCatalog.tool("magicWand")); store.wandOptions.sampleSize = 3
    store.wandOptions.tolerance = 0; store.wandOptions.antiAlias = false; store.wandOptions.contiguous = false
    store.colorRegionClick(at:.init(0,0)); XCTAssertTrue(store.geometryBusy)
    store.wandOptions.sampleSize = 1
    await store.geometryTask?.value; XCTAssertNil(store.error)
    XCTAssertEqual(try store.document.selectionMask?.bytes,[0,0,255,255])
    XCTAssertEqual(store.document.layers,original.layers); XCTAssertEqual(store.session.undoStack.count,1)
    XCTAssertEqual(store.wandOptions.sampleSize,1)
    let after = store.document; await store.undo(); XCTAssertEqual(store.document,original)
    await store.redo(); XCTAssertEqual(store.document,after)
  }
  @MainActor func testNativeAndHTTPMatchAllSizesDepthsAndOrdinaryMaskTargets() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) { service,file in
      for depth in PixelDepth.allCases { for mask in [false,true] { for size in ColorSampleSettings.sizes {
        let original = try self.fixture(depth,mask:mask)
        file.store.session = .init(document:original); file.store.maskEditingLayerID = mask ? original.activeLayerID:nil
        try service.share(file)
        let native = EditorStore(document:original); defer { native.renderTask?.cancel() }
        native.chooseTool(WorkspaceCatalog.tool("magicWand")); native.maskEditingLayerID = mask ? original.activeLayerID:nil
        native.wandOptions.sampleSize = size; native.wandOptions.tolerance = 0
        native.wandOptions.contiguous = false; native.wandOptions.antiAlias = false; native.wandSampleAllLayers = true
        native.colorRegionClick(at:.init(0,0)); await native.geometryTask?.value; XCTAssertNil(native.error)
        let code = try await h.edit(service,file,MagicWandAPI.name,["operation":"select","x":0,"y":0,"sampleSize":size,"tolerance":0,"contiguous":false,"antiAlias":false,"sampleAllLayers":true])
        XCTAssertEqual(code,200,"\(depth)/\(mask)/\(size)"); XCTAssertEqual(file.store.document,native.document)
        XCTAssertEqual(file.store.maskEditingLayerID,native.maskEditingLayerID)
        XCTAssertEqual(file.store.document.layers,original.layers); XCTAssertEqual(file.store.session.undoStack.count,1)
        XCTAssertEqual(file.store.wandOptions.sampleSize,1,"Selection overrides must not change defaults")
      } } }
    }
  }
  @MainActor func testConfigurationSchemasAndMalformedStaleBusyRequests() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) { service,file in
      let original = try self.fixture(); file.store.session = .init(document:original); try service.share(file)
      let config = try await h.edit(service,file,MagicWandAPI.name,["operation":"configure","sampleSize":11,"tolerance":7,"antiAlias":false,"mode":"add"])
      XCTAssertEqual(config,200); XCTAssertEqual(file.store.wandOptions.sampleSize,11)
      XCTAssertEqual(file.store.selectionMode,.add); XCTAssertEqual(file.store.document,original)
      XCTAssertTrue(file.store.session.undoStack.isEmpty)
      let bad: [[String:Any]] = [["operation":"configure"],["operation":"configure","x":0],["operation":"select"],
        ["operation":"select","x":0,"y":0,"sampleSize":2],["operation":"select","x":0,"y":0,"antiAlias":"true"],
        ["operation":"select","x":0,"y":0,"target":"unknown"],["operation":"select","x":0,"y":0,"layerID":"invalid"]]
      for parameters in bad { let status = try await h.edit(service,file,MagicWandAPI.name,parameters); XCTAssertEqual(status,400) }
      let select: [String:Any] = ["operation":"select","x":0,"y":0]
      let stale = try await h.edit(service,file,MagicWandAPI.name,select,revision:"old"); XCTAssertEqual(stale,409)
      file.store.geometryBusy = true
      let busy = try await h.edit(service,file,MagicWandAPI.name,select); XCTAssertEqual(busy,409); file.store.geometryBusy = false
      XCTAssertEqual(file.store.document,original); XCTAssertTrue(file.store.session.undoStack.isEmpty)
      let caps = try await h.request(service,path:"/v1/capabilities")
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with:caps.1) as? [String:Any])
      XCTAssertNotNil(object["magicWand"]); XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:MagicWandAPI.parameterSchema))
      XCTAssertEqual(AutomationCommand.definitions.count,267); XCTAssertEqual(ActionLibraryFile.maximumVersion,61)
      XCTAssertEqual((MagicWandAPI.state(file.store)["settings"] as? [String:Any])?["sampleSize"] as? Int,11)
    }
  }
  @MainActor func testLockedReadOnlySourceAndEveryModifierKeepExistingSelectionPolicy() async throws {
    let original = try fixture(), flags: [NSEvent.ModifierFlags] = [.control,.command,.option,.shift]
    for bits in 0..<16 {
      var locked = original; locked.layers[0].locked = true
      let store = EditorStore(document:locked); defer { store.renderTask?.cancel() }
      store.chooseTool(WorkspaceCatalog.tool("magicWand")); store.wandOptions.sampleSize = 3
      store.wandOptions.tolerance = 0; store.wandOptions.contiguous = false; store.wandOptions.antiAlias = false
      let modifiers = flags.enumerated().reduce(into:NSEvent.ModifierFlags()) { if bits & (1 << $1.offset) != 0 { $0.insert($1.element) } }
      let mode:SelectionMode = modifiers.contains(.shift) ? (modifiers.contains(.option) ? .intersect:.add):(modifiers.contains(.option) ? .subtract:.replace)
      XCTAssertEqual(store.selectionMode(modifiers:modifiers),mode)
      let canvas = CraftCanvas(store:store); canvas.updateCursorModifiers(modifiers); let cursor = canvas.toolCursor
      store.colorRegionClick(at:.init(0,0),modifiers:modifiers); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.document.layers,locked.layers)
      canvas.updateCursorModifiers(modifiers); XCTAssertEqual(canvas.toolCursor,cursor)
      if mode == .replace || mode == .add { XCTAssertEqual(try store.document.selectionMask?.bytes,[0,0,255,255]) }
    }
  }
  @MainActor func testCancelledAndRevokedPreparationCannotPublish() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) { service,file in
      let original = try self.fixture(); file.store.session = .init(document:original); try service.share(file)
      let share = try XCTUnwrap(service.shares.first?.id), revision = service.revision(file.store)
      var options = ColorMatchOptions(); options.sampleSize = 3
      let request = MagicWandRequest(layerID:try XCTUnwrap(original.activeLayerID),point:.init(0,0),options:options,mode:.replace,sampleAllLayers:false,mask:false)
      let pending = Task { try await service.executePreparedOperation(document:file,shareID:share,revision:revision,allowAuxiliary:true) { source in
        let command = try request.command(in:source); try await Task.sleep(for:.seconds(5)); return command
      } }
      for _ in 0..<200 where !file.store.geometryBusy { try await Task.sleep(for:.milliseconds(5)) }
      file.store.cancelActiveOperation()
      do { try await pending.value; XCTFail("Cancelled selection committed") } catch {}
      do {
        try await service.executePreparedOperation(document:file,shareID:share,revision:revision,allowAuxiliary:true,
          validateCommit:{service.revoke(share);throw AutomationFailure(status:409,message:"Revoked")}) { try request.command(in:$0) }
        XCTFail("Revoked selection committed")
      } catch {}
      XCTAssertEqual(file.store.document,original); XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
}
