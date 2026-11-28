import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class RawLinearDNGTests: XCTestCase {
  func testLinearDNGStoresHalfFloatWordsAndNativeDecoderReadsTheFullImage() throws {
    let (folder, url) = try destination()
    defer { try? FileManager.default.removeItem(at: folder) }
    let width = 512, height = 384
    var pixels = try Surface(width: width, height: height, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<height {
      for x in 0..<width {
        pixels.setLinearPixel(x: x, y: y, Pixel(x < 256 ? 0.125 : 1.5, 0.375, 0.625, 1))
      }
    }
    let document = try image(pixels)
    try RawLinearDNG.write(document, to: url)
    let data = try Data(contentsOf: url)
    let file = try TIFFContainer(data, metadata: false, additionalTags: [254, 50_706, 50_717], inspectSubIFDs: true)
    XCTAssertEqual(try file.scalar(254), 1)
    XCTAssertEqual(try file.scalar(256), 160)
    XCTAssertEqual(file.root.fields[50_706]?.data, Data([1, 4, 0, 0]))
    let raw = try XCTUnwrap(file.root.fields[330]?.children.first)
    func words(_ tag: Int, bytes: Int) throws -> [Int] {
      let field = try XCTUnwrap(raw.fields[tag])
      return (0..<field.count).map { file.order.number(field.data, $0 * bytes, bytes) }
    }
    XCTAssertEqual(try words(262, bytes: 2), [34_892])
    XCTAssertEqual(try words(256, bytes: 4), [width])
    XCTAssertEqual(try words(257, bytes: 4), [height])
    XCTAssertEqual(try words(258, bytes: 2), [16, 16, 16])
    XCTAssertEqual(try words(339, bytes: 2), [3, 3, 3])
    XCTAssertEqual(try words(50_717, bytes: 4), [2, 2, 2])
    let offsets = try words(273, bytes: 4), lengths = try words(279, bytes: 4)
    let stripHeight = try XCTUnwrap(words(278, bytes: 4).first)
    XCTAssertGreaterThan(offsets.count, 1)
    XCTAssertEqual(lengths.reduce(0, +), width * height * 6)
    let dark = [0x3000, 0x3600, 0x3900]
    let light = [0x3E00, 0x3600, 0x3900]
    for (x, y, expected) in [(0, 0, dark), (255, 16, dark), (256, 16, light), (511, 383, light)] {
      let pixelOffset = offsets[y / stripHeight] + (y % stripHeight * width + x) * 6
      XCTAssertEqual((0..<3).map { file.order.number(data, pixelOffset + 2 * $0, 2) }, expected)
    }

    let info = try RawSourceIO.inspect(data)
    XCTAssertEqual(info.type, "com.adobe.raw-image")
    XCTAssertEqual(info.nativeWidth, width)
    XCTAssertEqual(info.nativeHeight, height)
    let reopened = try RawSourceIO.open(data, fileName: url.lastPathComponent, depth: .f32)
    XCTAssertEqual(reopened.width, width)
    XCTAssertEqual(reopened.height, height)
    XCTAssertEqual(reopened.layers.first?.smartObject?.data, data)
  }

  func testAutomaticSettingsChangeTheXMPAndRetainEveryLinearRAWWord() throws {
    let (folder, rawURL) = try destination()
    defer { try? FileManager.default.removeItem(at: folder) }
    let autoURL = folder.appendingPathComponent("Owned-HDR-Auto.dng")
    var pixels = try Surface(width: 512, height: 384, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<pixels.height {
      for x in 0..<pixels.width {
        let shade = Float(y) / Float(pixels.height) * 0.09
        pixels.setLinearPixel(x: x, y: y, Pixel(x < 24 ? 1.10 : shade + 0.065, shade + 0.047, shade + 0.038, 1))
      }
    }
    let original = try image(pixels)
    let settings = try RawHDRMerge.automaticTone(pixels)
    XCTAssertNotEqual(settings.exposure, 0)
    XCTAssertNotEqual(settings.shadows, 0)
    try RawLinearDNG.write(original, to: rawURL)
    try RawLinearDNG.write(original, to: autoURL, settings: settings)

    func sensorPayload(_ data: Data, directory: TIFFContainer) throws -> [Data] {
      let sensor = try XCTUnwrap(directory.root.fields[330]?.children.first)
      let offsets = try XCTUnwrap(sensor.fields[273]), lengths = try XCTUnwrap(sensor.fields[279])
      XCTAssertEqual(offsets.count, lengths.count)
      return (0..<offsets.count).map { index in
        let start = directory.order.number(offsets.data, index * 4, 4)
        let count = directory.order.number(lengths.data, index * 4, 4)
        return data.subdata(in: start..<(start + count))
      }
    }
    let rawData = try Data(contentsOf: rawURL), autoData = try Data(contentsOf: autoURL)
    let raw = try TIFFContainer(rawData, metadata: false, additionalTags: [700], inspectSubIFDs: true)
    let auto = try TIFFContainer(autoData, metadata: false, additionalTags: [700], inspectSubIFDs: true)
    XCTAssertNil(raw.root.fields[700])
    XCTAssertEqual(try CameraRawXMP.read(XCTUnwrap(auto.root.fields[700]?.data)), settings)
    XCTAssertEqual(try sensorPayload(rawData, directory: raw), try sensorPayload(autoData, directory: auto))
  }

  func testPanoramaLinearDNGStoresASeparateUnmattedTransparencyPlane() throws {
    let (folder, url) = try destination()
    defer { try? FileManager.default.removeItem(at: folder) }
    var pixels = try Surface(width: 256, height: 192, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<pixels.height {
      for x in 12..<pixels.width {
        pixels.setLinearPixel(x: x, y: y, Pixel(0.5, 0.625, 0.75, x == 12 ? 0.5 : 1))
      }
    }
    let document = try image(pixels)
    XCTAssertThrowsError(try RawLinearDNG.write(document, to: url))
    try RawLinearDNG.write(document, to: url, preserveTransparency: true)
    let data = try Data(contentsOf: url)
    let file = try TIFFContainer(data, metadata: false, additionalTags: [254], inspectSubIFDs: true)
    let directories = try XCTUnwrap(file.root.fields[330]?.children)
    XCTAssertEqual(directories.count, 2)
    let mask = try XCTUnwrap(directories.first { $0.fields[254]?.data == Data([4, 0, 0, 0]) })
    XCTAssertEqual(mask.fields[262]?.data, Data([4, 0]))
    let offset = file.order.number(try XCTUnwrap(mask.fields[273]?.data), 0, 4)
    XCTAssertEqual(Array(data[offset + 11...offset + 13]), [0, 128, 255])
    let raw = try XCTUnwrap(directories.first { $0 !== mask })
    let samples = file.order.number(try XCTUnwrap(raw.fields[273]?.data), 0, 4)
    XCTAssertEqual(file.order.number(data, samples + 12 * 6, 2), 0x3800)
    let info = try RawSourceIO.inspect(data)
    XCTAssertEqual(info.nativeWidth, 256)
    XCTAssertEqual(info.nativeHeight, 192)
    let decoded = try RawSourceIO.render(data, settings: .init(), depth: .f32).0
    XCTAssertEqual(decoded.linearPixel(x: 11, y: 0).a, 0)
    XCTAssertEqual(decoded.linearPixel(x: 12, y: 0).a, 128.0 / 255.0, accuracy: 0.000_01)
    XCTAssertEqual(decoded.linearPixel(x: 13, y: 0).a, 1)
  }

  func testAutoCropIsEditableAndRetainsTheEntireSensorAndMask() throws {
    let (folder, url) = try destination()
    defer { try? FileManager.default.removeItem(at: folder) }
    var pixels = try Surface(width: 256, height: 192, depth: .f32, colorEncoding: .linearRGB)
    for y in 16..<176 {
      for x in 12..<244 { pixels.setLinearPixel(x: x, y: y, Pixel(0.25, 0.375, 0.5, 1)) }
    }
    let image = try image(pixels)
    let bounds = try RawCropBounds(left: 12.0 / 256.0, top: 16.0 / 192.0,
      right: 244.0 / 256.0, bottom: 176.0 / 192.0)
    try RawLinearDNG.write(image, to: url, preserveTransparency: true, crop: bounds)
    let data = try Data(contentsOf: url)
    let full = try RawSourceIO.inspect(data)
    XCTAssertEqual(full.nativeWidth, 256)
    XCTAssertEqual(full.nativeHeight, 192)
    let opened = try RawSourceIO.open(data, fileName: url.lastPathComponent, depth: .f32)
    XCTAssertEqual(opened.width, 232)
    XCTAssertEqual(opened.height, 160)
    let object = try XCTUnwrap(opened.layers.first?.smartObject)
    XCTAssertEqual(object.data, data)
    XCTAssertEqual(object.rawDevelopment?.crop, bounds)
    let reset = try RawDevelopment.decodeJSON(Data("{\"crop\":null}".utf8), base: XCTUnwrap(object.rawDevelopment))
    let uncropped = try RawSourceIO.render(data, settings: reset, depth: .f32).0
    XCTAssertEqual(uncropped.width, 256)
    XCTAssertEqual(uncropped.height, 192)
    XCTAssertEqual(uncropped.linearPixel(x: 0, y: 0).a, 0)
    XCTAssertEqual(uncropped.linearPixel(x: 12, y: 16).a, 1)
    XCTAssertThrowsError(try RawDevelopment.decodeJSON(Data("{\"crop\":{\"left\":0,\"top\":0,\"right\":-1,\"bottom\":1}}".utf8)))
  }

  func testInvalidLinearSamplesLeaveExistingDestinationUntouched() throws {
    let (folder, url) = try destination()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = Data("Keep the existing file".utf8)
    try original.write(to: url)
    var pixels = try Surface(width: 64, height: 64, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<pixels.height {
      for x in 0..<pixels.width { pixels.setLinearPixel(x: x, y: y, Pixel(0.2, 0.3, 0.4, 1)) }
    }
    pixels.setLinearPixel(x: 1, y: 1, Pixel(-0.2, 0.3, 0.4, 1))
    let document = try image(pixels)
    XCTAssertThrowsError(try RawLinearDNG.write(document, to: url))
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [url.lastPathComponent])
  }

  private func destination() throws -> (URL, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    return (folder, folder.appendingPathComponent("Owned-HDR.dng"))
  }

  private func image(_ surface: Surface) throws -> CraftDocument {
    var document = try CraftDocument(width: surface.width, height: surface.height, depth: .f32)
    let layer = Layer(name: "HDR Merge", content: .raster(surface))
    document.layers = [layer]
    document.activeLayerID = layer.id
    return document
  }
}
