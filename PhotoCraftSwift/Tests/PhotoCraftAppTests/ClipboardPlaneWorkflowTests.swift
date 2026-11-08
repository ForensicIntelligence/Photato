import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ClipboardPlaneWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,_ kind:Int=0)throws->(CraftDocument,ClipboardPlaneTarget) {
    var d=try CraftDocument(width:8,height:6,depth:depth);var s=try Surface(width:8,height:6,depth:depth,fill:Pixel(0.25,0.25,0.25));s.setPixel(x:3,y:2,Pixel(0.75,0.75,0.75))
    let c=AlphaChannel(name:"Clipboard source",pixels:s)
    switch kind {
    case 0:d.alphaChannels=[c];return(d,.alpha(c.id))
    case 1:d.quickMask=c;return(d,.quickMask)
    case 2:d.layers[0].mask=s;return(d,.layerMask(d.layers[0].id))
    default:
      d.layers[0].smartObject=try SmartObject(fileName:"Owned.photato",mediaType:"application/vnd.photato.document",data:NativeArchive.encode(d),width:8,height:6)
      var stack=SmartFilterStack();stack.mask=s;d.layers[0].smartFilters=stack;try d.validate();return(d,.smartFilterMask(d.layers[0].id))
    }
  }
  @MainActor func select(_ target:ClipboardPlaneTarget,_ s:EditorStore)throws {
    switch target{case .alpha(let id):try s.selectAlphaChannel(id);case .quickMask:try s.selectQuickMaskChannel();case .layerMask(let id):s.selectMask(id);case .smartFilterMask(let id):s.selectSmartFilterMask(id)}
  }
  func gray(_ d:CraftDocument,_ target:ClipboardPlaneTarget)throws->Surface {
    if let t=target.channel{return try d.channel(t).pixels}
    let layer=try XCTUnwrap(d.layers.first{$0.id==target.layerID})
    if case .smartFilterMask=target{return try XCTUnwrap(layer.smartFilters?.mask)}
    return try XCTUnwrap(layer.mask)
  }
  @MainActor func testNativeEveryDepthTargetCopyCutPasteAndUndoUseSelectedPlane()async throws {
    for depth in PixelDepth.allCases{for kind in 0..<4 {
      var (d,target)=try fixture(depth,kind);d.selection = .init(x:2,y:1,width:3,height:3)
      let clipboard=MemoryClipboard(),s=EditorStore(document:d,clipboard:clipboard);defer{s.geometryTask?.cancel();s.renderTask?.cancel()};try select(target,s)
      s.backgroundColor = .black;let before=s.document
      XCTAssertTrue(s.canCopy());XCTAssertTrue(s.canCopy(cut:true));XCTAssertFalse(s.canCopy(merged:true));XCTAssertFalse(s.clipboardTargetAvailable)
      s.copyImage();await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertTrue(s.document==before);XCTAssertTrue(s.session.undoStack.isEmpty)
      let copied=try clipboard.read().decoded(),image=try XCTUnwrap(ClipboardPlane.numericImage(copied));XCTAssertEqual(image.values.pixel(x:1,y:1).r,try gray(d,target).pixel(x:3,y:2).r)
      s.copyImage(cut:true);await s.geometryTask?.value;XCTAssertNil(s.error);let cut=s.document
      XCTAssertEqual(try gray(cut,target).pixel(x:3,y:2).r,0);XCTAssertEqual(s.session.undoStack.last?.label,"Cut")
      s.pasteImage(.inPlace);await s.geometryTask?.value;XCTAssertNil(s.error);let pasted=s.document
      XCTAssertEqual(try gray(pasted,target).pixel(x:3,y:2).r,try gray(d,target).pixel(x:3,y:2).r)
      XCTAssertEqual(s.clipboardPlaneTarget,target);XCTAssertEqual(pasted.layers[0].content,d.layers[0].content)
      await s.undo();XCTAssertTrue(s.document==cut);await s.undo();XCTAssertTrue(s.document==before);await s.redo();await s.redo();XCTAssertTrue(s.document==pasted)
    }}
  }
  @MainActor func testNativeFailedCancelledAndStaleCopyNeverCutsOrPublishesClipboard()async throws {
    for mode in 0..<4 {
      var (d,target)=try fixture();d.selection = .init(x:2,y:1,width:3,height:3)
      let clipboard=MemoryClipboard(),s=EditorStore(document:d,clipboard:clipboard);defer{s.geometryTask?.cancel();s.renderTask?.cancel()};try select(target,s)
      if mode==0{clipboard.rejectWrites=true}
      s.copyImage(cut:true);let task=s.geometryTask
      if mode==1{task?.cancel()}else if mode==2{clipboard.changeCount += 1}else if mode==3{s.alphaEditingID=nil}
      await task?.value;XCTAssertTrue(s.document==d);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertNil(clipboard.value)
      if mode != 1{XCTAssertNotNil(s.error)}
    }
  }
  @MainActor func testNativeStaleAndCancelledPastePreserveTargetAndSource()async throws {
    for mode in 0..<3 {
      let (d,target)=try fixture(.u16,2),clipboard=MemoryClipboard(),s=EditorStore(document:d,clipboard:clipboard);defer{s.geometryTask?.cancel();s.renderTask?.cancel()};try select(target,s)
      try clipboard.write(ClipboardRepresentations(ClipboardContent.pixels(Surface(width:2,height:2,fill:.white))))
      s.pasteImage();let task=s.geometryTask
      if mode==0{task?.cancel()}else if mode==1{clipboard.changeCount += 1}else{s.maskEditingLayerID=nil}
      await task?.value;XCTAssertTrue(s.document==d);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testMaximumSparseNativePayloadOmitsFallbacksAndNamedPasteboardRetainsFullExtent()throws {
    var d=try CraftDocument(width:300000,height:300000,depth:.f32);let c=AlphaChannel(name:"Large",pixels:try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(0.25,0.25,0.25)));d.alphaChannels=[c]
    let copied=try ClipboardPlane.copy(d,target:.alpha(c.id)),representations=try ClipboardRepresentations(copied)
    XCTAssertNil(representations.tiff);XCTAssertNil(representations.png);XCTAssertLessThan(representations.native.count,1024*1024)
    let pasteboard=NSPasteboard(name:.init("Photato-plane-test-"+UUID().uuidString));defer{pasteboard.releaseGlobally()};let access=SystemClipboard(pasteboard:pasteboard)
    try access.write(representations);let result=try access.read().decoded();XCTAssertEqual(result.bounds.width,300000);XCTAssertEqual(result.bounds.height,300000)
    let image=try XCTUnwrap(ClipboardPlane.numericImage(result));XCTAssertEqual(image.values.pixel(x:299999,y:299999).r,0.25);XCTAssertNil(pasteboard.data(forType:.png));XCTAssertNil(pasteboard.data(forType:.tiff))
  }
  @MainActor func testHTTPNativeCopyCutPasteEquivalenceEveryDepthAndTargetWithoutSystemClipboardAccess()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,file in
      for depth in PixelDepth.allCases{for kind in 0..<4 {
        var (d,target)=try fixture(depth,kind);d.selection = .init(x:2,y:1,width:3,height:3);file.store.session=EditorSession(document:d);try service.share(file)
        let clipboard=MemoryClipboard(),native=EditorStore(document:d,clipboard:clipboard);defer{native.geometryTask?.cancel();native.renderTask?.cancel()};try select(target,native);native.backgroundColor = .black
        let id=try XCTUnwrap(service.shares.first?.id),revision=service.revision(file.store)
        let (http,data)=try await h.request(service,path:"/v1/documents/\(id)/commands",body:["command":"clipboard.copy","revision":revision,"parameters":["target":ClipboardPlaneAPI.json(target)]])
        XCTAssertEqual(http.statusCode,200);let payload=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]),base64=try XCTUnwrap(payload["payloadBase64"]as?String),bytes=try XCTUnwrap(Data(base64Encoded:base64)),image=try XCTUnwrap(ClipboardPlane.numericImage(ClipboardAPI.decode(bytes)))
        XCTAssertEqual(image.values.pixel(x:1,y:1).r,try gray(d,target).pixel(x:3,y:2).r);XCTAssertEqual(service.revision(file.store),revision);XCTAssertTrue(file.store.session.undoStack.isEmpty)
        native.copyImage(cut:true);await native.geometryTask?.value
        var status=try await h.edit(service,file,"clipboard.cut",["target":ClipboardPlaneAPI.json(target),"backgroundValue":0]);XCTAssertEqual(status,200);XCTAssertTrue(file.store.document==native.document)
        native.pasteImage(.inPlace);await native.geometryTask?.value
        status=try await h.edit(service,file,"clipboard.paste",["target":ClipboardPlaneAPI.json(target),"payloadBase64":base64,"placement":"inPlace"]);XCTAssertEqual(status,200);XCTAssertTrue(file.store.document==native.document)
        status=try await h.edit(service,file,"history.undo");XCTAssertEqual(status,200);await native.undo();XCTAssertTrue(file.store.document==native.document)
      }}
    }
  }
  @MainActor func testHTTPInvalidTargetsOptionsStaleBusyAndLocksAreAtomic()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,file in
      let (d,target)=try fixture();file.store.session=EditorSession(document:d);try service.share(file)
      for params:[String:Any]in [["target":["kind":"unknown"]],["target":["kind":"alpha","channelID":"bad"]],["target":ClipboardPlaneAPI.json(target),"merged":true],["target":ClipboardPlaneAPI.json(target),"layerIDs":[d.layers[0].id.uuidString]]] {
        let status=try await h.edit(service,file,"clipboard.copy",params);XCTAssertEqual(status,400);XCTAssertTrue(file.store.document==d)
      }
      var status=try await h.edit(service,file,"clipboard.cut",["backgroundValue":0]);XCTAssertEqual(status,400)
      status=try await h.edit(service,file,"clipboard.copy",["target":["kind":"alpha","channelID":UUID().uuidString]]);XCTAssertEqual(status,422)
      file.store.geometryBusy=true;status=try await h.edit(service,file,"clipboard.copy",["target":ClipboardPlaneAPI.json(target)]);XCTAssertEqual(status,409);file.store.geometryBusy=false
      status=try await h.edit(service,file,"clipboard.copy",["target":ClipboardPlaneAPI.json(target)],revision:"stale");XCTAssertEqual(status,409);XCTAssertTrue(file.store.document==d);XCTAssertTrue(file.store.session.undoStack.isEmpty)
      XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,60)
    }
  }
  @MainActor func testHiddenQuickMaskAndLockedMaskAvailabilityAndUnsupportedRecording()async throws {
    for kind in [1,2] {
      var (d,target)=try fixture(.u8,kind);d.selection = .init(x:1,y:1,width:2,height:2)
      let s=EditorStore(document:d,clipboard:MemoryClipboard());defer{s.geometryTask?.cancel();s.renderTask?.cancel()};try select(target,s)
      if kind==1{try s.setQuickMaskVisibility(false)}else{var locked=s.document;locked.layers[0].protection = [.all];s.session=EditorSession(document:locked)}
      XCTAssertTrue(s.canCopy());XCTAssertFalse(s.canCopy(cut:true));XCTAssertFalse(s.canPaste(.centered))
    }
    let (d,target)=try fixture();let s=EditorStore(document:d,clipboard:MemoryClipboard());defer{s.geometryTask?.cancel();s.renderTask?.cancel()};try select(target,s);try s.session.startActionRecording(name:"Targeted clipboard")
    s.copyImage();await s.geometryTask?.value;XCTAssertFalse(s.session.actionRecording?.snapshot.steps.isEmpty ?? true)
    let step=try XCTUnwrap(s.session.actionRecording?.snapshot.steps.first);if case .unsupported=step.operation{}else{XCTFail("Unsupported clipboard recording was disguised")}
  }
  @MainActor func testStateSchemaFactoryShortcutsAndNewFromGrayscaleClipboard()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,file in
      let (d,target)=try fixture(.u16);file.store.session=EditorSession(document:d);try select(target,file.store);try service.share(file)
      let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:ClipboardPlaneAPI.state(file.store)));XCTAssertNoThrow(try BrushAPI.merge(state,schema:ClipboardPlaneAPI.stateSchema))
      let content=try ClipboardPlane.copy(d,target:target),payload=try content.encoded().base64EncodedString();service.setDocumentTransfersEnabled(true)
      let status=try await h.edit(service,file,"clipboard.newDocument",["payloadBase64":payload]);XCTAssertEqual(status,201)
      XCTAssertEqual((service.controller.documents.last as? CraftNSDocument)?.store.document.colorMode,.grayscale)
      XCTAssertNotNil(ClipboardAPI.capabilities["targetedPlanes"]);XCTAssertNotNil((AutomationService.capabilities["clipboard"]as?[String:Any])?["targetedPlanes"])
    }
  }
}
