import CoreGraphics
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LargeColorProfileWorkflowTests: XCTestCase {
  func maximumSource(_ mode: DocumentColorMode? = nil) throws -> CraftDocument {
    var source = try CraftDocument(width: 300_000, height: 300_000, depth: .u16)
    if let mode {
      var native = try NativeModeRaster(width: source.width, height: source.height, mode: mode, depth: .u16)
      for c in 0..<mode.componentCount {
        let v = Float(c + 1) / 8
        native = try native.replacingChannel(c, with: Surface(width: source.width, height: source.height,
          depth: .u16, fill: Pixel(v, v, v)))
      }
      native = try native.replacingOpacity(with: Surface(width: source.width, height: source.height,
        depth: .u16, fill: Pixel(0.5, 0.5, 0.5)))
      try native.set(0.75, component: 0, index: source.width * source.height - 1)
      source.modeDescriptor = try .init(mode: mode, depth: .u16, profile: native.profile)
      source.layers[0].nativeMode = native; source.layers[0].content = .raster(try native.surface())
    } else {
      var pixels = try Surface(width: source.width, height: source.height, depth: .u16,
        fill: Pixel(0.2, 0.4, 0.8, 0.5))
      pixels.setPixel(x: 299_999, y: 299_999, Pixel(0.75, 0.25, 0.1, 0))
      source.layers[0].content = .raster(pixels)
    }
    return source
  }
  func testMaximumSparseAssignmentIsAnUndoableNumericIdentity() throws {
    for depth in PixelDepth.allCases {
      var source = try CraftDocument(width: 300_000, height: 300_000, depth: depth)
      var pixels = try Surface(width: source.width, height: source.height, depth: depth,
        fill: Pixel(0.25, 0.5, 0.75, 0), colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      pixels.setPixel(x: 299_999, y: 299_999, Pixel(0.8, 0.3, 0.1, 0.5))
      source.layers[0].content = .raster(pixels)
      let profile = try NativeModeProfile.atDepth(XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?), mode: .rgb, depth: depth)
      let command = try ColorProfileInput.command(.init(.assign, profile: profile), in: source)
      var session = EditorSession(document: source)
      try session.execute(command)
      let assigned = session.document
      XCTAssertEqual(assigned.layers, source.layers)
      XCTAssertEqual(assigned.workingICC, profile)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(assigned)), assigned)
      try session.undo(); XCTAssertEqual(session.document, source)
      try session.redo(); XCTAssertEqual(session.document, assigned)
    }
  }
  @MainActor func testLargeNativePreviewCancelCommitAndUndoUseBoundedImages() async throws {
    var source = try CraftDocument(width: 9001, height: 1001, depth: .u16)
    source.layers[0].content = .raster(try Surface(width: source.width, height: source.height,
      depth: .u16, fill: Pixel(0.2, 0.4, 0.8, 0.75)))
    let store = EditorStore(document: source)
    defer { store.cancelColorProfile(); store.renderTask?.cancel() }
    XCTAssertTrue(store.canBeginColorProfile)
    let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
    store.beginColorProfile(.assign)
    let draft = try XCTUnwrap(store.colorProfileWorkspace)
    try draft.loadProfile(profile); await draft.task?.value
    XCTAssertTrue(draft.ready, draft.error ?? "No bounded preview")
    XCTAssertEqual(draft.image?.width, 2048); XCTAssertLessThanOrEqual(try XCTUnwrap(draft.image?.height), 2048)
    XCTAssertEqual(draft.originalImage?.width, 2048)
    XCTAssertEqual(store.document, source)
    store.cancelColorProfile(); XCTAssertEqual(store.document, source)
    store.beginColorProfile(.convert)
    let commit = try XCTUnwrap(store.colorProfileWorkspace)
    try commit.loadProfile(profile); await commit.task?.value
    XCTAssertTrue(commit.ready, commit.error ?? "No converted preview")
    store.commitColorProfile(); await commit.commitTask?.value
    XCTAssertNil(store.colorProfileWorkspace, commit.error ?? "No commit")
    var expected = source
    try ColorProfileInput.command(.init(.convert, profile: profile), in: source).apply(to: &expected)
    XCTAssertEqual(store.document, expected)
    try store.session.undo(); XCTAssertEqual(store.document, source)
    try store.session.redo(); XCTAssertEqual(store.document, expected)
  }
  @MainActor func testEditThenUndoCannotCommitAnEarlierProfilePreview() async throws {
    let source = try ColorProfileWorkflowTests().fixture()
    let store = EditorStore(document: source)
    defer { store.cancelColorProfile(); store.renderTask?.cancel() }
    store.beginColorProfile(.assign)
    let draft = try XCTUnwrap(store.colorProfileWorkspace)
    try draft.loadProfile(XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?))
    await draft.task?.value
    XCTAssertTrue(draft.ready, draft.error ?? "No preview")
    try store.session.execute(.renameLayer(source.layers[0].id, "Temporary"))
    try store.session.undo(); XCTAssertEqual(store.document, source)
    store.commitColorProfile(); await draft.commitTask?.value
    XCTAssertEqual(store.document, source)
    XCTAssertNotNil(draft.error)
    XCTAssertFalse(draft.committing)
  }
  @MainActor func testDocumentCloseAndReadRetireProfileWork() async throws {
    let source = try ColorProfileWorkflowTests().fixture()
    for close in [false, true] {
      let document = CraftNSDocument(model: source), store = document.store
      defer { store.renderTask?.cancel(); store.cancelColorProfile() }
      store.beginColorProfile(.convert)
      let draft = try XCTUnwrap(store.colorProfileWorkspace)
      let preview = draft.task
      if close { document.close() }
      else { try document.read(from: NativeArchive.encodeChunked(source), ofType: CraftNSDocument.nativeType) }
      await preview?.value
      XCTAssertNil(store.colorProfileWorkspace)
      XCTAssertFalse(draft.ready); XCTAssertFalse(draft.rendering)
      XCTAssertEqual(store.document, source)
    }
  }
  @MainActor func testRealHTTPLargeRGBAndComponentProfilesMatchNativeHistory() async throws {
    let helper = AutomationTests()
    for mode: DocumentColorMode? in [nil, .cmyk, .grayscale] {
      let source = try maximumSource(mode)
      let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        let store = document.store
        store.session = EditorSession(document: source)
        store.selectedLayerIDs = Set(source.activeLayerID.map { [$0] } ?? [])
        try service.share(document)
        var expected = source
        try ColorProfileInput.command(.init(.convert, profile: profile), in: source).apply(to: &expected)
        let revision = service.revision(store)
        let status = try await helper.edit(service, document, "document.convertProfile", ["profileBase64": profile.base64EncodedString()])
        XCTAssertEqual(status, 200); XCTAssertEqual(store.document, expected)
        let stale = try await helper.edit(service, document, "document.convertProfile", ["profileBase64": profile.base64EncodedString()], revision: revision)
        XCTAssertEqual(stale, 409); XCTAssertEqual(store.document, expected)
        try store.session.undo(); XCTAssertEqual(store.document, source)
        try store.session.redo(); XCTAssertEqual(store.document, expected)
        let capabilities = ColorProfileAPI.capabilities
        XCTAssertEqual(capabilities["maximumPixels"] as? Int, Surface.maxPixels)
        XCTAssertEqual(capabilities["maximumDimension"] as? Int, 300_000)
        XCTAssertEqual(capabilities["legacyKernelMaximumPixels"] as? Int, 8_388_608)
        XCTAssertEqual(capabilities["pagedProfileOperations"] as? Bool, true)
      }
    }
  }
  func testPublishedOutputICCUsesIdenticalLargeNativeConversion() throws {
    let source = try maximumSource()
    let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
    let url = URL(string: "https://example.test/owned-large-profile.icc")!
    let adapter = try AdobeOutputProfile(["type": "custom", "name": "Owned Display P3",
      "imageMode": "rgb", "source": ["url": url.absoluteString]])
    let result = try adapter.convert(source, resources: [url: profile], rasterOutput: false)
    var expected = source
    try ColorProfileInput.command(.init(.convert, profile: profile), in: source).apply(to: &expected)
    XCTAssertEqual(result, expected)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(result)), result)
  }
  @MainActor func testAPIProfileTargetCannotFallThroughToGenericClipboardAvailability() async throws {
    let helper = AutomationTests()
    let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let store = document.store, source = store.document
      store.smartFilterMaskEditing = true
      defer { store.smartFilterMaskEditing = false }
      XCTAssertFalse(store.canBeginColorProfile)
      XCTAssertTrue(store.clipboardTargetAvailable)
      let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: [
        "command": "document.assignProfile", "revision": service.revision(store),
        "parameters": ["profileBase64": profile.base64EncodedString()]])
      XCTAssertEqual(response.0.statusCode, 422)
      let error = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: String])
      XCTAssertEqual(error["error"], "This operation requires the composite color-profile target.")
      XCTAssertEqual(store.document, source)
    }
  }
}
