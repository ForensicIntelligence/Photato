import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class LevelsAnalysisWorkflowTests: XCTestCase {
  @MainActor func testAnalysisCacheCancellationAndLatestRequest() async throws {
    var d = try CraftDocument(width: 4, height: 2)
    let target = Layer(name: "Levels", content: .adjustment(.levels(.init())))
    d.layers.append(target)
    let request = LevelsAnalysisRequest(document: d, layerID: target.id, pixelLayer: false)
    d.layers[1].content = .adjustment(.levels(.init(red: .init(gamma: 0.5))))
    XCTAssertEqual(request, .init(document: d, layerID: target.id, pixelLayer: false))
    let analysis = LevelsAnalysis()
    analysis.update(request)
    await analysis.task?.value
    XCTAssertEqual(analysis.histogram?.samples, 8)
    XCTAssertFalse(analysis.busy)
    var second = request
    second.document.layers[0].content = .raster(try Surface(width: 4, height: 2, fill: .black))
    analysis.update(second)
    analysis.cancel()
    await analysis.task?.value
    XCTAssertNil(analysis.request)
    XCTAssertNil(analysis.histogram)
    analysis.update(request)
    analysis.update(second)
    await analysis.task?.value
    XCTAssertEqual(analysis.histogram?.channels[0][0], 8)
    XCTAssertNil(analysis.error)
    XCTAssertFalse(analysis.busy)
  }
  @MainActor func testAutomaticCorrectionWorkflowCancellationAndUndo() async throws {
    var d = try CraftDocument(width: 16, height: 4)
    var s = try Surface(width: 16, height: 4)
    s.mapPixels { x, _, _ in Pixel(Float(x + 40) / 255, Float(x + 80) / 255, Float(x + 120) / 255) }
    d.layers[0].content = .raster(s)
    let store = EditorStore(document: d)
    defer { store.renderTask?.cancel() }
    store.autoCorrect(.tone)
    await store.geometryTask?.value
    XCTAssertNotEqual(store.document, d)
    XCTAssertEqual(store.session.undoStack.last?.label, "Auto Tone")
    await store.undo()
    XCTAssertEqual(store.document, d)
    store.autoCorrect(.color)
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertFalse(store.geometryBusy)
    store.beginLevels()
    store.autoCorrect(.contrast)
    XCTAssertEqual(store.document, d)
    store.cancelLevels()
  }
  func testPresetFileLoadBoundsAndOriginalRetention() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("Example.alv")
    let levels = BuiltInLevelsPreset.brighter.levels
    let data = try LevelsPresetCodec.write(levels)
    try data.write(to: url)
    let file = try LevelsPresetFile.load(url)
    XCTAssertEqual(file.levels, levels)
    XCTAssertEqual(file.original, data)
    try Data(repeating: 0, count: 5000).write(to: url)
    XCTAssertThrowsError(try LevelsPresetFile.load(url))
  }
}
