import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class GenerativeRemoveTests: XCTestCase {
  func testSparseMaximumCanvasEditsDistantMarksAndKeepsTheOriginalSelection() throws {
    var source = try CraftDocument(width: 300000, height: 300000)
    source.layers[0].locked = false
    let base = Pixel(0.4, 0.5, 0.6)
    let raster = try Surface(width: source.width, height: source.height, fill: base)
    source.layers[0].content = .raster(raster)
    let regions = [IntRect(x: 118, y: 110, width: 10, height: 12),
      IntRect(x: 299875, y: 299880, width: 12, height: 10)]
    source.setCoverageSelection(try .sampledCoverage(width: source.width, height: source.height, regions: regions) { x, y in
      regions.contains { $0.contains(x, y) } ? 255 : 0
    })
    let id = source.layers[0].id
    let strokes = [RemoveStroke(size: 21, points: [[121, 115]]), RemoveStroke(size: 21, points: [[299880, 299885]])]
    for newLayer in [false, true] {
      var settings = RemoveToolSettings()
      settings.mode = .generativeOn; settings.createNewLayer = newLayer
      let request = RemoveRequest(layerID: id, settings: settings, strokes: strokes)
      let inputs = try RemovePreparation.generativeGuides(request, document: source)
      XCTAssertTrue(inputs.2.isPaged)
      XCTAssertLessThan(inputs.2.allocatedBytes, 1_000_000)
      var calls = 0
      let prepared = try RemovePreparation.prepareGenerative(request, source: source, prepared: inputs) { _, marks in
        calls += 1
        XCTAssertTrue(marks.contains(0)); XCTAssertTrue(marks.contains(1))
        return try Surface(width: 512, height: 512, fill: Pixel(0.1, 0.8, 0.2))
      }
      XCTAssertEqual(calls, 2)
      let edited = try prepared.applied(to: source)
      XCTAssertEqual(edited.selection, source.selection)
      XCTAssertEqual(edited.selectionMask, source.selectionMask)
      guard let layer = edited.layers.last, case .raster(let output) = layer.content else { return XCTFail("Missing repair layer") }
      if newLayer { XCTAssertEqual(edited.layers.first, source.layers[0]) }
      let protected = output.pixel(x: 150000 - layer.x, y: 150000 - layer.y)
      XCTAssertEqual(protected, newLayer ? .clear : raster.pixel(x: 150000, y: 150000))
      for (x, y) in [(121, 115), (299880, 299885)] {
        XCTAssertNotEqual(output.pixel(x: x - layer.x, y: y - layer.y), protected)
      }
      XCTAssertLessThan(output.allocatedBytes, 3_000_000)
    }
  }

  func testOverlappingModelPredictionsBlendAtTheRepairBoundary() throws {
    var source = try CraftDocument(width: 1350, height: 140)
    source.layers[0].locked = false
    let sourcePixels = try Surface(width: source.width, height: source.height, fill: Pixel(0.5, 0.5, 0.5))
    source.layers[0].content = .raster(sourcePixels)
    var settings = RemoveToolSettings(); settings.mode = .generativeOn
    let strokes = [RemoveStroke(size: 67, points: [[255, 70], [1250, 70]])]
    let request = RemoveRequest(layerID: source.layers[0].id, settings: settings, strokes: strokes)
    let inputs = try RemovePreparation.generativeGuides(request, document: source)
    var predictions = 0
    let edit = try RemovePreparation.prepareGenerative(request, source: source, prepared: inputs) { _, _ in
      predictions += 1
      return try Surface(width: 512, height: 512, fill: Pixel(Float(predictions) * 0.20, 0.2, 0.8))
    }
    XCTAssertEqual(predictions, 3)
    guard case .raster(let pixels) = edit.result.layers[0].content else { return XCTFail("Missing painted output") }
    let left = try XCTUnwrap(inputs.2.bounds).x
    for seam in [left + 512, left + 1024] {
      XCTAssertLessThan(abs(pixels.pixel(x: seam, y: 70).r - pixels.pixel(x: seam - 1, y: 70).r), 0.04)
    }
    XCTAssertNotEqual(pixels.pixel(x: 450, y: 70), pixels.pixel(x: 1150, y: 70))
    XCTAssertEqual(pixels.pixel(x: 512, y: 18), sourcePixels.pixel(x: 512, y: 18))
  }
}
