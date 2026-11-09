import Foundation
import Compression
import CryptoKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

/// Owned regression programs, not independently captured Photoshop pixels.
final class PhotoBlendLegacyCaptureTests: XCTestCase {
  func programs() throws -> [(String, CraftDocument, PhotoBlendSettings)] {
    var result: [(String, CraftDocument, PhotoBlendSettings)] = []
    for depth in PixelDepth.allCases {
      for method in PhotoBlendSettings.Method.allCases {
        let source = try PhotoBlendWorkflowTests().fixture(depth, focus: method == .stack)
        for seamless in [false, true] { for fill in [false, true] {
          var settings = PhotoBlendSettings(); settings.method = method
          settings.seamlessTones = seamless; settings.fillTransparentAreas = fill
          result.append(("\(depth.rawValue)-\(method.rawValue)-seamless\(seamless)-fill\(fill)", source, settings))
        } }
      }
    }
    return result
  }
  func words(_ surface: Surface) -> Data {
    var bytes = Data()
    for y in 0..<surface.height { for x in 0..<surface.width {
      let p = surface.linearPixel(x: x, y: y)
      for value in [p.r, p.g, p.b, p.a] {
        var word = value.bitPattern.littleEndian
        withUnsafeBytes(of: &word) { bytes.append(contentsOf: $0) }
      }
    } }
    return bytes
  }
  func testCaptureOpaqueBlendProgramsWithoutChangingSource() throws {
    var bytes = Data(), cases: [[String: Any]] = []
    for (name, source, settings) in try programs() {
      let original = source, offset = bytes.count
      let edit = try PhotoBlend.prepare(source, layerIDs: Set(source.layers.map(\.id)), settings: settings)
      bytes.append(try words(Renderer.composite(edit.result)))
      XCTAssertEqual(source, original)
      cases.append(["name": name, "offset": offset, "bytes": bytes.count - offset,
        "layers": edit.result.layers.count, "visible": edit.result.layers.map(\.visible)])
    }
    XCTAssertEqual(cases.count, 24); XCTAssertEqual(bytes.count, 983040)
    let fixture = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/PhotoBlend/opaque-513.f32le.zlib")
    let compressed = try Data(contentsOf:fixture),raw = Data(compressed.dropFirst(2).dropLast(4))
    var expected = [UInt8](repeating:0,count:983040)
    let size = raw.withUnsafeBytes { src in
      compression_decode_buffer(&expected,expected.count,src.bindMemory(to:UInt8.self).baseAddress!,raw.count,nil,COMPRESSION_ZLIB)
    }
    XCTAssertEqual(size,expected.count)
    let frozen = Data(expected)
    XCTAssertEqual(SHA256.hash(data:frozen).map { String(format:"%02x",$0) }.joined(),
      "69a0f15a686f7522355ad98e161f7c7b56c08e558baf79099ecc87e94fdad068")
    XCTAssertEqual(bytes,frozen,"The owned build513 opaque composite regression changed.")
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let folder = URL(fileURLWithPath: path)
      try bytes.write(to: folder.appendingPathComponent("blend-programs.f32le"))
      try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys])
        .write(to: folder.appendingPathComponent("blend-programs.json"))
    }
  }
}
