import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class DocumentGuideWorkflowTests:XCTestCase {
  func input()throws->Data {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/SourceGuides")
    return try Data(contentsOf:folder.appendingPathComponent("guides-u8.pcraft"))
  }
  @MainActor func testNativeDialogPreviewCancelCommitAndStaleDocument()async throws {
    let original=try CraftDocument(width:24,height:16),store=EditorStore(document:original);defer{store.renderTask?.cancel()}
    store.beginGuides(.create);var draft=try XCTUnwrap(store.guideDraft);draft.axis = .horizontal;draft.position="25%"
    XCTAssertEqual(draft.previewLines?.last?.position,4);XCTAssertEqual(store.document,original)
    store.guideDraft=nil;XCTAssertEqual(store.document,original)
    store.beginGuides(.create);draft=try XCTUnwrap(store.guideDraft);draft.position="12.125 px";draft.color=Pixel(1,0,0);store.commitGuides(draft)
    XCTAssertNil(store.guideDraft);XCTAssertNil(store.error);XCTAssertEqual(store.document.guides?.first?.position,12.125)
    XCTAssertNotNil(DocumentIO.persistenceIssue(store.document,format:.psd));XCTAssertNil(DocumentIO.persistenceIssue(store.document,format:.native))
    let created=store.document;try await store.navigateHistory(redo:false);XCTAssertEqual(store.document,original);try await store.navigateHistory(redo:true);XCTAssertEqual(store.document,created)
    store.selectedGuideIDs=Set((created.guides ?? []).map(\.id));store.beginGuides(.edit);draft=try XCTUnwrap(store.guideDraft);draft.position="9px"
    var changedDocument=store.document;changedDocument.name="Changed";store.session=EditorSession(document:changedDocument);let changed=store.document;store.commitGuides(draft);XCTAssertNotNil(draft.error);XCTAssertEqual(store.document,changed);store.guideDraft=nil
    store.configureGuideView(locked:true);store.beginGuides(.create);XCTAssertNil(store.guideDraft)
  }
  @MainActor func testAPIAndDesktopGuideCommandsHistoryViewAndInvalidRequests()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      try service.share(document);let id=try XCTUnwrap(service.shares.first?.id),before=document.store.document,guide=DocumentGuide(axis:.vertical,position:2.125,color:Pixel(1,0,0))
      var expected=EditorSession(document:before);try expected.execute(.guides(.add([guide])))
      let parameters:[String:Any]=["operation":"add","guides":[["id":guide.id.uuidString,"axis":"vertical","position":2.125,"color":["r":1,"g":0,"b":0,"a":1]]]]
      @MainActor func command(_ name:String,_ p:[String:Any],revision:String?=nil)async throws->(HTTPURLResponse,Data) {try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":name,"revision":revision ?? service.revision(document.store),"parameters":p])}
      let add=try await command("guides.edit",parameters);XCTAssertEqual(add.0.statusCode,200,String(decoding:add.1,as:UTF8.self));XCTAssertEqual(document.store.document,expected.document)
      service.setDocumentTransfersEnabled(true)
      let deniedColor=try await helper.request(service,path:"/v1/documents/\(id)/file.psd");XCTAssertEqual(deniedColor.0.statusCode,422)
      let nativeColor=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"78"]);XCTAssertEqual(nativeColor.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(nativeColor.1),expected.document)

      let state=try XCTUnwrap(service.state(service.shares[0],document:document)["guides"]as?[String:Any]);XCTAssertEqual((state["items"]as?[[String:Any]])?.count,1)
      let locked=try await command("guides.view",["locked":true,"visible":false]);XCTAssertEqual(locked.0.statusCode,200);XCTAssertTrue(document.store.guidesLocked);XCTAssertFalse(document.store.showCanvasGuides)
      let denied=try await command("guides.edit",["operation":"clear"]);XCTAssertEqual(denied.0.statusCode,409);XCTAssertEqual(document.store.document,expected.document)
      let unlocked=try await command("guides.view",["locked":false,"visible":true]);XCTAssertEqual(unlocked.0.statusCode,200)
      let stale=try await command("guides.edit",["operation":"clear"],revision:"stale");XCTAssertEqual(stale.0.statusCode,409)
      let invalid=try await command("guides.edit",["operation":"add","guides":[["axis":"diagonal","position":1]]]);XCTAssertEqual(invalid.0.statusCode,400);XCTAssertEqual(document.store.document,expected.document)
      let undo=try await command("history.undo",[:]);XCTAssertEqual(undo.0.statusCode,200);XCTAssertEqual(document.store.document,before)
      let redo=try await command("history.redo",[:]);XCTAssertEqual(redo.0.statusCode,200);XCTAssertEqual(document.store.document,expected.document)
      document.store.beginGuides(.layout)
      let busy=try await command("guides.view",["locked":true]);XCTAssertEqual(busy.0.statusCode,409);document.store.guideDraft=nil
      XCTAssertNotNil(GuideAPI.capabilities["edit"])
    }
  }
  @MainActor func testSourceImportNative78TransferAndPSDPSBSaveMatchDesktop()async throws {
    let helper=AutomationTests(),io=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}){service,_ in
      defer{PSDAuxiliaryWorkflowTests().cleanup(service.controller)};service.setDocumentTransfersEnabled(true)
      let imported=try await io.request(service,path:"/v1/documents/import",data:input(),type:PcraftImport.mediaType)
      XCTAssertEqual(imported.0.statusCode,201,String(decoding:imported.1,as:UTF8.self))
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:imported.1)as?[String:Any]),id=try XCTUnwrap(state["id"]as?String),document=try XCTUnwrap(service.shares.first?.document),before=document.store.document
      XCTAssertEqual(before.guides?.count,10);XCTAssertEqual(before.minimumArchiveVersion,78)
      let old=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"77"]);XCTAssertEqual(old.0.statusCode,422)
      let current=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"78"]);XCTAssertEqual(current.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(current.1),before)
      for format in ["psd","psb"] {
        let response=try await helper.request(service,path:"/v1/documents/\(id)/file.\(format)");XCTAssertEqual(response.0.statusCode,200)
        XCTAssertEqual(response.1,try DocumentIO.encode(before,format:format=="psb" ? .psb:.psd));XCTAssertEqual(try PSDCodec.read(response.1).guides?.count,10)
      }
      XCTAssertEqual(document.store.document,before)
    }
  }
  @MainActor func testGuideCursorAllModifiersAndCapturedGestureGeometry()throws {
    let store=EditorStore(document:try CraftDocument(width:32,height:24)),canvas=CraftCanvas(store:store);defer{store.renderTask?.cancel()}
    canvas.frame=NSRect(x:0,y:0,width:640,height:480)
    let original=store.document,line=DocumentGuide(axis:.vertical,position:10)
    store.guideGesture=GuideGesture(original:original,lines:[line],start:.init(10,20),newGuide:false,current:[line])
    canvas.cursorLocationInView=CGPoint(x:100,y:100)
    for bits in 0..<16 {
      var flags:NSEvent.ModifierFlags=[]
      for (index,flag)in [NSEvent.ModifierFlags.control,.command,.option,.shift].enumerated() where bits&(1<<index) != 0 {flags.insert(flag)}
      canvas.updateCursorModifiers(flags)
      XCTAssertEqual(canvas.toolCursor,.symbol(flags.contains(.option) ? "arrow.up.and.down":"arrow.left.and.right",flags.contains(.shift) ? .constrain:nil))
      store.guideGesture?.update(.init(23,37),option:flags.contains(.option),shift:flags.contains(.shift),tick:10)
      let result=try XCTUnwrap(store.guideGesture?.current.first)
      XCTAssertEqual(result.axis,flags.contains(.option) ? .horizontal:.vertical)
      XCTAssertEqual(result.position,flags.contains(.option) ? (flags.contains(.shift) ? 40:37):(flags.contains(.shift) ? 20:23))
    }
    canvas.viewDidMoveToWindow();XCTAssertNil(store.guideGesture);XCTAssertEqual(store.document,original);XCTAssertFalse(store.hasToneDraft)
    var snapping=original;snapping.guides=[.init(axis:.vertical,position:30),.init(axis:.horizontal,position:40)];store.session=EditorSession(document:snapping)
    for bits in 0..<16 {
      var flags:NSEvent.ModifierFlags=[]
      for (index,flag)in [NSEvent.ModifierFlags.control,.command,.option,.shift].enumerated() where bits&(1<<index) != 0 {flags.insert(flag)}
      let offset=store.guideMoveOffset(.init(x:10,y:20,width:10,height:10),dx:7,dy:7,zoom:1,modifiers:flags)
      XCTAssertEqual(offset.0,flags.contains(.command) ? 7:10);XCTAssertEqual(offset.1,flags.contains(.command) ? 7:10)
    }
    store.tool = .move;canvas.cursorLocationInView=canvas.viewPoint(.init(x:30,y:20));canvas.updateCursorModifiers([.shift,.option]);store.selectedGuideIDs=[]
    XCTAssertEqual(canvas.toolCursor,.symbol("arrow.left.and.right",.add))
    store.selectedGuideIDs=[try XCTUnwrap(snapping.guides?.first?.id)]
    XCTAssertEqual(canvas.toolCursor,.symbol("arrow.left.and.right",.subtract))

  }
  @MainActor func testLegacyNativeResourcesBecomeEditableBeforeDesktopOrAPIChanges()throws {
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/SourceGuides/independent-guides.psd")
    let emptyResourceFile=fixture.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("photoshop-solid-8.psd")
    let noGuides=try PSDCodec.read(Data(contentsOf:emptyResourceFile));XCTAssertNil(noGuides.guides);XCTAssertLessThan(noGuides.minimumArchiveVersion,78)
    XCTAssertEqual(try DocumentGuideInput.adoptingLegacyGuides(noGuides),noGuides)
    var legacy=try PSDCodec.read(Data(contentsOf:fixture));legacy.guides=nil
    let bytes=try NativeArchive.encode(legacy),decoded=try DocumentIO.decode(bytes,native:true,name:"Legacy")
    XCTAssertEqual(decoded.guides?.count,10);XCTAssertEqual(decoded.minimumArchiveVersion,78)
    XCTAssertEqual(decoded,try DocumentIO.decode(bytes,native:true,name:"Legacy"));XCTAssertEqual(decoded.layers,legacy.layers)
    let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".photato");try bytes.write(to:file);defer{try? FileManager.default.removeItem(at:file)}
    XCTAssertEqual(try DocumentIO.readNative(file),decoded)
    var session=EditorSession(document:decoded);let line=DocumentGuide(axis:.vertical,position:2)
    try session.execute(.guides(.add([line])));XCTAssertEqual(session.document.guides?.count,11)
    let output=try PSDCodec.read(PSDCodec.writeRasterLayers(session.document));XCTAssertEqual(output.guides?.count,11)
  }
  @MainActor func testFactoryGuideMenuBindingsAndShortcutDefaults()throws {
    let helper=PhotoshopMenuTests()
    try helper.withMenus{_,menu in
      let items=helper.allItems(menu)
      for title in ["New Guide…","New Guide Layout…","Edit Selected Guides","Clear Canvas Guides","Lock Guides"] {
        let item=try XCTUnwrap(items.first{$0.title==title});XCTAssertNotNil(item.action)
      }
      let lock=try XCTUnwrap(items.first{$0.title=="Lock Guides"});XCTAssertEqual(lock.keyEquivalent,";");XCTAssertEqual(lock.keyEquivalentModifierMask,[.option,.command])
      let snap=try XCTUnwrap(items.first{$0.title=="Snap"});XCTAssertEqual(snap.keyEquivalent,";");XCTAssertEqual(snap.keyEquivalentModifierMask,[.shift,.command])
    }
  }
}
