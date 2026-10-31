import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class SmartFilterTests: XCTestCase {
  func testFiltersPreserveSourceArchivesHistoryAndRasterizationAtEveryDepth() throws {
    for depth in PixelDepth.allCases { for kind in RasterFilter.Kind.allCases {
      let original = try SmartObjectTests().converted(depth), id = original.layers[0].id
      var session = EditorSession(document: original)
      var filter=RasterFilter(kind)
      if kind == .displace { filter.distortion?.map = .init(width:1,height:1,channels:2,samples:Data([150,90])) }
      if kind == .shear { filter.distortion?.points=[.init(0,0.5),.init(1,-0.5)] }
      if kind.isClassicDetail && !ClassicDetailSettings.depths(kind).contains(depth) {XCTAssertThrowsError(try session.execute(.applyFilter(id,filter)));XCTAssertEqual(session.document,original);continue}
      if kind == .lensBlur && depth == .f32 { XCTAssertThrowsError(try session.execute(.applyFilter(id,filter)));XCTAssertEqual(session.document,original);continue }
      if kind == .perspectiveWarp { filter.perspective?.planes=[.init(source:[PathPoint(0,0),PathPoint(8,0),PathPoint(8,6),PathPoint(0,6)],destination:[PathPoint(0,0),PathPoint(9,0),PathPoint(10,6),PathPoint(1,6)])] }
      if kind == .puppetWarp { filter.puppet?.pins=[.init(source:PathPoint(3,4)),.init(source:PathPoint(7,6),destination:PathPoint(8,5))] }
      try session.execute(.applyFilter(id, filter))
      let result = session.document, layer = result.layers[0]
      XCTAssertEqual(layer.content, original.layers[0].content)
      XCTAssertEqual(layer.smartObject, original.layers[0].smartObject)
      XCTAssertEqual(layer.smartFilters?.filters.first?.filter.kind, kind)
      XCTAssertEqual(result.minimumArchiveVersion, kind == .shadowsHighlights ? 45 : kind.isClassicDetail ? 44 : kind.isOtherVideo ? 43 : kind.isRender ? 42 : kind.isStylize ? 41 : kind.isPixelate ? 40 : kind.isDistortion ? 39 : kind == .lensBlur ? 38 : (kind == .smartSharpen || kind == .reduceNoise) ? 37 : kind == .filterGallery ? 36 : kind == .adaptiveWideAngle ? 31 : kind == .lensCorrection ? 30 : kind == .blurGallery ? 29 : kind == .perspectiveWarp ? 26 : kind == .puppetWarp ? 25 : kind == .cameraRaw ? 21 : kind == .liquify ? 19 : 15)
      for data in [try NativeArchive.encode(result), try NativeArchive.encodeChunked(result)] {
        XCTAssertEqual(try NativeArchive.decode(data), result)
      }
      let render = try Renderer.composite(result)
      try session.undo(); XCTAssertEqual(session.document, original)
      try session.redo(); XCTAssertEqual(session.document, result)
      try session.execute(.rasterize(id, Renderer.layerSurface(layer, in: result)))
      XCTAssertNil(session.document.layers[0].smartObject); XCTAssertNil(session.document.layers[0].smartFilters)
      XCTAssertEqual(try Renderer.composite(session.document).rgbaData(depth: depth), try render.rgbaData(depth: depth))
    } }
  }
  func testEditsReorderingVisibilityBlendingMaskAndIncrementalRender() throws {
    let original = try SmartObjectTests().converted(), id = original.layers[0].id
    var d = original
    try Command.applyFilter(id, RasterFilter(.mosaic)).apply(to: &d)
    try Command.applyFilter(id, RasterFilter(.highPass)).apply(to: &d)
    let before = try Renderer.render(d)
    var stack = try XCTUnwrap(d.layers[0].smartFilters)
    stack.filters.reverse(); stack.filters[0].opacity = 0.4; stack.filters[0].blendMode = .multiply
    try Command.smartFilters(id, stack).apply(to: &d)
    XCTAssertEqual(try Renderer.render(d, reusing: before).surface, try Renderer.composite(d))
    try Command.smartFilterMask(id, .maskFill(id, 0)).apply(to: &d)
    XCTAssertEqual(try Renderer.composite(d).rgbaData(depth: .u8), try Renderer.composite(original).rgbaData(depth: .u8))
    try Command.smartFilterMask(id, .maskFill(id, 1)).apply(to: &d)
    stack = try XCTUnwrap(d.layers[0].smartFilters); stack.enabled = false
    try Command.smartFilters(id, stack).apply(to: &d)
    XCTAssertEqual(try Renderer.composite(d).rgbaData(depth: .u8), try Renderer.composite(original).rgbaData(depth: .u8))
    XCTAssertEqual(d.layers[0].content, original.layers[0].content)
  }
  func testFilterMaskBrushSelectionTransformsAndOrdinaryMaskIsolation() throws {
    var d = try SmartObjectTests().converted(); let id = d.layers[0].id
    d.layers[0].mask = try Surface(width: 6, height: 4, fill: Pixel(0.7, 0.7, 0.7))
    let ordinary = d.layers[0].mask
    try Command.selection(IntRect(x: 3, y: 4, width: 2, height: 2)).apply(to: &d)
    try Command.applyFilter(id, RasterFilter(.mosaic)).apply(to: &d)
    XCTAssertTrue(d.layers[0].smartFilters!.maskProperties.linked)
    XCTAssertEqual(d.layers[0].smartFilters!.mask!.pixel(x: 3, y: 4).r, 1)
    XCTAssertEqual(d.layers[0].smartFilters!.mask!.pixel(x: 0, y: 0).r, 0)
    try Command.selection(nil).apply(to: &d)
    var brush = Brush(); brush.size = 2; brush.color = .black; brush.hardness = 1
    try Command.smartFilterMask(id, .maskStroke(id, [.init(x: 3.5, y: 4.5)], brush)).apply(to: &d)
    XCTAssertEqual(d.layers[0].mask, ordinary)
    XCTAssertEqual(d.layers[0].smartFilters!.mask!.pixel(x: 3, y: 4).r, 0)
    let old = d.layers[0].smartFilters!.maskProperties.transform
    try Command.move(id, d.layers[0].x + 3, d.layers[0].y + 2).apply(to: &d)
    XCTAssertEqual(d.layers[0].smartFilters!.maskProperties.transform, .translation(3, 2) * old)
    var stack = d.layers[0].smartFilters!; stack.maskProperties.linked = false
    try Command.smartFilters(id, stack).apply(to: &d)
    try Command.transform(id, .scale(2, 2), .bicubic).apply(to: &d)
    XCTAssertEqual(d.layers[0].smartFilters!.maskProperties.transform, stack.maskProperties.transform)
    try Command.crop(IntRect(x: 1, y: 1, width: 10, height: 8)).apply(to: &d)
    XCTAssertEqual(d.layers[0].smartFilters!.maskProperties.transform, .translation(-1, -1) * stack.maskProperties.transform)
  }
  func testLocksMalformedStacksAndOversizeAreAtomic() throws {
    var session = EditorSession(document: try SmartObjectTests().converted()); let id = session.document.layers[0].id
    try session.execute(.applyFilter(id, RasterFilter(.boxBlur)))
    var invalid = session.document.layers[0].smartFilters!
    invalid.filters.append(invalid.filters[0]); let before = session.document
    XCTAssertThrowsError(try session.execute(.smartFilters(id, invalid)))
    XCTAssertEqual(session.document, before)
    try session.execute(.protection([id: [.image]])); let locked = session.document
    XCTAssertThrowsError(try session.execute(.applyFilter(id, RasterFilter(.average))))
    XCTAssertEqual(session.document, locked)
    try session.execute(.smartFilterMask(id, .maskFill(id, 0)))
    try session.execute(.lock(id, true)); let fullyLocked = session.document
    XCTAssertThrowsError(try session.execute(.smartFilterMask(id, .maskFill(id, 1))))
    XCTAssertEqual(session.document, fullyLocked)
    var invalidTarget = session.document
    XCTAssertThrowsError(try Command.smartFilterMask(id, .visibility(id, false)).apply(to: &invalidTarget))
    var oversized = try SmartObjectTests().converted()
    oversized.layers[0].affine = .scale(1000, 1000)
    let huge = oversized
    var hugeSession = EditorSession(document: huge)
    XCTAssertThrowsError(try hugeSession.execute(.applyFilter(huge.layers[0].id, RasterFilter(.cameraRaw))))
    XCTAssertEqual(hugeSession.document, huge)
  }
  func testSupportedPSDPSBFiltersMasksAndCacheAtEveryDepth() throws {
    for depth in PixelDepth.allCases { for format in PSDFileFormat.allCases {
      for kind in RasterFilter.Kind.allCases where kind != .shadowsHighlights && !kind.isClassicDetail && !kind.isOtherVideo && !kind.isRender && (!kind.isStylize || kind == .emboss) && !kind.isPixelate && !kind.isDistortion && kind != .average && kind != .liquify && kind != .cameraRaw && kind != .puppetWarp && kind != .perspectiveWarp && kind != .blurGallery && kind != .lensCorrection && kind != .adaptiveWideAngle && kind != .filterGallery && kind != .smartSharpen && kind != .reduceNoise && kind != .lensBlur {
        var d = try SmartObjectTests().converted(depth); let id = d.layers[0].id
        var f = RasterFilter(kind); if kind == .addNoise { f.seed = .max }
        try Command.applyFilter(id, f).apply(to: &d)
        try Command.smartFilterMask(id, .maskFill(id, 0.5)).apply(to: &d)
        // Fractional outside is a native-only property; keep a binary PSD outside.
        d.layers[0].smartFilters?.maskProperties.outside = 1
        let data = try PSDCodec.writeRasterLayers(d, format: format)
        let reopened = try PSDCodec.read(data), layer = reopened.layers[0]
        XCTAssertEqual(layer.smartFilters?.filters.first?.filter, f)
        XCTAssertNotNil(layer.smartFilters?.mask)
        XCTAssertNotNil(reopened.sourceMetadata?["psdGlobal_FEid"])
        let a = try Renderer.composite(d), b = try Renderer.composite(reopened)
        for y in 0..<d.height { for x in 0..<d.width {
          let p = a.pixel(x: x, y: y), q = b.pixel(x: x, y: y)
          XCTAssertEqual(p.r, q.r, accuracy: 0.005); XCTAssertEqual(p.a, q.a, accuracy: 0.005)
        } }
      }
    } }
  }
  func testUnsupportedPSDOptionsRejectAndMaskCacheCorruptionRejects() throws {
    var d = try SmartObjectTests().converted(); let id = d.layers[0].id
    try Command.applyFilter(id, RasterFilter(.average)).apply(to: &d)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
    d.layers[0].smartFilters?.filters[0].filter = RasterFilter(.boxBlur)
    d.layers[0].smartFilters?.maskProperties.feather = 2
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
    d.layers[0].smartFilters?.maskProperties.feather = 0
    var bytes = try PSDSmartFilters.cacheData(d)
    bytes[3] = 9; d.sourceMetadata = ["psdGlobal_FEid": bytes]
    XCTAssertThrowsError(try PSDSmartFilters.masks(in: d))
  }
  func testPublishedAdobeLayerSelectionAndSmartFilterActions() throws {
    var d = try SmartObjectTests().converted(); d.layers[0].name = "Artwork"
    let action = #"[{"_obj":"select","_target":[{"_ref":"layer","_name":"Artwork"}]},{"_obj":"gaussianBlur","radius":{"_unit":"pixelsUnit","_value":12}}]"#
    let result = try PhotoshopActionProgram(actionJSON: action).applying(to: d).session.document
    XCTAssertEqual(result.layers[0].content, d.layers[0].content)
    XCTAssertEqual(result.layers[0].smartFilters?.filters.first?.filter.radius, 12)
    var duplicate = d.layers[0]; duplicate.id = UUID(); d.layers.append(duplicate)
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON: action).applying(to: d))
  }
  func testClipboardAndOffCanvasMaskPersistence() throws {
    var d = try SmartObjectTests().converted(); let id = d.layers[0].id
    try Command.applyFilter(id, RasterFilter(.mosaic)).apply(to: &d)
    var brush = Brush(); brush.size = 4; brush.color = .black
    try Command.smartFilterMask(id, .maskStroke(id, [.init(x: -5, y: -5)], brush)).apply(to: &d)
    let maskBefore = try MaskSampler(layer: d.layers[0].filterMaskProjection())
    let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    let maskAfter = try MaskSampler(layer: reopened.layers[0].filterMaskProjection())
    XCTAssertEqual(maskBefore.coverage(x: -4.5, y: -4.5), maskAfter.coverage(x: -4.5, y: -4.5), accuracy: 0.005)
    let clip = try ClipboardRenderer.copy(d, layerIDs: [id])
    let preview = try ClipboardRenderer.preview(clip)
    XCTAssertEqual(try preview.rgbaData(depth: .u8), try Renderer.composite(d).rgbaData(depth: .u8))
    let pasted = try clip.newDocument(name: "Pasted")
    XCTAssertEqual(pasted.layers[0].smartFilters?.filters, d.layers[0].smartFilters?.filters)
    try Command.selection(IntRect(x: 0, y: 0, width: d.width, height: d.height)).apply(to: &d)
    let selected = try ClipboardRenderer.copy(d, layerIDs: [id])
    XCTAssertEqual(selected.kind, .pixels)
    var expected = d
    expected.layers[0] = try SmartFilterEngine.renderedLayer(d.layers[0], in: d)
    XCTAssertEqual(try ClipboardRenderer.preview(ClipboardRenderer.copy(expected, layerIDs: [id])), try ClipboardRenderer.preview(selected))
  }

}
