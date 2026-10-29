import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class WorkingProfileWorkflowTests: XCTestCase {
  func testNativeInputRejectsBoundedButUnusableICCProfile() throws {
    var document = try CraftDocument(width: 1, height: 1)
    var invalid = Data(repeating: 0, count: 132)
    invalid[3] = 132
    invalid[8] = 4
    for (offset, text) in [(16, "RGB "), (20, "XYZ "), (36, "acsp")] {
      invalid.replaceSubrange(offset..<offset + 4, with: Data(text.utf8))
    }
    document.workingICC = invalid
    let archive = try NativeArchive.encode(document)
    XCTAssertThrowsError(try DocumentIO.decode(archive, native: true, name: "Invalid profile"))
  }

  func document() throws -> CraftDocument {
    var d = try CraftDocument(width: 2, height: 1, depth: .u16)
    d.workingICC = CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?
    d.layers[0].content = .raster(
      try Surface(width: 2, height: 1, depth: .u16, fill: Pixel(0.6, 0.3, 0.2)))
    return d
  }
  @MainActor func testNativeColourWellUsesDocumentProfile() throws {
    let d = try document()
    let store = EditorStore(document: d)
    defer { store.renderTask?.cancel() }
    let chosen = Color(.sRGB, red: 0.6, green: 0.4, blue: 0.2)
    let p = try XCTUnwrap(store.workingPixel(chosen))
    XCTAssertNotEqual(p.r, 0.6)
    let shown = try XCTUnwrap(NSColor(store.displayColor(p)).usingColorSpace(.sRGB))
    XCTAssertEqual(shown.redComponent, 0.6, accuracy: 0.0001)
    XCTAssertEqual(shown.greenComponent, 0.4, accuracy: 0.0001)
    XCTAssertEqual(shown.blueComponent, 0.2, accuracy: 0.0001)
    XCTAssertEqual(store.document, d)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  func testCrossDocumentCloneConvertsColoursAndLeavesMaskSamplesAlone() throws {
    var source = try document()
    let target = try CraftDocument(width: 2, height: 1, depth: .u16)
    let id = source.layers[0].id
    let sample = try CloneSourceRequest(
      document: source, layerID: id, sampling: .current,
      ignoreAdjustments: false, mask: false, target: target
    ).sample()
    let original = try Renderer.layerSurface(source.layers[0], in: source)
    let expected = try ColorManagement.converted(original, from: source, to: target)
    XCTAssertEqual(try sample.surface.rgbaData(depth: .u16), try expected.rgbaData(depth: .u16))
    XCTAssertNotEqual(sample.surface.pixel(x: 0, y: 0).r, original.pixel(x: 0, y: 0).r)
    let mask = try Surface(width: 2, height: 1, depth: .u16, fill: Pixel(0.4, 0.4, 0.4))
    source.layers[0].mask = mask
    let maskSample = try CloneSourceRequest(
      document: source, layerID: id, sampling: .current,
      ignoreAdjustments: false, mask: true, target: target
    ).sample()
    XCTAssertEqual(maskSample.surface, mask)
  }
}
