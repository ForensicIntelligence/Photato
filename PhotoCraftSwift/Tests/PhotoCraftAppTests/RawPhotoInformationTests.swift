import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftImaging

final class RawPhotoInformationTests: XCTestCase {
  private func source(timestamp: String, lens: String, caption: String) throws -> Data {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let bytes = try Data(contentsOf: directory.appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng"))
    let packet = Data("""
      <x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
       <rdf:RDF><rdf:Description rdf:about="" xmlns:exif="http://ns.adobe.com/exif/1.0/"
           xmlns:aux="http://ns.adobe.com/exif/1.0/aux/" xmlns:dc="http://purl.org/dc/elements/1.1/"
           exif:DateTimeOriginal="\(timestamp)" aux:Lens="\(lens)">
        <dc:description><rdf:Alt><rdf:li xml:lang="x-default">\(caption)</rdf:li></rdf:Alt></dc:description>
        <dc:rights><rdf:Alt><rdf:li xml:lang="x-default">Owned test fixture</rdf:li></rdf:Alt></dc:rights>
       </rdf:Description></rdf:RDF>
      </x:xmpmeta>
      """.utf8)
    return try RawSourceIO.replacingDNGXMP(bytes) { _ in packet }
  }

  @MainActor func testFilmstripMetadataSortUsesCaptureInstantsAndKeepsSelection() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let later = directory.appendingPathComponent("B - Later.dng")
    let earlier = directory.appendingPathComponent("A - Earlier.dng")
    let sourceA = try source(timestamp: "2026-11-28T09:00:00+02:00", lens: "85 mm Prime", caption: "First exposure")
    let sourceB = try source(timestamp: "2026-11-28T06:00:00-05:00", lens: "24 mm Prime", caption: "Second exposure")
    try sourceA.write(to: earlier)
    try sourceB.write(to: later)
    let workspace = RawFilmstripWorkspace(controller: controller)
    defer { workspace.close() }
    workspace.start([later, earlier])
    await workspace.waitUntilIdle()
    XCTAssertNil(workspace.error)
    let active = try XCTUnwrap(workspace.activeInformation)
    XCTAssertEqual(active.fileName, later.lastPathComponent)
    XCTAssertEqual(active.camera, "Synthetic Bayer Test")
    XCTAssertEqual(active.lens, "24 mm Prime")
    XCTAssertEqual(active.captureDate, "2026-11-28T06:00:00-05:00")
    XCTAssertEqual(active.caption, "Second exposure")
    XCTAssertEqual(active.copyright, "Owned test fixture")
    XCTAssertEqual(active.width, 512)
    XCTAssertEqual(active.height, 384)
    XCTAssertEqual(active.byteCount, sourceB.count)
    let selection = workspace.selection
    workspace.order = .captureDate
    XCTAssertEqual(workspace.displayedPhotos.map(\.name), [earlier.lastPathComponent, later.lastPathComponent])
    XCTAssertEqual(workspace.selection, selection)
    workspace.order = .lens
    XCTAssertEqual(workspace.displayedPhotos.map(\.name), [later.lastPathComponent, earlier.lastPathComponent])
    XCTAssertEqual(workspace.activeInformation, active)
    XCTAssertEqual(try Data(contentsOf: earlier), sourceA)
    XCTAssertEqual(try Data(contentsOf: later), sourceB)
  }

  @MainActor func testAuthenticatedRawInspectShowsOriginalMetadataWithoutHistory() async throws {
    let helper = AutomationTests()
    let raw = try source(timestamp: "2026-11-28T09:00:00+02:00", lens: "85 mm Prime", caption: "Owned capture")
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      let model = try RawSourceIO.open(raw, fileName: "Owned.dng")
      let document = CraftNSDocument(model: model)
      service.controller.addDocument(document)
      defer { document.close() }
      try service.share(document)
      let share = try XCTUnwrap(service.shares.last)
      let layer = try XCTUnwrap(model.layers.first)
      let result = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: [
        "command": "raw.inspect", "revision": service.revision(document.store),
        "parameters": ["layerID": layer.id.uuidString],
      ])
      XCTAssertEqual(result.0.statusCode, 200, String(decoding: result.1.prefix(400), as: UTF8.self))
      let data = try XCTUnwrap(JSONSerialization.jsonObject(with: result.1) as? [String: Any])
      let info = try XCTUnwrap(data["photoInformation"] as? [String: Any])
      XCTAssertEqual(info["fileName"] as? String, "Owned.dng")
      XCTAssertEqual(info["byteCount"] as? Int, raw.count)
      XCTAssertEqual(info["lens"] as? String, "85 mm Prime")
      XCTAssertEqual(info["caption"] as? String, "Owned capture")
      XCTAssertEqual(info["type"] as? String, "com.adobe.raw-image")
      XCTAssertNil(info["captureOrder"])
      XCTAssertEqual(document.store.document, model)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
}
