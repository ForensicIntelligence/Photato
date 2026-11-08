import AppKit
import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging
@testable import PhotoCraft

final class NativeImageExportPublicationTests: XCTestCase {
  private func fixture() throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 3, name: "Owned asset")
    document.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(0.25, 0.5, 0.75, 0.5)))
    return document
  }
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("photato-asset500-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }
  private func asset(_ bytes: Data, name: String = "Owned.png") -> ImageExportFile {
    .init(name: name, data: bytes, width: 4, height: 3, sourceID: nil, scale: 1)
  }
  @MainActor func testSingleFilePublicationMatchesNativeAndHTTPPNGJPEGGIFWithoutHistory() async throws {
    let helper = AutomationTests(), source = try fixture(), directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: source)
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first), revision = service.revision(document.store)
      for format in ImageExportSettings.Format.allCases {
        var settings = ImageExportSettings(); settings.format = format
        let output = try await document.store.encodedImageAssets(settings)
        XCTAssertEqual(output.files.count, 1)
        let file = try XCTUnwrap(output.files.first), url = directory.appendingPathComponent(file.name)
        try ImageExportPublication.write(output.files, to: url, directory: false)
        let response = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: [
          "command": "image.export", "revision": service.revision(document.store),
          "parameters": ["settings": BrushAPI.json(settings)]])
        XCTAssertEqual(response.0.statusCode, 200, String(decoding: response.1.prefix(500), as: UTF8.self))
        let archive = try PcraftZIP(response.1)
        XCTAssertEqual(try Data(contentsOf: url), file.data)
        XCTAssertEqual(try archive.read(file.name), file.data)
      }
      XCTAssertEqual(document.store.document, source)
      XCTAssertEqual(service.revision(document.store), revision)
      XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertFalse(document.isDocumentEdited)
      XCTAssertNotNil(ImageExportAPI.capabilities["nativePublication"])
      XCTAssertEqual(AutomationCommand.definitions.count, 267)
    }
  }
  func testSingleFileReplacementRetainsPermissionsAndFollowsSelectedSymlinkWithoutReplacingAlias() throws {
    let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("Owned.png"), alias = directory.appendingPathComponent("Chosen.png")
    try Data("Previous owned version".utf8).write(to: destination)
    try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: destination.path)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: destination)
    let files = try ImageExportPreparation.render(fixture(), settings: .init()).files
    try ImageExportPublication.write(files, to: alias, directory: false)
    XCTAssertEqual(try Data(contentsOf: destination), files[0].data)
    XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: alias.path)[.type] as? FileAttributeType, .typeSymbolicLink)
    let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)
    XCTAssertEqual(permissions.intValue & 0o777, 0o640)
    XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), ["Owned.png", "Chosen.png"])
  }
  @MainActor func testOversizedAndCancelledPublicationRetainsExistingBytesAndLeavesNoNewFiles() async throws {
    let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("Owned.png"), original = Data("Previous owned version".utf8)
    try original.write(to: destination)
    let oversized = asset(Data(repeating: 0, count: ImageAssetExport.maximumBytes + 1))
    XCTAssertThrowsError(try ImageExportPublication.write([oversized], to: destination, directory: false))
    XCTAssertEqual(try Data(contentsOf: destination), original)
    let files = try ImageExportPreparation.render(fixture(), settings: .init()).files
    let pending = Task { @MainActor in try ImageExportPublication.write(files, to: destination, directory: false) }
    pending.cancel()
    do { try await pending.value; XCTFail("Cancelled publication replaced the destination") }
    catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
    XCTAssertEqual(try Data(contentsOf: destination), original)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Owned.png"])
  }
  func testMultiFilePublicationStillPreflightsAllNamesAndNeverReplacesExistingAssets() throws {
    let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
    let original = Data("Previous second asset".utf8), second = directory.appendingPathComponent("Second.png")
    try original.write(to: second)
    let files = [asset(Data("First".utf8), name: "First.png"), asset(Data("Second".utf8), name: "Second.png")]
    XCTAssertThrowsError(try ImageExportPublication.write(files, to: directory, directory: true))
    XCTAssertEqual(try Data(contentsOf: second), original)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("First.png").path))
    XCTAssertThrowsError(try ImageExportPublication.write([], to: second, directory: false))
    XCTAssertEqual(try Data(contentsOf: second), original)
  }
}
