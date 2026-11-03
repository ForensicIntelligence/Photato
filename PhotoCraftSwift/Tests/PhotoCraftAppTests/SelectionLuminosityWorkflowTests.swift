import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class SelectionLuminosityWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var source=try CraftDocument(width:4,height:2);source.layers[0].background=nil
    var pixels=try Surface(width:4,height:2,fill:.black)
    for y in 0..<2 {for (x,p) in [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),Pixel(1,1,1)].enumerated(){pixels.setPixel(x:x,y:y,p)}}
    source.layers[0].content = .raster(pixels);return source
  }
  @MainActor func testNativeHTTPCompositeAndCustomGrayShareExactCoverageAndUndo()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,file in
      let model=try self.fixture();file.store.session=EditorSession(document:model);try service.share(file)
      file.store.loadSelectionSource(.composite);await file.store.geometryTask?.value
      XCTAssertNil(file.store.error);XCTAssertEqual(try file.store.document.coverageSelection()?.denseBytes(),[107,211,51,255,107,211,51,255])
      let native=file.store.document;await file.store.undo();XCTAssertEqual(file.store.document,model)
      let status=try await helper.edit(service,file,"channel.edit",["action":"loadSelection","source":["kind":"composite"]])
      XCTAssertEqual(status,200);XCTAssertEqual(file.store.document,native);XCTAssertEqual(file.store.document.layers,model.layers)
      let share=try XCTUnwrap(service.shares.first{$0.document === file})
      let state=try XCTUnwrap(service.state(share,document:file)["selectionChannels"]as? [String:Any])
      XCTAssertEqual(state["workingGrayProfile"]as? String,"Dot Gain 20%")
      await file.store.undo();var settings=service.controller.colorSettings.value
      try settings.setProfile(NativeModeProfile.standard(.grayscale,depth:.f32),for:.grayscale)
      try service.controller.colorSettings.commit(settings,revision:service.controller.colorSettings.revision)
      let custom=try await helper.edit(service,file,"channel.edit",["action":"loadSelection","source":["kind":"composite"]])
      XCTAssertEqual(custom,200);XCTAssertEqual(try file.store.document.coverageSelection()?.denseBytes(),[57,183,15,255,57,183,15,255])
      XCTAssertEqual(file.store.document.layers,model.layers);await file.store.undo();XCTAssertEqual(file.store.document,model)
    }
  }
  @MainActor func testNativeWorkingProfileChangeRejectsPreparedSelection()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,file in
      let original=try self.fixture();file.store.session=EditorSession(document:original)
      file.store.loadSelectionSource(.composite)
      var settings=service.controller.colorSettings.value;settings.blackPointCompensation=false
      try service.controller.colorSettings.commit(settings,revision:service.controller.colorSettings.revision)
      await file.store.geometryTask?.value
      XCTAssertNotNil(file.store.error);XCTAssertEqual(file.store.document,original);XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPWorkingProfileChangeRejectsInFlightSelectionAtomically()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,file in
      let original=try self.fixture();file.store.session=EditorSession(document:original);try service.share(file)
      service.selectionChannelPrepare={command,target,defaults,source,settings in
        try await Task.sleep(for:.milliseconds(150))
        return try SelectionChannelPreparation.prepare(command,target:target,defaults:defaults,source:source,colorSettings:settings)
      }
      let request=Task{try await helper.edit(service,file,"channel.edit",["action":"loadSelection","source":["kind":"composite"]])}
      for _ in 0..<250 where !file.store.geometryBusy {try await Task.sleep(for:.milliseconds(10))}
      XCTAssertTrue(file.store.geometryBusy)
      var settings=service.controller.colorSettings.value;settings.blackPointCompensation=false
      try service.controller.colorSettings.commit(settings,revision:service.controller.colorSettings.revision)
      let status=try await request.value;XCTAssertEqual(status,409)
      XCTAssertEqual(file.store.document,original);XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
}
