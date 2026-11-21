import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

private struct GroupFixture: RemoveDistractionDetecting {
  func detectDistractions(in input: Surface) async throws -> [RemoveDistractionMark] {
    func rect(_ x: Int) throws -> SelectionMask {
      try .make(.rectangle(.init(x: x, y: 7, width: 4, height: 4)), width: input.width, height: input.height, antiAlias: false)
    }
    return [.init(category: .visualClutter, mask: try rect(19)),
      .init(category: .poles, mask: try rect(5)), .init(category: .poles, mask: try rect(9))]
  }
}

final class RemoveDistractionSceneTests: XCTestCase {
  func testCategoryMasksComposeBeforeOrderedBrushAndSelectionClipping() async throws {
    var source = try CraftDocument(width: 32, height: 24)
    source.layers[0].locked = false
    let layer = source.layers[0].id, original = source
    let groups = try await RemoveDistractionPreparation.detect(source, layerID: layer, settings: .init(), detector: GroupFixture())
    XCTAssertEqual(groups.map(\.category), [.poles, .visualClutter])
    XCTAssertEqual(groups.map(\.count), [2, 1])
    XCTAssertEqual(groups[0].coverage.bounds, IntRect(x: 5, y: 7, width: 8, height: 4))
    XCTAssertEqual(groups[1].coverage.bounds, IntRect(x: 19, y: 7, width: 4, height: 4))
    XCTAssertEqual(source, original)
    source.selection = .init(x: 0, y: 0, width: 18, height: source.height)
    let mark = RemoveRequest(layerID: layer, settings: .init(), strokes: [
      .init(size: 1, subtract: true, points: [[6.5, 8.5]]),
      .init(size: 1, points: [[17.5, 15.5]])], categoryCoverages: groups.map(\.coverage))
    let beforeSelection = try RemovePreparation.markCoverage(mark, in: source)
    let applied = try RemovePreparation.coverage(mark, in: source)
    XCTAssertEqual(beforeSelection.coverage(x: 20, y: 8), 1)
    XCTAssertEqual(applied.coverage(x: 20, y: 8), 0)
    XCTAssertEqual(applied.coverage(x: 5, y: 7), 1)
    XCTAssertEqual(applied.coverage(x: 6, y: 8), 0)
    XCTAssertEqual(applied.coverage(x: 17, y: 15), 1)
    XCTAssertThrowsError(try RemovePreparation.markCoverage(.init(layerID: layer, settings: .init(),
      strokes: [], categoryCoverages: [try SelectionMask.make(.rectangle(.init(x: 0, y: 0, width: 1, height: 1)), width: 1, height: 1)]), in: source))
  }

  func testDustMarksIsolatedBrightAndDarkSpotsAndProtectsEdgesAndSubject() throws {
    var input = try Surface(width: 96, height: 64, fill: Pixel(0.53, 0.55, 0.56))
    for y in 0..<64 { for x in 75..<96 { input.setPixel(x: x, y: y, .black) } }
    input.setPixel(x: 15, y: 18, .black); input.setPixel(x: 40, y: 30, .white)
    input.setPixel(x: 59, y: 15, .black)
    let marks = try XCTUnwrap(DistractionDustDetection.detect(input, protected: [.init(x: 55, y: 10, width: 12, height: 12)]))
    XCTAssertEqual(marks.category, .spotsAndDust); XCTAssertEqual(marks.count, 2)
    XCTAssertEqual(marks.mask.coverage(x: 15, y: 18), 1)
    XCTAssertEqual(marks.mask.coverage(x: 40, y: 30), 1)
    XCTAssertEqual(marks.mask.coverage(x: 59, y: 15), 0)
    XCTAssertEqual(marks.mask.coverage(x: 75, y: 21), 0)
  }

  func testObjectRepairMarginIsVisibleAndRespectsNearbyProtectedSubject() throws {
    let object = try SelectionMask.make(.rectangle(.init(x: 6, y: 7, width: 6, height: 5)),
      width: 24, height: 24, antiAlias: false)
    let protection = IntRect(x: 12, y: 6, width: 7, height: 10)
    let mask = try XCTUnwrap(NativeDistractionDetection.reviewCoverage(object, from: [protection]))
    XCTAssertEqual(mask.coverage(x: 3, y: 8), 1)
    XCTAssertEqual(mask.coverage(x: 2, y: 8), 0)
    XCTAssertEqual(mask.coverage(x: 12, y: 9), 0)
    XCTAssertEqual(mask.coverage(x: 9, y: 9), 1)
    XCTAssertNil(try NativeDistractionDetection.reviewCoverage(object,
      from: [.init(x: 4, y: 4, width: 12, height: 12)]))
  }

  func testProposalSuppressionKeepsDifferentCategoriesWhenBoxesTouch() {
    let combined = IntRect(x: 10, y: 10, width: 20, height: 26)
    let nested = IntRect(x: 12, y: 12, width: 14, height: 16)
    let bench = DistractionProposal(category: .identifiedObjects, bounds: combined, confidence: 0.65)
    let bin = DistractionProposal(category: .visualClutter, bounds: nested, confidence: 0.41)
    let expandedBench = DistractionProposal(category: .identifiedObjects, bounds: nested, confidence: 0.41)
    XCTAssertFalse(CoreMLDistractionDetector.duplicates(bench, bin))
    XCTAssertTrue(CoreMLDistractionDetector.duplicates(bench, expandedBench))
  }

  func testLocalReviewSamplesChosenSourceAndKeepsOutputAndSelection() throws {
    for depth: PixelDepth in [.u8, .u16, .f32] {
      var source = try CraftDocument(width: 40, height: 36, depth: depth)
      let layerID = source.layers[0].id
      let target = try Surface(width: 40, height: 36, depth: depth, fill: Pixel(0.75, 0.1, 0.1))
      source.layers[0].locked = false
      source.layers[0].content = .raster(target)
      source.layers.append(Layer(name: "Visible blue guide", content: .raster(try Surface(width: 40,
        height: 36, depth: depth, fill: Pixel(0.1, 0.1, 0.75)))))
      source.selection = .init(x: 14, y: 12, width: 8, height: 8)
      let marks = try SelectionMask.make(.rectangle(.init(x: 12, y: 14, width: 14, height: 6)),
        width: 40, height: 36, antiAlias: false)
      for sampleAllLayers in [false, true] {
        var settings = RemoveToolSettings()
        settings.sampleAllLayers = sampleAllLayers
        settings.createNewLayer = sampleAllLayers
        let request = RemoveRequest(layerID: layerID, settings: settings, strokes: [], categoryCoverages: [marks])
        let (layer, input, mask) = try RemovePreparation.guides(request, document: source)
        let edit = try RemovePreparation.prepareLocalReview(request, source: source, input: input,
          layer: layer, mask: mask) { image, selected in
          let plane = LocalGenerativeFill.side * LocalGenerativeFill.side
          let i = 100 * LocalGenerativeFill.side + 100
          XCTAssertEqual(selected[i], 0)
          XCTAssertGreaterThan(image[(sampleAllLayers ? 2 * plane : 0) + i], 0.7)
          return try Surface(width: LocalGenerativeFill.side, height: LocalGenerativeFill.side, fill: Pixel(0.15, 0.7, 0.15))
        }
        XCTAssertEqual(edit.result.selection, source.selection)
        XCTAssertEqual(edit.result.selectionMask, source.selectionMask)
        XCTAssertEqual(edit.result.layers.last, source.layers.last)
        if sampleAllLayers {
          XCTAssertEqual(edit.result.layers[0], source.layers[0])
          XCTAssertEqual(edit.result.layers[1].name, "Remove")
          XCTAssertEqual(edit.result.layers[1].x, 14)
          XCTAssertEqual(edit.result.layers[1].y, 14)
        } else {
          guard case .raster(let result) = edit.result.layers[0].content else { return XCTFail("Missing raster") }
          XCTAssertEqual(result.pixel(x: 13, y: 16), target.pixel(x: 13, y: 16))
          XCTAssertNotEqual(result.pixel(x: 17, y: 17), target.pixel(x: 17, y: 17))
        }
      }
    }
  }
}
