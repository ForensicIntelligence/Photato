import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class JPEGXLImportWorkflowTests: XCTestCase {
  private struct Expected: Decodable {
    let width: Int
    let height: Int
    let depth: Int
    let RGBA: [[Int]]
  }

  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run {
      _ = PhotatoApp.makeDelegate(isolatedSession: true)
      _ = NSApplication.shared
    }
  }

  private func fixture(_ name: String, extension suffix: String = "jxl") throws -> URL {
    try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: suffix,
      subdirectory: "Fixtures/jpeg-xl-import"))
  }

  private func checkPixels(_ document: CraftDocument, expected: Expected) throws {
    XCTAssertEqual(document.width, expected.width)
    XCTAssertEqual(document.height, expected.height)
    XCTAssertEqual(document.depth, expected.depth == 8 ? .u8 : .u16)
    let layer = try XCTUnwrap(document.layers.first)
    guard case .raster(let surface) = layer.content else { return XCTFail("Expected an editable raster layer.") }
    let maximum = Float((1 << expected.depth) - 1)
    let actual = (0..<(expected.width * expected.height)).map { index in
      let pixel = surface.pixel(x: index % expected.width, y: index / expected.width)
      return [pixel.r, pixel.g, pixel.b, pixel.a].map { Int(($0 * maximum).rounded()) }
    }
    XCTAssertEqual(actual, expected.RGBA)
  }

  @MainActor func testJPEGXLAdmissionAndSaveFormatsReflectTheRuntimeDecoder() throws {
    XCTAssertEqual(DocumentOpenFormat.availableCases.contains(.jxl), JPEGXLInput.isAvailable)
    XCTAssertEqual(DocumentIO.readableTypes.contains(JPEGXLInput.typeIdentifier), JPEGXLInput.isAvailable)
    XCTAssertEqual(DocumentIO.uploadTypes.contains(JPEGXLInput.mediaType), JPEGXLInput.isAvailable)
    XCTAssertNil(DocumentOpenFormat.jxl.persistenceFormat)
    XCTAssertNil(DocumentIO.Format(fileExtension: "jxl"))
    let capability = try XCTUnwrap(AutomationService.documentOpeningCapabilities["jpegXL"] as? [String: Any])
    XCTAssertEqual(capability["available"] as? Bool, JPEGXLInput.isAvailable)
    let raw = try Data(contentsOf: fixture("raw8"))
    XCTAssertEqual(DocumentOpenFormat.detect(raw), .jxl)
    XCTAssertThrowsError(try DocumentOpenFormat.png.validate(.jxl))
    if JPEGXLInput.isAvailable {
      XCTAssertNoThrow(try DocumentOpenFormat.jxl.validate(.jxl))
      XCTAssertThrowsError(try DocumentIO.decode(Data(raw.prefix(4)), native: false, name: "Truncated"))
    } else {
      XCTAssertThrowsError(try DocumentOpenFormat.jxl.validate(.jxl))
      XCTAssertThrowsError(try DocumentIO.decode(raw, native: false, name: "Unavailable"))
    }
  }

  @MainActor func testBothSignaturesOpenWithExactOwnedSamplesAndNativeSave() async throws {
    try XCTSkipUnless(JPEGXLInput.isAvailable)
    let manifest = try Data(contentsOf: fixture("expected", extension: "json"))
    let expected = try JSONDecoder().decode([String: Expected].self, from: manifest)
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["raw8", "container16"] {
      let original = try Data(contentsOf: fixture(name))
      let source = folder.appendingPathComponent(name + ".bin")
      try original.write(to: source)
      XCTAssertEqual(DocumentOpenFormat.detect(source), .jxl)
      let prepared = try PreparedLocalDocument.read(source, format: .jxl)
      XCTAssertNil(prepared.format)
      try checkPixels(prepared.model, expected: XCTUnwrap(expected[name]))
      let document = prepared.makeDocument(url: source)
      defer { document.close() }
      XCTAssertNil(document.fileURL)
      XCTAssertEqual(document.importedSourceURL, source.standardizedFileURL.resolvingSymlinksInPath())
      let output = folder.appendingPathComponent(name + ".photato")
      try await document.persistDocument(to: output, format: .native, operation: .saveAsOperation)
      XCTAssertEqual(try NativeArchive.readPaged(output), prepared.model)
      XCTAssertEqual(try Data(contentsOf: source), original)
    }
  }

  func testAnimationIsRejectedBeforeImageIOCanDropFrames() throws {
    try XCTSkipUnless(JPEGXLInput.isAvailable)
    let animated = try Data(contentsOf: fixture("two-frames"))
    // The authored fixture's two jxlp boxes start at bytes 32 and 71.
    // Cross-check their types before extracting the independent raw stream.
    XCTAssertEqual(animated.count, 100)
    guard animated.count == 100 else { return }
    XCTAssertEqual(Data(animated[36..<40]), Data("jxlp".utf8))
    XCTAssertEqual(Data(animated[75..<79]), Data("jxlp".utf8))
    let stream = Data(animated[44..<71]) + Data(animated[83..<100])
    XCTAssertTrue(stream.starts(with: [0xff, 0x0a]))
    func box(_ name: String, payload: Data) -> Data {
      let size = UInt32(payload.count + 8).bigEndian
      return withUnsafeBytes(of: size) { Data($0) } + Data(name.utf8) + payload
    }
    func fragment(_ index: UInt32, data: Data) -> Data {
      let index = index.bigEndian
      return box("jxlp", payload: withUnsafeBytes(of: index) { Data($0) } + data)
    }
    let containerHeader = Data(animated.prefix(32))
    let complete = containerHeader + box("jxlc", payload: stream)
    let fragmented = containerHeader + fragment(0, data: Data(stream.prefix(3))) +
      fragment(0x8000_0001, data: Data(stream.dropFirst(3)))
    for input in [animated, stream, complete, fragmented] {
      XCTAssertThrowsError(try DocumentIO.decode(input, native: false, name: "Animation")) { error in
        XCTAssertEqual(error as? CraftError,
          .unsupported("Open a still JPEG XL image. Animated JPEG XL is not supported."))
      }
    }
  }

  @MainActor func testHTTPImportMatchesNativeAndRejectsWrongOrTruncatedInput() async throws {
    try XCTSkipUnless(JPEGXLInput.isAvailable)
    let raw = try Data(contentsOf: fixture("raw8"))
    let png = try Data(contentsOf: fixture("raw8", extension: "png"))
    let animated = try Data(contentsOf: fixture("two-frames"))
    let files = DocumentIOWorkflowTests()
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, _ in
      let path = "/v1/documents/import"
      let format = ["X-Photato-Open-Format": "jxl", "X-Photato-Name": "JPEG XL"]
      let denied = try await files.request(service, path: path, data: raw, type: JPEGXLInput.mediaType, headers: format)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let baseline = service.shares.count
      for (bytes, type, headers) in [
        (png, JPEGXLInput.mediaType, [:]),
        (png, "application/octet-stream", format),
        (Data(raw.prefix(4)), JPEGXLInput.mediaType, format),
        (animated, JPEGXLInput.mediaType, format),
      ] {
        let failed = try await files.request(service, path: path, data: bytes, type: type, headers: headers)
        XCTAssertEqual(failed.0.statusCode, 422, String(decoding: failed.1, as: UTF8.self))
        XCTAssertEqual(service.shares.count, baseline)
      }
      for type in [JPEGXLInput.mediaType, "application/octet-stream"] {
        let accepted = try await files.request(service, path: path, data: raw, type: type, headers: format)
        XCTAssertEqual(accepted.0.statusCode, 201, String(decoding: accepted.1, as: UTF8.self))
        let imported = try XCTUnwrap(service.shares.last?.document)
        let expected = try DocumentIO.decode(raw, native: false, name: "JPEG XL")
        XCTAssertEqual(imported.store.document.layers.first?.content, expected.layers.first?.content)
        XCTAssertNil(imported.fileURL)
        XCTAssertNil(imported.importedSourceURL)
        imported.updateChangeCount(.changeCleared)
        imported.close()
      }
    }
  }
}
