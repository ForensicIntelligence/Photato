import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class LayerMergeRenderTests: XCTestCase {
  func file(_ name: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: (name as NSString).lastPathComponent, withExtension: "psd",
          subdirectory: ["Fixtures/layer-merge", (name as NSString).deletingLastPathComponent]
            .filter { !$0.isEmpty }.joined(separator: "/"))))
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
        case .down, .clippingMask, .stampDown, .stampGroup: ids = [try XCTUnwrap(document.activeLayerID)]
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

  func testPreparedHDRNormalPixelMasksMatchSavedLayersOnBothArchitectures() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    func document(_ name: String) throws -> CraftDocument {
      let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "psd",
        subdirectory: "Fixtures/layer-merge/hdr-mask"))
      return try PSDCodec.read(Data(contentsOf: url))
    }
    for scene in ["boundary", "translucent"] {
      for mask in ["binary-top", "binary-base", "feather-top", "feather-both"] {
        let name = "\(scene)-\(mask)"
        var source = try document(name)
        source.activeLayerID = source.layers.last?.id
        XCTAssertTrue(source.layers.contains { $0.mask != nil })
        let expected = try document("\(architecture)-\(name)-visible")
        let result = try LayerMergePreparation.prepare(source, layerIDs: [], operation: .visible).result
        try compare(result, expected, label: name)
        try compare(PSDCodec.read(PSDCodec.writeRasterLayers(result)), expected, label: "PSD " + name)
      }
    }
  }

  func testPreparedMergeClippingMaskMatchesSavedPixelsVisibilityAndLayerPlacement() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    for name in ["locked-base-base", "chain-32-hide-base"] {
      let source = try PSDCodec.read(file("clipping-merge/\(name)"))
      let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" })
      XCTAssertThrowsError(try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask), name)
    }
    var cases = [
      "chain-32-hide-all-clips", "chain-32-active-clip", "empty-base", "outside-base", "padding-base",
      "zero-base-opacity-base",
    ]
    for bits in [8, 16, 32] {
      cases += [
        "chain-\(bits)-base", "nested-\(bits)-base", "chain-\(bits)-base-half",
        "chain-\(bits)-lower-half", "chain-\(bits)-base-multiply",
        "chain-\(bits)-lock-hidden", "chain-\(bits)-lock-lower",
      ]
    }
    for name in cases {
      var source = try PSDCodec.read(file("clipping-merge/\(name)"))
      let expected = try PSDCodec.read(file("clipping-merge/\(architecture)-\(name)-merged"))
      let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" })
      let down = name.hasSuffix("active-clip")
      let selected = try XCTUnwrap(source.layers.first { $0.name == (down ? "Lower clip" : base.name) })
      source.activeLayerID = selected.id
      let operation: LayerMergeOperation = down ? .down : .clippingMask
      let plan = try LayerMergePlan(operation, layerIDs: [selected.id], in: source)
      let result = try LayerMergePreparation.prepare(source, layerIDs: [selected.id], operation: operation).result
      XCTAssertEqual(result.activeLayerID, base.id, name)
      XCTAssertEqual(result.layers.map(\.name), expected.layers.map(\.name), name)
      XCTAssertEqual(result.layers.filter { $0.id != base.id }, source.layers.filter { !plan.removedIDs.contains($0.id) }, name)
      let expectedBase = try XCTUnwrap(expected.layers.first { $0.name == base.name }, name)
      let destination = try XCTUnwrap(result.layers.first { $0.id == base.id }, name)
      let roundTripped = try PSDCodec.read(PSDCodec.writeRasterLayers(result))
      let reopened = try XCTUnwrap(roundTripped.layers.first { $0.name == base.name }, name)
      for layer in [destination, reopened] {
        XCTAssertEqual(layer.name, expectedBase.name, name)
        XCTAssertEqual(layer.x, expectedBase.x, name)
        XCTAssertEqual(layer.y, expectedBase.y, name)
        XCTAssertEqual(layer.blendMode, expectedBase.blendMode, name)
        XCTAssertEqual(layer.opacity, expectedBase.opacity, name)
        XCTAssertFalse(layer.isClipped, name)
        guard case .raster(let pixels) = layer.content, case .raster(let reference) = expectedBase.content else {
          return XCTFail("Expected raster samples for \(name)")
        }
        XCTAssertEqual(pixels.width, reference.width, name)
        XCTAssertEqual(pixels.height, reference.height, name)
        let encoding: SurfaceColorEncoding = source.depth == .f32 ? .linearRGB : .sRGB
        XCTAssertEqual(try pixels.rgbaData(depth: source.depth, colorEncoding: encoding),
          try reference.rgbaData(depth: source.depth, colorEncoding: encoding), name)
      }
    }
  }

  func testMergeClippingMaskPreservesSparseCanvasAndOriginalAlpha() throws {
    let size = Surface.maxDimension
    let alpha: Float = 0.5
    let raw = try Surface(width: size, height: size, depth: .f32, fill: Pixel(0.25, 0.75, 0.25, alpha))
      .interpretingSamples(as: .linearRGB)
    var base = Layer(name: "Base", content: .raster(raw))
    base.opacity = 0.5
    let patch = try Surface(width: 2, height: 3, depth: .f32, fill: Pixel(0.75, 0.25, 0.5, 1))
      .interpretingSamples(as: .linearRGB)
    var top = Layer(name: "Clip", content: .raster(patch))
    top.x = size - 2
    top.y = size - 3
    top.clipped = true
    var document = try CraftDocument(width: size, height: size, depth: .f32)
    document.layers = [base, top]
    document.activeLayerID = base.id
    let result = try LayerMergePreparation.prepare(document, layerIDs: [base.id], operation: .clippingMask).result
    XCTAssertEqual(result.layers.count, 1)
    XCTAssertEqual(result.layers[0].opacity, base.opacity)
    guard case .raster(let pixels) = result.layers[0].content else { return XCTFail("Expected raster") }
    XCTAssertEqual(pixels.width, size)
    XCTAssertEqual(pixels.height, size)
    XCTAssertLessThanOrEqual(pixels.tileCount, 1)
    XCTAssertTrue(pixels.linearPixel(x: 0, y: 0).hasSameBits(as: Pixel(0.25, 0.75, 0.25, alpha)))
    XCTAssertTrue(pixels.linearPixel(x: size - 1, y: size - 1).hasSameBits(as: Pixel(0.75, 0.25, 0.5, alpha)))
  }

  func testScreenClippingMergeAndStampMatchPhotoshopStoredSamples() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let variants: [(String, LayerMergeOperation)] = [
      ("lower-17", .clippingMask), ("upper-50", .clippingMask),
      ("both", .clippingMask), ("only", .clippingMask),
      ("stamp", .stampGroup), ("down", .down)
    ]
    for stack in ["chain", "nested", "holdout-chain"] {
      for bits in [8, 16] {
        for (variant, operation) in variants {
          let name = "\(stack)-\(bits)-screen-\(variant)"
          let referenceName = stack == "holdout-chain" ? name : "\(architecture)-\(name)"
          let original = try PSDCodec.read(file("screen-clipping/\(name)"))
          let reference = try PSDCodec.read(file("screen-clipping/\(referenceName)-merged"))
          let selectedName = operation == .down ? "Lower clip" : "Clipping base"
          let selected = try XCTUnwrap(original.layers.first { $0.name == selectedName }, name)
          let wanted = try XCTUnwrap(reference.layers.first { $0.name == "Clipping base" }, name)
          let edit = try LayerMergePreparation.prepare(original, layerIDs: [selected.id], operation: operation)
          let result = try edit.applied(to: original)
          XCTAssertEqual(result.layers.map(\.name), reference.layers.map(\.name), name)
          if operation == .stampGroup {
            XCTAssertEqual(result.layers.map(\.id), original.layers.map(\.id), name)
          }
          for doc in [result, try PSDCodec.read(PSDCodec.writeRasterLayers(result))] {
            let base = try XCTUnwrap(doc.layers.first { $0.name == "Clipping base" }, name)
            guard case .raster(let pixels) = base.content, case .raster(let expected) = wanted.content else {
              return XCTFail("Expected stored Screen output for \(name)")
            }
            XCTAssertEqual(base.x, wanted.x, name)
            XCTAssertEqual(base.y, wanted.y, name)
            XCTAssertEqual(pixels.width, expected.width, name)
            XCTAssertEqual(pixels.height, expected.height, name)
            XCTAssertEqual(try pixels.rgbaData(depth: original.depth, colorEncoding: .sRGB),
              try expected.rgbaData(depth: original.depth, colorEncoding: .sRGB), name)
          }
        }
      }
    }
  }

  func testContextualStampsMatchSavedDestinationAndKeepOtherLayers() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let ordinary = [8, 16, 32].flatMap { depth in
      ["top-stamp", "bottom-half", "top-half", "bottom-multiply"].map {
        ("ordinary-\(depth)-\($0)", LayerMergeOperation.stampDown, "Layer 1", "Source")
      }
    }
    let grouped = [8, 16, 32].map {
      ("chain-\($0)-active-base", LayerMergeOperation.stampGroup, "Clipping base", "Clipping base")
    }
    let edgeCases: [(String, LayerMergeOperation, String, String)] = [
      ("chain-32-active-clip", .stampDown, "Lower clip", "Clipping base"),
      ("chain-32-hide-all-clips", .stampGroup, "Clipping base", "Clipping base"),
      ("nested-32-active-base", .stampGroup, "Clipping base", "Clipping base"),
    ]
    for (name, operation, selectedName, destinationName) in ordinary + grouped + edgeCases {
      var original = try PSDCodec.read(file("context-stamp/\(name)"))
      let selected = try XCTUnwrap(original.layers.first { $0.name == selectedName }, name)
      let destination = try XCTUnwrap(original.layers.first { $0.name == destinationName }, name)
      original.activeLayerID = selected.id
      let reference = try PSDCodec.read(file("context-stamp/\(architecture)-\(name)-stamped"))
      let expected = try XCTUnwrap(reference.layers.first { $0.name == destinationName }, name)
      let edit = try LayerMergePreparation.prepare(original, layerIDs: [selected.id], operation: operation)
      XCTAssertEqual(edit.layerIDs, [selected.id], name)
      let result = try edit.applied(to: original)
      XCTAssertEqual(result.activeLayerID, selected.id, name)
      XCTAssertEqual(result.layers.map(\.id), original.layers.map(\.id), name)
      XCTAssertEqual(result.layers.filter { $0.id != destination.id },
        original.layers.filter { $0.id != destination.id }, name)
      let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(result))
      for output in [result, saved] {
        let layer = try XCTUnwrap(output.layers.first { $0.name == destinationName }, name)
        XCTAssertEqual(layer.x, expected.x, name)
        XCTAssertEqual(layer.y, expected.y, name)
        XCTAssertEqual(layer.opacity, expected.opacity, name)
        XCTAssertEqual(layer.blendMode, expected.blendMode, name)
        XCTAssertEqual(layer.isClipped, expected.isClipped, name)
        guard case .raster(let pixels) = layer.content, case .raster(let wanted) = expected.content else {
          return XCTFail("Raster stamp expected for \(name)")
        }
        XCTAssertEqual(pixels.width, wanted.width, name)
        XCTAssertEqual(pixels.height, wanted.height, name)
        let encoding: SurfaceColorEncoding = original.depth == .f32 ? .linearRGB : .sRGB
        XCTAssertEqual(try pixels.rgbaData(depth: original.depth, colorEncoding: encoding),
          try wanted.rgbaData(depth: original.depth, colorEncoding: encoding), name)
      }
    }
    for name in ["ordinary-32-bottom-stamp","ordinary-32-top-locked","ordinary-32-bottom-locked","ordinary-32-bottom-hidden"] {
      let original = try PSDCodec.read(file("context-stamp/\(name)"))
      let selected = try XCTUnwrap(original.layers.first { $0.name == (name.hasSuffix("bottom-stamp") ? "Source" : "Layer 1") })
      XCTAssertFalse(LayerMerge.canApply(.stampDown, layerIDs: [selected.id], in: original), name)
      XCTAssertThrowsError(try LayerMergePreparation.prepare(original, layerIDs: [selected.id], operation: .stampDown), name)
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
