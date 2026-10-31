import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers
import XCTest

@testable import PhotoCraft

final class DocumentIOWorkflowTests: XCTestCase {
  @MainActor func testIndependentPSBUploadDownloadAndCapabilityMetadata() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/psb")
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, _ in
      defer { self.cleanup(service.controller) }
      service.setDocumentTransfersEnabled(true)
      let input = try Data(contentsOf: root.appendingPathComponent("rgb32-compression1.psb"))
      let uploaded = try await self.request(
        service, path: "/v1/documents/import", data: input, type: "application/x-photoshop")
      XCTAssertEqual(uploaded.0.statusCode, 201, String(decoding: uploaded.1, as: UTF8.self))
      let state = try self.object(uploaded.1)
      let id = try XCTUnwrap(state["id"] as? String)
      let doc = try XCTUnwrap(service.shares.first?.document)
      let before = doc.store.document
      let dirty = doc.isDocumentEdited
      let reply = try await self.request(service, path: "/v1/documents/\(id)/file.psb")
      XCTAssertEqual(reply.0.statusCode, 200)
      XCTAssertEqual(reply.0.value(forHTTPHeaderField: "Content-Type"), "application/x-photoshop")
      XCTAssertEqual(reply.1, try DocumentIO.encode(before, format: .psb))
      XCTAssertEqual(try PSDCodec.read(reply.1).layers.map(\.name), before.layers.map(\.name))
      XCTAssertEqual(doc.store.document, before)
      XCTAssertEqual(doc.isDocumentEdited, dirty)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let capabilities = AutomationService.documentTransferCapabilities
      let container = try XCTUnwrap(capabilities["photoshopContainers"] as? [String: Any])
      XCTAssertEqual(container["readVersions"] as? [Int], [1, 2])
      XCTAssertEqual(container["streamingLargeFiles"] as? Bool, true)
      XCTAssertEqual(container["maximumFileBytes"]as?Int,PSDCodec.maximumFileBytes)
      XCTAssertEqual(container["maximumDataBytes"]as?Int,PSDCodec.maximumInputBytes)
      let paging=try XCTUnwrap(container["pagedRGB"]as?[String:Any]);XCTAssertEqual(paging["apiHeapMaximumBytes"]as?Int,134_217_728)
      XCTAssertEqual(paging["rowPatchHeapReserveBytes"]as?Int,16*1024*1024)
      XCTAssertEqual(container["maximumDimension"] as? Int, Surface.maxDimension)
      let output = try XCTUnwrap(container["fileOutput"] as? [String: Any])
      XCTAssertEqual(output["boundedWrites"] as? Bool, true)
      XCTAssertEqual(output["maximumWriteBytes"] as? Int, 65536)
      XCTAssertEqual(output["rowBasedCompression"] as? Bool, true)
      XCTAssertEqual(output["checkedLengthBackpatching"] as? Bool, true)
      XCTAssertEqual(output["atomicReplacement"] as? Bool, true)
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let copy = folder.appendingPathComponent("api-equivalent.psb")
      try await doc.copyDocument(to: copy, format: .psb)
      XCTAssertEqual(try Data(contentsOf: copy), reply.1)
      let decoding = try XCTUnwrap(container["channelDecoding"] as? [String: Any])
      XCTAssertEqual(decoding["rowBased"] as? Bool, true)
      XCTAssertEqual(decoding["zipInputChunkBytes"] as? Int, 65536)
      let files = try XCTUnwrap(container["fileInput"] as? [String: Any])
      XCTAssertEqual(files["boundedReads"] as? Bool, true)
      XCTAssertEqual(files["readWindowBytes"] as? Int, PSDCodec.fileReadWindowBytes)
      XCTAssertEqual(files["maximumCacheBytes"] as? Int, PSDCodec.maximumFileCacheBytes)
      let inputURL = root.appendingPathComponent("rgb32-compression1.psb")
      let fromFile = try DocumentIO.read(inputURL)
      XCTAssertNil(fromFile.sourceICC, "This independent fixture is untagged.")
      XCTAssertEqual(before.profileIsUntagged, true)
      XCTAssertNil(try PSDCodec.read(reply.1).sourceICC, "Opening must not silently add a profile tag.")
      // Compare the actual native open policy boundary with API import, rather
      // than a raw decoder whose defaults intentionally bypass desktop policies.
      try service.controller.documentOpening.begin([inputURL], display: false)
      await service.controller.documentOpening.waitUntilIdle()
      let opened = try XCTUnwrap(service.controller.documents.compactMap { $0 as? CraftNSDocument }
        .first { $0.fileURL == inputURL })
      XCTAssertEqual(opened.store.document.profileIsUntagged, true)
      XCTAssertEqual(try DocumentIO.encode(opened.store.document, format: .psb), reply.1)
      XCTAssertEqual(fromFile.layers.count, before.layers.count)
      for (original, imported) in zip(fromFile.layers, before.layers) {
        XCTAssertEqual(original.content, imported.content, "Default opening preserves stored samples and group content.")
        XCTAssertEqual(original.nativeMode, imported.nativeMode)
      }
      XCTAssertEqual(try Data(contentsOf: inputURL), input)
      // A corrupt unused merged preview must still fail the shared API decoder.
      var corrupt = try Data(contentsOf: root.appendingPathComponent("rgb32-compression3.psb"))
      corrupt[corrupt.count - 1] ^= 1
      let rejected = try await self.request(
        service, path: "/v1/documents/import", data: corrupt, type: "application/x-photoshop")
      XCTAssertEqual(rejected.0.statusCode, 422)
      XCTAssertEqual(service.shares.count, 1)
      XCTAssertEqual(doc.store.document, before)
      XCTAssertEqual(doc.isDocumentEdited, dirty)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      XCTAssertTrue(DocumentIO.uploadTypes.contains("application/x-photoshop"))
    }
  }

  private final class DecoderGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var released = false
    var hasEntered: Bool {
      condition.lock()
      defer { condition.unlock() }
      return entered
    }
    func wait() {
      condition.lock()
      defer { condition.unlock() }
      entered = true
      while !released {
        if !condition.wait(until: Date().addingTimeInterval(5)) { break }
      }
    }
    func release() {
      condition.lock()
      defer { condition.unlock() }
      released = true
      condition.broadcast()
    }
  }
  private func fixture(depth: PixelDepth = .u8) throws -> CraftDocument {
    var doc = try CraftDocument(width: 4, height: 3, depth: depth, name: "Document transfer")
    var surface = try Surface(width: 4, height: 3, depth: depth)
    for y in 0..<3 {
      for x in 0..<4 {
        surface.setPixel(x: x, y: y, Pixel(Float(x) / 3, Float(y) / 2, 0.25, 1))
      }
    }
    doc.layers[0].content = .raster(surface)
    return doc
  }
  private func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  @MainActor private func cleanup(_ controller: CraftDocumentController) {
    for case let doc as CraftNSDocument in controller.documents {
      doc.updateChangeCount(.changeCleared)
      doc.close()
    }
  }
  @MainActor func testOpenPanelIncludesDeclaredRasterAndNativeFormats() throws {
    _ = NSApplication.shared
    let panel = NSOpenPanel()
    DocumentIO.configureOpenPanel(panel)
    XCTAssertTrue(panel.allowsMultipleSelection)
    XCTAssertTrue(panel.canChooseFiles)
    XCTAssertFalse(panel.canChooseDirectories)
    XCTAssertFalse(panel.allowsOtherFileTypes)
    let identifiers = Set(try XCTUnwrap(panel.allowedContentTypes).map(\.identifier))
    XCTAssertTrue(
      Set([
        "public.png", "public.jpeg", "public.tiff", "com.adobe.photoshop-image",
        "com.adobe.photoshop-large-image",
      ]).isSubset(
        of: identifiers))
    XCTAssertEqual(CraftNSDocument.readableTypes, DocumentIO.readableTypes)
  }
  @MainActor func testFileOpenEditNativeSaveReopenAndImportedIdentity() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("source.png")
    let data = try DocumentIO.encode(fixture(), format: .png)
    try data.write(to: url)
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    var opened: NSDocument?
    controller.openDocument(withContentsOf: url, display: false) { doc, existed, error in
      XCTAssertNil(error)
      XCTAssertFalse(existed)
      opened = doc
    }
    await controller.documentOpening.waitUntilIdle()
    let doc = try XCTUnwrap(opened as? CraftNSDocument)
    XCTAssertEqual(doc.fileURL, url)
    XCTAssertEqual(doc.persistenceFormat, .png)
    XCTAssertTrue(controller.document(for: url) === doc)
    let alias = directory.appendingPathComponent("alias.png")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: url)
    controller.openDocument(withContentsOf: alias, display: false) { second, existed, error in
      XCTAssertNil(error)
      XCTAssertTrue(existed)
      XCTAssertTrue(second === doc)
    }
    await controller.documentOpening.waitUntilIdle()
    XCTAssertEqual(controller.documents.count, 1)
    try doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id, "Edited"))
    let native = directory.appendingPathComponent("saved.photato")
    try await doc.persistDocument(to: native, format: .native, operation: .saveAsOperation)
    XCTAssertNil(doc.importedSourceURL)
    XCTAssertNil(controller.document(for: url))
    let reopened =
      try controller.makeDocument(withContentsOf: native, ofType: CraftNSDocument.nativeType)
      as! CraftNSDocument
    defer { reopened.store.renderTask?.cancel() }
    XCTAssertEqual(reopened.store.document, doc.store.document)
    XCTAssertEqual(reopened.fileURL, native)
    XCTAssertEqual(
      try Data(contentsOf: url), data, "Native save must not overwrite imported source.")
  }
  func testSharedDecodeEncodePreservesNativeAndHighDepthPSD() throws {
    for depth in PixelDepth.allCases {
      let doc = try fixture(depth: depth)
      let data = try DocumentIO.encode(doc, format: .native)
      XCTAssertEqual(try DocumentIO.decodeUpload(data, native: true, name: "ignored"), doc)
      let psd = try DocumentIO.encode(doc, format: .psd)
      let imported = try DocumentIO.decodeUpload(psd, native: false, name: "PSD")
      XCTAssertEqual(imported.depth, depth)
      XCTAssertEqual(
        try Renderer.composite(imported).rgbaData(depth: depth),
        try Renderer.composite(doc).rgbaData(depth: depth))
    }
    XCTAssertThrowsError(try DocumentIO.decodeUpload(Data(), native: false, name: "Empty"))
    XCTAssertThrowsError(
      try DocumentIO.decodeUpload(Data("not an image".utf8), native: false, name: "Invalid"))
    let data = try DocumentIO.encode(fixture(), format: .native)
    XCTAssertThrowsError(try NativeArchive.decode(data, rasterByteLimit: 1))
    XCTAssertThrowsError(try NativeArchive.decode(data, rasterByteLimit: -1))
  }
  func testUploadDimensionsRejectedBeforePixelDecodeAndRouteBudgets() async throws {
    let header: [String: Any] = ["document": ["width": 300_001, "height": 1]]
    let data = try PropertyListSerialization.data(
      fromPropertyList: header, format: .binary, options: 0)
    XCTAssertThrowsError(try DocumentIO.decodeUpload(data, native: true, name: "Huge")) { error in
      XCTAssertEqual((error as? AutomationFailure)?.status, 413)
    }
    XCTAssertNil(
      try AutomationRequest.parse(
        Data("POST /v1/documents/import HTTP/1.1\r\nContent-Length: 67108864\r\n\r\n".utf8)))
    for line in [
      "POST /v1/documents/import", "POST /v1/documents/id/commands",
      "POST /v1/documents/import/extra",
    ] {
      let n = line == "POST /v1/documents/import" ? 67_108_865 : 65_537
      XCTAssertThrowsError(
        try AutomationRequest.parse(Data("\(line) HTTP/1.1\r\nContent-Length: \(n)\r\n\r\n".utf8)))
    }
    XCTAssertTrue(
      String(decoding: AutomationResponse.json([:], status: 201).wire, as: UTF8.self).hasPrefix(
        "HTTP/1.1 201 Created"))
  }
  @MainActor func request(
    _ service: AutomationService, path: String, data: Data? = nil, type: String = "image/png",
    headers: [String: String] = [:], authenticate: Bool = true
  ) async throws -> (HTTPURLResponse, Data) {
    var request = URLRequest(
      url: try XCTUnwrap(URL(string: try XCTUnwrap(service.endpoint) + path)))
    request.timeoutInterval = 10
    if authenticate {
      request.setValue(
        "Bearer \(try XCTUnwrap(service.token))", forHTTPHeaderField: "Authorization")
    }
    if let data {
      request.httpMethod = "POST"
      request.httpBody = data
      request.setValue(type, forHTTPHeaderField: "Content-Type")
    }
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    let (body, response) = try await URLSession.shared.data(for: request)
    return (try XCTUnwrap(response as? HTTPURLResponse), body)
  }
  @MainActor func testHTTPUploadEditDownloadReopenMatchesDesktopAndPreservesHistory() async throws {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, _ in
      defer { self.cleanup(service.controller) }
      service.setDocumentTransfersEnabled(true)
      let input = try DocumentIO.encode(self.fixture(), format: .png)
      let reply = try await self.request(
        service, path: "/v1/documents/import", data: input,
        headers: ["X-Photato-Name": "Client image"])
      XCTAssertEqual(reply.0.statusCode, 201, String(decoding: reply.1, as: UTF8.self))
      let state = try self.object(reply.1)
      let id = try XCTUnwrap(state["id"] as? String)
      let doc = try XCTUnwrap(service.shares.first?.document)
      XCTAssertEqual(doc.store.document.name, "Client image")
      XCTAssertEqual(state["isModified"] as? Bool, true)
      XCTAssertNil(doc.fileURL)
      let before = doc.store.document
      let layerID = try XCTUnwrap(doc.store.document.activeLayerID)
      let edit = try await AutomationTests().request(
        service, path: "/v1/documents/\(id)/commands",
        body: [
          "command": "layer.rename", "revision": service.revision(doc.store),
          "parameters": ["layerID": layerID.uuidString, "name": "API edit"],
        ])
      XCTAssertEqual(edit.0.statusCode, 200)
      let edited = doc.store.document
      let desktop = CraftNSDocument(model: before)
      defer { desktop.store.renderTask?.cancel() }
      try desktop.store.executeEditorCommand(.renameLayer(layerID, "API edit"))
      XCTAssertEqual(edited, desktop.store.document)
      for format in DocumentIO.Format.allCases {
        let result = try await self.request(
          service, path: "/v1/documents/\(id)/file.\(format.rawValue)",
          headers: ["X-Photato-Revision": service.revision(doc.store)]
            .merging(format == .native ? ["X-Photato-Archive-Version": "11"] : [:]) { _, new in new
            })
        XCTAssertEqual(
          result.0.statusCode, 200, String(decoding: result.1.prefix(300), as: UTF8.self))
        XCTAssertEqual(result.0.value(forHTTPHeaderField: "Content-Type"), format.mediaType)
        XCTAssertEqual(result.1, try DocumentIO.encode(desktop.store.document, format: format))
        if format == .native { XCTAssertEqual(try NativeArchive.decode(result.1), edited) }
      }
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
      XCTAssertTrue(doc.isDocumentEdited)
      await doc.store.undo()
      XCTAssertEqual(doc.store.document, before)
      await doc.store.redo()
      XCTAssertEqual(doc.store.document, edited)
      XCTAssertEqual(service.shares.count, 1)
    }
  }
  @MainActor func testRGB32HTTPUploadRenameDownloadAndUndoRetainSampleBits() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(
        "PhotoCraftImagingTests/Fixtures/photoshop-depth-32.psd")
    let input = try Data(contentsOf: fixture)
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, _ in
      defer { self.cleanup(service.controller) }
      service.setDocumentTransfersEnabled(true)
      let reply = try await self.request(
        service, path: "/v1/documents/import", data: input, type: "image/vnd.adobe.photoshop")
      XCTAssertEqual(reply.0.statusCode, 201)
      let id = try XCTUnwrap(try self.object(reply.1)["id"] as? String)
      let doc = try XCTUnwrap(service.shares.first?.document)
      let before = doc.store.document
      let layerID = before.layers[0].id
      let edit = try await AutomationTests().request(
        service, path: "/v1/documents/\(id)/commands",
        body: [
          "command": "layer.rename", "revision": service.revision(doc.store),
          "parameters": ["layerID": layerID.uuidString, "name": "Preserved HDR"],
        ])
      XCTAssertEqual(edit.0.statusCode, 200)
      let desktop = CraftNSDocument(model: before)
      defer { desktop.store.renderTask?.cancel() }
      try desktop.store.executeEditorCommand(.renameLayer(layerID, "Preserved HDR"))
      for format in [DocumentIO.Format.native, .psd] {
        let response = try await self.request(
          service, path: "/v1/documents/\(id)/file.\(format.rawValue)",
          headers: format == .native ? ["X-Photato-Archive-Version": "11"] : [:])
        XCTAssertEqual(response.0.statusCode, 200)
        XCTAssertEqual(response.1, try DocumentIO.encode(desktop.store.document, format: format))
        let restored = try DocumentIO.decodeUpload(
          response.1, native: format == .native, name: "Reopened")
        for (a, b) in zip(before.layers, restored.layers) {
          guard case .raster(let a) = a.content, case .raster(let b) = b.content else {
            return XCTFail()
          }
          XCTAssertEqual(
            try a.rgbaData(depth: .f32, colorEncoding: .linearRGB),
            try b.rgbaData(depth: .f32, colorEncoding: .linearRGB))
        }
      }
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
      await doc.store.undo()
      XCTAssertEqual(doc.store.document, before)
      await doc.store.redo()
      XCTAssertEqual(doc.store.document, desktop.store.document)
    }
  }
  @MainActor func testTransferAuthenticationEnablementValidationBusyAndRevocation() async throws {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, doc in
      let input = try DocumentIO.encode(self.fixture(), format: .native)
      let route = "/v1/documents/import"
      let unauthorized = try await self.request(
        service, path: route, data: input, authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      let disabled = try await self.request(service, path: route, data: input)
      XCTAssertEqual(disabled.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let wrongType = try await self.request(
        service, path: route, data: input, type: "application/json")
      XCTAssertEqual(wrongType.0.statusCode, 415)
      let wrongName = try await self.request(
        service, path: route, data: input,
        headers: ["X-Photato-Name": String(repeating: "x", count: 257)])
      XCTAssertEqual(wrongName.0.statusCode, 400)
      let invalid = try await self.request(service, path: route, data: Data("bad".utf8))
      XCTAssertEqual(invalid.0.statusCode, 422)
      XCTAssertEqual(service.controller.documents.count, 1)
      try service.share(doc)
      let id = try XCTUnwrap(service.shares.first?.id)
      let path = "/v1/documents/\(id)/file.pcswift"
      let stale = try await self.request(
        service, path: path, headers: ["X-Photato-Revision": "stale"])
      XCTAssertEqual(stale.0.statusCode, 409)
      doc.store.geometryBusy = true
      let busy = try await self.request(service, path: path)
      XCTAssertEqual(busy.0.statusCode, 409)
      doc.store.geometryBusy = false
      service.documentTransferBusy = true
      let concurrent = try await self.request(service, path: path)
      XCTAssertEqual(concurrent.0.statusCode, 429)
      service.documentTransferBusy = false
      service.revoke(id)
      let revoked = try await self.request(service, path: path)
      XCTAssertEqual(revoked.0.statusCode, 404)
      service.stop()
      XCTAssertFalse(service.documentTransfersEnabled)
    }
  }
  @MainActor func testNativeAndOriginalPhotoshopUploadsKeepEditableStructure() async throws {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, _ in
      defer { self.cleanup(service.controller) }
      service.setDocumentTransfersEnabled(true)
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent()
      for bits in [8, 16, 32] {
        let url = root.appendingPathComponent(
          "PhotoCraftImagingTests/Fixtures/photoshop-solid-\(bits).psd")
        let data = try Data(contentsOf: url)
        let expected = try DocumentIO.read(url)
        let reply = try await self.request(
          service, path: "/v1/documents/import", data: data, type: "image/vnd.adobe.photoshop",
          headers: ["X-Photato-Name": "Original PSD"])
        XCTAssertEqual(reply.0.statusCode, 201, String(decoding: reply.1, as: UTF8.self))
        let state = try self.object(reply.1)
        let id = try XCTUnwrap(state["id"] as? String)
        let opened = try XCTUnwrap(service.shares.first { $0.id.uuidString == id }?.document)
        XCTAssertEqual(opened.store.document.depth, expected.depth)
        XCTAssertEqual(opened.store.document.layers.count, expected.layers.count)
        XCTAssertEqual(
          try Renderer.composite(opened.store.document).rgbaData(depth: expected.depth),
          try Renderer.composite(expected).rgbaData(depth: expected.depth))
        let native = try await self.request(service, path: "/v1/documents/\(id)/file.pcswift")
        XCTAssertEqual(native.0.statusCode, 200)
        XCTAssertEqual(try NativeArchive.decode(native.1), opened.store.document)
      }
      let original = try self.fixture(depth: .f32)
      let bytes = try NativeArchive.encode(original)
      let reply = try await self.request(
        service, path: "/v1/documents/import", data: bytes, type: DocumentIO.Format.native.mediaType
      )
      XCTAssertEqual(reply.0.statusCode, 201)
      let id = try XCTUnwrap(self.object(reply.1)["id"] as? String)
      let opened = try XCTUnwrap(service.shares.first { $0.id.uuidString == id }?.document)
      XCTAssertEqual(opened.store.document, original)
      let capabilities = try await self.request(service, path: "/v1/capabilities")
      let decoded = try self.object(capabilities.1)
      XCTAssertEqual(decoded["documentTransfersEnabled"] as? Bool, true)
      XCTAssertNotNil(decoded["documentTransfers"] as? [String: Any])
    }
  }
  @MainActor func testDisableAndReenableDuringDecodeCannotPublishStaleDocument() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let gate = DecoderGate()
    let model = try fixture()
    let service = AutomationService(
      controller: controller, pressedMouseButtons: { 0 },
      documentDecoder: { _, _, _ in
        gate.wait()
        return model
      })
    defer {
      gate.release()
      service.stop()
      cleanup(controller)
    }
    service.start()
    for _ in 0..<100 where !service.isRunning { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertTrue(service.isRunning)
    service.setDocumentTransfersEnabled(true)
    let request = AutomationRequest(
      method: "POST", path: "/v1/documents/import",
      headers: [
        "authorization": "Bearer \(try XCTUnwrap(service.token))", "content-type": "image/png",
      ], body: Data([1]))
    let pending = Task { await service.handle(request) }
    for _ in 0..<100 where !gate.hasEntered { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertTrue(gate.hasEntered)
    service.setDocumentTransfersEnabled(false)
    service.setDocumentTransfersEnabled(true)
    gate.release()
    let reply = await pending.value
    XCTAssertEqual(reply.status, 409)
    XCTAssertTrue(controller.documents.isEmpty)
    XCTAssertTrue(service.shares.isEmpty)
    XCTAssertFalse(service.documentTransferBusy)
  }
}

extension DocumentIOWorkflowTests {
  @MainActor func testChunkedNativeHTTPAndDesktopFileBytesAgreeAndCorruptionIsAtomic() async throws
  {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, _ in
      defer { self.cleanup(service.controller) }
      service.setDocumentTransfersEnabled(true)
      let model = try DocumentSaveWorkflowTests().fixture(depth: .f32)
      let bytes = try DocumentIO.encode(model, format: .native)
      XCTAssertTrue(bytes.starts(with: Data("PHOTATO\0".utf8)))
      let uploaded = try await self.request(
        service, path: "/v1/documents/import", data: bytes, type: "application/vnd.photato.document"
      )
      XCTAssertEqual(uploaded.0.statusCode, 201)
      let id = try XCTUnwrap(try self.object(uploaded.1)["id"] as? String)
      let document = try XCTUnwrap(service.shares.first?.document)
      let reply = try await self.request(
        service, path: "/v1/documents/\(id)/file.photato",
        headers: ["X-Photato-Archive-Version": "11"])
      XCTAssertEqual(reply.0.statusCode, 200)
      XCTAssertEqual(reply.1, bytes)
      let legacyBytes = try NativeArchive.encode(document.store.document)
      for ext in ["photato", "pcswift"] {
        let defaultOutput = try await self.request(service, path: "/v1/documents/\(id)/file.\(ext)")
        XCTAssertEqual(defaultOutput.0.statusCode, 200)
        XCTAssertEqual(defaultOutput.1, legacyBytes)
        let currentOutput = try await self.request(
          service, path: "/v1/documents/\(id)/file.\(ext)",
          headers: ["X-Photato-Archive-Version": "11"])
        XCTAssertEqual(currentOutput.0.statusCode, 200)
        XCTAssertEqual(currentOutput.1, bytes)
      }
      for version in ["9", "64", "invalid"] {
        let rejected = try await self.request(
          service, path: "/v1/documents/\(id)/file.photato",
          headers: ["X-Photato-Archive-Version": version])
        XCTAssertEqual(rejected.0.statusCode, 400)
      }
      let nonnative = try await self.request(
        service, path: "/v1/documents/\(id)/file.psd", headers: ["X-Photato-Archive-Version": "11"])
      XCTAssertEqual(nonnative.0.statusCode, 400)
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let target = folder.appendingPathComponent("copy.photato")
      try await document.copyDocument(to: target, format: .native)
      XCTAssertEqual(try Data(contentsOf: target), reply.1)
      XCTAssertEqual(try DocumentIO.read(target), document.store.document)
      let revision = service.revision(document.store)
      let shares = service.shares.count
      var invalid = bytes
      invalid[invalid.count - 1] ^= 1
      let rejected = try await self.request(
        service, path: "/v1/documents/import", data: invalid,
        type: "application/vnd.photato.document")
      XCTAssertEqual(rejected.0.statusCode, 422)
      XCTAssertEqual(service.shares.count, shares)
      XCTAssertEqual(service.revision(document.store), revision)
      let formats = try XCTUnwrap(
        AutomationService.documentTransferCapabilities["nativeArchives"] as? [String: Any])
      XCTAssertEqual(formats["writeVersion"] as? Int, 11)
      XCTAssertEqual(formats["readVersions"] as? [Int], Array(1...64))
      let legacy = try await self.request(
        service, path: "/v1/documents/import", data: NativeArchive.encode(model),
        type: "application/vnd.photato.document")
      XCTAssertEqual(legacy.0.statusCode, 201)
    }
  }
}
