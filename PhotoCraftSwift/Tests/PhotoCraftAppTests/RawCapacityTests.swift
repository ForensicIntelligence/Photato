import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawCapacityTests: XCTestCase {
  private let small = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng")

  func testRAWOverBothFormerLimitsOpensEditsAndReopensWithOriginalSensor() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let raw = try makeLargeOriginal(in: folder)
    let original = try Data(contentsOf: raw, options: .alwaysMapped)
    XCTAssertGreaterThan(original.count, SmartObject.maximumSourceBytes)
    let prepared = try PreparedLocalDocument.read(raw, format: .raw)
    var document = prepared.model
    XCTAssertEqual(document.width, 8192)
    XCTAssertEqual(document.height, 4608)
    XCTAssertGreaterThan(document.width * document.height, Surface.maximumDensePixels)
    let first = try XCTUnwrap(document.layers.first)
    let object = try XCTUnwrap(first.smartObject)
    XCTAssertTrue(object.sourceBytes.isFileBacked)
    XCTAssertTrue(object.data == original)
    guard case .raster(let sensor) = first.content else { return XCTFail("Expected RAW sensor pixels.") }
    XCTAssertGreaterThan(sensor.mappedTileCount, 0)
    XCTAssertLessThan(sensor.allocatedBytes, 8 * 1024 * 1024)

    var settings = try XCTUnwrap(object.rawDevelopment)
    settings.adjustments.exposure = 0.75
    settings.adjustments.contrast = 12
    settings.adjustments.vibrance = -10
    try RawSourceIO.command(in: document, layerID: first.id, settings: settings).apply(to: &document)
    guard case .raster(let edited) = document.layers[0].content else { return XCTFail("Expected developed pixels.") }
    XCTAssertGreaterThan(edited.mappedTileCount, 0)
    for region in [IntRect(x: 23, y: 10, width: 65, height: 71),
                   IntRect(x: 8095, y: 4539, width: 97, height: 69)] {
      let originalRegion = try sensor.cropped(to: region)
      let expected = try CameraRawEngine.develop(originalRegion, settings: settings.adjustments)
      XCTAssertEqual(try edited.cropped(to: region), expected)
    }
    let archive = folder.appendingPathComponent("Large.photato")
    try NativeArchive.write(document, to: archive)
    let reopened = try NativeArchive.readPaged(archive)
    let reopenedObject = try XCTUnwrap(reopened.layers.first?.smartObject)
    XCTAssertTrue(reopenedObject.sourceBytes.isFileBacked)
    XCTAssertTrue(reopenedObject.data == original)
    XCTAssertEqual(reopenedObject.rawDevelopment, document.layers[0].smartObject?.rawDevelopment)
    XCTAssertTrue(reopened.layers[0].content == document.layers[0].content)
    XCTAssertTrue(try Data(contentsOf: raw, options: .alwaysMapped) == original)
  }

  func testLargeDNGSettingsWriterKeepsOriginalSensorBytes() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try makeLargeOriginal(in: folder)
    let source = try Data(contentsOf: url, options: .alwaysMapped)
    var settings = RawDevelopment()
    settings.adjustments.exposure = 1.25
    let output = try RawSourceIO.dngWithSettings(source, settings: settings)
    XCTAssertGreaterThan(output.count, source.count)
    XCTAssertEqual(output.prefix(4), source.prefix(4))
    XCTAssertNotEqual(output[4..<8], source[4..<8])
    XCTAssertTrue(output[8..<source.count] == source[8..<source.count])
    let reopened = try RawSourceIO.open(output, fileName: "Developed.dng")
    let stored = try XCTUnwrap(reopened.layers[0].smartObject?.rawDevelopment)
    XCTAssertEqual(stored.adjustments.exposure, 1.25)
    XCTAssertTrue(try Data(contentsOf: url, options: .alwaysMapped) == source)
  }

  func testLargeDNGGeometryMustAgreeWithDecoderAndAdmissionBounds() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let fullArea = try makeLargeOriginal(in: folder, name: "At512MP.dng", width: 25_600, height: 20_000, sparse: true)
    let beyondArea = try makeLargeOriginal(in: folder, name: "Beyond512MP.dng", width: 25_600, height: 20_001, sparse: true)
    let fullSide = try makeLargeOriginal(in: folder, name: "At65000.dng", width: 65_000, height: 64, sparse: true)
    let beyondSide = try makeLargeOriginal(in: folder, name: "Beyond65000.dng", width: 65_002, height: 64, sparse: true)
    for (url, w, h) in [(fullArea, 25_600, 20_000), (fullSide, 65_000, 64)] {
      let data = try Data(contentsOf: url, options: .alwaysMapped)
      do {
        let inspected = try RawSourceIO.inspect(data)
        XCTAssertEqual(inspected.nativeWidth, w)
        XCTAssertEqual(inspected.nativeHeight, h)
      } catch {
        XCTAssertTrue(error.localizedDescription.contains("could not render the DNG at its declared size"),
          error.localizedDescription)
      }
    }
    for url in [beyondArea, beyondSide] {
      let data = try Data(contentsOf: url, options: .alwaysMapped)
      XCTAssertThrowsError(try RawSourceIO.inspect(data)) { error in
        XCTAssertTrue(error.localizedDescription.contains("512 megapixels"), error.localizedDescription)
      }
    }
  }

  @MainActor func testAuthenticatedCapabilitiesExposeLocalRAWAndSensorLimits() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      let response = try await helper.request(service, path: "/v1/capabilities")
      XCTAssertEqual(response.0.statusCode, 200)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let raw = try XCTUnwrap(body["rawDevelopment"] as? [String: Any])
      XCTAssertEqual(raw["maximumSourceBytes"] as? Int, 64 * 1024 * 1024)
      XCTAssertEqual(raw["maximumLocalSourceBytes"] as? Int, 2 * 1024 * 1024 * 1024)
      XCTAssertEqual(raw["maximumSensorPixels"] as? Int, 512_000_000)
      XCTAssertEqual(raw["maximumSensorSide"] as? Int, 65_000)
      XCTAssertEqual(raw["maximumSpatialAdjustmentPixels"] as? Int, 512_000_000)
      XCTAssertEqual(raw["limitedLargeAdjustments"] as? [String], [])
      XCTAssertEqual(raw["pagedTone"] as? [String], ["highlights", "shadows", "texture", "clarity", "dehaze"])
      XCTAssertEqual(raw["pagedDetail"] as? [String],
        ["sharpening", "luminanceNoiseReduction", "colorNoiseReduction"])
      XCTAssertEqual(raw["pagedEffects"] as? [String], ["vignette", "grain"])
    }
  }

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  // Enlarge our existing synthetic Bayer fixture while keeping its camera
  // matrix and TIFF/DNG structure. The input stays reproducible without a large binary fixture.
  private func makeLargeOriginal(in folder: URL, name: String = "Owned-Large.dng",
    width: Int = 8192, height: Int = 4608, sparse: Bool = false) throws -> URL {
    let input = try Data(contentsOf: small)
    func u16(_ offset: Int) -> UInt16 {
      input.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
    }
    func u32(_ offset: Int) -> Int {
      input.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))) }
    }
    func word(_ number: Int) -> Data {
      withUnsafeBytes(of: UInt32(number).littleEndian) { Data($0) }
    }
    let index = u32(4)
    let entries = Dictionary(uniqueKeysWithValues: (0..<Int(u16(index))).map { i in
      let offset = index + 2 + i * 12
      return (Int(u16(offset)), offset + 8)
    })
    let firstSample = try u32(XCTUnwrap(entries[273]))
    var header = Data(input.prefix(firstSample))
    let bodyBytes = width * height * 2
    func replace(_ tag: Int, value: Int) throws {
      let offset = try XCTUnwrap(entries[tag])
      header.replaceSubrange(offset..<(offset + 4), with: word(value))
    }
    try replace(256, value: width); try replace(257, value: height)
    try replace(278, value: height); try replace(279, value: bodyBytes)
    for (tag, values) in [(50_720, [width, height]), (50_829, [0, 0, height, width])] {
      let offset = try u32(XCTUnwrap(entries[tag]))
      header.replaceSubrange(offset..<(offset + values.count * 4), with: values.reduce(into: Data()) { $0 += word($1) })
    }
    let url = folder.appendingPathComponent(name)
    if sparse {
      try header.write(to: url)
      let file = try FileHandle(forWritingTo: url)
      defer { try? file.close() }
      try file.truncate(atOffset: UInt64(header.count + bodyBytes))
      return url
    }
    let writer = try AtomicFileWriter(to: url, maximumBytes: header.count + bodyBytes)
    try writer.append(header)
    let band = (0..<(width * Surface.tileSide)).map { i -> UInt16 in
      let x = i % width, y = i / width
      return UInt16(64 + (11 * x + 7 * y + 91 * (x % 2 + y % 2)) % 3950).littleEndian
    }
    let rows = band.withUnsafeBytes { Data($0) }
    for _ in 0..<(height / Surface.tileSide) { try writer.append(rows) }
    try writer.commit()
    return url
  }
}
