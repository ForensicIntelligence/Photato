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

  func testMaximumSparseStampPatchesPreserveTransparentRGBAtAllDepths() async throws {
    for depth in PixelDepth.allCases {
      let size = Surface.maxDimension
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var first = try Surface(width: 3, height: 2, depth: depth, colorEncoding: encoding)
      first.setPixel(x: 0, y: 0, Pixel(1, 0, 0, 1))
      first.setPixel(x: 2, y: 1, Pixel(1, 0, 0, 1))
      let second = try Surface(width: 2, height: 3, depth: depth,
        fill: Pixel(0, 0, 1, 1), colorEncoding: encoding)
      var bottom = Layer(name: "First", content: .raster(first))
      bottom.x = 2
      bottom.y = 4
      var top = Layer(name: "Second", content: .raster(second))
      top.x = size - 3
      top.y = size - 4
      var document = try CraftDocument(width: size, height: size, depth: depth)
      document.layers = [bottom, top]
      document.activeLayerID = top.id
      let source = document
      let result = try await Task.detached {
        var renderedPatches = 0
        let canvas = IntRect(x: 0, y: 0, width: size, height: size)
        let rendered = try PagedCanvasRenderer.composite(source, region: canvas, forStamp: true, onPatch: {
          renderedPatches = $0
          if $0 > 4 { withUnsafeCurrentTask { $0?.cancel() } }
        })
        return (rendered, renderedPatches)
      }.value
      XCTAssertEqual(result.1, 2)
      XCTAssertTrue(result.0.pixel(x: 3, y: 4).hasSameBits(as: .clear))
      let sample = depth == .f32 ? result.0.linearPixel(x: 6, y: 4) : result.0.pixel(x: 6, y: 4)
      XCTAssertTrue(sample.hasSameBits(as: Pixel(1, 1, 1, 0)))
      for operation in [LayerMergeOperation.stampVisible, .stampSelected] {
        let ids: Set<UUID> = operation == .stampSelected ? [bottom.id, top.id] : []
        let stamped = try LayerMergePreparation.prepare(source, layerIDs: ids, operation: operation).result
        XCTAssertEqual(Array(stamped.layers.dropLast()), source.layers)
        let stamp = try XCTUnwrap(stamped.layers.last)
        XCTAssertEqual(stamp.id, stamped.activeLayerID)
        XCTAssertEqual(stamp.x, 2)
        XCTAssertEqual(stamp.y, 4)
        guard case .raster(let pixels) = stamp.content else { return XCTFail("Expected raster stamp") }
        XCTAssertEqual(pixels.width, size - 3)
        XCTAssertEqual(pixels.height, size - 5)
        XCTAssertLessThanOrEqual(pixels.tileCount, 8)
        XCTAssertTrue(pixels.pixel(x: 1, y: 0).hasSameBits(as: .clear))
        let gap = depth == .f32 ? pixels.linearPixel(x: 4, y: 0) : pixels.pixel(x: 4, y: 0)
        XCTAssertTrue(gap.hasSameBits(as: Pixel(1, 1, 1, 0)))
        let end = depth == .f32 ? pixels.linearPixel(x: pixels.width - 1, y: pixels.height - 1)
          : pixels.pixel(x: pixels.width - 1, y: pixels.height - 1)
        XCTAssertTrue(end.hasSameBits(as: Pixel(0, 0, 1, 1)))
      }
    }
  }

  func testMaximumSparseStampKeepsItsParentAndGroupPixels() async throws {
    let size = Surface.maxDimension
    func document(side: Int) throws -> CraftDocument {
      let group = Layer(name: "Nested", content: .group(.init(passThrough: true)))
      let red = try Surface(width: 2, height: 2, depth: .f32, fill: Pixel(1, 0, 0, 0.5), colorEncoding: .linearRGB)
      let blue = try Surface(width: 2, height: 2, depth: .f32, fill: Pixel(0, 0, 1, 0.5), colorEncoding: .linearRGB)
      var base = Layer(name: "Base", content: .raster(red))
      base.x = 2
      base.y = 2
      var child = Layer(name: "Child", content: .raster(blue))
      child.x = side - 3
      child.y = side - 3
      child.parentID = group.id
      var document = try CraftDocument(width: side, height: side, depth: .f32)
      document.layers = [base, child, group]
      document.activeLayerID = child.id
      return document
    }
    let original = try document(side: size)
    let measured = try await Task.detached {
      var patches = 0
      let canvas = IntRect(x: 0, y: 0, width: size, height: size)
      let pixels = try PagedCanvasRenderer.composite(original, region: canvas, forStamp: true, onPatch: {
        patches = $0
        if $0 > 4 { withUnsafeCurrentTask { $0?.cancel() } }
      })
      return (pixels, patches)
    }.value
    XCTAssertEqual(measured.1, 2)
    let compact = try document(side: 64)
    let reference = try Renderer.compositePrepared(compact,
      region: IntRect(x: 0, y: 0, width: 64, height: 64), forStamp: true)
    for (x, y, expectedX, expectedY) in [(2, 2, 2, 2), (3, 5, 3, 5), (size - 3, size - 3, 61, 61)] {
      XCTAssertTrue(measured.0.linearPixel(x: x, y: y).hasSameBits(
        as: reference.linearPixel(x: expectedX, y: expectedY)))
    }
    let prepared = try LayerMergePreparation.prepare(original, layerIDs: [], operation: .stampVisible)
    let stamp = prepared.result.layers[2]
    XCTAssertEqual(stamp.id, prepared.result.activeLayerID)
    XCTAssertEqual(stamp.parentID, original.layers[2].id)
    XCTAssertEqual(prepared.result.layers.filter { $0.id != stamp.id }, original.layers)
  }

  func testSparseStampSamplesTheImplicitFullCanvasBackdrop() async throws {
    let size = Surface.maxDimension
    let background = Pixel(0.25, 0.5, 0.75, 0.5)
    let foreground = Pixel(1, 0, 0, 0.5)
    for depth in PixelDepth.allCases {
      func document(_ side: Int) throws -> CraftDocument {
        let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
        var backdrop = try Surface(width: side, height: side, depth: depth,
          fill: background, colorEncoding: encoding)
        backdrop.setPixel(x: 2, y: 3, Pixel(0, 0, 1, 1))
        let base = Layer(name: "Base", content: .raster(backdrop))
        var cover = Layer(name: "Cover", content: .raster(try Surface(
          width: 2, height: 3, depth: depth, fill: foreground, colorEncoding: encoding)))
        cover.x = side - 3
        cover.y = side - 4
        var source = try CraftDocument(width: side, height: side, depth: depth)
        source.layers = [base, cover]
        source.activeLayerID = cover.id
        return source
      }
      let large = try document(size)
      let compact = try document(64)
      let result = try await Task.detached {
        let extent = IntRect(x: 0, y: 0, width: size, height: size)
        return try PagedCanvasRenderer.composite(large, region: extent, forStamp: true, onPatch: {
          if $0 > 4 { withUnsafeCurrentTask { $0?.cancel() } }
        })
      }.value
      let reference = try Renderer.compositePrepared(compact,
        region: IntRect(x: 0, y: 0, width: 64, height: 64), forStamp: true)
      func sample(_ pixels: Surface, _ x: Int, _ y: Int) -> Pixel {
        depth == .f32 ? pixels.linearPixel(x: x, y: y) : pixels.pixel(x: x, y: y)
      }
      XCTAssertLessThanOrEqual(result.tileCount, 2)
      for (x, y) in [(2, 3), (17, 24), (size - 2, size - 3)] {
        let compactX = x > 32 ? 64 - (size - x) : x
        let compactY = y > 32 ? 64 - (size - y) : y
        XCTAssertTrue(sample(result, x, y).hasSameBits(as: sample(reference, compactX, compactY)))
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
