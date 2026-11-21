import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LayerStyleWorkflowTests: XCTestCase {
  @MainActor func testRotatedMaximumPatternViewportMatchesNativeAndHTTP() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let size = Surface.maxDimension
      var artwork = try CraftDocument(width: size, height: size)
      artwork.layers[0].content = .raster(try Surface(width: size, height: size, fill: .white))
      var tile = try Surface(width: 4, height: 4, fill: .white)
      tile.setPixel(x: 0, y: 0, .black)
      tile.setPixel(x: 2, y: 2, Pixel(0.1, 0.6, 0.3))
      artwork.patterns = [try RasterPattern(name: "Owned rotated pattern", surface: tile)]
      shared.store.session = EditorSession(document: artwork)
      shared.store.updateViewport(size: CGSize(width: 232, height: 140), backingScale: 1)
      shared.store.setZoom(1, center: true)
      shared.store.beginLayerStyle(.patternOverlay)
      let sheet = LayerStyleSheet(store: shared.store)
      sheet.overlayPatternValue(\.scale, 100).wrappedValue = 56
      sheet.overlayPatternValue(\.angle, 0).wrappedValue = 31
      shared.store.updateLayerEffect(0) { $0.opacity = 0.5 }
      await shared.store.renderTask?.value
      XCTAssertNil(shared.store.error)
      XCTAssertNotNil(shared.store.rasterViewportPreview)
      XCTAssertNil(shared.store.patternCanvasPreview)
      XCTAssertNil(shared.store.renderSnapshot)
      XCTAssertEqual(shared.store.document, artwork)
      shared.store.commitLayerStyle()
      await shared.store.renderTask?.value
      shared.store.setZoom(0.6667)
      shared.store.pan = CGSize(width: 20, height: -13)
      await shared.store.renderTask?.value
      XCTAssertNil(shared.store.error)

      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let root = "/v1/documents/\(id)"
      let view = shared.store.viewport.largeCanvasRequest
      let rect = view.region
      let header = """
      {"x":\(rect.x),"y":\(rect.y),"width":\(rect.width),"height":\(rect.height),"outputWidth":\(view.width),"outputHeight":\(view.height)}
      """
      @MainActor func check(_ suffix: String) async throws {
        let display = try XCTUnwrap(shared.store.image)
        let result = try await helper.request(service, path: root + "/" + suffix, headers: [
          "X-Photato-Viewport": header, "X-Photato-Revision": service.revision(shared.store),
        ])
        XCTAssertEqual(result.0.statusCode, 200)
        XCTAssertEqual(result.1, try AutomationService.png(display))
      }
      XCTAssertEqual(shared.store.rasterViewportPreview?.region, rect)
      try await check("preview.png")
      try shared.store.selectEditingChannel(.green)
      await shared.store.renderTask?.value
      try await check("channel-preview.png")
      try shared.store.selectEditingChannel(.composite)
      shared.store.proofSettings.enabled = true
      shared.store.render()
      await shared.store.renderTask?.value
      XCTAssertNil(shared.store.proofDisplayError)
      try await check("proof-preview.png")

      let stale = try await helper.request(service, path: root + "/preview.png", headers: [
        "X-Photato-Viewport": header, "X-Photato-Revision": "stale",
      ])
      XCTAssertEqual(stale.0.statusCode, 409)
      for (bad, status) in [
        (#"{"x":true,"y":0,"width":3,"height":3}"#, 400),
        (#"{"x":0,"y":0,"width":3,"height":3,"outputWidth":2}"#, 400),
        (#"{"x":299999,"y":0,"width":3,"height":3}"#, 400),
        (#"{"x":0,"y":0,"width":8000,"height":8000,"outputWidth":40,"outputHeight":40}"#, 413),
        (#"{"x":0,"y":0,"width":3000,"height":2000}"#, 413),
      ] {
        let rejected = try await helper.request(service, path: root + "/preview.png", headers: ["X-Photato-Viewport": bad])
        XCTAssertEqual(rejected.0.statusCode, status)
      }
      XCTAssertEqual(shared.store.session.undoStack.count, 1)
      XCTAssertNil(shared.store.renderSnapshot)
    }
  }

  @MainActor func testOpaqueMaximumPatternPreviewFitsZoomsAndServesPNG() async throws {
    try await checkMaximumPatternPreviewFitsZoomsAndServesPNG(angle: 0)
  }

  @MainActor func testQuarterTurnMaximumPatternPreviewFitsZoomsAndServesPNG() async throws {
    try await checkMaximumPatternPreviewFitsZoomsAndServesPNG(angle: 90)
  }

  @MainActor private func checkMaximumPatternPreviewFitsZoomsAndServesPNG(angle: Double) async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let size = Surface.maxDimension
      var artwork = try CraftDocument(width: size, height: size)
      artwork.layers[0].content = .raster(try Surface(width: size, height: size, fill: .white))
      var tile = try Surface(width: 4, height: 4, fill: .white)
      tile.setPixel(x: 0, y: 0, .black)
      artwork.patterns = [try RasterPattern(name: "Owned repeat", surface: tile)]
      shared.store.session = EditorSession(document: artwork)
      shared.store.updateViewport(size: CGSize(width: 200, height: 160), backingScale: 1)
      shared.store.beginLayerStyle(.patternOverlay)
      let sheet = LayerStyleSheet(store: shared.store)
      sheet.overlayPatternValue(\.scale, 100).wrappedValue = 200
      sheet.overlayPatternValue(\.angle, 0).wrappedValue = angle
      shared.store.updateLayerEffect(0) { $0.opacity = 0.5 }
      await shared.store.renderTask?.value
      XCTAssertNil(shared.store.error)
      XCTAssertEqual(shared.store.canvasRasterPreview?.documentRegion,
        IntRect(x: 0, y: 0, width: size, height: size))
      XCTAssertNotNil(shared.store.patternCanvasPreview)
      XCTAssertNil(shared.store.renderSnapshot)
      XCTAssertEqual(shared.store.document, artwork)
      shared.store.commitLayerStyle()
      await shared.store.renderTask?.value
      XCTAssertNil(shared.store.error)
      XCTAssertEqual(shared.store.session.undoStack.count, 1)

      shared.store.setZoom(1, center: true)
      shared.store.pan.width += 13
      await shared.store.renderTask?.value
      let visible = try XCTUnwrap(shared.store.canvasRasterPreview?.documentRegion)
      XCTAssertEqual(visible.width, 200)
      XCTAssertEqual(visible.height, 160)
      let request = try RasterPreviewRequest(region: visible, width: 200, height: 160)
      let proof = try XCTUnwrap(shared.store.patternCanvasPreview)
      let reference = try Renderer.composite(shared.store.document, region: visible)
      XCTAssertEqual(try proof.imageSamples(request).rgbaData(depth: .u8),
        try reference.cropped(to: visible).rgbaData(depth: .u8))
      let point = StrokePoint(x: Double(size / 2) + 0.5, y: Double(size / 2) + 0.5)
      let before = try proof.pixel(x: size / 2, y: size / 2)
      var brush = shared.store.brush
      brush.color = Pixel(0.12, 0.56, 0.6)
      shared.store.stroke([point], brush: brush)
      await shared.store.renderTask?.value
      XCTAssertNil(shared.store.error)
      let after = try XCTUnwrap(shared.store.patternCanvasPreview).pixel(x: size / 2, y: size / 2)
      XCTAssertNotEqual(after, before)
      await shared.store.undo()
      await shared.store.renderTask?.value
      XCTAssertEqual(try shared.store.patternCanvasPreview?.pixel(x: size / 2, y: size / 2), before)

      shared.store.fit()
      await shared.store.renderTask?.value
      XCTAssertEqual(shared.store.canvasRasterPreview?.documentRegion,
        IntRect(x: 0, y: 0, width: size, height: size))
      XCTAssertNotNil(shared.store.patternCanvasPreview)
      XCTAssertNil(shared.store.renderSnapshot)

      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let reply = try await helper.request(service, path: "/v1/documents/\(id)/preview.png", timeout: 90)
      XCTAssertEqual(reply.0.statusCode, 200)
      let opened = try RasterIO.read(reply.1)
      XCTAssertEqual(opened.width, 2048)
      XCTAssertEqual(opened.height, 2048)
      XCTAssertEqual(shared.store.session.undoStack.count, 1)
    }
  }

  @MainActor func testMaximumPatternOverlayNativePreviewAndAPIEdits() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let size = Surface.maxDimension
      var artwork = try CraftDocument(width: size, height: size)
      let region = IntRect(x: size - 104, y: size - 104, width: 30, height: 30)
      artwork.layers[0].x = region.x + 4
      artwork.layers[0].y = region.y + 4
      artwork.layers[0].content = .raster(try Surface(width: 24, height: 24, fill: .white))
      var tile = try Surface(width: 4, height: 4, fill: .white)
      tile.setPixel(x: 0, y: 0, .black)
      artwork.patterns = [try RasterPattern(name: "Owned overlay pattern", surface: tile)]
      shared.store.session = EditorSession(document: artwork)
      shared.store.updateViewport(size: .init(width: region.width, height: region.height), backingScale: 1)
      shared.store.setZoom(1, center: true)
      shared.store.pan = .init(width: size / 2 - region.x - region.width / 2,
        height: size / 2 - region.y - region.height / 2)
      XCTAssertTrue(shared.store.validateLayerStyleMenu("Layer > Layer Style > Pattern Overlay…"))
      XCTAssertFalse(shared.store.validateLayerStyleMenu("Layer > Layer Style > Drop Shadow…"))
      try service.share(shared)

      shared.store.beginLayerStyle(.patternOverlay)
      let sheet = LayerStyleSheet(store: shared.store)
      sheet.overlayPatternValue(\.scale, 100).wrappedValue = 200
      shared.store.expandLayerEffect(0)
      XCTAssertNil(shared.store.layerStyleDraft?.style.effects.first?.advanced)
      await shared.store.renderTask?.value
      XCTAssertNil(shared.store.error)
      XCTAssertEqual(shared.store.canvasRasterPreview?.documentRegion, region)
      XCTAssertEqual(shared.store.image?.width, region.width)
      XCTAssertNil(shared.store.rasterViewportPreview)
      XCTAssertNotNil(shared.store.renderSnapshot)
      let draft = try XCTUnwrap(shared.store.layerStyleDraft)
      XCTAssertEqual(shared.store.document, artwork)
      shared.store.commitLayerStyle()
      await shared.store.renderTask?.value
      XCTAssertNil(shared.store.error)
      let native = shared.store.document
      let layerID = artwork.layers[0].id.uuidString
      XCTAssertEqual(native.layers[0].style, draft.style)
      XCTAssertEqual(shared.store.session.undoStack.count, 1)
      let expected = try Renderer.composite(native, region: region).cropped(to: region).rgbaData(depth: .u8)

      let undo = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(shared.store.document, artwork)
      let edit = try await helper.edit(service, shared, "layer.style", ["layerIDs": [layerID], "style": draft.style.apiObject])
      XCTAssertEqual(edit, 200)
      XCTAssertEqual(shared.store.document, native)
      let patched = try await helper.edit(service, shared, "layer.style.patch",
        ["layerIDs": [layerID], "effectIndex": 0, "effect": ["opacity": 0.5]])
      XCTAssertEqual(patched, 200)
      XCTAssertEqual(shared.store.document.layers[0].style?.effects.first?.opacity, 0.5)
      let stable = shared.store.document
      let unsupported = try await helper.edit(service, shared, "layer.style",
        ["layerIDs": [layerID], "style": ["effects": [["kind": "dropShadow"]]]])
      XCTAssertEqual(unsupported, 422)
      XCTAssertEqual(shared.store.document, stable)
      let old = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(old, 200)

      let capabilitiesReply = try await helper.request(service, path: "/v1/capabilities")
      let capabilities = try XCTUnwrap(JSONSerialization.jsonObject(with: capabilitiesReply.1) as? [String: Any])
      let styles = try XCTUnwrap(capabilities["layerStyles"] as? [String: Any])
      let regional = try XCTUnwrap(styles["regionalPatternOverlay"] as? [String: Any])
      XCTAssertEqual(regional["maximumCanvasDimension"] as? Int, size)

      // PSB keeps an RLE placeholder even when the merged image is omitted.
      // A max-size placeholder exceeds the existing bounded HTTP response.
      let transferSize = 4096
      let transferRegion = IntRect(x: transferSize - 104, y: transferSize - 104, width: 30, height: 30)
      var transfer = try CraftDocument(width: transferSize, height: transferSize)
      transfer.patterns = native.patterns
      transfer.layers = native.layers
      transfer.activeLayerID = native.activeLayerID
      transfer.layers[0].x = transferRegion.x + 4
      transfer.layers[0].y = transferRegion.y + 4
      shared.store.renderTask?.cancel()
      shared.store.session = EditorSession(document: transfer)
      service.setDocumentTransfersEnabled(true)
      let id = try XCTUnwrap(service.shares.first?.id)
      let download = try await helper.request(service, path: "/v1/documents/\(id)/file.psb",
        headers: ["X-Photato-Export-Options": #"{"psdMaximizeCompatibility":false}"#])
      XCTAssertEqual(download.0.statusCode, 200)
      let reopened = try PSDCodec.read(download.1)
      XCTAssertEqual(reopened.width, transferSize)
      XCTAssertEqual(reopened.layers.first?.style?.effects.first?.pattern?.placement.scale, 200)
      XCTAssertEqual(try Renderer.composite(reopened, region: transferRegion).cropped(to: transferRegion).rgbaData(depth: .u8), expected)
    }
  }

  @MainActor func testActualNumericBindingsDoNotOverlapObservedDraftAccess() throws {
    let store = EditorStore(document: try CraftDocument(width: 24, height: 24))
    defer { store.renderTask?.cancel() }
    store.beginLayerStyle(.dropShadow)
    let sheet = LayerStyleSheet(store: store)
    sheet.value(\.size, 5).wrappedValue = 18
    sheet.value(\.distance, 5).wrappedValue = 28
    XCTAssertEqual(store.layerStyleDraft?.style.effects[0].size, 18)
    XCTAssertEqual(store.layerStyleDraft?.style.effects[0].distance, 28)
    store.addLayerEffect(.gradientOverlay)
    sheet.gradientColor(false).wrappedValue = Pixel(1,0,0)
    store.removeLayerEffect()
    XCTAssertEqual(store.layerStyleDraft?.selected, 0)
    XCTAssertEqual(store.layerStyleDraft?.style.effects.count, 1)
    store.removeLayerEffect()
    XCTAssertEqual(store.layerStyleDraft?.style.effects.count, 0)
    store.cancelLayerStyle()
  }
  @MainActor func testPreviewCancelCommitCopyPasteClearAndHistory() async throws {
    let original=try CraftDocument(width:24,height:24),store=EditorStore(document:original)
    defer { store.renderTask?.cancel();EditorStore.copiedLayerStyle=nil }
    store.beginLayerStyle(.dropShadow);await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertTrue(store.hasToneDraft);XCTAssertFalse(store.canBeginLayerStyle)
    XCTAssertEqual(store.document,original);store.cancelLayerStyle();XCTAssertEqual(store.document,original)
    store.beginLayerStyle(.stroke);store.commitLayerStyle()
    XCTAssertNotNil(store.document.layers[0].style);XCTAssertEqual(store.session.undoStack.count,1)
    let changed=store.document
    store.copyLayerStyle();store.clearLayerStyle();XCTAssertNil(store.document.layers[0].style)
    store.pasteLayerStyle();XCTAssertEqual(store.document,changed)
    await store.undo();XCTAssertNil(store.document.layers[0].style)
    await store.redo();XCTAssertEqual(store.document,changed)
  }
  @MainActor func testHTTPStyleStateHistoryAndStaleBusyValidation() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      try service.share(shared)
      let before=shared.store.document,id=before.layers[0].id
      let parameters:[String:Any] = ["layerIDs":[id.uuidString],"style":["effects":[["kind":"dropShadow","size":3]]]]
      let status=try await helper.edit(service,shared,"layer.style",parameters);XCTAssertEqual(status,200)
      var expected=before;var effect=LayerEffect(.dropShadow);effect.size=3
      try Command.layerStyle([id],LayerStyle(effects:[effect])).apply(to:&expected)
      XCTAssertEqual(shared.store.document,expected)
      let stale=try await helper.edit(service,shared,"layer.style",parameters,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.beginLayerStyle()
      let busy=try await helper.edit(service,shared,"layer.style",parameters);XCTAssertEqual(busy,409)
      shared.store.cancelLayerStyle()
      let invalid=try await helper.edit(service,shared,"layer.style",["layerIDs":[id.uuidString],"style":["fillOpacity":2]])
      XCTAssertEqual(invalid,400);XCTAssertEqual(shared.store.document,expected)
      let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,before)
    }
  }
  @MainActor func testNativeDownloadRequiresVersion13AndStateExposesStyles() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try shared.store.session.execute(.layerStyle([shared.store.document.layers[0].id], LayerStyle(effects: [LayerEffect(.stroke)])))
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let stateReply = try await helper.request(service, path: "/v1/documents/\(id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateReply.1) as? [String: Any])
      XCTAssertNotNil((state["layers"] as? [[String: Any]])?.first?["style"] as? [String: Any])
      service.setDocumentTransfersEnabled(true)
      let old = try await helper.request(service, path: "/v1/documents/\(id)/file.photato")
      XCTAssertEqual(old.0.statusCode, 422)
      let current = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "13"])
      XCTAssertEqual(current.0.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decode(current.1), shared.store.document)
    }
  }
  @MainActor func testNativeGradientOverlaySavesAndDownloadsAsEditablePSDAndPSB() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var artwork = shared.store.document
      var pixels = try Surface(width: artwork.width, height: artwork.height)
      for y in 0..<artwork.height { pixels.setPixel(x: 1, y: y, .black) }
      artwork.layers[0].content = .raster(pixels)
      shared.store.session = EditorSession(document: artwork)
      shared.store.beginLayerStyle(.gradientOverlay)
      LayerStyleSheet(store: shared.store).gradientColor(false).wrappedValue = Pixel(1, 0, 0)
      shared.store.commitLayerStyle()
      let document = shared.store.document
      let layer = try XCTUnwrap(document.layers.first { $0.id == document.activeLayerID })
      let effect = try XCTUnwrap(layer.style?.effects.first)
      XCTAssertEqual(effect.kind, .gradientOverlay)
      var expected = try XCTUnwrap(effect.gradient)
      // The Photoshop format encodes implicit full opacity as two explicit stops.
      XCTAssertTrue(expected.gradient.opacity.isEmpty)
      expected.gradient.opacity = [.init(0, 1), .init(1, 1)]
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      for (suffix, format) in [("psd", DocumentIO.Format.psd), ("psb", .psb)] {
        XCTAssertNil(DocumentIO.persistenceIssue(document, format: format))
        let saved = try DocumentIO.encode(document, format: format)
        let download = try await helper.request(service, path: "/v1/documents/\(id)/file.\(suffix)")
        XCTAssertEqual(download.0.statusCode, 200)
        XCTAssertEqual(download.1, saved)
        let reopened = try PSDCodec.read(saved)
        let savedLayer = try XCTUnwrap(reopened.layers.first { $0.name == layer.name })
        XCTAssertEqual(savedLayer.style?.effects.first?.gradient, expected)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8),
          try Renderer.composite(document).rgbaData(depth: .u8))
      }
      XCTAssertEqual(shared.store.document, document)
      XCTAssertEqual(shared.store.session.undoStack.count, 1)
    }
  }
  @MainActor func testNativePatternOverlayPercentAndAPIPSDDownloads() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var artwork = shared.store.document
      var tile = try Surface(width: 4, height: 4, fill: .white)
      tile.setPixel(x: 0, y: 0, .black)
      artwork.patterns = [try RasterPattern(name: "Owned style pattern", surface: tile)]
      shared.store.session = EditorSession(document: artwork)
      shared.store.beginLayerStyle(.patternOverlay)
      let sheet = LayerStyleSheet(store: shared.store)
      XCTAssertEqual(sheet.overlayPatternValue(\.scale, 100).wrappedValue, 100)
      sheet.overlayPatternValue(\.scale, 100).wrappedValue = 200
      sheet.overlayPatternValue(\.angle, 0).wrappedValue = 30
      shared.store.setPatternOverlayLinked(0, linked: false)
      shared.store.commitLayerStyle()
      let document = shared.store.document
      let effect = try XCTUnwrap(document.layers.first?.style?.effects.first)
      XCTAssertEqual(effect.kind, .patternOverlay)
      XCTAssertEqual(effect.pattern?.placement.scale, 200)
      XCTAssertEqual(effect.pattern?.placement.angle, 30)
      XCTAssertEqual(effect.pattern?.linked, false)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      for (suffix, format) in [("psd", DocumentIO.Format.psd), ("psb", .psb)] {
        let saved = try DocumentIO.encode(document, format: format)
        let download = try await helper.request(service, path: "/v1/documents/\(id)/file.\(suffix)")
        XCTAssertEqual(download.0.statusCode, 200)
        XCTAssertEqual(download.1, saved)
        let reopened = try PSDCodec.read(saved)
        XCTAssertEqual(reopened.layers.first?.style?.effects.first, effect)
        XCTAssertEqual(try Renderer.composite(reopened), try Renderer.composite(document))
      }
      XCTAssertEqual(shared.store.session.undoStack.count, 1)
    }
  }

  func testAdobeDropShadowEditsUseNativeModelAndStrictContract() throws {
    let original=try CraftDocument(width:24,height:24);var session=EditorSession(document:original)
    let raw:[String:Any] = ["name":original.layers[0].name,"operation":["type":"edit"],"layerEffects":["dropShadow":[["distance":9,"opacity":80,"useGlobalLight":false,"angle":-45,"color":["rgb":["red":255,"green":0,"blue":0]]]]]]
    try AdobeProtectionEdit(raw,path:"layers[0]").apply(to:&session)
    let effect=try XCTUnwrap(session.document.layers[0].style?.effects.first)
    XCTAssertEqual(effect.kind,.dropShadow);XCTAssertEqual(effect.distance,9);XCTAssertEqual(effect.color,Pixel(1,0,0));XCTAssertEqual(effect.opacity,0.8)
    let result=try PSDCodec.read(PSDCodec.writeRasterLayers(session.document))
    XCTAssertEqual(result.layers[0].style?.effects.first?.distance,9)
    for fields:[String:Any] in [["noise":1],["antiAliased":true],["layerKnocksOut":false],["angle":181],["distance":true],["bogus":0]] {
      XCTAssertThrowsError(try AdobeLayerEffects.parse(["dropShadow":[fields]]))
    }
    XCTAssertThrowsError(try AdobeLayerEffects.parse(["dropShadow":[]]))
    XCTAssertEqual(try AdobeLayerEffects.parse(["dropShadow":[["distance":30000]]])?.first?.distance,30000)
  }
  @MainActor func testFactoryMenuStyleBindings() throws {
    try PhotoshopMenuTests().withMenus { _,menu in
      func find(_ menu:NSMenu,_ path:String)->NSMenuItem? {
        for item in menu.items { if item.identifier?.rawValue==path {return item};if let submenu=item.submenu,let result=find(submenu,path){return result} };return nil
      }
      for path in AppDelegate.layerStyleMenuPaths { XCTAssertEqual(try XCTUnwrap(find(menu,path)).action,#selector(AppDelegate.layerStyleMenu(_:))) }
    }
  }
}
