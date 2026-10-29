import CoreGraphics
import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeModeRasterTests: XCTestCase {
  func testDefaultLabProfileStaysStableAcrossCreationTimesAndKeepsCustomBytes() async throws {
    let first = try NativeModeProfile.standard(.lab, depth: .u8)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let second = try NativeModeProfile.standard(.lab, depth: .u16)
    XCTAssertEqual(first, second)
    let custom = try XCTUnwrap(CGColorSpace(name: CGColorSpace.genericLab)?.copyICCData() as Data?)
    let raster = try NativeModeRaster(width: 2, height: 1, mode: .lab, depth: .u8, profile: custom)
    XCTAssertEqual(raster.profile, custom)
  }
  func fixture(_ depth: PixelDepth = .u16) throws -> Surface {
    var pixels = try Surface(width: 3, height: 2, depth: depth)
    for y in 0..<2 { for x in 0..<3 {
      pixels.setPixel(x: x, y: y, Pixel(Float(x + 1) / 4, Float(y + 1) / 3, 0.8, Float(x) / 2))
    } }
    return pixels
  }

  func testRealComponentsMatchDirectColorSyncIncludingHiddenColorAndAlpha() throws {
    for mode in DocumentColorMode.componentModes { for depth in [PixelDepth.u8, .u16] {
      let source = try fixture(depth), result = try NativeModeRaster.converting(source, to: mode)
      let native = try XCTUnwrap(mode == .lab ? CGColorSpace(name: CGColorSpace.genericLab) : CGColorSpace(iccData: result.profile as CFData))
      let rgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
      XCTAssertEqual(result.planes.count, mode.componentCount + 1)
      XCTAssertEqual(result.planes.map(\.count), Array(repeating: 6 * result.bytesPerSample, count: mode.componentCount + 1))
      for y in 0..<2 { for x in 0..<3 {
        let p = source.pixel(x: x, y: y), i = y * 3 + x
        let color = try XCTUnwrap(CGColor(colorSpace: rgb, components: [CGFloat(p.r), CGFloat(p.g), CGFloat(p.b), CGFloat(p.a)]))
        let expected = try XCTUnwrap(color.converted(to: native, intent: .relativeColorimetric, options: nil)?.components)
        for c in 0..<mode.componentCount {
          var value = Float(expected[c])
          if mode == .lab { value = c == 0 ? value / 100 : (value + 128) / 255 }
          XCTAssertEqual(result.value(component: c, index: i), depth.quantize(value), "\(mode) \(depth) component \(c)")
        }
        XCTAssertEqual(result.value(component: mode.componentCount, index: i), p.a)
      } }
      let display = try result.surface()
      XCTAssertEqual(display.width, source.width)
      XCTAssertEqual(display.height, source.height)
      for y in 0..<2 { for x in 0..<3 {
        XCTAssertEqual(display.pixel(x: x, y: y).a, source.pixel(x: x, y: y).a)
      } }
    } }
  }

  func testRGB32RetainsHDRSubnormalsSignedZeroAndHiddenColor() throws {
    let words: [UInt32] = [0, 0x80000000, 1, 0x80000001, 0x3f800001, 0xc0500000, 0x7f7fffff]
    var source = try Surface(width: words.count, height: 1, depth: .f32, colorEncoding: .linearRGB)
    for (i, bits) in words.enumerated() { source.setLinearPixel(x: i, y: 0, Pixel(Float(bitPattern: bits), 0.75, -0.25, 0)) }
    let raster = try NativeModeRaster.converting(source, to: .rgb)
    let display = try raster.surface()
    for (i, bits) in words.enumerated() {
      XCTAssertEqual(raster.value(component: 0, index: i).bitPattern, bits)
      XCTAssertTrue(display.linearPixel(x: i, y: 0).hasSameBits(as: source.linearPixel(x: i, y: 0)))
    }
    let restored = try PropertyListDecoder().decode(NativeModeRaster.self, from: PropertyListEncoder().encode(raster))
    XCTAssertEqual(restored.planes, raster.planes)
  }

  func testGray32UsesExtendedColorSyncAndPreservesNumericChannels() throws {
    var source = try Surface(width: 2, height: 1, depth: .f32, colorEncoding: .linearRGB)
    source.setLinearPixel(x: 0, y: 0, Pixel(2, 2, 2, 0.5))
    source.setLinearPixel(x: 1, y: 0, Pixel(2.5, -0.2, 0.75, 0))
    let result = try NativeModeRaster.converting(source, to: .grayscale)
    XCTAssertEqual(result.value(component: 0, index: 0), 2, accuracy: 0.000001)
    let rgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    let retained = try XCTUnwrap(CGColorSpace(iccData: result.profile as CFData))
    let gray = try XCTUnwrap(CGColorSpaceCreateExtended(retained))
    let input = try XCTUnwrap(CGColor(colorSpace: rgb, components: [2.5, -0.2, 0.75, 0]))
    let expected = try XCTUnwrap(input.converted(to: gray, intent: .relativeColorimetric, options: nil)?.components?.first)
    XCTAssertEqual(result.value(component: 0, index: 1), Float(expected))
    let channel = try result.channel(0), display = try result.surface()
    XCTAssertEqual(channel.colorEncoding, .sRGB, "Channel samples are numeric, not RGB transfer encoded")
    XCTAssertEqual(channel.pixel(x: 0, y: 0).r, 2)
    XCTAssertEqual(display.linearPixel(x: 0, y: 0).r, 2, accuracy: 0.000001)
    XCTAssertEqual(try result.replacingChannel(0, with: channel), result)
  }

  func testChannelEditCropAndCacheReconciliationKeepIndependentBlackInk() throws {
    var native = try NativeModeRaster(width: 3, height: 2, mode: .cmyk, depth: .u16)
    for i in 0..<6 { for c in 0..<5 { try native.set(Float(i + c + 1) / 16, component: c, index: i) } }
    let original = native
    let previous = try native.surface()
    XCTAssertEqual(try native.reconciled(with: previous, previous: previous), native)
    var edited = previous
    let old = previous.pixel(x: 1, y: 0)
    edited.setPixel(x: 1, y: 0, Pixel(old.r, old.g, old.b, 0.75))
    let alphaEdit = try native.reconciled(with: edited, previous: previous)
    for c in 0..<4 { XCTAssertEqual(alphaEdit.planes[c], native.planes[c]) }
    XCTAssertEqual(alphaEdit.value(component: 4, index: 1), PixelDepth.u16.quantize(0.75))
    var black = try native.channel(3)
    black.setPixel(x: 2, y: 1, Pixel(0.9, 0.9, 0.9))
    native = try native.replacingChannel(3, with: black)
    for c in [0, 1, 2, 4] { XCTAssertEqual(native.planes[c], original.planes[c]) }
    XCTAssertEqual(native.value(component: 3, index: 5), PixelDepth.u16.quantize(0.9))
    XCTAssertNotEqual(native.planes[3], original.planes[3])
    let crop = try native.cropped(to: IntRect(x: 1, y: 0, width: 2, height: 2))
    for (i, sourceIndex) in [1, 2, 4, 5].enumerated() { XCTAssertEqual(crop.components(index: i), native.components(index: sourceIndex)) }
    XCTAssertThrowsError(try native.cropped(to: IntRect(x: -1, y: 0, width: 2, height: 2)))
    XCTAssertThrowsError(try native.replacingChannel(4, with: black))
    XCTAssertThrowsError(try native.reconciled(with: crop.surface(), previous: previous))
  }

  func testOnlyChangedRGBPixelsRegenerateNativeComponents() throws {
    let source = try fixture(), native = try NativeModeRaster.converting(source, to: .cmyk)
    let before = try native.surface()
    var edited = before
    edited.setPixel(x: 1, y: 1, Pixel(0.9, 0.1, 0.2, 0.5))
    let result = try native.reconciled(with: edited, previous: before)
    let full = try NativeModeRaster.converting(edited, to: .cmyk, profile: native.profile)
    for i in 0..<6 { XCTAssertEqual(result.components(index: i), i == 4 ? full.components(index: i) : native.components(index: i)) }
  }

  func testProfileAndDimensionValidationRejectsMismatchedCorruptAndNonlinearInput() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let profile = try NativeModeProfile.standard(mode, depth: depth)
      XCTAssertNoThrow(try NativeModeProfile.validate(profile, mode: mode, depth: depth))
      var bad = profile; bad[36] = 0
      XCTAssertThrowsError(try NativeModeProfile.validate(bad, mode: mode, depth: depth))
      bad = profile; bad[128...131] = Data([255, 255, 255, 255])
      XCTAssertThrowsError(try NativeModeProfile.validate(bad, mode: mode, depth: depth))
    } }
    XCTAssertThrowsError(try NativeModeProfile.validate(NativeModeProfile.standard(.rgb, depth: .u8), mode: .cmyk, depth: .u8))
    XCTAssertThrowsError(try NativeModeProfile.validate(NativeModeProfile.standard(.grayscale, depth: .u8), mode: .grayscale, depth: .f32))
    XCTAssertThrowsError(try NativeModeRaster(width: Int.max, height: 1, mode: .rgb, depth: .u8))
    XCTAssertThrowsError(try NativeModeRaster(width: 1, height: 0, mode: .rgb, depth: .u8))
    XCTAssertThrowsError(try NativeModeRaster(width: 32768, height: 32768, mode: .rgb, depth: .u8))
    XCTAssertThrowsError(try NativeModeRaster(width: 1, height: 1, mode: .cmyk, depth: .f32))
    var raster = try NativeModeRaster(width: 1, height: 1, mode: .rgb, depth: .f32)
    XCTAssertThrowsError(try raster.set(.infinity, component: 0, index: 0))
    XCTAssertThrowsError(try raster.set(2, component: 3, index: 0))
    XCTAssertThrowsError(try raster.set(0, component: 4, index: 0))
  }

  func testInlineArchiveBudgetsAndCorruptionAreValidated() throws {
    let native = try NativeModeRaster.converting(fixture(), to: .lab)
    let bytes = try PropertyListEncoder().encode(native)
    XCTAssertEqual(try PropertyListDecoder().decode(NativeModeRaster.self, from: bytes), native)
    let budgeted = PropertyListDecoder(); budgeted.userInfo[.rasterDecodeBudget] = RasterDecodeBudget(bytes: 0)
    XCTAssertThrowsError(try budgeted.decode(NativeModeRaster.self, from: bytes)) { XCTAssertTrue($0 is NativeArchiveMemoryLimit) }
    let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
    for replacement: (String, Any) in [("planes", [Data()]), ("width", Int.max), ("profile", Data())] {
      var bad = fields; bad[replacement.0] = replacement.1
      let data = try PropertyListSerialization.data(fromPropertyList: bad, format: .binary, options: 0)
      XCTAssertThrowsError(try PropertyListDecoder().decode(NativeModeRaster.self, from: data))
    }
  }

  private final class Blobs: RasterBlobEncoding, RasterBlobDecoding, @unchecked Sendable {
    var data: [String: Data] = [:]
    func storeBytes(_ bytes: Data) throws -> String {
      let key = bytes.base64EncodedString(); data[key] = bytes; return key
    }
    func bytes(_ digest: String, maximumBytes: Int) throws -> Data {
      guard let bytes = data[digest], bytes.count <= maximumBytes else { throw CraftError.invalid("Missing or oversized test blob") }
      return bytes
    }
    func tile(_ digest: String) throws -> [Pixel] { throw CraftError.invalid("Not a tile") }
  }
  func testArchiveBlobContextRetainsAllPlaneBytesAndRejectsMissingContext() throws {
    let native = try NativeModeRaster.converting(fixture(), to: .cmyk)
    let blobs = Blobs(), encoder = PropertyListEncoder(), decoder = PropertyListDecoder()
    encoder.userInfo[.historyTileEncoder] = blobs; decoder.userInfo[.historyTileDecoder] = blobs
    let data = try encoder.encode(native)
    XCTAssertEqual(try decoder.decode(NativeModeRaster.self, from: data), native)
    XCTAssertThrowsError(try PropertyListDecoder().decode(NativeModeRaster.self, from: data))
    blobs.data.removeAll()
    XCTAssertThrowsError(try decoder.decode(NativeModeRaster.self, from: data))
  }

  func testCancelledConversionDoesNotProducePartialRaster() async throws {
    let source = try fixture()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try NativeModeRaster.converting(source, to: .cmyk)
    }
    do { _ = try await task.value; XCTFail("Cancelled conversion succeeded") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
