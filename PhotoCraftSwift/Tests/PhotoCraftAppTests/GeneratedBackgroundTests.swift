import AppKit
import ImagePlayground
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GeneratedBackgroundTests: XCTestCase {
  let capability = AICapability(available: true, message: "Owned validation; no provider invoked")
  func document(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 6, depth: depth, name: "Owned masked subject")
    var pixels = try Surface(width: 8, height: 6, depth: depth)
    var mask = try Surface(width: 8, height: 6, depth: depth, fill: .black)
    for y in 0..<6 { for x in 0..<8 {
      pixels.setPixel(x: x, y: y, Pixel(Float(x + 1) / 10, Float(y + 1) / 8, 0.25))
      let v: Float = (2..<6).contains(x) && (1..<5).contains(y) ? 1 : 0
      mask.setPixel(x: x, y: y, Pixel(v, v, v))
    }}
    d.layers[0].background = nil; d.layers[0].protection = []; d.layers[0].locked = false
    d.layers[0].name = "Subject"; d.layers[0].content = .raster(pixels); d.layers[0].mask = mask
    var properties = MaskProperties(); properties.linked = false
    d.layers[0].maskProperties = properties
    d.selection = .init(x: 3, y: 2, width: 2, height: 2)
    try d.validate(); return d
  }
  func image() throws -> Data {
    var d = try CraftDocument(width: 2, height: 4)
    d.layers[0].content = .raster(try Surface(width: 2, height: 4, fill: Pixel(0, 0, 1)))
    return try DocumentIO.encode(d, format: .png)
  }
  /// Public-format raw merged plane reader, independent of Photato's decoder.
  func rawRGB32Composite(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    func number(_ at: Int, _ count: Int) throws -> Int {
      guard at >= 0, count > 0, at + count <= bytes.count else { throw CraftError.invalid("Truncated owned PSD reference") }
      return bytes[at..<at+count].reduce(0) { $0 * 256 + Int($1) }
    }
    XCTAssertEqual(Array(bytes.prefix(4)), Array("8BPS".utf8))
    XCTAssertEqual(try number(4,2),1); XCTAssertEqual(try number(14,4),6)
    XCTAssertEqual(try number(18,4),8); XCTAssertEqual(try number(22,2),32); XCTAssertEqual(try number(24,2),3)
    XCTAssertGreaterThanOrEqual(try number(12,2),3)
    var at=26
    for _ in 0..<3 { let size=try number(at,4); at += 4 + size }
    XCTAssertEqual(try number(at,2),0); at += 2
    guard at + 576 <= bytes.count else { throw CraftError.invalid("Truncated RGB32 plane data") }
    return Data(bytes[at..<at+576])
  }
  @MainActor func store(_ depth: PixelDepth = .u8) throws -> EditorStore {
    let s = try ImageGenerationLifecycleTests().store(depth)
    s.session = EditorSession(document: try document(depth)); s.renderTask?.cancel()
    s.imageGenerationIntent = .background; s.prompt = "An empty blue studio background"
    return s
  }
  @MainActor func begin(_ s: EditorStore) async throws -> ImageGenerationJob {
    try s.startImageGeneration(capability: capability)
    let job = try XCTUnwrap(s.imageGenerationJob)
    let preparation = try XCTUnwrap(s.aiTask); await preparation.value
    XCTAssertEqual(job.phase, .awaitingSystem, s.aiError ?? "")
    return job
  }
  @MainActor func testAllRGBDepthsKeepSubjectMaskSelectionAndOriginalBytesWithOneUndo() async throws {
    let bytes = try image()
    for depth in PixelDepth.allCases {
      let s = try store(depth); defer { s.cancelAIWork(); s.renderTask?.cancel() }
      let original = s.document, id = try XCTUnwrap(original.activeLayerID)
      let originalPixels = try Renderer.composite(original)
      let job = try await begin(s)
      XCTAssertEqual(job.intent, .background); XCTAssertEqual(job.foregroundLayerID, id)
      XCTAssertEqual(job.referenceWidth, 8); XCTAssertEqual(job.referenceHeight, 6)
      XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
      // Later draft UI changes cannot relabel or redirect an accepted request.
      s.imageGenerationIntent = .image; s.prompt = "Later prompt"
      try s.acceptGeneratedImageData(bytes, requestID: job.id, resultStyle: "owned")
      let task = try XCTUnwrap(s.aiTask); await task.value
      XCTAssertEqual(job.phase, .completed, s.aiError ?? "")
      XCTAssertEqual(s.session.undoStack.count, 1); XCTAssertEqual(s.session.undoStack.last?.label, "Generate Background")
      XCTAssertNil(job.original); XCTAssertNil(job.referenceImage)
      XCTAssertEqual(s.document.layers.count, original.layers.count + 1)
      XCTAssertEqual(Array(s.document.layers.dropFirst()), original.layers)
      XCTAssertEqual(s.document.selection, original.selection); XCTAssertEqual(s.document.selectionMask, original.selectionMask)
      XCTAssertEqual(s.document.width, original.width); XCTAssertEqual(s.document.height, original.height)
      let background = try XCTUnwrap(s.activeLayer)
      XCTAssertEqual(s.document.layers.first?.id, background.id); XCTAssertEqual(background.name, "Generated Background")
      XCTAssertEqual(background.x, 0); XCTAssertEqual(background.y, 0)
      let context = try XCTUnwrap(GeneratedBackground.record(background))
      XCTAssertEqual(context.foregroundLayerID, id); XCTAssertEqual(context.width, 8); XCTAssertEqual(context.height, 6)
      XCTAssertEqual(try GeneratedImageStorage.original(background).1, bytes)
      let record = try XCTUnwrap(GeneratedImageStorage.record(background))
      XCTAssertEqual(record.initialPrompt, "An empty blue studio background")
      if case .raster(let p) = background.content {
        XCTAssertEqual(p.width, 8); XCTAssertEqual(p.height, 6); XCTAssertEqual(p.depth, depth)
        for y in 0..<6 { for x in 0..<8 {
          XCTAssertEqual(p.pixel(x: x, y: y), Pixel(0, 0, 1), "Opaque cover must not introduce transparent edges")
        }}
      } else { XCTFail("Expected background pixels") }
      let composed = try Renderer.composite(s.document)
      if depth == .f32 {
        // Stored subject samples/mask already compare exactly above. Opaque
        // source-over arithmetic/profile conversion is not a bitwise identity.
        // Keep the separate observed in-memory/file residual open and require
        // exact independent Photoshop output for the exported working image.
        let url=try XCTUnwrap(Bundle.module.url(forResource:"photoshop-exported-rgb32-planar",
          withExtension:"bin",subdirectory:"Fixtures/GeneratedBackground490"))
        let expected=try Data(contentsOf:url)
        XCTAssertEqual(try rawRGB32Composite(PSDCodec.writeRasterLayers(s.document,compression:.raw)),expected)
      } else {
        for y in 1..<5 { for x in 2..<6 {
          XCTAssertEqual(composed.pixel(x: x, y: y), originalPixels.pixel(x: x, y: y), "Fully protected subject pixels")
        }}
      }
      XCTAssertEqual(composed.pixel(x: 0, y: 0), Pixel(0, 0, 1), "Background ignores current selection")
      let result = s.document
      let restored = try DocumentIO.decode(DocumentIO.encode(result, format: .native), native: true, name: "Offline")
      XCTAssertEqual(restored.layers, result.layers); XCTAssertEqual(restored.selection, result.selection)
      XCTAssertEqual(try GeneratedBackground.record(restored.layers[0]), context)
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let directory = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try DocumentIO.encode(original, format: .native).write(to: directory.appendingPathComponent("background-source-\(depth.rawValue).photato"))
        try DocumentIO.encode(result, format: .native).write(to: directory.appendingPathComponent("background-owned-result-\(depth.rawValue).photato"))
      }
      let undone = await s.undo(); XCTAssertTrue(undone); XCTAssertEqual(s.document, original)
      let redone = await s.redo(); XCTAssertTrue(redone); XCTAssertEqual(s.document, result)
    }
  }
  func testExistingLayerHierarchyAndMaskPropertiesAreRetainedAndInvalidTargetsReject() throws {
    var d = try document(.f32)
    var p = d.layers[0].effectiveMaskProperties
    p.transform = .translation(0.25, -0.5); p.density = 0.85; p.feather = 1.5; p.inverted = true
    d.layers[0].maskProperties = p; d.layers[0].opacity = 0.75
    let lower = Layer(name: "Original lower image", content: .raster(try Surface(width: 8, height: 6, depth: .f32, fill: .white)))
    d.layers.insert(lower, at: 0)
    let source = d, id = try XCTUnwrap(source.activeLayerID)
    let layer = try GeneratedBackground.prepareLayer(image(), source: source, requestID: UUID(),
      sourceRevision: UUID(), initialPrompt: "Owned background", startedAt: Date(), acceptedAt: Date(),
      processing: .unknown, resultStyle: nil)
    let command = try GeneratedBackground.command(layer, source: source, foregroundID: id)
    var result = source; try command.apply(to: &result)
    XCTAssertEqual(result.layers.map(\.id), [lower.id, layer.id, id])
    XCTAssertEqual(result.layers[0], source.layers[0]); XCTAssertEqual(result.layers[2], source.layers[1])
    var changed = source; changed.layers[1].name = "Changed"
    XCTAssertThrowsError(try command.apply(to: &changed)); XCTAssertEqual(changed.layers[1].name, "Changed")
    let mutations: [(inout CraftDocument) -> Void] = [
      { $0.layers[1].mask = nil }, { $0.layers[1].visible = false },
      { $0.layers[1].parentID = UUID() }, { $0.layers[1].clipped = true },
      { $0.layers[1].background = true },
      { $0.layers[1].maskProperties?.enabled = false },
      { $0.width = 0 }, { $0.height = 0 }, { $0.width = 300001 },
    ]
    for mutate in mutations {
      var bad = source; mutate(&bad); XCTAssertNil(GeneratedBackground.foreground(in: bad))
      XCTAssertThrowsError(try GeneratedBackground.reference(bad))
    }
    var malformed = layer; malformed.x = 1
    XCTAssertThrowsError(try GeneratedBackground.command(malformed, source: source, foregroundID: id))
    malformed = layer; malformed.sourceTags?[GeneratedBackground.contextKey] = Data("{}".utf8)
    XCTAssertThrowsError(try GeneratedBackground.command(malformed, source: source, foregroundID: id))
    XCTAssertThrowsError(try GeneratedBackground.command(layer, source: source, foregroundID: UUID()))
    XCTAssertEqual(source, d)
  }
  @MainActor func testReferenceCancellationCannotClearAReplacementJob() async throws {
    let s = try store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelAIWork(); s.renderTask?.cancel() }
    s.backgroundReferencePreparation = { source in await gate.wait(); return try GeneratedBackground.reference(source) }
    try s.startImageGeneration(capability: capability)
    let first = try XCTUnwrap(s.imageGenerationJob), task = try XCTUnwrap(s.aiTask), original = s.document
    try await ImageGenerationLifecycleTests().wait(gate)
    XCTAssertEqual(first.phase, .preparingReference); XCTAssertFalse(s.showImagePlayground)
    s.cancelImageGeneration(first.id)
    s.imageGenerationIntent = .image; try s.startImageGeneration(capability: capability)
    let second = try XCTUnwrap(s.imageGenerationJob)
    await gate.release(); await task.value
    XCTAssertEqual(first.phase, .cancelled); XCTAssertNil(first.referenceImage)
    XCTAssertTrue(s.imageGenerationJob === second); XCTAssertEqual(second.phase, .awaitingSystem)
    XCTAssertTrue(s.aiBusy); XCTAssertTrue(s.showImagePlayground)
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testEditThenUndoDuringReferencePreparationStillRejectsOldSnapshot() async throws {
    let s = try store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelAIWork(); s.renderTask?.cancel() }
    s.backgroundReferencePreparation = { source in await gate.wait(); return try GeneratedBackground.reference(source) }
    let original = s.document
    try s.startImageGeneration(capability: capability)
    let job = try XCTUnwrap(s.imageGenerationJob), task = try XCTUnwrap(s.aiTask)
    try await ImageGenerationLifecycleTests().wait(gate)
    try s.executeEditorCommand(.renameLayer(try XCTUnwrap(original.activeLayerID), "Transient edit"))
    let undone = await s.undo(); XCTAssertTrue(undone); XCTAssertEqual(s.document, original)
    await gate.release(); await task.value
    XCTAssertEqual(job.phase, .stale); XCTAssertNil(job.referenceImage); XCTAssertNil(job.original)
    XCTAssertFalse(s.aiBusy); XCTAssertFalse(s.showImagePlayground); XCTAssertEqual(s.document, original)
  }
  @MainActor func testCancellationDuringBackgroundPreparationKeepsAcceptedOriginalAndSource() async throws {
    let s = try store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelAIWork(); s.renderTask?.cancel() }
    s.backgroundGenerationPreparation = { bytes,source,id,revision,prompt,start,accepted,processing,style in
      await gate.wait()
      return try GeneratedBackground.prepareLayer(bytes,source:source,requestID:id,sourceRevision:revision,
        initialPrompt:prompt,startedAt:start,acceptedAt:accepted,processing:processing,resultStyle:style)
    }
    let job = try await begin(s), original = s.document
    try s.acceptGeneratedImageData(image(), requestID: job.id)
    let task = try XCTUnwrap(s.aiTask); try await ImageGenerationLifecycleTests().wait(gate)
    let retained = try XCTUnwrap(job.retainedResultID)
    s.cancelImageGeneration(job.id); await gate.release(); await task.value
    XCTAssertEqual(job.phase, .cancelled); XCTAssertEqual(s.document, original)
    XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertNotNil(s.authorizedGeneratedResults[retained])
  }
  @MainActor func testChangedForegroundWhileBackgroundPreparesNeverPublishesResult() async throws {
    let s = try store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelAIWork(); s.renderTask?.cancel() }
    s.backgroundGenerationPreparation = { bytes,source,id,revision,prompt,start,accepted,processing,style in
      await gate.wait()
      return try GeneratedBackground.prepareLayer(bytes,source:source,requestID:id,sourceRevision:revision,
        initialPrompt:prompt,startedAt:start,acceptedAt:accepted,processing:processing,resultStyle:style)
    }
    let job = try await begin(s)
    try s.acceptGeneratedImageData(image(), requestID: job.id)
    let task = try XCTUnwrap(s.aiTask); try await ImageGenerationLifecycleTests().wait(gate)
    try s.executeEditorCommand(.invertMask(try XCTUnwrap(job.foregroundLayerID)))
    let changed = s.document
    await gate.release(); await task.value
    XCTAssertEqual(job.phase, .stale); XCTAssertEqual(s.document, changed); XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertNotNil(job.retainedResultID)
  }
  @MainActor func testHTTPBackgroundPreparationRetainsNativeApprovalAndValidatesContext() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      doc.store.session = EditorSession(document: try self.document()); doc.store.renderTask?.cancel()
      defer { doc.store.cancelAIWork(); doc.store.renderTask?.cancel() }
      try service.share(doc); let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/ai"
      @MainActor func body(_ intent: Any = "background") -> [String: Any] {
        ["operation": "prepare", "revision": service.revision(doc.store), "prompt": "Owned background", "intent": intent]
      }
      let denied = try await h.request(service, path: path, body: body()); XCTAssertEqual(denied.0.statusCode, 403)
      service.setWorkspacePanelChangesEnabled(true)
      let missingWindow = try await h.request(service, path: path, body: body()); XCTAssertEqual(missingWindow.0.statusCode, 409)
      let controller = NSWindowController(window: NSWindow(contentRect: .init(x: 0,y: 0,width: 300,height: 200),styleMask: [.titled],backing: .buffered,defer: false))
      doc.addWindowController(controller)
      defer { doc.store.showAI=false; doc.removeWindowController(controller); controller.close() }
      let original = doc.store.document
      let accepted = try await h.request(service, path: path, body: body()); XCTAssertEqual(accepted.0.statusCode, 200, String(decoding: accepted.1, as: UTF8.self))
      XCTAssertTrue(doc.store.showAI); XCTAssertFalse(doc.store.aiBusy); XCTAssertNil(doc.store.imageGenerationJob)
      XCTAssertEqual(doc.store.imageGenerationIntent, .background); XCTAssertEqual(doc.store.document, original)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: accepted.1) as? [String:Any])
      XCTAssertEqual(state["intent"] as? String, "background"); XCTAssertEqual(state["requiresNativeApproval"] as? Bool, true)
      XCTAssertEqual((state["background"] as? [String:Any])?["eligibleForegroundLayerID"] as? String, original.activeLayerID?.uuidString)
      for invalid: Any in [true, 0, "outpaint", NSNull()] {
        let invalidReply = try await h.request(service, path: path, body: body(invalid))
        XCTAssertEqual(invalidReply.0.statusCode, 400); XCTAssertEqual(doc.store.document, original)
      }
      var stale = body(); stale["revision"]="stale"
      let staleResponse = try await h.request(service, path:path, body:stale)
      XCTAssertEqual(staleResponse.0.statusCode, 409)
      var extra = body(); extra["headless"]=true
      let extraResponse = try await h.request(service, path:path, body:extra)
      XCTAssertEqual(extraResponse.0.statusCode, 400)
      // Existing clients omit intent and must retain the original image-layer workflow.
      var legacy = body(); legacy.removeValue(forKey:"intent")
      let sheetBusy = try await h.request(service, path:path, body:legacy)
      XCTAssertEqual(sheetBusy.0.statusCode,409)
      doc.store.showAI = false // Native Done; keep the existing interaction fence.
      XCTAssertNotEqual(legacy["revision"] as? String,service.revision(doc.store))
      legacy["revision"] = service.revision(doc.store)
      let legacyResponse = try await h.request(service, path:path, body:legacy)
      XCTAssertEqual(legacyResponse.0.statusCode, 200)
      XCTAssertEqual(doc.store.imageGenerationIntent, .image); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      doc.store.showAI = false
      try doc.store.executeEditorCommand(.deleteMask(try XCTUnwrap(original.activeLayerID)))
      let noMaskResponse = try await h.request(service, path:path, body:body())
      XCTAssertEqual(noMaskResponse.0.statusCode, 409)
      XCTAssertTrue(String(decoding:noMaskResponse.1,as:UTF8.self).contains("masked pixel layer"))
      XCTAssertEqual(doc.store.imageGenerationIntent, .image)
    }
  }
  @MainActor func testHTTPStateSchemasAndOwnedResultShareNativeBackgroundHistory() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      try ImageGenerationLifecycleTests().isolate(doc.store)
      doc.store.session = EditorSession(document: try self.document(.u16)); doc.store.renderTask?.cancel()
      doc.store.imageGenerationIntent = .background; doc.store.prompt = "Owned API background"
      defer { doc.store.cancelAIWork(); doc.store.renderTask?.cancel() }
      try service.share(doc); let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/ai"
      let before = doc.store.document, job = try await self.begin(doc.store)
      var state = AIImageAPI.state(doc.store), jobState = try XCTUnwrap(state["job"] as? [String:Any])
      XCTAssertEqual(jobState["intent"] as? String, "background")
      XCTAssertEqual(jobState["foregroundLayerID"] as? String, before.activeLayerID?.uuidString)
      for (object,schema) in [(state,AIImageAPI.stateSchema),(jobState,AIImageAPI.jobSchema)] {
        let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNoThrow(try BrushAPI.merge(value,schema:schema))
      }
      let bytes = try self.image(); try doc.store.acceptGeneratedImageData(bytes, requestID: job.id)
      let task = try XCTUnwrap(doc.store.aiTask); await task.value
      let response = try await h.request(service,path:path); XCTAssertEqual(response.0.statusCode,200)
      state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String:Any])
      let context = try XCTUnwrap(state["selectedBackground"] as? [String:Any])
      XCTAssertEqual(context["foregroundLayerID"] as? String, before.activeLayerID?.uuidString)
      XCTAssertEqual(context["placement"] as? String,"coverBelowSubject")
      XCTAssertEqual(doc.store.session.undoStack.count,1); XCTAssertEqual(Array(doc.store.document.layers.dropFirst()),before.layers)
      service.setDocumentTransfersEnabled(true)
      let original = try await h.request(service,path:"/v1/documents/\(share.id)/ai/results/\(try XCTUnwrap(job.resultLayerID))")
      XCTAssertEqual(original.0.statusCode,200); XCTAssertEqual(original.1,bytes)
      XCTAssertEqual(AutomationCommand.definitions.count,267)
    }
  }
  @MainActor func testNativeControllerReceivesCapturedSubjectAndBackgroundConcept() async throws {
    let s = try store(); defer { s.cancelAIWork(); s.renderTask?.cancel() }
    let job = try await begin(s)
    guard LocalAI.platform.available else { XCTAssertFalse(LocalAI.imageCapability.available); return }
    guard #available(macOS 26.0, *) else { XCTFail("Current validation host requires macOS26+ for this branch"); return }
    let controller = SystemImagePlayground.makeController(job: job)
    let image = try XCTUnwrap(controller.sourceImage)
    XCTAssertEqual(Int(image.size.width),8); XCTAssertEqual(Int(image.size.height),6)
    XCTAssertEqual(controller.concepts.count,2)
    XCTAssertFalse(controller.allowedGenerationStyles.contains(.externalProvider))
    s.imageGenerationIntent = .image
    XCTAssertEqual(job.intent,.background); XCTAssertEqual(job.foregroundLayerID,s.document.activeLayerID)
  }
  @MainActor func testNativePreparationAndUnavailableProviderDoNotReadReferenceOrEdit() throws {
    let s = try store(); defer { s.cancelAIWork(); s.renderTask?.cancel() }
    let before = s.document
    s.imageGenerationIntent = .image; s.prepareBackgroundGeneration()
    XCTAssertEqual(s.imageGenerationIntent,.background); XCTAssertTrue(s.showAI)
    XCTAssertTrue(s.canStartBackgroundGeneration); XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertThrowsError(try s.startImageGeneration(capability:.init(available:false,message:"Owned unavailable model")))
    XCTAssertNil(s.imageGenerationJob); XCTAssertFalse(s.aiBusy); XCTAssertFalse(s.showImagePlayground)
    XCTAssertEqual(s.document,before)
  }
  @MainActor func testBackgroundStartsFromMaskTargetWithoutPaintingIntoIt() async throws {
    let s = try store(); defer { s.cancelAIWork(); s.renderTask?.cancel() }
    let original = s.document, id = try XCTUnwrap(original.activeLayerID)
    s.selectMask(id); XCTAssertTrue(s.editingMask); XCTAssertTrue(s.canStartBackgroundGeneration)
    let job = try await begin(s)
    XCTAssertFalse(s.editingMask); XCTAssertEqual(job.intent, .background)
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
}
