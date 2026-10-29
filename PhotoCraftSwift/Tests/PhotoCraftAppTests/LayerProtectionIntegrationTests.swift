import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest
@testable import PhotoCraft

final class LayerProtectionIntegrationTests: XCTestCase {
  @MainActor func testNativeCheckboxAvailabilityOnPresentation() throws {
    _ = NSApplication.shared
    for protection: LayerProtection in [.fullyLocked, [.transparency, .image], []] {
      var model = try CraftDocument(width: 2, height: 2)
      model.layers[0].protection = protection
      let store = EditorStore(document: model)
      defer { store.renderTask?.cancel() }
      store.beginLayerProtection()
      let draft = try XCTUnwrap(store.layerProtectionDraft)
      let host = NSHostingView(rootView: LayerProtectionSheet(store: store, draft: draft))
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 310, height: 220),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { window.contentView = nil; window.close() }
      window.layoutIfNeeded()
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      host.layoutSubtreeIfNeeded()
      func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
      }
      let controls = Dictionary(uniqueKeysWithValues: buttons(host).map { ($0.title, $0) })
      for title in ["Transparency", "Image", "Position", "Prevent auto-nest", "All"] {
        let button = try XCTUnwrap(controls[title])
        let enabled = title == "All" || (!protection.fullyLocks
          && !(title == "Transparency" && protection.contains(.image)))
        XCTAssertEqual(button.isEnabled, enabled, "Initial \(title), flags \(protection.rawValue)")
      }
      XCTAssertEqual(store.document, model)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testDesktopHTTPHistoryBusyAndState() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let original = shared.store.document
      let id = original.layers[0].id
      let oldRevision = service.revision(shared.store)
      let desktop = EditorStore(document: original)
      defer { desktop.renderTask?.cancel() }
      desktop.beginLayerProtection()
      let draft = try XCTUnwrap(desktop.layerProtectionDraft)
      draft.set(.image, enabled: true)
      desktop.commitLayerProtection(draft)
      XCTAssertNil(desktop.error)
      let status = try await helper.edit(service, shared, "layer.protection",
        ["layerIDs": [id.uuidString], "protection": ["transparency", "composite"]])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(shared.store.document, desktop.document)
      let share = try XCTUnwrap(service.shares.first)
      let response = try await helper.request(service, path: "/v1/documents/\(share.id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let layer = try XCTUnwrap((state["layers"] as? [[String: Any]])?.first)
      XCTAssertEqual(layer["imageLocked"] as? Bool, true)
      XCTAssertEqual(layer["positionLocked"] as? Bool, false)
      service.setDocumentTransfersEnabled(true)
      let legacy = try await helper.request(service, path: "/v1/documents/\(share.id)/file.photato")
      XCTAssertEqual(legacy.0.statusCode, 422)
      let download = try await helper.request(service, path: "/v1/documents/\(share.id)/file.photato",
        headers: ["X-Photato-Archive-Version": "12"])
      XCTAssertEqual(download.0.statusCode, 200)
      XCTAssertEqual(download.1[8], 12)
      XCTAssertEqual(try NativeArchive.decode(download.1), desktop.document)
      let staleHTTP = try await helper.edit(service, shared, "layer.protection",
        ["layerIDs": [id.uuidString], "protection": ["none"]], revision: oldRevision)
      XCTAssertEqual(staleHTTP, 409)
      shared.store.beginLayerProtection()
      let blocked = try await helper.edit(service, shared, "layer.protection",
        ["layerIDs": [id.uuidString], "protection": ["none"]])
      XCTAssertEqual(blocked, 409)
      shared.store.layerProtectionDraft = nil
      try shared.store.session.undo()
      XCTAssertEqual(shared.store.document, original)
      desktop.beginLayerProtection()
      let stale = try XCTUnwrap(desktop.layerProtectionDraft)
      desktop.layerPanelGeneration = UUID()
      desktop.commitLayerProtection(stale)
      XCTAssertNotNil(stale.error)
    }
  }
  func testAdobeProtectionEditAndPhotatoCommandEquivalence() throws {
    var d = try CraftDocument(width: 2, height: 2)
    let id = d.layers[0].id
    d.layers[0].name = "Pixels"
    d.layers[0].sourceTags = ["lyid": Data([0, 0, 0, 7])]
    let base: [String: Any] = ["image": ["source": ["url": "https://example.test/input.psd"]],
      "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 3600]]]]
    for names in [["none"], ["all"], ["position"], ["composite"], ["transparency", "artboard_autonest"]] {
      var request = base
      request["edits"] = ["layers": [["id": 7, "operation": ["type": "edit"], "protection": names]]]
      let adobe = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: request), createComposite: true)
      let command = try AutomationCommand(data: JSONSerialization.data(withJSONObject: [
        "command": "layer.protection", "revision": "test", "parameters": ["layerIDs": [id.uuidString], "protection": names]]))
      var native = EditorSession(document: d)
      try native.execute(XCTUnwrap(command.nativeCommand(document: d)))
      XCTAssertEqual(try adobe.applying(to: d).session.document, native.document)
    }
    var request = base; request["edits"] = [:] as [String: Any]
    XCTAssertEqual(try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: request), createComposite: true).applying(to: d).session.document, d)
    for invalid: [String: Any] in [
      ["layerIDs": [id.uuidString], "protection": []],
      ["layerIDs": [id.uuidString, id.uuidString], "protection": ["all"]],
      ["layerIDs": [id.uuidString], "protection": ["none", "all"]],
      ["layerIDs": [id.uuidString], "protection": ["image"]],
      ["layerIDs": [id.uuidString], "protection": ["none"], "includeDescendants": 1],
    ] {
      let command = try AutomationCommand(data: JSONSerialization.data(withJSONObject: [
        "command": "layer.protection", "revision": "test", "parameters": invalid]))
      XCTAssertThrowsError(try command.nativeCommand(document: d))
    }
  }
  @MainActor func testGroupPropagationMaskEditingAndLayerViaAvailability() throws {
    var d = try CraftDocument(width: 4, height: 4)
    let child = d.layers[0].id
    var group = Layer(name: "Group", content: .group(GroupContent()))
    group.protection = .transparency
    d.layers[0].parentID = group.id
    d.layers[0].mask = try Surface(width: 4, height: 4, fill: .white)
    d.layers.append(group)
    func request(_ include: Bool) throws -> Command {
      let value: [String: Any] = ["command": "layer.protection", "revision": "test",
        "parameters": ["layerIDs": [group.id.uuidString], "protection": ["composite"],
          "includeDescendants": include]]
      return try XCTUnwrap(AutomationCommand(data: JSONSerialization.data(withJSONObject: value))
        .nativeCommand(document: d))
    }
    var inherited = EditorSession(document: d)
    try inherited.execute(request(false))
    XCTAssertTrue(inherited.document.isImageLocked(child))
    XCTAssertTrue(inherited.document.layers[0].protection.isEmpty)
    try inherited.execute(.maskFill(child, 0))
    XCTAssertEqual(inherited.document.layers[0].mask?.pixel(x: 0, y: 0).r, 0)
    let store = EditorStore(document: inherited.document)
    defer { store.renderTask?.cancel() }
    store.perform(.selection(IntRect(x: 0, y: 0, width: 2, height: 2)))
    XCTAssertTrue(store.canLayerVia(.copy))
    XCTAssertFalse(store.canLayerVia(.cut))
    var expanded = EditorSession(document: d)
    try expanded.execute(request(true))
    XCTAssertEqual(expanded.document.layers[0].protection, .image)
    var adobe = EditorSession(document: d)
    try AdobeProtectionEdit(["name": "Group", "operation": ["type": "edit"],
      "protection": ["composite"]], path: "edits.layers[0]").apply(to: &adobe)
    XCTAssertEqual(expanded.document, adobe.document)
    try expanded.undo(); XCTAssertEqual(expanded.document, d)
    var locked = EditorSession(document: try CraftDocument(width: 2, height: 2))
    let root = locked.document.layers[0].id
    try locked.execute(.lock(root, true))
    try locked.execute(.newGroup(.init(name: "Locked child group"), children: [root]))
    XCTAssertTrue(locked.document.layers[0].locked)
    var apiModel = try CraftDocument(width: 2, height: 2)
    apiModel.layers[0].protection = .image
    let controls = EditorStore(document: apiModel)
    defer { controls.renderTask?.cancel() }
    controls.beginLayerProtection()
    let imageDraft = try XCTUnwrap(controls.layerProtectionDraft)
    XCTAssertEqual(imageDraft.state(.transparency), .on)
    imageDraft.set(.image, enabled: false)
    controls.commitLayerProtection(imageDraft)
    XCTAssertEqual(controls.activeLayer?.protection, .transparency)
    controls.perform(.protection([apiModel.layers[0].id: .all]))
    controls.beginLayerProtection()
    let allDraft = try XCTUnwrap(controls.layerProtectionDraft)
    allDraft.set(.all, enabled: false)
    controls.commitLayerProtection(allDraft)
    XCTAssertEqual(controls.activeLayer?.protection, .partial)
  }

}
