import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeComponentBlockTests: XCTestCase {
  func testMaximumAdmittedUniformModesKeepImplicitSamplesAndCaches() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let input = try Surface(width: 4096, height: 2048, depth: depth, fill: Pixel(0.2, 0.4, 0.8, 1))
      let source = try NativeModeRaster.converting(input, to: mode)
      XCTAssertEqual(source.residentComponentEditBytes, 0, "\(mode)/\(depth)")
      XCTAssertTrue(source.isOpaque); XCTAssertEqual(try source.surface().tileCount, 0)
      XCTAssertEqual(try source.channel(0).tileCount, 0)
      var changed = source; try changed.set(0, component: 0, index: 4096 * 2048 - 1)
      XCTAssertLessThan(changed.residentComponentEditBytes, 20000)
      XCTAssertEqual(source.residentComponentEditBytes, 0)
      XCTAssertEqual(changed.rawWord(component: 1, index: 4096 * 2048 - 1), source.rawWord(component: 1, index: 4096 * 2048 - 1))
      XCTAssertThrowsError(try NativeModeRaster(width: 4096, height: 2049, mode: mode, depth: depth))
    } }
  }
  func testSparseFloatDefaultsAndBlockBoundaryKeepExactWords() throws {
    var input = try Surface(width: 8193, height: 1, depth: .f32, fill: Pixel(-0.0, 2, -3, 0.5))
    input = try input.interpretingSamples(as: .linearRGB)
    let words: [UInt32] = [1, 0x80000001, 0x3f800001, 0xc0500000]
    for (i, word) in words.enumerated() { input.setLinearPixel(x: 4094 + i, y: 0, Pixel(Float(bitPattern: word), 2, -3, 0.5)) }
    let source = try NativeModeRaster.converting(input, to: .rgb)
    let display = try source.surface(), channel = try source.channel(0)
    XCTAssertLessThan(display.tileCount, 4); XCTAssertLessThan(channel.tileCount, 4)
    for i in [0, 4093, 4094, 4095, 4096, 4097, 4098, 8192] {
      XCTAssertEqual(source.rawWord(component: 0, index: i), input.linearPixel(x: i, y: 0).r.bitPattern)
      XCTAssertTrue(display.linearPixel(x: i, y: 0).hasSameBits(as: input.linearPixel(x: i, y: 0)))
      XCTAssertEqual(channel.pixel(x: i, y: 0).r.bitPattern, input.linearPixel(x: i, y: 0).r.bitPattern)
    }
    let restored = try PropertyListDecoder().decode(NativeModeRaster.self, from: PropertyListEncoder().encode(source))
    XCTAssertEqual(restored, source)
    var data = Data()
    for i in [0, 4093, 4094, 4095, 4096, 4097, 4098, 8192] {
      let word = source.rawWord(component: 0, index: i)
      for byte in 0..<4 { data.append(UInt8(truncatingIfNeeded: word >> (byte * 8))) }
    }
    try capture("float-boundary", data)
  }
  func testComponentReplacementAndAlphaOwnershipKeepUntargetedBytes() throws {
    let source = try NativeModeRaster.converting(Surface(width: 8193, height: 1, depth: .u16, fill: .white), to: .cmyk)
    let black = try source.channel(3)
    var edit = black; edit.setPixel(x: 4095, y: 0, Pixel(0.25, 0.25, 0.25)); edit.setPixel(x: 4096, y: 0, Pixel(0.75, 0.75, 0.75))
    let changed = try source.replacingChannel(3, with: edit)
    for c in [0, 1, 2, 4] { XCTAssertEqual(try changed.planeBytes(c), try source.planeBytes(c)) }
    XCTAssertEqual(changed.rawWord(component: 3, index: 4095), 16384)
    XCTAssertEqual(changed.rawWord(component: 3, index: 4096), 49151)
    XCTAssertEqual(try changed.replacingChannel(3, with: black), source)
    XCTAssertTrue(changed.isOpaque)
    var transparent = changed; try transparent.set(0, component: 4, index: 8192)
    XCTAssertFalse(transparent.isOpaque); XCTAssertTrue(changed.isOpaque)
    var full = try NativeModeRaster(width: 3, height: 1, mode: .grayscale, depth: .u16)
    for i in 0..<3 { try full.set(1, component: 1, index: i) }
    XCTAssertTrue(full.isOpaque, "Padding beyond valid samples is not alpha")
    try capture("black-boundary", Data(try changed.planeBytes(3)[8190..<8198]))
  }
  func testCropAndReframeKeepSignedZeroAndRawSampleOrder() throws {
    var source = try NativeModeRaster(width: 4, height: 3, mode: .rgb, depth: .f32)
    let words: [UInt32] = [0x80000000, 1, 0x80000001, 0x3f800001, 0xc0500000, 0x40000000, 0, 0x3e800000, 0x3f000000, 0x3f800000, 0x40400000, 0xbf800000]
    for i in 0..<12 { try source.set(Float(bitPattern: words[i]), component: 0, index: i); try source.set(1, component: 3, index: i) }
    let crop = try source.cropped(to: .init(x: 1, y: 1, width: 2, height: 2))
    for (i, index) in [5, 6, 9, 10].enumerated() { XCTAssertEqual(crop.rawWord(component: 0, index: i), words[index]) }
    let frame = try crop.reframedExactly(bounds: .init(x: -1, y: -1, width: 4, height: 4), background: .white)
    for (i, index) in [5, 6, 9, 10].enumerated() { XCTAssertEqual(frame.rawWord(component: 0, index: (i / 2 + 1) * 4 + i % 2 + 1), words[index]) }
    XCTAssertEqual(frame.rawWord(component: 3, index: 0), Float(1).bitPattern)
    try capture("crop-red", crop.planeBytes(0))
  }
  func testRetainedConversionAndCacheReconcileShareUnchangedPlanes() throws {
    let input = try Surface(width: 512, height: 256, depth: .u16, fill: Pixel(0.2, 0.4, 0.8))
    let source = try NativeModeRaster.converting(input, to: .cmyk)
    let gray = try source.converted(to: .grayscale, depth: .u16)
    XCTAssertEqual(gray.residentComponentEditBytes, 0); XCTAssertEqual(try gray.surface().tileCount, 0)
    let before = try source.surface(); var edited = before
    let pixel = before.pixel(x: 511, y: 255)
    edited.setPixel(x: 511, y: 255, Pixel(pixel.r, pixel.g, pixel.b, 0.5))
    let changed = try source.reconciled(with: edited, previous: before)
    for c in 0..<4 { XCTAssertEqual(try changed.planeBytes(c), try source.planeBytes(c)) }
    XCTAssertEqual(changed.rawWord(component: 4, index: 512 * 256 - 1), 32768)
    XCTAssertLessThan(changed.residentComponentEditBytes, 12000)
    XCTAssertEqual(try source.reconciled(with: before, previous: before), source)
  }
  func testLinearDefaultChangesAreNotHiddenByEncodedRounding() throws {
    var pair: (Surface, Surface)?
    for bits in UInt32(0x3e800000)..<UInt32(0x3e800800) {
      let a = try Surface(width: 1, height: 1, depth: .f32, fill: Pixel(Float(bitPattern: bits), 0.5, 0.5)).interpretingSamples(as: .linearRGB)
      let b = try Surface(width: 1, height: 1, depth: .f32, fill: Pixel(Float(bitPattern: bits + 1), 0.5, 0.5)).interpretingSamples(as: .linearRGB)
      if a.defaultPixel.hasSameBits(as: b.defaultPixel) { pair = (a, b); break }
    }
    let (a, b) = try XCTUnwrap(pair, "A Float32 transfer collision is needed for this guard")
    let source = try NativeModeRaster.converting(a, to: .rgb)
    let changed = try source.reconciled(with: b, previous: a)
    XCTAssertEqual(changed.rawWord(component: 0, index: 0), b.linearPixel(x: 0, y: 0).r.bitPattern)
    XCTAssertNotEqual(changed.rawWord(component: 0, index: 0), source.rawWord(component: 0, index: 0))
  }
  func testLegacyDecodeRejectsNonfiniteAlphaAndMalformedPlanes() throws {
    let source = try NativeModeRaster(width: 2, height: 1, mode: .rgb, depth: .f32)
    let encoded = try JSONEncoder().encode(source)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    for word in [Float.nan.bitPattern, Float.infinity.bitPattern, Float(1.1).bitPattern, Float(-0.1).bitPattern] {
      var object = original, planes = try XCTUnwrap(original["planes"] as? [String])
      var bytes = Data(count: 8)
      for i in 0..<4 { bytes[i] = UInt8(truncatingIfNeeded: word >> (8 * i)) }
      planes[3] = bytes.base64EncodedString(); object["planes"] = planes
      XCTAssertThrowsError(try JSONDecoder().decode(NativeModeRaster.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    XCTAssertThrowsError(try source.planeBytes(4)); XCTAssertEqual(source.rawWord(component: 4, index: 0), 0)
    XCTAssertEqual(try JSONDecoder().decode(NativeModeRaster.self, from: encoded), source)
  }
  func testCancelledSparseOperationsDoNotReturnCandidates() async throws {
    let pixels = try Surface(width: 4096, height: 2048, depth: .u16, fill: .white)
    let native = try NativeModeRaster.converting(pixels, to: .cmyk)
    let task = Task.detached { () -> Bool in
      while !Task.isCancelled { await Task.yield() }
      do { _ = try native.channel(0); return false } catch is CancellationError {} catch { return false }
      do { _ = try native.surface(); return false } catch is CancellationError {} catch { return false }
      do { _ = try native.replacingChannel(0, with: pixels); return false } catch is CancellationError {} catch { return false }
      do { _ = try NativeModeRaster.converting(pixels, to: .cmyk); return false } catch is CancellationError {} catch { return false }
      return native.residentComponentEditBytes == 0
    }
    task.cancel(); let passed = await task.value; XCTAssertTrue(passed)
  }
  private func capture(_ name: String, _ data: Data) throws {
    guard let folder = ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"] else { return }
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".bin"), options: .withoutOverwriting)
  }
}
