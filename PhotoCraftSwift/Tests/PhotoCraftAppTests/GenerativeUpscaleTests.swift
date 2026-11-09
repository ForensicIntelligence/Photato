import AppKit
import Foundation
import PhotoCraftCore
@testable import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

private struct OwnedUpscaleModel:LearnedUpscalePredicting {
  let contract=LearnedUpscaleContract(inputSide:66,interiorSide:32)
  func prediction(_ input:[Float]) async throws -> [Float] {
    try Task.checkCancellation()
    let side=contract.inputSide,out=side*4
    var result=[Float](repeating:0,count:3*out*out)
    for c in 0..<3 {for y in 0..<out {for x in 0..<out {
      let value=input[(c*side+y/4)*side+x/4]
      result[(c*out+y)*out+x] = c == 0 ? value+0.05:c == 1 ? value*0.9:value*0.8
    }}}
    return result
  }
}
private struct InvalidUpscaleModel:LearnedUpscalePredicting {
  let contract=LearnedUpscaleContract(inputSide:66,interiorSide:32)
  let nonfinite:Bool
  func prediction(_ input:[Float]) async throws -> [Float] {
    nonfinite ? [Float](repeating:.nan,count:3*264*264):[]
  }
}
private final class UpscaleGate:@unchecked Sendable {
  let condition=NSCondition();var open=false
  func wait(){condition.lock();while !open {condition.wait()};condition.unlock()}
  func release(){condition.lock();open=true;condition.broadcast();condition.unlock()}
}

final class GenerativeUpscaleTests:XCTestCase {
  func source(_ depth:PixelDepth = .u8,width:Int=4,height:Int=3)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth,name:"Owned upscale")
    var p=try Surface(width:width,height:height,depth:depth)
    for y in 0..<height {for x in 0..<width {p.setPixel(x:x,y:y,Pixel(Float(x%7)/10,Float(y%5)/10,0.25,Float((x+y)%3)/2))}}
    d.layers=[Layer(name:"Original",content:.raster(p))];d.activeLayerID=d.layers[0].id
    d.resolution=240;return d
  }
  func testPortableHalfBridgeAllFiniteCodesAndSDRRoundingBoundaries() throws {
    var finite=0,rounding=0
    for raw in 0...65535 where raw & 0x7c00 != 0x7c00 {
      let word=UInt16(raw),value=OpenEXR.halfValue(word)
      XCTAssertEqual(try OpenEXR.halfBits(value),word);finite+=1
    }
    for raw in 0..<0x3c00 {
      let lo=OpenEXR.halfValue(UInt16(raw)),hi=OpenEXR.halfValue(UInt16(raw+1))
      let midpoint=Float((Double(lo)+Double(hi))/2)
      XCTAssertEqual(try OpenEXR.halfBits(midpoint),UInt16(raw+(raw&1)))
      XCTAssertEqual(try OpenEXR.halfBits(midpoint.nextDown),UInt16(raw))
      XCTAssertEqual(try OpenEXR.halfBits(midpoint.nextUp),UInt16(raw+1))
      #if arch(arm64)
      for value in [midpoint.nextDown,midpoint,midpoint.nextUp] {
        XCTAssertEqual(try OpenEXR.halfBits(value),Swift.Float16(value).bitPattern)
      }
      #endif
      rounding+=3
    }
    XCTAssertEqual(finite,63488);XCTAssertEqual(rounding,46080)
  }
  func testOutputGeometryUsesDocumentLimitsWithoutAllocatingDenseCanvases() throws {
    let maximum=try LearnedUpscale.outputSize(width:75_000,height:75_000,scale:4)
    XCTAssertEqual(maximum.width,300_000);XCTAssertEqual(maximum.height,300_000)
    for (w,h,s) in [(0,1,2),(1,-1,4),(1,1,3),(75_001,1,4),(Int.max,Int.max,4)] {
      XCTAssertThrowsError(try LearnedUpscale.outputSize(width:w,height:h,scale:s))
    }
    XCTAssertThrowsError(try LearnedUpscaleContract(inputSide:66,interiorSide:31).validate())
    XCTAssertNoThrow(try LearnedUpscaleContract.realESRGAN.validate())
  }
  func testTiledEdgesTwoAndFourAndIndependentAlphaAtEveryRGBDepth() async throws {
    for depth in PixelDepth.allCases {for scale in [2,4] {
      let doc=try source(depth,width:65,height:35),original=doc
      guard case .raster(let pixels)=doc.layers[0].content else {return XCTFail("Missing owned pixels")}
      let output=try await LearnedUpscale.render(pixels,scale:scale,depth:depth,model:OwnedUpscaleModel())
      XCTAssertEqual(output.width,65*scale);XCTAssertEqual(output.height,35*scale)
      for (x,y) in [(0,0),(31*scale,2),(32*scale,3),(64*scale,34*scale),(output.width-1,output.height-1)] {
        let input=pixels.pixel(x:x/scale,y:y/scale)
        var expected=try Surface(width:1,height:1,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
        let a=independentAlpha(pixels,x:x,y:y,scale:scale)
        let p=Pixel(min(1,input.r+0.05),input.g*0.9,input.b*0.8,a)
        if depth == .f32 {expected.setLinearPixel(x:0,y:0,SRGBTransfer.linear(p));XCTAssertEqual(output.linearPixel(x:x,y:y),expected.linearPixel(x:0,y:0))}
        else {expected.setPixel(x:0,y:0,p);XCTAssertEqual(output.pixel(x:x,y:y),expected.pixel(x:0,y:0))}
      }
      XCTAssertEqual(doc,original)
      if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],depth == .u8,scale == 4 {
        var bytes=Data()
        for y in 0..<output.height {for x in 0..<output.width {
          let p=output.pixel(x:x,y:y);bytes.append(contentsOf:[p.r,p.g,p.b,p.a].map{UInt8(($0*255).rounded())})
        }}
        try bytes.write(to:URL(fileURLWithPath:path).appendingPathComponent("owned-upscale-rgba8.bin"))
      }
    }}
  }
  private func independentAlpha(_ p:Surface,x:Int,y:Int,scale:Int)->Float {
    let a=min(Double(p.width-1),max(0,(Double(x)+0.5)/Double(scale)-0.5))
    let b=min(Double(p.height-1),max(0,(Double(y)+0.5)/Double(scale)-0.5))
    let i=Int(a),j=Int(b),u=Float(a-Double(i)),v=Float(b-Double(j))
    return (p.pixel(x:i,y:j).a*(1-u)+p.pixel(x:min(p.width-1,i+1),y:j).a*u)*(1-v)
      + (p.pixel(x:i,y:min(p.height-1,j+1)).a*(1-u)+p.pixel(x:min(p.width-1,i+1),y:min(p.height-1,j+1)).a*u)*v
  }
  func testWrongShapeAndNonfiniteModelOutputRejectWithoutChangingInput() async throws {
    let d=try source(),original=d
    guard case .raster(let p)=d.layers[0].content else {return XCTFail("No pixels")}
    for bad in [false,true] {
      do {_ = try await LearnedUpscale.render(p,scale:2,depth:.u8,model:InvalidUpscaleModel(nonfinite:bad));XCTFail("Invalid provider output accepted")}
      catch {XCTAssertFalse(error is CancellationError)}
    }
    XCTAssertEqual(d,original)
  }
  func testCancellationAndHDRRejectBeforeReturningOutput() async throws {
    let pixels=try Surface(width:1,height:1,depth:.f32,fill:Pixel(2,0,0))
    do {_ = try await LearnedUpscale.render(pixels,scale:4,depth:.f32,model:OwnedUpscaleModel());XCTFail("HDR silently clipped")}
    catch {XCTAssertTrue(error.localizedDescription.contains("SDR"))}
    let worker=Task.detached {
      withUnsafeCurrentTask{$0?.cancel()}
      return try await LearnedUpscale.render(Surface(width:1,height:1),scale:2,depth:.u8,model:OwnedUpscaleModel())
    }
    do {_ = try await worker.value;XCTFail("Cancellation ignored")}catch{XCTAssertTrue(error is CancellationError)}
  }
  func testDerivedDocumentAllDepthsKeepsSourceAndReopensOffline() async throws {
    for depth in PixelDepth.allCases {
      let doc=try source(depth),original=doc
      let result=try await LearnedUpscaleDocument.prepare(doc,scale:2,model:OwnedUpscaleModel())
      XCTAssertNotEqual(result.id,doc.id);XCTAssertEqual(result.name,"Owned upscale - 2x")
      XCTAssertEqual(result.width,8);XCTAssertEqual(result.height,6);XCTAssertEqual(result.depth,depth)
      XCTAssertEqual(result.pixelsPerInch,240);XCTAssertEqual(result.workingICC,doc.workingICC)
      XCTAssertEqual(result.layers.count,1);XCTAssertTrue(EditorSession(document:result).undoStack.isEmpty)
      XCTAssertNotNil(result.layers[0].sourceTags?["PtSR"])
      let reopened=try DocumentIO.decode(DocumentIO.encode(result,format:.native),native:true,name:"Offline")
      XCTAssertEqual(reopened.layers,result.layers);XCTAssertEqual(doc,original)
    }
  }
  @MainActor func testNativeCreatesIndependentUnsavedOutputWithNoSourceUndo() async throws {
    let controller=CraftDocumentController(),doc=CraftNSDocument(model:try source())
    controller.addDocument(doc);defer{for d in controller.documents {d.close()}}
    doc.store.upscaleUnavailableReason={nil}
    doc.store.upscalePreparation={d,s,p in try await LearnedUpscaleDocument.prepare(d,scale:s,model:OwnedUpscaleModel(),progress:p)}
    let original=doc.store.document
    doc.store.beginUpscale();let draft=try XCTUnwrap(doc.store.upscaleDraft)
    XCTAssertEqual(draft.scale,2);XCTAssertTrue(doc.store.hasToneDraft)
    doc.store.commitUpscale(draft);await doc.store.geometryTask?.value
    XCTAssertNil(draft.error);XCTAssertNil(doc.store.upscaleDraft);XCTAssertNil(doc.store.upscaleOperationID);XCTAssertFalse(doc.store.geometryBusy)
    let created=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0 !== doc})
    XCTAssertNil(created.fileURL);XCTAssertNil(created.importedSourceURL);XCTAssertTrue(created.isDocumentEdited)
    XCTAssertTrue(created.store.session.undoStack.isEmpty);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    XCTAssertEqual(doc.store.document,original);XCTAssertEqual(created.store.document.width,8)
  }
  @MainActor func testNativeUnsupportedStaleAndCancelledDraftCannotPublish() async throws {
    let controller=CraftDocumentController(),doc=CraftNSDocument(model:try source())
    controller.addDocument(doc);defer{for d in controller.documents {d.close()}}
    doc.store.upscaleUnavailableReason={"Missing optional model"}
    doc.store.beginUpscale();let denied=try XCTUnwrap(doc.store.upscaleDraft)
    doc.store.commitUpscale(denied);XCTAssertNil(doc.store.geometryTask)
    doc.store.cancelUpscale();doc.store.upscaleUnavailableReason={nil}
    doc.store.beginUpscale();let stale=try XCTUnwrap(doc.store.upscaleDraft)
    var changed=doc.store.document;changed.name="Changed";doc.store.session=EditorSession(document:changed)
    doc.store.commitUpscale(stale);XCTAssertNotNil(stale.error);doc.store.cancelUpscale()
    let gate=UpscaleGate();defer{gate.release()}
    doc.store.upscalePreparation={d,s,p in gate.wait();return try await LearnedUpscaleDocument.prepare(d,scale:s,model:OwnedUpscaleModel(),progress:p)}
    doc.store.beginUpscale();let draft=try XCTUnwrap(doc.store.upscaleDraft)
    doc.store.commitUpscale(draft);let task=doc.store.geometryTask
    doc.store.cancelUpscale();gate.release();await task?.value
    XCTAssertEqual(controller.documents.count,1);XCTAssertFalse(doc.store.geometryBusy);XCTAssertNil(doc.store.upscaleOperationID)
  }
  @MainActor func testRealHTTPNewSharedOutputUsesSamePreparationAndKeepsSource() async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      try service.share(doc);let controller=try XCTUnwrap(doc.ownerController)
      defer{for d in controller.documents where d !== doc {d.close()}}
      doc.store.upscaleUnavailableReason={nil}
      doc.store.upscalePreparation={d,s,p in try await LearnedUpscaleDocument.prepare(d,scale:s,model:OwnedUpscaleModel(),progress:p)}
      let original=doc.store.document
      let denied=try await h.edit(service,doc,UpscaleAPI.name);XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let invalid=try await h.edit(service,doc,UpscaleAPI.name,["scale":3]);XCTAssertEqual(invalid,400)
      let stale=try await h.edit(service,doc,UpscaleAPI.name,revision:"stale");XCTAssertEqual(stale,409)
      let code=try await h.edit(service,doc,UpscaleAPI.name,["scale":4]);XCTAssertEqual(code,201)
      let created=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0 !== doc})
      XCTAssertEqual(created.store.document.width,16);XCTAssertEqual(created.store.document.height,12)
      XCTAssertEqual(service.shares.count,2);XCTAssertEqual(doc.store.document,original)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty);XCTAssertNil(created.fileURL);XCTAssertTrue(created.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPRevocationAndExactCancellationCannotPublishLateOutput() async throws {
    for revoke in [false,true] {
      let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
        try service.share(doc);service.setDocumentTransfersEnabled(true);doc.store.upscaleUnavailableReason={nil}
        let original=doc.store.document,gate=UpscaleGate();defer{gate.release()}
        doc.store.upscalePreparation={d,s,p in gate.wait();return try await LearnedUpscaleDocument.prepare(d,scale:s,model:OwnedUpscaleModel(),progress:p)}
        let task=Task{try await h.edit(service,doc,UpscaleAPI.name)}
        let deadline=Date().addingTimeInterval(10)
        while doc.store.upscaleOperationID == nil && Date()<deadline {await Task.yield()}
        let operation=try XCTUnwrap(doc.store.upscaleOperationID)
        if revoke {service.setDocumentTransfersEnabled(false)} else {
          let wrong=try await h.edit(service,doc,UpscaleAPI.cancel,["operationID":UUID().uuidString]);XCTAssertEqual(wrong,409)
          let cancel=try await h.edit(service,doc,UpscaleAPI.cancel,["operationID":operation.uuidString]);XCTAssertEqual(cancel,200)
        }
        gate.release();let code=try await task.value;XCTAssertEqual(code,409)
        XCTAssertEqual(doc.store.document,original);XCTAssertEqual(doc.ownerController?.documents.count,1)
        XCTAssertFalse(doc.store.geometryBusy);XCTAssertNil(doc.store.upscaleOperationID)
      }
    }
  }
  @MainActor func testSchemaFactoryShortcutAndNativeControlLayout() throws {
    XCTAssertEqual(AutomationCommand.definitions.count,269)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:UpscaleAPI.capabilities))
    let store=EditorStore(document:try source(),actions:ActionLibrary());defer{store.renderTask?.cancel()}
    let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:UpscaleAPI.state(store)))
    XCTAssertNoThrow(try BrushAPI.merge(state,schema:UpscaleAPI.stateSchema))
    let image=try XCTUnwrap(PhotoshopMenuCatalog.menus.first{$0.title=="Image"})
    let menu=try XCTUnwrap(image.children?.first{$0.title=="Generative Upscale…"})
    XCTAssertEqual(menu.key,"u");XCTAssertEqual(menu.modifiers,[.option,.shift,.command])
    let draft=UpscaleDraft(store:store)
    let host=NSHostingView(rootView:GenerativeUpscaleSheet(store:store,draft:draft))
    host.frame = .init(x:0,y:0,width:540,height:400);host.layoutSubtreeIfNeeded();XCTAssertGreaterThanOrEqual(host.fittingSize.width,500)
  }
  func testRealCoreMLProviderContractAndLearnedOutput() async throws {
    #if arch(arm64)
    let path=try XCTUnwrap(ProcessInfo.processInfo.environment["PHOTATO_UPSCALE_TEST_MODEL"],"Explicit acquired-model path is required for this focused inference test")
    let model=try CoreMLUpscaleModel(url:URL(fileURLWithPath:path),cpuOnly:true)
    var source=try Surface(width:4,height:3,depth:.u8)
    for y in 0..<3 {for x in 0..<4 {source.setPixel(x:x,y:y,Pixel(Float(x)/4,Float(y)/3,0.25,0.5))}}
    let rendered=try await LearnedUpscale.render(source,scale:4,depth:.u8,model:model)
    XCTAssertEqual(rendered.width,16);XCTAssertEqual(rendered.height,12)
    var different=0,bytes=Data()
    for y in 0..<12 {for x in 0..<16 {
      let p=rendered.pixel(x:x,y:y),original=source.pixel(x:x/4,y:y/4)
      XCTAssertTrue(p.isFinite);XCTAssertEqual(p.a,128.0/255.0)
      if p.r != original.r || p.g != original.g || p.b != original.b {different+=1}
      bytes.append(contentsOf:[p.r,p.g,p.b,p.a].map{UInt8(($0*255).rounded())})
    }}
    XCTAssertGreaterThan(different,100,"Actual learned output must differ from nearest-neighbour resizing")
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try bytes.write(to:URL(fileURLWithPath:path).appendingPathComponent("real-coreml-upscale-rgba8.bin"))
    }
    #else
    XCTAssertNotNil(LocalUpscaleProvider.unavailableReason)
    #endif
  }
}
