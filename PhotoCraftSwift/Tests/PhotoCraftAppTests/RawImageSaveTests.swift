import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawImageSaveTests: XCTestCase {
  @MainActor func testDevelopedImageUsesTheSameEncodersAsRawImportAndDownload() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng")
    let sensor = try Data(contentsOf: fixture)
    var settings = RawDevelopment()
    settings.adjustments.exposure = 0.75
    let workflow = RawWorkflowOutput(profile: .displayP3, depth: .u8, pixelsPerInch: 300,
      resize: .init(mode: .percentage, value: 50))
    let original = try RawSourceIO.open(sensor, fileName: fixture.lastPathComponent, settings: settings)
    let developed = try RawOpenMode.copy.output(from: original, workflow: workflow)
    XCTAssertTrue(developed.layers[0].isBackground)
    XCTAssertEqual(original.layers[0].smartObject?.data, sensor)
    XCTAssertEqual(try Data(contentsOf: fixture), sensor)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, initial in
      defer { for doc in service.controller.documents where doc !== initial { doc.close() } }
      service.setDocumentTransfersEnabled(true)
      let capabilities = try await api.request(service, path: "/v1/capabilities")
      XCTAssertEqual(capabilities.0.statusCode, 200)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: capabilities.1) as? [String: Any])
      let transfers = try XCTUnwrap(body["documentTransfers"] as? [String: Any])
      let cameraRaw = try XCTUnwrap(transfers["cameraRawDevelopedImage"] as? [String: Any])
      XCTAssertEqual(cameraRaw["formats"] as? [String], ["tiff", "jpeg", "png", "psd"])

      let imported = try await AutomationOpeningTests().upload(service, bytes: sensor,
        type: "image/x-adobe-dng", headers: [
          "X-Photato-Name": fixture.deletingPathExtension().lastPathComponent,
          "X-Photato-Raw-Open-Mode": "copy",
          "X-Photato-Raw-XMP": try CameraRawXMP.write(settings).base64EncodedString(),
          "X-Photato-Raw-Workflow": try JSONEncoder().encode(workflow).base64EncodedString()
        ])
      XCTAssertEqual(imported.0.statusCode, 201, String(decoding: imported.1, as: UTF8.self))
      let share = try XCTUnwrap(service.shares.last)
      let document = try XCTUnwrap(share.document)
      XCTAssertEqual(document.store.document.width, 256)
      XCTAssertEqual(document.store.document.height, 192)
      XCTAssertEqual(document.store.document.pixelsPerInch, 300)

      for format in [DocumentIO.Format.tiff, .jpeg, .png, .psd] {
        let url = folder.appendingPathComponent("Developed." + format.rawValue)
        try DocumentIO.prepareOutput(developed, format: format, persistence: false).write(to: url)
        let localBytes = try Data(contentsOf: url)
        let remote = try await api.request(service, path: "/v1/documents/\(share.id)/file.\(format.rawValue)")
        XCTAssertEqual(remote.0.statusCode, 200, String(decoding: remote.1.prefix(200), as: UTF8.self))
        XCTAssertTrue(localBytes == remote.1, "Different developed image bytes for \(format.rawValue).")
        let reopened = try DocumentIO.read(url)
        XCTAssertEqual(reopened.width, 256)
        XCTAssertEqual(reopened.height, 192)
        XCTAssertEqual(reopened.depth, .u8)
      }
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertNil(document.fileURL)
    }
    XCTAssertEqual(try Data(contentsOf: fixture), sensor)
  }
}
