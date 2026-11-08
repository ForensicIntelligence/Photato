import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

private struct FullPersonDistractionDetector: PeopleDetecting {
  func people(in image: Surface) async throws -> [DetectedObjectMask] {
    let coverage = try Surface(width: image.width, height: image.height, fill: .white)
    return [.init(instanceID: 1, mask: try SelectionMask(coverage: coverage))]
  }
}
private struct NoProtectedPreparationSubject: ForegroundDetecting {
  func mask(for image: Surface) async throws -> SelectionMask {
    try SelectionMask(width: image.width, height: image.height, bytes: Array(repeating: 0, count: image.width * image.height))
  }
}

private actor DistractionInputSpy: PeopleDetecting {
  var sampled: Pixel?
  func people(in image: Surface) async throws -> [DetectedObjectMask] {
    sampled = image.pixel(x: 12, y: 12)
    let mask = try SelectionMask.make(.rectangle(.init(x: 10, y: 10, width: 4, height: 4)), width: image.width, height: image.height, antiAlias: false)
    return [.init(instanceID: 1, mask: mask)]
  }
}

final class PeopleDistractionPreparationTests: XCTestCase {
  func testDetectedSeedAndOrderedRefinementsRespectExactOriginalSelection() throws {
    var doc = try RemovePreparationTests().fixture(); doc.selection = .init(x: 0, y: 0, width: 12, height: 24)
    let seed = try SelectionMask.make(.rectangle(.init(x: 10, y: 10, width: 4, height: 4)), width: 24, height: 24, antiAlias: false)
    let request = RemoveRequest(layerID: doc.layers[0].id, settings: .init(),
      strokes: [.init(size: 1, subtract: true, points: [[10.5, 10.5]])], initialCoverage: seed)
    let marks = try RemovePreparation.markCoverage(request, in: doc), effective = try RemovePreparation.coverage(request, in: doc)
    XCTAssertEqual(marks.byte(at: 10 * 24 + 10), 0); XCTAssertEqual(marks.byte(at: 12 * 24 + 13), 255)
    XCTAssertEqual(effective.byte(at: 12 * 24 + 13), 0); XCTAssertEqual(effective.byte(at: 12 * 24 + 11), 255)
    XCTAssertEqual(doc.selection, .init(x: 0, y: 0, width: 12, height: 24)); XCTAssertNil(doc.selectionMask)
    let result = try RemovePreparation.prepare(request, document: doc).result
    XCTAssertEqual(result.selection, doc.selection); XCTAssertEqual(result.selectionMask, doc.selectionMask)
  }
  func testSeedOnlyRemovalKeepsProtectedSampleWordsAndReopensAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let doc = try RemovePreparationTests().fixture(depth)
      let seed = try SelectionMask.make(.rectangle(.init(x: 10, y: 10, width: 4, height: 4)), width: 24, height: 24, antiAlias: false)
      let request = RemoveRequest(layerID: doc.layers[0].id, settings: .init(), strokes: [], initialCoverage: seed)
      let result = try RemovePreparation.prepare(request, document: doc).result
      guard case .raster(let before) = doc.layers[0].content, case .raster(let after) = result.layers[0].content else { return XCTFail("Raster missing") }
      let expected = depth == .f32 ? before.linearPixel(x: 0, y: 0) : before.pixel(x: 0, y: 0)
      for y in 0..<24 { for x in 0..<24 {
        let p = depth == .f32 ? after.linearPixel(x: x, y: y) : after.pixel(x: x, y: y)
        XCTAssertEqual([p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern], [expected.r.bitPattern,expected.g.bitPattern,expected.b.bitPattern,expected.a.bitPattern])
      } }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)), result)
    }
  }
  func testInvalidSeedDimensionsEmptyRequestsAndCancelledPreparationRejectBeforeEditing() async throws {
    let doc = try RemovePreparationTests().fixture(), id = doc.layers[0].id
    let wrong = try SelectionMask(coverage: Surface(width: 2, height: 2, fill: .white))
    XCTAssertThrowsError(try RemovePreparation.markCoverage(.init(layerID: id, settings: .init(), strokes: [], initialCoverage: wrong), in: doc))
    XCTAssertThrowsError(try RemoveRequest(layerID: id, settings: .init(), strokes: []).validate())
    let seed = try SelectionMask.make(.rectangle(.init(x: 10, y: 10, width: 4, height: 4)), width: 24, height: 24, antiAlias: false)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try RemovePreparation.prepare(.init(layerID: id, settings: .init(), strokes: [], initialCoverage: seed), document: doc)
    }
    do { _ = try await task.value; XCTFail("Cancelled preparation succeeded") } catch is CancellationError { }
    XCTAssertEqual(doc.layers.count, 1); XCTAssertNil(doc.selectionMask)
  }
  func testDetectionUsesExplicitSourceAndKeepsLargeOverlayBounded() async throws {
    var doc = try RemovePreparationTests().fixture(); let original = doc.layers[0]
    let donor = Layer(name: "Owned green visible donor", content: .raster(try Surface(width: 24, height: 24, fill: Pixel(0, 1, 0))))
    doc.layers.append(donor)
    let currentSpy = DistractionInputSpy(), allSpy = DistractionInputSpy()
    var settings = RemoveToolSettings(); settings.createNewLayer = true
    _ = try await RemovePeoplePreparation.detect(doc, layerID: original.id, settings: settings, detector: currentSpy, foregroundDetector: NoProtectedPreparationSubject())
    settings.sampleAllLayers = true
    _ = try await RemovePeoplePreparation.detect(doc, layerID: original.id, settings: settings, detector: allSpy, foregroundDetector: NoProtectedPreparationSubject())
    let current = await currentSpy.sampled, all = await allSpy.sampled
    XCTAssertEqual(current, Pixel(1, 0, 0)); XCTAssertEqual(all, Pixel(0, 1, 0))
    XCTAssertEqual(doc.layers[0], original); XCTAssertEqual(doc.layers[1], donor)
    var large = try CraftDocument(width: 4097, height: 2049); large.layers[0].locked = false
    let detection = try await RemovePeoplePreparation.detect(large, layerID: large.layers[0].id, settings: .init(), detector: FullPersonDistractionDetector(), foregroundDetector: NoProtectedPreparationSubject())
    XCTAssertEqual(detection.count, 1); XCTAssertEqual(detection.coverage?.bounds, .init(x: 0, y: 0, width: 4097, height: 2049))
    XCTAssertLessThanOrEqual(try XCTUnwrap(detection.overlay).width, 2048); XCTAssertLessThanOrEqual(try XCTUnwrap(detection.overlay).height, 2048)
  }
  func testForegroundPersonIsExcludedWholeWhileIndependentBackgroundPersonRemains() throws {
    let doc = try RemovePreparationTests().fixture(), input = try Surface(width: 24, height: 24, fill: .white)
    let main = try SelectionMask.make(.rectangle(.init(x: 2, y: 2, width: 10, height: 18)), width: 24, height: 24, antiAlias: false)
    let other = try SelectionMask.make(.rectangle(.init(x: 17, y: 5, width: 3, height: 6)), width: 24, height: 24, antiAlias: false)
    let scene = try PeopleScene(source: .init(doc, layerID: doc.layers[0].id, sampleAllLayers: false), input: input,
      masks: [.init(instanceID: 1, mask: main), .init(instanceID: 2, mask: other)])
    XCTAssertEqual(try RemovePeoplePreparation.distractionIDs(scene, foreground: main), [2])
    XCTAssertEqual(try RemovePeoplePreparation.distractionIDs(scene, foreground: nil), [1, 2])
    let all = try SelectionMask(coverage: Surface(width: 24, height: 24, fill: .white))
    XCTAssertEqual(try RemovePeoplePreparation.distractionIDs(scene, foreground: all), [])
    let invalid = try SelectionMask(coverage: Surface(width: 2, height: 2, fill: .white))
    XCTAssertThrowsError(try RemovePeoplePreparation.distractionIDs(scene, foreground: invalid))
  }

}
