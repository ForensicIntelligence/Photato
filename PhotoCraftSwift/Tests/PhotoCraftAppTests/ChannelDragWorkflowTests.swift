import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ChannelDragWorkflowTests: XCTestCase {
  private func fixture() throws -> CraftDocument {
    var document = try CraftDocument(width: 3, height: 2)
    document.layers[0].content = .raster(try Surface(width: 3, height: 2, fill: Pixel(0.2, 0.4, 0.6)))
    document.alphaChannels = try ["Matte", "Subject", "Background"].enumerated().map { index, name in
      var pixels = try Surface(width: 3, height: 2, fill: .black)
      pixels.setPixel(x: index, y: 0, .white)
      return AlphaChannel(name: name, pixels: pixels)
    }
    return document
  }

  @MainActor func testSavedChannelDragReordersAndDeletesTheRowWithoutFlattening() async throws {
    var original = try fixture()
    var hidden = Layer(name: "Hidden", content: original.layers[0].content)
    hidden.visible = false
    original.layers.append(hidden)
    let store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    let channels = try XCTUnwrap(original.alphaChannels)
    try store.selectAlphaChannel(channels[1].id)
    var provider = ChannelDrag.provider(store: store, source: .alpha(channels[0].id))
    XCTAssertFalse(ChannelDrag.canReceive(.reorder(.alpha(channels[1].id), after: false), in: store))
    let moved = await ChannelDrag.receive(provider, destination: .reorder(.alpha(channels[2].id), after: true), in: store)
    XCTAssertTrue(moved)
    XCTAssertEqual(store.document.alphaChannels, [channels[1], channels[2], channels[0]])
    XCTAssertEqual(store.session.undoStack.count, 1)
    provider = ChannelDrag.provider(store: store, source: .alpha(channels[0].id))
    let deleted = await ChannelDrag.receive(provider, destination: .trash, in: store)
    XCTAssertTrue(deleted)
    XCTAssertEqual(store.document.alphaChannels, [channels[1], channels[2]])
    XCTAssertEqual(store.document.layers, original.layers)
    XCTAssertEqual(store.session.undoStack.count, 2)
    await store.undo()
    await store.undo()
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testProcessTrashFollowsDraggedComponentAndMatchesMenuCommandBytes() async throws {
    var original = try fixture()
    var hidden = Layer(name: "Hidden", content: original.layers[0].content)
    hidden.visible = false
    original.layers.append(hidden)
    let store = EditorStore(document: original)
    defer { store.renderTask?.cancel(); store.geometryTask?.cancel() }
    var prompts = 0
    store.flattenImageConfirmation = { _ in prompts += 1; return false }
    try store.selectColorComponentRow(0, modifiers: [])
    let provider = ChannelDrag.provider(store: store, source: .component(2))
    let accepted = await ChannelDrag.receive(provider, destination: .trash, in: store)
    XCTAssertTrue(accepted)
    await store.geometryTask?.value
    XCTAssertEqual(prompts, 0)
    XCTAssertNil(store.error)
    XCTAssertEqual(store.document.colorChannelNames, ["Cyan", "Magenta"])
    XCTAssertEqual(store.document.alphaChannels, original.alphaChannels)
    XCTAssertEqual(store.session.undoStack.count, 1)
    var expected = original
    try InkModeInput.deleteProcess(.init(mode: .rgb, components: [2], mergeVisible: true), in: original).apply(to: &expected)
    XCTAssertEqual(try expected.inkChannel(expected.inkChannelTargets[0]), try store.document.inkChannel(store.document.inkChannelTargets[0]))
    XCTAssertEqual(try expected.inkChannel(expected.inkChannelTargets[1]), try store.document.inkChannel(store.document.inkChannelTargets[1]))
    await store.undo()
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testNewChannelTargetDuplicatesNumericalDataAndRejectsReusedOrForeignPayload() async throws {
    let original = try fixture()
    let store = EditorStore(document: original)
    let other = EditorStore(document: try CraftDocument(width: 3, height: 2))
    defer { store.renderTask?.cancel(); store.geometryTask?.cancel(); other.renderTask?.cancel() }
    let channel = try XCTUnwrap(original.alphaChannels?.first)
    let old = ChannelDrag.provider(store: store, source: .alpha(channel.id))
    let provider = ChannelDrag.provider(store: store, source: .alpha(channel.id))
    let foreign = await ChannelDrag.receive(provider, destination: .duplicate, in: other)
    XCTAssertFalse(foreign)
    let superseded = await ChannelDrag.receive(old, destination: .duplicate, in: store)
    XCTAssertFalse(superseded)
    XCTAssertFalse(ChannelDrag.receive(Data("other application".utf8), destination: .duplicate, in: store))
    let accepted = await ChannelDrag.receive(provider, destination: .duplicate, in: store)
    XCTAssertTrue(accepted)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    let copied = try XCTUnwrap(store.document.alphaChannels?.last)
    XCTAssertNotEqual(copied.id, channel.id)
    XCTAssertEqual(copied.name, "Matte copy")
    XCTAssertEqual(copied.pixels, channel.pixels)
    XCTAssertEqual(store.alphaEditingID, copied.id)
    XCTAssertEqual(store.session.undoStack.count, 1)
    let reused = await ChannelDrag.receive(provider, destination: .duplicate, in: store)
    XCTAssertFalse(reused)
    await store.undo()
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testMatchingOpenImageAcceptsCrossDocumentDropAndOnlyDestinationChanges() async throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let original = try fixture()
    let source = CraftNSDocument(model: original)
    let destination = CraftNSDocument(model: try CraftDocument(width: 3, height: 2, depth: .u16))
    let mismatch = CraftNSDocument(model: try CraftDocument(width: 4, height: 2))
    for document in [source, destination, mismatch] {
      controller.addDocument(document)
    }
    let destinationBefore = destination.store.document
    let channel = try XCTUnwrap(original.alphaChannels?.first)
    let provider = ChannelDrag.provider(store: source.store, source: .alpha(channel.id))
    XCTAssertFalse(ChannelDrag.canReceive(.canvas, in: source.store))
    XCTAssertFalse(ChannelDrag.canReceive(.canvas, in: mismatch.store))
    XCTAssertTrue(ChannelDrag.canReceive(.canvas, in: destination.store))
    let accepted = await ChannelDrag.receive(provider, destination: .canvas, in: destination.store)
    XCTAssertTrue(accepted)
    await destination.store.geometryTask?.value
    XCTAssertNil(destination.store.error)
    let copied = try XCTUnwrap(destination.store.document.alphaChannels?.last)
    XCTAssertEqual(copied.name, channel.name)
    XCTAssertEqual(copied.pixels.depth, .u16)
    XCTAssertEqual(copied.pixels.pixel(x: 0, y: 0), .white)
    XCTAssertEqual(copied.pixels.pixel(x: 1, y: 0).r, 0)
    XCTAssertEqual(source.store.document, original)
    XCTAssertTrue(source.store.session.undoStack.isEmpty)
    XCTAssertEqual(destination.store.session.undoStack.count, 1)
    await destination.store.undo()
    XCTAssertEqual(destination.store.document, destinationBefore)
  }

  @MainActor func testDocumentRevisionAndLastPlateProtectDragTransactions() async throws {
    var original = try CraftDocument(width: 3, height: 2)
    let samples = try InkPlane(width: 3, height: 2, depth: .u8, value: 0.5)
    let a = InkPlate(name: "Cyan", color: Pixel(0, 1, 1), solidity: 0, samples: samples)
    let b = InkPlate(name: "Dark", color: .black, solidity: 0, samples: samples)
    original = try original.replacingInkMode(.multichannel(.init(plates: [a, b])))
    let store = EditorStore(document: original)
    defer { store.renderTask?.cancel(); store.geometryTask?.cancel() }
    var provider = ChannelDrag.provider(store: store, source: .plate(a.id))
    let accepted = await ChannelDrag.receive(provider, destination: .reorder(.plate(b.id), after: true), in: store)
    XCTAssertTrue(accepted)
    await store.geometryTask?.value
    XCTAssertEqual(store.document.inkChannelTargets, [.plate(b.id), .plate(a.id)])
    provider = ChannelDrag.provider(store: store, source: .plate(b.id))
    await store.undo()
    let stale = await ChannelDrag.receive(provider, destination: .trash, in: store)
    XCTAssertFalse(stale)
    XCTAssertEqual(store.document, original)
    provider = ChannelDrag.provider(store: store, source: .plate(b.id))
    let deleted = await ChannelDrag.receive(provider, destination: .trash, in: store)
    XCTAssertTrue(deleted)
    await store.geometryTask?.value
    provider = ChannelDrag.provider(store: store, source: .plate(a.id))
    let finalPlate = await ChannelDrag.receive(provider, destination: .trash, in: store)
    XCTAssertFalse(finalPlate)
    XCTAssertEqual(store.document.inkChannelTargets, [.plate(a.id)])
    XCTAssertEqual(store.session.undoStack.count, 1)
  }
}
