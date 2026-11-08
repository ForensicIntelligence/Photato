import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class QuickMaskOriginWorkflowTests: XCTestCase {
  @MainActor func testNativeTogglePreservesExplicitFullAndUndo() async throws {
    var model = try CraftDocument(width: 8, height: 8)
    model.selection = .init(x: 0, y: 0, width: 8, height: 8)
    let store = EditorStore(document: model, quickMaskPreferences: QuickMaskPreferences())
    defer { store.renderTask?.cancel() }
    store.toggleQuickMask()
    let active = store.document
    XCTAssertEqual(active.quickMask?.psdQuickMaskInitiallyEmpty, false)
    store.toggleQuickMask()
    XCTAssertTrue(try XCTUnwrap(store.document.coverageSelection()).isFullCoverage)
    await store.undo(); XCTAssertEqual(store.document, active)
    await store.redo(); XCTAssertTrue(try XCTUnwrap(store.document.coverageSelection()).isFullCoverage)
    XCTAssertEqual(store.document.layers, model.layers)
  }
  @MainActor func testHTTPEntryFillExitAndNativePathAgree() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let model = try CraftDocument(width: 8, height: 8)
      document.store.session = EditorSession(document: model); try service.share(document)
      let native = EditorStore(document: model, quickMaskPreferences: QuickMaskPreferences())
      defer { native.renderTask?.cancel() }
      var options = ChannelDisplayOptions(); options.indicates = .selectedAreas
      native.quickMaskOptions = options
      native.toggleQuickMask()
      let entered = try await helper.edit(service, document, "channel.edit", ["action":"quickMask", "enabled":true, "indicates":"selectedAreas"])
      XCTAssertEqual(entered, 200)
      XCTAssertEqual(document.store.document.quickMask?.psdQuickMaskInitiallyEmpty, true)
      XCTAssertEqual(document.store.document.quickMask?.pixels, native.document.quickMask?.pixels)
      XCTAssertEqual(document.store.document.quickMask?.pixels.pixel(x: 0, y: 0).r, 0)
      let filled = try await helper.edit(service, document, "channel.edit", ["action":"fill", "target":"quickMask", "value":0, "opacity":1])
      XCTAssertEqual(filled, 200)
      native.perform(.channel(.fill(.quickMask, 0, 1)))
      let exited = try await helper.edit(service, document, "channel.edit", ["action":"quickMask", "enabled":false])
      XCTAssertEqual(exited, 200); native.toggleQuickMask()
      XCTAssertEqual(try document.store.document.coverageSelection()?.denseBytes(), try native.document.coverageSelection()?.denseBytes())
      XCTAssertTrue(try XCTUnwrap(document.store.document.coverageSelection()).isFullCoverage)
      XCTAssertEqual(document.store.document.layers, model.layers)
    }
  }
  @MainActor func testHTTPNative91NegotiationPreservesRetainedSelectedGray() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var model = try CraftDocument(width: 8, height: 8, depth: .f32)
      let raw = try Surface(width: 8, height: 8, depth: .f32, fill: Pixel(0.1234567, 0.1234567, 0.1234567))
      let coverage = try raw.mappedStoredSamples { p in let v: Float = 1 - p.r; return Pixel(v, v, v) }
      var options = ChannelDisplayOptions(); options.indicates = .selectedAreas
      var channel = AlphaChannel(name: "Selected", pixels: coverage, options: options)
      channel.psdSelectedGray = raw; model.alphaChannels = [channel]
      document.store.session = EditorSession(document: model); try service.share(document)
      let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/file.photato"
      let denied = try await helper.request(service, path: path, headers: ["X-Photato-Archive-Version":"91"])
      XCTAssertEqual(denied.0.statusCode, 403); XCTAssertEqual(document.store.document, model)
      service.setDocumentTransfersEnabled(true)
      for headers in [[:], ["X-Photato-Archive-Version":"90"]] {
        let (response, _) = try await helper.request(service, path: path, headers: headers)
        XCTAssertEqual(response.statusCode, 422)
        XCTAssertEqual(document.store.document, model)
      }
      let (response, data) = try await helper.request(service, path: path, headers: ["X-Photato-Archive-Version":"91"])
      XCTAssertEqual(response.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decode(data), model)
      let metadata = ChannelAPI.state(channel), state = try XCTUnwrap(metadata["psd"] as? [String: Any])
      XCTAssertEqual(state["retainedFloat32SelectedGray"] as? Bool, true)
      XCTAssertEqual(ChannelAPI.photoshopCapabilities["selectedGrayRetentionVersion"] as? Int, 91)
    }
  }
}
