import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class ColorRangeGate:@unchecked Sendable {
  let condition=NSCondition();var released=false
  func wait(){condition.lock();while !released{condition.wait()};condition.unlock()}
  func release(){condition.lock();released=true;condition.broadcast();condition.unlock()}
}
final class ColorRangeWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:24,height:16,depth:depth);var pixels=try Surface(width:24,height:16,depth:depth,fill:Pixel(1,0,0));for y in 0..<16{for x in 12..<24{pixels.setPixel(x:x,y:y,Pixel(0,1,0))}};d.layers[0].content = .raster(pixels);return d
  }
  @MainActor func settle(_ m:ColorRangeWorkspace)async {for _ in 0..<30{await m.task?.value;if !m.loading && !m.rendering{return};await Task.yield()}}
  func testCompositeProfilesDepthsPriorSelectionAndNoRasterDependency()throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth);d.workingICC=try ColorManagement.importedProfile(XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3)?.copyICCData() as Data?),depth:depth)
      d.selection = .init(x:0,y:0,width:8,height:16)
      let input=try ColorRangeInput.prepare(d);var settings=ColorRangeSettings();settings.kind = .reds
      let mask=try input.mask(settings);XCTAssertGreaterThan(mask.byte(at:2),0);XCTAssertEqual(mask.byte(at:10),0);XCTAssertEqual(mask.byte(at:20),0)
      var result=d;try input.command(settings).apply(to:&result);XCTAssertEqual(result.depth,depth);XCTAssertEqual(result.workingICC,d.workingICC);XCTAssertEqual(result.layers,d.layers)
      d.layers[0].locked=true;XCTAssertNoThrow(try ColorRangeInput.prepare(d).command(settings))
    }
  }
  @MainActor func testNativePreviewSamplingCancelCommitAndUndo()async throws {
    let original=try fixture(),s=EditorStore(document:original,brushes:BrushLibrary());defer{s.cancelColorRange();s.renderTask?.cancel()}
    s.beginColorRange();let m=try XCTUnwrap(s.colorRangeDraft);await settle(m);XCTAssertNotNil(m.sourceImage);XCTAssertNotNil(m.selectionImage);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    m.sample(x:2,y:2,mode:.sample);await settle(m);XCTAssertEqual(m.settings.samples.count,1);XCTAssertGreaterThan(m.mask?.byte(at:2) ?? 0,240)
    m.sample(x:20,y:2,mode:.add);await settle(m);XCTAssertEqual(m.settings.samples.count,2);XCTAssertGreaterThan(m.mask?.byte(at:20) ?? 0,240)
    m.sample(x:2,y:2,mode:.subtract);await settle(m);XCTAssertEqual(m.mask?.byte(at:2),0)
    for view in ColorRangePreview.allCases {m.preview=view;m.refresh();await settle(m);XCTAssertNotNil(m.previewImage);XCTAssertNil(m.error)}
    let expected=try XCTUnwrap(m.mask);s.commitColorRange();await m.commitTask?.value;XCTAssertNil(m.error);XCTAssertNil(s.colorRangeDraft);XCTAssertEqual(s.document.selectionMask,expected);XCTAssertEqual(s.session.undoStack.last?.label,"Color Range")
    _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
    s.beginColorRange();let cancelled=try XCTUnwrap(s.colorRangeDraft);s.cancelColorRange();await settle(cancelled);XCTAssertTrue(cancelled.closed);XCTAssertTrue(s.document==original)
  }
  @MainActor func testNativeStaleSourceAndDocumentReadCloseCancel()async throws {
    let original=try fixture(),doc=CraftNSDocument(model:original),s=doc.store;defer{s.cancelColorRange();s.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}
    s.beginColorRange();let m=try XCTUnwrap(s.colorRangeDraft);await settle(m);m.sample(x:2,y:2,mode:.sample);await settle(m)
    try s.executeEditorCommand(.renameLayer(original.layers[0].id,"External change"));s.commitColorRange();await m.commitTask?.value;XCTAssertNotNil(m.error);XCTAssertNil(s.document.selection);s.cancelColorRange()
    s.beginColorRange();let reading=try XCTUnwrap(s.colorRangeDraft);try doc.read(from:NativeArchive.encodeChunked(original),ofType:CraftNSDocument.nativeType);await settle(reading);XCTAssertNil(s.colorRangeDraft);XCTAssertTrue(reading.closed)
    s.beginColorRange();let closing=try XCTUnwrap(s.colorRangeDraft);doc.close();await settle(closing);XCTAssertNil(s.colorRangeDraft);XCTAssertTrue(closing.closed)
  }
  @MainActor func testAPIEqualsNativeSettingsAndPresetsWithHistory()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try self.fixture(),s=doc.store;s.session=EditorSession(document:original);try service.share(doc)
      var settings=ColorRangeSettings();settings.kind = .greens;settings.fuzziness=20
      for params:[String:Any] in [["settings":BrushAPI.json(settings)],["presetBase64":try settings.presetData().base64EncodedString()]] {
        s.session=EditorSession(document:original);let code=try await h.edit(service,doc,"selection.colorRange",params);XCTAssertEqual(code,200)
        var expected=original;try ColorRangeInput.prepare(original).command(settings).apply(to:&expected);XCTAssertTrue(s.document==expected);XCTAssertEqual(s.colorRangeSettings,settings);XCTAssertEqual(s.session.undoStack.count,1)
        _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original);_=await s.requestHistory(redo:true).value;XCTAssertTrue(s.document==expected)
      }
      let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.colorRangeState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:ColorRangeAPI.stateSchema))
      let schema=try XCTUnwrap(AutomationCommand.definitions.first{$0.name=="selection.colorRange"});let root=try XCTUnwrap(schema.schema["properties"] as? [String:Any]),parameters=try XCTUnwrap(root["parameters"] as? [String:Any]);XCTAssertEqual((parameters["properties"] as? [String:Any])?.count,2)
    }
  }
  @MainActor func testAPIInvalidBusyStaleAndDeterministicRevocation()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try self.fixture(),s=doc.store;s.session=EditorSession(document:original);try service.share(doc)
      let bad:[[String:Any]]=[["settings":["fuzziness":201]],["settings":["kind":"skinTones"]],["settings":["unknown":1]],["settings":["samples":[["color":["r":1,"g":0,"b":0,"a":1],"point":["x":2,"y":0]]]]],["settings":["minimum":200,"maximum":1]],["settings":["localized":true]],["presetBase64":"bad!"],["settings":[:],"presetBase64":"e30="]]
      for params in bad {let code=try await h.edit(service,doc,"selection.colorRange",params);XCTAssertEqual(code,400);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)}
      let stale=try await h.edit(service,doc,"selection.colorRange",[:],revision:"old");XCTAssertEqual(stale,409)
      s.beginColorRange();let busy=try await h.edit(service,doc,"selection.colorRange",[:]);XCTAssertEqual(busy,409);s.cancelColorRange()
      let gate=ColorRangeGate();s.colorRangePreparation={document in gate.wait();try Task.checkCancellation();return try ColorRangeInput.prepare(document)}
      let request=Task{try await h.edit(service,doc,"selection.colorRange",["settings":["kind":"reds"]])}
      let until=Date().addingTimeInterval(10);while !s.geometryBusy && Date()<until{await Task.yield()};XCTAssertTrue(s.geometryBusy)
      service.revoke(try XCTUnwrap(service.shares.first{$0.document === doc}?.id));gate.release();let revoked=try await request.value;XCTAssertEqual(revoked,409);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testAll16CursorModesCapturedGestureAndRestoration()async throws {
    let s=EditorStore(document:try fixture(),brushes:BrushLibrary());defer{s.cancelColorRange();s.renderTask?.cancel()};s.beginColorRange();let m=try XCTUnwrap(s.colorRangeDraft);await settle(m)
    let menus=PhotoshopMenuTests();try menus.withMenus {_,menu in let item=try XCTUnwrap(menus.allItems(menu).first{$0.action == #selector(AppDelegate.colorRange)});XCTAssertEqual(item.title,"Color Range…");XCTAssertEqual(item.keyEquivalent,"")}
    let view=ColorRangeCanvasView();view.model=m;view.frame = .init(x:0,y:0,width:240,height:160)
    let flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for sampler in ColorRangeSampler.allCases {m.sampler=sampler;for n in 0..<16 {
      let f=flags.enumerated().reduce(NSEvent.ModifierFlags()){result,item in n & (1<<item.offset) != 0 ? result.union(item.element):result}
      let expected:ColorRangeSampler=f.contains(.option) ? .subtract:f.contains(.shift) ? .add:sampler
      view.updateCursorModifiers(f);XCTAssertEqual(ToolCursor.colorRangeSampler(sampler,modifiers:f),expected);XCTAssertEqual(view.toolCursor,ToolCursor.colorRange(expected))
    }}
    m.sampler = .sample;let down=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:.init(x:40,y:40),modifierFlags:.shift,timestamp:1,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1));view.mouseDown(with:down)
    XCTAssertEqual(view.capturedSampler,.add);view.updateCursorModifiers(.option);XCTAssertEqual(view.toolCursor,ToolCursor.colorRange(.add))
    let drag=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDragged,location:.init(x:160,y:80),modifierFlags:.option,timestamp:1.5,windowNumber:0,context:nil,eventNumber:2,clickCount:1,pressure:1));view.mouseDragged(with:drag);XCTAssertEqual(m.settings.samples.last?.subtract,false)
    let up=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseUp,location:.init(x:40,y:40),modifierFlags:.option,timestamp:2,windowNumber:0,context:nil,eventNumber:2,clickCount:1,pressure:0));view.mouseUp(with:up);XCTAssertNil(view.capturedSampler);XCTAssertEqual(view.toolCursor,ToolCursor.colorRange(.subtract));view.clearCursorInput();XCTAssertEqual(view.toolCursor,ToolCursor.colorRange(.sample));XCTAssertNil(view.cursorGestureModifiers)
    m.settings.kind = .reds;view.refreshToolCursor();XCTAssertEqual(view.toolCursor,.arrow)
  }
}
