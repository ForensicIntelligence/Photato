import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private struct StackFixtureTransport: AdobeResourceTransport {
  let data: Data
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data,output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("Fixture uses hosted output.") }
}
final class ImageStackWorkflowTests: XCTestCase {
  let samples: [[Pixel]] = [[Pixel(0.1,0.8,0.2,1),Pixel(0.9,0.1,0.3,0)], [Pixel(0.9,0.2,0.6,0.5),Pixel(0.2,0.4,0.8,0.3)], [Pixel(0.2,0.6,0.4,1),Pixel(0.6,0.2,0.4,1)], [Pixel(0.3,0.4,0.8,0.8),Pixel(0.8,0.2,0.2,0)], [Pixel(0.1,0.2,0.4,1),Pixel(0.4,0.8,0.6,0.5)]]
  func source(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:2,height:1,depth:depth);d.layers = []
    for (i,row) in samples.enumerated() {
      var s = try Surface(width:2,height:1,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for (x,p) in row.enumerated() { if depth == .f32 { s.setLinearPixel(x:x,y:0,p) } else { s.setPixel(x:x,y:0,p) } }
      d.layers.append(Layer(name:"Source \(i)",content:.raster(s)))
    };d.activeLayerID = d.layers.last?.id;return d
  }
  func smart(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try source(depth);try SmartObjectIO.convert(in:d,selected:Set(d.layers.map(\.id))).apply(to:&d);return d
  }
  func testUnchangedStatisticsAgainstLicensedRustAndAnalyticalValues() throws {
    let data = try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/ImageStack/original.json"))
    let oracle = try JSONDecoder().decode([String:[[Float]]].self,from:data)
    // The five corrected moments/entropy use independent documented-math fixtures.
    for mode: ImageStackMode in [.maximum,.mean,.median,.minimum,.range,.summation] {
      let key = mode == .standardDeviation ? "StandardDeviation":mode.title
      let expected = try XCTUnwrap(oracle[key])
      for x in 0..<2 { for c in 0..<3 {
        let values = samples.compactMap { row -> Float? in let p = row[x];return p.a > 0 ? [p.r,p.g,p.b][c]:nil }
        XCTAssertEqual(min(1,max(0,mode.statistic(values))),expected[x][c],accuracy:0.000002,key)
      } }
      let d = try source(.f32),pixels = try ImageStack.render(d,mode:mode,in:d)
      for x in 0..<2 { let p = pixels.linearPixel(x:x,y:0);XCTAssertEqual(p.a,expected[x][3],accuracy:0.00001)
        for c in 0..<3 { XCTAssertEqual(min(1,[p.r,p.g,p.b][c]),expected[x][c],accuracy:0.00001,key) }
      }
    }
    XCTAssertEqual(ImageStackMode.median.statistic([0.2,0.8]),0.5)
    XCTAssertEqual(ImageStackMode.mean.statistic([]),0)
  }
  func testDepthsNative23HistoryNoneAndSourceRetention() throws {
    for depth in PixelDepth.allCases {
      let original = try smart(depth),id = original.layers[0].id,source = original.layers[0].smartObject!.data
      var session = EditorSession(document:original)
      for mode in ImageStackMode.allCases {
        try session.execute(ImageStack.command(in:session.document,layerID:id,mode:mode))
        XCTAssertEqual(session.document.layers[0].smartObject?.data,source)
        XCTAssertEqual(session.document.minimumArchiveVersion,23)
        for data in [try NativeArchive.encode(session.document),try NativeArchive.encodeChunked(session.document)] { XCTAssertTrue(try NativeArchive.decode(data) == session.document) }
      }
      let stacked = session.document
      try session.execute(ImageStack.command(in:stacked,layerID:id,mode:nil));XCTAssertTrue(session.document == original)
      try session.undo();XCTAssertTrue(session.document == stacked);try session.redo();XCTAssertTrue(session.document == original)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(stacked,format:.psd))
    }
  }
  func testHDRSummationAndTransparentFrames() throws {
    var d = try source(.f32)
    for i in d.layers.indices { var s = try Surface(width:2,height:1,depth:.f32,colorEncoding:.linearRGB);s.setLinearPixel(x:0,y:0,Pixel(2,3,4));d.layers[i].content = .raster(s) }
    let p = try ImageStack.render(d,mode:.summation,in:d)
    XCTAssertEqual(p.linearPixel(x:0,y:0).r,10,accuracy:0.00001);XCTAssertEqual(p.linearPixel(x:1,y:0),.clear)
  }
  func testPerInstanceModesRecomputeOnReplacementAndPreserveGeometryFiltersMasks() throws {
    var d = try smart(),id = d.layers[0].id
    try Command.duplicateLayer(id).apply(to:&d);let other = d.layers[1].id
    try ImageStack.command(in:d,layerID:id,mode:.mean).apply(to:&d)
    try ImageStack.command(in:d,layerID:other,mode:.median).apply(to:&d)
    d.layers[0].x = 4;d.layers[0].mask = try Surface(width:2,height:1,fill:.white)
    let old = d
    var contents = try source();for i in contents.layers.indices { contents.layers[i].content = .raster(try Surface(width:2,height:1,fill:Pixel(0.2,0.4,0.6))) }
    var session = EditorSession(document:d)
    try session.execute(SmartObjectIO.replacement(in:d,layerID:id,source:contents,preserveSize:false))
    XCTAssertEqual(session.document.layers.map{$0.smartObject?.stackMode},[.mean,.median]);XCTAssertEqual(session.document.layers[0].x,4)
    XCTAssertEqual(session.document.layers[0].mask,old.layers[0].mask)
    for layer in session.document.layers { XCTAssertEqual(try Renderer.layerSurface(layer,in:session.document).pixel(x:0,y:0).r,0.2,accuracy:0.005) }
    try session.undo();XCTAssertTrue(session.document == old)
    d.layers[1].locked = true
    XCTAssertThrowsError(try PreparedEdit(command:SmartObjectIO.replacement(in:d,layerID:id,source:contents),document:d))
  }
  func testSampleMasksVisibilityGroupsAndDimensions() throws {
    var d = try source(.f32);d.layers[1].visible = false
    d.layers[0].mask = try Surface(width:2,height:1,fill:.clear)
    let p = try ImageStack.render(d,mode:.mean,in:d).linearPixel(x:0,y:0)
    XCTAssertEqual(p.r,0.2,accuracy:0.00001)
    try Command.groupLayers(d.layers.map(\.id),"Sources").apply(to:&d)
    XCTAssertEqual(try ImageStack.render(d,mode:.mean,in:d).linearPixel(x:0,y:0).r,p.r,accuracy:0.00001)
    var options = ImageStackSettings();options.createSmartObject = true;options.mode = .median
    let inputs = [try source(),try CraftDocument(width:3,height:2)]
    let output = try ImageStack.prepare(inputs,settings:options).document
    XCTAssertEqual(output.width,3);XCTAssertEqual(output.height,2)
    XCTAssertEqual(try SmartObjectIO.sourceDocument(output.layers[0].smartObject!).layers.count,2)
  }
  func testAlignmentUsesSharedRegistration() throws {
    let d = try PhotoAlignWorkflowTests().fixture(),inputs = try d.layers.map { layer -> CraftDocument in var one = d;one.layers = [layer];one.activeLayerID = layer.id;try one.validate();return one }
    var s = ImageStackSettings();s.align = true;s.createSmartObject = true;s.mode = .median
    let result = try ImageStack.prepare(inputs,settings:s)
    XCTAssertTrue(result.aligned);XCTAssertEqual(result.sourceCount,2)
    let contents = try SmartObjectIO.sourceDocument(result.document.layers[0].smartObject!)
    let a = contents.layers[0], b = contents.layers[1]
    let sa = try Renderer.layerSurface(a,in:contents),sb = try Renderer.layerSurface(b,in:contents)
    var total: Float = 0, count = 0
    for y in 30..<150 { for x in 60..<220 {
      let p = sa.pixel(x:x-a.x,y:y-a.y),q = sb.pixel(x:x-b.x,y:y-b.y)
      if p.a > 0.99 && q.a > 0.99 { total += abs(p.r-q.r);count += 1 }
    } }
    XCTAssertGreaterThan(count,1000);XCTAssertLessThan(total/Float(max(1,count)),0.025)
  }
  @MainActor func setup(_ service: AutomationService,_ original: CraftNSDocument) throws -> [String:Any] {
    let d = try source()
    for (i,layer) in d.layers.prefix(3).enumerated() {
      var one = d;one.layers = [layer];one.activeLayerID = layer.id
      let doc: CraftNSDocument
      if i == 0 { original.store.session = EditorSession(document:one);doc = original } else { doc = CraftNSDocument(model:one);service.controller.addDocument(doc) }
      try service.share(doc)
    }
    return ["sources":service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]},"settings":["createSmartObject":true,"mode":"median"],"name":"API Stack"]
  }
  @MainActor func cleanup(_ service: AutomationService,_ original: CraftNSDocument) { service.controller.cancelImageStack();HDRMergeWorkflowTests().cleanup(service.controller,except:original) }
  @MainActor func testNativeWorkspacePreviewCancelCommitAndSourceStaleness() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,original in
      _ = try setup(service,original);defer { cleanup(service,original) }
      service.controller.beginImageStack(statistics:true,display:false);let model = try XCTUnwrap(service.controller.imageStackWorkspace);model.addOpenDocuments();model.refresh();await model.task?.value
      XCTAssertTrue(model.ready,model.error ?? "Not ready")
      let view = NSHostingView(rootView:ImageStackView(model:model));view.frame = NSRect(x:0,y:0,width:830,height:630);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,0)
      service.controller.beginHDRMerge(display:false);service.controller.beginPhotomerge(display:false);XCTAssertNil(service.controller.hdrMergeWorkspace);XCTAssertNil(service.controller.photomergeWorkspace)
      try original.store.session.execute(.renameLayer(original.store.document.layers[0].id,"Changed"));original.store.revision += 1
      XCTAssertThrowsError(try model.commit(display:false));model.refresh();await model.task?.value
      let prepared = try XCTUnwrap(model.result).document,created = try model.commit(display:false)
      XCTAssertTrue(created.store.document == prepared);XCTAssertNil(created.fileURL);XCTAssertTrue(created.isDocumentEdited)
      service.controller.beginImageStack(display:false);service.controller.imageStackWorkspace?.addOpenDocuments();service.controller.cancelImageStack();XCTAssertNil(service.controller.imageStackWorkspace)
    }
  }
  @MainActor func testHTTPModeCreationHistoryVersionAndGuards() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,original in
      let params = try setup(service,original);defer { cleanup(service,original) }
      let disabled = try await helper.edit(service,original,"document.imageStack",params);XCTAssertEqual(disabled,403)
      service.setDocumentTransfersEnabled(true)
      let snapshots = service.shares.map{$0.document!.store.document}
      let response = try await helper.request(service,path:"/v1/documents/\(service.shares[0].id)/commands",body:["command":"document.imageStack","revision":service.revision(original.store),"parameters":params])
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      let created = try XCTUnwrap(service.shares.last?.document),id = created.store.document.layers[0].id
      @MainActor func editCreated(_ name: String,_ params: [String:Any] = [:],revision: String? = nil) async throws -> Int {
        let response = try await helper.request(service,path:"/v1/documents/\(service.shares.last!.id)/commands",body:["command":name,"revision":revision ?? service.revision(created.store),"parameters":params])
        return response.0.statusCode
      }
      for mode in ImageStackMode.allCases {
        var expected = EditorSession(document:created.store.document);try expected.execute(ImageStack.command(in:created.store.document,layerID:id,mode:mode))
        let status = try await editCreated("smartObject.stackMode",["layerID":id.uuidString,"mode":mode.rawValue]);XCTAssertEqual(status,200)
        XCTAssertTrue(created.store.document == expected.document)
      }
      let stacked = created.store.document
      let none = try await editCreated("smartObject.stackMode",["layerID":id.uuidString,"mode":"none"]);XCTAssertEqual(none,200);XCTAssertNil(created.store.activeLayer?.smartObject?.stackMode)
      let undo = try await editCreated("history.undo");XCTAssertEqual(undo,200);XCTAssertTrue(created.store.document == stacked)
      let bad = try await editCreated("smartObject.stackMode",["layerID":id.uuidString,"mode":"bad"]);XCTAssertEqual(bad,400)
      let stale = try await editCreated("smartObject.stackMode",["layerID":id.uuidString,"mode":"mean"],revision:"old");XCTAssertEqual(stale,409)
      let base = "/v1/documents/\(service.shares.last!.id)/file.photato"
      let old = try await helper.request(service,path:base,headers:["X-Photato-Archive-Version":"22"]);XCTAssertEqual(old.0.statusCode,422)
      let saved = try await helper.request(service,path:base,headers:["X-Photato-Archive-Version":"23"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1) == created.store.document)
      for (i,share) in service.shares.prefix(3).enumerated() { XCTAssertTrue(share.document!.store.document == snapshots[i]);XCTAssertTrue(share.document!.store.session.undoStack.isEmpty) }
    }
  }
  func testAdobeInstalledRendererDescriptorSharesNativeHistoryAndRejectsUnknown() throws {
    let d = try smart(),id = d.layers[0].id
    for (code,mode) in [("$avrg",ImageStackMode.mean),("$medn",.median),("$summ",.summation),("$stdv",.standardDeviation)] {
      let program = try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"applyImageStackPluginRenderer\",\"imageStackPlugin\":{\"_class\":\"\(code)\"},\"name\":\"Stack\"}]")
      let result = try program.applying(to:d,stackRenderer:{try ImageStack.command(in:$0,layerID:$1,mode:$2)})
      var expected = EditorSession(document:d);try expected.execute(ImageStack.command(in:d,layerID:id,mode:mode))
      XCTAssertTrue(result.session.document == expected.document);XCTAssertEqual(result.session.undoStack.count,1)
    }
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"applyImageStackPluginRenderer\",\"imageStackPlugin\":{\"_class\":\"bogus\"}}]"))
  }

  @MainActor func testBothAdobeJobRoutesUseStackRenderer() async throws {
    let input = try PSDCodec.writeRasterLayers(smart()),decoded = try PSDCodec.read(input)
    let action = #"[{"_obj":"applyImageStackPluginRenderer","imageStackPlugin":{"_class":"$medn"},"name":"Median"}]"#
    var expected = decoded;try ImageStack.command(in:decoded,layerID:decoded.layers[0].id,mode:.median).apply(to:&expected)
    let body: [String:Any] = ["image":["source":["url":"https://example.test/stack.psd"]],"options":["actions":[["source":["content":action,"contentType":"application/json"]]]],"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:StackFixtureTransport(data:input)) { service,shared in
      service.setResourceJobsEnabled(true);let original = shared.store.document
      for path in ["/v1/action-jobs","/v2/execute-actions"] {
        let output = try await AutomationActionJobsTests().output(service,submit:path,payload:body,expectedMediaType:"image/png")
        XCTAssertEqual(output.2,try DocumentIO.encode(expected,format:.png))
      };XCTAssertTrue(shared.store.document == original)
    }
  }
  @MainActor func testFolderLoadingInvalidBatchAndCancel() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,original in
      defer { cleanup(service,original) }
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer { try? FileManager.default.removeItem(at:folder) }
      for i in 0..<2 { try NativeArchive.encodeChunked(source()).write(to:folder.appendingPathComponent("Photo\(i).photato")) }
      service.controller.beginImageStack(display:false);let model = try XCTUnwrap(service.controller.imageStackWorkspace)
      model.load([folder],folder:true);await model.loadingTask?.value;XCTAssertEqual(model.sources.count,2);XCTAssertNil(model.error)
      model.refresh();await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
      let bad = folder.appendingPathComponent("Broken.photato");try Data("broken".utf8).write(to:bad)
      model.load([bad]);await model.loadingTask?.value;XCTAssertEqual(model.sources.count,2);XCTAssertNotNil(model.error);XCTAssertFalse(model.ready)
      service.controller.cancelImageStack();XCTAssertEqual(service.controller.documents.count,1)
    }
  }
  @MainActor func testStackedChildSaveRetainsModesAndParentUndo() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,parent in
      defer { cleanup(service,parent) }
      var d = try smart();let id = d.layers[0].id
      try ImageStack.command(in:d,layerID:id,mode:.mean).apply(to:&d)
      parent.store.session = EditorSession(document:d)
      let object = d.layers[0].smartObject!,child = CraftNSDocument(model:try SmartObjectIO.sourceDocument(object))
      service.controller.addDocument(child);child.smartObjectEditLink = .init(parent:parent,layerID:id,source:object)
      child.store.perform(.fill(child.store.document.layers[0].id,Pixel(1,0,0)))
      let expected = try ImageStack.render(child.store.document,mode:.mean,in:d)
      try await child.commitSmartObjectContents();XCTAssertEqual(parent.store.activeLayer?.smartObject?.stackMode,.mean)
      XCTAssertEqual(try Renderer.layerSurface(parent.store.activeLayer!,in:parent.store.document),expected)
      await parent.store.undo();XCTAssertTrue(parent.store.document == d)
    }
  }
  @MainActor func testAPICancelRevocationBusyStaleAndInvalidSettings() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,original in
      let params = try setup(service,original);defer { cleanup(service,original) };service.setDocumentTransfersEnabled(true)
      var invalid = params;invalid["settings"] = ["mode":"median"]
      let bad = try await helper.edit(service,original,"document.imageStack",invalid);XCTAssertEqual(bad,400)
      var stale = params;var sources = params["sources"] as! [[String:Any]];sources[1]["revision"] = "stale";stale["sources"] = sources
      let conflict = try await helper.edit(service,original,"document.imageStack",stale);XCTAssertEqual(conflict,409)
      service.controller.beginHDRMerge(display:false)
      let busy = try await helper.edit(service,original,"document.imageStack",params);XCTAssertEqual(busy,409);service.controller.cancelHDRMerge()
      for share in service.shares {
        let doc = share.document!;var large = try CraftDocument(width:512,height:512)
        large.layers[0].content = .raster(try Surface(width:512,height:512,fill:Pixel(0.3,0.5,0.8)))
        doc.store.renderTask?.cancel();doc.store.session = EditorSession(document:large);doc.store.revision += 1
      }
      for revoke in [false,true] {
        var current = params;current["sources"] = service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]}
        let command = try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"document.imageStack","revision":service.revision(original.store),"parameters":current])),id = service.shares[0].id
        let task = Task { try await service.executeImageStack(command,anchorID:id) }
        for _ in 0..<100 where service.imageStackOperationID == nil { try await Task.sleep(for:.milliseconds(1)) }
        XCTAssertNotNil(service.imageStackOperationID)
        if revoke { service.setDocumentTransfersEnabled(false) }
        else { let operation = try XCTUnwrap(service.imageStackOperationID),status = try await helper.edit(service,original,"document.imageStack.cancel",["operationID":operation.uuidString]);XCTAssertEqual(status,200) }
        do { _ = try await task.value;XCTFail("Cancelled stack published") } catch is CancellationError {} catch { XCTAssertTrue(error is AutomationFailure) }
        XCTAssertEqual(service.controller.documents.count,3);XCTAssertNil(service.imageStackOperationID);XCTAssertFalse(service.documentTransferBusy);XCTAssertFalse(original.store.geometryBusy)
      }
    }
  }
}
