import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class EmbeddedPlacementWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width:8,height:6)
    var pixels = try Surface(width:8,height:6)
    for y in 0..<6 {for x in 0..<8 {pixels.setPixel(x:x,y:y,Pixel(x<4 ? 1:0,y<3 ? 1:0,(x+y)%2 == 0 ? 1:0,1))}}
    d.layers[0].content = .raster(pixels);return d
  }
  func folder() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);return root
  }
  func output(_ name: String,_ data: Data) throws {
    if let path = ProcessInfo.processInfo.environment["PHOTATO_PLACEMENT_OUTPUT"] {
      let root = URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
      try data.write(to:root.appendingPathComponent(name))
    }
  }
  @MainActor func testRasterNativePSDAndPSBPreviewCancelCommitAndUndo() async throws {
    let root = try folder();defer {try? FileManager.default.removeItem(at:root)}
    for format in [DocumentIO.Format.png,.jpeg,.tiff,.native,.psd,.psb] {
      let data = try DocumentIO.encode(fixture(),format:format),url = root.appendingPathComponent("Original."+format.rawValue)
      try data.write(to:url)
      let original = try CraftDocument(width:16,height:12),store = EditorStore(document:original)
      defer {store.renderTask?.cancel()}
      var changes = 0;store.onChange = {_ in changes += 1}
      store.selectedLayerIDs = Set(original.activeLayerID.map{[$0]} ?? [])
      store.placeEmbeddedSource(url);await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertNotNil(store.transformDraft);XCTAssertEqual(store.document,original)
      XCTAssertEqual(store.embeddedPlacementState["stage"] as? String,"transform")
      XCTAssertEqual(store.pdfPlacementState["stage"] as? String,"idle")
      XCTAssertEqual(store.activeLayer?.smartObject?.data,data);XCTAssertEqual(changes,0)
      store.cancelTransform();XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(store.embeddedPlacement);XCTAssertEqual(store.selectedLayerIDs,Set(original.activeLayerID.map{[$0]} ?? []))
      store.placeEmbeddedSource(url);await store.geometryTask?.value
      var transform = try XCTUnwrap(store.transformDraft);transform.angle = 90;transform.centerX += 2
      store.updateTransform(transform);let expected = try Renderer.composite(store.previewDocument).rgbaData(depth:.u8)
      store.commitTransform();await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(changes,1)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth:.u8),expected)
      XCTAssertEqual(store.activeLayer?.smartObject?.data,data);XCTAssertEqual(try Data(contentsOf:url),data)
      let placed = store.document;XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(placed)),placed)
      await store.undo();XCTAssertEqual(store.document,original);await store.redo();XCTAssertEqual(store.document,placed)
      if format == .png {try output("rotated-placement.png",DocumentIO.encode(placed,format:.png))}
    }
  }
  @MainActor func testRAWChooserSettingsCancelAndRetainedSource() async throws {
    let root = try folder();defer {try? FileManager.default.removeItem(at:root)}
    let bytes = try RawDevelopmentWorkflowTests().data(),url = root.appendingPathComponent("Sensor.dng");try bytes.write(to:url)
    let original = try CraftDocument(width:64,height:48),parent = CraftNSDocument(model:original),store = parent.store
    defer {store.renderTask?.cancel()}
    store.rawPlacementPresenter = {workspace in
      XCTAssertEqual(store.embeddedPlacementState["stage"] as? String,"developingRaw")
      XCTAssertEqual(store.document,original);workspace.cancel()
    }
    store.placeEmbeddedSource(url);await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertNil(store.transformDraft);XCTAssertEqual(store.document,original)
    store.rawPlacementPresenter = {workspace in Task {@MainActor in
      await workspace.prepare();XCTAssertTrue(workspace.model.ready,workspace.model.error ?? "")
      var settings = workspace.model.sensorSettings!;settings.exposure = 0.5
      workspace.model.changeSensor(settings);await workspace.model.task?.value;workspace.run()
    }}
    store.placeEmbeddedSource(url);await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.activeLayer?.smartObject?.rawDevelopment?.exposure,0.5)
    XCTAssertEqual(store.document,original);XCTAssertNil(store.rawPlacementWorkspace)
    store.commitTransform();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(store.activeLayer?.smartObject?.data,bytes)
    XCTAssertEqual(try Data(contentsOf:url),bytes);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(store.document)),store.document)
    await store.undo();XCTAssertEqual(store.document,original)
    store.rawPlacementPresenter = {_ in}
    store.placeEmbeddedSource(url);let pending = store.geometryTask
    for _ in 0..<200 where store.rawPlacementWorkspace == nil {try await Task.sleep(for:.milliseconds(5))}
    XCTAssertNotNil(store.rawPlacementWorkspace);parent.close();await pending?.value
    XCTAssertNil(store.rawPlacementWorkspace);XCTAssertNil(store.embeddedPlacementOperationID)
    XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testCloseStaleInvalidSourceAndCancellationCannotPublish() async throws {
    let root = try folder();defer {try? FileManager.default.removeItem(at:root)}
    let url = root.appendingPathComponent("Artwork.png");try DocumentIO.encode(fixture(),format:.png).write(to:url)
    let original = try CraftDocument(width:16,height:12),doc = CraftNSDocument(model:original),store = doc.store
    defer {store.renderTask?.cancel()}
    store.placeEmbeddedSource(url);let pending = store.geometryTask;store.cancelActiveOperation();await pending?.value
    XCTAssertEqual(store.document,original);XCTAssertNil(store.embeddedPlacement);XCTAssertFalse(store.geometryBusy)
    store.placeEmbeddedSource(url);await store.geometryTask?.value
    var newer = original;newer.name = "Changed";store.session = EditorSession(document:newer)
    store.commitTransform();XCTAssertNotNil(store.error);XCTAssertEqual(store.document,newer);XCTAssertNil(store.embeddedPlacement)
    try Data("Not an image".utf8).write(to:url)
    store.placeEmbeddedSource(url);await store.geometryTask?.value
    XCTAssertNotNil(store.error);XCTAssertEqual(store.document,newer);XCTAssertTrue(store.session.undoStack.isEmpty)
    try DocumentIO.encode(fixture(),format:.png).write(to:url)
    store.placeEmbeddedSource(url);await store.geometryTask?.value;doc.close()
    XCTAssertNil(store.embeddedPlacement);XCTAssertNil(store.transformDraft);XCTAssertNil(store.embeddedPlacementOperationID)
  }
  @MainActor func upload(_ service: AutomationService,_ parent: CraftNSDocument,_ data: Data,
    name: String = "Artwork.png",options: [String:Any] = [:],revision: String? = nil,type: String = "application/octet-stream") async throws -> (HTTPURLResponse,Data) {
    let id = try XCTUnwrap(service.shares.first(where:{$0.document === parent})?.id)
    return try await DocumentIOWorkflowTests().request(service,path:"/v1/documents/\(id)/smart-objects/source",data:data,type:type,
      headers:["X-Photato-Name":name,"X-Photato-Revision":revision ?? service.revision(parent.store),
        "X-Photato-Placement-Options":String(decoding:try JSONSerialization.data(withJSONObject:options),as:UTF8.self)])
  }
  @MainActor func testBinaryHTTPMatchesNativeOriginalBytesTransformAndUndo() async throws {
    let root = try folder();defer {try? FileManager.default.removeItem(at:root)}
    let bytes = try DocumentIO.encode(fixture(),format:.png),url = root.appendingPathComponent("Artwork.png");try bytes.write(to:url)
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,parent in
      parent.store.session = EditorSession(document:try CraftDocument(width:16,height:12));try service.share(parent)
      let original = parent.store.document,store = EditorStore(document:original);defer {store.renderTask?.cancel()}
      let disabled = try await upload(service,parent,bytes);XCTAssertEqual(disabled.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      store.placeEmbeddedSource(url);await store.geometryTask?.value
      var transform = try XCTUnwrap(store.transformDraft);transform.angle = 90;transform.centerX += 2;store.updateTransform(transform)
      let matrix = try JSONSerialization.jsonObject(with:JSONEncoder().encode(transform.delta))
      store.commitTransform();await store.geometryTask?.value
      let stale = try await upload(service,parent,bytes,revision:"stale");XCTAssertEqual(stale.0.statusCode,409)
      let mime = try await upload(service,parent,bytes,type:"text/plain");XCTAssertEqual(mime.0.statusCode,415)
      let response = try await upload(service,parent,bytes,options:["transform":matrix]);XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1,as:UTF8.self))
      XCTAssertEqual(try Renderer.composite(parent.store.document).rgbaData(depth:.u8),try Renderer.composite(store.document).rgbaData(depth:.u8))
      XCTAssertEqual(parent.store.activeLayer?.smartObject?.data,bytes);XCTAssertEqual(parent.store.session.undoStack.count,1)
      let shared = try XCTUnwrap(service.shares.first?.id),layer = try XCTUnwrap(parent.store.activeLayer?.id)
      let download = try await AutomationTests().request(service,path:"/v1/documents/\(shared)/smart-objects/\(layer)/source")
      XCTAssertEqual(download.1,bytes)
      let undo = try await AutomationTests().edit(service,parent,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(parent.store.document,original)
      parent.store.placeEmbeddedSource(url);await parent.store.geometryTask?.value
      let busy = try await upload(service,parent,bytes);XCTAssertEqual(busy.0.statusCode,409);parent.store.cancelTransform()
    }
  }
  @MainActor func testBinaryRAWSettingsAndFrameReplacement() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,parent in
      try service.share(parent);service.setDocumentTransfersEnabled(true)
      let raw = try RawDevelopmentWorkflowTests().data()
      let placed = try await upload(service,parent,raw,name:"Sensor.dng",options:["rawDevelopment":["exposure":0.5]])
      XCTAssertEqual(placed.0.statusCode,200,String(decoding:placed.1,as:UTF8.self))
      XCTAssertEqual(parent.store.activeLayer?.smartObject?.data,raw);XCTAssertEqual(parent.store.activeLayer?.smartObject?.rawDevelopment?.exposure,0.5)
      let id = try XCTUnwrap(parent.store.activeLayer?.id),before = parent.store.document
      let png = try DocumentIO.encode(fixture(),format:.png)
      let replacement = try await upload(service,parent,png,options:["layerID":id.uuidString])
      XCTAssertEqual(replacement.0.statusCode,200);XCTAssertEqual(parent.store.activeLayer?.smartObject?.data,png)
      let undo = try await AutomationTests().edit(service,parent,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(parent.store.document,before)
      var frameDocument = try CraftDocument(width:16,height:12)
      try Command.frame(.create(name:"Frame",bounds:IntRect(x:0,y:0,width:16,height:12),definition:FrameDefinition(width:16,height:12),children:[])).apply(to:&frameDocument)
      let frame = try XCTUnwrap(frameDocument.activeLayerID);parent.store.session = EditorSession(document:frameDocument)
      let framed = try await upload(service,parent,png,options:["frameID":frame.uuidString,"frameFit":"fit"])
      XCTAssertEqual(framed.0.statusCode,200);XCTAssertEqual(parent.store.document.children(of:frame).first?.smartObject?.data,png)
      XCTAssertEqual(parent.store.session.undoStack.count,1)
    }
  }
  @MainActor func testSharedSourceInitialTransformAndStrictOptions() async throws {
    let original = try CraftDocument(width:16,height:12),source = try fixture()
    let transform = Transform2D.translation(2,1)
    let command = try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"smartObject.place","revision":"test","parameters":["sourceDocumentID":UUID().uuidString,"sourceRevision":"test","transform":try JSONSerialization.jsonObject(with:JSONEncoder().encode(transform))]]))
    var actual = original;try command.smartObjectCommand(document:actual,source:source).apply(to:&actual)
    var expected = original;var options = EmbeddedSourceOptions();options.transform = transform
    try EmbeddedSourceAPI.prepare(NativeArchive.encodeChunked(source),"Contents.photato",expected,options).apply(to:&expected)
    XCTAssertEqual(try Renderer.composite(actual).rgbaData(depth:.u8),try Renderer.composite(expected).rgbaData(depth:.u8))
    for bad in ["{\"wat\":1}","{\"fit\":0}","{\"preserveSize\":true}","{\"frameFit\":\"fit\"}","{\"transform\":{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"tx\":0,\"ty\":0}}","{\"rawDevelopment\":{\"exposure\":true}}","{\"rawDevelopment\":{\"exposure\":6}}"] {
      XCTAssertThrowsError(try EmbeddedSourceAPI.options(bad),bad)
    }
    let uuid = UUID().uuidString
    XCTAssertThrowsError(try EmbeddedSourceAPI.options("{\"layerID\":\"\(uuid)\",\"fit\":true}"))
    XCTAssertThrowsError(try EmbeddedSourceAPI.options("{\"layerID\":\"\(uuid)\",\"frameID\":\"\(uuid)\"}"))
    let bytes = try DocumentIO.encode(source,format:.png)
    var rawOptions = EmbeddedSourceOptions();rawOptions.rawDevelopment = .init()
    XCTAssertThrowsError(try EmbeddedSourceAPI.prepare(bytes,"fake.dng",original,rawOptions))
  }
  @MainActor func testBinaryCancellationAndRevocationLeaveNoHistory() async throws {
    for revoke in [false,true] {
      try await AutomationTests().withService(pressedMouseButtons:{0}) {service,parent in
        try service.share(parent);service.setDocumentTransfersEnabled(true)
        service.embeddedSourcePreparation = {data,name,original,options in
          try await Task.sleep(for:.milliseconds(200));return try EmbeddedSourceAPI.prepare(data,name,original,options)
        }
        let original = parent.store.document,share = try XCTUnwrap(service.shares.first?.id),bytes = try DocumentIO.encode(fixture(),format:.png)
        let pending = Task {try await upload(service,parent,bytes)}
        for _ in 0..<100 where !parent.store.geometryBusy {try await Task.sleep(for:.milliseconds(5))}
        XCTAssertTrue(parent.store.geometryBusy)
        let operation = try XCTUnwrap(service.embeddedSourceOperations[share])
        if revoke {service.setDocumentTransfersEnabled(false)} else {
          let helper = AutomationTests()
          let wrong = try await helper.request(service,path:"/v1/documents/\(share)/smart-objects/source/cancel",body:["operationID":UUID().uuidString]);XCTAssertEqual(wrong.0.statusCode,409)
          let cancelled = try await helper.request(service,path:"/v1/documents/\(share)/smart-objects/source/cancel",body:["operationID":operation.uuidString]);XCTAssertEqual(cancelled.0.statusCode,200)
        }
        let response = try await pending.value;XCTAssertEqual(response.0.statusCode,409)
        XCTAssertEqual(parent.store.document,original);XCTAssertTrue(parent.store.session.undoStack.isEmpty);XCTAssertTrue(service.embeddedSourceOperations.isEmpty)
      }
    }
  }
  @MainActor func testRAWPlacementControlsOffscreenAndIdempotentCancel() async throws {
    let workspace = try RawPlacementWorkspace(document:RawDevelopmentWorkflowTests().fixture())
    await workspace.prepare();XCTAssertTrue(workspace.model.ready,workspace.model.error ?? "")
    var completions = 0;workspace.completion = {_ in completions += 1}
    let window = RawPlacementWindow(model:workspace);defer {window.close()}
    XCTAssertEqual(window.window?.title,"Camera Raw — Place Embedded")
    if ProcessInfo.processInfo.environment["PHOTATO_PLACEMENT_OUTPUT"] != nil {
      let host = NSHostingView(rootView:CameraRawSheet(store:workspace.store,workspace:workspace.model,placement:workspace).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.light))
      window.window?.appearance = NSAppearance(named:.aqua);window.window?.contentView = host
      host.frame = NSRect(x:0,y:0,width:1100,height:720);host.layoutSubtreeIfNeeded()
      try await Task.sleep(for:.milliseconds(150));await workspace.model.task?.value;host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
      try output("raw-placement-controls.png",XCTUnwrap(bitmap.representation(using:.png,properties:[:])))
    }
    workspace.cancel();workspace.cancel();XCTAssertEqual(completions,1);XCTAssertTrue(workspace.finished)
  }
}
