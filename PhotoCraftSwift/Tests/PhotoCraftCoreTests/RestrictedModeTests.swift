import CoreGraphics
import Foundation
import XCTest
@testable import PhotoCraftCore

final class RestrictedModeTests: XCTestCase {
  private struct Oracle: Decodable {
    struct Indexed: Decodable {
      var name: String; var palette: IndexedPaletteKind; var forced: IndexedForcedColors
      var colors: Int; var dither: IndexedDither; var amount: Float; var paletteFile: String; var indexFile: String
    }
    struct Bitmap: Decodable {
      var name: String; var method: BitmapConversionMethod; var shape: BitmapHalftoneShape
      var angle: Double; var frequency: Double; var outputResolution: Double; var file: String
    }
    var width: Int; var height: Int; var indexed: [Indexed]; var bitmap: [Bitmap]
  }
  private func oracle() throws -> (Oracle, URL) {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "provenance", withExtension: "json", subdirectory: "Fixtures/RestrictedModes"))
    return (try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: url)), url.deletingLastPathComponent())
  }
  func testLicensedRustPaletteAndDitherReferences() throws {
    let (oracle, root) = try oracle(), bytes = try Data(contentsOf: root.appendingPathComponent("input.rgba"))
    let pixels = stride(from: 0, to: bytes.count, by: 4).map { i in
      SIMD4<Float>(Float(bytes[i]) / 255, Float(bytes[i + 1]) / 255, Float(bytes[i + 2]) / 255, Float(bytes[i + 3]) / 255)
    }
    XCTAssertEqual(oracle.indexed.count, 124)
    for entry in oracle.indexed {
      let palette = try PaletteQuantization.palette(pixels, kind: entry.palette, colors: entry.colors, forced: entry.forced.colors([]))
      let actualPalette = Data(palette.flatMap { [$0.red, $0.green, $0.blue] })
      XCTAssertEqual(actualPalette, try Data(contentsOf: root.appendingPathComponent(entry.paletteFile)), entry.name)
      let indices = try PaletteQuantization.indices(pixels, width: oracle.width, palette: palette, dither: entry.dither, amount: entry.amount)
      XCTAssertEqual(indices, try Data(contentsOf: root.appendingPathComponent(entry.indexFile)), entry.name)
    }
  }
  func testLicensedRustBitmapReferences() throws {
    let (oracle, root) = try oracle(), gray = try Data(contentsOf: root.appendingPathComponent("input.gray")).map { Float($0) / 255 }
    XCTAssertEqual(oracle.bitmap.count, 21)
    for entry in oracle.bitmap {
      var settings = BitmapConversionSettings(); settings.method = entry.method
      settings.shape = entry.shape; settings.angle = entry.angle; settings.frequency = entry.frequency; settings.outputResolution = entry.outputResolution
      let raster = try BitmapRaster.converting(gray, width: oracle.width, settings: settings)
      XCTAssertEqual(raster.bits, try Data(contentsOf: root.appendingPathComponent(entry.file)), entry.name)
      XCTAssertEqual(raster.rowStride, 3); XCTAssertEqual(raster.height, 13)
    }
  }
  func testPaletteIdentitySurvivesEditingAndSerialization() throws {
    let red = PaletteColor(255, 0, 0), blue = PaletteColor(0, 0, 255)
    let source = try IndexedRaster(width: 4, height: 1, palette: [red, red, blue], indices: Data([1, 0, 2, 1]))
    let reopened = try JSONDecoder().decode(IndexedRaster.self, from: JSONEncoder().encode(source)); try reopened.validate()
    XCTAssertEqual(reopened, source)
    let changed = try source.replacingPalette([red, .init(0, 255, 0), blue], transparentIndex: nil)
    XCTAssertEqual(changed.indices, Data([1, 0, 2, 1]))
    let pixels = try changed.surface(); XCTAssertEqual(pixels.pixel(x: 0, y: 0), Pixel(0, 1, 0)); XCTAssertEqual(pixels.pixel(x: 1, y: 0), red.pixel)
    let before = try source.surface(); var edited = before; edited.setPixel(x: 2, y: 0, red.pixel)
    XCTAssertEqual(try source.reconciled(with: edited, previous: before).indices, Data([1, 0, 0, 1]))
    XCTAssertEqual(try source.cropped(to: .init(x: 1, y: 0, width: 2, height: 1)).indices, Data([0, 2]))
    XCTAssertThrowsError(try source.replacingPalette([red], transparentIndex: nil))
  }
  func testTransparentEntryIsNeverChosenForOpaquePixels() throws {
    let palette: [PaletteColor] = [.init(0, 0, 0), .init(255, 255, 255), .init(255, 255, 255)]
    let pixels: [SIMD4<Float>] = [SIMD4(1, 1, 1, 1), SIMD4(1, 1, 1, 0), SIMD4(1, 1, 1, 0.5)]
    for dither in IndexedDither.allCases {
      let data = try PaletteQuantization.indices(pixels, width: 3, palette: palette, dither: dither, transparentIndex: 1)
      XCTAssertEqual(data, Data([2, 1, 2]))
      let raster = try IndexedRaster(width: 3, height: 1, palette: palette, indices: data, transparentIndex: 1)
      XCTAssertEqual(try raster.surface().pixel(x: 0, y: 0).a, 1); XCTAssertEqual(try raster.surface().pixel(x: 1, y: 0).a, 0)
    }
    XCTAssertThrowsError(try PaletteQuantization.indices([SIMD4(1, 1, 1, 1)], width: 1, palette: [.init(255, 255, 255)], dither: .none, transparentIndex: 0))
  }
  func testPreserveExactAndNearestTies() throws {
    let pixels = [SIMD4<Float>](repeating: SIMD4(128 / 255, 128 / 255, 128 / 255, 1), count: 64)
    let palette: [PaletteColor] = [.init(127, 127, 127), .init(128, 128, 128), .init(129, 129, 129)]
    for dither in IndexedDither.allCases {
      XCTAssertEqual(try PaletteQuantization.indices(pixels, width: 8, palette: palette, dither: dither, preserveExact: true), Data(repeating: 1, count: 64))
    }
    XCTAssertNotEqual(try PaletteQuantization.indices(pixels, width: 8, palette: palette, dither: .pattern), Data(repeating: 1, count: 64))
    XCTAssertEqual(try PaletteQuantization.indices([SIMD4(0.5, 0.5, 0.5, 1)], width: 1, palette: [.init(0, 0, 0), .init(255, 255, 255)], dither: .none), Data([0]))
  }
  func testIndexedConversionMatteMasterPreviousAndCapacity() throws {
    var source = try Surface(width: 2, height: 1, fill: Pixel(1, 0, 0, 0.5)); source.setPixel(x: 1, y: 0, .clear)
    var settings = IndexedColorSettings(); settings.palette = .exact; settings.forced = .none; settings.dither = .none
    settings.matte = .init(255, 255, 255)
    let matte = try IndexedRaster.converting(source, settings: settings)
    let view = try matte.surface(); XCTAssertEqual(view.pixel(x: 0, y: 0), Pixel(1, 127 / 255, 127 / 255))
    XCTAssertEqual(view.pixel(x: 1, y: 0), .clear)
    settings.transparency = false; settings.matte = nil
    XCTAssertEqual(try IndexedRaster.converting(source, settings: settings).surface().pixel(x: 1, y: 0), .white)
    source = try Surface(width: 1, height: 1, fill: Pixel(1, 0, 0))
    settings.palette = .masterAdaptive; settings.colors = 2
    let other = try Surface(width: 1, height: 1, fill: Pixel(0, 0, 1))
    let master = try IndexedRaster.converting(source, settings: settings, masterSources: [other])
    XCTAssertEqual(Set(master.palette), Set([PaletteColor(255, 0, 0), PaletteColor(0, 0, 255)]))
    XCTAssertThrowsError(try IndexedRaster.converting(source, settings: settings))
    settings.palette = .previous
    XCTAssertEqual(try IndexedRaster.converting(source, settings: settings, previousPalette: master.palette).palette, master.palette)
    XCTAssertThrowsError(try IndexedRaster.converting(source, settings: settings))
    settings.palette = .localAdaptive; settings.transparency = true; settings.forced = .blackWhite
    XCTAssertThrowsError(try IndexedRaster.converting(Surface(width: 2, height: 1), settings: settings))
    settings.forced = .none
    XCTAssertLessThanOrEqual(try IndexedRaster.converting(Surface(width: 2, height: 1), settings: settings).palette.count, 2)
    let all = (0..<256).map { PaletteQuantization.Sample(Float($0) / 255, 0, 0, 1) }
    XCTAssertThrowsError(try PaletteQuantization.palette(all, kind: .exact, colors: 256, forced: [.init(0, 255, 0)]))
  }
  func testPackedBitmapPaddingCropEditingAndRoundTrip() throws {
    let sliced = Data([0xff, 0x80])[1...]
    XCTAssertEqual(try BitmapRaster(width: 1, height: 1, bits: sliced).surface().pixel(x: 0, y: 0), .black)
    let indexSlice = Data([0xff, 0])[1...]
    XCTAssertEqual(try IndexedRaster(width: 1, height: 1, palette: [.init(0, 0, 0)], indices: indexSlice).surface().pixel(x: 0, y: 0), .black)
    let original = try BitmapRaster(width: 9, height: 2, bits: Data([0x81, 0x80, 0x42, 0]))
    XCTAssertEqual(original.rowStride, 2); XCTAssertEqual(original.estimatedBytes, 4)
    let reopened = try JSONDecoder().decode(BitmapRaster.self, from: JSONEncoder().encode(original)); try reopened.validate(); XCTAssertEqual(reopened, original)
    XCTAssertEqual(try original.cropped(to: .init(x: 1, y: 0, width: 8, height: 2)).bits, Data([0x03, 0x84]))
    let before = try original.surface(); var edited = before; edited.setPixel(x: 8, y: 1, .black)
    XCTAssertEqual(try original.reconciled(with: edited, previous: before).bits, Data([0x81, 0x80, 0x42, 0x80]))
    XCTAssertThrowsError(try BitmapRaster(width: 9, height: 1, bits: Data([0, 0x01])))
    XCTAssertThrowsError(try BitmapRaster(width: Int.max, height: 1, bits: Data()))
    XCTAssertThrowsError(try BitmapRaster(width: 1, height: 1, bits: Data()))
    var threshold = BitmapConversionSettings(); threshold.method = .threshold
    XCTAssertEqual(try BitmapRaster.converting([0, 0.49, 0.5, 1], width: 4, settings: threshold).bits, Data([0xc0]))
  }
  func testCustomPatternPhaseAndSolidEndpoints() throws {
    var settings = BitmapConversionSettings(); settings.method = .customPattern
    settings.pattern = try .init(width: 2, height: 2, samples: Data([0, 255, 255, 0]))
    let half = try BitmapRaster.converting([Float](repeating: 0.5, count: 12), width: 4, settings: settings)
    XCTAssertEqual(half.bits, Data([0x50, 0xa0, 0x50]))
    XCTAssertEqual(try BitmapRaster.converting([Float](repeating: 0, count: 4), width: 4, settings: settings).bits, Data([0xf0]))
    XCTAssertEqual(try BitmapRaster.converting([Float](repeating: 1, count: 4), width: 4, settings: settings).bits, Data([0]))
  }
  func testInvalidInputAndCancellation() async throws {
    XCTAssertThrowsError(try PaletteQuantization.indices([SIMD4(0, 0, 0, 1)], width: 0, palette: [.init(0, 0, 0)], dither: .none))
    XCTAssertThrowsError(try PaletteQuantization.palette([SIMD4(.nan, 0, 0, 1)], kind: .exact, colors: 2))
    XCTAssertThrowsError(try IndexedRaster(width: 1, height: 1, palette: [.init(0, 0, 0)], indices: Data([1])))
    XCTAssertThrowsError(try IndexedRaster(width: 1, height: 1, palette: [.init(0, 0, 0)], indices: Data([0]), transparentIndex: -1))
    XCTAssertThrowsError(try BitmapRaster.converting([.infinity], width: 1, settings: .init()))
    var settings = BitmapConversionSettings(); settings.method = .customPattern; XCTAssertThrowsError(try settings.validate())
    settings.method = .halftone; settings.frequency = 0; XCTAssertThrowsError(try settings.validate())
    let work = Task { try Task.checkCancellation(); return try BitmapRaster.converting([0.5], width: 1, settings: .init()) }
    work.cancel(); do { _ = try await work.value; XCTFail("Cancellation ignored") } catch { XCTAssertTrue(error is CancellationError) }
  }
  func testNonSRGBPaletteProfileIsRetainedAndManaged() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)), profile = try XCTUnwrap(space.copyICCData() as Data?)
    var source = try Surface(width: 8, height: 1)
    for x in 0..<8 { source.setPixel(x: x, y: 0, Pixel(Float(x) / 7, Float(7 - x) / 7, Float(x % 3) / 2)) }
    var settings = IndexedColorSettings(); settings.colors = 3; settings.forced = .none
    let managed = try IndexedRaster.converting(source, settings: settings, profile: profile)
    XCTAssertEqual(managed.profile, profile); try managed.validate(); XCTAssertEqual(managed.palette.count, 3)
    let standard = try IndexedRaster.converting(source, settings: settings)
    XCTAssertNotEqual(standard.palette, managed.palette)
  }
}
