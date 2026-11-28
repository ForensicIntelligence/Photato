import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftImaging

final class RawHDRPanoramaWorkflowTests: XCTestCase {
  @MainActor func testHDRPanoramaUsesCaptureOrderAndMatchesTheAuthenticatedDNG() async throws {
    _ = NSApplication.shared
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let sequence = try makeSequence(in: folder)
    let defaultsName = "Photato.HDRPanoramaTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(),
      cameraRawPreferences: CameraRawPreferences(defaults: defaults))
    let workspace = RawFilmstripWorkspace(controller: controller)
    defer { workspace.close() }
    workspace.start(Array(sequence.map(\.url).reversed()))
    await workspace.waitUntilIdle()
    XCTAssertFalse(workspace.canMergePanorama(hdr: true))
    workspace.selectAll()
    let selected = workspace.selection
    workspace.beginPanorama(hdr: true)
    let request = try XCTUnwrap(workspace.panoramaRequest)
    XCTAssertTrue(request.hdr)
    XCTAssertEqual(request.photos.map(\.original.url), sequence.map(\.url))
    XCTAssertEqual(request.name, "Capture-6-HDR-Pano")
    workspace.panoramaRequest = nil
    XCTAssertEqual(workspace.selection, selected)
    workspace.beginPanorama(hdr: true)
    let active = try XCTUnwrap(workspace.panoramaRequest)
    let prepared = try RawPanorama.prepareHDRSources(active.photos.map { $0.original.hdrMergeSource(settings: $0.settings) })
    XCTAssertEqual(prepared.bracketSize, 3)
    XCTAssertEqual(prepared.photos.count, 2)
    var settings = active.settings
    settings.projection = .perspective
    settings.autoSettings = false
    let result = try RawPanorama.prepare(prepared.photos, options: settings, name: active.name)
    XCTAssertGreaterThan(result.document.width, 180)
    XCTAssertNotNil(result.crop)
    XCTAssertNotNil(result.preview)
    let destination = folder.appendingPathComponent(active.name + ".dng")
    let saved = try await workspace.savePanorama(result, to: destination, requestID: active.id)
    workspace.acceptPanorama(saved, requestID: active.id, settings: settings)
    XCTAssertEqual(workspace.photos.count, 7)
    XCTAssertEqual(workspace.activeSettings?.crop, result.crop)
    XCTAssertEqual(workspace.selection, [saved.id])
    let data = try Data(contentsOf: destination)
    for input in sequence { XCTAssertEqual(try Data(contentsOf: input.url), input.data) }

    let layers = try sequence.map { try XCTUnwrap(RawSourceIO.open($0.data, fileName: $0.url.lastPathComponent).layers.first) }
    var document = try CraftDocument(width: 180, height: 176, depth: .u16, name: "Brackets")
    document.layers = layers
    document.activeLayerID = layers[0].id
    let original = document
    let tests = AutomationTests()
    try await tests.withService(pressedMouseButtons: { 0 }) { service, _ in
      let shared = CraftNSDocument(model: original)
      service.controller.addDocument(shared)
      defer { shared.close() }
      try service.share(shared)
      let share = try XCTUnwrap(service.shares.last)
      let route = "/v1/documents/\(share.id)/commands"
      let revision = service.revision(shared.store)
      let inputs: [String:Any] = ["layerIDs":layers.map { $0.id.uuidString }, "bracketSize":3,
        "projection":"perspective", "autoSettings":false]
      var body: [String:Any] = ["command":"raw.mergeHDRPanorama", "revision":revision, "parameters":inputs]
      service.setDocumentTransfersEnabled(true)
      var invalid = inputs
      invalid["bracketSize"] = 2.5
      body["parameters"] = invalid
      let malformed = try await tests.request(service, path: route, body: body)
      XCTAssertEqual(malformed.0.statusCode, 400)
      body["parameters"] = inputs
      let downloaded = try await tests.request(service, path: route, body: body)
      XCTAssertEqual(downloaded.0.statusCode, 200)
      XCTAssertEqual(downloaded.0.value(forHTTPHeaderField: "Content-Type"), "image/x-adobe-dng")
      XCTAssertEqual(downloaded.1, data)
      XCTAssertEqual(shared.store.document, original)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      let capabilities = try await tests.request(service, path: "/v1/capabilities")
      let catalogue = try XCTUnwrap(JSONSerialization.jsonObject(with: capabilities.1) as? [String:Any])
      let commands = try XCTUnwrap(catalogue["commands"] as? [[String:Any]])
      XCTAssertEqual(commands.count, AutomationTests.expectedCommandCount)
      XCTAssertTrue(commands.contains { $0["command"] as? String == "raw.mergeHDRPanorama" })
    }
  }

  private func makeSequence(in folder: URL) throws -> [(url: URL, data: Data)] {
    let textureFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PhotoAlign/texture.bin")
    let texture = try Data(contentsOf: textureFile).withUnsafeBytes { raw -> [Float] in
      stride(from: 0, to: raw.count, by: 4).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) }
    }
    let shutters = [60, 120, 30, 50, 100, 25]
    return try shutters.enumerated().map { index, shutter in
      let position = index / 3
      var pixels = try Surface(width: 180, height: 176, depth: .f32, colorEncoding: .linearRGB)
      for y in 0..<pixels.height {
        for x in 0..<pixels.width {
          let value = (0.03 + texture[(y + position * 16) * 256 + x + position * 76] * 0.64) * (60 / Float(shutter))
          let sensor = min(0.99, value)
          pixels.setLinearPixel(x: x, y: y, Pixel(sensor, sensor, sensor, 1))
        }
      }
      let layer = Layer(name: "Capture", content: .raster(pixels))
      var document = try CraftDocument(width: pixels.width, height: pixels.height, depth: .f32, name: layer.name)
      document.layers = [layer]
      document.activeLayerID = layer.id
      let url = folder.appendingPathComponent("Capture-\(shutters.count - index).dng")
      try RawLinearDNG.write(document, to: url)
      let initial = try Data(contentsOf: url)
      let data = exposureMetadata(in: initial, shutter: shutter, capture: index + 1)
      try data.write(to: url, options: .atomic)
      return (url, data)
    }
  }

  private func exposureMetadata(in input: Data, shutter: Int, capture: Int) -> Data {
    func integer(_ offset: Int, bytes: Int) -> Int {
      (0..<bytes).reduce(0) { $0 | Int(input[offset + $1]) << (8 * $1) }
    }
    func little(_ value: Int, bytes: Int) -> Data {
      Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }
    func entry(_ tag: Int, _ type: Int, count: Int = 1, _ value: Int) -> Data {
      little(tag, bytes: 2) + little(type, bytes: 2) + little(count, bytes: 4) + little(value, bytes: 4)
    }
    let root = integer(4, bytes: 4), count = integer(root, bytes: 2)
    let offsets = (0..<count).map { root + 2 + $0 * 12 }
    var fields = Dictionary(uniqueKeysWithValues: offsets.map { (integer($0, bytes: 2), input.subdata(in: $0..<($0 + 12))) })
    var output = input
    if output.count % 2 != 0 { output.append(0) }
    let exposure = output.count
    output += little(1, bytes: 4) + little(shutter, bytes: 4)
    let aperture = output.count
    output += little(8, bytes: 4) + little(1, bytes: 4)
    let timestamp = output.count
    output += Data(String(format: "2026:11:28 14:15:%02d\0", capture).utf8)
    let exif = output.count
    output += little(4, bytes: 2) + entry(33_434, 5, exposure) + entry(33_437, 5, aperture)
      + entry(34_855, 3, 100) + entry(36_867, 2, count: 20, timestamp) + little(0, bytes: 4)
    let updated = output.count
    fields[34_665] = entry(34_665, 4, exif)
    output += little(fields.count, bytes: 2)
    for key in fields.keys.sorted() { output += fields[key]! }
    output += little(0, bytes: 4)
    output.replaceSubrange(4..<8, with: little(updated, bytes: 4))
    return output
  }
}
