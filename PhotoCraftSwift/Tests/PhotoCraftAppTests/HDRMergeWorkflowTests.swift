import AppKit
import ImageIO
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class HDRMergeWorkflowTests: XCTestCase {
  func fixture(_ name: String) throws -> Data { try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/HDRMerge/\(name)")) }
  func images() throws -> [[HDRMergeMath.Sample]] {
    let data = try fixture("brackets.rgba8")
    return (0..<4).map { j in (0..<96*32).map { i in let k = (j*96*32+i)*4;return .init(Float(data[k])/255,Float(data[k+1])/255,Float(data[k+2])/255,1) } }
  }
  func sources() throws -> [CraftDocument] {
    try images().enumerated().map { j,pixels in
      var d = try CraftDocument(width:96,height:32,name:"Exposure \(j+1)"),s = try Surface(width:96,height:32)
      for y in 0..<32 { for x in 0..<96 { let q = pixels[y*96+x];s.setPixel(x:x,y:y,Pixel(q.x,q.y,q.z)) } }
      d.layers = [Layer(name:d.name,content:.raster(s))];d.activeLayerID = d.layers[0].id;return d
    }
  }
  func settings(_ depth: PixelDepth = .f32) -> HDRMergeSettings { var s = HDRMergeSettings();s.exposureSource = .manual;s.exposureEV = [-2,0,2,4];s.align = false;s.depth = depth;return s }
  func testOriginalRustRadianceAndResponseOracle() throws {
    let result = try HDRMergeMath.merge(width:96,height:32,images:images(),exposures:[0.25,1,4,16],removeGhosts:false,ghostBase:nil)
    let data = try fixture("radiance.f32le"),curve = try fixture("response.f64le")
    let expected: [Float] = data.withUnsafeBytes { raw in stride(from:0,to:raw.count,by:4).map { Float(bitPattern:raw.loadUnaligned(fromByteOffset:$0,as:UInt32.self).littleEndian) } }
    let expectedCurve: [Double] = curve.withUnsafeBytes { raw in stride(from:0,to:raw.count,by:8).map { Double(bitPattern:raw.loadUnaligned(fromByteOffset:$0,as:UInt64.self).littleEndian) } }
    var maxRelative: Float = 0,maxCurve = 0.0
    for i in result.pixels.indices { for c in 0..<4 { maxRelative = max(maxRelative,abs(result.pixels[i][c]-expected[i*4+c])/max(1e-5,abs(expected[i*4+c]))) } }
    for c in 0..<3 { for i in 0..<256 { maxCurve = max(maxCurve,abs(result.response[c][i]-expectedCurve[c*256+i])) } }
    XCTAssertLessThan(maxRelative,0.0001);XCTAssertLessThan(maxCurve,0.00001);XCTAssertEqual(result.ghostBase,0);XCTAssertGreaterThan(result.stops,9)
    XCTAssertTrue(result.response.allSatisfy { g in zip(g,g.dropFirst()).allSatisfy{$0 < $1} })
    XCTAssertGreaterThan(result.pixels.map(\.x).max()!,1)
  }
  func testExposureEstimationAndExposureInvariantAlignment() throws {
    let factors = try HDRMergeMath.estimate(images());for i in 1..<4 { XCTAssertTrue((2...8).contains(factors[i]/factors[i-1])) }
    let w = 128,h = 96
    let gray: [Float] = (0..<w*h).map { i in 0.5+0.4*sin(Float(i%w)*0.21)*cos(Float(i/w)*0.17) }
    let shifted = (0..<w*h).map { i in gray[min(h-1,max(0,i/w+3))*w+min(w-1,max(0,i%w-5))]*0.6 }
    XCTAssertEqual(try HDRMergeMath.offset(width:w,height:h,reference:shifted,image:gray,levels:4),SIMD2(5,-3))
    XCTAssertEqual(try HDRMergeMath.offset(width:32,height:32,reference:[Float](repeating:0.2,count:1024),image:[Float](repeating:0.4,count:1024)),.zero)
  }
  func testGhostRemovalUsesChosenBaseAndFourToneOperators() throws {
    let w = 64,h = 64
    var shots = [Float(0.5),1,2].map { dt in [HDRMergeMath.Sample](repeating:.init(repeating:pow(0.2*dt,0.45)),count:w*h).map{q in HDRMergeMath.Sample(q.x,q.y,q.z,1)} }
    for y in 20..<40 { for x in 20..<40 { shots[2][y*w+x] = .init(0.2,0.2,0.2,1) } }
    let plain = try HDRMergeMath.merge(width:w,height:h,images:shots,exposures:[0.5,1,2],removeGhosts:false,ghostBase:1)
    let clean = try HDRMergeMath.merge(width:w,height:h,images:shots,exposures:[0.5,1,2],removeGhosts:true,ghostBase:1)
    XCTAssertLessThan(abs(clean.pixels[30*w+30].y/clean.pixels[5*w+5].y-1),0.15)
    XCTAssertGreaterThan(abs(plain.pixels[30*w+30].y/plain.pixels[5*w+5].y-1),0.2);XCTAssertGreaterThan(clean.ghostFraction,0.05)
    let ramp = (0..<96*32).map { i -> HDRMergeMath.Sample in let b = Float(0.002)*pow(2,Float(i%96)/96*12);return .init(b,b*0.8,b*0.6,1) }
    for method in HDRMergeSettings.Method.allCases { var s = settings(.u16);s.method = method
      let pixels = try HDRMergeMath.toneMap(ramp,width:96,height:32,settings:s)
      XCTAssertTrue(pixels.allSatisfy{(0...1).contains($0.x) && (0...1).contains($0.y) && (0...1).contains($0.z) && $0.w == 1});XCTAssertGreaterThan(pixels[94].y,pixels[2].y)
    }
  }
  func testNativeDepthsPersistenceHistoryMetadataAndDisplayOnlyPreview() throws {
    var inputs = try sources();let original = inputs
    for depth in PixelDepth.allCases {
      let result = try HDRMerge.prepare(inputs,settings:settings(depth),name:"Merged"),d = result.document
      XCTAssertEqual(d.depth,depth);XCTAssertEqual(d.name,"Merged");XCTAssertEqual(result.exposureEV,[0,2,4,6]);XCTAssertTrue(inputs == original)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(d)) == d)
      XCTAssertEqual(try Renderer.composite(PSDCodec.read(PSDCodec.writeRasterLayers(d))),try Renderer.composite(d))
      var session = EditorSession(document:d);try session.execute(.renameLayer(d.layers[0].id,"Edited"));try session.undo();XCTAssertTrue(session.document == d)
      _ = try HDRMerge.preview(result,exposure:-3);XCTAssertTrue(result.document == d)
    }
    for i in inputs.indices {
      let exif: [String:Any] = [kCGImagePropertyExifExposureTime as String:pow(4,Double(i))/1000,kCGImagePropertyExifFNumber as String:2,kCGImagePropertyExifISOSpeedRatings as String:[100]]
      inputs[i].sourceMetadata = ["imageIOProperties":try PropertyListSerialization.data(fromPropertyList:[kCGImagePropertyExifDictionary as String:exif],format:.binary,options:0)]
    }
    var s = settings();s.exposureSource = .metadata
    let result = try HDRMerge.prepare(inputs,settings:s);XCTAssertEqual(result.exposureEV,[0,2,4,6]);XCTAssertEqual(result.exposureSource,.metadata)
  }
  func testPipelineAlignmentPreservesReferenceFrameAndSkipsMissingBorderSamples() throws {
    let w = 128,h = 96
    func brackets(shifted: Bool) throws -> [CraftDocument] {
      try (0..<3).map { j in
        var d = try CraftDocument(width:w,height:h,depth:.u16),surface = try Surface(width:w,height:h,depth:.u16)
        for y in 0..<h { for x in 0..<w {
          let sx = shifted && j == 0 ? min(w-1,max(0,x-5)):x,sy = shifted && j == 0 ? min(h-1,max(0,y+3)):y
          let l: Float = 0.15+0.12*sin(Float(sx)*0.21)*cos(Float(sy)*0.17),v = pow(l*pow(2,Float(j-1)),0.45)
          surface.setPixel(x:x,y:y,Pixel(v,v,v))
        } };d.layers = [Layer(name:"Bracket",content:.raster(surface))];d.activeLayerID = d.layers[0].id;return d
      }
    }
    var s = settings();s.exposureEV = [-1,0,1];s.ghostBase = 1
    let expected = try Renderer.composite(HDRMerge.prepare(brackets(shifted:false),settings:s).document)
    s.align = true;let result = try HDRMerge.prepare(brackets(shifted:true),settings:s),actual = try Renderer.composite(result.document)
    XCTAssertEqual(result.offsets[0],[-5,3]);XCTAssertEqual(result.offsets[1],[0,0]);XCTAssertEqual(result.document.width,w);XCTAssertEqual(result.document.height,h)
    var error: Float = 0;var count = 0
    for y in 10..<h-10 { for x in 10..<w-10 { let e = expected.linearPixel(x:x,y:y).r,a = actual.linearPixel(x:x,y:y);error += abs(a.r-e)/max(e,0.001);count += 1;XCTAssertEqual(a.a,1) } }
    XCTAssertLessThan(error/Float(count),0.03);XCTAssertEqual(actual.linearPixel(x:w-1,y:0).a,1)
  }
  @MainActor func testFolderSourcesPreviewAndCancelLeaveOriginalsAlone() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,original in
      let folder = try DocumentPersistenceTests().directory();defer { try? FileManager.default.removeItem(at:folder);cleanup(service.controller,except:original) }
      for (i,d) in try sources().enumerated() { try DocumentIO.encode(d,format:.png).write(to:folder.appendingPathComponent("bracket-\(i).png")) }
      service.controller.beginHDRMerge(display:false);let model = try XCTUnwrap(service.controller.hdrMergeWorkspace)
      model.load([folder],folder:true);await model.loadingTask?.value;XCTAssertEqual(model.sources.count,4);XCTAssertNil(model.error)
      model.settings = settings();for (i,source) in model.sources.enumerated() { model.manualEV[source.id] = Double(i*2-2) }
      model.refresh();await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
      service.controller.cancelHDRMerge();XCTAssertNil(service.controller.hdrMergeWorkspace);XCTAssertEqual(service.controller.documents.count,1)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).count,4)
    }
  }
  func testInvalidMetadataDimensionsTransparencySettingsAndCancellation() async throws {
    var input = try sources(),s = settings();s.exposureSource = .metadata;XCTAssertThrowsError(try HDRMerge.prepare(input,settings:s))
    s = settings();s.exposureEV = [0];XCTAssertThrowsError(try HDRMerge.prepare(input,settings:s))
    input[1] = try CraftDocument(width:20,height:30);XCTAssertThrowsError(try HDRMerge.prepare(input,settings:settings()))
    input = try sources();input[1].layers[0].content = .raster(try Surface(width:96,height:32));XCTAssertThrowsError(try HDRMerge.prepare(input,settings:settings()))
    let sources = try sources(),options = settings(),worker = Task { try Task.checkCancellation();return try HDRMerge.prepare(sources,settings:options) };worker.cancel()
    do { _ = try await worker.value;XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("\(error)") }
  }
  @MainActor func cleanup(_ controller: CraftDocumentController,except original: CraftNSDocument) {
    controller.cancelHDRMerge();controller.cancelPhotomerge()
    for case let doc as CraftNSDocument in controller.documents where doc !== original { doc.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close();controller.removeDocument(doc) }
  }
  @MainActor func setup(_ service: AutomationService,_ original: CraftNSDocument) throws -> [String:Any] {
    let input = try sources();original.store.session = EditorSession(document:input[0]);try service.share(original)
    for source in input.dropFirst() { let doc = CraftNSDocument(model:source);service.controller.addDocument(doc);try service.share(doc) }
    return ["sources":service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]},"settings":["exposureSource":"manual","exposureEV":[-2,0,2,4],"align":false],"name":"API HDR"]
  }
  @MainActor func testNativeSourcePreviewStaleGuardCommitAndWorkspaceExclusion() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,original in
      _ = try setup(service,original);defer { cleanup(service.controller,except:original) }
      let controller = service.controller;controller.beginHDRMerge(display:false);let model = try XCTUnwrap(controller.hdrMergeWorkspace);model.addOpenDocuments();model.settings = settings();for (i,source) in model.sources.enumerated() { model.manualEV[source.id] = Double(i*2-2) };model.refresh();await model.task?.value
      XCTAssertTrue(model.ready,model.error ?? "Not ready");controller.beginPhotomerge(display:false);XCTAssertNil(controller.photomergeWorkspace)
      let view = NSHostingView(rootView:HDRMergeView(model:model));view.frame = NSRect(x:0,y:0,width:1000,height:740);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,0)
      let expected = try XCTUnwrap(model.result).document;model.previewExposure = -2;model.updatePreview();await model.task?.value;XCTAssertTrue(model.result?.document == expected)
      let response = try await AutomationTests().request(service,path:"/v1/capabilities")
      let capabilities = try JSONSerialization.jsonObject(with:response.1) as! [String:Any],state = try XCTUnwrap(capabilities["hdrMergeState"] as? [String:Any])
      XCTAssertEqual(state["previewExposure"] as? Double,-2);XCTAssertEqual(state["sourceCount"] as? Int,4);let rendering = try XCTUnwrap(state["rendering"] as? Bool),ready = try XCTUnwrap(state["ready"] as? Bool)
      print("HDR preview state during HTTP:",rendering,ready)
      XCTAssertEqual(ready,!rendering)
      await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Preview did not settle")
      model.manualEV[model.sources[0].id] = -1;XCTAssertFalse(model.ready);model.manualEV[model.sources[0].id] = -2
      let source = try XCTUnwrap(model.sources[1].document);try source.store.session.execute(.renameLayer(source.store.document.layers[0].id,"Changed"));source.store.revision += 1;XCTAssertThrowsError(try model.commit(display:false))
      model.refresh();await model.task?.value;let prepared = try XCTUnwrap(model.result).document,new = try model.commit(display:false);XCTAssertTrue(new.store.document == prepared);XCTAssertTrue(new.isDocumentEdited);XCTAssertNil(new.fileURL);XCTAssertNil(controller.hdrMergeWorkspace)
    }
  }
  @MainActor func testHTTPCreationEquivalenceSchemasAndSourceHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,original in
      let params = try setup(service,original);defer { cleanup(service.controller,except:original) };service.setDocumentTransfersEnabled(true)
      let before = service.shares.map{$0.document!.store.document},expected = try HDRMerge.prepare(before,settings:settings(),name:"API HDR").document
      let response = try await helper.request(service,path:"/v1/documents/\(service.shares[0].id)/commands",body:["command":"document.hdrMerge","revision":service.revision(original.store),"parameters":params])
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self));let json = try JSONSerialization.jsonObject(with:response.1) as! [String:Any];XCTAssertNotNil(json["hdrMergeResult"])
      let created = try XCTUnwrap(service.shares.last?.document);XCTAssertEqual(try Renderer.composite(created.store.document),try Renderer.composite(expected));XCTAssertTrue(created.isDocumentEdited)
      for (i,share) in service.shares.prefix(4).enumerated() { XCTAssertTrue(share.document!.store.document == before[i]);XCTAssertTrue(share.document!.store.session.undoStack.isEmpty) }
      let definition = try XCTUnwrap(AutomationCommand.definitions.first{$0.name == "document.hdrMerge"});let fields = ((definition.schema["properties"] as! [String:Any])["parameters"] as! [String:Any])["properties"] as! [String:Any];XCTAssertNotNil(fields["settings"])
    }
  }
  @MainActor func testAPIGuardsCancellationAndRevocation() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,original in
      let params = try setup(service,original);defer { cleanup(service.controller,except:original) }
      let disabled = try await helper.edit(service,original,"document.hdrMerge",params);XCTAssertEqual(disabled,403);service.setDocumentTransfersEnabled(true)
      for (key,bounds) in HDRMergeSettings.numericBounds { for value in [bounds.0,bounds.1] {
        var edge = params;var settings = params["settings"] as! [String:Any];settings[key] = value;edge["settings"] = settings
        let data = try JSONSerialization.data(withJSONObject:["command":"document.hdrMerge","revision":service.revision(original.store),"parameters":edge])
        XCTAssertNoThrow(try AutomationCommand(data:data).hdrMergeOptions(),key)
      } }
      var bad = params;bad["settings"] = ["exposureSource":"manual","exposureEV":[0]];let invalid = try await helper.edit(service,original,"document.hdrMerge",bad);XCTAssertEqual(invalid,400)
      bad = params;var staleSources = params["sources"] as! [[String:Any]];staleSources[1]["revision"] = "stale";bad["sources"] = staleSources;let stale = try await helper.edit(service,original,"document.hdrMerge",bad);XCTAssertEqual(stale,409)
      service.controller.beginPhotomerge(display:false);let busy = try await helper.edit(service,original,"document.hdrMerge",params);XCTAssertEqual(busy,409);service.controller.cancelPhotomerge()
      // A3k-pixel optimized merge can complete before the first HTTP round trip.
      // Exercise cancellation during a substantive real merge, with no fake worker.
      for share in service.shares {
        let document = try XCTUnwrap(share.document),originalPixels = try Renderer.composite(document.store.document)
        var large = try CraftDocument(width:512,height:512),pixels = try Surface(width:512,height:512)
        for y in 0..<512 { for x in 0..<512 { pixels.setPixel(x:x,y:y,originalPixels.pixel(x:x*96/512,y:y*32/512)) } }
        large.layers = [Layer(name:"Exposure",content:.raster(pixels))];large.activeLayerID = large.layers[0].id
        document.store.renderTask?.cancel();document.store.session = EditorSession(document:large);document.store.revision += 1
      }
      for revoke in [false,true] {
        var current = params;current["sources"] = service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]}
        let command = try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"document.hdrMerge","revision":service.revision(original.store),"parameters":current])),id = service.shares[0].id
        let task = Task { try await service.executeHDRMerge(command,anchorID:id) }
        for _ in 0..<100 where service.hdrMergeOperationID == nil { try await Task.sleep(for:.milliseconds(1)) }
        XCTAssertNotNil(service.hdrMergeOperationID)
        if revoke { service.setDocumentTransfersEnabled(false) } else { let operation = try XCTUnwrap(service.hdrMergeOperationID),status = try await helper.edit(service,original,"document.hdrMerge.cancel",["operationID":operation.uuidString]);XCTAssertEqual(status,200) }
        do { _ = try await task.value;XCTFail("Cancelled merge published") } catch is CancellationError {} catch { XCTAssertTrue(error is AutomationFailure) }
        XCTAssertEqual(service.controller.documents.count,4);XCTAssertNil(service.hdrMergeOperationID);XCTAssertFalse(original.store.geometryBusy);XCTAssertFalse(service.documentTransferBusy)
      }
    }
  }
}
