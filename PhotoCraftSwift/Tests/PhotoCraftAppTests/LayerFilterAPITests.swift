import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LayerFilterAPITests: XCTestCase {
  @MainActor func testAllNineModesNativeHTTPStateAndSampleArchiveWithObservedViewSelectionAtEveryDepth() async throws {
    let h = AutomationTests(), fixture = LayerFilterWorkflowTests()
    try await h.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, doc in
      for depth in PixelDepth.allCases {
        let source = try fixture.fixture(depth), s = doc.store, native = EditorStore(document: source)
        defer { fixture.stop(native) }
        s.session = EditorSession(document: source)
        let selected = Set(source.layers.filter { ["Pixel A", "Nested pixels"].contains($0.name) }.map(\.id))
        s.selectedLayerIDs = selected; native.selectedLayerIDs = selected
        s.renderTask?.cancel(); await s.renderTask?.value
        native.renderTask?.cancel(); await native.renderTask?.value
        let revision = s.revision, bytes = try NativeArchive.encodeChunked(source)
        try service.share(doc)
        for mode in LayerFilterMode.allCases {
          var filter = LayerPanelFilter(); filter.mode = mode
          filter.name = "Pixel"; filter.kinds = [.pixel, .type]; filter.color = .red
          filter.smartKinds = [.embedded]; filter.blend = BlendMode.multiply.rawValue
          filter.attribute = .notVisible
          if mode == .artboard { filter.artboardID = source.layers.first { $0.group?.artboard != nil }!.id.uuidString.lowercased() }
          try native.setLayerFilter(filter)
          let code = try await h.edit(service, doc, LayerFilterAPI.command,
            ["operation": "configure", "filter": BrushAPI.json(filter)])
          XCTAssertEqual(code, 200, mode.rawValue)
          XCTAssertEqual(s.layerPanelFilter, native.layerPanelFilter)
          XCTAssertEqual(s.layersInPanel().map(\.id), native.layersInPanel().map(\.id))
          XCTAssertEqual(s.document, fixture.retainingViewSelection(source, s)); XCTAssertEqual(s.revision, revision)
          XCTAssertEqual(try NativeArchive.encodeChunked(s.document), try NativeArchive.encodeChunked(fixture.retainingViewSelection(source, s)))
          XCTAssertFalse(bytes.isEmpty)
          XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertTrue(s.session.redoStack.isEmpty)
          let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: s.layerFilterState))
          XCTAssertNoThrow(try BrushAPI.merge(value, schema: LayerFilterAPI.stateSchema))
        }
      }
    }
  }

  @MainActor func testPatchRetentionDisableEnableFindIsolateAndSelectAllUseNativePaths() async throws {
    let h = AutomationTests(), fixture = LayerFilterWorkflowTests()
    try await h.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, doc in
      let source = try fixture.fixture(), s = doc.store
      s.session = EditorSession(document: source); try service.share(doc)
      let original = service.revision(s)
      var code = try await h.edit(service, doc, LayerFilterAPI.command,
        ["operation": "configure", "filter": ["mode": "name", "name": "pixels", "color": 1]])
      XCTAssertEqual(code, 200); XCTAssertNotEqual(service.revision(s), original)
      let config = s.layerPanelFilter
      code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "disable"])
      XCTAssertEqual(code, 200); XCTAssertFalse(s.layerPanelFilter.enabled)
      XCTAssertEqual(s.layerPanelFilter.name, config.name); XCTAssertEqual(s.layerPanelFilter.color, config.color)
      code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "enable"])
      XCTAssertEqual(code, 200); XCTAssertEqual(s.layerPanelFilter, config)
      code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "selectAll"])
      XCTAssertEqual(code, 200)
      XCTAssertEqual(Set(s.document.layers.filter { s.selectedLayerIDs.contains($0.id) }.map(\.name)), ["Nested pixels", "Board pixels"])
      code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "isolate"])
      XCTAssertEqual(code, 200); XCTAssertTrue(s.layerFilterIsolated)
      XCTAssertEqual(Set(s.layersInPanel().map(\.id)), s.selectedLayerIDs)
      code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "find"])
      XCTAssertEqual(code, 200); XCTAssertEqual(s.layerPanelFilter.mode, .name)
      XCTAssertEqual(s.layerFilterFocusRequest, 1); XCTAssertEqual(s.layersTab, .layers)
      code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "reset"])
      XCTAssertEqual(code, 200); XCTAssertEqual(s.layerPanelFilter, LayerPanelFilter())
      XCTAssertEqual(s.document, fixture.retainingViewSelection(source, s)); XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }

  @MainActor func testInvalidMissingUnsupportedBusyStaleRevokedAndForeignParametersAreAtomic() async throws {
    let h = AutomationTests(), fixture = LayerFilterWorkflowTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try fixture.fixture(), s = doc.store
      s.session = EditorSession(document: source); try service.share(doc)
      let original = s.layerPanelFilter
      let invalid: [[String: Any]] = [
        [:], ["mode": "unknown"], ["typo": 1], ["enabled": 1], ["name": NSNull()],
        ["name": "bad\0name"], ["name": String(repeating: "🙂", count: 33_000)],
        ["color": 999], ["color": true], ["kinds": ["pixel", "pixel"]],
        ["kinds": ["unknown"]], ["smartKinds": ["embedded", "embedded"]],
        ["attribute": "unknown"], ["blend": "unknown"], ["artboardID": "bad"],
      ]
      for patch in invalid {
        let code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "configure", "filter": patch])
        XCTAssertEqual(code, 400, "\(patch)"); XCTAssertEqual(s.layerPanelFilter, original)
      }
      let missing = try await h.edit(service, doc, LayerFilterAPI.command,
        ["operation": "configure", "filter": ["artboardID": UUID().uuidString]])
      XCTAssertEqual(missing, 404)
      let library = try await h.edit(service, doc, LayerFilterAPI.command,
        ["operation": "configure", "filter": ["mode": "smartObject", "smartKinds": ["library"]]])
      XCTAssertEqual(library, 422)
      let foreign = try await h.edit(service, doc, LayerFilterAPI.command,
        ["operation": "reset", "filter": ["mode": "kind"]])
      XCTAssertEqual(foreign, 400)
      let stale = try await h.edit(service, doc, LayerFilterAPI.command,
        ["operation": "find"], revision: "stale")
      XCTAssertEqual(stale, 409)
      s.beginLayerProtection()
      let busy = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "find"])
      XCTAssertEqual(busy, 409); s.layerProtectionDraft = nil
      let id = try XCTUnwrap(service.shares.first?.id), revision = service.revision(s)
      service.revoke(id)
      let revoked = try await h.request(service, path: "/v1/documents/\(id)/commands",
        body: ["command": LayerFilterAPI.command, "revision": revision, "parameters": ["operation": "find"]])
      XCTAssertEqual(revoked.0.statusCode, 404)
      XCTAssertEqual(s.layerPanelFilter, original); XCTAssertEqual(s.document, fixture.retainingViewSelection(source, s))
      XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertEqual(s.layerFilterFocusRequest, 0)
    }
  }

  @MainActor func testSelectionAndDisclosureInvalidateSharedRevisionWithoutHistoryOrRecording() async throws {
    let h = AutomationTests(), fixture = LayerFilterWorkflowTests()
    try await h.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, doc in
      let source = try fixture.fixture(), s = doc.store
      s.session = EditorSession(document: source); try service.share(doc)
      let id = source.layers.first { $0.name == "Pixel A" }!.id
      try s.session.execute(.opacity(id, 0.5)); try s.session.undo()
      XCTAssertEqual(s.session.redoStack.count, 1)
      try s.session.startActionRecording(name: "View filtering")
      var revision = service.revision(s)
      s.selectedLayerIDs = Set(source.layers.prefix(2).map(\.id))
      XCTAssertNotEqual(service.revision(s), revision)
      let stale = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "isolate"], revision: revision)
      XCTAssertEqual(stale, 409)
      revision = service.revision(s)
      s.toggleGroupDisclosure(source.layers[1].id)
      XCTAssertNotEqual(service.revision(s), revision)
      let code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "isolate"])
      XCTAssertEqual(code, 200)
      XCTAssertEqual(s.session.redoStack.count, 1); XCTAssertTrue(s.session.undoStack.isEmpty)
      XCTAssertEqual(s.session.actionRecording?.snapshot.steps.count, 0)
      try s.session.redo(); XCTAssertEqual(s.document.layers.first { $0.id == id }?.opacity, 0.5)
    }
  }

  @MainActor func testDiscoveryStateSchemaAndNoSerializationVersionOrAdobeEndpointChange() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      try service.share(doc)
      // Existing source-reference APIs cap revision strings at256characters.
      for brush in [false, true] { for evaluation in [false, true] {
        let revision = service.revision(doc.store, includeBrush: brush, includeFilterEvaluation: evaluation)
        XCTAssertEqual(revision.utf8.count, 64)
        XCTAssertTrue(revision.allSatisfy { $0.isHexDigit })
      } }
      let caps = try await h.request(service, path: "/v1/capabilities")
      let capabilities = try XCTUnwrap(JSONSerialization.jsonObject(with: caps.1) as? [String: Any])
      XCTAssertNotNil(capabilities["layerFilter"])
      let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await h.request(service, path: "/v1/documents/\(id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertNotNil(state["layerFilter"])
      let value = try JSONDecoder().decode(AutomationValue.self,
        from: JSONSerialization.data(withJSONObject: try XCTUnwrap(state["layerFilter"])))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: LayerFilterAPI.stateSchema))
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
      XCTAssertEqual(AutomationTests.expectedCommandCount, 248)
      let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == LayerFilterAPI.command })
      XCTAssertEqual(definition.optionalParameters, ["filter"])
      XCTAssertEqual(ActionLibraryFile.maximumVersion, 48)
      XCTAssertTrue(JSONSerialization.isValidJSONObject(LayerFilterAPI.capabilities))
    }
  }
}
