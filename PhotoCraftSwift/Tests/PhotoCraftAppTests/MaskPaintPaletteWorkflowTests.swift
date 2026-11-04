import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MaskPaintPaletteWorkflowTests:XCTestCase {
  let pink=Pixel(210/255,74/255,126/255),gray=Pixel(128/255,128/255,128/255)
  func model(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:8,height:8,depth:depth);d.layers[0].background=nil
    d.layers[0].mask=try Surface(width:8,height:8,depth:depth,fill:.white);return d
  }
  func smartModel()throws->CraftDocument {
    var d=try SmartFilterWorkflowTests().fixture();var stack=SmartFilterStack();stack.filters=[SmartFilter(filter:RasterFilter(.gaussianBlur))];try stack.createMask(in:d);d.layers[0].smartFilters=stack;try d.validate();return d
  }
  @MainActor func expectEdit(_ helper:AutomationTests,_ service:AutomationService,_ file:CraftNSDocument,_ name:String,_ params:[String:Any],_ status:Int=200,revision:String?=nil,sourceFile:StaticString=#filePath,line:UInt=#line)async throws {
    let actual=try await helper.edit(service,file,name,params,revision:revision);XCTAssertEqual(actual,status,file:sourceFile,line:line)
  }
  @MainActor func pair(_ s:EditorStore,_ fg:Pixel,_ bg:Pixel,file:StaticString=#filePath,line:UInt=#line) {XCTAssertEqual(s.brush.color,fg,file:file,line:line);XCTAssertEqual(s.backgroundColor,bg,file:file,line:line)}
  @MainActor func testMaskTargetUsesIndependentPairAndPhotoshopDefaultsAtEveryDepth()throws {
    for depth in PixelDepth.allCases {
      let d=try model(depth),s=EditorStore(document:d);defer{s.renderTask?.cancel()}
      s.brush.color=pink;s.selectMask(d.layers[0].id);pair(s,.white,.black);XCTAssertEqual(s.paintColorContext,.mask)
      s.swapColors();pair(s,.black,.white);s.brush.color=gray;s.resetColors();pair(s,.white,.black)
      try s.selectEditingChannel(.composite);pair(s,pink,.white);XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testLayerAndSmartFilterMasksSharePairAcrossDocumentsWithoutChangingImageOrAuxiliary()throws {
    let p=PaintPalette(),a=EditorStore(document:try model(),paintPalette:p),b=EditorStore(document:try smartModel(),paintPalette:p)
    defer{a.renderTask?.cancel();b.renderTask?.cancel()};a.brush.color=pink
    a.selectMask(a.document.layers[0].id);a.brush.color=gray;b.selectSmartFilterMask(b.document.layers[0].id);pair(b,gray,.black)
    b.swapColors();pair(a,.black,gray);a.toggleQuickMask();pair(a,.black,.white);a.toggleQuickMask();pair(a,pink,.white)
    a.selectMask(a.document.layers[0].id);pair(a,.black,gray);XCTAssertTrue(a.session.undoStack.count==2);XCTAssertTrue(b.session.undoStack.isEmpty)
  }
  @MainActor func testQuickMaskExitPreservesIndependentlySelectedMaskButOwnTargetReturnsImage()throws {
    let s=EditorStore(document:try model());defer{s.renderTask?.cancel()};s.brush.color=pink
    s.selectMask(s.document.layers[0].id);s.brush.color=gray;s.toggleQuickMask();pair(s,.black,.white)
    let quick=s.document.quickMask;s.selectMask(s.document.layers[0].id);XCTAssertNil(s.editingChannel);pair(s,gray,.black);XCTAssertEqual(s.document.quickMask,quick)
    s.toggleQuickMask();XCTAssertNil(s.document.quickMask);XCTAssertTrue(s.editingMask);pair(s,gray,.black)
    s.toggleQuickMask();XCTAssertEqual(s.editingChannel,.quickMask);s.toggleQuickMask();XCTAssertFalse(s.editingMask);pair(s,pink,.white)
  }
  @MainActor func testDeletedOrInactiveMaskFallsBackToImageBeforeAnyRender()throws {
    let s=EditorStore(document:try model());defer{s.renderTask?.cancel()};s.brush.color=pink;s.selectMask(s.document.layers[0].id);s.brush.color=gray
    var withoutMask=s.document;withoutMask.layers[0].mask=nil;s.session=EditorSession(document:withoutMask);XCTAssertEqual(s.paintColorContext,.image);pair(s,pink,.white);XCTAssertTrue(s.maskEditingTargetState is NSNull)
  }
  @MainActor func testPaletteV1MigrationRetainsPairsAndV2RestoresAllThreeWithoutRewritingLegacy()throws {
    let name="Photato.mask-palette."+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:name));defer{defaults.removePersistentDomain(forName:name)}
    let image=PaintColorPair(foreground:pink,background:.white),aux=PaintColorPair(foreground:.white,background:.black)
    let legacy=try JSONSerialization.data(withJSONObject:["version":1,"image":JSONSerialization.jsonObject(with:JSONEncoder().encode(image)),"auxiliary":JSONSerialization.jsonObject(with:JSONEncoder().encode(aux))]);defaults.set(legacy,forKey:PaintPalette.legacyKey)
    let p=PaintPalette(defaults:defaults);XCTAssertEqual(p.colors(context:.image),image);XCTAssertEqual(p.colors(context:.auxiliary),aux);XCTAssertEqual(p.colors(context:.mask),PaintColorContext.mask.defaults)
    let mask=PaintColorPair(foreground:gray,background:.black);p.set(mask,context:.mask)
    let restored=PaintPalette(defaults:defaults);XCTAssertEqual(restored.colors(context:.mask),mask);XCTAssertEqual(restored.colors(context:.image),image);XCTAssertEqual(restored.colors(context:.auxiliary),aux);XCTAssertEqual(defaults.data(forKey:PaintPalette.legacyKey),legacy)
    let detached=p.detached();p.set(PaintColorContext.mask.defaults,context:.mask);XCTAssertEqual(detached.colors(context:.mask),mask)
  }
  @MainActor func testCapturedMaskBrushPaintHistoryAndImagePixelsRemainIndependent()async throws {
    let d=try model(),s=EditorStore(document:d);defer{s.renderTask?.cancel()};s.brush.color=pink;s.selectMask(d.layers[0].id);s.resetColors();s.swapColors()
    var captured=s.brush;captured.size=3;captured.hardness=1;s.brush.color=gray
    s.stroke([.init(x:4,y:4)],brush:captured);XCTAssertNil(s.error);XCTAssertEqual(s.document.layers[0].mask?.pixel(x:4,y:4).r,0);XCTAssertEqual(s.document.layers[0].content,d.layers[0].content)
    let changed=s.document;await s.undo();XCTAssertEqual(s.document,d);await s.redo();XCTAssertEqual(s.document,changed);pair(s,gray,.white)
  }
  @MainActor func testHTTPMaskTargetConfigurePaintStateAndQuickMaskExitMatchNative()async throws {
    let helper=AutomationTests()
    for smart in [false,true] {
      try await helper.withService(pressedMouseButtons:{0}) {service,file in
        let d=try (smart ? smartModel():model()),id=d.layers[0].id;file.store.session=EditorSession(document:d);try service.share(file);file.store.brush.color=pink
        let kind=smart ? "smartFilterMask":"layerMask",params:[String:Any]=["target":kind,"layerID":id.uuidString]
        try await expectEdit(helper,service,file,"channel.view",params,200)
        pair(file.store,.white,.black);XCTAssertEqual(file.store.paintColorContext,.mask)
        try await expectEdit(helper,service,file,"brush.configure",["brush":["color":BrushAPI.json(Pixel.black),"size":3,"hardness":1]],200)
        let before=file.store.document
        try await expectEdit(helper,service,file,"paint.stroke",["target":kind,"layerID":id.uuidString,"points":[["x":4,"y":4]]],200)
        XCTAssertEqual(file.store.paintColorContext,.mask);XCTAssertNotEqual(file.store.document,before)
        let plane=try XCTUnwrap(smart ? file.store.document.layers[0].smartFilters?.mask:file.store.document.layers[0].mask)
        XCTAssertEqual(plane.pixel(x:4,y:4).r,0);XCTAssertEqual(plane.pixel(x:0,y:0).r,1)
        XCTAssertEqual(file.store.imagePaintColorPair.foreground,pink)
        if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
          let id=try XCTUnwrap(service.shares.first?.id),response=try await helper.request(service,path:"/v1/documents/\(id)")
          XCTAssertEqual(response.0.statusCode,200);try response.1.write(to:folder.appendingPathComponent("mask-palette-\(kind)-state.json"))
          let samples=(0..<plane.height).flatMap{y in (0..<plane.width).map{x in Int((plane.pixel(x:x,y:y).r*255).rounded())}}
          try JSONSerialization.data(withJSONObject:["kind":kind,"width":plane.width,"height":plane.height,"gray8":samples],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("mask-palette-\(kind)-plane.json"))
        }
        let selected=try XCTUnwrap(service.shares.first),state=service.state(selected,document:file),target=try XCTUnwrap(state["maskEditingTarget"]as?[String:Any]);XCTAssertEqual(target["kind"]as?String,kind);XCTAssertEqual(target["layerID"]as?String,id.uuidString)
        let native=EditorStore(document:before);defer{native.renderTask?.cancel()};if smart {native.selectSmartFilterMask(id)}else{native.selectMask(id)}
        native.stroke([.init(x:4,y:4)],brush:file.store.brush);XCTAssertEqual(native.document,file.store.document)
        try await expectEdit(helper,service,file,"channel.edit",["action":"quickMask","enabled":true],200)
        try await expectEdit(helper,service,file,"channel.view",params,200)
        try await expectEdit(helper,service,file,"channel.edit",["action":"quickMask","enabled":false],200);XCTAssertEqual(file.store.paintColorContext,.mask)
      }
    }
  }
  @MainActor func testHTTPInvalidBusyStaleMaskTargetsNeverChangeTargetPalettePixelsOrHistory()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,file in
      file.store.session=EditorSession(document:try model());try service.share(file);let original=file.store.document,colors=file.store.activePaintColorPair,id=original.layers[0].id
      for (params,status) in [(["target":"layerMask"],400),(["target":"layerMask","layerID":"bad"],400),(["target":"layerMask","layerID":UUID().uuidString],404),(["target":"smartFilterMask","layerID":id.uuidString],422),(["target":"RGB","layerID":id.uuidString],400),(["target":"layerMask","layerID":id.uuidString,"overlay":false],400)] as [([String:Any],Int)] {
        try await expectEdit(helper,service,file,"channel.view",params,status);XCTAssertEqual(file.store.paintColorContext,.image);XCTAssertEqual(file.store.document,original);XCTAssertEqual(file.store.activePaintColorPair,colors)
      }
      let target:[String:Any]=["target":"layerMask","layerID":id.uuidString]
      try await expectEdit(helper,service,file,"channel.view",target,409,revision:"old")
      file.store.geometryBusy=true;try await expectEdit(helper,service,file,"channel.view",target,409);file.store.geometryBusy=false
      XCTAssertTrue(file.store.session.undoStack.isEmpty);XCTAssertEqual(file.store.document,original);XCTAssertEqual(file.store.paintColorContext,.image);XCTAssertEqual(AutomationCommand.definitions.count,239)
    }
  }
}
