import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LegacyRGB8ComponentTests: XCTestCase {
  func fixture(width:Int=7,height:Int=5)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:.u8)
    d.layers[0].content = .raster(try Surface(width:width,height:height,depth:.u8,fill:Pixel(19.0/255,101.0/255,211.0/255,127.0/255)))
    try d.validate();return d
  }
  @MainActor func close(_ s:EditorStore) {s.cancelBrush();s.geometryTask?.cancel();s.renderTask?.cancel()}
  func pixels(_ d:CraftDocument)throws->Surface {
    guard case .raster(let s)=d.layers[0].content else{throw CraftError.invalid("Missing test raster")};return s
  }
  @MainActor func testTargetsKeepLegacyPreviewVisibilityAndObservableNumericalState() throws {
    let original=try fixture(),s=EditorStore(document:original);defer{close(s)}
    for (target,index) in [(RGBChannelPreview.red,0),(.green,1),(.blue,2)] {
      try s.selectEditingChannel(target)
      XCTAssertEqual(s.componentTarget,target);XCTAssertTrue(s.modeComponentTargets.isEmpty)
      XCTAssertEqual(s.effectiveComponentTargets,[index]);XCTAssertEqual(s.documentModeState["editingComponents"]as? [Int],[index])
      s.previewChannel(.blue);XCTAssertEqual(s.componentTarget,target);XCTAssertEqual(s.effectiveComponentTargets,[index])
      XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
    try s.selectEditingChannel(.composite);XCTAssertTrue(s.effectiveComponentTargets.isEmpty)
    XCTAssertFalse(s.document.hasNativeModeStorage)
  }
  @MainActor func testAllSingleChannelRoutedOperationsMatchSharedEngineAndKeepOtherWords() throws {
    let original=try fixture(),id=original.layers[0].id
    for (target,index) in [(RGBChannelPreview.red,0),(.green,1),(.blue,2)] {
      var brush=Brush();brush.size=1;brush.hardness=1;brush.color = .white
      var erase=brush;erase.erase=true;erase.backgroundColor = .white
      var pairs:[(Command,ModeComponentEdit.Operation)]=[
        (.fill(id,Pixel(0.25,0.25,0.25)),.fill(0.25,1)),(.clear(id),.fill(1,1)),
        (.applyAdjustment(id,.invert),.invert),(.stroke(id,[.init(x:2.5,y:2.5)],brush),.stroke([.init(x:2.5,y:2.5)],brush)),
        (.stroke(id,[.init(x:2.5,y:2.5)],erase),.stroke([.init(x:2.5,y:2.5)],erase))]
      for kind in ModeComponentEdit.filters.sorted(by:{$0.rawValue<$1.rawValue}) {var f=RasterFilter(kind);f.radius=1;f.seed=37;pairs.append((.applyFilter(id,f),.filter(f)))}
      for (command,op) in pairs {
        let s=EditorStore(document:original);defer{close(s)};try s.selectEditingChannel(target)
        var expected=original;try ModeComponentEdit(layerID:id,components:[index],operation:op).apply(to:&expected)
        try s.executeEditorCommand(command);XCTAssertEqual(s.document,expected)
        let before=try pixels(original),after=try pixels(s.document)
        for y in 0..<5 {for x in 0..<7 {let a=before.pixel(x:x,y:y),b=after.pixel(x:x,y:y)
          if index != 0 {XCTAssertEqual(a.r.bitPattern,b.r.bitPattern)}
          if index != 1 {XCTAssertEqual(a.g.bitPattern,b.g.bitPattern)}
          if index != 2 {XCTAssertEqual(a.b.bitPattern,b.b.bitPattern)}
          XCTAssertEqual(a.a.bitPattern,b.a.bitPattern)
        }}
      }
    }
  }
  @MainActor func testMenuAndToolAvailabilityRejectsUnportedTargets() throws {
    let s=EditorStore(document:try fixture());defer{close(s)};try s.selectEditingChannel(.red)
    s.tool = .brush;XCTAssertTrue(s.canUseBrush);XCTAssertTrue(s.canUseComponentCanvasTool);XCTAssertTrue(s.canInvertPixels)
    s.tool = .eraser;XCTAssertTrue(s.canUseBrush);XCTAssertTrue(s.canUseComponentCanvasTool)
    s.tool = .mixerBrush;XCTAssertFalse(s.canUseBrush);XCTAssertFalse(s.canUseComponentCanvasTool)
    for kind in ModeComponentEdit.filters {XCTAssertTrue(s.canBeginFilterKind(kind))}
    for kind in [RasterFilter.Kind.cameraRaw,.lightingEffects,.relight,.filterGallery] {XCTAssertFalse(s.canBeginFilterKind(kind))}
    var locked=s.document;locked.layers[0].locked=true;s.session=EditorSession(document:locked);s.tool = .brush
    XCTAssertFalse(s.canEditModeComponents);XCTAssertFalse(s.canUseBrush)
  }
  @MainActor func testFilterDraftCapturesLegacyComponentPreviewCommitCancelAndUndo() async throws {
    let original=try fixture(),s=EditorStore(document:original);defer{close(s)};try s.selectEditingChannel(.green)
    s.beginFilter(.gaussianBlur);let draft=try XCTUnwrap(s.filterDraft)
    XCTAssertEqual(draft.modeComponents,[1]);guard case .modeComponents(let edit)=try draft.command(in:original)else{return XCTFail()}
    XCTAssertEqual(edit.components,[1]);XCTAssertThrowsError(try s.selectEditingChannel(.blue))
    s.cancelFilter();XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginFilter(.highPass);let accepted=try XCTUnwrap(s.filterDraft);var expected=original;try accepted.command(in:original).apply(to:&expected)
    s.commitFilter();await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document,expected)
    XCTAssertEqual(s.session.undoStack.count,1);await s.undo();XCTAssertEqual(s.document,original)
  }
  @MainActor func testBrushPreviewAndReleaseCaptureTargetColorSettingsAndOneUndo() async throws {
    let original=try fixture(),s=EditorStore(document:original);defer{close(s)};try s.selectEditingChannel(.red)
    s.tool = .brush;s.brush.size=1;s.brush.hardness=1;s.brush.color = .white
    s.beginBrush(.init(x:2.5,y:2.5,time:0),zoom:1);let gesture=try XCTUnwrap(s.brushGesture)
    guard case .modeComponents(let preview)=try XCTUnwrap(s.brushPreviewCommand)else{return XCTFail()}
    XCTAssertEqual(preview.components,[0]);await s.brushPreviewTask?.value;await s.renderTask?.value
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertEqual(s.surface?.pixel(x:2,y:2).r,1)
    XCTAssertThrowsError(try s.selectEditingChannel(.blue));s.previewChannel(.blue)
    s.brush.color = .black;s.extendBrush(.init(x:3.5,y:2.5,time:10))
    var expected=original;try ModeComponentEdit(layerID:original.layers[0].id,components:[0],operation:.stroke(gesture.points,gesture.brush)).apply(to:&expected)
    s.finishBrush();await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document,expected)
    XCTAssertEqual(s.componentTarget,.red);XCTAssertEqual(s.session.undoStack.count,1)
    await s.undo();XCTAssertEqual(s.document,original);await s.redo();XCTAssertEqual(s.document,expected)
  }
  @MainActor func testCancelledBrushAndStalePreparedTargetNeverCommit() throws {
    let original=try fixture(),s=EditorStore(document:original);defer{close(s)};try s.selectEditingChannel(.red);s.tool = .brush
    s.beginBrush(.init(x:2.5,y:2.5),zoom:1);XCTAssertNotNil(s.brushGesture);s.cancelBrush()
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    let edit=Command.modeComponents(.init(layerID:original.layers[0].id,components:[0],operation:.invert))
    let prepared=try PreparedEdit(command:edit,document:original)
    try s.selectEditingChannel(.blue)
    XCTAssertThrowsError(try s.executeCompositePreparedEdit(prepared,allowModeComponents:true))
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testQuickMaskImageTargetKeepsTemporaryMaskAndPaletteScope() async throws {
    let s=EditorStore(document:try fixture());defer{close(s)};s.toggleQuickMask();let original=s.document,mask=try XCTUnwrap(original.quickMask)
    try s.selectEditingChannel(.red);XCTAssertNil(s.editingChannel);XCTAssertEqual(s.displayedAuxiliaryChannel,.quickMask)
    try s.setQuickMaskVisibility(false);s.tool = .eraser;s.backgroundColor = .white;s.brush.size=1;s.brush.hardness=1
    s.beginBrush(.init(x:2.5,y:2.5),zoom:1);XCTAssertNotNil(s.brushGesture);s.finishBrush();await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document.quickMask,mask);XCTAssertFalse(s.isQuickMaskVisible)
    XCTAssertEqual(s.componentTarget,.red);XCTAssertNil(s.editingChannel)
    try s.selectQuickMaskChannel();XCTAssertFalse(s.canInvertPixels)
    try s.setQuickMaskVisibility(true);XCTAssertTrue(s.canInvertPixels)
  }
  @MainActor func testAllSixteenModifiersKeepSelectedChannelBrushCursorAndDispatch() throws {
    let s=EditorStore(document:try fixture());defer{close(s)};try s.selectEditingChannel(.red)
    let canvas=CraftCanvas(store:s),modifiers:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for tool in [EditorTool.brush,.eraser] {s.tool=tool
      for bits in 0..<16 {
        let flags=modifiers.enumerated().reduce(NSEvent.ModifierFlags()){ bits&(1<<$1.offset)==0 ? $0:$0.union($1.element) }
        canvas.updateCursorModifiers(flags);XCTAssertEqual(canvas.toolCursor,tool.cursor(modifiers:flags))
        XCTAssertTrue(s.canUseComponentCanvasTool);s.beginBrush(.init(x:2.5,y:2.5),zoom:1,alternate:flags.contains(.option))
        guard case .modeComponents(let edit)=try XCTUnwrap(s.brushPreviewCommand)else{return XCTFail()}
        XCTAssertEqual(edit.components,[0]);if case .stroke(_,let brush)=edit.operation {XCTAssertEqual(brush.erase,tool == .eraser)}else{XCTFail()}
        s.cancelBrush()
      }
    }
    canvas.clearCursorInput();XCTAssertEqual(canvas.cursorModifiers,[])
  }
  @MainActor func testMaximumOrdinaryRGB8FillAndStrokeKeepLegacyStateAndNativeArchive() async throws {
    let original=try fixture(width:300000,height:300000),s=EditorStore(document:original);defer{close(s)};try s.selectEditingChannel(.red)
    let fill=try s.componentFillCommand(value:0.25,opacity:0.4)
    try s.executeEditorCommand(fill);XCTAssertEqual(s.session.undoStack.last?.label,"Fill")
    let filled=s.document,at=try pixels(filled).pixel(x:299999,y:299999)
    XCTAssertEqual(at.r,37.0/255);XCTAssertEqual(at.g,101.0/255);XCTAssertEqual(at.b,211.0/255);XCTAssertEqual(at.a,127.0/255)
    var brush=Brush();brush.size=1;brush.hardness=1;brush.color = .white
    try s.executeEditorCommand(.stroke(original.layers[0].id,[.init(x:299999.5,y:299999.5)],brush))
    XCTAssertEqual(try pixels(s.document).pixel(x:299999,y:299999).r,1)
    XCTAssertFalse(s.document.hasNativeModeStorage);XCTAssertEqual(s.componentTarget,.red)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encode(s.document)),s.document)
    await s.undo();XCTAssertEqual(s.document,filled);await s.undo();XCTAssertEqual(s.document,original)
    try capture("maximum-rgb8-fill",[at.r,at.g,at.b,at.a].map{UInt8((unit($0)*255).rounded())})
  }
  @MainActor func testHTTPStrokeEraseModeEditAndStateMatchDesktopForEveryChannel() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      for (title,index) in [("Red",0),("Green",1),("Blue",2)] {
        let selected=try await helper.edit(service,document,"channel.target",["channel":title]);XCTAssertEqual(selected,200)
        let before=document.store.document
        let fields:[String:Any]=["points":[["x":2.5,"y":2.5]],"brush":["size":1,"hardness":1,"color":["r":1,"g":1,"b":1,"a":1]]]
        var brush=Brush();brush.size=1;brush.hardness=1;brush.color = .white
        var expected=before;try ModeComponentEdit(layerID:before.layers[0].id,components:[index],operation:.stroke([.init(x:2.5,y:2.5)],brush)).apply(to:&expected)
        let status=try await helper.edit(service,document,"paint.stroke",fields);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
        let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,before)
        let mode=try await helper.edit(service,document,"mode.channel.edit",["layerID":before.layers[0].id.uuidString,"components":[index],"action":"invert"])
        XCTAssertEqual(mode,200);XCTAssertEqual(document.store.componentTarget.title,title)
        XCTAssertEqual(document.store.documentModeState["editingComponents"]as? [Int],[index])
        let undoMode=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undoMode,200)
        var erase=fields;erase["brush"]=["size":1,"hardness":1,"erase":true,"backgroundColor":["r":1,"g":1,"b":1,"a":1]]
        let erased=try await helper.edit(service,document,"paint.stroke",erase);XCTAssertEqual(erased,200)
        let undoErase=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undoErase,200)
      }
      XCTAssertEqual(document.store.document,original)
    }
  }
  @MainActor func testHTTPInvalidBusyStaleLayerAndTargetMismatchAreAtomic() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      let selected=try await helper.edit(service,document,"channel.target",["channel":"Red"]);XCTAssertEqual(selected,200)
      let fields:[String:Any]=["points":[["x":2.5,"y":2.5]],"brush":["size":1,"hardness":1]]
      let stale=try await helper.edit(service,document,"paint.stroke",fields,revision:"stale");XCTAssertEqual(stale,409)
      var wrong=fields;wrong["target"]="layerMask"
      let mask=try await helper.edit(service,document,"paint.stroke",wrong);XCTAssertEqual(mask,422)
      let mismatch=try await helper.edit(service,document,"mode.channel.edit",["layerID":original.layers[0].id.uuidString,"components":[1],"action":"invert"]);XCTAssertEqual(mismatch,422)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"paint.stroke",fields);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testNeutralFillLiteralBytesAndUndoStayCompatibleWithLegacyCommand() async throws {
    let original=try fixture(),s=EditorStore(document:original);defer{close(s)};try s.selectEditingChannel(.red)
    try s.executeEditorCommand(s.componentFillCommand(value:0.25,opacity:0.4))
    let p=try pixels(s.document).pixel(x:2,y:2)
    let bytes=[p.r,p.g,p.b,p.a].map {UInt8((unit($0)*255).rounded())}
    XCTAssertEqual(bytes,[37,101,211,127]);XCTAssertEqual(s.session.undoStack.last?.label,"Fill")
    try capture("neutral-rgb8-fill",bytes);await s.undo();XCTAssertEqual(s.document,original)
    let caps=try XCTUnwrap(DocumentModeAPI.capabilities["legacyRGB8Tools"]as? [String:Any]);XCTAssertEqual(caps["targetStatePreserved"]as? Bool,true)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:DocumentModeAPI.capabilities))
  }
  @MainActor func testPaintStrokeAlsoUsesCapturedNativeComponentTarget() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try ModeChannelWorkflowTests().fixture(.cmyk,.u16)
      document.store.session=EditorSession(document:original);try service.share(document)
      try document.store.selectModeComponents([3])
      var brush=Brush();brush.size=1;brush.hardness=1;brush.color = .black
      var expected=original
      try ModeComponentEdit(layerID:original.layers[0].id,components:[3],operation:.stroke([.init(x:1.5,y:1.5)],brush)).apply(to:&expected)
      let status=try await helper.edit(service,document,"paint.stroke",["points":[["x":1.5,"y":1.5]],"brush":["size":1,"hardness":1,"color":["r":0,"g":0,"b":0,"a":1]]])
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
    }
  }
  func capture(_ name:String,_ bytes:[UInt8])throws {
    guard let folder=ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"]else{return}
    try Data(bytes).write(to:URL(fileURLWithPath:folder).appendingPathComponent(name+".bin"))
  }
}
