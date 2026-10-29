import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VariableProfileWorkflowTests: XCTestCase {
  func template(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try ColorProfileWorkflowTests().fixture(depth)
    let layerID = document.layers[0].id
    try Command.variables(.define([.init(name: "photo", layerID: layerID, kind: .pixelReplacement)])).apply(to: &document)
    var pixels = try Surface(width: 3, height: 1, depth: depth)
    pixels.setPixel(x: 0, y: 0, Pixel(1, 0, 0, 1))
    pixels.setPixel(x: 1, y: 0, Pixel(0, 1, 0, 0.5))
    pixels.setPixel(x: 2, y: 0, Pixel(0, 0, 1, 0))
    let image = VariableImage(name: "Owned RGB with alpha", pixels: pixels)
    try Command.variables(.image(image)).apply(to: &document)
    let row = VariableDataSet(name: "Colors", values: ["photo": .pixels(image.id)])
    try Command.variables(.dataSets([row], append: false)).apply(to: &document)
    try Command.variables(.apply(row.id)).apply(to: &document)
    return document
  }
  func testAssignAndConvertKeepAssetsUsableWithUndoAndNativePersistence() throws {
    for depth in PixelDepth.allCases {
      for operation in ColorProfileRequest.Operation.allCases {
        let source = try template(depth), original = source.variables!.images[0]
        let profile = try ColorProfileWorkflowTests().profile(CGColorSpace.displayP3, depth: depth)
        let request = ColorProfileRequest(operation, profile: profile)
        var session = EditorSession(document: source)
        try session.execute(ColorProfileInput.command(request, in: source))
        let changed = session.document, asset = try XCTUnwrap(changed.variables?.images.first)
        XCTAssertEqual(asset.id, original.id); XCTAssertEqual(asset.name, original.name)
        XCTAssertEqual(asset.workingICC, profile); XCTAssertEqual(asset.pixels.depth, depth)
        XCTAssertEqual(changed.variables?.dataSets, source.variables?.dataSets)
        XCTAssertNil(changed.variables?.activeDataSetID)
        if operation == .assign { XCTAssertEqual(changed.layers, source.layers) }
        for x in 0..<3 { XCTAssertEqual(asset.pixels.pixel(x: x, y: 0).a, original.pixels.pixel(x: x, y: 0).a) }
        XCTAssertNotEqual(asset.pixels, original.pixels)
        // Hidden blue is converted independently of its zero alpha rather than discarded.
        XCTAssertGreaterThan(asset.pixels.pixel(x: 2, y: 0).b, 0.8)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(changed)), changed)
        try session.undo(); XCTAssertEqual(session.document, source)
        try session.redo(); XCTAssertEqual(session.document, changed)
        let rowID = changed.variables!.dataSets[0].id
        try session.execute(.variables(.apply(rowID)))
        let applied = session.document
        XCTAssertEqual(applied.variables?.images, changed.variables?.images)
        try session.execute(.variables(.apply(rowID))); XCTAssertEqual(session.document, applied)
        XCTAssertNoThrow(try VariableDataExport.render(changed, options: .init(format: .png)))
      }
    }
  }
  func testIdentityAndCancelledProfileWorkDoNotPartiallyChangeAssets() async throws {
    let source = try template(.u16), profile = try NativeModeProfile.standard(.rgb, depth: .u16)
    var assigned = source
    try ColorProfileInput.command(.init(.assign, profile: profile), in: source).apply(to: &assigned)
    let same = try VariableGraphicsInput.imagesForWorkingProfile(in: assigned)
    XCTAssertEqual(same, assigned.variables)
    let p3 = try ColorProfileWorkflowTests().profile(CGColorSpace.displayP3)
    let input = assigned
    let worker = Task.detached {
      try await Task.sleep(for: .milliseconds(20))
      return try ColorProfileInput.command(.init(.convert, profile: p3), in: input)
    }
    worker.cancel()
    do { _ = try await worker.value; XCTFail("Cancelled conversion returned a command") } catch is CancellationError {}
    XCTAssertEqual(assigned.variables, same)
  }
  @MainActor func testNativeProfilePreviewCancelAndCommitRetainVariableHistory() async throws {
    let original = try template(.u16), store = EditorStore(document: original)
    defer { store.cancelColorProfile(); store.renderTask?.cancel() }
    let p3 = try ColorProfileWorkflowTests().profile(CGColorSpace.displayP3)
    store.beginColorProfile(.assign)
    let draft = try XCTUnwrap(store.colorProfileWorkspace); try draft.loadProfile(p3); await draft.task?.value
    XCTAssertTrue(draft.ready, draft.error ?? "Preview unavailable")
    XCTAssertEqual(store.document, original)
    store.cancelColorProfile(); XCTAssertEqual(store.document, original)
    store.beginColorProfile(.assign)
    let commit = try XCTUnwrap(store.colorProfileWorkspace); try commit.loadProfile(p3); await commit.task?.value
    store.commitColorProfile(); await commit.commitTask?.value
    XCTAssertNil(store.colorProfileWorkspace, commit.error ?? "Commit incomplete")
    XCTAssertEqual(store.document.variables?.images.first?.workingICC, p3)
    XCTAssertEqual(store.session.undoStack.count, 1)
    store.performGeometry(.variables(.apply(original.variables!.dataSets[0].id))); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count, 2)
    try store.session.undo(); try store.session.undo(); XCTAssertEqual(store.document, original)
  }
  @MainActor func testHTTPProfileOperationsMatchNativeAndReapplyExport() async throws {
    let helper = AutomationTests(), original = try template(.u16)
    let p3 = try ColorProfileWorkflowTests().profile(CGColorSpace.displayP3)
    for operation in ColorProfileRequest.Operation.allCases {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        document.store.session = EditorSession(document: original); try service.share(document)
        let command = operation == .assign ? "document.assignProfile" : "document.convertProfile"
        let result = try await helper.edit(service, document, command, ["profileBase64": p3.base64EncodedString()]); XCTAssertEqual(result, 200)
        var expected = original; try ColorProfileInput.command(.init(operation, profile: p3), in: original).apply(to: &expected)
        XCTAssertEqual(document.store.document, expected)
        let rowID = original.variables!.dataSets[0].id
        let applied = try await helper.edit(service, document, "variables.apply", ["dataSetID": rowID.uuidString]); XCTAssertEqual(applied, 200)
        service.setDocumentTransfersEnabled(true)
        let exported = try await helper.edit(service, document, "variables.export", ["format": "png"]); XCTAssertEqual(exported, 200)
        try document.store.session.undo(); try document.store.session.undo(); XCTAssertEqual(document.store.document, original)
      }
    }
  }
}
