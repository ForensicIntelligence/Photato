import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class LayerStampTests: XCTestCase {
  private func fixture(_ name: String) throws -> CraftDocument {
    let url = try XCTUnwrap(Bundle.module.url(
      forResource: name, withExtension: "psd", subdirectory: "Fixtures/layer-stamp"))
    return try PSDCodec.read(Data(contentsOf: url))
  }

  func testPhotoshopStampNamesPositionsAndSamples() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let cases: [(source: String, result: String, operation: LayerMergeOperation, targets: [String])] = [
      ("root-stack", "stamp-visible", .stampVisible, ["Middle"]),
      ("root-stack", "stamp-selected", .stampSelected, ["Low", "Middle"]),
      ("hidden-upper", "hidden-top-selected", .stampSelected, ["Middle", "Layer 1"]),
      ("inside-group", "cross-parent-selected", .stampSelected, ["Low", "Middle"]),
      ("inside-group", "cross-parent-half-opacity", .stampSelected, ["Low", "Middle"]),
      ("inside-group", "cross-parent-isolated", .stampSelected, ["Low", "Middle"]),
      ("inside-group", "cross-parent-hidden-group", .stampSelected, ["Low", "Middle"]),
      ("inside-group", "stamp-single-group", .stampSelected, ["Folder"]),
      ("root-stack", "locked-active", .stampVisible, ["Middle"]),
      ("root-stack", "clipping-base-active", .stampVisible, ["Middle"]),
      ("root-stack", "duplicate-selected-name", .stampSelected, ["Low", "Middle"]),
      ("root-stack", "naming-gap", .stampVisible, ["Middle"]),
    ]
    for sample in cases {
      var source = try fixture(sample.source)
      let active = try XCTUnwrap(source.layers.first { $0.name == sample.targets.last }?.id, sample.result)
      source.activeLayerID = active
      if sample.result == "locked-active" { source.layers[1].locked = true }
      if sample.result == "clipping-base-active" { source.layers[2].clipped = true }
      if sample.result == "duplicate-selected-name" { source.layers[2].name = "Middle (merged)" }
      if sample.result == "naming-gap" { source.layers[2].name = "Layer 9" }
      if sample.result == "cross-parent-half-opacity" { source.layers[2].opacity = Float(128) / 255 }
      if sample.result == "cross-parent-isolated" { source.layers[2].content = .group(.init(passThrough: false)) }
      if sample.result == "cross-parent-hidden-group" { source.layers[2].visible = false }
      source.selection = IntRect(x: 0, y: 0, width: 1, height: 1)
      let ids = Set(source.layers.filter { sample.targets.contains($0.name) }.map(\.id))
      let expected = try fixture("\(architecture)-\(sample.source)-\(sample.result)")
      let prepared = try LayerMergePreparation.prepare(source, layerIDs: ids, operation: sample.operation)
      let result = try prepared.applied(to: source)
      XCTAssertEqual(result.layers.map(\.name), expected.layers.map(\.name), sample.result)
      XCTAssertEqual(result.layers.filter { $0.id != result.activeLayerID }, source.layers, sample.result)
      XCTAssertEqual(result.selection, source.selection, sample.result)
      let index = try XCTUnwrap(result.layers.firstIndex { $0.id == result.activeLayerID }, sample.result)
      let stamp = result.layers[index]
      let reference = expected.layers[index]
      XCTAssertEqual(stamp.name, reference.name, sample.result)
      XCTAssertEqual(stamp.x, reference.x, sample.result)
      XCTAssertEqual(stamp.y, reference.y, sample.result)
      XCTAssertEqual(stamp.parentID, source.layers.first { $0.id == active }?.parentID, sample.result)
      XCTAssertFalse(stamp.isBackground, sample.result)
      XCTAssertFalse(stamp.isClipped, sample.result)
      guard case .raster(let pixels) = stamp.content, case .raster(let expectedPixels) = reference.content else {
        XCTFail("Missing raster for \(sample.result)")
        continue
      }
      XCTAssertEqual(pixels.width, expectedPixels.width, sample.result)
      XCTAssertEqual(pixels.height, expectedPixels.height, sample.result)
      XCTAssertEqual(try pixels.rgbaData(depth: .f32, colorEncoding: .linearRGB),
        try expectedPixels.rgbaData(depth: .f32, colorEncoding: .linearRGB), sample.result)
      let saved = try NativeArchive.decode(NativeArchive.encode(result))
      XCTAssertEqual(saved, result, sample.result)
    }
  }

  func testPhotoshopIntegerStampPreservesWorkingGridSamples() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    for bits in [8, 16] {
      let url = try XCTUnwrap(Bundle.module.url(forResource: "photoshop-source-rgb\(bits)",
        withExtension: "psd", subdirectory: "Fixtures/layer-merge"))
      var source = try PSDCodec.read(Data(contentsOf: url))
      source.activeLayerID = source.layers.last?.id
      for (selection, operation) in [("visible", LayerMergeOperation.stampVisible), ("selected", .stampSelected)] {
        let expected = try fixture("\(architecture)-owned-\(bits)-stamp-\(selection)")
        let result = try LayerMergePreparation.prepare(source, layerIDs: Set(source.layers.map(\.id)), operation: operation).result
        let layer = try XCTUnwrap(result.layers.last)
        let reference = try XCTUnwrap(expected.layers.last)
        XCTAssertEqual(layer.name, reference.name)
        XCTAssertEqual(layer.x, reference.x)
        XCTAssertEqual(layer.y, reference.y)
        guard case .raster(let pixels) = layer.content, case .raster(let expectedPixels) = reference.content else {
          return XCTFail("Stamp must contain a pixel layer")
        }
        XCTAssertEqual(pixels.width, expectedPixels.width)
        XCTAssertEqual(pixels.height, expectedPixels.height)
        XCTAssertEqual(try pixels.rgbaData(depth: source.depth), try expectedPixels.rgbaData(depth: source.depth), "\(bits)-bit \(selection)")
      }
    }
  }

  func testRejectedAndStaleStampPreservesDocument() throws {
    var source = try fixture("root-stack")
    source.activeLayerID = source.layers[1].id
    XCTAssertThrowsError(try LayerMergePreparation.prepare(source, layerIDs: [source.layers[1].id], operation: .stampSelected))
    source.layers[2].clipped = true
    XCTAssertThrowsError(try LayerMergePreparation.prepare(source, layerIDs: [source.layers[0].id, source.layers[2].id], operation: .stampSelected))
    let prepared = try LayerMergePreparation.prepare(source, layerIDs: [], operation: .stampVisible)
    var stale = source
    stale.layers[0].name = "Changed while preparing"
    XCTAssertThrowsError(try prepared.applied(to: stale))
    source.layers[1].visible = false
    XCTAssertThrowsError(try LayerMergePreparation.prepare(source, layerIDs: [], operation: .stampVisible))
  }
}
