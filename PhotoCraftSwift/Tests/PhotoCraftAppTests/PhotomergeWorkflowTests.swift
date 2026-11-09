import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PhotomergeWorkflowTests: XCTestCase {
  func sources(_ depth: PixelDepth = .u8) throws -> [CraftDocument] {
    let texture = try PhotoAlignWorkflowTests().texture()
    return try (0..<2).map { k in
      var d = try CraftDocument(width:180,height:176,depth:depth);d.name = "Photo \(k+1)"
      var s = try Surface(width:180,height:176,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<176 { for x in 0..<180 {
        let v = texture[(y+k*16)*256+x+k*76],p = Pixel(v,v,v,1)
        if depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) }
      } };d.layers = [Layer(name:d.name,content:.raster(s))];d.activeLayerID = d.layers[0].id;return d
    }
  }
  func settings(blend: Bool = false,fill: Bool = false) -> PhotomergeSettings { var s = PhotomergeSettings();s.projection = .reposition;s.blendImages = blend;s.fillTransparentAreas = fill;return s }
  func testExpandedPanoramaGeometryAllDepthsPersistenceAndHistory() throws {
    for depth in PixelDepth.allCases {
      let input = try sources(depth),before = input,aligned = try Photomerge.prepare(input,settings:settings(),name:"Panorama"),result = aligned.document
      XCTAssertTrue(input == before);XCTAssertTrue((256...257).contains(result.width));XCTAssertTrue((192...193).contains(result.height));XCTAssertLessThan(aligned.rmsPixels,0.25);XCTAssertEqual(result.depth,depth);XCTAssertEqual(result.name,"Panorama")
      XCTAssertEqual(result.layers.count,2);XCTAssertEqual(result.layers[0].x,0);XCTAssertTrue((75...76).contains(result.layers[1].x));XCTAssertTrue((15...16).contains(result.layers[1].y))
      let composite = try Renderer.composite(result),sourceImage = try Renderer.composite(input[1])
      var error: Float = 0;var samples = 0
      // Independently known crop offset is(76,16). Compare scene samples in the
      // second photo's exclusive region; allow genuine subpixel registration.
      for y in stride(from:40,to:170,by:7) { for x in stride(from:190,to:250,by:7) {
        let a = depth == .f32 ? composite.linearPixel(x:x,y:y):composite.pixel(x:x,y:y)
        let b = depth == .f32 ? sourceImage.linearPixel(x:x-76,y:y-16):sourceImage.pixel(x:x-76,y:y-16)
        XCTAssertEqual(a.a,1);error += abs(a.r-b.r);samples += 1
      } };XCTAssertLessThan(error/Float(samples),0.02)
      XCTAssertNil(result.selection);XCTAssertTrue(result.layers.allSatisfy(\.visible));XCTAssertGreaterThan(result.width,input[0].width)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result)) == result)
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(result));XCTAssertEqual(try Renderer.composite(reopened),try Renderer.composite(result))
      var session = EditorSession(document:result);try session.execute(.renameLayer(result.layers[0].id,"Edited"));try session.undo();XCTAssertTrue(session.document == result);try session.redo();XCTAssertEqual(session.document.layers[0].name,"Edited")
    }
  }
  func testBlendedPanoramaAndTransparentFillWithOrWithoutBlending() throws {
    let input = try sources()
    for (blend,fill) in [(true,false),(true,true),(false,true)] {
      let result = try Photomerge.prepare(input,settings:settings(blend:blend,fill:fill)).document,composite = try Renderer.composite(result)
      XCTAssertEqual(result.layers.count,fill ? 3:2);XCTAssertEqual(composite.pixel(x:230,y:3).a,fill ? 1:0)
      XCTAssertEqual(composite.pixel(x:20,y:50).a,1);XCTAssertEqual(composite.pixel(x:220,y:90).a,1)
      if blend {
        // This alignment has partially covered border pixels. Fill retains
        // source isolation there; noFill keeps the corrected sources visible.
        XCTAssertNotNil(result.layers[0].mask);XCTAssertEqual(result.layers[0].visible,!fill)
        XCTAssertEqual(result.layers.prefix(2).map(\.name),input.map(\.name))
      }
      else { XCTAssertTrue(result.layers[0].visible);XCTAssertNil(result.layers[0].mask);guard case .raster(let overlay) = result.layers[2].content else { return XCTFail() };XCTAssertEqual(overlay.pixel(x:20,y:50).a,0) }
    }
  }
  func testMixedProfilesAndDepthsConvertBeforeAlignment() throws {
    var input = try sources(.u16);input[0].depth = .u8
    guard case .raster(let first) = input[0].layers[0].content,case .raster(var second) = input[1].layers[0].content else { return XCTFail() }
    input[0].layers[0].content = .raster(try first.converted(to:.u8))
    input[1].workingICC = CGColorSpace(name:CGColorSpace.displayP3)!.copyICCData() as Data?
    for y in 0..<second.height { for x in 0..<second.width { let v = second.pixel(x:x,y:y).r;second.setPixel(x:x,y:y,Pixel(v,0.35*v,0.15*v)) } };input[1].layers[0].content = .raster(second)
    let converted = try ColorManagement.converted(second,from:input[1],to:input[0]),result = try Photomerge.prepare(input,settings:settings()).document
    XCTAssertEqual(result.depth,.u8);XCTAssertEqual(result.workingICC,input[0].workingICC)
    guard case .raster(let out) = result.layers[1].content else { return XCTFail() }
    XCTAssertEqual(out.pixel(x:140,y:90).r,converted.pixel(x:140,y:90).r,accuracy:0.01)
    XCTAssertNotEqual(converted.pixel(x:140,y:90),second.pixel(x:140,y:90))
  }
  func testInvalidInputsAndCancellationDoNotPublishPartialResults() async throws {
    let input = try sources();XCTAssertThrowsError(try Photomerge.prepare([input[0]],settings:settings()))
    var invalid = settings();invalid.focalLengthPixels = .nan;XCTAssertThrowsError(try Photomerge.prepare(input,settings:invalid))
    var blank = input;blank[1].layers[0].content = .raster(try Surface(width:180,height:176,fill:.white));XCTAssertThrowsError(try Photomerge.prepare(blank,settings:settings()))
    let options = settings(),task = Task { try Task.checkCancellation();return try Photomerge.prepare(input,settings:options) };task.cancel()
    do { _ = try await task.value;XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("\(error)") }
  }
  @MainActor func cleanup(_ controller: CraftDocumentController,except original: CraftNSDocument) {
    controller.cancelPhotomerge()
    for case let doc as CraftNSDocument in controller.documents where doc !== original { doc.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close();controller.removeDocument(doc) }
  }
  @MainActor func testNativeOpenSourcesPreviewCancelCommitAndStaleGuard() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,original in
      let input = try sources(),controller = service.controller;original.store.session = EditorSession(document:input[0]);let second = CraftNSDocument(model:input[1]);controller.addDocument(second)
      defer { cleanup(controller,except:original) }
      controller.beginPhotomerge(display:false);let model = try XCTUnwrap(controller.photomergeWorkspace);model.addOpenDocuments();XCTAssertEqual(model.sources.count,2);model.settings = settings();model.refresh();await model.task?.value
      XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertTrue(original.store.document == input[0]);XCTAssertEqual(controller.documents.count,2)
      let view = NSHostingView(rootView:PhotomergeView(model:model));view.frame = NSRect(x:0,y:0,width:780,height:590);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,0)
      try second.store.session.execute(.renameLayer(second.store.document.layers[0].id,"Changed"));second.store.revision += 1;XCTAssertThrowsError(try model.commit(display:false));XCTAssertEqual(controller.documents.count,2)
      model.refresh();await model.task?.value;let expected = try XCTUnwrap(model.result).document,created = try model.commit(display:false)
      XCTAssertTrue(created.store.document == expected);XCTAssertTrue(created.isDocumentEdited);XCTAssertNil(created.fileURL);XCTAssertNil(controller.photomergeWorkspace)
      controller.beginPhotomerge(display:false);controller.photomergeWorkspace?.addOpenDocuments();controller.cancelPhotomerge();XCTAssertEqual(controller.documents.count,3)
    }
  }
  @MainActor func testNativeFolderImportDuplicatesAndFailedBatchAreAtomic() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,original in
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotomergeSources-\(UUID())",isDirectory:true);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
      defer { try? FileManager.default.removeItem(at:dir);service.controller.cancelPhotomerge() }
      for (i,source) in try sources().enumerated() { try DocumentIO.encode(source,format:.png).write(to:dir.appendingPathComponent("\(i).png")) }
      try Data("ignore".utf8).write(to:dir.appendingPathComponent("notes.txt"))
      service.controller.beginPhotomerge(display:false);let model = try XCTUnwrap(service.controller.photomergeWorkspace)
      model.load([dir],folder:true);await model.loadingTask?.value;XCTAssertNil(model.error);XCTAssertEqual(model.sources.count,2)
      model.load([dir],folder:true);await model.loadingTask?.value;XCTAssertNotNil(model.error);XCTAssertEqual(model.sources.count,2)
      let bad = dir.appendingPathComponent("bad.png"),valid = dir.appendingPathComponent("third.png");try Data("broken".utf8).write(to:bad);try DocumentIO.encode(sources()[0],format:.png).write(to:valid)
      model.load([valid,bad]);await model.loadingTask?.value;XCTAssertNotNil(model.error);XCTAssertEqual(model.sources.count,2)
      model.settings = settings();model.refresh();await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready");model.selected = [model.sources[0].id];model.removeSelected();XCTAssertFalse(model.ready);XCTAssertEqual(model.sources.count,1)
      XCTAssertEqual(service.controller.documents.count,1);XCTAssertTrue(service.controller.documents.first === original)
    }
  }
  @MainActor func setup(_ service: AutomationService,_ original: CraftNSDocument) throws -> (CraftNSDocument,[String:Any]) {
    let input = try sources();original.store.session = EditorSession(document:input[0]);let second = CraftNSDocument(model:input[1]);service.controller.addDocument(second);try service.share(original);try service.share(second)
    let sources: [[String:Any]] = service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]}
    return (second,["sources":sources,"settings":["projection":"reposition","blendImages":false],"name":"API Panorama"])
  }
  @MainActor func testHTTPNewDocumentEquivalenceSchemasAndIndependentSourceHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,original in
      let (second,params) = try setup(service,original);defer { cleanup(service.controller,except:original) };service.setDocumentTransfersEnabled(true)
      let before = [original.store.document,second.store.document],expected = try Photomerge.prepare(before,settings:settings(),name:"API Panorama").document
      let response = try await helper.request(service,path:"/v1/documents/\(service.shares[0].id)/commands",body:["command":"document.photomerge","revision":service.revision(original.store),"parameters":params])
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self));let json = try JSONSerialization.jsonObject(with:response.1) as! [String:Any];XCTAssertNotNil(json["photomergeResult"])
      let created = try XCTUnwrap(service.shares.last?.document);XCTAssertFalse(created === second);XCTAssertEqual(try Renderer.composite(created.store.document),try Renderer.composite(expected));XCTAssertTrue(created.isDocumentEdited)
      XCTAssertTrue(original.store.document == before[0]);XCTAssertTrue(second.store.document == before[1]);XCTAssertTrue(original.store.session.undoStack.isEmpty);XCTAssertTrue(second.store.session.undoStack.isEmpty)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(created.store.document)) == created.store.document)
      let definition = try XCTUnwrap(AutomationCommand.definitions.first{$0.name == "document.photomerge"});let fields = ((definition.schema["properties"] as! [String:Any])["parameters"] as! [String:Any])["properties"] as! [String:Any];XCTAssertNotNil(fields["sources"]);XCTAssertNotNil(fields["settings"])
    }
  }
  @MainActor func testAPIPermissionsInvalidBusyAndStaleInputs() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,original in
      let (second,params) = try setup(service,original);defer { cleanup(service.controller,except:original) }
      let disabled = try await helper.edit(service,original,"document.photomerge",params);XCTAssertEqual(disabled,403);service.setDocumentTransfersEnabled(true)
      var bad = params;bad["settings"] = ["blendImages":1];let invalid = try await helper.edit(service,original,"document.photomerge",bad);XCTAssertEqual(invalid,400)
      var duplicate = params;duplicate["sources"] = [params["sources"] as! [[String:Any]]][0].prefix(1).flatMap{[$0,$0]};let dup = try await helper.edit(service,original,"document.photomerge",duplicate);XCTAssertEqual(dup,400)
      try second.store.session.execute(.renameLayer(second.store.document.layers[0].id,"Changed"));second.store.revision += 1;let stale = try await helper.edit(service,original,"document.photomerge",params);XCTAssertEqual(stale,409)
      service.controller.beginPhotomerge(display:false);let busy = try await helper.edit(service,original,"document.photomerge",params);XCTAssertEqual(busy,409);service.controller.cancelPhotomerge()
      XCTAssertEqual(service.controller.documents.count,2);XCTAssertNil(service.photomergeOperationID)
    }
  }
  @MainActor func testAPICancellationAndRevocationPublishNothing() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,original in
      let (_,params) = try setup(service,original);defer { cleanup(service.controller,except:original) };service.setDocumentTransfersEnabled(true)
      for revoke in [false,true] {
        var current = params;current["sources"] = service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]}
        let command = try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"document.photomerge","revision":service.revision(original.store),"parameters":current])),id = service.shares[0].id
        let gate = DocumentPersistenceTests.Gate()
        service.photomergePreparation = { sources, settings, name in
          gate.wait()
          try Task.checkCancellation()
          return try Photomerge.prepare(sources, settings: settings, name: name)
        }
        let task = Task { try await service.executePhotomerge(command,anchorID:id) }
        defer { gate.release(); task.cancel() }
        try await DocumentPersistenceTests().waitFor(gate)
        XCTAssertNotNil(service.photomergeOperationID)
        if revoke { service.setDocumentTransfersEnabled(false) }
        else {
          let operation = try XCTUnwrap(service.photomergeOperationID),status = try await helper.edit(service,original,"document.photomerge.cancel",["operationID":operation.uuidString]);XCTAssertEqual(status,200)
        }
        gate.release()
        do { _ = try await task.value;XCTFail("Cancelled operation published a panorama") } catch is CancellationError {} catch { XCTAssertTrue(error is AutomationFailure) }
        XCTAssertEqual(service.controller.documents.count,2);XCTAssertNil(service.photomergeOperationID);XCTAssertFalse(original.store.geometryBusy);XCTAssertFalse(service.documentTransferBusy)
      }
    }
  }
}
