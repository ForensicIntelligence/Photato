import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers
import XCTest

@testable import PhotoCraft

final class DocumentIOWorkflowTests: XCTestCase {
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
      Set(["public.png", "public.jpeg", "public.tiff", "com.adobe.photoshop-image"]).isSubset(
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
  func testUploadDimensionsRejectedBeforePixelDecodeAndRouteBudgets() throws {
    let header: [String: Any] = ["document": ["width": 100_000, "height": 100_000]]
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
  @MainActor private func request(
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
          headers: ["X-Photato-Revision": service.revision(doc.store)])
        XCTAssertEqual(
          result.0.statusCode, 200, String(decoding: result.1.prefix(300), as: UTF8.self))
        XCTAssertEqual(result.0.value(forHTTPHeaderField: "Content-Type"), format.mediaType)
        XCTAssertEqual(result.1, try DocumentIO.encode(desktop.store.document, format: format))
        if format == .native { XCTAssertEqual(try NativeArchive.decode(result.1), edited) }
      }
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
      XCTAssertTrue(doc.isDocumentEdited)
      doc.store.undo()
      XCTAssertEqual(doc.store.document, before)
      doc.store.redo()
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
          service, path: "/v1/documents/\(id)/file.\(format.rawValue)")
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
      doc.store.undo()
      XCTAssertEqual(doc.store.document, before)
      doc.store.redo()
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
