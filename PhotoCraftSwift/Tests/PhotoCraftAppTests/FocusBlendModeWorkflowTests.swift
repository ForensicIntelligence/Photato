import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class FocusBlendModeWorkflowTests:XCTestCase {
  private func document(_ depth:PixelDepth = .u8, mask:Bool=false)throws->CraftDocument {
    var d=try CraftDocument(width:48,height:32,depth:depth);var s=try Surface(width:48,height:32,depth:depth)
    for y in 0..<32 {for x in 0..<48 {s.setPixel(x:x,y:y,Pixel(x<24 ? 0.8:0.2,Float(y+1)/40,x<24 ? 0.3:0.7))}}
    d.layers[0].content = .raster(s);if mask {d.layers[0].mask=s};return d
  }
  @MainActor private func configure(_ store:EditorStore,_ tool:FocusTool,_ mode:PhotoCraftCore.BlendMode){
    store.chooseTool(WorkspaceCatalog.tool(tool.rawValue.lowercased()));store.retouchSettings.brush.size=12;store.retouchSettings.brush.hardness=0.6;store.retouchSettings.brush.opacity=0.63;store.retouchSettings.brush.flow=0.7;store.retouchSettings.brush.spacing=0.15;store.retouchSettings.brush.pressureSize=false;store.retouchSettings.brush.pressureOpacity=true;store.retouchSettings.brush.mode=mode;store.retouchSettings.focus.strength=0.65;store.retouchSettings.focus.protectDetail=false
  }
  private func points(_ tool:FocusTool)->[StrokePoint]{tool == .smudge ? [.init(x:18.5,y:16.5,pressure:0.8),.init(x:31.5,y:16.5,pressure:0.6)]:[.init(x:23.5,y:16.5,pressure:0.8)]}
  @MainActor private func begin(_ store:EditorStore,_ tool:FocusTool)async {let p=points(tool);store.beginClone(p[0]);for q in p.dropFirst(){store.extendClone(q)};await store.clonePrepareTask?.value;await store.retouchPreviewTask?.value}
  @MainActor private func stop(_ store:EditorStore){store.cancelClone();store.renderTask?.cancel();store.clonePrepareTask?.cancel();store.geometryTask?.cancel();store.retouchPreviewTask?.cancel()}
  @MainActor func testNativeAllModesCaptureCancelCommitUndoAndVersionedActions()async throws {
    for tool in FocusTool.allCases {for mode in FocusBlendModes.supported {
      let doc=try document(.u16),library=ActionLibrary(),store=EditorStore(document:doc,cloneState:CloneSources(),actions:library);defer{stop(store)}
      configure(store,tool,mode);await begin(store,tool);XCTAssertNil(store.error)
      let draft=try XCTUnwrap(store.cloneDraft);XCTAssertEqual(draft.brush.mode,mode);var expected=doc;try XCTUnwrap(draft.command).apply(to:&expected)
      store.retouchSettings.brush.mode = .normal;XCTAssertEqual(store.cloneDraft?.brush.mode,mode);store.cancelClone();XCTAssertEqual(store.document,doc);XCTAssertTrue(store.session.undoStack.isEmpty)
      configure(store,tool,mode);try store.startRecordingAction(name:"Focus mode",set:"Owned");await begin(store,tool);store.finishClone();await store.geometryTask?.value;await store.retouchPreviewTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertNotEqual(expected,doc);XCTAssertEqual(store.session.undoStack.count,1)
      let action=try store.stopRecordingAction(),bytes=try library.exportFile(action.id),decoded=try ActionLibraryFile.decode(bytes)
      XCTAssertEqual(decoded.version,mode == .normal ? 21:55)
      if mode != .normal {var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes)as?[String:Any]);raw["version"]=54;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:raw)))}
      await store.undo();XCTAssertEqual(store.document,doc);store.retouchSettings.brush.mode = .normal;store.playAction(decoded.actions[0]);await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.document,expected)
      await store.undo();XCTAssertEqual(store.document,doc);await store.redo();XCTAssertEqual(store.document,expected)
    }}
  }
  @MainActor func testHTTPAllModesMatchCapturedNativeAtEveryDepthWithUndo()async throws {
    let helper=AutomationTests();try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,document in
      for depth in PixelDepth.allCases {for tool in FocusTool.allCases {for mode in FocusBlendModes.supported {
        let doc=try self.document(depth);document.store.session=EditorSession(document:doc);try service.share(document)
        let native=EditorStore(document:doc,cloneState:CloneSources(),actions:ActionLibrary());defer{self.stop(native)};self.configure(native,tool,mode);await self.begin(native,tool)
        let draft=try XCTUnwrap(native.cloneDraft);var expected=doc;try XCTUnwrap(draft.command).apply(to:&expected)
        let parameters:[String:Any]=["tool":tool.rawValue.lowercased(),"points":BrushAPI.json(draft.points),"brush":BrushAPI.json(draft.brush),"focus":BrushAPI.json(draft.focusOptions)]
        let status=try await helper.edit(service,document,"retouch.stroke",parameters);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
        XCTAssertEqual(document.store.session.undoStack.count,expected==doc ? 0:1)
        if expected != doc {let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,doc)}
      }}}
    }
  }
  @MainActor func testNativeModeRevisionNoOpAndHTTPStaleDefaultGuard()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,document in
      let doc=try self.document();document.store.session=EditorSession(document:doc);try service.share(document)
      var prior=service.revision(document.store)
      for settings in [document.store.cloneState.blur,document.store.cloneState.sharpen,document.store.cloneState.smudge] {
        settings.brush.mode = .darken;let changed=service.revision(document.store);XCTAssertNotEqual(changed,prior)
        settings.brush.mode = .darken;XCTAssertEqual(service.revision(document.store),changed);prior=changed
      }
      XCTAssertEqual(document.store.document,doc);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let old=service.revision(document.store);document.store.cloneState.blur.brush.mode = .lighten
      let parameters:[String:Any]=["tool":"blur","points":[["x":23.5,"y":16.5]],"brush":["size":12]]
      let stale=try await helper.edit(service,document,"retouch.stroke",parameters,revision:old);XCTAssertEqual(stale,409);XCTAssertEqual(document.store.document,doc);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let status=try await helper.edit(service,document,"retouch.stroke",parameters);XCTAssertEqual(status,200);XCTAssertEqual(document.store.cloneState.blur.brush.mode,.lighten);XCTAssertNotEqual(document.store.document,doc)
    }
  }
  @MainActor func testHTTPMaskUnsupportedModesStaleAndBusyAreAtomic()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,document in
      let doc=try self.document(.f32,mask:true);document.store.session=EditorSession(document:doc);try service.share(document)
      let valid:[String:Any]=["tool":"smudge","target":"layerMask","points":[["x":18.5,"y":16.5],["x":31.5,"y":16.5]],"brush":["size":12,"mode":"Darken"],"focus":["strength":0.65]]
      for tool in ["blur","sharpen","smudge","dodge"] {var p=valid;p["tool"]=tool;p["brush"]=["mode":"Multiply"];if tool=="dodge"{p.removeValue(forKey:"focus")};let status=try await helper.edit(service,document,"retouch.stroke",p);XCTAssertEqual(status,400);XCTAssertEqual(document.store.document,doc);XCTAssertTrue(document.store.session.undoStack.isEmpty)}
      let stale=try await helper.edit(service,document,"retouch.stroke",valid,revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"retouch.stroke",valid);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let status=try await helper.edit(service,document,"retouch.stroke",valid);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document.layers[0].content,doc.layers[0].content);XCTAssertNotEqual(document.store.document.layers[0].mask,doc.layers[0].mask)
      await document.store.undo();XCTAssertEqual(document.store.document,doc)
    }
  }
  @MainActor func testNativeMasksAndSampleAllLayersPreserveSourcesAndCapturedMode()async throws {
    for tool in FocusTool.allCases {
      var doc=try document(.u16);let base=doc.layers[0];doc.layers.append(Layer(name:"Retouch",content:.raster(try Surface(width:1,height:1,depth:.u16))));doc.activeLayerID=doc.layers.last!.id
      let store=EditorStore(document:doc,cloneState:CloneSources());defer{stop(store)};configure(store,tool,.color);store.retouchSettings.focus.sampleAllLayers=true;await begin(store,tool)
      let draft=try XCTUnwrap(store.cloneDraft);XCTAssertEqual(draft.brush.mode,.color);store.retouchSettings.brush.mode = .lighten;store.retouchSettings.focus.sampleAllLayers=false;store.finishClone();await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.document.layers[0],base);XCTAssertNotEqual(store.document,doc);await store.undo();XCTAssertEqual(store.document,doc)
      let masked=try document(.u16,mask:true),target=EditorStore(document:masked,cloneState:CloneSources());defer{stop(target)};configure(target,tool,.darken);target.selectMask(masked.layers[0].id);await begin(target,tool);target.finishClone();await target.geometryTask?.value;XCTAssertNil(target.error);XCTAssertEqual(target.document.layers[0].content,masked.layers[0].content);await target.undo();XCTAssertEqual(target.document,masked)
    }
  }
  @MainActor func testHostedPickerSchemaStateAndAllModifierCursorPolicies()throws {
    let expected=["Normal","Darken","Lighten","Hue","Saturation","Color","Luminosity"];XCTAssertEqual(FocusBlendModes.supported.map(\.rawValue),expected)
    let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name=="retouch.stroke"}),root=try XCTUnwrap(definition.schema["properties"]as?[String:Any]),parameters=try XCTUnwrap(root["parameters"]as?[String:Any]);XCTAssertNotNil(parameters["allOf"]);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:definition.schema));XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,60)
    let store=EditorStore(document:try document(),cloneState:CloneSources());defer{stop(store)};let flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for tool in FocusTool.allCases {for mode in FocusBlendModes.supported {configure(store,tool,mode);let view=NSHostingView(rootView:WorkspaceView(store:store).focusOptions);view.frame=NSRect(x:0,y:0,width:1000,height:45);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.bounds.width,0)
      let state=try XCTUnwrap(store.retouchToolState[tool.rawValue.lowercased()]as?[String:Any]),brush=try XCTUnwrap(state["brush"]as?[String:Any]);XCTAssertEqual(brush["mode"]as?String,mode.rawValue)
      for bits in 0..<16 {let modifiers=flags.enumerated().reduce(NSEvent.ModifierFlags()){v,p in bits&(1<<p.offset) != 0 ? v.union(p.element):v};let cursor=store.tool.cursor(modifiers:modifiers);XCTAssertFalse(cursor.native.image.size.width==0)}
    }}
  }
}
