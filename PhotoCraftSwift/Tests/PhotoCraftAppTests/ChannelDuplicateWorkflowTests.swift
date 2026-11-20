import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class ChannelDuplicateWorkflowTests: XCTestCase {
  private func componentSource(mode: DocumentColorMode = .cmyk, width: Int = 8, height: Int = 5) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: height, depth: .u16, name: "Owned proof")
    var native = try NativeModeRaster(width: width, height: height, mode: mode, depth: .u16)
    native = try native.replacingOpacity(with: Surface(width: width, height: height, depth: .u16, fill: .white))
    try native.set(Float(12345) / 65535, component: mode.componentCount - 1, index: width * height - 1)
    try native.set(Float(54321) / 65535, component: mode.componentCount - 1, index: 2)
    document.modeDescriptor = try .init(mode: mode, depth: .u16, profile: native.profile)
    document.layers[0].nativeMode = native
    document.layers[0].content = .raster(try native.surface())
    document.layers[0].background = true
    document.selection = IntRect(x: 0, y: 0, width: 1, height: 1)
    document.resolution = 244
    return document
  }

  func testMaximumCMYKBlackDuplicateInvertsExactlyAndPersistsTheEntirePlane() throws {
    let document = try componentSource(width: 300_000, height: 300_000)
    let last = document.width * document.height - 1
    guard case .document(let result, let id) = try ChannelDuplication.prepare(.component(3), in: document,
      to: nil, name: "Black copy", documentName: "Plate proof") else { return XCTFail("Expected a channel document") }
    XCTAssertTrue(result.isChannelOnly)
    XCTAssertEqual(result.colorMode, .multichannel)
    XCTAssertEqual(result.name, "Plate proof")
    XCTAssertNotEqual(result.id, document.id)
    XCTAssertEqual(result.resolution, 244)
    XCTAssertNil(result.selection)
    let plane = try result.channel(.alpha(id)).pixels
    XCTAssertTrue(plane.allocatedBytes + plane.mappedBytes < 4_000_000)
    for (index, word) in [(0, 65535), (2, 65535 - 54321), (last, 65535 - 12345)] {
      XCTAssertEqual(plane.pixel(x: index % document.width, y: index / document.width).r, Float(word) / 65535)
    }
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(result)), result)
    guard case .edit(let edit, let invertedID) = try ChannelDuplication.prepare(.component(3), in: document,
      to: document, name: "Density", invert: true) else { return XCTFail("Expected a destination edit") }
    var session = EditorSession(document: document)
    try session.execute(edit)
    let density = try session.document.channel(.alpha(invertedID)).pixels
    XCTAssertEqual(density.defaultPixel.r, 0)
    XCTAssertEqual(density.pixel(x: document.width - 1, y: document.height - 1).r, Float(12345) / 65535)
    XCTAssertEqual(session.document.selection, document.selection)
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo()
    XCTAssertEqual(session.document, document)
  }

  func testInkCopiesRetainNameColorSolidityAndNumericWordsInBothDestinations() throws {
    let ink = try InkPlane(width: 3, height: 1, depth: .u16, bytes: Data([0xff, 0xff, 0x39, 0x30, 0, 0]))
    let first = InkPlate(name: "Spot A", color: Pixel(0.2, 0.9, 0.1), solidity: 0.33, samples: ink)
    let document = try CraftDocument(width: 3, height: 1, depth: .u16)
      .replacingInkMode(.multichannel(MultichannelRaster(plates: [first])))
    guard case .document(let created, let channelID) = try ChannelDuplication.prepare(.plate(first.id), in: document,
      to: nil, name: "Spot copy", documentName: "Spot mask", invert: true),
      case .multichannel(let plates) = created.inkMode else { return XCTFail("Expected a printing-plate document") }
    XCTAssertEqual(plates.plates.count, 1)
    let copied = try XCTUnwrap(plates.plates.first)
    XCTAssertEqual(copied.id, channelID)
    XCTAssertNotEqual(copied.id, first.id)
    XCTAssertEqual(copied.name, "Spot copy")
    XCTAssertEqual(copied.color, first.color)
    XCTAssertEqual(copied.solidity, first.solidity)
    XCTAssertEqual((0..<3).map(copied.samples.rawWord), (0..<3).map { 65535 - first.samples.rawWord(at: $0) })

    var ordinary = try CraftDocument(width: 3, height: 1, depth: .u8)
    guard case .edit(let command, let copiedID) = try ChannelDuplication.prepare(.plate(first.id), in: document,
      to: ordinary, name: "Cross depth") else { return XCTFail("Expected a spot destination edit") }
    try command.apply(to: &ordinary)
    let saved = try ordinary.channel(.alpha(copiedID))
    XCTAssertEqual(saved.spot, SpotInk(color: first.color, solidity: first.solidity))
    XCTAssertEqual(saved.pixels.pixel(x: 1, y: 0).r, PixelDepth.u8.quantize(Float(12345) / 65535))
    XCTAssertNil(saved.psdIdentifier)
  }

  @MainActor func testNativeDuplicateSheetCancelsThenCopiesOnlyToChosenDocumentWithUndo() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let source = try componentSource(mode: .rgb)
    let sourceFile = CraftNSDocument(model: source)
    let target = try CraftDocument(width: source.width, height: source.height, name: "Destination")
    let targetFile = CraftNSDocument(model: target)
    let wrongFile = CraftNSDocument(model: try CraftDocument(width: 2, height: 3, name: "Wrong dimensions"))
    for file in [sourceFile, targetFile, wrongFile] { controller.addDocument(file) }
    controller.documentWindows.activeDocument = sourceFile
    sourceFile.makeWindowControllers()
    sourceFile.showWindows()
    let editor = try XCTUnwrap(sourceFile.windowForSheet)
    defer {
      sourceFile.store.cancelChannelDialog()
      for file in [sourceFile, targetFile, wrongFile] {
        file.store.renderTask?.cancel()
        file.updateChangeCount(.changeCleared)
        file.close()
      }
    }
    try sourceFile.store.selectModeComponents([2])
    XCTAssertEqual(sourceFile.store.selectedDuplicateChannel, .component(2))
    sourceFile.store.beginDuplicateChannel(sourceFile.store.selectedDuplicateChannel)
    let draft = try XCTUnwrap(sourceFile.store.channelDialog)
    XCTAssertEqual(Set(draft.documents.map(\.id)), [source.id, target.id])
    XCTAssertEqual(draft.name, "Blue copy")
    for _ in 0..<120 where editor.attachedSheet == nil { try await Task.sleep(for: .milliseconds(25)) }
    XCTAssertNotNil(editor.attachedSheet)
    sourceFile.store.cancelChannelDialog()
    for _ in 0..<120 where editor.attachedSheet != nil { try await Task.sleep(for: .milliseconds(25)) }
    XCTAssertNil(editor.attachedSheet)
    XCTAssertEqual(sourceFile.store.document, source)
    sourceFile.store.beginDuplicateChannel(.component(2))
    let selected = try XCTUnwrap(sourceFile.store.channelDialog)
    selected.name = "Blue mask"
    selected.documentID = target.id
    sourceFile.store.commitChannelDialog(selected)
    await selected.task?.value
    XCTAssertNil(sourceFile.store.channelDialog, selected.error ?? "")
    XCTAssertEqual(sourceFile.store.document, source)
    XCTAssertTrue(sourceFile.store.session.undoStack.isEmpty)
    let copied = try XCTUnwrap(targetFile.store.document.alphaChannels?.first)
    XCTAssertEqual(copied.name, "Blue mask")
    XCTAssertEqual(copied.pixels.pixel(x: 2, y: 0).r, PixelDepth.u8.quantize(Float(54321) / 65535))
    XCTAssertEqual(targetFile.store.session.undoStack.count, 1)
    await targetFile.store.undo()
    XCTAssertEqual(targetFile.store.document, target)
  }

  @MainActor func testAuthenticatedCopiesRequireBothRevisionsAndNewDocumentPermission() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let source = try self.componentSource(mode: .rgb)
      file.store.session = EditorSession(document: source)
      try service.share(file)
      let sourceShare = try XCTUnwrap(service.shares.first)
      let other = CraftNSDocument(model: try CraftDocument(width: source.width, height: source.height, depth: .u16, name: "Target"))
      service.controller.addDocument(other)
      try service.share(other)
      defer {
        for doc in service.controller.documents.compactMap({ $0 as? CraftNSDocument }) where doc !== file {
          doc.store.renderTask?.cancel()
          doc.updateChangeCount(.changeCleared)
          doc.close()
        }
      }
      let otherShare = try XCTUnwrap(service.shares.first { $0.document === other })
      let baseline = other.store.document
      @MainActor func copy(_ destination: [String: Any], revision: String? = nil) async throws -> (Int, [String: Any]) {
        let body: [String: Any] = ["command": ChannelDuplicateAPI.name, "revision": revision ?? service.revision(file.store),
          "parameters": ["source": ["kind": "component", "component": 2], "destination": destination, "name": "Owned channel", "invert": true]]
        let response = try await AutomationTests().request(service, path: "/v1/documents/\(sourceShare.id)/commands", body: body, timeout: 20)
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
        return (response.0.statusCode, state)
      }
      let staleSource = try await copy(["kind": "current"], revision: "old")
      XCTAssertEqual(staleSource.0, 409)
      let staleDestination = try await copy(["kind": "open", "shareID": otherShare.id.uuidString, "revision": "old"])
      XCTAssertEqual(staleDestination.0, 409)
      XCTAssertEqual(other.store.document, baseline)

      let remote = try await copy(["kind": "open", "shareID": otherShare.id.uuidString, "revision": service.revision(other.store)])
      XCTAssertEqual(remote.0, 200, "\(remote.1)")
      let remoteID = try XCTUnwrap((remote.1["channelID"] as? String).flatMap(UUID.init(uuidString:)))
      let plane = try other.store.document.channel(.alpha(remoteID)).pixels
      XCTAssertEqual(plane.pixel(x: 2, y: 0).r, Float(65535 - 54321) / 65535)
      XCTAssertEqual(other.store.session.undoStack.count, 1)
      await other.store.undo()
      XCTAssertEqual(other.store.document, baseline)
      XCTAssertEqual(file.store.document, source)

      let denied = try await copy(["kind": "new", "name": "New proof"])
      XCTAssertEqual(denied.0, 403)
      service.setDocumentTransfersEnabled(true)
      let new = try await copy(["kind": "new", "name": "New proof"])
      XCTAssertEqual(new.0, 201, "\(new.1)")
      let newShare = try XCTUnwrap((new.1["document"] as? [String: Any])?["id"] as? String)
      let output = try XCTUnwrap(service.shares.first { $0.id.uuidString == newShare }?.document)
      XCTAssertEqual(output.store.document.name, "New proof")
      XCTAssertTrue(output.store.document.isChannelOnly)
      XCTAssertEqual(output.store.document.alphaChannels?.first?.pixels, plane)
      XCTAssertTrue(output.store.session.undoStack.isEmpty)
      XCTAssertNil(output.fileURL)

      let current = try await copy(["kind": "current"])
      XCTAssertEqual(current.0, 200, "\(current.1)")
      XCTAssertEqual(file.store.document.alphaChannels?.first?.pixels, plane)
      await file.store.undo()
      XCTAssertEqual(file.store.document, source)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
}
