import AppKit
import SwiftUI
import XCTest
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class SourceAdjustmentWorkflowTests:XCTestCase {
  struct Entry:Decodable {let name:String,depth:String,settings:SourceAdjustment,project:String,source:String}
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/SourceAdjustments")
  func data(_ name:String)throws->Data {try Data(contentsOf:root.appendingPathComponent(name))}
  func entries()throws->[Entry] {try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func status(_ actual:Int,_ expected:Int,file:StaticString=#filePath,line:UInt=#line){XCTAssertEqual(actual,expected,file:file,line:line)}
  @MainActor func testNativePropertiesAllKindsFloatEditsHistoryAndPersistence()async throws {
    _ = NSApplication.shared
    for e in try entries() where e.depth=="u8" {
      let original=try PcraftImport.read(data(e.source));var d=original;let layer=try e.settings.layer(in:d);try Command.addLayer(layer).apply(to:&d);let store=EditorStore(document:d,actions:ActionLibrary());defer{store.renderTask?.cancel()}
      let view=NSHostingView(rootView:SourceAdjustmentEditor(store:store,layerID:layer.id));view.frame=NSRect(x:0,y:0,width:320,height:900);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.height,0)
      var value=e.settings
      if let key=value.parameters.keys.sorted().first,key != "size",key != "levels" {value.parameters[key] = (value.parameters[key] ?? 0)*0.5;store.setSourceAdjustment(layer.id,value);XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,value==e.settings ? 0:1);if value != e.settings {await store.undo();XCTAssertEqual(store.document,d);await store.redo()}}
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(store.document)),store.document);XCTAssertEqual(store.document.minimumArchiveVersion,74)
    }
  }
  @MainActor func testNativeHTTPCreateSetApplyEqualityAllDepthsAndAtomicGuards()async throws {
    let helper=AutomationTests()
    for e in try entries() where e.name=="vibrance-16" || e.name=="mixer-False" || e.name=="curves-fractional" || e.name=="gradient-reverse-dither" || e.name=="lookup-31" {
      try await helper.withService(pressedMouseButtons:{0}) {service,document in
        try service.share(document);let original=try PcraftImport.read(self.data(e.source)),id=original.layers[0].id;document.store.session=EditorSession(document:original);document.store.selectedLayerIDs=[id]
        var desktop=EditorSession(document:original);try desktop.execute(.applyAdjustment(id,.source(e.settings)))
        self.status(try await helper.edit(service,document,"adjustment.apply",["layerID":id.uuidString,"adjustment":e.settings.apiObject]),200)
        XCTAssertEqual(document.store.document,desktop.document);XCTAssertEqual(try Renderer.composite(document.store.document),try Renderer.composite(desktop.document));let edited=document.store.document
        self.status(try await helper.edit(service,document,"history.undo"),200);XCTAssertEqual(document.store.document,original);self.status(try await helper.edit(service,document,"history.redo"),200);XCTAssertEqual(document.store.document,edited)
        let stale=service.revision(document.store)
        self.status(try await helper.edit(service,document,"adjustment.create",["adjustment":e.settings.apiObject,"name":"Owned original adjustment"]),200)
        let created=try XCTUnwrap(document.store.document.layers.last);guard case .adjustment(.source(let settings))=created.content else {return XCTFail("Created typed source adjustment")};XCTAssertEqual(settings,e.settings)
        self.status(try await helper.edit(service,document,"adjustment.set",["layerID":created.id.uuidString,"adjustment":e.settings.apiObject],revision:stale),409)
        let before=document.store.document,history=document.store.session.undoStack.count
        self.status(try await helper.edit(service,document,"adjustment.set",["layerID":created.id.uuidString,"adjustment":e.settings.apiObject]),200);XCTAssertEqual(document.store.document,before);XCTAssertEqual(document.store.session.undoStack.count,history)
        var bad=e.settings.apiObject;bad["extra"]=1;self.status(try await helper.edit(service,document,"adjustment.set",["layerID":created.id.uuidString,"adjustment":bad]),400);XCTAssertEqual(document.store.document,before)
        document.store.coalescingChanges=true
        self.status(try await helper.edit(service,document,"adjustment.set",["layerID":created.id.uuidString,"adjustment":e.settings.apiObject]),409);document.store.coalescingChanges=false;XCTAssertEqual(document.store.document,before)
      }
    }
  }
  @MainActor func testAllKindsAPICreationStateSchemaAndTypeValidation()async throws {
    let helper=AutomationTests()
    for e in try entries() where e.depth=="u8" {
      XCTAssertEqual(try SourceAdjustment.decodeAPI(e.settings.apiObject),e.settings)
      try await helper.withService(pressedMouseButtons:{0}){service,document in
        try service.share(document);let d=try PcraftImport.read(self.data(e.source));document.store.session=EditorSession(document:d)
        self.status(try await helper.edit(service,document,"adjustment.create",["adjustment":e.settings.apiObject]),200)
        let layer=try XCTUnwrap(document.store.document.layers.last);guard case .adjustment(.source(let a))=layer.content else {return XCTFail("Original adjustment created")};XCTAssertEqual(a,e.settings)
        let state=service.state(try XCTUnwrap(service.shares.first),document:document),layers=try XCTUnwrap(state["layers"]as?[[String:Any]]);XCTAssertNotNil(layers.last?["sourceAdjustment"])
        let before=document.store.document
        let other=SourceAdjustment(.invert);if other.kind != e.settings.kind {self.status(try await helper.edit(service,document,"adjustment.set",["layerID":layer.id.uuidString,"adjustment":other.apiObject]),422);XCTAssertEqual(document.store.document,before)}
      }
    }
    XCTAssertEqual((SourceAdjustment.apiCapabilities["editableKinds"]as?[String])?.count,16);XCTAssertEqual(SourceAdjustment.apiCapabilities["adobeCompatible"]as?Bool,false)
  }
  @MainActor func testActions29Native74HTTPNegotiationAndLegacyVersions()async throws {
    let e=try XCTUnwrap(entries().first{$0.name.hasPrefix("brightness-False") && $0.settings.parameters["brightness"] != 0}),d=try PcraftImport.read(data(e.source)),id=d.layers[0].id;let command=Command.applyAdjustment(id,.source(e.settings)),operation=try XCTUnwrap(ActionOperation(recording:command,in:d)),action=RecordedAction(name:"Owned source adjustment",steps:[.init(name:"Apply original",operation:operation)])
    let file=ActionLibraryFile(actions:[action]);XCTAssertEqual(file.requiredVersion,29);XCTAssertEqual(try ActionLibraryFile.decode(file.encoded()).version,29)
    let old=ActionLibraryFile(actions:[RecordedAction(name:"Old Invert",steps:[.init(name:"Invert",operation:.adjustment(.active,.invert))])]);XCTAssertLessThan(old.requiredVersion,29)
    var session=EditorSession(document:d);try session.execute(.action(action));var expected=d;try command.apply(to:&expected);XCTAssertEqual(session.document,expected);try session.undo();XCTAssertEqual(session.document,d)
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,document in
      service.setDocumentTransfersEnabled(true);try service.share(document);var source=d;try Command.addLayer(e.settings.layer(in:d)).apply(to:&source);document.store.session=EditorSession(document:source);let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
      let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"73"]);XCTAssertEqual(old.0.statusCode,422)
      let current=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"74"]);XCTAssertEqual(current.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(current.1),source)
    }
  }
}
