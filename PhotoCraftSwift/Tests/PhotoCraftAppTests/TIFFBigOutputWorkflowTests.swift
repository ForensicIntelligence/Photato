import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFBigOutputWorkflowTests: XCTestCase {
  @MainActor func testBigTIFFNativeControlsAndHTTPDownloadAndSave() async throws {
    let accessory = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff)
    XCTAssertFalse(accessory.tiffBigTIFF.isHidden)
    XCTAssertEqual(accessory.tiffBigTIFF.state, .off)
    XCTAssertNil(accessory.encodingOptions.tiffBigTIFF)
    accessory.tiffBigTIFF.performClick(nil)
    XCTAssertEqual(accessory.encodingOptions.tiffBigTIFF, true)
    accessory.formats.selectItem(withTitle: DocumentIO.Format.png.title)
    accessory.updateFormat()
    XCTAssertTrue(accessory.tiffBigTIFF.isHidden)
    XCTAssertNil(accessory.encodingOptions.tiffBigTIFF)
    accessory.formats.selectItem(withTitle: DocumentIO.Format.tiff.title)
    accessory.updateFormat()
    XCTAssertEqual(accessory.encodingOptions.tiffBigTIFF, true)
    accessory.tiffBigTIFF.performClick(nil)
    XCTAssertEqual(accessory.encodingOptions.tiffBigTIFF, false)
    let restored = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff,
      initialOptions: [.tiff: .init(tiffBigTIFF: true)])
    XCTAssertEqual(restored.encodingOptions.tiffBigTIFF, true)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    var model = try CraftDocument(width: 27, height: 19, depth: .u8)
    model.layers[0].content = .raster(try Surface(width: 27, height: 19, depth: .u8, fill: .white))
    let options = RasterEncodingOptions(tiffCompression: .lzw, tiffImagePyramid: true, tiffBigTIFF: true)
    let fields = DocumentEncodingOptions.json(options)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: model)
      service.setDocumentTransfersEnabled(true)
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let route = "/v1/documents/\(id)/file.tiff"
      let download = try await helper.request(service, path: route, headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(download.0.statusCode, 200, String(decoding: download.1, as: UTF8.self))
      XCTAssertEqual(download.1, try RasterIO.encoded(model, type: .tiff, options: options))
      let response = try await helper.edit(service, shared, "document.saveAs",
        ["name": "bigtiff-verification", "format": "tiff", "replace": false, "options": fields])
      XCTAssertEqual(response, 200)
      XCTAssertEqual(shared.rememberedEncodingOptions[.tiff], options)
      let saved = try Data(contentsOf: folder.appendingPathComponent("bigtiff-verification.tiff"))
      XCTAssertEqual(saved.prefix(4), Data([77, 77, 0, 43]))
      let bad = try await helper.request(service, path: route,
        headers: ["X-Photato-Export-Options": #"{"tiffBigTIFF":"true"}"#])
      XCTAssertEqual(bad.0.statusCode, 400)
    }
  }

  @MainActor func testRGB16SpotAndAlphaTIFFOpenAndSaveThroughNativeAndAPIs() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-aux/photoshop-rgb16-alpha-spot.tiff")
    let original = try DocumentIO.read(fixture)
    XCTAssertNil(DocumentIO.persistenceIssue(original, format: .tiff))
    XCTAssertEqual(original.alphaChannels?.map(\.name), ["Proof ink", "Alpha 2"])
    let input = try Data(contentsOf: fixture)
    func check(_ reopened: CraftDocument) throws {
      XCTAssertEqual(reopened.depth, .u16)
      XCTAssertEqual(reopened.alphaChannels?.map(\.name), original.alphaChannels?.map(\.name))
      XCTAssertEqual(reopened.alphaChannels?.map(\.spot), original.alphaChannels?.map(\.spot))
      for (a, b) in zip(try XCTUnwrap(reopened.alphaChannels), try XCTUnwrap(original.alphaChannels)) {
        XCTAssertEqual(try a.pixels.rgbaData(depth: .u16), try b.pixels.rgbaData(depth: .u16))
      }
    }
    try check(AdobeActionAssets.decode(input))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let options = RasterEncodingOptions(tiffCompression: .zip, tiffLayers: true,
      tiffTransparency: false, tiffBigTIFF: true)
    let native = directory.appendingPathComponent("native.tiff")
    try RasterIO.write(original, to: native, type: .tiff, options: options)
    let fields = DocumentEncodingOptions.json(options)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    let automation = AutomationTests()
    try await automation.withService(pressedMouseButtons: { 0 }) { service, shared in
      defer { for document in service.controller.documents where document !== shared { document.close() } }
      service.setDocumentTransfersEnabled(true)
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(directory)
      let upload = try await AutomationOpeningTests().upload(service, bytes: input,
        type: "image/tiff", format: "tiff")
      XCTAssertEqual(upload.0.statusCode, 201, String(decoding: upload.1, as: UTF8.self))
      let share = try XCTUnwrap(service.shares.last)
      let imported = try XCTUnwrap(share.document)
      try check(imported.store.document)
      let download = try await automation.request(service, path: "/v1/documents/\(share.id)/file.tiff",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(download.0.statusCode, 200, String(decoding: download.1, as: UTF8.self))
      XCTAssertEqual(download.1, try Data(contentsOf: native))
      let saved = try await automation.edit(service, imported, "document.saveAs",
        ["name": "channels", "format": "tiff", "replace": false, "options": fields])
      XCTAssertEqual(saved, 200)
      try check(DocumentIO.read(directory.appendingPathComponent("channels.tiff")))
    }
  }


  @MainActor func testTIFFCopyOptionsKeepFlatNamedChannelsThroughBothAPIs() async throws {
    let accessory = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff, depth: .u8,
      hasAlphaChannels: true, hasSpotColors: true)
    XCTAssertEqual(accessory.tiffLayers.state, .off)
    XCTAssertEqual(accessory.tiffAlphaChannels.state, .on)
    XCTAssertEqual(accessory.tiffSpotColors.state, .on)
    XCTAssertEqual(accessory.encodingOptions.tiffAlphaChannels, true)
    accessory.tiffAlphaChannels.performClick(nil)
    XCTAssertEqual(accessory.encodingOptions.tiffAlphaChannels, false)
    XCTAssertEqual(accessory.encodingOptions.tiffSpotColors, true)
    let jpegIndex = try XCTUnwrap(RasterEncodingOptions.TIFFCompression.allCases.firstIndex(of: .jpeg))
    accessory.tiffCompression.selectItem(at: jpegIndex + 1)
    accessory.updateTIFFCompression()
    XCTAssertFalse(accessory.tiffSpotColors.isEnabled)
    XCTAssertEqual(accessory.encodingOptions.tiffSpotColors, false)
    accessory.tiffCompression.selectItem(at: 0)
    accessory.updateTIFFCompression()
    XCTAssertEqual(accessory.encodingOptions.tiffAlphaChannels, false)
    XCTAssertEqual(accessory.encodingOptions.tiffSpotColors, true)
    accessory.formats.selectItem(withTitle: DocumentIO.Format.png.title)
    accessory.updateFormat()
    XCTAssertNil(accessory.encodingOptions.tiffSpotColors)

    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-flat-aux/photoshop-flat-rgb16-aux.tiff")
    let bytes = try Data(contentsOf: fixture)
    let original = try DocumentIO.read(fixture)
    XCTAssertEqual(try AdobeActionAssets.decode(bytes).alphaChannels?.map(\.name), ["Proof ink", "Alpha 2"])
    let options = RasterEncodingOptions(tiffCompression: .zip, tiffLayers: false,
      tiffTransparency: false, tiffBigTIFF: true, tiffAlphaChannels: false, tiffSpotColors: true)
    let fields = DocumentEncodingOptions.json(options)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    let automation = AutomationTests()
    try await automation.withService(pressedMouseButtons: { 0 }) { service, shared in
      defer { for document in service.controller.documents where document !== shared { document.close() } }
      service.setDocumentTransfersEnabled(true)
      let upload = try await AutomationOpeningTests().upload(service, bytes: bytes,
        type: "image/tiff", format: "tiff")
      XCTAssertEqual(upload.0.statusCode, 201, String(decoding: upload.1, as: UTF8.self))
      let share = try XCTUnwrap(service.shares.last)
      XCTAssertEqual(share.document?.store.document.alphaChannels?.map(\.name), ["Proof ink", "Alpha 2"])
      let route = "/v1/documents/\(share.id)/file.tiff"
      let download = try await automation.request(service, path: route, headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(download.0.statusCode, 200, String(decoding: download.1, as: UTF8.self))
      XCTAssertEqual(download.1, try RasterIO.encoded(original, type: .tiff, options: options))
      let output = try AdobeActionAssets.decode(download.1)
      XCTAssertEqual(output.layers.count, 1)
      XCTAssertEqual(output.alphaChannels?.map(\.name), ["Proof ink"])
      let malformed = try await automation.request(service, path: route,
        headers: ["X-Photato-Export-Options": #"{"tiffSpotColors":1}"#])
      XCTAssertEqual(malformed.0.statusCode, 400)
    }
  }


  @MainActor func testRGB16TIFFMatteMatchesAuthenticatedDownload() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-rgb16-matte/stack.psd")
    let original = try DocumentIO.read(fixture)
    let accessory = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff, depth: .u16)
    accessory.tiffTransparency.performClick(nil)
    let options = accessory.encodingOptions
    XCTAssertEqual(options.tiffTransparency, false)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: DocumentEncodingOptions.json(options)), as: UTF8.self)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
    defer { try? FileManager.default.removeItem(at: url) }
    try RasterIO.write(original, to: url, type: .tiff, options: options)
    let native = try Data(contentsOf: url)
    let automation = AutomationTests()
    try await automation.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: original)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let share = try XCTUnwrap(service.shares.first)
      let download = try await automation.request(service, path: "/v1/documents/\(share.id)/file.tiff",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(download.0.statusCode, 200, String(decoding: download.1, as: UTF8.self))
      XCTAssertEqual(download.1, native)
      let opened = try AdobeActionAssets.decode(download.1)
      XCTAssertEqual(opened.depth, .u16)
      XCTAssertEqual(opened.layers.count, 1)
      XCTAssertEqual(shared.store.document.layers.map(\.name), original.layers.map(\.name))
    }
  }


  @MainActor func testActiveQuickMaskThroughNativeOpenSaveAndAuthenticatedTIFFDownload() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-quick-mask/photoshop-quick-mask-with-saved-channels.tiff")
    let document = try DocumentIO.read(fixture)
    let original = try XCTUnwrap(document.quickMask)
    XCTAssertNil(DocumentIO.persistenceIssue(document, format: .tiff))
    XCTAssertNotNil(DocumentIO.persistenceIssue(document, format: .tiff, options: .init(tiffLayers: false)))
    let actionInput = try AdobeActionAssets.decode(Data(contentsOf: fixture))
    XCTAssertEqual(actionInput.quickMask?.psdIdentifier, original.psdIdentifier)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let options = RasterEncodingOptions(tiffCompression: .zip, tiffLayers: true,
      tiffTransparency: true, tiffBigTIFF: true, tiffAlphaChannels: false, tiffSpotColors: false)
    let fields = DocumentEncodingOptions.json(options)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: document)
      service.setDocumentTransfersEnabled(true)
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder)
      try service.share(shared)
      let share = try XCTUnwrap(service.shares.first)
      let response = try await helper.request(service, path: "/v1/documents/\(share.id)/file.tiff",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(response.0.statusCode, 200, String(decoding: response.1, as: UTF8.self))
      let downloaded = try RasterIO.read(response.1)
      XCTAssertNil(downloaded.alphaChannels)
      let quickMask = try XCTUnwrap(downloaded.quickMask)
      XCTAssertEqual(quickMask.name, original.name)
      XCTAssertEqual(quickMask.psdQuickMaskInitiallyEmpty, original.psdQuickMaskInitiallyEmpty)
      XCTAssertEqual(try quickMask.pixels.rgbaData(depth: .u16), try original.pixels.rgbaData(depth: .u16))
      let saved = try await helper.edit(service, shared, "document.saveAs",
        ["name": "quick-mask", "format": "tiff", "replace": false, "options": fields])
      XCTAssertEqual(saved, 200)
      XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("quick-mask.tiff")), response.1)
      XCTAssertNotNil(shared.store.document.quickMask)
      XCTAssertEqual(shared.store.document.alphaChannels?.count, 2)
    }
  }

}
