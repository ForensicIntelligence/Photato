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

  func testClippingEditsMatchSavedPhotoshopWithEditablePixelMasks() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let commands: [(String, LayerMergeOperation)] = [
      ("merge-mask", .clippingMask), ("stamp-mask", .stampGroup),
      ("merge-down", .down), ("stamp-down", .stampDown),
    ]
    for depth in [8, 16, 32] {
      let variants = ["base", "clip", "both", "disabled", "offset", "density"]
      for variant in variants {
        let name = "mask-\(depth)-\(variant)"
        let original = try PSDCodec.read(file("pixel-masked-clipping/\(name)"))
        let base = try XCTUnwrap(original.layers.first { $0.name == "Clipping base" })
        let top = try XCTUnwrap(original.layers.first { $0.name == "Lower clip" })
        for (suffix, operation) in commands {
          let label = "\(name)-\(suffix)"
          let expected = try PSDCodec.read(file("pixel-masked-clipping/\(architecture)-\(label)-merged"))
          var source = original
          let selected = operation == .down || operation == .stampDown ? top.id : base.id
          source.activeLayerID = selected
          XCTAssertTrue(LayerMerge.canApply(operation, layerIDs: [selected], in: source), label)
          let result = try LayerMergePreparation.prepare(source, layerIDs: [selected], operation: operation).applied(to: source)
          XCTAssertEqual(result.activeLayerID, operation == .stampDown ? top.id : base.id, label)
          let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(result))
          for output in [result, reopened] {
            try compare(output, expected, label: label)
            let written = try XCTUnwrap(output.layers.first { $0.name == base.name }, label)
            XCTAssertEqual(written.mask, base.mask, label)
            XCTAssertEqual(written.maskProperties, base.maskProperties, label)
            if operation == .stampGroup || operation == .stampDown {
              let retained = try XCTUnwrap(output.layers.first { $0.name == top.name }, label)
              XCTAssertEqual(retained.mask, top.mask, label)
              XCTAssertEqual(retained.maskProperties, top.maskProperties, label)
            }
          }
        }
      }
    }
  }

  func testClippingAppliesPixelMaskBeforeFractionalLayerOpacity() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    for depth in [8, 16, 32] {
      let variants = ["clip", "offset", "disabled", "density"]
      let modes = ["normal29", "multiply63"] + (depth == 32 ? [] : ["screen63"])
      for variant in variants {
        for mode in modes {
          let name = "mask-\(depth)-\(variant)-\(mode)"
          let source = try PSDCodec.read(file("pixel-masked-clipping/\(name)"))
          let reference = try PSDCodec.read(file("pixel-masked-clipping/\(architecture)-\(name)-merged"))
          let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" })
          let result = try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask)
            .applied(to: source)
          try compare(result, reference, label: name)
          try compare(PSDCodec.read(PSDCodec.writeRasterLayers(result)), reference, label: "PSD " + name)
        }
      }
    }
  }

  func testFeatheredClippingMergesAndStampsMatchWidePhotoshopReferences() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let cases: [(String, LayerMergeOperation, Double)] = [
      ("wide250-merge-mask", .clippingMask, 250), ("wide250-stamp-mask", .stampGroup, 250),
      ("wide1000-merge-down", .down, 1000), ("wide1000-stamp-down", .stampDown, 1000),
      ("offset250-merge-mask", .clippingMask, 250),
    ]
    for (name, operation, radius) in cases {
      let original = try PSDCodec.read(file("feathered-clipping/\(name)"))
      let expected = try PSDCodec.read(file("feathered-clipping/\(architecture)-\(name)-merged"))
      let base = try XCTUnwrap(original.layers.first)
      let clip = try XCTUnwrap(original.layers.last)
      XCTAssertEqual(clip.maskProperties?.feather, radius, name)
      let selectClip = operation == .down || operation == .stampDown
      let selected = selectClip ? clip.id : base.id
      var source = original
      source.activeLayerID = selected
      XCTAssertTrue(LayerMerge.canApply(operation, layerIDs: [selected], in: source), name)
      let merged = try LayerMergePreparation.prepare(source, layerIDs: [selected], operation: operation).applied(to: source)
      try compare(merged, expected, label: name)
      let stamps = operation == .stampGroup || operation == .stampDown
      XCTAssertEqual(merged.layers.first?.id, base.id, name)
      XCTAssertEqual(merged.layers.first?.mask, base.mask, name)
      XCTAssertEqual(merged.activeLayerID, operation == .stampDown ? clip.id : base.id, name)
      if stamps {
        XCTAssertEqual(merged.layers.last, clip, name)
      }
    }
  }

  func testFeatheredClippingImpulseRecordsRemainingIntelSampleDifferences() throws {
    #if arch(x86_64)
    let architecture = "intel"
    let differingWords = [9, 52, 136]
    let maximumULPs = [1, 2, 1]
    #else
    let architecture = "arm"
    let differingWords = [0, 0, 0]
    let maximumULPs = [0, 0, 0]
    #endif
    for (index, radius) in [3, 4, 8].enumerated() {
      let name = "impulse\(radius)-merge-mask"
      let source = try PSDCodec.read(file("feathered-clipping/\(name)"))
      let expected = try PSDCodec.read(file("feathered-clipping/\(architecture)-\(name)-merged"))
      let base = try XCTUnwrap(source.layers.first)
      let merged = try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask).result
      guard case .raster(let actual) = merged.layers.first?.content,
        case .raster(let reference) = expected.layers.first?.content
      else { return XCTFail(name) }
      XCTAssertEqual(actual.width, reference.width, name)
      XCTAssertEqual(actual.height, reference.height, name)
      var differences = 0
      var maximum = 0
      for y in 0..<reference.height {
        for x in 0..<reference.width {
          let a = actual.linearPixel(x: x, y: y), b = reference.linearPixel(x: x, y: y)
          XCTAssertEqual(a.a.bitPattern, b.a.bitPattern, name)
          XCTAssertEqual(a.r.bitPattern, a.g.bitPattern, name)
          XCTAssertEqual(a.r.bitPattern, a.b.bitPattern, name)
          let ulps = abs(Int(a.r.bitPattern) - Int(b.r.bitPattern))
          if ulps != 0 { differences += 1 }
          maximum = max(maximum, ulps)
        }
      }
      XCTAssertEqual(differences, differingWords[index], name)
      XCTAssertEqual(maximum, maximumULPs[index], name)
    }
  }

  func testFeatheredClippingKeepsDistantMaskTilesSparseOnMaximumCanvas() throws {
    let side = Surface.maxDimension
    let basePixels = try Surface(width: side, height: side, depth: .f32, fill: .black, colorEncoding: .linearRGB)
    let base = Layer(name: "Clipping base", content: .raster(basePixels))
    let white = try Surface(width: side, height: side, depth: .f32, fill: .white, colorEncoding: .linearRGB)
    var clip = Layer(name: "Clip", content: .raster(white))
    clip.clipped = true
    var mask = try Surface(width: side, height: side, depth: .f32, fill: .white)
    mask.setPixel(x: 63, y: 63, .black)
    mask.setPixel(x: side - 1, y: side - 1, .black)
    clip.mask = mask
    var properties = MaskProperties()
    properties.feather = 8
    clip.maskProperties = properties
    var source = try CraftDocument(width: side, height: side, depth: .f32)
    source.layers = [base, clip]
    source.activeLayerID = base.id
    let result = try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask).result
    guard case .raster(let pixels) = result.layers.first?.content else { return XCTFail("Expected raster") }
    let sampler = try MaskSampler(layer: clip, canvasSize: (side, side))
    XCTAssertEqual(pixels.width, side)
    XCTAssertEqual(pixels.height, side)
    XCTAssertLessThanOrEqual(pixels.tileCount, 9)
    XCTAssertEqual(pixels.linearPixel(x: side / 2, y: side / 2).r.bitPattern, Float(1).bitPattern)
    for (x, y) in [(63, 63), (64, 64), (82, 63), (side - 1, side - 1), (side - 23, side - 12)] {
      let reference = sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5)
      XCTAssertEqual(pixels.linearPixel(x: x, y: y).r.bitPattern, reference.bitPattern)
    }
    XCTAssertLessThan(pixels.linearPixel(x: 64, y: 64).r, 1)
  }

  func testFeatheredSmallClipIsBoundedAtOneThousandPixelsOnMaximumCanvas() throws {
    let side = Surface.maxDimension
    let basePixels = try Surface(width: side, height: side, depth: .f32, fill: .black, colorEncoding: .linearRGB)
    let base = Layer(name: "Clipping base", content: .raster(basePixels))
    let white = try Surface(width: 3, height: 3, depth: .f32, fill: .white, colorEncoding: .linearRGB)
    var clip = Layer(name: "Clip", content: .raster(white))
    clip.x = 150_000
    clip.y = 125_000
    clip.clipped = true
    clip.mask = try Surface(width: 1, height: 1, depth: .f32, fill: .white)
    var properties = MaskProperties()
    properties.feather = 1000
    properties.transform = .translation(1, 1)
    clip.maskProperties = properties
    var source = try CraftDocument(width: side, height: side, depth: .f32)
    source.layers = [base, clip]
    source.activeLayerID = base.id
    let result = try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask).result
    guard case .raster(let pixels) = result.layers.first?.content else { return XCTFail("Expected raster") }
    XCTAssertEqual(pixels.width, side)
    XCTAssertEqual(pixels.height, side)
    XCTAssertLessThanOrEqual(pixels.tileCount, 4)
    XCTAssertGreaterThan(pixels.linearPixel(x: clip.x + 1, y: clip.y + 1).r, 0)
    XCTAssertEqual(pixels.linearPixel(x: clip.x - 1, y: clip.y).r, 0)
    XCTAssertEqual(pixels.linearPixel(x: side - 1, y: side - 1).r, 0)
  }

  func testClippedFloatMaskDensityMatchesSavedCoverageAcrossByteRanges() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let settings = ["density17", "density40", "density73", "dbyte001", "dbyte003", "dbyte019",
      "dbyte025", "dbyte051", "dbyte077", "dbyte127", "dbyte128", "dbyte153", "dbyte191",
      "dbyte221", "dbyte254"]
    for setting in settings {
      let name = "coverage-32-\(setting)-merge-mask"
      let source = try PSDCodec.read(file("pixel-masked-clipping/\(name)"))
      let reference = try PSDCodec.read(file("pixel-masked-clipping/\(architecture)-\(name)-merged"))
      let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" })
      let result = try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask)
        .applied(to: source)
      try compare(result, reference, label: setting)
      try compare(PSDCodec.read(PSDCodec.writeRasterLayers(result)), reference, label: "PSD " + setting)
    }
  }

  func testClippedPixelMaskOnlyAllocatesItsSparseCoverageOnMaximumCanvas() throws {
    let side = Surface.maxDimension
    var source = try CraftDocument(width: side, height: side, depth: .u16)
    let basePixels = try Surface(width: side, height: side, depth: .u16, fill: Pixel(0.25, 0.5, 0.75, 0.5))
    let base = Layer(name: "Clipping base", content: .raster(basePixels))
    let upper = try Surface(width: side, height: side, depth: .u16, fill: .white)
    var clip = Layer(name: "Clip", content: .raster(upper))
    clip.clipped = true
    clip.mask = try Surface(width: 1, height: 1, depth: .u16, fill: .white)
    var properties = MaskProperties()
    properties.transform = .translation(Double(side - 1), Double(side - 1))
    clip.maskProperties = properties
    source.layers = [base, clip]
    source.activeLayerID = base.id
    let result = try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask).result
    guard let layer = result.layers.first, case .raster(let pixels) = layer.content else { return XCTFail("Expected raster result") }
    let before = basePixels.pixel(x: 0, y: 0)
    XCTAssertEqual(pixels.width, side)
    XCTAssertEqual(pixels.height, side)
    XCTAssertLessThanOrEqual(pixels.tileCount, 1)
    XCTAssertEqual(pixels.pixel(x: 0, y: 0), before)
    XCTAssertEqual(pixels.pixel(x: side - 1, y: side - 1), Pixel(1, 1, 1, before.a))
  }

  func testClippedArithmeticModesMatchSavedStoredLayers() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    for depth in [8, 16] {
      for mode in ["linearAdd", "subtract", "divide"] {
        for coverage in ["opaque", "partial"] {
          for opacity in [100, 37] {
            let name = "clipped-arithmetic-\(depth)-\(coverage)-\(mode)-\(opacity)-merge-mask"
            let source = try PSDCodec.read(file("clipped-arithmetic/\(name)"))
            let expected = try PSDCodec.read(file("clipped-arithmetic/\(architecture)-\(name)-merged"))
            let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" })
            XCTAssertTrue(LayerMerge.canApply(.clippingMask, layerIDs: [base.id], in: source), name)
            let edit = try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask)
            let result = try edit.applied(to: source)
            XCTAssertEqual(result.activeLayerID, base.id, name)
            try compare(result, expected, label: name)
            try compare(PSDCodec.read(PSDCodec.writeRasterLayers(result)), expected, label: "PSD " + name)
          }
        }
      }
    }
  }

  func testHDRClippedArithmeticMatchesSavedLayersAcrossCoverageAndWidths() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let modes = ["linearAdd", "subtract", "divide"]
    let shapes = ["opaque", "partial", "solidBase", "solidClip", "baseMask", "clipMask", "dimBase", "threshold"]
    var cases: [(String, LayerMergeOperation)] = shapes.flatMap { shape in
      modes.flatMap { mode in
        [100, 37].map { ("\(shape)-\(mode)-\($0)-merge-mask", .clippingMask) }
      }
    }
    for (suffix, operation) in [("merge-mask", LayerMergeOperation.clippingMask),
                                ("stamp-mask", .stampGroup), ("merge-down", .down), ("stamp-down", .stampDown)] {
      cases += modes.map { ("masked-\($0)-79-\(suffix)", operation) }
    }
    for width in [7, 13, 21, 35, 69, 261] {
      cases += [("full\(width)-divide-37-merge-mask", .clippingMask),
                ("shift\(width)-divide-37-merge-mask", .clippingMask)]
    }
    XCTAssertEqual(cases.count, 72)
    for (suffix, operation) in cases {
      let name = "clipped-arithmetic-32-" + suffix
      var source = try PSDCodec.read(file("clipped-arithmetic/\(name)"))
      let expected = try PSDCodec.read(file("clipped-arithmetic/\(architecture)-\(name)-merged"))
      let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" })
      let clip = try XCTUnwrap(source.layers.first { $0.name == "Lower clip" })
      let selectsClip = operation == .down || operation == .stampDown
      let target = selectsClip ? clip.id : base.id
      source.activeLayerID = target
      XCTAssertTrue(LayerMerge.canApply(operation, layerIDs: [target], in: source), name)
      let result = try LayerMergePreparation.prepare(source, layerIDs: [target], operation: operation).applied(to: source)
      XCTAssertEqual(result.activeLayerID, operation == .stampDown ? clip.id : base.id, name)
      for actual in [result, try PSDCodec.read(PSDCodec.writeRasterLayers(result))] {
        try compare(actual, expected, label: name)
        let retained = try XCTUnwrap(actual.layers.first { $0.name == base.name })
        XCTAssertEqual(retained.opacity, base.opacity, name)
        XCTAssertEqual(retained.mask, base.mask, name)
        if operation == .stampDown || operation == .stampGroup {
          let contributor = try XCTUnwrap(actual.layers.first { $0.name == clip.name })
          XCTAssertEqual(contributor.mask, clip.mask, name)
          XCTAssertEqual(contributor.blendMode, clip.blendMode, name)
        }
      }
    }
  }

  func testHDRClippedDivideAllocatesOnlyTheDifferentImplicitScanlineRemainder() throws {
    let width = Surface.tileSide + 2
    let basePixels = try Surface(width: width, height: 1, depth: .f32,
      fill: Pixel(0.875, 0.875, 0.875, 1)).interpretingSamples(as: .linearRGB)
    let clipPixels = try Surface(width: width, height: 1, depth: .f32,
      fill: Pixel(0.5, 0.5, 0.5, 1)).interpretingSamples(as: .linearRGB)
    let base = Layer(name: "Clipping base", content: .raster(basePixels))
    var clip = Layer(name: "Lower clip", content: .raster(clipPixels))
    clip.clipped = true
    clip.blendMode = .divide
    clip.opacity = 94 / 255
    var document = try CraftDocument(width: width, height: 1, depth: .f32)
    document.layers = [base, clip]
    document.activeLayerID = base.id
    let result = try LayerMergePreparation.prepare(document, layerIDs: [base.id], operation: .clippingMask).result
    guard case .raster(let output) = result.layers.first?.content else { return XCTFail("Expected a raster") }
    #if arch(arm64)
    XCTAssertEqual(output.linearPixel(x: 0, y: 0).r.bitPattern, 0x3f994949)
    XCTAssertEqual(output.tileCount, 1)
    #else
    XCTAssertEqual(output.linearPixel(x: 0, y: 0).r.bitPattern, 0x3f99494a)
    XCTAssertEqual(output.tileCount, 0)
    #endif
    XCTAssertEqual(output.linearPixel(x: width - 1, y: 0).r.bitPattern, 0x3f99494a)
  }

  func testClippedMultiplyDarkenLightenAndDifferenceMatchSavedLayersAtAllRGBDepths() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    for depth in [8, 16, 32] {
      for mode in ["multiply", "darken", "lighten", "difference"] {
        let name = "chain-\(depth)-clip-\(mode)"
        var source = try PSDCodec.read(file("clipped-blend-modes/\(name)"))
        let expected = try PSDCodec.read(file("clipped-blend-modes/\(architecture)-\(name)-merged"))
        let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" })
        source.activeLayerID = base.id
        XCTAssertTrue(LayerMerge.canApply(.clippingMask, layerIDs: [base.id], in: source), name)
        let result = try LayerMergePreparation.prepare(source, layerIDs: [base.id], operation: .clippingMask).applied(to: source)
        XCTAssertEqual(result.activeLayerID, base.id, name)
        try compare(result, expected, label: name)
        try compare(PSDCodec.read(PSDCodec.writeRasterLayers(result)), expected, label: "PSD " + name)
      }
    }
  }

  func testIndependentNormalClippingMatchesSavedPhotoshopLayersAndRetainsFlag() throws {
    for bits in [8, 16] {
      for (variant, operation) in [
        ("normal-base", LayerMergeOperation.clippingMask), ("screen-only", .clippingMask),
        ("screen-stamp", .stampGroup), ("screen-down", .down)
      ] {
        let label = "independent-\(bits)-\(variant)"
        var source = try PSDCodec.read(file("independent-clipping/\(label)"))
        let reference = try PSDCodec.read(file("independent-clipping/arm-\(label)-merged"))
        let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" }, label)
        let selectedName = operation == .down ? "Lower clip" : base.name
        let selected = try XCTUnwrap(source.layers.first { $0.name == selectedName }, label)
        source.activeLayerID = selected.id
        XCTAssertFalse(base.clipsBlendAsGroup, label)
        XCTAssertTrue(LayerMerge.canApply(operation, layerIDs: [selected.id], in: source), label)
        let result = try LayerMergePreparation.prepare(source, layerIDs: [selected.id], operation: operation).applied(to: source)
        XCTAssertEqual(result.activeLayerID, base.id, label)
        let originalByName = Dictionary(uniqueKeysWithValues: source.layers.map { ($0.name, $0) })
        for retained in result.layers where retained.id != base.id {
          XCTAssertEqual(retained, originalByName[retained.name], label)
        }
        let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(result))
        for document in [result, reopened] {
          let destination = try XCTUnwrap(document.layers.first { $0.name == base.name }, label)
          XCTAssertFalse(destination.clipsBlendAsGroup, label)
          XCTAssertEqual(destination.blendMode, .normal, label)
          try compare(document, reference, label: label)
        }
      }
    }
  }

  func testIndependentMultiplyBasePreservesItsModeAndIgnoresBackdropInStoredOutput() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    let cases: [(String, LayerMergeOperation)] = [
      ("mask", .clippingMask), ("no-backdrop", .clippingMask), ("stamp", .stampGroup),
      ("down", .down), ("stamp-down", .stampDown),
    ]
    for bits in [8, 16, 32] {
      var maskResults: [Data] = []
      for (variant, operation) in cases {
        let label = "independent-\(bits)-multiply-\(variant)"
        var source = try PSDCodec.read(file("independent-clipping/\(label)"))
        let reference = try PSDCodec.read(file("independent-clipping/\(architecture)-\(label)-merged"))
        let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" }, label)
        let selectsFirstClip = operation == .down || operation == .stampDown
        let selectedName = selectsFirstClip ? "Lower clip" : base.name
        let selected = try XCTUnwrap(source.layers.first { $0.name == selectedName }, label)
        source.activeLayerID = selected.id
        XCTAssertFalse(base.clipsBlendAsGroup, label)
        XCTAssertTrue(LayerMerge.canApply(operation, layerIDs: [selected.id], in: source), label)
        let result = try LayerMergePreparation.prepare(source, layerIDs: [selected.id], operation: operation).applied(to: source)
        XCTAssertEqual(result.activeLayerID, operation == .stampDown ? selected.id : base.id, label)
        let destination = try XCTUnwrap(result.layers.first { $0.id == base.id }, label)
        XCTAssertEqual(destination.blendMode, .multiply, label)
        XCTAssertEqual(destination.opacity, base.opacity, label)
        XCTAssertFalse(destination.clipsBlendAsGroup, label)
        try compare(result, reference, label: label)
        let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(result))
        XCTAssertFalse(try XCTUnwrap(reopened.layers.first { $0.name == base.name }).clipsBlendAsGroup)
        try compare(reopened, reference, label: label)
        if variant == "mask" || variant == "no-backdrop" {
          guard case .raster(let pixels) = destination.content else { return XCTFail("Expected raster \(label)") }
          maskResults.append(try pixels.rgbaData(depth: source.depth,
            colorEncoding: source.depth == .f32 ? .linearRGB : .sRGB))
        }
      }
      XCTAssertEqual(maskResults.count, 2)
      XCTAssertEqual(maskResults[0], maskResults[1])
    }
  }

  func testAdjacentClippedMergeAndStampMatchPhotoshopSamplesAndPreserveClipping() throws {
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    var cases: [(String, String, LayerMergeOperation)] = []
    for bits in [8, 16, 32] {
      for (name, operation) in [("merge", LayerMergeOperation.down), ("stamp", .stampDown)] {
        let source = "chain-\(bits)-upper-\(name)-visible"
        cases.append((source, "\(architecture)-\(source)", operation))
      }
    }
    for bits in [8, 16] {
      for (name, operation) in [
        ("merge-visible", LayerMergeOperation.down), ("stamp-visible", .stampDown),
        ("merge-source-half", .down), ("stamp-destination-half", .stampDown),
      ] {
        let source = "holdout-chain-\(bits)-upper-\(name)"
        cases.append((source, source, operation))
      }
    }
    for (input, output, operation) in cases {
      var source = try PSDCodec.read(file("adjacent-clips/\(input)"))
      let reference = try PSDCodec.read(file("adjacent-clips/\(output)-merged"))
      let selected = try XCTUnwrap(source.layers.first { $0.name == "Upper clip" }, input)
      let destination = try XCTUnwrap(source.layers.first { $0.name == "Hidden clip" }, input)
      let expected = try XCTUnwrap(reference.layers.first { $0.name == destination.name }, input)
      source.activeLayerID = selected.id
      XCTAssertTrue(LayerMerge.canApply(operation, layerIDs: [selected.id], in: source), input)
      let result = try LayerMergePreparation.prepare(source, layerIDs: [selected.id], operation: operation).applied(to: source)
      let removed: Set<UUID> = operation == .down ? [selected.id] : []
      XCTAssertEqual(result.layers.map(\.id), source.layers.map(\.id).filter { !removed.contains($0) }, input)
      XCTAssertEqual(result.layers.filter { $0.id != destination.id },
        source.layers.filter { $0.id != destination.id && !removed.contains($0.id) }, input)
      XCTAssertEqual(result.activeLayerID, operation == .down ? destination.id : selected.id, input)
      let roundTripped = try PSDCodec.read(PSDCodec.writeRasterLayers(result))
      for tree in [result, roundTripped] {
        let actual = try XCTUnwrap(tree.layers.first { $0.name == destination.name }, input)
        XCTAssertTrue(actual.isClipped, input)
        XCTAssertEqual(actual.opacity, expected.opacity, input)
        XCTAssertEqual(actual.x, expected.x, input)
        XCTAssertEqual(actual.y, expected.y, input)
        guard case .raster(let pixels) = actual.content, case .raster(let wanted) = expected.content else {
          return XCTFail("Expected an adjacent clip raster for \(input)")
        }
        XCTAssertEqual(pixels.width, wanted.width, input)
        XCTAssertEqual(pixels.height, wanted.height, input)
        let encoding: SurfaceColorEncoding = source.depth == .f32 ? .linearRGB : .sRGB
        XCTAssertEqual(try pixels.rgbaData(depth: source.depth, colorEncoding: encoding),
          try wanted.rgbaData(depth: source.depth, colorEncoding: encoding), input)
      }
    }
    for bits in [8, 16, 32] {
      let source = try PSDCodec.read(file("adjacent-clips/chain-\(bits)-upper-stamp-hidden"))
      let selected = try XCTUnwrap(source.layers.first { $0.name == "Upper clip" })
      for operation in [LayerMergeOperation.down, .stampDown] {
        XCTAssertFalse(LayerMerge.canApply(operation, layerIDs: [selected.id], in: source))
        XCTAssertThrowsError(try LayerMergePreparation.prepare(source, layerIDs: [selected.id], operation: operation))
      }
    }
  }

  func testAdjacentClippedMergeUsesSparsePatchesAcrossMaximumCanvas() throws {
    let size = Surface.maxDimension
    var source = try CraftDocument(width: size, height: size, depth: .u16)
    let base = try XCTUnwrap(source.layers.first)
    let red = Pixel(1, 0, 0, 1), blue = Pixel(0, 0, 1, 1)
    var lower = Layer(name: "Lower clip", content: .raster(try Surface(width: 1, height: 1, depth: .u16, fill: red)))
    var upper = Layer(name: "Upper clip", content: .raster(try Surface(width: 1, height: 1, depth: .u16, fill: blue)))
    lower.clipped = true
    upper.clipped = true
    upper.x = size - 1
    upper.y = size - 1
    source.layers = [base, lower, upper]
    source.activeLayerID = upper.id
    let result = try LayerMergePreparation.prepare(source, layerIDs: [upper.id], operation: .down).applied(to: source)
    let output = try XCTUnwrap(result.layers.last)
    XCTAssertEqual(output.id, lower.id)
    XCTAssertTrue(output.isClipped)
    guard case .raster(let pixels) = output.content else { return XCTFail("Expected a sparse clipped raster") }
    XCTAssertEqual(pixels.width, size)
    XCTAssertEqual(pixels.height, size)
    XCTAssertLessThanOrEqual(pixels.tileCount, 2)
    XCTAssertEqual(pixels.pixel(x: 0, y: 0), red)
    XCTAssertEqual(pixels.pixel(x: size - 1, y: size - 1), blue)
    XCTAssertEqual(pixels.pixel(x: size / 2, y: size / 2), Pixel(1, 1, 1, 0))
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
