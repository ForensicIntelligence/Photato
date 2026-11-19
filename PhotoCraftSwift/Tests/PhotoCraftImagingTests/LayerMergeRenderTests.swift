import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class LayerMergeRenderTests: XCTestCase {
  func file(_ name: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: name, withExtension: "psd", subdirectory: "Fixtures/layer-merge")))
  }
  func compare(_ actual: CraftDocument, _ expected: CraftDocument, label: String) throws {
    XCTAssertEqual(actual.layers.count, expected.layers.count, label)
    for (a, b) in zip(actual.layers, expected.layers) {
      XCTAssertEqual(a.name, b.name, label)
      XCTAssertEqual(a.x, b.x, label)
      XCTAssertEqual(a.y, b.y, label)
      XCTAssertEqual(a.visible, b.visible, label)
      XCTAssertEqual(a.opacity, b.opacity, label)
      guard case .raster(let p) = a.content, case .raster(let q) = b.content else {
        return XCTFail(label)
      }
      XCTAssertEqual(p.width, q.width, label)
      XCTAssertEqual(p.height, q.height, label)
      // PSD samples retain their embedded working profile. The separate WorkingProfileTests
      // compares against independently extracted original-profile raw bytes without decoding
      // the expected pixels through PSDCodec.
      let encoding: SurfaceColorEncoding = actual.depth == .f32 ? .linearRGB : .sRGB
      XCTAssertEqual(
        try p.rgbaData(depth: actual.depth, colorEncoding: encoding),
        try q.rgbaData(depth: expected.depth, colorEncoding: encoding),
        label + " exact working-space RGBA samples")
    }
  }
  func testPhotoshopLayerMergesAndPSDExportAtAllDepths() throws {
    for bits in [8, 16, 32] {
      for operation in [LayerMergeOperation.down, .selected, .visible] {
        var original = try PSDCodec.read(file("photoshop-source-rgb\(bits)"))
        original.activeLayerID = original.layers.last?.id
        let ids =
          operation == .down
          ? Set([try XCTUnwrap(original.activeLayerID)]) : Set(original.layers.map(\.id))
        var result = original
        try Command.mergeLayers(ids, operation).apply(to: &result)
        let key = operation == .down ? "down" : operation == .visible ? "visible" : "selected"
        let expected = try PSDCodec.read(file("photoshop-\(key)-rgb\(bits)"))
        try compare(result, expected, label: "\(key) RGB\(bits)")
        try compare(
          PSDCodec.read(PSDCodec.writeRasterLayers(result)), expected,
          label: "PSD \(key) RGB\(bits)")
      }
    }
  }

  func testPreparedHDRNormalMergeAndStampMatchSavedStraightLayerSamples() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    func fixture(_ name: String) throws -> CraftDocument {
      let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "psd",
        subdirectory: "Fixtures/layer-merge/hdr-normal"))
      return try PSDCodec.read(Data(contentsOf: url))
    }
    let modes: [(String, LayerMergeOperation)] = [
      ("down", .down), ("visible", .visible), ("stamp-visible", .stampVisible),
    ]
    let examples: [(String, [(String, LayerMergeOperation)])] = [
      ("boundary", [("visible", .visible)]),
      ("boundary-top-0", [("visible", .visible)]),
      ("boundary-top-50", [("visible", .visible)]),
      ("boundary-top-99", [("visible", .visible)]),
      ("boundary-top-75-base-25", [("visible", .visible)]),
      ("opaque", modes),
      ("translucent", modes),
      ("coverage-one", modes + [("selected", .selected), ("stamp-selected", .stampSelected)]),
    ]
    for (name, operations) in examples {
      var document = try fixture(name)
      document.activeLayerID = document.layers.last?.id
      for (suffix, operation) in operations {
        let label = "\(name)-\(suffix)"
        let ids: Set<UUID>
        switch operation {
        case .down: ids = [try XCTUnwrap(document.activeLayerID)]
        case .selected, .stampSelected: ids = Set(document.layers.map(\.id))
        case .visible, .stampVisible: ids = []
        }
        let expected = try XCTUnwrap(fixture("\(architecture)-\(label)").layers.last)
        let result = try LayerMergePreparation.prepare(document, layerIDs: ids, operation: operation).applied(to: document)
        if operation.preservesSources {
          XCTAssertEqual(result.layers.filter { $0.id != result.activeLayerID }, document.layers, label)
        } else {
          XCTAssertEqual(result.layers.count, 1, label)
        }
        let roundTripped = try PSDCodec.read(PSDCodec.writeRasterLayers(result))
        let merged = try XCTUnwrap(result.layers.first { $0.id == result.activeLayerID }, label)
        for actual in [merged, try XCTUnwrap(roundTripped.layers.last)] {
          XCTAssertEqual(actual.x, expected.x, label)
          XCTAssertEqual(actual.y, expected.y, label)
          guard case .raster(let pixels) = actual.content, case .raster(let reference) = expected.content else {
            return XCTFail("Expected a raster for \(label)")
          }
          XCTAssertEqual(pixels.width, reference.width, label)
          XCTAssertEqual(pixels.height, reference.height, label)
          XCTAssertEqual(try pixels.rgbaData(depth: .f32, colorEncoding: .linearRGB),
            try reference.rgbaData(depth: .f32, colorEncoding: .linearRGB), label)
        }
      }
    }
  }

  func testPhotoshopOffCanvasBoundsHiddenPixelsAndActiveVisiblePosition() throws {
    let original = try PSDCodec.read(file("photoshop-source-geometry-hidden-rgb8"))
    for (operation, active, key) in [
      (LayerMergeOperation.selected, 2, "selected"), (.visible, 2, "visible"),
      (.visible, 0, "visible-bottom"),
    ] {
      var result = original
      result.activeLayerID = result.layers[active].id
      try Command.mergeLayers(Set(result.layers.map(\.id)), operation).apply(to: &result)
      let expected = try PSDCodec.read(file("photoshop-\(key)-geometry-hidden-rgb8"))
      try compare(result, expected, label: key)
      try compare(PSDCodec.read(PSDCodec.writeRasterLayers(result)), expected, label: "PSD " + key)
    }
  }
}
