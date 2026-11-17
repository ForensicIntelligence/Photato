import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SaveOpacityResponsivenessTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run {
      _ = PhotatoApp.makeDelegate(isolatedSession: true)
      _ = NSApplication.shared
    }
  }

  func testOpacityMatchesVisibleSamplesAndIsolatesCopyOnWrite() throws {
    for depth in PixelDepth.allCases {
      // The allocated tiles still contain transparent padding beyond this image.
      var opaque = try Surface(width: 67, height: 65, depth: depth)
      opaque.mapPixels { _, _, _ in Pixel(0.25, 0.5, 0.75) }
      let mapped = try opaque.spillingTiles(to: RasterTileStore(maximumBytes: 4 * Surface.tileSide * Surface.tileSide * MemoryLayout<Pixel>.stride))
      XCTAssertEqual(mapped.mappedTileCount, 4)

      for source in [opaque, mapped] {
        XCTAssertTrue(try source.isOpaque())
        XCTAssertTrue(try source.allStoredSamplesSatisfy { $0.a == 1 })
        var edited = source
        edited.setPixel(x: 66, y: 64, Pixel(0.4, 0.7, 0.2, 0.5))
        XCTAssertFalse(try edited.isOpaque())
        XCTAssertFalse(try edited.allStoredSamplesSatisfy { $0.a == 1 })
        XCTAssertTrue(try source.isOpaque())
        edited.setPixel(x: 66, y: 64, Pixel(0.4, 0.7, 0.2))
        XCTAssertTrue(try edited.isOpaque())
        XCTAssertTrue(try edited.allStoredSamplesSatisfy { $0.a == 1 })
      }
    }

    let width = 300_000
    var implicit = try Surface(width: width, height: width, fill: .white)
    XCTAssertTrue(try implicit.isOpaque())
    implicit.setPixel(x: width - 1, y: width - 1, .clear)
    XCTAssertFalse(try implicit.isOpaque())
    XCTAssertFalse(try implicit.allStoredSamplesSatisfy { $0.a == 1 })
    XCTAssertEqual(implicit.tileCount, 1)
  }

  func testExactAlphaRetainsJPEGAndOpenEXRSaveCopyPolicy() throws {
    var jpeg = try CraftDocument(width: 65, height: 66)
    var rgb = try Surface(width: 65, height: 66, fill: .white)
    rgb.setPixel(x: 64, y: 65, .black)
    jpeg.layers[0].content = .raster(rgb)
    XCTAssertNil(DocumentIO.persistenceIssue(jpeg, format: .jpeg))
    let encoded = try DocumentIO.encodeForPersistence(jpeg, format: .jpeg)
    XCTAssertEqual(encoded, try DocumentIO.encode(jpeg, format: .jpeg))

    rgb.setPixel(x: 64, y: 65, Pixel(0, 0, 0, 254.0 / 255))
    jpeg.layers[0].content = .raster(rgb)
    XCTAssertEqual(DocumentIO.persistenceIssue(jpeg, format: .jpeg),
      "JPEG cannot retain transparency. Use Save a Copy to choose a matte.")
    XCTAssertThrowsError(try DocumentIO.encodeForPersistence(jpeg, format: .jpeg))
    XCTAssertNil(DocumentIO.persistenceIssue(jpeg, format: .png))

    var exr = try CraftDocument(width: 65, height: 66, depth: .f32)
    var linear = try Surface(width: 65, height: 66, depth: .f32, fill: .white, colorEncoding: .linearRGB)
    let opaqueEXR = RasterEncodingOptions(exrTransparency: false)
    exr.layers[0].content = .raster(linear)
    XCTAssertNil(DocumentIO.persistenceIssue(exr, format: .exr, options: opaqueEXR))
    linear.setLinearPixel(x: 64, y: 65, Pixel(2, 0.5, 0.75, Float(1).nextDown))
    exr.layers[0].content = .raster(linear)
    XCTAssertEqual(DocumentIO.persistenceIssue(exr, format: .exr, options: opaqueEXR),
      "Use Save a Copy to omit transparency.")
    XCTAssertNil(DocumentIO.persistenceIssue(exr, format: .exr))
  }

  @MainActor func testWritableFormatsAndHTTPRefreshAfterAlphaEditAndUndo() async throws {
    let settings = RecoveryPreferencesStore()
    var preferences = settings.value
    preferences.saveDialogFormats = [.jpeg, .png]
    try settings.commit(preferences, revision: settings.revision)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }, recoveryPreferences: settings) { service, document in
      var model = try CraftDocument(width: 65, height: 67)
      let surface = try Surface(width: 65, height: 67, fill: .white)
      model.layers[0].content = .raster(surface)
      document.store.session = EditorSession(document: model)
      await document.store.renderTask?.value
      try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let route = "/v1/documents/\(id)"

      @MainActor func check(expectedDialog: [String]) async throws {
        let revision = service.revision(document.store)
        let result = try await helper.request(service, path: route)
        XCTAssertEqual(result.0.statusCode, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: result.1) as? [String: Any])
        XCTAssertEqual(json["saveFormats"] as? [String], document.saveFormats.map(\.rawValue))
        XCTAssertEqual(json["saveDialogFormats"] as? [String], expectedDialog)
        XCTAssertEqual(document.dialogSaveFormats.map(\.rawValue), expectedDialog)
        XCTAssertEqual(document.writableTypes(for: .saveAsOperation), document.saveFormats.map(\.typeIdentifier))
        XCTAssertEqual(service.revision(document.store), revision)
      }

      try await check(expectedDialog: ["png", "jpeg"])
      var transparent = surface
      transparent.setPixel(x: 64, y: 66, .clear)
      var edited = EditorSession(document: model)
      try edited.execute(.replaceContent(model.layers[0].id, .raster(transparent)))
      document.store.session = edited
      try await check(expectedDialog: ["png"])
      await document.store.undo()
      await document.store.renderTask?.value
      try await check(expectedDialog: ["png", "jpeg"])
      XCTAssertEqual(document.store.document, model)
    }
  }

  func testOwned24And36MPMeasurementsUseExactWritablePolicy() throws {
    guard let directory = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else {
      throw XCTSkip("Timing capture requires an owned output directory.")
    }
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for height in [4_000, 6_000] {
      let width = 6_000
      var pixels = try Surface(width: width, height: height, fill: .white)
      // Allocate every tile through the normal setter. A sparse white fill
      // alone would exercise no pixel scan in either implementation.
      for y in stride(from: 0, to: height, by: Surface.tileSide) {
        for x in stride(from: 0, to: width, by: Surface.tileSide) {
          pixels.setPixel(x: x, y: y, .black)
        }
      }
      let side = Surface.tileSide
      XCTAssertEqual(pixels.tileCount, ((width + side - 1) / side) * ((height + side - 1) / side))
      var model = try CraftDocument(width: width, height: height)
      model.layers[0].content = .raster(pixels)
      let clock = ProcessInfo.processInfo
      var start = clock.systemUptime
      for _ in 0..<2 { XCTAssertTrue(try pixels.allStoredSamplesSatisfy { $0.a == 1 }) }
      let previous = (clock.systemUptime - start) * 1_000
      start = clock.systemUptime
      XCTAssertNil(DocumentIO.persistenceIssue(model, format: .jpeg))
      let cold = (clock.systemUptime - start) * 1_000
      start = clock.systemUptime
      for _ in 0..<120 { XCTAssertNil(DocumentIO.persistenceIssue(model, format: .jpeg)) }
      let warm = (clock.systemUptime - start) * 1_000
      let report: [String: Any] = [
        "width": width, "height": height, "allTilesAllocated": true,
        "previousTwoOpacityChecksMS": previous, "currentFirstJPEGPolicyMS": cold,
        "current120JPEGPolicyReadsMS": warm, "matchingEligibility": true,
        "scope": "Synchronous CPU cost of prior sample predicate and current format policy. No file encoding or display timing.",
      ]
      let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
      try data.write(to: folder.appendingPathComponent("save-opacity-\(height).json"), options: .withoutOverwriting)
    }
  }
}
