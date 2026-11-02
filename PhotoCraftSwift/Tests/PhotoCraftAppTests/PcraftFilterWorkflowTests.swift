import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PcraftFilterWorkflowTests:XCTestCase {
  struct Entry:Decodable {let name:String,command:String,depth:String,supported:Bool,cached:String}
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/PcraftFilters")
  func data(_ name:String)throws->Data{try Data(contentsOf:root.appendingPathComponent(name))}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  @MainActor func testEveryMappedProgramHasNativeEditorCancelAndAPINoOpState()throws {
    _ = NSApplication.shared
    for entry in try entries() where entry.supported && entry.depth=="u8" {
      let d=try PcraftImport.read(data(entry.cached)),layer=try XCTUnwrap(d.layers.first),stack=try XCTUnwrap(layer.smartFilters),item=try XCTUnwrap(stack.filters.first)
      let store=EditorStore(document:d,actions:ActionLibrary());defer{store.renderTask?.cancel();store.cancelFilter()}
      XCTAssertTrue(store.canBeginFilterKind(item.filter.kind),entry.name);store.beginSmartFilter(layer.id,filterID:item.id)
      XCTAssertEqual(store.filterDraft?.filter,item.filter,entry.name);XCTAssertEqual(store.filterDraft?.opacity,0.75);store.cancelFilter();XCTAssertTrue(store.document == d);XCTAssertTrue(store.session.undoStack.isEmpty)
      let state=stack.apiState;XCTAssertTrue(JSONSerialization.isValidJSONObject(state))
      let payload:[String:Any] = ["enabled":stack.enabled,"filters":state["filters"]!]
      let bytes=try JSONSerialization.data(withJSONObject:["command":"smartFilter.set","revision":"owned","parameters":["layerID":layer.id.uuidString,"stack":payload]])
      let request=try AutomationCommand(data:bytes),command=try request.smartFilterCommand(document:d);var result=d;try command.apply(to:&result);XCTAssertTrue(result == d,entry.name)
    }
    let capability=SourceSmartObjectAPI.capabilities,coverage=try XCTUnwrap(capability["sourceFilterCoverage"] as? [String:Any])
    XCTAssertEqual(coverage["declaredCommands"] as? Int,110);XCTAssertEqual(coverage["mappedCommands"] as? Int,110)
    XCTAssertEqual(Set(try XCTUnwrap(capability["sourceFilterCommands"] as? [String])),Set(PcraftImport.sourceSmartFilterCommands))
    XCTAssertTrue(JSONSerialization.isValidJSONObject(capability))
  }
  @MainActor func testNativeCommitAndHTTPChangesSharePixelsHistoryBusyAndStaleGuards()async throws {
    let helper=AutomationTests()
    for entry in try entries() where entry.supported && entry.depth=="u8" && (entry.name.hasSuffix("-custom") || entry.name=="gallery-stack") {
      try await helper.withService(pressedMouseButtons:{0}){service,document in
        let input=try self.data(entry.cached),d=try PcraftImport.read(input),layer=try XCTUnwrap(d.layers.first),item=try XCTUnwrap(layer.smartFilters?.filters.first)
        document.store.session=EditorSession(document:d);document.store.selectedLayerIDs=[layer.id];try service.share(document)
        let desktop=EditorStore(document:d,actions:ActionLibrary());defer{desktop.renderTask?.cancel();desktop.cancelFilter()}
        desktop.beginSmartFilter(layer.id,filterID:item.id);XCTAssertNotNil(desktop.filterDraft);desktop.filterDraft?.opacity=0.4;desktop.commitFilter();await desktop.geometryTask?.value;XCTAssertNil(desktop.error,entry.name)
        var stack=try XCTUnwrap(layer.smartFilters);stack.filters[0].opacity=0.4
        let payload:[String:Any] = ["enabled":stack.enabled,"filters":stack.apiState["filters"]!]
        let code=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":payload]);XCTAssertEqual(code,200,entry.name)
        XCTAssertTrue(document.store.document == desktop.document,entry.name);XCTAssertEqual(try Renderer.composite(document.store.document),try Renderer.composite(desktop.document));XCTAssertEqual(document.store.session.undoStack.count,1)
        let edited=document.store.document;await document.store.undo();XCTAssertTrue(document.store.document == d);await document.store.redo();XCTAssertTrue(document.store.document == edited)
        let stale=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":payload],revision:"stale");XCTAssertEqual(stale,409)
        document.store.beginSmartFilter(layer.id,filterID:item.id);let busy=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":payload]);document.store.cancelFilter();XCTAssertEqual(busy,409)
        XCTAssertTrue(document.store.document == edited);XCTAssertEqual(try self.data(entry.cached),input)
      }
    }
  }
  @MainActor func testRGB32LensCacheNoOpDisableUndoAndRenderRejectionAreAtomic()async throws {
    let input=try data("filter-blur-lensBlur-f32-cached.pcraft"),d=try PcraftImport.read(input),layer=try XCTUnwrap(d.layers.first),item=try XCTUnwrap(layer.smartFilters?.filters.first)
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,document in
      document.store.session=EditorSession(document:d);document.store.selectedLayerIDs=[layer.id];try service.share(document)
      XCTAssertFalse(document.store.canBeginFilterKind(.lensBlur));document.store.beginSmartFilter(layer.id,filterID:item.id);XCTAssertNil(document.store.filterDraft)
      func payload(_ stack:SmartFilterStack)->[String:Any]{["enabled":stack.enabled,"filters":stack.apiState["filters"]!]}
      let originalStack=try XCTUnwrap(layer.smartFilters)
      let noop=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":payload(originalStack)])
      XCTAssertEqual(noop,200);XCTAssertTrue(document.store.document == d);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      var disabled=originalStack;disabled.enabled=false
      let code=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":payload(disabled)])
      XCTAssertEqual(code,200);XCTAssertNil(document.store.activeLayer?.pristineSmartAppearance);XCTAssertEqual(document.store.session.undoStack.count,1)
      await document.store.undo();XCTAssertTrue(document.store.document == d);XCTAssertNotNil(document.store.activeLayer?.pristineSmartAppearance?.pixels)
      var changed=originalStack;changed.filters[0].opacity=0.4
      let rejected=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":payload(changed)])
      XCTAssertEqual(rejected,422);XCTAssertTrue(document.store.document == d);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(d)) == d);XCTAssertEqual(try self.data("filter-blur-lensBlur-f32-cached.pcraft"),input)
      var rasterized=EditorSession(document:d);try rasterized.execute(SmartObjectIO.rasterizationCommand(layer,in:d));XCTAssertNil(rasterized.document.layers[0].smartObject);XCTAssertEqual(try Renderer.composite(rasterized.document),try Renderer.composite(d));try rasterized.undo();XCTAssertTrue(rasterized.document == d)
    }
  }

}
