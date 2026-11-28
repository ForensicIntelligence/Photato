import AppKit
import CryptoKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AutomationOpeningTests: XCTestCase {
  @MainActor func upload(_ service: AutomationService, bytes: Data, type: String,
    format: String? = nil) async throws -> (HTTPURLResponse, Data)
  {
    var request = URLRequest(url: URL(string: try XCTUnwrap(service.endpoint) + "/v1/documents/import")!)
    request.httpMethod = "POST"; request.httpBody = bytes
    request.setValue("Bearer \(try XCTUnwrap(service.token))", forHTTPHeaderField: "Authorization")
    request.setValue(type, forHTTPHeaderField: "Content-Type")
    if let format { request.setValue(format, forHTTPHeaderField: "X-Photato-Open-Format") }
    let (data, response) = try await URLSession.shared.data(for: request)
    return (try XCTUnwrap(response as? HTTPURLResponse), data)
  }
  @MainActor func testHTTPSelectedNativeAndRasterFormatsMatchDesktopAndRejectMismatches() async throws {
    let api = AutomationTests()
    try await api.withService { service, original in
      let c = service.controller
      defer { for doc in c.documents where doc !== original { doc.close() } }
      service.setDocumentTransfersEnabled(true)
      let model = try CraftDocument(width: 4, height: 3)
      for format in [DocumentIO.Format.native, .psd, .psb, .png] {
        let bytes = try DocumentIO.encode(model, format: format)
        let bad = try await upload(service, bytes: bytes, type: "application/octet-stream", format: "jpeg")
        XCTAssertEqual(bad.0.statusCode, 422)
        XCTAssertEqual(service.shares.count, 0)
        let valid = try await upload(service, bytes: bytes, type: "application/octet-stream", format: format.rawValue)
        XCTAssertEqual(valid.0.statusCode, 201, String(decoding: valid.1, as: UTF8.self))
        let doc = try XCTUnwrap(service.shares.last?.document)
        var expected = try DocumentIO.decodeUpload(bytes, native: format == .native, name: "Imported Image")
        let actual = doc.store.document
        if format != .native {
          // Independent image decodes allocate document/layer identities.
          // This one-layer fixture must otherwise preserve the complete model.
          XCTAssertEqual(expected.layers.count, 1)
          XCTAssertEqual(actual.layers.count, 1)
          expected.id = actual.id
          expected.layers[0].id = actual.layers[0].id
          expected.activeLayerID = actual.activeLayerID
          if let left = actual.sourceMetadata?["imageIOProperties"],
            let right = expected.sourceMetadata?["imageIOProperties"]
          {
            // ImageIO's binary plist dictionary order is not canonical.
            let properties = try PropertyListSerialization.propertyList(from: left, format: nil) as? NSDictionary
            let expectedProperties = try PropertyListSerialization.propertyList(from: right, format: nil) as? NSDictionary
            XCTAssertNotNil(properties)
            XCTAssertEqual(properties, expectedProperties)
            expected.sourceMetadata?["imageIOProperties"] = left
          }
        }
        XCTAssertTrue(actual == expected, "\(format.rawValue) imported model differs after identity normalization")
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertNil(doc.fileURL)
        service.revoke(try XCTUnwrap(service.shares.last?.id)); doc.close()
      }
      let bytes = try NativeArchive.encode(model)
      let auto = try await upload(service, bytes: bytes, type: "image/png", format: "automatic")
      XCTAssertEqual(auto.0.statusCode, 201)
      XCTAssertEqual(service.shares.last?.document?.store.document, model)
      let invalid = try await upload(service, bytes: bytes, type: "application/octet-stream", format: "bad")
      XCTAssertEqual(invalid.0.statusCode, 400)
      let unsupported = try await upload(service, bytes: bytes, type: "application/octet-stream")
      XCTAssertEqual(unsupported.0.statusCode, 415)
      let legacy = try await upload(service, bytes: bytes, type: "image/png")
      XCTAssertEqual(legacy.0.statusCode, 422)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }

  @MainActor func testPNGImportThroughPhotatoAndAdobeKeepsHiddenRGB() async throws {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setDocumentTransfersEnabled(true)
      for depth in [PixelDepth.u8, .u16] {
        var pixels = try Surface(width: 3, height: 2, depth: depth)
        let minimumOpacity: Float = depth == .u8 ? 1 / 255 : 1 / 65535
        pixels.setPixel(x: 0, y: 0, Pixel(206 / 255, 173 / 255, 204 / 255, 0))
        pixels.setPixel(x: 1, y: 0, Pixel(25 / 255, 197 / 255, 51 / 255, minimumOpacity))
        let png = try RasterIO.encoded(pixels, options: .init(pngInterlaced: true))
        let expected = try pixels.rgbaData(depth: depth)
        func check(_ model: CraftDocument) throws {
          XCTAssertEqual(model.depth, depth)
          guard case .raster(let raster) = try XCTUnwrap(model.layers.first).content else {
            XCTFail("Expected raw PNG samples on a raster layer.")
            return
          }
          XCTAssertEqual(try raster.rgbaData(depth: depth), expected)
        }
        try check(DocumentIO.decodeUpload(png, native: false, name: "Owned PNG"))
        if depth == .u8 { try check(AdobeActionAssets.decode(png)) }
        let reply = try await upload(service, bytes: png, type: "image/png", format: "png")
        XCTAssertEqual(reply.0.statusCode, 201, String(decoding: reply.1, as: UTF8.self))
        try check(XCTUnwrap(service.shares.last?.document?.store.document))
      }
    }
  }
  @MainActor func testGrayscalePNGImportAndDownloadPreserveTheNativePlanes() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setDocumentTransfersEnabled(true)
      for depth in [PixelDepth.u8, .u16] {
        let maximum: UInt32 = depth == .u8 ? 255 : 65535
        let gray = [maximum - 11, maximum / 2, 3]
        let alpha: [UInt32] = [0, 1, maximum]
        let builder = try NativeModeRaster.RowBuilder(width: 3, height: 1, mode: .grayscale, depth: depth)
        try builder.appendRow(gray, component: 0)
        try builder.appendRow(alpha, component: 1)
        let raster = try builder.finish()
        var document = try CraftDocument(width: 3, height: 1, depth: depth)
        document.modeDescriptor = try .init(mode: .grayscale, depth: depth, profile: raster.profile)
        document.layers[0].nativeMode = raster
        document.layers[0].content = .raster(try raster.surface())
        let input = try DocumentIO.encode(document, format: .png)
        let imported = try await upload(service, bytes: input, type: "image/png", format: "png")
        XCTAssertEqual(imported.0.statusCode, 201, String(decoding: imported.1, as: UTF8.self))
        let share = try XCTUnwrap(service.shares.last)
        let opened = try XCTUnwrap(share.document?.store.document)
        func check(_ document: CraftDocument) throws {
          XCTAssertEqual(document.colorMode, .grayscale)
          XCTAssertEqual(document.depth, depth)
          let native = try XCTUnwrap(document.layers.first?.nativeMode)
          XCTAssertEqual(gray.indices.map { native.rawWord(component: 0, index: $0) }, gray)
          XCTAssertEqual(alpha.indices.map { native.rawWord(component: 1, index: $0) }, alpha)
        }
        try check(opened)
        if depth == .u8 { try check(AdobeActionAssets.decode(input)) }
        let download = try await helper.request(service, path: "/v1/documents/\(share.id)/file.png")
        XCTAssertEqual(download.0.statusCode, 200)
        try check(RasterIO.read(download.1))

        var top = Layer(name: "Top gray", content: .raster(try raster.surface()))
        top.nativeMode = raster
        top.opacity = Float(149) / 255
        document.layers.append(top)
        let layeredInput = try DocumentIO.encode(document, format: .psd)
        let layered = try await upload(service, bytes: layeredInput, type: "application/octet-stream", format: "psd")
        XCTAssertEqual(layered.0.statusCode, 201, String(decoding: layered.1, as: UTF8.self))
        let layeredShare = try XCTUnwrap(service.shares.last)
        let layeredDocument = try XCTUnwrap(layeredShare.document?.store.document)
        XCTAssertEqual(layeredDocument.layers.count, 2)
        let layeredDownload = try await helper.request(service, path: "/v1/documents/\(layeredShare.id)/file.png")
        XCTAssertEqual(layeredDownload.0.statusCode, 200)
        XCTAssertEqual(layeredDownload.1, try DocumentIO.encode(layeredDocument, format: .png))
        let flattened = try XCTUnwrap(RasterIO.read(layeredDownload.1).layers.first?.nativeMode)
        XCTAssertEqual(flattened.rawWord(component: 0, index: 0), maximum)
        XCTAssertEqual(flattened.rawWord(component: 1, index: 0), 0)

        for format in [DocumentIO.Format.psd, .psb] {
          let expected = try DocumentIO.encode(layeredDocument, format: format)
          let file = try await helper.request(service, path: "/v1/documents/\(layeredShare.id)/file.\(format.rawValue)")
          XCTAssertEqual(file.0.statusCode, 200)
          XCTAssertEqual(file.1, expected)
          XCTAssertEqual(file.1.prefix(14).suffix(2), Data([0, 2]))
        }
        let encoding = AutomationEncodingOptionsTests()
        let body = encoding.body(outputs: [encoding.output("image/vnd.adobe.photoshop")])
        let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: body))
        let adobe = try AdobeActionAssets.encode(request, document: layeredDocument)
        XCTAssertEqual(adobe.map(\.data), [try DocumentIO.encode(layeredDocument, format: .psd)])

        let tiffOptions = RasterEncodingOptions(tiffTransparency: false, tiffEmbedProfile: false)
        let optionsFields = DocumentEncodingOptions.json(tiffOptions)
        let optionsHeader = String(decoding: try JSONSerialization.data(withJSONObject: optionsFields), as: UTF8.self)
        let tiff = try await helper.request(service, path: "/v1/documents/\(layeredShare.id)/file.tiff",
          headers: ["X-Photato-Export-Options": optionsHeader])
        let expectedTIFF = try DocumentIO.encode(layeredDocument, format: .tiff, options: tiffOptions)
        XCTAssertEqual(tiff.0.statusCode, 200)
        XCTAssertEqual(tiff.1, expectedTIFF)
        XCTAssertEqual(try RasterIO.read(tiff.1).profileIsUntagged, true)
        let job = encoding.body(outputs: [encoding.output("image/tiff", extra: ["encodingOptions": optionsFields])])
        let jobRequest = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: job), allowPhotatoOptions: true)
        XCTAssertEqual(try AdobeActionAssets.encode(jobRequest, document: layeredDocument).map(\.data), [expectedTIFF])
      }
    }
  }

  @MainActor func testIndexedPNGWithGradedAlphaOpensThroughPhotatoAndAdobeAsRGB() async throws {
    // Owned 17 × 11 Adam7 fixture with duplicate RGB entries and palette alpha 0, 1, 127 and 255.
    let encoded = """
      iVBORw0KGgoAAAANSUhEUgAAABEAAAALAgMAAAGTSb4CAAAAAXNSR0IArs4c6QAAAAxQTFRFHbT1HbT18J0XryLR8pTS/
      AAAAAR0Uk5TAAF//zf0hhkAAAAXSURBVHicY2RghMBV1xhXgSjGuwyPGcsZToLpJfIi+wAAABdJREFUuwyMHQxAHqMSA
      5T9n4GB4SCQy8BwjzESTxNpAAAAEElEQVQUSL4GCjIw/ICIAwCr/hJOXnjp+wAAAABJRU5ErkJggg==
      """
    let png = try XCTUnwrap(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters))
    let expected = "e961e9100f3b121b3961037561b359114fed43eebba105bebe7fbe79e004a483"
    func check(_ document: CraftDocument) throws {
      XCTAssertEqual(document.colorMode, .rgb)
      XCTAssertEqual(document.depth, .u8)
      XCTAssertNil(document.restrictedMode)
      guard case .raster(let surface) = try XCTUnwrap(document.layers.first).content else { return XCTFail() }
      let digest = try SHA256.hash(data: surface.rgbaData(depth: .u8)).map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(digest, expected)
    }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setDocumentTransfersEnabled(true)
      try check(DocumentIO.decodeUpload(png, native: false, name: "Palette transparency"))
      try check(AdobeActionAssets.decode(png))
      let reply = try await upload(service, bytes: png, type: "image/png", format: "png")
      XCTAssertEqual(reply.0.statusCode, 201, String(decoding: reply.1, as: UTF8.self))
      let share = try XCTUnwrap(service.shares.last)
      let opened = try XCTUnwrap(share.document?.store.document)
      try check(opened)
      let download = try await helper.request(service, path: "/v1/documents/\(share.id)/file.png")
      XCTAssertEqual(download.0.statusCode, 200)
      XCTAssertEqual(download.1, try DocumentIO.encode(opened, format: .png))
      try check(RasterIO.read(download.1))
    }
  }

  @MainActor func testLargerPalettePNGUsesPagedRGBInBothResourcePaths() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/png-paged-palette/paged-ordinary.png")
    let input = try Data(contentsOf: fixture)
    func check(_ document: CraftDocument) throws {
      XCTAssertEqual(document.colorMode, .rgb)
      XCTAssertEqual(document.width, 8193)
      XCTAssertEqual(document.height, 1024)
      guard case .raster(let surface) = try XCTUnwrap(document.layers.first).content else { return XCTFail() }
      XCTAssertGreaterThan(surface.mappedTileCount, 0)
      XCTAssertEqual(surface.pixel(x: 0, y: 0), Pixel(29 / 255, 180 / 255, 245 / 255, 0))
      XCTAssertEqual(surface.pixel(x: 4096, y: 512), Pixel(29 / 255, 180 / 255, 245 / 255, 1 / 255))
      XCTAssertEqual(surface.pixel(x: 8192, y: 1023), Pixel(175 / 255, 34 / 255, 209 / 255, 1))
    }
    try check(AdobeActionAssets.decode(input))
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setDocumentTransfersEnabled(true)
      let reply = try await upload(service, bytes: input, type: "image/png", format: "png")
      XCTAssertEqual(reply.0.statusCode, 201, String(decoding: reply.1, as: UTF8.self))
      try check(XCTUnwrap(service.shares.last?.document?.store.document))
    }
  }

  @MainActor func testNativeOpeningStatePrivacyPermissionsAndExactIDCancellation() async throws {
    let api = AutomationTests()
    try await api.withService { service, original in
      let c = service.controller
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder); c.documentOpening.reader = PreparedLocalDocument.read }
      let url = try DocumentOpeningTests().fixture(folder, name: "private-name.photato")
      let gate = OpeningGate(); defer { gate.release() }
      c.documentOpening.reader = { url, format in gate.wait(); try Task.checkCancellation(); return try PreparedLocalDocument.read(url, format: format) }
      let id = try c.documentOpening.begin([url], display: false)
      try await DocumentOpeningTests().wait(gate)
      let stateResponse = try await api.request(service, path: "/v1/document-opening")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateResponse.1) as? [String: Any])
      let schema = try XCTUnwrap(AutomationService.documentOpeningCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      XCTAssertFalse(String(decoding: stateResponse.1, as: UTF8.self).contains("private-name"))
      XCTAssertEqual(state["active"] as? Bool, true)
      let denied = try await api.request(service, path: "/v1/document-opening/cancel", body: ["operationID": id.uuidString])
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      for payload in [["operationID": UUID().uuidString], ["operationID": "bad"], ["operationID": id.uuidString, "extra": "bad"]] {
        let response = try await api.request(service, path: "/v1/document-opening/cancel", body: payload)
        XCTAssertEqual(response.0.statusCode, payload.count == 1 && payload["operationID"] != "bad" ? 409 : 400)
      }
      let media = try await api.request(service, path: "/v1/document-opening/cancel",
        body: ["operationID": id.uuidString], headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      let importing = try await upload(service, bytes: try NativeArchive.encode(CraftDocument(width: 1, height: 1)),
        type: DocumentIO.Format.native.mediaType)
      XCTAssertEqual(importing.0.statusCode, 409)
      let cancel = try await api.request(service, path: "/v1/document-opening/cancel", body: ["operationID": id.uuidString])
      XCTAssertEqual(cancel.0.statusCode, 200)
      gate.release(); await c.documentOpening.task?.value
      XCTAssertEqual(c.documents.count, 1)
      XCTAssertTrue(c.documents[0] === original)
      XCTAssertEqual(c.documentOpening.state?.cancellationRequested, true)
      let stale = try await api.request(service, path: "/v1/document-opening/cancel", body: ["operationID": id.uuidString])
      XCTAssertEqual(stale.0.statusCode, 409)
    }
  }
  @MainActor func testRevokedSelectedUploadCannotPublishAfterWorkerReturns() async throws {
    let gate = OpeningGate(); defer { gate.release() }
    let api = AutomationTests()
    try await api.withService(documentDecoder: { data, native, name in
      gate.wait(); return try DocumentIO.decodeUpload(data, native: native, name: name)
    }) { service, original in
      service.setDocumentTransfersEnabled(true)
      let bytes = try NativeArchive.encode(CraftDocument(width: 4, height: 3))
      let task = Task { try await self.upload(service, bytes: bytes, type: "application/octet-stream", format: "automatic") }
      try await DocumentOpeningTests().wait(gate)
      service.setDocumentTransfersEnabled(false)
      gate.release()
      let response = try await task.value
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertEqual(service.shares.count, 0)
      XCTAssertEqual(service.controller.documents.count, 1)
      XCTAssertTrue(service.controller.documents[0] === original)
    }
  }
  @MainActor func testFinishedCloseDuringUploadStillPreventsLatePublication() async throws {
    let gate = OpeningGate(); defer { gate.release() }
    let api = AutomationTests()
    try await api.withService(documentDecoder: { data, native, name in
      gate.wait(); return try DocumentIO.decodeUpload(data, native: native, name: name)
    }) { service, original in
      service.setDocumentTransfersEnabled(true)
      let bytes = try NativeArchive.encode(CraftDocument(width: 4, height: 3))
      let task = Task { try await self.upload(service, bytes: bytes, type: "application/octet-stream", format: "automatic") }
      try await DocumentOpeningTests().wait(gate)
      let closing = service.controller.documentClosing
      let id = try closing.prepare([original], scope: .all, mode: .discard)
      closing.start(id); await closing.task?.value
      XCTAssertFalse(closing.isActive)
      gate.release()
      let response = try await task.value
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertTrue(service.controller.documents.isEmpty)
      XCTAssertEqual(service.shares.count, 0)
    }
  }

}
