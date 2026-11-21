import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RemoveWiresPreparationTests: XCTestCase {
  func testReducedDetectorFindsWideFrameCrossingCableAndKeepsShortRidges() throws {
    let width = 512, height = 384
    var luma = Array(repeating: Float(169), count: width * height)
    for y in 102...114 {
      for x in 0..<width { luma[y * width + x] = 48 }
    }
    for y in 200...212 {
      for x in 182..<290 { luma[y * width + x] = 48 }
    }
    for y in 309..<height {
      for x in 0..<width { luma[y * width + x] = 61 }
    }
    let result = try WireRidgeDetection.detect(luma: luma, width: width, height: height, reduced: true)
    XCTAssertEqual(result.trackCount, 1)
    let cable = result.normals[(102 * width)..<(115 * width)]
    XCTAssertTrue(cable.allSatisfy { $0 > 0 })
    XCTAssertTrue(result.normals.suffix(from: 195 * width).allSatisfy { $0 == 0 })
  }

  func testOnlyWireWithinSelectionChangesAtEachRGBDepth() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 112, height: 68, depth: depth)
      var source = try Surface(width: doc.width, height: doc.height, depth: depth, fill: Pixel(0.66, 0.75, 0.9))
      for x in 0..<doc.width { source.setPixel(x: x, y: 20, Pixel(0.12, 0.11, 0.14)) }
      for y in 45..<doc.height {
        for x in 0..<doc.width { source.setPixel(x: x, y: y, Pixel(0.42, 0.3, 0.2)) }
      }
      doc.layers[0].content = .raster(source); doc.layers[0].locked = false
      doc.selection = .init(x: 12, y: 0, width: 56, height: doc.height)
      var options = RemoveToolSettings(); options.createNewLayer = false; options.sampleAllLayers = false
      let result = try RemoveWiresPreparation.prepare(doc, layerID: doc.layers[0].id, settings: options)
      XCTAssertTrue(result.applied); XCTAssertEqual(result.candidateTracks, 1)
      XCTAssertEqual(result.edit.result.selection, doc.selection); XCTAssertNil(result.edit.result.selectionMask)
      guard case .raster(let repaired) = result.edit.result.layers[0].content else { return XCTFail("Missing wire result") }
      let sky = source.linearPixel(x: 0, y: 0)
      for y in 0..<doc.height {
        for x in 0..<doc.width {
          let expected = y == 20 && (12..<68).contains(x) ? sky : source.linearPixel(x: x, y: y)
          XCTAssertEqual(repaired.linearPixel(x: x, y: y), expected, "\(depth), \(x), \(y)")
        }
      }
      var session = EditorSession(document: doc)
      try session.executePrepared(PreparedEdit(command: .regionRetouch(result.edit), document: doc))
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo(); XCTAssertEqual(session.document, doc)
      try session.redo(); XCTAssertEqual(session.document, result.edit.result)
    }
  }

  func testSamplesVisibleLayersAndCommitsAnEditablePatchAboveTheOldCanvasLimit() throws {
    var doc = try CraftDocument(width: 4200, height: 4000)
    var photo = try Surface(width: doc.width, height: doc.height, fill: Pixel(0.7, 0.81, 0.92))
    let wire = Pixel(0.1, 0.12, 0.13)
    for y in 1000..<1006 {
      for x in 0..<photo.width { photo.setPixel(x: x, y: y, wire) }
    }
    doc.layers[0].content = .raster(photo)
    var target = Layer(name: "Retouch target", content: .raster(try Surface(width: doc.width, height: doc.height)))
    target.locked = true; doc.layers.append(target); doc.activeLayerID = target.id
    doc.selection = .init(x: 1390, y: 900, width: 350, height: 200)
    var options = RemoveToolSettings(); options.createNewLayer = true
    options.sampleAllLayers = false
    let local = try RemoveWiresPreparation.prepare(doc, layerID: target.id, settings: options)
    XCTAssertFalse(local.applied)
    options.sampleAllLayers = true
    let result = try RemoveWiresPreparation.prepare(doc, layerID: target.id, settings: options)
    XCTAssertTrue(result.applied); XCTAssertEqual(result.candidateTracks, 1)
    XCTAssertEqual(Array(result.edit.result.layers.prefix(2)), doc.layers)
    XCTAssertEqual(result.edit.result.selection, doc.selection)
    let output = try XCTUnwrap(result.edit.result.layers.last)
    XCTAssertEqual(output.name, "Remove Wires and Cables")
    XCTAssertEqual(output.id, result.edit.result.activeLayerID)
    let repaired = try Renderer.composite(result.edit.result, region: .init(x: 1370, y: 970, width: 410, height: 65))
    XCTAssertEqual(repaired.pixel(x: 1600, y: 1002), photo.pixel(x: 1600, y: 970))
    XCTAssertEqual(repaired.pixel(x: 1389, y: 1002), photo.pixel(x: 1389, y: 1002))
  }

  func testNoWireOrProtectedSelectionReturnsTheOriginalDocument() throws {
    var doc = try CraftDocument(width: 144, height: 112)
    var pixels = try Surface(width: doc.width, height: doc.height, fill: Pixel(0.2, 0.6, 0.8))
    for y in 59..<doc.height {
      for x in 0..<doc.width { pixels.setPixel(x: x, y: y, Pixel(0.07, 0.2, 0.14)) }
    }
    doc.layers[0].content = .raster(pixels); doc.layers[0].locked = false
    var settings = RemoveToolSettings(); settings.createNewLayer = false; settings.sampleAllLayers = false
    let first = try RemoveWiresPreparation.prepare(doc, layerID: doc.layers[0].id, settings: settings)
    XCTAssertFalse(first.applied); XCTAssertEqual(first.candidateTracks, 0); XCTAssertEqual(first.edit.result, doc)
    for x in 0..<doc.width { pixels.setPixel(x: x, y: 20, Pixel(0.01, 0.01, 0.02)) }
    doc.layers[0].content = .raster(pixels)
    doc.selection = .init(x: 0, y: 50, width: doc.width, height: 18)
    let second = try RemoveWiresPreparation.prepare(doc, layerID: doc.layers[0].id, settings: settings)
    XCTAssertFalse(second.applied); XCTAssertEqual(second.candidateTracks, 1); XCTAssertEqual(second.edit.result, doc)
    settings.mode = .generativeOn
    XCTAssertThrowsError(try RemoveWiresPreparation.prepare(doc, layerID: doc.layers[0].id, settings: settings))
  }
}
