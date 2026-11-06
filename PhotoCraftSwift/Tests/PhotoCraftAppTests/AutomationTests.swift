import AppKit
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class AutomationTests: XCTestCase {
  static let expectedCommandCount = 250
  func parse(_ text: String) throws -> AutomationRequest? {
    try AutomationRequest.parse(Data(text.utf8))
  }

  func testFramingWaitsForCompleteHeadersAndBody() throws {
    XCTAssertNil(try parse("GET / HTTP/1.1\r\nHost:"))
    XCTAssertNil(try parse("POST /v1/documents/x/commands HTTP/1.1\r\nContent-Length: 2\r\n\r\n{"))
    let result = try XCTUnwrap(
      parse("POST /v1/documents/x/commands HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}"))
    XCTAssertEqual(result.method, "POST")
    XCTAssertEqual(result.body, Data("{}".utf8))
  }
  func testAmbiguousAndUnboundedHTTPIsRejected() throws {
    for headers in [
      "Content-Length: 0\r\ncontent-length: 0", "Content-Length: -1", "Content-Length: 1x",
      "Content-Length: 65537", "Transfer-Encoding: chunked", "Expect: 100-continue",
      "Host: one\r\nHost: two", " Host: one", "Bad Header: value",
    ] { XCTAssertThrowsError(try parse("POST / HTTP/1.1\r\n\(headers)\r\n\r\n"), headers) }
    XCTAssertThrowsError(try parse(String(repeating: "x", count: 16_385)))
    XCTAssertThrowsError(try parse("GET / HTTP/1.1\r\nHost: test\r\n\r\nextra"))
    XCTAssertThrowsError(try parse("GET / HTTP/1.1\r\nContent-Length: 1\r\n\r\nx"))
    for path in ["http://evil/", "/%2e%2e", "/?token=x", "/#token", "/\\"] {
      XCTAssertThrowsError(try parse("GET \(path) HTTP/1.1\r\nHost: test\r\n\r\n"))
    }
  }
  func testResponseNeverCachesOrAllowsFraming() {
    let response = String(decoding: AutomationResponse.json(["ok": true]).wire, as: UTF8.self)
    XCTAssertTrue(response.contains("Cache-Control: no-store"))
    XCTAssertTrue(response.contains("frame-ancestors 'none'"))
    XCTAssertTrue(response.contains("Connection: close"))
    XCTAssertFalse(response.contains("Access-Control-Allow-Origin"))
  }

  @MainActor func withService(
    actions: ActionLibrary? = nil, brushes: BrushLibrary? = nil, skies:SkyLibrary? = nil, shapes:ShapeLibrary? = nil,
    pressedMouseButtons: @escaping @MainActor () -> Int = { NSEvent.pressedMouseButtons },
    resourceTransport: any AdobeResourceTransport = NativeAdobeResourceTransport(),
    foregroundDetector: any ForegroundDetecting = VisionForegroundDetector(),
    documentDecoder: @escaping @Sendable (Data, Bool, String) throws -> CraftDocument = {
      try DocumentIO.decodeUpload($0, native: $1, name: $2)
    },
    prepareHistory: @escaping HistoryPreparation = NativeHistoryNavigation.prepare,
    recoveryPreferences: RecoveryPreferencesStore? = nil,
    recoveryIndex: RecoveryIndexStore? = nil,
    applicationTerminator: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
    _ body: @MainActor (AutomationService, CraftNSDocument) async throws -> Void
  ) async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(
      workspaces: WorkspaceLibrary(), recoveryPreferences: recoveryPreferences, recoveryIndex: recoveryIndex)
    let document = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 4, height: 3, background: .clear), actions: actions, brushes: brushes, skies:skies, shapes:shapes,
      prepareHistory: prepareHistory)
    controller.addDocument(document)
    let service = AutomationService(
      controller: controller, pressedMouseButtons: pressedMouseButtons,
      resourceTransport: resourceTransport, foregroundDetector: foregroundDetector, documentDecoder: documentDecoder,
      applicationTerminator: applicationTerminator)
    defer {
      service.stop()
      document.store.renderTask?.cancel()
      controller.removeDocument(document)
    }
    service.start()
    for _ in 0..<100 where !service.isRunning { try await Task.sleep(for: .milliseconds(20)) }
    guard service.isRunning else {
      XCTFail("Loopback listener failed: \(service.message)")
      return
    }
    try await body(service, document)
  }
  @MainActor func request(
    _ service: AutomationService, path: String, body: [String: Any]? = nil,
    headers: [String: String] = [:], authenticate: Bool = true
  ) async throws -> (HTTPURLResponse, Data) {
    var request = URLRequest(
      url: try XCTUnwrap(URL(string: try XCTUnwrap(service.endpoint) + path)))
    request.timeoutInterval = 5
    if authenticate {
      request.setValue("Bearer " + (service.token ?? ""), forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.httpMethod = "POST"
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    let (data, response) = try await URLSession.shared.data(for: request)
    return (try XCTUnwrap(response as? HTTPURLResponse), data)
  }
  @MainActor func edit(
    _ service: AutomationService, _ document: CraftNSDocument, _ name: String,
    _ parameters: [String: Any] = [:], revision: String? = nil
  ) async throws -> Int {
    let id = try XCTUnwrap(service.shares.first?.id)
    let response = try await request(
      service, path: "/v1/documents/\(id)/commands",
      body: [
        "command": name, "revision": revision ?? service.revision(document.store),
        "parameters": parameters,
      ]
    )
    if response.0.statusCode >= 400 {
      // Keep server reasons for failures: a status alone cannot distinguish stale and busy 409s.
      // These responses contain error messages only, never the bearer token or request headers.
      let store = document.store
      let flags: [String: Bool] = [
        "geometry": store.geometryBusy, "ai": store.aiBusy, "draft": store.hasToneDraft,
        "transform": store.transformDraft != nil, "numeric": store.numericEditor != nil,
        "name": store.layerNameDraft != nil, "coalescing": store.coalescingChanges,
        "path": store.pathGesture != nil, "geometrySheet": store.geometrySheet != nil,
        "feather": store.showFeatherSelection, "patternName": store.patternNameDraft != nil,
        "gradientName": store.gradientNameDraft != nil, "showAI": store.showAI,
        "playground": store.showImagePlayground, "error": store.error != nil,
        "sheet": document.windowForSheet?.attachedSheet != nil, "modal": NSApp?.modalWindow != nil,
        "pointer": NSEvent.pressedMouseButtons != 0,
      ]
      print("API guard flags after response: \(flags.filter { $0.value }.keys.sorted())")
      print(
        "API \(name): HTTP \(response.0.statusCode) \(String(decoding: response.1, as: UTF8.self))")
    }
    return response.0.statusCode
  }

  @MainActor func testRealHTTPAuthenticationOriginHostAndCatalogue() async throws {
    try await withService { service, _ in
      let publicPage = try await request(service, path: "/", authenticate: false)
      XCTAssertEqual(publicPage.0.statusCode, 200)
      XCTAssertFalse(
        String(decoding: publicPage.1, as: UTF8.self).contains(service.token ?? "missing"))
      let unauthorized = try await request(service, path: "/v1/documents", authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      let crossOrigin = try await request(
        service, path: "/v1/documents", headers: ["Origin": "https://example.com"])
      XCTAssertEqual(crossOrigin.0.statusCode, 403)
      let badHost = try await request(
        service, path: "/v1/documents", headers: ["Host": "evil.test"])
      XCTAssertEqual(badHost.0.statusCode, 403)
      let nullOrigin = try await request(
        service, path: "/v1/documents", headers: ["Origin": "null"])
      XCTAssertEqual(nullOrigin.0.statusCode, 403)
      let sameOrigin = try await request(
        service, path: "/v1/capabilities", headers: ["Origin": try XCTUnwrap(service.endpoint)])
      XCTAssertEqual(sameOrigin.0.statusCode, 200)
      let catalogue = try XCTUnwrap(
        JSONSerialization.jsonObject(with: sameOrigin.1) as? [String: Any])
      XCTAssertEqual((catalogue["commands"] as? [Any])?.count, AutomationTests.expectedCommandCount)
      XCTAssertEqual((catalogue["menuInventory"] as? [Any])?.count, 808)
      XCTAssertFalse(String(decoding: sameOrigin.1, as: UTF8.self).contains("Support Development"))
      let empty = try await request(service, path: "/v1/documents")
      XCTAssertEqual(String(decoding: empty.1, as: UTF8.self), "{\"documents\":[]}")
    }
  }
  @MainActor func testAllTenCommandsUseNativeHistoryAndDirtyState() async throws {
    try await withService { service, document in
      try service.share(document)
      let store = document.store
      let original = store.document
      let share = try XCTUnwrap(service.shares.first)
      XCTAssertEqual(service.state(share,document:document)["windowTitle"] as? String, "Photato - " + (document.displayName ?? original.name))
      let id = try XCTUnwrap(original.activeLayerID).uuidString
      let commands: [(String, [String: Any])] = [
        ("layer.rename", ["layerID": id, "name": "Browser layer"]),
        ("layer.opacity", ["layerID": id, "opacity": 0.5]),
        ("layer.visibility", ["layerID": id, "visible": false]),
        ("layer.move", ["layerID": id, "x": 1, "y": 1]),
        ("selection.rectangle", ["x": 1, "y": 1, "width": 2, "height": 1]),
        ("layer.fill", ["layerID": id, "r": 1, "g": 0.5, "b": 0, "a": 1]),
        ("selection.clear", [:]), ("layer.new", ["name": "New from browser"]),
      ]
      var expected = EditorSession(document: original)
      for (name, parameters) in commands {
        let data = try JSONSerialization.data(withJSONObject: [
          "command": name, "revision": "unused", "parameters": parameters,
        ])
        let command = try XCTUnwrap(
          AutomationCommand(data: data).nativeCommand(document: expected.document))
        try expected.execute(command)
        let status = try await edit(service, document, name, parameters)
        XCTAssertEqual(status, 200, name)
        if name != "layer.new" { XCTAssertEqual(store.document, expected.document, name) }
      }
      XCTAssertEqual(store.document.layers.count, 2)
      XCTAssertEqual(store.activeLayer?.name, "New from browser")
      XCTAssertEqual(store.session.undoStack.count, 8)
      XCTAssertTrue(document.isDocumentEdited)
      let result = store.document
      for _ in 0..<8 {
        let status = try await edit(service, document, "history.undo")
        XCTAssertEqual(status, 200)
      }
      XCTAssertEqual(store.document, original)
      XCTAssertFalse(document.isDocumentEdited)
      for _ in 0..<8 { _ = try await edit(service, document, "history.redo") }
      XCTAssertEqual(store.document, result)
      XCTAssertTrue(document.isDocumentEdited)
      await store.undo()
      XCTAssertEqual(store.document.layers.count, 1, "Desktop Undo sees the API edit")
    }
  }
  @MainActor func testStaleInvalidBusyAndLockedEditsAreAtomic() async throws {
    try await withService { service, document in
      try service.share(document)
      let store = document.store
      let id = try XCTUnwrap(document.store.document.activeLayerID)
      let revision = service.revision(store)
      store.perform(.renameLayer(id, "Desktop edit"))
      let original = store.document
      let history = store.session.undoStack.count
      let stale = try await edit(
        service, document, "layer.rename", ["layerID": id.uuidString, "name": "Stale"],
        revision: revision)
      XCTAssertEqual(stale, 409)
      for parameters: [String: Any] in [
        ["layerID": id.uuidString, "opacity": 2], ["layerID": id.uuidString, "opacity": true],
        ["layerID": id.uuidString, "opacity": 0.4, "extra": 1],
        ["layerID": "invalid", "opacity": 0.4],
      ] {
        let status = try await edit(service, document, "layer.opacity", parameters)
        XCTAssertTrue([400, 404].contains(status))
      }
      store.coalesce(true)
      let busy = try await edit(
        service, document, "layer.rename", ["layerID": id.uuidString, "name": "Interrupted"])
      XCTAssertEqual(busy, 409)
      store.coalesce(false)
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(store.session.undoStack.count, history)
      store.perform(.lock(id, true))
      let locked = store.document
      let status = try await edit(
        service, document, "layer.fill", ["layerID": id.uuidString, "r": 1, "g": 0, "b": 0, "a": 1])
      XCTAssertEqual(status, 422)
      XCTAssertEqual(store.document, locked)
      XCTAssertNil(store.error, "API failures must not open desktop alerts")
    }
  }
  @MainActor func testSharesRevokeOnCloseReloadAndStopAndTokensRotate() async throws {
    try await withService { service, document in
      try service.share(document)
      let first = try XCTUnwrap(service.shares.first?.id)
      service.revoke(first)
      let revoked = try await request(service, path: "/v1/documents/\(first)")
      XCTAssertEqual(revoked.0.statusCode, 404)
      try service.share(document)
      document.store.layerPanelGeneration = UUID()
      service.prune()
      XCTAssertTrue(service.shares.isEmpty)
      try service.share(document)
      service.controller.removeDocument(document)
      service.prune()
      XCTAssertTrue(service.shares.isEmpty)
      service.controller.addDocument(document)
      try service.share(document)
      let oldToken = service.token
      service.stop()
      XCTAssertNil(service.endpoint)
      XCTAssertNil(service.token)
      XCTAssertTrue(service.shares.isEmpty)
      service.start()
      for _ in 0..<100 where !service.isRunning { try await Task.sleep(for: .milliseconds(20)) }
      XCTAssertTrue(service.isRunning)
      XCTAssertTrue(service.token != oldToken, "Restart must rotate the secret")
      let oldAuth = try await request(
        service, path: "/v1/documents", headers: ["Authorization": "Bearer " + (oldToken ?? "")])
      XCTAssertEqual(oldAuth.0.statusCode, 401)
    }
  }
  @MainActor func testPreviewIsNativePNGAndUnknownDocumentsStayPrivate() async throws {
    try await withService { service, document in
      let id = try XCTUnwrap(document.store.document.activeLayerID)
      document.store.perform(.fill(id, Pixel(1, 0, 0, 1)))
      try service.share(document)
      let share = try XCTUnwrap(service.shares.first?.id)
      let preview = try await request(service, path: "/v1/documents/\(share)/preview.png")
      XCTAssertEqual(preview.0.statusCode, 200)
      XCTAssertEqual(preview.0.value(forHTTPHeaderField: "Content-Type"), "image/png")
      let source = try XCTUnwrap(CGImageSourceCreateWithData(preview.1 as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      XCTAssertEqual(image.width, 4)
      XCTAssertEqual(image.height, 3)
      XCTAssertEqual(preview.1, try AutomationService.png(document.store.document))
      let unknown = try await request(service, path: "/v1/documents/\(UUID())")
      XCTAssertEqual(unknown.0.statusCode, 404)
      let file = try await request(service, path: "/v1/files")
      XCTAssertEqual(file.0.statusCode, 404)
    }
  }
  @MainActor func testNoOpDoesNotAddUndoAndUnknownCommandCannotDispatchMenus() async throws {
    try await withService { service, document in
      try service.share(document)
      let store = document.store
      let revision = service.revision(document.store)
      let id = try XCTUnwrap(store.document.activeLayerID).uuidString
      let noOp = try await edit(service, document, "layer.opacity", ["layerID": id, "opacity": 1])
      XCTAssertEqual(noOp, 200)
      XCTAssertEqual(service.revision(store), revision)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      let unknown = try await edit(service, document, "File > Save", [:])
      XCTAssertEqual(unknown, 422)
      XCTAssertFalse(document.isDocumentEdited)
    }
  }
  @MainActor func testLimitsAndMenuEntryAreExplicitProductAdditions() throws {
    _ = NSApplication.shared
    var oversized = try CraftNSDocument.blankModel(width: 2049, height: 2048, background: .clear)
    XCTAssertNoThrow(try AutomationService.checkLimits(oversized), "Logical area no longer determines API resident-data admission")
    for i in 0..<LayerLimits.maximumLayers { oversized.layers.append(Layer(name: "Limit \(i)", content: .raster(try Surface(width: 1, height: 1)))) }
    XCTAssertThrowsError(try AutomationService.checkLimits(oversized))
    let app = AppDelegate()
    XCTAssertFalse(app.automation.isRunning)
    XCTAssertNil(app.automation.token)
    let item = NSMenuItem(
      title: "Photato Automation API…", action: #selector(AppDelegate.showAutomation),
      keyEquivalent: "")
    XCTAssertTrue(app.validateMenuItem(item))
    XCTAssertEqual(
      PhotoshopMenuCatalog.menus.last?.children?.last?.title, "Photato Automation API…")
    XCTAssertEqual(PhotoshopMenuCatalog.menus.last?.children?.last?.key, "")
  }
  @MainActor func testHistoryRestoresDocumentsAboveFormerAPILayerLimit() async throws {
    try await withService { service, document in
      var history = EditorSession(document: document.store.document)
      for index in 0..<64 {
        try history.execute(.newPixelLayer(NewPixelLayerOptions(name: "Layer \(index)")))
      }
      try history.execute(.deleteLayer(try XCTUnwrap(history.document.activeLayerID)))
      document.store.session = history
      document.store.render()
      try service.share(document)
      let before = document.store.document
      let undo = try await edit(service, document, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(document.store.document.layers.count, before.layers.count + 1)
      document.store.session = history
      try document.store.session.undo()
      try document.store.session.undo()
      document.store.render()
      let beforeRedo = document.store.document
      let redo = try await edit(service, document, "history.redo")
      XCTAssertEqual(redo, 200)
      XCTAssertEqual(document.store.document.layers.count, beforeRedo.layers.count + 1)
    }
  }
  @MainActor func testCompetingClientsCannotBothCommitTheSameRevision() async throws {
    try await withService { service, document in
      try service.share(document)
      let revision = service.revision(document.store)
      let id = try XCTUnwrap(document.store.document.activeLayerID).uuidString
      let first = Task { @MainActor in
        try await self.edit(
          service, document, "layer.rename", ["layerID": id, "name": "First"], revision: revision)
      }
      let second = Task { @MainActor in
        try await self.edit(
          service, document, "layer.rename", ["layerID": id, "name": "Second"], revision: revision)
      }
      let statuses = try await [first.value, second.value]
      XCTAssertEqual(statuses.sorted(), [200, 409])
      XCTAssertEqual(document.store.session.undoStack.count, 1)
    }
  }
  @MainActor func testDesktopModalStatesAndMediaTypeRejectCommands() async throws {
    try await withService { service, document in
      try service.share(document)
      let store = document.store
      let parameters: [String: Any] = [
        "layerID": try XCTUnwrap(store.document.activeLayerID).uuidString, "name": "Blocked",
      ]
      for flag in [
        \EditorStore.geometryBusy, \.aiBusy, \.showAI, \.showImagePlayground,
        \.showFeatherSelection,
      ] {
        store[keyPath: flag] = true
        let status = try await edit(service, document, "layer.rename", parameters)
        XCTAssertEqual(status, 409)
        store[keyPath: flag] = false
      }
      let share = try XCTUnwrap(service.shares.first?.id)
      let response = try await request(
        service, path: "/v1/documents/\(share)/commands",
        body: [
          "command": "layer.rename", "parameters": parameters, "revision": service.revision(store),
        ], headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(response.0.statusCode, 415)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertFalse(document.isDocumentEdited)
    }
  }
  func testParameterValidationAndMachineSchemas() throws {
    let document = try CraftDocument(width: 4, height: 3)
    for (name, parameters) in [
      ("selection.rectangle", ["x": 0.5, "y": 0, "width": 1, "height": 1]),
      ("selection.rectangle", ["x": 3, "y": 0, "width": 2, "height": 1]),
      ("selection.rectangle", ["x": -1, "y": 0, "width": 1, "height": 1]),
    ] {
      let data = try JSONSerialization.data(withJSONObject: [
        "command": name, "parameters": parameters, "revision": "test",
      ])
      XCTAssertThrowsError(try AutomationCommand(data: data).nativeCommand(document: document))
    }
    XCTAssertEqual(Set(AutomationCommand.definitions.map(\.name)).count, AutomationTests.expectedCommandCount)
    for definition in AutomationCommand.definitions {
      XCTAssertTrue(JSONSerialization.isValidJSONObject(definition.schema))
      XCTAssertEqual(definition.schema["additionalProperties"] as? Bool, false)
    }
  }
}
