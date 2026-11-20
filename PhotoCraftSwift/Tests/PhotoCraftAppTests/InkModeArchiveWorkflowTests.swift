import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class InkModeArchiveWorkflowTests: XCTestCase {
  @MainActor func testReopenedMultichannelCMYKReturnMatchesNativePreviewAndHTTP() async throws {
    let values: [UInt32] = [4200, 15000, 27800, 56800]
    let builder = try NativeModeRaster.RowBuilder(width: 2, height: 1, mode: .cmyk, depth: .u16)
    for index in values.indices { try builder.fill(component: index, word: values[index]) }
    try builder.fill(component: 4, word: 65535)
    let native = try builder.finish()
    var source = try CraftDocument(width: 2, height: 1, depth: .u16)
    source.modeDescriptor = try .init(mode: .cmyk, depth: .u16, profile: native.profile)
    source.layers[0].nativeMode = native; source.layers[0].content = .raster(try native.surface())
    let foil = try source.newSpotChannel(name: "Owned foil",
      ink: SpotInk(color: Pixel(1, 0, 0), solidity: 0.62), density: Float(0xebae) / 65535)
    source.alphaChannels = [foil]
    var separated = source
    try InkModeInput.multichannel(in: source).apply(to: &separated)
    let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(separated, format: .psb))
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      store.session = EditorSession(document: reopened)
      try service.share(document)
      store.beginDocumentMode(.cmyk, depth: .u16)
      let workspace = try XCTUnwrap(store.documentModeWorkspace)
      await workspace.task?.value
      XCTAssertTrue(workspace.ready, workspace.error ?? "The CMYK preview did not finish.")
      XCTAssertEqual(store.document, reopened)
      store.commitDocumentMode()
      await workspace.commitTask?.value
      XCTAssertNil(workspace.error)
      let restored = store.document
      let components = try XCTUnwrap(restored.layers[0].nativeMode)
      XCTAssertEqual(values.indices.map { components.rawWord(component: $0, index: 1) }, values)
      XCTAssertEqual(restored.alphaChannels?.first?.name, foil.name)
      XCTAssertEqual(restored.alphaChannels?.first?.spot, foil.spot)
      XCTAssertEqual(restored.alphaChannels?.first?.pixels.pixel(x: 1, y: 0).r, Float(0xebae) / 65535)
      await store.undo()
      XCTAssertEqual(store.document, reopened)

      let response = try await helper.edit(service, document, "document.convertMode", ["mode": "cmyk", "depth": 16])
      XCTAssertEqual(response, 200)
      XCTAssertEqual(store.document, restored)
    }
  }

  @MainActor func testLayeredCMYKPreviewAndHTTPShareAllFourNativePlates() async throws {
    var source = try CraftDocument(width: 2, height: 1, depth: .u16)
    let backWords: [UInt32] = [4900, 15400, 28500, 49700]
    let frontWords: [UInt32] = [62000, 13600, 22300, 38000]
    let back = try NativeModeRaster.RowBuilder(width: 2, height: 1, mode: .cmyk, depth: .u16)
    let front = try NativeModeRaster.RowBuilder(width: 1, height: 1, mode: .cmyk, depth: .u16)
    for i in backWords.indices {
      try back.fill(component: i, word: backWords[i])
      try front.fill(component: i, word: frontWords[i])
    }
    try back.fill(component: 4, word: 65535); try front.fill(component: 4, word: 65535)
    let bottom = try back.finish(), top = try front.finish()
    source.modeDescriptor = try .init(mode: .cmyk, depth: .u16, profile: bottom.profile)
    source.layers[0].nativeMode = bottom; source.layers[0].content = .raster(try bottom.surface())
    var patch = Layer(name: "Patch", content: .raster(try top.surface()))
    patch.nativeMode = top; source.layers.append(patch)

    let original = source
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      store.session = EditorSession(document: original)
      try service.share(document)
      store.beginInkMode(.multichannel)
      let workspace = try XCTUnwrap(store.inkModeWorkspace)
      await workspace.task?.value
      XCTAssertFalse(workspace.ready)
      workspace.update { $0.mergeVisible = true }
      await workspace.task?.value
      XCTAssertTrue(workspace.ready, workspace.error ?? "The mode preview is unavailable.")
      XCTAssertEqual(store.document, original)
      store.commitInkMode()
      await workspace.commitTask?.value
      XCTAssertNil(workspace.error)
      let native = store.document
      let plates = try native.multichannelRaster().plates
      XCTAssertEqual(plates.map { $0.samples.rawWord(at: 0) }, frontWords)
      XCTAssertEqual(plates.map { $0.samples.rawWord(at: 1) }, backWords)
      await store.undo()
      XCTAssertEqual(store.document, original)

      let status = try await helper.edit(service, document, "document.convertMultichannel",
        ["mergeVisible": true, "plateIDs": workspace.request.plateIDs.map(\.uuidString)])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.document, native)
      let limits = try XCTUnwrap(InkModeAPI.capabilities["largeMultichannel"] as? [String: Any])
      XCTAssertEqual(limits["nativeLayeredSeparationModes"] as? [String], ["cmyk", "lab"])
    }
  }

  @MainActor func testHTTPConversionDownloadAndUndoKeepSpotInkSeparate() async throws {
    var original = try CraftDocument(width: 3, height: 2)
    let spot = try original.newSpotChannel(name: "Owned Orange",
      ink: SpotInk(color: Pixel(1, 0, 0), solidity: 0.64), density: Float(177) / 255)
    original.alphaChannels = [spot]
    let source = original
    let helper = AutomationTests(), files = DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: source)
      try service.share(document)
      service.setDocumentTransfersEnabled(true)
      let id = try XCTUnwrap(service.shares.first?.id)
      let request = InkModeRequest(.multichannel, document: source)
      var expected = source
      try request.command(in: source).apply(to: &expected)
      let conversion = try await helper.edit(service, document, "document.convertMultichannel",
        ["plateIDs": request.plateIDs.map(\.uuidString)])
      XCTAssertEqual(conversion, 200)
      XCTAssertEqual(document.store.document, expected)
      for format in ["psd", "psb"] {
        let output = try await files.request(service, path: "/v1/documents/\(id)/file.\(format)",
          headers: ["X-Photato-Export-Options": #"{"psdCompositeCompression":"raw"}"#])
        XCTAssertEqual(output.0.statusCode, 200)
        let restored = try PSDCodec.read(output.1)
        let ink = try XCTUnwrap(restored.multichannelRaster().plates.last)
        XCTAssertEqual(ink.name, spot.name)
        XCTAssertEqual(ink.color, spot.spot?.color)
        XCTAssertEqual(ink.solidity, spot.spot?.solidity)
        XCTAssertEqual(ink.samples.rawWord(at: 0), 177)
        XCTAssertNil(restored.alphaChannels)
      }
      XCTAssertEqual(document.store.document, expected)
      let undo = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(document.store.document, source)
    }
  }

  @MainActor func testNative48HTTPPreservesInkDataAndCanExitLayerlessMode() async throws {
    let gray = try InkPlane(width: 3, height: 1, bytes: Data([0, 128, 255]))
    let duo = try CraftDocument(width: 3, height: 1).replacingInkMode(.duotone(.init(gray: gray,
      settings: .init(inks: [.init(name: "Blue", color: Pixel(0.1, 0.2, 0.8))]))))
    var multi = duo; try InkModeInput.multichannel(in: duo).apply(to: &multi)
    let helper = AutomationTests(), files = DocumentIOWorkflowTests()
    for original in [duo, multi] {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        document.store.session = EditorSession(document: original)
        try service.share(document); service.setDocumentTransfersEnabled(true)
        let share = try XCTUnwrap(service.shares.first), route = "/v1/documents/\(share.id)/file.photato"
        XCTAssertTrue(document.store.canBeginDocumentMode)
        XCTAssertEqual(document.store.documentModeState["components"] as? [String], original.colorChannelNames)
        for version in [nil, "47"] as [String?] {
          let rejected = try await files.request(service, path: route, headers: version.map { ["X-Photato-Archive-Version": $0] } ?? [:])
          XCTAssertEqual(rejected.0.statusCode, 422)
          XCTAssertTrue(String(decoding: rejected.1, as: UTF8.self).contains("48"))
        }
        let native = try await files.request(service, path: route, headers: ["X-Photato-Archive-Version": "48"])
        XCTAssertEqual(native.0.statusCode, 200)
        XCTAssertTrue(try NativeArchive.decode(native.1) == original)
        let stale = try await files.request(service, path: route, headers: ["X-Photato-Archive-Version": "48", "X-Photato-Revision": "stale"])
        XCTAssertEqual(stale.0.statusCode, 409)
        let imported = try await files.request(service, path: "/v1/documents/import", data: native.1, type: "application/vnd.photato.document")
        XCTAssertEqual(imported.0.statusCode, 201)
        let reopened = try XCTUnwrap(service.controller.documents.compactMap { $0 as? CraftNSDocument }.first { $0 !== document })
        XCTAssertTrue(reopened.store.document == original)
        reopened.updateChangeCount(.changeCleared); reopened.close()
        var expected = original; try Command.rotateCanvas(.clockwise).apply(to: &expected)
        let rotation = try await helper.edit(service, document, "document.rotate", ["turn": "clockwise"])
        XCTAssertEqual(rotation, 200); XCTAssertTrue(document.store.document == expected)
        let geometryUndo = try await helper.edit(service, document, "history.undo")
        XCTAssertEqual(geometryUndo, 200); XCTAssertTrue(document.store.document == original)
        let conversion = try await helper.edit(service, document, "document.convertMode", ["mode": "rgb", "depth": 8])
        XCTAssertEqual(conversion, 200); XCTAssertNil(document.store.document.inkMode)
        let undoStatus = try await helper.edit(service, document, "history.undo")
        XCTAssertEqual(undoStatus, 200)
        XCTAssertTrue(document.store.document == original)
        let cap = try XCTUnwrap(AutomationService.documentTransferCapabilities["nativeArchives"] as? [String: Any])
        XCTAssertEqual(cap["pagedSelectionVersion"]as?Int,64); XCTAssertEqual(cap["inkModeVersion"] as? Int, 48); XCTAssertEqual(cap["readVersions"] as? [Int], Array(1...94))
      }
    }
  }
  @MainActor func testLargeCMYKPreviewNativeAndHTTPMatchThroughArchiveAndReturn() async throws {
    let width = 300_000, height = 129
    let last = width * height - 1
    let builder = try NativeModeRaster.RowBuilder(width: width, height: height, mode: .cmyk, depth: .u16)
    for c in 0..<4 { try builder.fill(component: c, word: UInt32(c * 59)) }
    try builder.fill(component: 4, word: 65535)
    var native = try builder.finish()
    try native.set(Float(0xBEEF) / 65535, component: 3, index: last)
    var document = try CraftDocument(width: width, height: height, depth: .u16)
    document.modeDescriptor = try .init(mode: .cmyk, depth: .u16, profile: native.profile)
    document.layers[0].content = .raster(try native.surface())
    document.layers[0].nativeMode = native
    let source = document
    let helper = AutomationTests(), files = DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let store = shared.store
      store.session = EditorSession(document: source)
      try service.share(shared)
      service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first)
      XCTAssertTrue(store.canBeginInkMode(.multichannel))
      store.beginInkMode(.multichannel)
      let workspace = try XCTUnwrap(store.inkModeWorkspace)
      await workspace.task?.value
      XCTAssertTrue(workspace.ready, workspace.error ?? "The mode preview is unavailable.")
      XCTAssertEqual(try XCTUnwrap(workspace.image).width, 2048)
      XCTAssertEqual(try XCTUnwrap(workspace.originalImage).width, 2048)
      XCTAssertEqual(store.document, source)
      store.commitInkMode()
      await workspace.commitTask?.value
      XCTAssertNil(workspace.error)
      let converted = store.document
      let plates = try converted.multichannelRaster().plates
      XCTAssertEqual(plates.map(\.id), workspace.request.plateIDs)
      XCTAssertEqual(plates[3].samples.rawWord(at: last), 0xBEEF)
      XCTAssertEqual(converted.minimumArchiveVersion, 93)
      await store.undo()
      XCTAssertEqual(store.document, source)

      let params = ["plateIDs": workspace.request.plateIDs.map(\.uuidString)]
      let stale = try await helper.edit(service, shared, "document.convertMultichannel", params, revision: "stale")
      XCTAssertEqual(stale, 409)
      XCTAssertEqual(store.document, source)
      let conversion = try await helper.edit(service, shared, "document.convertMultichannel", params)
      XCTAssertEqual(conversion, 200)
      XCTAssertEqual(store.document, converted)
      let saved = try await files.request(service, path: "/v1/documents/\(share.id)/file.photato",
        headers: ["X-Photato-Archive-Version": "93"])
      XCTAssertEqual(saved.0.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decode(saved.1), converted)
      let restored = try await helper.edit(service, shared, "document.convertMode", ["mode": "cmyk", "depth": 16])
      XCTAssertEqual(restored, 200)
      XCTAssertEqual(store.document.layers[0].nativeMode?.rawWord(component: 3, index: last), 0xBEEF)
      let undo = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(store.document, converted)
      let limits = try XCTUnwrap(InkModeAPI.capabilities["largeMultichannel"] as? [String: Any])
      XCTAssertEqual(limits["maximumPixels"] as? Int, Surface.maxPixels)
    }
  }
}
