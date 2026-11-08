import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

private actor LargePeopleProbe: PeopleDetecting {
  struct Size: Equatable, Sendable { let width: Int; let height: Int }
  var sizes: [Size] = []
  func people(in image: Surface) async throws -> [DetectedObjectMask] {
    sizes.append(.init(width: image.width, height: image.height))
    return [.init(instanceID: 2, mask: try .make(.rectangle(.init(x: 64, y: 32, width: 128, height: 64)),
      width: image.width, height: image.height, antiAlias: false))]
  }
}

final class LargePeopleSelectionTests: XCTestCase {
  func testMaximumCanvasWholePersonCoverageRemainsImplicitAndReopensWithHistory() throws {
    let document = try CraftDocument(width: 300000, height: 300000)
    let analysis = try Surface(width: 1024, height: 1024, fill: .white)
    let full = try SelectionMask.make(.rectangle(.init(x: 0, y: 0, width: 1024, height: 1024)), width: 1024, height: 1024, antiAlias: false)
    let scene = try PeopleScene(source: .init(document, layerID: document.activeLayerID, sampleAllLayers: false),
      input: analysis, masks: [.init(instanceID: 1, mask: full)])
    XCTAssertTrue(scene.reducedAnalysis); XCTAssertEqual(scene.analysisWidth, 1024)
    let mask = try scene.coverage(instanceIDs: [1], hardEdge: false)
    XCTAssertTrue(mask.isPaged); XCTAssertLessThan(mask.allocatedBytes, 1024 * 1024)
    XCTAssertEqual(mask.bounds, .init(x: 0, y: 0, width: 300000, height: 300000))
    XCTAssertEqual(mask.byte(at: 0), 255); XCTAssertEqual(mask.byte(at: mask.pixelCount - 1), 255)
    XCTAssertTrue(try mask.isFullCoverage)
    let hover = try scene.hoverCoverage(instanceIDs: [1])
    XCTAssertEqual(hover.width, 1024); XCTAssertEqual(hover.height, 1024)
    var session = EditorSession(document: document)
    try session.execute(scene.command(instanceIDs: [1], mode: .replace, hardEdge: false))
    let selected = session.document
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(selected)), selected)
    try session.undo(); XCTAssertEqual(session.document, document)
    try session.redo(); XCTAssertEqual(session.document, selected)
  }
  func testMaximumSparseCoverageVisitsOnlyProjectedSupportAndSupportsAllModes() throws {
    let document = try CraftDocument(width: 300000, height: 300000)
    let sparse = try SelectionMask.make(.rectangle(.init(x: 512, y: 512, width: 1, height: 1)), width: 1024, height: 1024, antiAlias: false)
    let scene = try PeopleScene(source: .init(document, layerID: document.activeLayerID, sampleAllLayers: false),
      input: Surface(width: 1024, height: 1024), masks: [.init(instanceID: 1, mask: sparse)])
    let mask = try scene.coverage(instanceIDs: [1], hardEdge: false)
    XCTAssertTrue(mask.isPaged); XCTAssertLessThan(mask.allocatedBytes, 16 * 1024 * 1024)
    XCTAssertEqual(mask.byte(at: 0), 0); XCTAssertEqual(mask.byte(at: mask.pixelCount - 1), 0)
    XCTAssertGreaterThan(mask.byte(at: 150146 * 300000 + 150146), 250)
    for mode in SelectionMode.allCases {
      var session = EditorSession(document: document)
      try session.execute(.selection(.init(x: 150000, y: 150000, width: 300, height: 300)))
      let before = session.document
      try session.execute(scene.command(instanceIDs: [1], mode: mode, hardEdge: false))
      let after = session.document
      XCTAssertEqual(after.layers, before.layers)
      try session.undo(); XCTAssertEqual(session.document, before)
      try session.redo(); XCTAssertEqual(session.document, after)
    }
  }
  func testFeaturesAreSampledAtDocumentResolutionAndUnionFollowsPerPersonExpansion() throws {
    let document = try CraftDocument(width: 8192, height: 1)
    let key = ObjectFinderSource(document, layerID: document.activeLayerID, sampleAllLayers: false)
    let full = try SelectionMask.make(.rectangle(.init(x: 0, y: 0, width: 1024, height: 1)), width: 1024, height: 1, antiAlias: false)
    let features = try PeopleFeatureMap(width: 2, height: 1, probabilities: [0.75,0,0,0,0.25,0, 0.25,0,0,0,0.75,0])
    let scene = try PeopleScene(source: key, input: Surface(width: 1024, height: 1), masks: [.init(instanceID: 1, mask: full)], featureMap: features)
    let mask = try scene.coverage(instanceIDs: [1], hardEdge: false, features: [.clothes])
    for (x,value) in [(0,64),(2047,64),(4095,127),(4096,128),(8191,191)] {
      XCTAssertEqual(mask.byte(at: x), UInt8(value))
    }
    let hard = try scene.coverage(instanceIDs: [1], hardEdge: true, features: [.clothes])
    XCTAssertEqual(hard.byte(at: 4095), 0); XCTAssertEqual(hard.byte(at: 4096), 255)
    try capture(mask, name: "large-people-features-soft.u8")
    try capture(hard, name: "large-people-features-hard.u8")
    let masks = try [64,65].enumerated().map { index,x in
      DetectedObjectMask(instanceID: index + 1, mask: try .make(.rectangle(.init(x: x, y: 0, width: 1, height: 1)), width: 1024, height: 1, antiAlias: false))
    }
    let adjacent = try PeopleScene(source: key, input: Surface(width: 1024, height: 1), masks: masks)
    let union = try adjacent.coverage(instanceIDs: [1,2], hardEdge: false)
    XCTAssertEqual(union.byte(at: 519), 143); XCTAssertEqual(union.byte(at: 520), 143)
    try capture(union, name: "large-people-adjacent-union.u8")
  }
  func testBoundedSamplerRejectsBadRegionsAndRetainsCancellation() async throws {
    for rect in [IntRect(x: -1, y: 0, width: 1, height: 1), .init(x: 8, y: 0, width: 1, height: 1), .init(x: 0, y: 0, width: Int.max, height: 1)] {
      XCTAssertThrowsError(try SelectionMask.sampledCoverage(width: 8, height: 2, regions: [rect]) { _,_ in 255 })
    }
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      XCTAssertThrowsError(try SelectionMask.sampledCoverage(width: 300000, height: 300000, regions: []) { _,_ in 255 }) { XCTAssertTrue($0 is CancellationError) }
    }
    try await task.value
    for size in [(0,1),(-1,1),(300001,1),(Int.max,Int.max)] {
      XCTAssertThrowsError(try PeopleAnalysis.dimensions(width: size.0, height: size.1))
    }
  }
  func testLargeCurrentLayerAndExplicitCompositePreserveSourceAtEveryRGBDepth() async throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 8192, height: 2, depth: depth)
      document.layers[0] = Layer(name: "Analysis source", content: .fill(Pixel(1,0,0)))
      document.activeLayerID = document.layers[0].id; document.layers[0].visible = false
      document.layers.append(Layer(name: "Unrelated cover", content: .fill(Pixel(0,1,0))))
      let original = document
      for all in [false,true] {
        let input = try PeopleAnalysis.input(document, layerID: document.activeLayerID, allLayers: all)
        XCTAssertEqual(input.width, 1024); XCTAssertEqual(input.height, 1)
        XCTAssertEqual(input.pixel(x: 512, y: 0), all ? Pixel(0,1,0) : Pixel(1,0,0))
      }
      XCTAssertEqual(document, original)
      for content: LayerContent in [.group(.init()), .adjustment(.invert)] {
        document.layers[0].content = content
        XCTAssertThrowsError(try PeopleAnalysis.input(document, layerID: document.activeLayerID, allLayers: false))
      }
    }
  }
  func testLargeDetectionUsesBoundedInputAndPublishesDocumentResolutionCoverageWithoutChangingSource() async throws {
    var document = try CraftDocument(width: 8192, height: 1025, depth: .f32)
    document.layers[0].content = .raster(try Surface(width: 8192, height: 1025, depth: .f32, fill: .white, colorEncoding: .linearRGB))
    let original = document, detector = LargePeopleProbe()
    let scene = try await PeopleScene.detect(document, layerID: document.activeLayerID, sampleAllLayers: false, detector: detector)
    let sizes = await detector.sizes
    XCTAssertEqual(sizes, [.init(width: 1024, height: 128)])
    XCTAssertEqual(scene.people.map(\.instanceID), [2])
    XCTAssertTrue(try XCTUnwrap(scene.people.first).bounds.contains(1024, 400))
    let mask = try scene.coverage(instanceIDs: [2], hardEdge: false)
    XCTAssertEqual(mask.width, 8192); XCTAssertEqual(mask.height, 1025)
    // Literal center-aligned bilinear step: x508=1/16 and x512=9/16 coverage.
    let samples: [(Int, UInt8)] = [(507, 0), (508, 16), (512, 143), (516, 255), (1024, 255), (1540, 0)]
    for (x, expected) in samples {
      XCTAssertEqual(mask.byte(at: 400 * 8192 + x), expected, "x=\(x)")
    }
    let hard = try scene.coverage(instanceIDs: [2], hardEdge: true)
    XCTAssertEqual(hard.byte(at: 400 * 8192 + 511), 0)
    XCTAssertEqual(hard.byte(at: 400 * 8192 + 512), 255)
    XCTAssertEqual(document, original); XCTAssertEqual(scene.source.document.layers, original.layers)
    try capture(mask, name: "large-people-soft.u8")
    try capture(hard, name: "large-people-hard.u8")
  }
  private func capture(_ mask: SelectionMask, name: String) throws {
    guard let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else { return }
    try Data(mask.bytes).write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
  }
}
