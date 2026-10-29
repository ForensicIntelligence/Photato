import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VariableDataExportTests: XCTestCase {
  func template() throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 4, name: "Owned variable template")
    let id = d.layers[0].id
    try Command.variables(.define([.init(name: "photo", layerID: id, kind: .pixelReplacement), .init(name: "show", layerID: id, kind: .visibility)])).apply(to: &d)
    let asset = VariableImage(name: "Owned red", pixels: try Surface(width: 2, height: 2, fill: Pixel(1, 0, 0)))
    try Command.variables(.image(asset)).apply(to: &d)
    try Command.variables(.dataSets([
      .init(name: "Red", values: ["photo": .pixels(asset.id)]),
      .init(name: "Original", values: ["photo": .pixels(nil)]),
      .init(name: "Hidden", values: ["show": .visibility(false)])], append: false)).apply(to: &d)
    return d
  }
  func testIndependentVariationsPNGZIPAndNativeTemplates() throws {
    let document = try template(), before = document
    let output = try VariableDataExport.render(document, options: .init(prefix: "owned", format: .png))
    XCTAssertEqual(output.files.count, 4)
    for (index, expected) in [Pixel(1, 0, 0), .white, .clear].enumerated() {
      let decoded = try RasterIO.read(output.files[index].data)
      let surface = try Renderer.composite(decoded)
      for y in 0..<4 { for x in 0..<4 { XCTAssertEqual(surface.pixel(x: x, y: y), expected) } }
    }
    let bytes = try output.zip(); XCTAssertFalse(bytes.isEmpty)
    let native = try VariableDataExport.render(document, options: .init(format: .native))
    for index in 0..<3 {
      let decoded = try NativeArchive.decode(native.files[index].data)
      XCTAssertEqual(decoded.variables?.activeDataSetID, document.variables!.dataSets[index].id)
      XCTAssertEqual(decoded.variables?.images, document.variables?.images)
      XCTAssertEqual(decoded.minimumArchiveVersion, 61)
    }
    XCTAssertEqual(document, before)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_VARIABLES_OUTPUT_DIR"] {
      let folder = URL(fileURLWithPath: path)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for file in output.files { try file.data.write(to: folder.appendingPathComponent(file.name), options: .withoutOverwriting) }
      try bytes.write(to: folder.appendingPathComponent("owned.zip"), options: .withoutOverwriting)
    }
  }
  func testPSDVariationsAndTemplateSaveGuidance() throws {
    let document = try template()
    XCTAssertNotNil(DocumentIO.persistenceIssue(document, format: .psd))
    XCTAssertNotNil(DocumentIO.persistenceIssue(document, format: .png))
    XCTAssertNil(DocumentIO.persistenceIssue(document, format: .native))
    XCTAssertThrowsError(try DocumentIO.encode(document, format: .psd))
    let output = try VariableDataExport.render(document, options: .init(format: .psd))
    for index in 0..<3 {
      let reopened = try PSDCodec.read(output.files[index].data)
      var expected = document; try Command.variables(.apply(document.variables!.dataSets[index].id)).apply(to: &expected)
      let actualPixels = try Renderer.composite(reopened), expectedPixels = try Renderer.composite(expected)
      for y in 0..<4 { for x in 0..<4 { XCTAssertEqual(actualPixels.pixel(x: x, y: y), expectedPixels.pixel(x: x, y: y)) } }
      XCTAssertNil(reopened.variables)
    }
  }
  func testInvalidSelectionBudgetSafeNamesAndExistingFolder() throws {
    var document = try template()
    XCTAssertThrowsError(try VariableDataExport.render(document, options: .init(prefix: "../escape")))
    XCTAssertThrowsError(try VariableDataExport.render(document, options: .init(dataSetIDs: [UUID()])))
    let id = document.variables!.dataSets[0].id
    XCTAssertThrowsError(try VariableDataExport.render(document, options: .init(dataSetIDs: [id, id])))
    XCTAssertThrowsError(try VariableDataExport.render(document, options: .init(format: .png), maximumBytes: 1))
    document.variables!.dataSets[0].name = "../one:two\\three"
    let output = try VariableDataExport.render(document, options: .init(format: .png, dataSetIDs: [id]))
    XCTAssertEqual(output.files.count, 2)
    XCTAssertFalse(output.files[0].name.contains("/")); XCTAssertFalse(output.files[0].name.contains(":")); XCTAssertFalse(output.files[0].name.contains("\\"))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("photato-owned-variables-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("output")
    let staged = try PreparedSequenceFolder.prepare(output, destination: destination)
    defer { staged.discard() }; try staged.commit()
    let repeated = try PreparedSequenceFolder.prepare(output, destination: destination)
    defer { repeated.discard() }; XCTAssertThrowsError(try repeated.commit())
    for file in output.files { XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(file.name)), file.data) }
  }
  func testCancelledOutputDoesNotPublishAnything() async throws {
    let document = try template()
    let task = Task.detached { try await Task.sleep(for: .milliseconds(20)); return try VariableDataExport.render(document, options: .init(format: .png)) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled export succeeded") } catch is CancellationError {}
  }
}
