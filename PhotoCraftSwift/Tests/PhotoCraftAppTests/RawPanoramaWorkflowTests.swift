import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftImaging

final class RawPanoramaWorkflowTests: XCTestCase {
  @MainActor func testPanoramaFilmstripAndAuthenticatedDownloadKeepOriginalsAndMatchDNG() async throws {
    _ = NSApplication.shared
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let urls = try inputDocuments().enumerated().map { index, document in
      let url = folder.appendingPathComponent("Pano-\(index + 1).dng")
      try RawLinearDNG.write(document, to: url)
      return url
    }
    let originals = try urls.map { try Data(contentsOf: $0) }
    let defaultsName = "Photato.PanoramaTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(),
      cameraRawPreferences: CameraRawPreferences(defaults: defaults))
    let filmstrip = RawFilmstripWorkspace(controller: controller)
    defer { filmstrip.close() }
    filmstrip.start(urls)
    await filmstrip.waitUntilIdle()
    XCTAssertFalse(filmstrip.canMergePanorama())
    filmstrip.selectAll()
    let originalSelection = filmstrip.selection
    let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
      timestamp: 0, windowNumber: 0, context: nil, characters: "M", charactersIgnoringModifiers: "M",
      isARepeat: false, keyCode: 46))
    XCTAssertTrue(filmstrip.handlePhotoMergeKey(key))
    XCTAssertEqual(filmstrip.panoramaRequest?.skipPreview, true)
    XCTAssertFalse(filmstrip.canMergeHDR())
    filmstrip.panoramaRequest = nil
    XCTAssertEqual(filmstrip.selection, originalSelection)
    filmstrip.beginPanorama()
    let request = try XCTUnwrap(filmstrip.panoramaRequest)
    XCTAssertEqual(request.name, "Pano-1-Pano")
    let view = NSHostingView(rootView: RawFilmstripPanoramaView(workspace: filmstrip, request: request))
    view.frame = NSRect(x: 0, y: 0, width: 790, height: 510)
    view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width, 590)

    let sources = try RawPanorama.prepareSources(request.photos.map { $0.original.hdrMergeSource(settings: $0.settings) })
    var options = request.settings
    options.projection = .perspective
    let panorama = try RawPanorama.prepare(sources, options: options, name: request.name)
    XCTAssertGreaterThan(panorama.document.width, 180)
    XCTAssertGreaterThan(panorama.matchedPoints, 10)
    XCTAssertNotNil(panorama.preview)
    do {
      _ = try await filmstrip.savePanorama(panorama, to: urls[0], requestID: request.id)
      XCTFail("Saving to a source must be rejected.")
    } catch CraftError.invalid { }
    let output = folder.appendingPathComponent(request.name + ".dng")
    let photo = try await filmstrip.savePanorama(panorama, to: output, requestID: request.id)
    filmstrip.acceptPanorama(photo, requestID: request.id, settings: options)
    XCTAssertNil(filmstrip.panoramaRequest)
    XCTAssertEqual(filmstrip.photos.count, 3)
    XCTAssertEqual(filmstrip.selection, [photo.id])
    XCTAssertEqual(filmstrip.activeSettings?.adjustments, panorama.adjustments)
    XCTAssertNotNil(panorama.crop)
    XCTAssertEqual(filmstrip.activeSettings?.crop, panorama.crop)
    filmstrip.resetRawCrop()
    XCTAssertNil(filmstrip.activeSettings?.crop)
    XCTAssertTrue(filmstrip.canUndo)
    filmstrip.undoEdit()
    XCTAssertEqual(filmstrip.activeSettings?.crop, panorama.crop)
    XCTAssertEqual(CameraRawPreferences(defaults: defaults).panoramaMerge, options)
    let expected = try Data(contentsOf: output)
    for (url, bytes) in zip(urls, originals) { XCTAssertEqual(try Data(contentsOf: url), bytes) }

    let layers = try zip(urls, originals).map { url, bytes in
      try XCTUnwrap(RawSourceIO.open(bytes, fileName: url.lastPathComponent).layers.first)
    }
    var source = try CraftDocument(width: 180, height: 176, depth: .u16, name: "RAW panorama inputs")
    source.layers = layers
    source.activeLayerID = layers[0].id
    let sharedSource = source
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, _ in
      let document = CraftNSDocument(model: sharedSource)
      service.controller.addDocument(document)
      defer { document.close() }
      try service.share(document)
      let catalogue = try await api.request(service, path: "/v1/capabilities")
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: catalogue.1) as? [String:Any])
      let commands = try XCTUnwrap(json["commands"] as? [[String:Any]])
      XCTAssertEqual(commands.count, AutomationTests.expectedCommandCount)
      XCTAssertTrue(commands.contains { $0["command"] as? String == "raw.mergePanorama" })
      let raw = try XCTUnwrap(json["rawDevelopment"] as? [String:Any])
      let limits = try XCTUnwrap(raw["panoramaMergeLimits"] as? [String:Int])
      XCTAssertEqual(limits["maximumPixelsPerSource"], 96_000_000)
      XCTAssertEqual(limits["maximumTotalPixels"], 384_000_000)
      XCTAssertEqual(limits["maximumOutputPixels"], 96_000_000)
      XCTAssertEqual(limits["maximumDownloadBytes"], SmartObject.maximumCameraRawSourceBytes)
      let share = try XCTUnwrap(service.shares.last)
      let route = "/v1/documents/\(share.id)/commands"
      let revision = service.revision(document.store)
      let parameters: [String: Any] = ["layerIDs":layers.map { $0.id.uuidString }, "projection":"perspective"]
      let body: [String: Any] = ["command":"raw.mergePanorama", "revision":revision, "parameters":parameters]
      service.setDocumentTransfersEnabled(false)
      let forbidden = try await api.request(service, path: route, body: body)
      XCTAssertEqual(forbidden.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      var invalid = body
      var invalidParameters = parameters
      invalidParameters["boundaryWarp"] = 101
      invalid["parameters"] = invalidParameters
      let rejected = try await api.request(service, path: route, body: invalid)
      XCTAssertEqual(rejected.0.statusCode, 400)
      let response = try await api.request(service, path: route, body: body)
      XCTAssertEqual(response.0.statusCode, 200)
      XCTAssertEqual(response.0.value(forHTTPHeaderField: "Content-Type"), "image/x-adobe-dng")
      XCTAssertEqual(response.0.value(forHTTPHeaderField: "Content-Length"), String(expected.count))
      XCTAssertEqual(response.1, expected)
      XCTAssertEqual(document.store.document, sharedSource)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertEqual(service.revision(document.store), revision)
    }
  }

  func testProjectionBoundaryWarpAndFillEdgesUseTheRegisteredScene() throws {
    let inputs = try inputDocuments()
    for projection in RawPanoramaSettings.Projection.allCases {
      let aligned = try RawPanorama.register(inputs, projection: projection, name: "Owned panorama")
      var options = RawPanoramaSettings()
      options.projection = projection
      options.autoSettings = false
      options.autoCrop = false
      let full = try RawPanorama.finish(aligned, options: options, makePreview: false)
      XCTAssertGreaterThan(full.document.width, 180)
      XCTAssertGreaterThan(full.matchedPoints, 10)
      options.autoCrop = true
      let crop = try RawPanorama.finish(aligned, options: options, makePreview: false)
      XCTAssertLessThanOrEqual(crop.document.width * crop.document.height, full.document.width * full.document.height)
      XCTAssertGreaterThan(crop.document.width, 180)
      for point in [SIMD2(0,0), SIMD2(crop.document.width-1,0), SIMD2(0,crop.document.height-1)] {
        let pixels = try Renderer.composite(crop.document)
        XCTAssertGreaterThanOrEqual(pixels.linearPixel(x: point.x, y: point.y).a, 0.999)
      }
      if projection == .perspective {
        options.autoCrop = false
        options.boundaryWarp = 100
        let warped = try RawPanorama.finish(aligned, options: options, makePreview: false)
        XCTAssertEqual(warped.document.width, full.document.width)
        XCTAssertNotEqual(try Renderer.composite(warped.document), try Renderer.composite(full.document))
        options.boundaryWarp = 0
        options.fillEdges = true
        let filled = try RawPanorama.finish(aligned, options: options, makePreview: false)
        let pixels = try Renderer.composite(filled.document)
        XCTAssertEqual(pixels.linearPixel(x: pixels.width - 1, y: 0).a, 1)
      }
    }
  }

  func testPagedPanoramaMatchesDenseDNGWithCoverageWarpAndCrop() throws {
    let inputs = try inputDocuments()
    let paged = try inputs.map { input -> CraftDocument in
      var copy = input
      guard case .raster(let source) = copy.layers[0].content else { throw CraftError.invalid("Missing fixture raster.") }
      let builder = try Surface.PagedBuilder(width: source.width, height: source.height, depth: .f32, colorEncoding: .linearRGB)
      try builder.append(source, atX: 0, atY: 0)
      copy.layers[0].content = .raster(try builder.finish())
      return copy
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    for projection in RawPanoramaSettings.Projection.allCases {
      let denseScene = try RawPanorama.register(inputs, projection: projection, name: "Dense")
      let pagedScene = try RawPanorama.register(paged, projection: projection, name: "Paged")
      XCTAssertGreaterThan(pagedScene.pixels.mappedBytes, 0)
      XCTAssertEqual(pagedScene.pixels, denseScene.pixels)
      var options = RawPanoramaSettings()
      options.projection = projection
      for warp in [0.0, 64] {
        options.boundaryWarp = warp
        let dense = try RawPanorama.finish(denseScene, options: options, makePreview: false)
        let mapped = try RawPanorama.finish(pagedScene, options: options, makePreview: false)
        XCTAssertEqual(mapped.crop, dense.crop)
        let denseURL = folder.appendingPathComponent("dense.dng")
        let mappedURL = folder.appendingPathComponent("paged.dng")
        try dense.write(to: denseURL)
        try mapped.write(to: mappedURL)
        XCTAssertEqual(try Data(contentsOf: mappedURL), try Data(contentsOf: denseURL))
      }
    }
  }

  private func inputDocuments() throws -> [CraftDocument] {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PhotoAlign/texture.bin")
    let values = try Data(contentsOf: file).withUnsafeBytes { raw -> [Float] in
      stride(from: 0, to: raw.count, by: 4).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) }
    }
    return try (0..<2).map { index in
      var pixels = try Surface(width: 180, height: 176, depth: .f32, colorEncoding: .linearRGB)
      for y in 0..<pixels.height {
        for x in 0..<pixels.width {
          let value = 0.02 + values[(y + index * 16) * 256 + x + index * 76] * 0.78
          pixels.setLinearPixel(x: x, y: y, Pixel(value, value, value, 1))
        }
      }
      let layer = Layer(name: "Exposure \(index + 1)", content: .raster(pixels))
      var document = try CraftDocument(width: pixels.width, height: pixels.height, depth: .f32, name: layer.name)
      document.layers = [layer]
      document.activeLayerID = layer.id
      return document
    }
  }
}
