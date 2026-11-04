import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class CanvasEdgeWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var source=try CraftDocument(width:8,height:6)
    var pixels=try Surface(width:8,height:6)
    for y in 2..<4{for x in 3..<5{pixels.setPixel(x:x,y:y,Pixel(1,0,0))}}
    source.layers[0].content = .raster(pixels);return source
  }
  @MainActor func testNativeTrimDefaultsCancelStaleAndUndo()async throws {
    let source=try fixture(),s=EditorStore(document:source);defer{s.geometryTask?.cancel();s.renderTask?.cancel()}
    s.beginTrim();let cancelled=try XCTUnwrap(s.trimDraft);XCTAssertEqual(cancelled.options.basis,.topLeft);XCTAssertTrue(cancelled.options.hasEdges);XCTAssertTrue(s.hasToneDraft)
    s.cancelTrim();s.commitTrim(cancelled);XCTAssertEqual(s.document,source);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginTrim();let stale=try XCTUnwrap(s.trimDraft);var changed=source;changed.name="Changed";s.session=EditorSession(document:changed);s.commitTrim(stale);XCTAssertNotNil(stale.error);s.cancelTrim()
    s.session=EditorSession(document:source);s.beginTrim();let draft=try XCTUnwrap(s.trimDraft);draft.options.basis = .transparent;s.commitTrim(draft);await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document.width,2);XCTAssertEqual(s.document.height,2);XCTAssertEqual(s.session.undoStack.count,1)
    _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,source)
  }
  @MainActor func testNativeRevealAllAndCapturedBackgroundAreUndoable()async throws {
    var source=try fixture();source.layers[0].x = -5
    let s=EditorStore(document:source);defer{s.geometryTask?.cancel();s.renderTask?.cancel()}
    s.applyCanvasEdges(.revealAll);await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document.width,10);XCTAssertEqual(s.document.layers[0].x,-3)
    _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,source)
    var paper=try DocumentCreation.blank(width:3,height:2,depth:.u8,background:Pixel(1,0,0),name:"Paper")
    var outside=Layer(name:"Outside",content:.raster(try Surface(width:1,height:1,fill:.white)));outside.x = -1;outside.y = -1;paper.layers.append(outside)
    let owner=EditorStore(document:paper);let saved=owner.backgroundColor;defer{owner.backgroundColor=saved;owner.geometryTask?.cancel();owner.renderTask?.cancel()}
    owner.backgroundColor=Pixel(0,0,1);owner.applyCanvasEdges(.revealAll);owner.backgroundColor=Pixel(0,1,0);await owner.geometryTask?.value
    XCTAssertNil(owner.error)
    guard case .raster(let pixels)=owner.document.layers[0].content else{return XCTFail("Background")}
    XCTAssertEqual(pixels.pixel(x:0,y:0),Pixel(0,0,1));XCTAssertEqual(owner.backgroundColor,Pixel(0,1,0))
  }
  @MainActor func testHTTPBothCommandsMatchNativeAndNativeArchive()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let source=try self.fixture();doc.store.session=EditorSession(document:source);try service.share(doc)
      let expected=try CanvasEdgePreparation.prepare(source,operation:.trim(.init(basis:.transparent))).result
      let trimmed=try await h.edit(service,doc,"document.trim",["basis":"transparent"]);XCTAssertEqual(trimmed,200);XCTAssertEqual(doc.store.document,expected);XCTAssertEqual(doc.store.session.undoStack.count,1)
      let undone=try await h.edit(service,doc,"history.undo");XCTAssertEqual(undone,200);XCTAssertEqual(doc.store.document,source)
      var shifted=source;shifted.layers[0].x = -5;doc.store.session=EditorSession(document:shifted)
      let revealExpected=try CanvasEdgePreparation.prepare(shifted,operation:.revealAll).result
      let revealed=try await h.edit(service,doc,"document.revealAll");XCTAssertEqual(revealed,200);XCTAssertEqual(doc.store.document,revealExpected)
      service.setDocumentTransfersEnabled(true);let id=try XCTUnwrap(service.shares.first?.id)
      let file=try await h.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"84"])
      XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),revealExpected)
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAndEmptyTrimAreAtomic()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let source=try self.fixture();doc.store.session=EditorSession(document:source);try service.share(doc)
      let invalid=try await h.edit(service,doc,"document.trim",["top":"yes"]);XCTAssertEqual(invalid,400)
      let badBasis=try await h.edit(service,doc,"document.trim",["basis":"invented"]);XCTAssertEqual(badBasis,400)
      let stale=try await h.edit(service,doc,"document.revealAll",revision:"stale");XCTAssertEqual(stale,409)
      doc.store.geometryBusy=true;let busy=try await h.edit(service,doc,"document.trim");doc.store.geometryBusy=false;XCTAssertEqual(busy,409)
      let badFill=try await h.edit(service,doc,"document.revealAll",["backgroundColor":[1,0]]);XCTAssertEqual(badFill,400)
      XCTAssertEqual(doc.store.document,source);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testInFlightCancellationAndRevocationCannotCommitEitherOperation()async throws {
    for command in CanvasEdgesAPI.commands {for revoke in [false,true] {
      let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
        let source=try self.fixture();doc.store.session=EditorSession(document:source);try service.share(doc)
        let gate=CanvasEdgeGate();defer{gate.release()};doc.store.canvasEdgePreparation={d,o,b in gate.wait();try Task.checkCancellation();return try CanvasEdgePreparation.command(d,operation:o,background:b)}
        let pending=Task{try await h.edit(service,doc,command,["basis":"transparent"].filter{_ in command=="document.trim"})};let deadline=Date().addingTimeInterval(10)
        while !doc.store.geometryBusy && Date()<deadline{await Task.yield()};XCTAssertTrue(doc.store.geometryBusy)
        if revoke{service.revoke(try XCTUnwrap(service.shares.first?.id))}else{doc.store.cancelActiveOperation()}
        gate.release();let status=try await pending.value;XCTAssertEqual(status,409);XCTAssertEqual(doc.store.document,source);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      }
    }}
  }
  @MainActor func testSemanticActions44ReplayAndRejectDowngradedFiles()throws {
    for operation in [CanvasEdgeOperation.trim(.init(basis:.transparent)),.revealAll] {
      var source=try fixture();if operation == .revealAll{source.layers[0].x = -5}
      var session=EditorSession(document:source);try session.startActionRecording(name:operation.label)
      try session.execute(CanvasEdgePreparation.command(source,operation:operation))
      let action=try XCTUnwrap(session.actionRecording?.snapshot),file=ActionLibraryFile(actions:[action]);XCTAssertEqual(file.requiredVersion,44)
      let bytes=try file.encoded();var downgraded=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]);downgraded["version"]=43
      XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:downgraded)))
      let played=try RecordedActionRenderer.prepare(action,in:source);var replay=EditorSession(document:source);try replay.execute(played.command);XCTAssertEqual(replay.document,session.document);XCTAssertEqual(replay.undoStack.count,1)
    }
  }
  @MainActor func testStateSchemasFactoryMenusAndCursorPolicyAreAligned()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()}
    let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.canvasEdgesState));XCTAssertNoThrow(try BrushAPI.merge(value,schema:CanvasEdgesAPI.stateSchema))
    func all(_ nodes:[EditorMenuNode])->[EditorMenuNode]{nodes.flatMap{[$0]+all($0.children ?? [])}}
    let items=all(PhotoshopMenuCatalog.menus)
    for title in ["Trim…","Reveal All"] {XCTAssertEqual(try XCTUnwrap(items.first{$0.title==title}).key,"")}
    XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount);XCTAssertEqual(ActionLibraryFile.maximumVersion,46)
    let canvas=CraftCanvas(store:s),flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for bits in 0..<16{let f=flags.enumerated().reduce(NSEvent.ModifierFlags()){r,p in bits&(1<<p.offset) != 0 ? r.union(p.element):r};canvas.updateCursorModifiers(f);let cursor=canvas.toolCursor;_=s.canvasEdgesState;canvas.updateCursorModifiers(f);XCTAssertEqual(canvas.toolCursor,cursor)}
  }
}
private final class CanvasEdgeGate:@unchecked Sendable {
  private let condition=NSCondition();private var open=false
  func wait(){condition.lock();while !open{condition.wait()};condition.unlock()}
  func release(){condition.lock();open=true;condition.broadcast();condition.unlock()}
}
