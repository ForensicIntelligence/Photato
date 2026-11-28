import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftImaging

final class RawGridWorkflowTests: XCTestCase {
  @MainActor func testGridSharesPhotographsFiltersRatingsAndBatchAdjustmentUndo() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let directory = try makeFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try fixture()
    let urls = ["D.dng", "A.dng", "C.dng", "B.dng"].map { directory.appendingPathComponent($0) }
    for url in urls { try bytes.write(to: url) }
    let workspace = RawFilmstripWorkspace(controller: controller)
    defer { workspace.close() }
    workspace.start(urls)
    await workspace.waitUntilIdle()
    XCTAssertNil(workspace.error)
    XCTAssertEqual(workspace.presentation, .loupe)

    workspace.order = .name
    let visible = workspace.displayedPhotos
    XCTAssertEqual(visible.map(\.name), ["A.dng", "B.dng", "C.dng", "D.dng"])
    XCTAssertTrue(workspace.handlePresentationKey(try key("g")))
    XCTAssertEqual(workspace.presentation, .grid)
    workspace.select(visible[0].id)
    workspace.moveGridSelection(.down, columns: 2, extending: true)
    XCTAssertEqual(workspace.selection, Set(visible.prefix(3).map(\.id)))
    XCTAssertEqual(workspace.activeID, visible[2].id)
    XCTAssertTrue(workspace.handleMarkingKey(try key("4")))
    XCTAssertTrue(workspace.handleMarkingKey(try key("6")))
    workspace.toggleLabelFilter(.red)
    workspace.setRatingFilter(.four)
    XCTAssertEqual(workspace.displayedPhotos.map(\.name), ["A.dng", "B.dng", "C.dng"])

    var adjustment = try XCTUnwrap(workspace.activeSettings)
    adjustment.adjustments.exposure = 0.75
    workspace.apply(adjustment, to: visible[2].id)
    XCTAssertEqual(workspace.displayedPhotos.map { $0.settings.adjustments.exposure }, [0.75, 0.75, 0.75])
    XCTAssertEqual(workspace.photos.first { $0.id == visible[3].id }?.settings.adjustments.exposure, 0)
    workspace.undoEdit()
    XCTAssertEqual(workspace.displayedPhotos.map { $0.settings.adjustments.exposure }, [0, 0, 0])
    workspace.redoEdit()
    workspace.openInLoupe(visible[1].id)
    await workspace.waitUntilIdle()
    XCTAssertEqual(workspace.presentation, .loupe)
    XCTAssertEqual(workspace.editor?.id, visible[1].id)
    XCTAssertEqual(workspace.selection, Set(visible.prefix(3).map(\.id)))
    XCTAssertEqual(workspace.activeSettings?.adjustments.exposure, 0.75)
    for url in urls { XCTAssertEqual(try Data(contentsOf: url), bytes) }
  }

  @MainActor func testGridKeyboardSizeAndDetailDoNotConsumeLoupeKeysOrChangeSelection() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let directory = try makeFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Owned.dng")
    try fixture().write(to: url)
    let workspace = RawFilmstripWorkspace(controller: controller)
    defer { workspace.close() }
    workspace.start([url])
    await workspace.waitUntilIdle()
    let selected = workspace.selection

    XCTAssertFalse(workspace.handlePresentationKey(try key(".")))
    XCTAssertFalse(workspace.handlePresentationKey(try key("-", modifiers: .option)))
    XCTAssertFalse(workspace.handlePresentationKey(try key("g", modifiers: .command)))
    XCTAssertTrue(workspace.handlePresentationKey(try key("g")))
    XCTAssertTrue(workspace.handlePresentationKey(try key(".")))
    XCTAssertEqual(workspace.gridDetails, .image)
    XCTAssertTrue(workspace.handlePresentationKey(try key(",")))
    XCTAssertEqual(workspace.gridDetails, .all)
    XCTAssertTrue(workspace.handlePresentationKey(try key("=", modifiers: .option)))
    XCTAssertGreaterThan(workspace.gridThumbnailSize, RawFilmstripWorkspace.defaultGridSize)
    workspace.resizeGrid(-1)
    XCTAssertEqual(workspace.gridThumbnailSize, RawFilmstripWorkspace.gridSizeRange.lowerBound)
    workspace.resizeGrid(.infinity)
    XCTAssertEqual(workspace.gridThumbnailSize, RawFilmstripWorkspace.gridSizeRange.lowerBound)
    XCTAssertFalse(workspace.handlePresentationKey(try key(".", modifiers: .command)))
    XCTAssertEqual(workspace.selection, selected)
    XCTAssertFalse(workspace.canUndo)
  }

  @MainActor func testDevelopedFilmstripThumbnailTracksActiveDraftWithoutTouchingOriginal() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let directory = try makeFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Owned.dng")
    let bytes = try fixture()
    try bytes.write(to: url)
    let workspace = RawFilmstripWorkspace(controller: controller)
    defer { workspace.close() }
    workspace.start([url])
    await workspace.waitUntilIdle()
    let editor = try XCTUnwrap(workspace.editor)
    let draft = try XCTUnwrap(editor.store.filterDraft)
    let model = CameraRawWorkspace()
    defer { model.close() }
    var madeThumbnails = [CGImage]()
    model.onThumbnail = { image, settings in
      madeThumbnails.append(image)
      workspace.updateThumbnail(image, settings: settings, photoID: editor.id)
    }
    model.onSensorChange = { settings in workspace.apply(settings, to: editor.id) }
    await model.prepare(document: editor.store.document, draft: draft, retainRawOutput: true)
    XCTAssertTrue(model.ready)
    let first = try XCTUnwrap(madeThumbnails.first)
    XCTAssertEqual(first.width, 288)
    XCTAssertEqual(first.height, 216)
    let firstPhoto = try XCTUnwrap(workspace.photos.first)
    XCTAssertTrue(workspace.thumbnail(for: firstPhoto) === first)

    var edited = try XCTUnwrap(workspace.activeSettings)
    edited.adjustments.exposure = 0.75
    model.changeSensor(edited)
    if let editorTask = model.task { await editorTask.value }
    let second = try XCTUnwrap(madeThumbnails.last)
    XCTAssertEqual(madeThumbnails.count, 2)
    let current = try XCTUnwrap(workspace.photos.first)
    XCTAssertTrue(workspace.thumbnail(for: current) === second)
    XCTAssertNotEqual(first.dataProvider?.data as Data?, second.dataProvider?.data as Data?)

    workspace.undoEdit()
    let restored = try XCTUnwrap(workspace.photos.first)
    XCTAssertEqual(restored.settings, firstPhoto.settings)
    XCTAssertFalse(workspace.thumbnail(for: restored) === second)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  @MainActor func testFilmstripVisibilityScopesContextAndRecoversAnEmptyGrid() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let directory = try makeFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try fixture()
    let urls = ["A.dng", "B.dng", "C.dng", "D.dng"].map { directory.appendingPathComponent($0) }
    for url in urls { try bytes.write(to: url) }
    let workspace = RawFilmstripWorkspace(controller: controller)
    defer { workspace.close() }
    workspace.start(urls)
    await workspace.waitUntilIdle()
    let ids = workspace.displayedPhotos.map(\.id)
    XCTAssertEqual(ids.count, 4)
    workspace.select(ids[1], extending: true)
    XCTAssertEqual(workspace.visibilityTargets(contextPhoto: ids[0]), Set(ids[0...1]))
    XCTAssertEqual(workspace.visibilityTargets(contextPhoto: ids[3]), [ids[3]])
    workspace.hidePhotos(contextPhoto: ids[3])
    XCTAssertEqual(workspace.selection, Set(ids[0...1]))
    XCTAssertEqual(workspace.displayedPhotos.map(\.id), Array(ids.prefix(3)))
    workspace.hidePhotos(contextPhoto: ids[0])
    XCTAssertEqual(workspace.activeID, ids[2])
    XCTAssertEqual(workspace.selection, [ids[2]])
    workspace.presentation = .grid
    workspace.hidePhotos()
    XCTAssertEqual(workspace.hiddenPhotoCount, 4)
    XCTAssertNil(workspace.activeID)
    XCTAssertTrue(workspace.selection.isEmpty)
    XCTAssertTrue(workspace.canWrite)
    XCTAssertFalse(workspace.canUndo)
    workspace.showAllHiddenPhotos()
    XCTAssertEqual(workspace.displayedPhotos.map(\.id), ids)
    XCTAssertEqual(workspace.activeID, ids[0])

    workspace.showOnlyPhotos(contextPhoto: ids[2])
    XCTAssertEqual(workspace.displayedPhotos.map(\.id), [ids[2]])
    workspace.selectAll()
    XCTAssertEqual(workspace.selection, [ids[2]])
    workspace.showAllHiddenPhotos()
    workspace.select(ids[1])
    workspace.select(ids[2], extending: true)
    workspace.showOnlyPhotos()
    XCTAssertEqual(workspace.displayedPhotos.map(\.id), [ids[1], ids[2]])
    XCTAssertFalse(workspace.canUndo)
    for url in urls { XCTAssertEqual(try Data(contentsOf: url), bytes) }
  }

  @MainActor func testSessionVisibilityKeepsFiltersAndHiddenEditsSurviveDoneAndReopen() async throws {
    _ = NSApplication.shared
    let preferences = CameraRawPreferences()
    preferences.dngStorage = .embedXMP
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(), cameraRawPreferences: preferences)
    let directory = try makeFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try fixture()
    let urls = ["Edited.dng", "Unedited.dng"].map { directory.appendingPathComponent($0) }
    for url in urls { try bytes.write(to: url) }
    let workspace = RawFilmstripWorkspace(controller: controller)
    workspace.start(urls)
    await workspace.waitUntilIdle()
    workspace.setLabel(.red)
    workspace.toggleLabelFilter(.red)
    workspace.hidePhotos()
    XCTAssertEqual(workspace.hiddenPhotoCount, 1)
    XCTAssertTrue(workspace.displayedPhotos.isEmpty)
    workspace.showAllHiddenPhotos()
    XCTAssertEqual(workspace.labelFilters, [.red])
    XCTAssertEqual(workspace.displayedPhotos.map(\.name), ["Edited.dng"])
    workspace.hidePhotos()
    workspace.clearFilters()
    XCTAssertEqual(workspace.displayedPhotos.map(\.name), ["Unedited.dng"])
    XCTAssertTrue(workspace.canUndo)
    workspace.finish(nil)
    await workspace.waitUntilIdle()
    XCTAssertNil(workspace.error)
    XCTAssertTrue(workspace.closed)

    let reopened = RawFilmstripWorkspace(controller: controller)
    defer { reopened.close() }
    reopened.start(urls)
    await reopened.waitUntilIdle()
    XCTAssertEqual(reopened.hiddenPhotoCount, 0)
    XCTAssertEqual(reopened.displayedPhotos.map(\.name), urls.map(\.lastPathComponent))
    XCTAssertEqual(reopened.photos.first?.marking.label, "Red")
    XCTAssertEqual(try Data(contentsOf: urls[1]), bytes)
  }

  private func makeFolder() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
  }

  private func fixture() throws -> Data {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try Data(contentsOf: directory.appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng"))
  }

  private func key(_ characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
      windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
      isARepeat: false, keyCode: 0))
  }
}
