import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PagedColorProfileTests: XCTestCase {
  func conversion(_ source: CraftDocument, _ request: ColorProfileRequest) throws -> ColorProfileRasterConversion {
    let profile = try ColorProfileInput.effectiveProfile(source)
    let destination = try ProofSettings.mode(of: request.profile)
    return try .init(request: request, depth: source.depth, sourceProfile: profile,
      sourceMode: source.colorMode, destination: destination,
      nativeOutput: source.modeDescriptor != nil || destination != .rgb,
      transform: ProofTransform(profile, request.profile, intent: request.intent, bpc: request.blackPointCompensation))
  }
  func paged(_ source: CraftDocument, _ request: ColorProfileRequest) throws -> CraftDocument {
    guard case .raster(let pixels) = source.layers[0].content else { throw CraftError.invalid("Missing test raster.") }
    let output = try conversion(source, request).paged(pixels, native: source.layers[0].nativeMode)
    var result = source
    result.layers[0].content = .raster(output.pixels); result.layers[0].nativeMode = output.native
    return result
  }
  func testDenseAndPagedRetainAllFrozenLegacyWordsAndExplicitErrors() throws {
    let helper = LegacyColorProfileCaptureTests()
    let folder = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
      .appendingPathComponent("paged-color-profile")
    let words = try Data(contentsOf: folder.appendingPathComponent("color-profile-legacy-small.words"))
    let outcomes = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
      folder.appendingPathComponent("color-profile-legacy-outcomes.json"))) as? [[String: Any]])
    let programs = try helper.programs()
    XCTAssertEqual(outcomes.count, 368); XCTAssertEqual(programs.count, outcomes.count)
    XCTAssertEqual(outcomes.filter { $0["error"] != nil }.count, 32)
    XCTAssertEqual(words.count, 1_984_272)
    var denseWords = Data(), pagedWords = Data()
    for (index, program) in programs.enumerated() {
      let (source, request) = program, expected = outcomes[index]
      XCTAssertEqual(expected["index"] as? Int, index)
      for usePaged in [false, true] {
        do {
          var result = source
          if usePaged { result = try paged(source, request) }
          else { try ColorProfileInput.command(request, in: source).apply(to: &result) }
          XCTAssertNil(expected["error"], "Legacy failure unexpectedly changed at \(index)")
          let actual = try helper.words(result)
          if let offset = expected["offset"] as? Int, let count = expected["bytes"] as? Int {
            XCTAssertEqual(actual, words.subdata(in: offset..<(offset + count)), "program \(index), paged=\(usePaged)")
          }
          if usePaged { pagedWords.append(actual) } else { denseWords.append(actual) }
        } catch {
          XCTAssertEqual(error.localizedDescription, expected["error"] as? String,
            "program \(index), paged=\(usePaged)")
        }
      }
    }
    XCTAssertEqual(denseWords, words); XCTAssertEqual(pagedWords, words)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try denseWords.write(to: URL(fileURLWithPath: path).appendingPathComponent("color-profile-dense-small.words"))
      try pagedWords.write(to: URL(fileURLWithPath: path).appendingPathComponent("color-profile-paged-small.words"))
    }
  }
  func testPatchBoundariesRetainIntegerFloatNativeComponentsAndHiddenRGB() throws {
    let helper = LegacyColorProfileCaptureTests()
    for (depth, mode) in [(PixelDepth.u8, Optional<DocumentColorMode>.none), (.u16, nil), (.f32, nil),
      (.u16, .cmyk), (.f32, .grayscale), (.u16, .lab)] {
      let source = try helper.fixture(depth, mode: mode, width: 2113, height: 67)
      let profile = try NativeModeProfile.atDepth(XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?), mode: .rgb, depth: depth)
      let request = ColorProfileRequest(.convert, profile: profile)
      var expected = source; try ColorProfileInput.command(request, in: source).apply(to: &expected)
      let result = try paged(source, request)
      XCTAssertEqual(try helper.words(result), try helper.words(expected), "\(depth) \(String(describing: mode))")
    }
  }
  func maximum(_ depth: PixelDepth, mode: DocumentColorMode?) throws -> CraftDocument {
    var result = try CraftDocument(width: 300_000, height: 300_000, depth: depth)
    let raw = Pixel(0.25, 0.5, 0.75, 0)
    var pixels = try Surface(width: result.width, height: result.height, depth: depth, fill: raw)
      .interpretingSamples(as: depth == .f32 ? .linearRGB : .sRGB)
    if let mode {
      var native = try NativeModeRaster(width: result.width, height: result.height, mode: mode, depth: depth)
      for c in 0..<mode.componentCount {
        let v = Float(c + 1) / 8
        native = try native.replacingChannel(c, with: Surface(width: result.width, height: result.height,
          depth: depth, fill: Pixel(v, v, v)))
      }
      native = try native.replacingOpacity(with: Surface(width: result.width, height: result.height, depth: depth, fill: .clear))
      for (x, y) in [(64, 65), (299_999, 299_999)] {
        for c in 0..<mode.componentCount { try native.set(Float(c + 2) / 7, component: c, index: y * result.width + x) }
        try native.set(x == 64 ? 0 : 0.5, component: mode.componentCount, index: y * result.width + x)
      }
      result.modeDescriptor = try .init(mode: mode, depth: depth, profile: native.profile)
      result.layers[0].nativeMode = native; pixels = try native.surface()
    } else {
      if depth == .f32 { pixels.setLinearPixel(x: 64, y: 65, Pixel(2.5, -0.1, 0.7, 0)) }
      else { pixels.setPixel(x: 64, y: 65, Pixel(0.9, 0.1, 0.3, 0)) }
      pixels.setPixel(x: 299_999, y: 299_999, Pixel(0.8, 0.2, 0.4, 0.5))
    }
    result.layers[0].content = .raster(pixels); try result.validate(); return result
  }
  func testMaximumSparseConversionAllLegalSourceModesMatchesDensePointReferences() throws {
    for depth in PixelDepth.allCases {
      let modes: [DocumentColorMode?] = depth == .f32 ? [nil, .rgb, .grayscale] : [nil, .rgb, .grayscale, .cmyk, .lab]
      for mode in modes {
        let source = try maximum(depth, mode: mode), original = source
        let profile = try NativeModeProfile.atDepth(XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?), mode: .rgb, depth: depth)
        let request = ColorProfileRequest(.convert, profile: profile)
        var result = source; try ColorProfileInput.command(request, in: source).apply(to: &result)
        guard case .raster(let before) = source.layers[0].content,
          case .raster(let after) = result.layers[0].content else { return XCTFail("Missing raster") }
        XCTAssertEqual(after.width, 300_000); XCTAssertEqual(after.height, 300_000)
        XCTAssertLessThan(after.tileCount, 10); XCTAssertEqual(source, original)
        for (x, y) in [(0, 0), (63, 64), (64, 65), (299_999, 299_999)] {
          let bounds = IntRect(x: x, y: y, width: 1, height: 1)
          var small = try CraftDocument(width: 1, height: 1, depth: depth)
          small.workingICC = source.workingICC; small.modeDescriptor = source.modeDescriptor
          small.layers[0].content = .raster(try before.cropped(to: bounds))
          small.layers[0].nativeMode = try source.layers[0].nativeMode?.cropped(to: bounds)
          var expected = small; try ColorProfileInput.command(request, in: small).apply(to: &expected)
          guard case .raster(let expectedPixels) = expected.layers[0].content else { return XCTFail("Missing reference") }
          let a = after.colorEncoding == .linearRGB ? after.linearPixel(x: x, y: y) : after.pixel(x: x, y: y)
          let b = expectedPixels.colorEncoding == .linearRGB ? expectedPixels.linearPixel(x: 0, y: 0) : expectedPixels.pixel(x: 0, y: 0)
          XCTAssertTrue(a.hasSameBits(as: b), "\(depth) \(String(describing: mode)) at\(x),\(y)")
          if let native = result.layers[0].nativeMode, let expectedNative = expected.layers[0].nativeMode {
            for c in 0...native.mode.componentCount {
              XCTAssertEqual(native.rawWord(component: c, index: y * result.width + x), expectedNative.rawWord(component: c, index: 0))
            }
          }
        }
        XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(result)), result)
      }
    }
  }
  func testActualDensePagedImageAboveOldBudgetMatchesEveryRepeatedPatch() throws {
    let source = try LegacyColorProfileCaptureTests().fixture(.u8, mode: nil, width: 64, height: 64)
    guard case .raster(let patch) = source.layers[0].content else { return XCTFail("Missing source") }
    let width = 4096, height = 2049
    let builder = try Surface.PagedBuilder(width: width, height: height)
    for y in stride(from: 0, to: height, by: 64) { for x in stride(from: 0, to: width, by: 64) {
      try builder.append(y + 64 <= height ? patch : patch.cropped(to: .init(x: 0, y: 0, width: 64, height: 1)), atX: x, atY: y)
    } }
    let pixels = try builder.finish()
    var large = try CraftDocument(width: width, height: height)
    large.layers[0].content = .raster(pixels)
    let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
    let request = ColorProfileRequest(.convert, profile: profile)
    var expected = source; try ColorProfileInput.command(request, in: source).apply(to: &expected)
    var result = large; try ColorProfileInput.command(request, in: large).apply(to: &result)
    guard case .raster(let expectedPatch) = expected.layers[0].content,
      case .raster(let output) = result.layers[0].content else { return XCTFail("Missing output") }
    XCTAssertGreaterThan(width * height, NativeModeRaster.maximumPixels)
    XCTAssertGreaterThan(pixels.mappedBytes, 0); XCTAssertGreaterThan(output.mappedBytes, 0)
    for y in stride(from: 0, to: height, by: 64) { for x in stride(from: 0, to: width, by: 64) {
      let h = min(64, height - y)
      XCTAssertEqual(try output.cropped(to: .init(x: x, y: y, width: 64, height: h)),
        try expectedPatch.cropped(to: .init(x: 0, y: 0, width: 64, height: h)))
    } }
    XCTAssertEqual(large.layers[0].content, .raster(pixels))
  }
  func testCancelledAndInvalidLargeProfileRequestsDoNotReturnEdits() async throws {
    let source = try maximum(.f32, mode: nil), original = source
    let profile = try NativeModeProfile.standard(.rgb, depth: .f32)
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try ColorProfileInput.command(.init(.convert, profile: profile), in: source)
    }
    do { _ = try await task.value; XCTFail("Cancelled conversion returned a command") } catch is CancellationError { }
    XCTAssertThrowsError(try ColorProfileInput.command(.init(.assign, profile: Data()), in: source))
    XCTAssertEqual(source, original)
  }
}
