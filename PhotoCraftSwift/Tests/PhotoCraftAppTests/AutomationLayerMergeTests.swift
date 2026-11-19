import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class AutomationLayerMergeTests: XCTestCase {
  @MainActor func testStampHTTPDiscoveryValidationAndHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let original = try fixture("photoshop-source-rgb8")
      shared.store.session = EditorSession(document: original)
      let share = try XCTUnwrap(service.shares.first)
      let response = try await helper.request(service, path: "/v1/documents/\(share.id)")
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let state = try XCTUnwrap(body["layerMerge"] as? [String: Any])
      XCTAssertEqual(state["stampVisible"] as? Bool, true)
      let reject = try await helper.edit(service, shared, "layer.merge", ["operation": "stampVisible", "layerIDs": original.layers.map { $0.id.uuidString }])
      XCTAssertEqual(reject, 400)
      XCTAssertEqual(shared.store.document, original)
      let accept = try await helper.edit(service, shared, "layer.merge", ["operation": "stampVisible", "layerIDs": [String]()])
      XCTAssertEqual(accept, 200)
      let result = shared.store.document
      XCTAssertEqual(result.layers.count, original.layers.count + 1)
      XCTAssertEqual(result.layers.filter { $0.id != result.activeLayerID }, original.layers)
      XCTAssertEqual(shared.store.session.undoStack.last?.label, "Stamp Visible")
      let undo = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(shared.store.document, original)
    }
  }

  @MainActor func testClippingMaskHTTPDiscoveryMergeRejectAndUndo() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var original = try fixture("clipping-merge/chain-8-base")
      let base = try XCTUnwrap(original.layers.first { $0.name == "Clipping base" })
      let clipped = try XCTUnwrap(original.layers.first { $0.name == "Lower clip" })
      original.activeLayerID = base.id
      shared.store.session = EditorSession(document: original)
      try service.share(shared)
      let share = try XCTUnwrap(service.shares.first)
      let response = try await helper.request(service, path: "/v1/documents/\(share.id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertEqual((state["layerMerge"] as? [String:Any])?["clippingMask"] as? Bool, true)
      let invalid = try await helper.edit(service, shared, "layer.merge",
        ["operation": "clippingMask", "layerIDs": [clipped.id.uuidString]])
      XCTAssertEqual(invalid, 422)
      XCTAssertEqual(shared.store.document, original)
      let success = try await helper.edit(service, shared, "layer.merge",
        ["operation": "clippingMask", "layerIDs": [base.id.uuidString]])
      XCTAssertEqual(success, 200)
      XCTAssertEqual(shared.store.document.layers.map(\.name), ["Unrelated below", "Clipping base", "Unrelated above"])
      XCTAssertEqual(shared.store.document.activeLayerID, base.id)
      XCTAssertEqual(shared.store.session.undoStack.last?.label, "Merge Clipping Mask")
      let undo = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(shared.store.document, original)
    }
  }

  @MainActor func testInPlaceStampsThroughNativeHTTPRetainLayerIDsAndHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      for (name, operation, selectedName) in [
        ("ordinary-8-top-stamp", "stampDown", "Layer 1"),
        ("chain-8-active-base", "stampGroup", "Clipping base"),
      ] {
        var source = try fixture("context-stamp/\(name)")
        let selected = try XCTUnwrap(source.layers.first { $0.name == selectedName })
        source.activeLayerID = selected.id
        shared.store.session = EditorSession(document: source)
        shared.store.selectedLayerIDs = [selected.id]
        let share = try XCTUnwrap(service.shares.first)
        let response = try await helper.request(service, path: "/v1/documents/\(share.id)")
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
        XCTAssertEqual((state["layerMerge"] as? [String: Any])?[operation] as? Bool, true)
        let status = try await helper.edit(service, shared, "layer.merge",
          ["operation": operation, "layerIDs": [selected.id.uuidString]])
        XCTAssertEqual(status, 200)
        XCTAssertEqual(shared.store.document.layers.map(\.id), source.layers.map(\.id))
        XCTAssertEqual(shared.store.document.activeLayerID, selected.id)
        XCTAssertEqual(shared.store.session.undoStack.last?.label,
          operation == "stampDown" ? "Stamp Down" : "Stamp Group")
        let undo = try await helper.edit(service, shared, "history.undo")
        XCTAssertEqual(undo, 200)
        XCTAssertEqual(shared.store.document, source)
      }
    }
  }

  @MainActor func testScreenClippingThroughDesktopAndNativeHTTPMatchesPhotoshop() async throws {
    try await verifyClippedWorkflow(folder: "screen-clipping", cases: [
      ("chain-8-screen-both", .clippingMask, "clippingMask", "Clipping base"),
      ("chain-16-screen-stamp", .stampGroup, "stampGroup", "Clipping base"),
      ("chain-16-screen-down", .down, "down", "Lower clip"),
    ])
  }

  @MainActor func testAdjacentClipsThroughDesktopAndNativeHTTPMatchPhotoshop() async throws {
    try await verifyClippedWorkflow(folder: "adjacent-clips", cases: [
      ("chain-8-upper-merge-visible", .down, "down", "Upper clip"),
      ("chain-32-upper-stamp-visible", .stampDown, "stampDown", "Upper clip"),
    ])
  }

  @MainActor func testIndependentClippingThroughDesktopAndNativeHTTPMatchesPhotoshop() async throws {
    try await verifyClippedWorkflow(folder: "independent-clipping", referenceArchitecture: "arm", cases: [
      ("independent-8-screen-only", .clippingMask, "clippingMask", "Clipping base"),
      ("independent-16-screen-stamp", .stampGroup, "stampGroup", "Clipping base"),
      ("independent-16-screen-down", .down, "down", "Lower clip"),
    ])
    try await verifyClippedWorkflow(folder: "independent-clipping", cases: [
      ("independent-8-multiply-mask", .clippingMask, "clippingMask", "Clipping base"),
      ("independent-32-multiply-stamp-down", .stampDown, "stampDown", "Lower clip"),
    ])
  }

  @MainActor func testClippedBlendModesThroughDesktopAndNativeHTTPMatchPhotoshop() async throws {
    try await verifyClippedWorkflow(folder: "clipped-blend-modes", cases: [
      ("chain-8-clip-multiply", .clippingMask, "clippingMask", "Clipping base"),
      ("chain-16-clip-lighten", .clippingMask, "clippingMask", "Clipping base"),
      ("chain-32-clip-difference", .clippingMask, "clippingMask", "Clipping base"),
    ])
  }

  @MainActor func testClippedPixelMasksThroughDesktopAndNativeHTTPMatchPhotoshop() async throws {
    try await verifyClippedWorkflow(folder: "pixel-masked-clipping", cases: [
      ("mask-8-both-merge-mask", .clippingMask, "clippingMask", "Clipping base"),
      ("mask-16-density-merge-down", .down, "down", "Lower clip"),
      ("mask-32-offset-stamp-down", .stampDown, "stampDown", "Lower clip"),
      ("mask-32-density-stamp-mask", .stampGroup, "stampGroup", "Clipping base"),
    ], sourceName: { $0.replacingOccurrences(of: #"-((merge|stamp)-(mask|down))$"#,
      with: "", options: .regularExpression) })
  }

  @MainActor func testWideFeatherClippingThroughDesktopAndHTTPMatchesPhotoshopAndUndoes() async throws {
    try await verifyClippedWorkflow(folder: "feathered-clipping", cases: [
      ("wide250-merge-mask", .clippingMask, "clippingMask", "Reference Black"),
      ("wide1000-stamp-down", .stampDown, "stampDown", "Reference Mask"),
    ], requestTimeout: 90)
  }

  @MainActor func testClippedArithmeticModesThroughDesktopAndNativeHTTPMatchPhotoshop() async throws {
    try await verifyClippedWorkflow(folder: "clipped-arithmetic", cases: [
      ("clipped-arithmetic-8-partial-linearAdd-37-merge-mask", .clippingMask, "clippingMask", "Clipping base"),
      ("clipped-arithmetic-16-opaque-subtract-37-merge-mask", .clippingMask, "clippingMask", "Clipping base"),
      ("clipped-arithmetic-16-partial-divide-37-merge-mask", .clippingMask, "clippingMask", "Clipping base"),
      ("clipped-arithmetic-32-masked-linearAdd-79-stamp-mask", .stampGroup, "stampGroup", "Clipping base"),
      ("clipped-arithmetic-32-masked-subtract-79-merge-down", .down, "down", "Lower clip"),
      ("clipped-arithmetic-32-masked-divide-79-stamp-down", .stampDown, "stampDown", "Lower clip"),
    ])
  }

  @MainActor private func verifyClippedWorkflow(
    folder: String, referenceArchitecture: String? = nil, cases: [(String, LayerMergeOperation, String, String)],
    requestTimeout: TimeInterval = 5, sourceName: (String) -> String = { $0 }
  ) async throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      for (name, operation, command, selectedName) in cases {
        var source = try fixture("\(folder)/\(sourceName(name))")
        let selected = try XCTUnwrap(source.layers.first { $0.name == selectedName })
        source.activeLayerID = selected.id
        let reference = try fixture("\(folder)/\(referenceArchitecture ?? architecture)-\(name)-merged")
        let desktop = EditorStore(document: source)
        defer { desktop.renderTask?.cancel() }
        let isStamp = operation == .stampDown || operation == .stampGroup
        let contextual = isStamp ? desktop.contextualStamp(.stampSelected) : desktop.menuMergeOperation
        XCTAssertEqual(contextual, operation, name)
        XCTAssertTrue(desktop.canMerge(operation), name)
        desktop.merge(contextual)
        await desktop.geometryTask?.value
        XCTAssertNil(desktop.error)
        try samePixels(desktop.document, reference)
        let store = shared.store
        store.session = EditorSession(document: source)
        store.selectedLayerIDs = [selected.id]
        let status = try await helper.edit(service, shared, "layer.merge",
          ["operation": command, "layerIDs": [selected.id.uuidString]], timeout: requestTimeout)
        XCTAssertEqual(status, 200, name)
        XCTAssertEqual(store.document, desktop.document, name)
        XCTAssertEqual(store.session.undoStack.last?.label, operation.rawValue, name)
        let undo = try await helper.edit(service, shared, "history.undo", timeout: requestTimeout)
        XCTAssertEqual(undo, 200, name)
        XCTAssertEqual(store.document, source, name)
      }
    }
  }

  func fixture(_ name: String) throws -> CraftDocument {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    return try PSDCodec.read(
      Data(
        contentsOf: root.appendingPathComponent(
          "PhotoCraftImagingTests/Fixtures/layer-merge/" + name + ".psd")))
  }
  func samePixels(_ actual: CraftDocument, _ expected: CraftDocument) throws {
    XCTAssertEqual(actual.layers.count, expected.layers.count)
    XCTAssertEqual(try ColorManagement.space(for: actual), try ColorManagement.space(for: expected))
    if let embedded = expected.workingICC { XCTAssertEqual(actual.workingICC, embedded) }
    for (a, b) in zip(actual.layers, expected.layers) {
      XCTAssertEqual(a.name, b.name)
      XCTAssertEqual(a.x, b.x)
      XCTAssertEqual(a.y, b.y)
      guard case .raster(let x) = a.content, case .raster(let y) = b.content else {
        return XCTFail()
      }
      let encoding: SurfaceColorEncoding = actual.depth == .f32 ? .linearRGB : .sRGB
      if actual.depth == .f32, x.width == 256, x.height == 7, a.name == "Source", a.x == 0, a.y == 1
      {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
          .deletingLastPathComponent()
        #if arch(x86_64)
        let reference = "hdr-normal/intel-legacy-down.rgba"
        #else
        let reference = "original-profile-down-rgb32.rgba"
        #endif
        let raw = try Data(contentsOf: root.appendingPathComponent(
          "PhotoCraftImagingTests/Fixtures/layer-merge/" + reference))
        let output = try x.rgbaData(depth: .f32, colorEncoding: .linearRGB)
        XCTAssertEqual(output.count, raw.count)
        XCTAssertEqual(zip(output, raw).filter { $0 != $1 }.count, 0)
      }
      XCTAssertEqual(
        try x.rgbaData(depth: actual.depth, colorEncoding: encoding),
        try y.rgbaData(depth: expected.depth, colorEncoding: encoding))
    }
  }
  @MainActor func testEveryMergeDepthDesktopHTTPPhotoshopAndHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      for bits in [8, 16, 32] {
        for (name, operation) in [
          ("down", LayerMergeOperation.down), ("selected", .selected), ("visible", .visible),
        ] {
          let original = try fixture("photoshop-source-rgb\(bits)")
          #if arch(x86_64)
          let expectedName = bits == 32 ? "hdr-normal/intel-legacy-\(name)" : "photoshop-\(name)-rgb\(bits)"
          #else
          let expectedName = "photoshop-\(name)-rgb\(bits)"
          #endif
          let expected = try fixture(expectedName)
          let desktop = EditorStore(document: original)
          defer { desktop.renderTask?.cancel() }
          if operation == .selected { desktop.selectedLayerIDs = Set(original.layers.map(\.id)) }
          desktop.merge(operation)
          await desktop.geometryTask?.value
          XCTAssertNil(desktop.error)
          try samePixels(desktop.document, expected)
          let store = shared.store
          store.session = EditorSession(document: original)
          store.selectedLayerIDs = Set(original.activeLayerID.map { [$0] } ?? [])
          let ids =
            operation == .visible
            ? []
            : operation == .down
              ? [try XCTUnwrap(original.activeLayerID).uuidString]
              : original.layers.map { $0.id.uuidString }
          let status = try await helper.edit(
            service, shared, "layer.merge", ["operation": name, "layerIDs": ids])
          XCTAssertEqual(status, 200)
          let share = try XCTUnwrap(service.shares.first)
          let response = try await helper.request(service, path: "/v1/documents/\(share.id)")
          XCTAssertEqual(response.0.statusCode, 200)
          let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: response.1) as? [String: Any])
          let profile = try XCTUnwrap(state["workingProfile"] as? [String: Any])
          XCTAssertEqual(profile["embedded"] as? Bool, original.workingICC != nil)
          XCTAssertEqual(
            profile["sampleEncoding"] as? String, bits == 32 ? "linearRGB" : "profileRGB")
          XCTAssertEqual(
            (profile["iccSHA256"] as? String)?.count, original.workingICC == nil ? nil : 64)
          XCTAssertEqual(store.document, desktop.document)
          try samePixels(PSDCodec.read(PSDCodec.writeRasterLayers(store.document)), expected)
          XCTAssertEqual(
            store.selectedLayerIDs, Set(store.document.activeLayerID.map { [$0] } ?? []))
          XCTAssertEqual(store.session.undoStack.map(\.label), [operation.rawValue])
          XCTAssertTrue(shared.isDocumentEdited)
          let undo = try await helper.edit(service, shared, "history.undo")
          XCTAssertEqual(undo, 200)
          XCTAssertEqual(store.document, original)
          let redo = try await helper.edit(service, shared, "history.redo")
          XCTAssertEqual(redo, 200)
          XCTAssertEqual(store.document, desktop.document)
          await store.undo()
          store.renderTask?.cancel()
          XCTAssertEqual(store.document, original)
          shared.updateChangeCount(.changeCleared)
        }
      }
    }
  }
  @MainActor func testMergeRejectsInvalidStaleBusyContextAndOversizedRequestsAtomically()
    async throws
  {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let original = try fixture("photoshop-source-rgb8")
      let store = shared.store
      store.session = EditorSession(document: original)
      let id = try XCTUnwrap(original.activeLayerID).uuidString
      let valid: [String: Any] = ["operation": "down", "layerIDs": [id]]
      for bad: [String: Any] in [
        ["operation": "unknown", "layerIDs": [id]], ["operation": "down", "layerIDs": id],
        ["operation": "down", "layerIDs": [true]], ["operation": "down", "layerIDs": [id, id]],
        ["operation": "selected", "layerIDs": [id]], ["operation": "visible", "layerIDs": [id]],
      ] {
        let result = try await helper.edit(service, shared, "layer.merge", bad)
        XCTAssertEqual(result, 400)
      }
      let missing = try await helper.edit(
        service, shared, "layer.merge", ["operation": "down", "layerIDs": [UUID().uuidString]])
      XCTAssertEqual(missing, 404)
      let stale = try await helper.edit(service, shared, "layer.merge", valid, revision: "stale")
      XCTAssertEqual(stale, 409)
      store.geometryBusy = true
      let busy = try await helper.edit(service, shared, "layer.merge", valid)
      XCTAssertEqual(busy, 409)
      store.geometryBusy = false
      try store.selectEditingChannel(.red)
      let component = try await helper.edit(service, shared, "layer.merge", valid)
      XCTAssertEqual(component, 422)
      try store.selectEditingChannel(.composite)
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      for variant in 0..<2 {
        var changed = original
        if variant == 0 { changed.layers[1].locked = true }
        if variant == 1 { changed.layers[0].content = .fill(.white) }
        store.session = EditorSession(document: changed)
        let result = try await helper.edit(service, shared, "layer.merge", valid)
        XCTAssertEqual(result,422)
        XCTAssertEqual(store.document, changed)
        XCTAssertTrue(store.session.undoStack.isEmpty)
      }
    }
  }
}
