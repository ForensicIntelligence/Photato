import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PortableLinkedArtworkTests: XCTestCase {
  private func artwork(_ color: Pixel, at url: URL) throws -> Data {
    let bytes = try LinkedArtworkWorkflowTests().artwork(color)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: url)
    return bytes
  }

  private func add(_ link: LinkedSmartObjectSource, bytes: Data, named name: String,
    to document: inout CraftDocument) throws {
    let layer = try LinkedSmartObjectIO.place(bytes, fileName: name, reference: link, in: document)
    try Command.addLayer(layer).apply(to: &document)
  }

  @MainActor func testMovedPSBFindsNestedRelativeSourceAndUsesItThroughHTTPAndPackage() async throws {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, document in
      let root = try LinkedArtworkWorkflowTests().folder()
      defer { try? FileManager.default.removeItem(at: root); document.store.linkedSourceController?.stop() }
      let staging = root.appendingPathComponent("Job")
      let folder = root.appendingPathComponent("Moved Job")
      let relativePath = "Artwork/Approved Marks/Logo.png"
      let absoluteSource = root.appendingPathComponent("Old Location/Logo.png")
      let originalBytes = try self.artwork(Pixel(0.8, 0.2, 0.1), at: absoluteSource)
      let newBytes = try self.artwork(Pixel(0.1, 0.2, 0.8), at: staging.appendingPathComponent(relativePath))
      let source = try LinkedSmartObjectSource(reference: absoluteSource.path,
        contentHash: LinkedSmartObjectSource.fingerprint(originalBytes), byteLength: UInt64(originalBytes.count),
        relativePath: relativePath)
      var authored = try CraftDocument(width: 16, height: 12, name: "Portable")
      try self.add(source, bytes: originalBytes, named: "Logo.png", to: &authored)
      try PSDCodec.writeRasterLayers(authored, to: staging.appendingPathComponent("Portable.psb"), format: .psb)
      try FileManager.default.moveItem(at: staging, to: folder)
      let psb = folder.appendingPathComponent("Portable.psb")
      let initial = try DocumentIO.read(psb)
      let store = document.store
      let registry = LinkedSourceRegistry(persistent: false)
      store.linkedSourceRegistry = registry
      store.session = EditorSession(document: initial)
      store.onChange = nil
      document.fileURL = nil
      document.importedSourceURL = psb
      XCTAssertTrue(store.hasRelativePackageLinks)
      XCTAssertFalse(store.canPackageLinkedArtwork)
      let savedLink = try XCTUnwrap(store.activeLayer?.smartObject?.linkedSource)
      XCTAssertEqual(savedLink.reference, absoluteSource.path)
      XCTAssertEqual(savedLink.relativePath, relativePath)
      _ = try service.authorizeLinkedArtwork(absoluteSource, registry: registry)
      XCTAssertThrowsError(try registry.resolve(savedLink, documentID: initial.id, documentURL: psb))
      try registry.authorizePackage(folder, document: initial, documentURL: psb)
      let grant = try registry.resolve(savedLink, documentID: initial.id, documentURL: psb)
      XCTAssertEqual(try LinkedArtworkRead.read(grant).data, newBytes)

      try service.share(document)
      let helper = AutomationTests()
      let blocked = try await helper.edit(service, document, "smartObject.linked.update")
      XCTAssertEqual(blocked, 403)
      XCTAssertEqual(store.document, initial)
      let moved = folder.appendingPathComponent(relativePath)
      _ = try service.authorizeLinkedArtwork(moved, registry: registry)
      let updated = try await helper.edit(service, document, "smartObject.linked.update")
      XCTAssertEqual(updated, 200)
      XCTAssertEqual(store.activeLayer?.smartObject?.data, newBytes)
      XCTAssertEqual(store.activeLayer?.smartObject?.linkedSource?.reference, absoluteSource.path)
      XCTAssertEqual(store.activeLayer?.smartObject?.linkedSource?.relativePath, relativePath)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let edited = store.document
      await store.undo()
      XCTAssertEqual(store.document, initial)
      await store.redo()
      XCTAssertEqual(store.document, edited)
      XCTAssertEqual(try Data(contentsOf: absoluteSource), originalBytes)

      try await document.persistDocument(to: folder.appendingPathComponent("Portable.photato"), format: .native,
        operation: .saveAsOperation)
      XCTAssertTrue(store.canPackageLinkedArtwork)
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(root)
      let package = try await helper.edit(service, document, "smartObject.linked.package",
        ["name": "repackaged", "format": "psb"])
      XCTAssertEqual(package, 200)
      XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("repackaged/Links/Logo.png")), newBytes)
    }
  }

  @MainActor func testAuthorizedRelativeThenOriginalBookmarkThenAdjacentSource() throws {
    let root = try LinkedArtworkWorkflowTests().folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Folder")
    let psd = folder.appendingPathComponent("Document.psd")
    let nested = folder.appendingPathComponent("Subfolder/Logo.png")
    let absolute = root.appendingPathComponent("Original/Logo.png")
    let adjacent = folder.appendingPathComponent("Logo.png")
    let relativeBytes = try artwork(Pixel(1, 0, 0), at: nested)
    let absoluteBytes = try artwork(Pixel(0, 1, 0), at: absolute)
    let adjacentBytes = try artwork(Pixel(0, 0, 1), at: adjacent)
    let registry = LinkedSourceRegistry(persistent: false)
    let absoluteGrant = try registry.authorize(absolute)
    let link = try LinkedSmartObjectSource(reference: absoluteGrant.reference, authorizationID: absoluteGrant.id,
      contentHash: LinkedSmartObjectSource.fingerprint(absoluteBytes), byteLength: UInt64(absoluteBytes.count),
      relativePath: ".\\Subfolder\\Logo.png")
    var document = try CraftDocument(width: 16, height: 12)
    try add(link, bytes: absoluteBytes, named: "Logo.png", to: &document)
    func resolved() throws -> LinkedArtworkRead {
      try LinkedArtworkRead.read(registry.resolve(link, documentID: document.id, documentURL: psd))
    }
    XCTAssertEqual(try resolved().data, absoluteBytes)
    try registry.authorizePackage(folder, document: document, documentURL: psd)
    XCTAssertEqual(try resolved().data, relativeBytes)
    try FileManager.default.moveItem(at: nested, to: root.appendingPathComponent("Unlinked.png"))
    XCTAssertEqual(try resolved().data, absoluteBytes)
    try FileManager.default.moveItem(at: absolute, to: root.appendingPathComponent("Moved Original.png"))
    XCTAssertEqual(try resolved().data, absoluteBytes)
    try registry.revoke(absoluteGrant.id)
    let fallback = try resolved()
    XCTAssertEqual(fallback.data, adjacentBytes)
    XCTAssertEqual(try fallback.reference.relativePath, link.relativePath)
  }

  @MainActor func testFolderLookupSkipsMissingAndOutOfFolderSources() throws {
    let root = try LinkedArtworkWorkflowTests().folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Package")
    let documentURL = folder.appendingPathComponent("Document.psd")
    let outside = root.appendingPathComponent("Outside.png")
    let source = try artwork(Pixel(0.1, 0.6, 0.4), at: outside)
    _ = try artwork(Pixel(0.1, 0.6, 0.4), at: folder.appendingPathComponent("Artwork/Good.png"))
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("External.png"), withDestinationURL: outside)
    let registry = LinkedSourceRegistry(persistent: false)
    var document = try CraftDocument(width: 16, height: 12)
    let paths = ["Artwork/Good.png", "../Outside.png", "External.png", "Artwork/Missing.png"]
    let links = try paths.map { path in
      try LinkedSmartObjectSource(reference: outside.path, contentHash: LinkedSmartObjectSource.fingerprint(source),
        byteLength: UInt64(source.count), relativePath: path)
    }
    for (index, link) in links.enumerated() {
      try add(link, bytes: source, named: "Layer\(index).png", to: &document)
    }
    XCTAssertThrowsError(try registry.authorizePackage(root, document: document, documentURL: documentURL))
    XCTAssertThrowsError(try registry.resolve(links[0], documentID: document.id, documentURL: documentURL))
    try registry.authorizePackage(folder, document: document, documentURL: documentURL)
    XCTAssertEqual(try LinkedArtworkRead.read(registry.resolve(links[0], documentID: document.id,
      documentURL: documentURL)).data, source)
    for link in links.dropFirst() {
      XCTAssertThrowsError(try registry.resolve(link, documentID: document.id, documentURL: documentURL))
    }
  }
}
