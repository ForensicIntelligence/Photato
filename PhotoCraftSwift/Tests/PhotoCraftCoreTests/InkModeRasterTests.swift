import Foundation
import XCTest
@testable import PhotoCraftCore

final class InkModeRasterTests: XCTestCase {
  func gray(_ bytes: [UInt8]) throws -> InkPlane { try InkPlane(width: bytes.count, height: 1, bytes: Data(bytes)) }
  func testPlaneSamplesDepthByteOrderAndBounds() throws {
    let bytes = Data([99, 0, 128, 255, 99])
    let eight = try InkPlane(width: 3, height: 1, bytes: bytes[1..<4])
    XCTAssertEqual(eight.bytes, Data([0, 128, 255]))
    let sixteen = try eight.converted(to: .u16)
    XCTAssertEqual(sixteen.bytes, Data([0, 0, 128, 128, 255, 255]))
    XCTAssertEqual(try sixteen.converted(to: .u8), eight)
    XCTAssertEqual(try sixteen.converted(to: .u16, inverted: true).bytes, Data([255, 255, 127, 127, 0, 0]))
    let edited = try sixteen.replacing(offset: 1, values: [1])
    XCTAssertEqual(edited.bytes, Data([0, 0, 255, 255, 255, 255]))
    XCTAssertEqual(sixteen.bytes, Data([0, 0, 128, 128, 255, 255]))
    for values: [Float] in [[.nan], [.infinity], [-0.1], [1.1]] { XCTAssertThrowsError(try eight.replacing(offset: 0, values: values)) }
    XCTAssertThrowsError(try eight.replacing(offset: -1, values: [0]))
    XCTAssertThrowsError(try eight.replacing(offset: 3, values: [0]))
    XCTAssertThrowsError(try InkPlane(width: Int.max, height: Int.max, bytes: Data()))
    XCTAssertThrowsError(try InkPlane(width: 1, height: 1, depth: .f32))
    XCTAssertThrowsError(try InkPlane(width: 2, height: 1, bytes: Data([0])))
  }
  func testDuotoneRetainsGrayAndRendersNamedInks() throws {
    let source = try gray(Array(0...255))
    let monotone = try DuotoneRaster(gray: source, settings: .init())
    let result = try InkModeRaster.duotone(monotone).surface()
    for x in 0..<256 { XCTAssertEqual(result.pixel(x: x, y: 0).r, Float(x) / 255, accuracy: 0.000001) }
    let settings = DuotoneSettings(inks: [.init(name: "Cyan", color: Pixel(0, 1, 1)), .init(name: "Magenta", color: Pixel(1, 0, 1))])
    let duotone = try DuotoneRaster(gray: source, settings: settings)
    let color = try InkModeRaster.duotone(duotone).surface()
    XCTAssertEqual(color.pixel(x: 0, y: 0), Pixel(0, 0, 1))
    XCTAssertEqual(color.pixel(x: 255, y: 0), .white)
    XCTAssertEqual(color.pixel(x: 128, y: 0).r, 128.0 / 255, accuracy: 0.000001)
    XCTAssertEqual(duotone.gray, source)
    let cropped = try InkModeRaster.duotone(duotone).surface(region: .init(x: 32, y: 0, width: 2, height: 1))
    XCTAssertEqual(cropped.pixel(x: 31, y: 0).a, 0); XCTAssertEqual(cropped.pixel(x: 32, y: 0), color.pixel(x: 32, y: 0))
  }
  func testOverprintChangesOnlyDisplayAndEditingInvalidatesRawSettings() throws {
    let source = try gray([0, 128, 255]), inks = [DuotoneInk(name: "Cyan", color: Pixel(0, 1, 1)), DuotoneInk(name: "Magenta", color: Pixel(1, 0, 1))]
    let original = try DuotoneRaster(gray: source, settings: .init(inks: inks), sourceModeData: Data([1, 2, 3]))
    XCTAssertEqual(try original.replacing(settings: original.settings), original)
    var settings = original.settings; settings.overprints = [.init(mask: 3, color: Pixel(0, 1, 0))]
    let changed = try original.replacing(settings: settings), displayed = try InkModeRaster.duotone(changed).surface()
    XCTAssertEqual(displayed.pixel(x: 0, y: 0), Pixel(0, 1, 0)); XCTAssertEqual(displayed.pixel(x: 2, y: 0), .white)
    XCTAssertNil(changed.sourceModeData); XCTAssertEqual(changed.gray, source)
    XCTAssertEqual(try changed.separations(), try original.separations())
    XCTAssertEqual(original.sourceModeData, Data([1, 2, 3]))
  }
  func testInkCurvesProduceIndependentEditablePlates() throws {
    let source = try gray([0, 128, 255])
    let ink = DuotoneInk(name: "Half black", color: .black, curve: [.init(0, 0), .init(1, 0.5)])
    let raster = try DuotoneRaster(gray: source, settings: .init(inks: [ink]))
    var separated = try raster.separations()
    XCTAssertEqual(separated.plates[0].id, ink.id); XCTAssertEqual(separated.plates[0].name, ink.name)
    XCTAssertEqual(separated.plates[0].samples.bytes, Data([128, 63, 0]))
    separated.plates[0].samples = try separated.plates[0].samples.replacing(offset: 0, values: [0])
    XCTAssertEqual(raster.gray, source); XCTAssertEqual(separated.plates[0].samples.bytes, Data([0, 63, 0]))
    XCTAssertEqual(try separated.plates[0].samples.surface(inverted: true).pixel(x: 0, y: 0), .white)
  }
  func testMultichannelInkDensitySolidityOrderAndSixteenBitStorage() throws {
    let plane = try InkPlane(width: 1, height: 1, depth: .u16, value: 1)
    let cyan = InkPlate(name: "Cyan", color: Pixel(0, 1, 1), samples: plane)
    var magenta = InkPlate(name: "Magenta", color: Pixel(1, 0, 1), samples: plane)
    let transparent = try MultichannelRaster(plates: [cyan, magenta])
    XCTAssertEqual(try InkModeRaster.multichannel(transparent).surface().pixel(x: 0, y: 0), Pixel(0, 0, 1))
    magenta.solidity = 1
    let covered = try MultichannelRaster(plates: [cyan, magenta])
    XCTAssertEqual(try InkModeRaster.multichannel(covered).surface().pixel(x: 0, y: 0), magenta.color)
    let reordered = try MultichannelRaster(plates: [magenta, cyan])
    XCTAssertEqual(try InkModeRaster.multichannel(reordered).surface().pixel(x: 0, y: 0), Pixel(0, 0, 1))
    XCTAssertEqual(covered.plates[0].samples.bytes, Data([255, 255])); XCTAssertEqual(covered.depth, .u16)
  }
  func testModelValidationAndCodablePreserveInkIdentityAndBytes() throws {
    let source = try gray([1, 2, 253, 254])
    let settings = DuotoneSettings(inks: [.init(name: "Named ink", color: Pixel(0.2, 0.4, 0.1))])
    let duotone = try DuotoneRaster(gray: source, settings: settings, sourceModeData: Data([7]))
    for original in [InkModeRaster.duotone(duotone), .multichannel(try duotone.separations())] {
      XCTAssertTrue(try JSONDecoder().decode(InkModeRaster.self, from: JSONEncoder().encode(original)) == original)
      XCTAssertTrue(try PropertyListDecoder().decode(InkModeRaster.self, from: PropertyListEncoder().encode(original)) == original)
    }
    var invalid = settings; invalid.inks[0].curve = [.init(0, 0), .init(0, 1), .init(1, 1)]; XCTAssertThrowsError(try invalid.validate())
    invalid = settings; invalid.inks[0].color.a = 0; XCTAssertThrowsError(try invalid.validate())
    invalid = settings; invalid.overprints = [.init(mask: 1, color: .black)]; XCTAssertThrowsError(try invalid.validate())
    XCTAssertThrowsError(try MultichannelRaster(plates: []))
    let plate = InkPlate(name: "Ink", color: .black, samples: source)
    XCTAssertThrowsError(try MultichannelRaster(plates: [plate, plate]))
    XCTAssertThrowsError(try MultichannelRaster(plates: [plate, .init(name: "Other", color: .black, samples: InkPlane(width: 1, height: 1))]))
    XCTAssertThrowsError(try DuotoneRaster(gray: source.converted(to: .u16), settings: settings))
  }
  func testCancelledInkRenderingDoesNotReturnPixels() async throws {
    let source = try gray([0, 128, 255]), raster = try DuotoneRaster(gray: source, settings: .init())
    let worker = Task.detached {
      while !Task.isCancelled { await Task.yield() }
      return try InkModeRaster.duotone(raster).surface()
    }
    worker.cancel()
    do { _ = try await worker.value; XCTFail("Cancelled ink rendering returned an image") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(raster.gray, source)
  }
  func testOriginalRustInkDisplayAndPlateSamplesMatchByteForByte() throws {
    struct Reference: Decodable {
      struct Ink: Decodable { var name: String; var color: [Float]; var curve: [[Float]] }
      struct Case: Decodable { var name: String; var inks: [Ink] }
      var cases: [Case]
    }
    let url = try XCTUnwrap(Bundle.module.url(forResource: "provenance", withExtension: "json", subdirectory: "Fixtures/InkModes"))
    let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
    XCTAssertEqual(reference.cases.count, 4)
    for item in reference.cases {
      let inks = item.inks.map { ink in
        DuotoneInk(name: ink.name, color: Pixel(ink.color[0], ink.color[1], ink.color[2]), curve: ink.curve.map { .init($0[0], $0[1]) })
      }
      let raster = try DuotoneRaster(gray: gray(Array(0...255)), settings: .init(inks: inks))
      let rgba = try InkModeRaster.duotone(raster).surface().rgbaData(depth: .u8)
      var rgb = Data()
      for i in 0..<256 { rgb.append(rgba[i * 4..<i * 4 + 3]) }
      let expectedRGB = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(item.name + ".rgb"))
      XCTAssertEqual(rgb, expectedRGB, "Rust ink display differs: \(item.name)")
      let separated = try raster.separations()
      let plates = separated.plates.reduce(into: Data()) { $0.append($1.samples.bytes) }
      let expectedPlates = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(item.name + ".plates"))
      XCTAssertEqual(plates, expectedPlates, "Rust ink plates differ: \(item.name)")
    }
  }
}
