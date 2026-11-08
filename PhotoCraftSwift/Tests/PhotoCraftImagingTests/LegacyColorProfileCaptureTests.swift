import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

/// Owned samples captured before replacing the dense profile-operation path.
/// These freeze ColorSync behavior on the observed host, not Adobe ACE output.
final class LegacyColorProfileCaptureTests: XCTestCase {
  func fixture(_ depth: PixelDepth, mode: DocumentColorMode?, width: Int = 67, height: Int = 3) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: height, depth: depth)
    var pixels = try Surface(width: width, height: height, depth: depth,
      colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    for y in 0..<height { for x in 0..<width {
      let p = Pixel(Float((x * 17 + y * 3) % 65) / 64,
        Float((x * 5 + y * 19) % 65) / 64, Float((x * 11 + y * 7) % 65) / 64,
        [Float(0), 0.25, 0.5, 1][(x + y) % 4])
      if depth == .f32 {
        pixels.setLinearPixel(x: x, y: y, Pixel(p.r * 3 - 0.1, p.g, p.b * 2, p.a))
      } else { pixels.setPixel(x: x, y: y, p) }
    } }
    document.layers[0].content = .raster(pixels)
    if let mode {
      document = try document.convertingMode(.init(mode: mode, depth: depth))
    }
    return document
  }
  func programs() throws -> [(CraftDocument, ColorProfileRequest)] {
    var result: [(CraftDocument, ColorProfileRequest)] = []
    for depth in PixelDepth.allCases {
      let modes: [DocumentColorMode] = depth == .f32 ? [.rgb, .grayscale] : [.rgb, .grayscale, .cmyk, .lab]
      for sourceMode: DocumentColorMode? in [nil] + modes.map(Optional.some) {
        let source = try fixture(depth, mode: sourceMode)
        for destination in modes {
          let profile = try destination == .rgb
            ? NativeModeProfile.atDepth(XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?), mode: .rgb, depth: depth)
            : NativeModeProfile.standard(destination, depth: depth)
          for intent in ModeRenderingIntent.allCases { for bpc in [false, true] {
            var request = ColorProfileRequest(.convert, profile: profile)
            request.intent = intent; request.blackPointCompensation = bpc
            result.append((source, request))
          } }
        }
      }
    }
    return result
  }
  func words(_ document: CraftDocument) throws -> Data {
    guard case .raster(let pixels) = document.layers[0].content else { throw CraftError.invalid("Missing owned profile raster.") }
    var result = Data()
    func append(_ word: UInt32) {
      var word = word.littleEndian
      withUnsafeBytes(of: &word) { result.append(contentsOf: $0) }
    }
    for y in 0..<pixels.height { for x in 0..<pixels.width {
      let pixel = pixels.colorEncoding == .linearRGB ? pixels.linearPixel(x: x, y: y) : pixels.pixel(x: x, y: y)
      for value in [pixel.r, pixel.g, pixel.b, pixel.a] { append(value.bitPattern) }
      if let native = document.layers[0].nativeMode {
        for c in 0...native.mode.componentCount { append(native.rawWord(component: c, index: y * pixels.width + x)) }
      }
    } }
    return result
  }
  func testCaptureOwnedLegacyProfilePrograms() throws {
    let programs = try programs()
    XCTAssertEqual(programs.count, 368)
    var bytes = Data(), outcomes: [[String: Any]] = []
    for (index, program) in programs.enumerated() {
      let (source, request) = program
      do {
        var result = source
        try ColorProfileInput.command(request, in: source).apply(to: &result)
        let words = try words(result)
        outcomes.append(["index": index, "offset": bytes.count, "bytes": words.count])
        bytes.append(words)
      } catch {
        // Preserve unsupported legacy conversions explicitly. Recording them is
        // inventory evidence, not a claim that these combinations work.
        outcomes.append(["index": index, "error": error.localizedDescription])
      }
    }
    XCTAssertFalse(bytes.isEmpty)
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try bytes.write(to: URL(fileURLWithPath: folder).appendingPathComponent("color-profile-legacy-small.words"), options: .withoutOverwriting)
      try JSONSerialization.data(withJSONObject: outcomes, options: [.sortedKeys, .prettyPrinted])
        .write(to: URL(fileURLWithPath: folder).appendingPathComponent("color-profile-legacy-outcomes.json"), options: .withoutOverwriting)
    }
  }
}
