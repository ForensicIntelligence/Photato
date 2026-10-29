import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ColorPolicyTests: XCTestCase {
  func source() throws -> CraftDocument {
    var doc = try ColorProfileWorkflowTests().fixture()
    doc.workingICC = try ColorProfileWorkflowTests().profile(CGColorSpace.displayP3)
    return doc
  }
  func customCMYK() throws -> Data {
    // Owned metadata variant, not a different printing characterization.
    var data = try NativeModeProfile.standard(.cmyk, depth: .u16)
    data.replaceSubrange(48..<52, with: Data("PHTO".utf8)); try NativeModeProfile.validate(data, mode: .cmyk, depth: .u16)
    return data
  }
  func pixels(_ document: CraftDocument) throws -> Surface {
    guard case .raster(let value) = document.layers[0].content else { throw CraftError.invalid("Expected raster fixture.") }
    return value
  }
  func testOpeningPreserveConvertOffAndExplicitOverride() throws {
    let original = try source(); var settings = ColorSettings()
    XCTAssertEqual(try ColorPolicyInput.opening(original, settings: settings), original)
    settings.rgbPolicy = .off
    let off = try ColorPolicyInput.opening(original, settings: settings)
    XCTAssertEqual(off.layers, original.layers); XCTAssertEqual(off.profileIsUntagged, true)
    XCTAssertEqual(try ColorProfileInput.effectiveProfile(off), try settings.profile(.rgb, depth: original.depth))
    settings.rgbPolicy = .convertToWorking
    let converted = try ColorPolicyInput.opening(original, settings: settings)
    XCTAssertNil(converted.profileIsUntagged); XCTAssertNotEqual(try pixels(converted), try pixels(original))
    XCTAssertEqual(try pixels(converted).pixel(x: 0, y: 0).a, try pixels(original).pixel(x: 0, y: 0).a)
    XCTAssertEqual(try ColorPolicyInput.opening(original, settings: settings, choice: .init(.preserveEmbedded)), original)
    settings.askMismatchOpening = true
    XCTAssertThrowsError(try ColorPolicyInput.opening(original, settings: settings)) { XCTAssertTrue($0 is ColorPolicyReviewNeeded) }
    XCTAssertThrowsError(try ColorPolicyInput.opening(original, settings: settings, choice: .init(.leaveUntagged)))
  }
  func testMissingProfileUsesWorkingInterpretationAndCanAssignCustom() throws {
    var original = try source(); original.profileIsUntagged = true
    var settings = ColorSettings(); settings.askMissingOpening = true
    XCTAssertThrowsError(try ColorPolicyInput.opening(original, settings: settings))
    let untagged = try ColorPolicyInput.opening(original, settings: settings, choice: .init(.leaveUntagged))
    XCTAssertEqual(untagged.layers, original.layers); XCTAssertEqual(untagged.profileIsUntagged, true)
    XCTAssertEqual(try ColorProfileInput.effectiveProfile(untagged), try settings.profile(.rgb, depth: original.depth))
    let assigned = try ColorPolicyInput.opening(original, settings: settings, choice: .init(.assignWorking))
    XCTAssertEqual(assigned.layers, original.layers); XCTAssertNil(assigned.profileIsUntagged)
    let custom = try ColorPolicyInput.opening(original, settings: settings, choice: .init(.assignProfile, profile: original.workingICC))
    XCTAssertEqual(custom.workingICC, original.workingICC); XCTAssertNil(custom.profileIsUntagged)
    XCTAssertThrowsError(try ColorPolicyInput.opening(original, settings: settings, choice: .init(.assignProfile)))
  }
  func testPasteNumbersAndAppearanceUseDistinctSamplesAndRetainAlpha() throws {
    let source = try source(), target = try ColorProfileWorkflowTests().fixture()
    let content = try ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id])
    var settings = ColorSettings(); settings.askMismatchPasting = true
    XCTAssertThrowsError(try ColorPolicyInput.pasteCommand(content, into: target, settings: settings))
    var numbers = EditorSession(document: target)
    try numbers.execute(ColorPolicyInput.pasteCommand(content, into: target, settings: settings, choice: .init(.preserveNumbers)))
    guard case .raster(let numeric) = numbers.document.layers.last?.content else { return XCTFail("pasted pixels") }
    XCTAssertEqual(numeric, try pixels(source))
    var appearance = EditorSession(document: target)
    try appearance.execute(ColorPolicyInput.pasteCommand(content, into: target, settings: settings, choice: .init(.convertAppearance)))
    guard case .raster(let converted) = appearance.document.layers.last?.content else { return XCTFail("pasted pixels") }
    XCTAssertNotEqual(converted, numeric); XCTAssertEqual(converted.pixel(x: 0, y: 0).a, numeric.pixel(x: 0, y: 0).a)
    try numbers.undo(); XCTAssertEqual(numbers.document, target)
    try appearance.undo(); XCTAssertEqual(appearance.document, target)
  }
  func testCMYKPreserveNumbersRetainsEveryPlane() throws {
    let target = try source().convertingMode(.init(mode: .cmyk, depth: .u16))
    var source = target
    try ColorProfileInput.command(.init(.assign, profile: customCMYK()), in: source).apply(to: &source)
    let content = try ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id])
    var settings = ColorSettings(); settings.cmykPolicy = .off
    var session = EditorSession(document: target)
    try session.execute(ColorPolicyInput.pasteCommand(content, into: target, settings: settings))
    XCTAssertEqual(session.document.layers.last?.nativeMode?.planes, source.layers[0].nativeMode?.planes)
    XCTAssertEqual(session.document.layers.last?.nativeMode?.profile, target.modeDescriptor?.profile)
  }
  func testNativeRGBClipboardToCustomOrdinaryRGBRetainsConvertedCoordinates() throws {
    let target = try source()
    let native = try ColorProfileWorkflowTests().fixture().convertingMode(.init(mode: .rgb, depth: .u16))
    let content = try ClipboardRenderer.copy(native, layerIDs: [native.layers[0].id])
    var expected = native
    try ColorProfileInput.command(.init(.convert, profile: XCTUnwrap(target.workingICC)), in: native).apply(to: &expected)
    var session = EditorSession(document: target)
    try session.execute(ColorPolicyInput.pasteCommand(content, into: target, settings: .init()))
    guard case .raster(let pixels) = session.document.layers.last?.content, let components = expected.layers[0].nativeMode else { return XCTFail("pixels") }
    for x in 0..<3 {
      let p = pixels.pixel(x: x, y: 0)
      for (channel,value) in [p.r,p.g,p.b,p.a].enumerated() { XCTAssertEqual(value, components.value(component: channel, index: x)) }
    }
  }
  @MainActor func testSettingsMigrationOldClientPatchAndOffNewDocument() throws {
    let folder = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("ColorSettings.json")
    let legacy: [String: Any] = ["version": 1, "settings": ["intent": "relativeColorimetric", "blackPointCompensation": true]]
    try JSONSerialization.data(withJSONObject: legacy).write(to: url)
    let store = ColorSettingsStore(url: url); XCTAssertNil(store.loadError)
    var next = store.value; next.rgbPolicy = .off; next.askMissingOpening = true
    try store.commit(next, revision: store.revision)
    XCTAssertEqual(ColorSettingsStore(url: url).value, next)
    let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    XCTAssertEqual(archive["version"] as? Int, 2)
    var old = ColorSettingsAPI.json(.init()); for key in ColorSettingsAPI.policyFields.keys { old.removeValue(forKey: key) }; for key in ColorSettingsAPI.alertFields.keys { old.removeValue(forKey: key) }
    let raw = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: old))
    let patched = try ColorSettingsAPI.decode(raw, base: next)
    XCTAssertEqual(patched.rgbPolicy, .off); XCTAssertTrue(patched.askMissingOpening)
    let options = NewDocumentOptions(settings: next); options.widthField.stringValue = "3"; options.heightField.stringValue = "1"
    XCTAssertEqual(try options.document(name: "Untagged").profileIsUntagged, true)
    try options.setProfile(NativeModeProfile.standard(.rgb, depth: .u8), name: "Explicit")
    XCTAssertNil(try options.document(name: "Tagged").profileIsUntagged)
  }
  func testFloatClipboardCanConvertToIntegerCMYKWithoutChangingSource() throws {
    let source = try ColorProfileWorkflowTests().fixture(.f32)
    let target = try ColorProfileWorkflowTests().fixture().convertingMode(.init(mode: .cmyk, depth: .u16))
    let content = try ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id])
    var session = EditorSession(document: target)
    try session.execute(ColorPolicyInput.pasteCommand(content, into: target, settings: .init()))
    let result = try XCTUnwrap(session.document.layers.last?.nativeMode)
    XCTAssertEqual(result.mode, .cmyk); XCTAssertEqual(result.depth, .u16)
    XCTAssertEqual(content.document, source)
    XCTAssertEqual(result.value(component: 4, index: 0), PixelDepth.u16.quantize(try pixels(source).pixel(x: 0, y: 0).a))
    XCTAssertThrowsError(try ColorPolicyInput.pasteCommand(content, into: target, settings: .init(), choice: .init(.preserveNumbers)))
  }
  @MainActor func testNativeReviewCancellationClosesItsOwnWindow() async throws {
    _ = NSApplication.shared
    var settings = ColorSettings(); settings.askMismatchOpening = true
    let assessment = try ColorPolicyInput.openingAssessment(source(), settings: settings)
    let before = Set(NSApp.windows.map(ObjectIdentifier.init))
    let task = Task { try await ColorPolicyDialog.present(assessment, .rgb, .u16) }
    for _ in 0..<100 where !NSApp.windows.contains(where: { !before.contains(ObjectIdentifier($0)) && $0.title == "Embedded Profile Mismatch" }) {
      try await Task.sleep(for: .milliseconds(5))
    }
    let window = try XCTUnwrap(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.title == "Embedded Profile Mismatch" })
    XCTAssertTrue(window.isVisible)
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertFalse(window.isVisible)
  }
  @MainActor func testPolicyViewsFitAndCaptureOffscreen() throws {
    _ = NSApplication.shared
    let store = ColorSettingsStore(), draft = ColorSettingsDraft(store: store)
    let actual = ColorSettingsWindowController(store: store)
    let actualWindow = try XCTUnwrap(actual.window), actualView = try XCTUnwrap(actualWindow.contentView)
    defer { actual.close() }
    actualView.layoutSubtreeIfNeeded()
    XCTAssertGreaterThanOrEqual(actualView.bounds.height, actualView.fittingSize.height, "The actual Color Settings window must contain every policy control.")
    XCTAssertGreaterThanOrEqual(actualView.bounds.width, actualView.fittingSize.width)
    let assessment = try ColorPolicyInput.openingAssessment(source(), settings: .init())
    let review = ColorPolicyDialog(assessment, mode: .rgb, depth: .u16)
    let views: [(String, NSView, CGFloat)] = [
      ("color-settings", NSHostingView(rootView: ColorSettingsView(draft: draft, dismiss: {})), 580),
      ("profile-review", NSHostingView(rootView: ColorPolicyDialogView(model: review)), 560)]
    for (name, view, width) in views {
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua); window.contentView = view
      defer { window.close() }
      view.layoutSubtreeIfNeeded()
      let size = view.fittingSize
      XCTAssertLessThanOrEqual(size.width, width); XCTAssertLessThanOrEqual(size.height, 800)
      view.frame = .init(origin: .zero, size: size); window.setContentSize(size); view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
      if let directory = ProcessInfo.processInfo.environment["PHOTATO_POLICY_EVIDENCE"] {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
      }
    }
  }
  @MainActor func testOpeningCancelAndAcceptedConversionKeepSourceAndFingerprint() async throws {
    let folder = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("owned.psd"), bytes = try DocumentIO.encode(source(), format: .psd)
    try bytes.write(to: url)
    let controller = DocumentOpeningTests().controller()
    defer { controller.documentOpening.colorPolicyReviewer = ColorPolicyDialog.present; for doc in controller.documents { doc.updateChangeCount(.changeCleared); doc.close() } }
    var settings = ColorSettings(); settings.askMismatchOpening = true
    try controller.colorSettings.commit(settings, revision: controller.colorSettings.revision)
    controller.documentOpening.colorPolicyReviewer = { assessment, _, _ in
      XCTAssertEqual(assessment.kind, .mismatch); throw CancellationError()
    }
    try controller.documentOpening.begin([url], display: false); await controller.documentOpening.waitUntilIdle()
    XCTAssertTrue(controller.documents.isEmpty); XCTAssertEqual(try Data(contentsOf: url), bytes)
    controller.documentOpening.colorPolicyReviewer = { _, _, _ in .init(.convertToWorking) }
    let prepared = try PreparedLocalDocument.read(url, format: .psd)
    try controller.documentOpening.begin([url], display: false); await controller.documentOpening.waitUntilIdle()
    let opened = try XCTUnwrap(controller.documents.first as? CraftNSDocument)
    XCTAssertTrue(opened.isDocumentEdited); XCTAssertTrue(opened.sourceSaveNeedsReview)
    XCTAssertEqual(opened.fileModificationDate, prepared.modificationDate)
    XCTAssertEqual(opened.recoverySourceRecord?.fingerprint, prepared.fingerprint)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(try ColorProfileInput.effectiveProfile(opened.store.document), try settings.profile(.rgb, depth: .u16))
  }
  @MainActor func testNativePasteReviewCancelStaleAndAcceptedNumbers() async throws {
    let clipboard = MemoryClipboard(), original = try ColorProfileWorkflowTests().fixture(), source = try source()
    clipboard.value = try ClipboardRepresentations(ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id]))
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let store = EditorStore(document: original, clipboard: clipboard); store.documentController = controller
    defer { store.renderTask?.cancel() }
    var settings = ColorSettings(); settings.askMismatchPasting = true
    try controller.colorSettings.commit(settings, revision: controller.colorSettings.revision)
    store.colorPolicyReviewer = { _, _, _ in throw CancellationError() }
    store.pasteImage(); await store.geometryTask?.value
    XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
    store.colorPolicyReviewer = { _, _, _ in clipboard.changeCount += 1; return .init(.preserveNumbers) }
    store.pasteImage(); await store.geometryTask?.value
    XCTAssertEqual(store.document, original); XCTAssertNotNil(store.error)
    store.colorPolicyReviewer = { _, _, _ in .init(.preserveNumbers) }; store.error = nil
    store.pasteImage(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.document.layers.count, 2)
    guard case .raster(let pixels) = store.document.layers.last?.content else { return XCTFail("pixels") }
    XCTAssertEqual(pixels, try self.pixels(source))
    await store.undo(); XCTAssertEqual(store.document, original)
  }
  @MainActor func testAPIImportAndPasteReviewNeverPublishOrEditBeforeDecision() async throws {
    let helper = AutomationTests(), transfer = DocumentIOWorkflowTests(), source = try source()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var settings = ColorSettings(); settings.askMismatchOpening = true; settings.askMismatchPasting = true
      try service.controller.colorSettings.commit(settings, revision: service.controller.colorSettings.revision)
      service.setDocumentTransfersEnabled(true); try service.share(document)
      let bytes = try DocumentIO.encode(source, format: .psd), count = service.controller.documents.count
      let review = try await transfer.request(service, path: "/v1/documents/import", data: bytes, type: "image/vnd.adobe.photoshop")
      XCTAssertEqual(review.0.statusCode, 409); XCTAssertEqual(service.controller.documents.count, count)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: review.1) as? [String: Any]); XCTAssertNotNil(object["colorProfileReview"])
      let accepted = try await transfer.request(service, path: "/v1/documents/import", data: bytes, type: "image/vnd.adobe.photoshop", headers: ["X-Photato-Color-Decision": "preserveEmbedded"])
      XCTAssertEqual(accepted.0.statusCode, 201, String(decoding: accepted.1, as: UTF8.self))
      for case let imported as CraftNSDocument in service.controller.documents where imported !== document { imported.updateChangeCount(.changeCleared); imported.close() }
      let payload = try ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id]).encoded().base64EncodedString()
      let original = document.store.document
      let blocked = try await helper.edit(service, document, "clipboard.paste", ["payloadBase64": payload])
      XCTAssertEqual(blocked, 409); XCTAssertEqual(document.store.document, original)
      let pasted = try await helper.edit(service, document, "clipboard.paste", ["payloadBase64": payload, "colorDecision": "preserveNumbers"])
      XCTAssertEqual(pasted, 200); XCTAssertEqual(document.store.document.layers.count, original.layers.count + 1)
      let invalid = try await helper.edit(service, document, "clipboard.paste", ["payloadBase64": payload, "colorDecision": "discard"])
      XCTAssertEqual(invalid, 400)
    }
  }
  @MainActor func testWorkingProofSnapshotNativeAPIAndPresetsRetainCustomICC() async throws {
    let helper = AutomationTests(), profile = try customCMYK()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var settings = ColorSettings(); settings.workingCMYK = profile
      try service.controller.colorSettings.commit(settings, revision: service.controller.colorSettings.revision)
      try service.share(document); let original = document.store.document
      document.store.beginProof(); let draft = try XCTUnwrap(document.store.proofWorkspace)
      XCTAssertEqual(try draft.settings.resolvedProfile(), profile)
      document.store.cancelProof()
      let configured = try await helper.edit(service, document, "proof.configure", ["settings": ["device": "workingCMYK", "enabled": true]])
      XCTAssertEqual(configured, 200); XCTAssertEqual(try document.store.proofSettings.resolvedProfile(), profile)
      let encoded = try JSONEncoder().encode(document.store.proofSettings)
      try service.controller.colorSettings.commit(.init(), revision: service.controller.colorSettings.revision)
      XCTAssertEqual(try document.store.proofSettings.resolvedProfile(), profile)
      XCTAssertEqual(try JSONDecoder().decode(ProofSettings.self, from: encoded).resolvedProfile(), profile)
      let refreshed = try await helper.edit(service, document, "proof.configure", ["settings": ["device": "workingCMYK"]])
      XCTAssertEqual(refreshed, 200)
      XCTAssertEqual(try document.store.proofSettings.resolvedProfile(), try NativeModeProfile.standard(.cmyk, depth: .u16))
      XCTAssertEqual(document.store.document, original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
}
