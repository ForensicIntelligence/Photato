import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LocalGeneratedBackgroundTests: XCTestCase {
  private func document(width: Int = 128, height: Int = 96) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: height)
    document.layers[0].content = .raster(try Surface(width: width, height: height, fill: Pixel(0.1, 0.25, 0.7)))
    var mask = try Surface(width: width, height: height, fill: .black)
    try mask.mapPixels(in: IntRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2)) { x, _, _ in
      x == width / 4 ? Pixel(0.25, 0.25, 0.25) : .white
    }
    document.layers[0].mask = mask
    return document
  }

  private func generated(_ pixel: Pixel) throws -> Surface {
    try Surface(width: LocalGenerativeFill.side, height: LocalGenerativeFill.side, depth: .f32, fill: pixel)
  }

  func testBackgroundLayerReopensAndRegeneratesAfterSubjectEdits() throws {
    let original = try document()
    let red = try generated(Pixel(0.9, 0.15, 0.2)), green = try generated(Pixel(0.12, 0.86, 0.18))
    var originalImage: [Float] = [], originalMask: [Float] = []
    let command = try LocalGeneratedBackground.prepare(original, prompt: "", seed: 721, count: 2) { prompt, seeds, image, mask in
      XCTAssertEqual(prompt, LocalGeneratedBackground.defaultPrompt)
      XCTAssertEqual(seeds, [721, 722])
      originalImage = image
      originalMask = mask
      return [red, green]
    }
    var session = EditorSession(document: original)
    try session.executePrepared(PreparedEdit(command: command, document: original))
    let result = session.document
    XCTAssertEqual(result.layers.last, original.layers.first)
    XCTAssertEqual(result.activeLayerID, result.layers.first?.id)
    let background = try XCTUnwrap(result.layers.first)
    let metadata = try XCTUnwrap(GenerativeFillVariations.read(background))
    XCTAssertTrue(metadata.isBackground)
    XCTAssertNil(background.mask)
    let rendered = try Renderer.composite(result)
    let subject = try Renderer.composite(original)
    XCTAssertTrue(rendered.pixel(x: 64, y: 48).hasSameBits(as: subject.pixel(x: 64, y: 48)))
    XCTAssertGreaterThan(rendered.pixel(x: 2, y: 2).r, 0.85)
    XCTAssertTrue(originalMask.contains(0))
    XCTAssertTrue(originalMask.contains(1))
    try session.undo()
    XCTAssertEqual(session.document, original)

    let restored = try [NativeArchive.decode(NativeArchive.encodeChunked(result)),
      PSDCodec.read(PSDCodec.writeRasterLayers(result, format: .psd)),
      PSDCodec.read(PSDCodec.writeRasterLayers(result, format: .psb))]
    for (index, loaded) in restored.enumerated() {
      var edited = loaded
      let target = edited.layers[0].id
      edited.layers[1].mask?.setPixel(x: 64, y: 48, .black)
      let editedSubject = edited.layers[1]
      var added = edited
      let edit = try GenerativeFillVariations.append(to: target, in: edited, prompt: "a forest clearing", seed: 723, count: 1) {
        prompt, seeds, image, mask in
        XCTAssertEqual(prompt, "a forest clearing")
        XCTAssertEqual(seeds, [723])
        XCTAssertTrue(image == originalImage)
        XCTAssertTrue(mask == originalMask)
        return [green]
      }
      try edit.apply(to: &added)
      XCTAssertEqual(added.layers[1], editedSubject)
      XCTAssertEqual(GenerativeFillVariations.read(added.layers[0])?.entries.last?.prompt, "a forest clearing")
      if index == 2 {
        var similar = edited
        let reference = metadata.entries[1].id
        let edit = try GenerativeFillVariations.append(to: target, in: edited, prompt: nil, seed: 724, count: 1,
          referenceVariationID: reference) { prompt, _, image, mask in
          XCTAssertEqual(prompt, LocalGeneratedBackground.defaultPrompt)
          XCTAssertFalse(image == originalImage)
          XCTAssertTrue(mask == originalMask)
          return [red]
        }
        try edit.apply(to: &similar)
        let loadedAgain = try PSDCodec.read(PSDCodec.writeRasterLayers(similar, format: .psb))
        let reloaded = try XCTUnwrap(GenerativeFillVariations.read(loadedAgain.layers[0]))
        XCTAssertEqual(Array(reloaded.entries.prefix(2)), metadata.entries)
        XCTAssertEqual(reloaded.entries.last?.referenceVariationID, reference)
      }
    }
  }

  func testBackgroundCoversWideCanvasWithEditablePlacement() throws {
    let source = try document(width: 6_200, height: 97)
    var edited = source
    let blue = try generated(Pixel(0.12, 0.3, 0.92))
    try LocalGeneratedBackground.prepare(source, prompt: "purple twilight", seed: 20, count: 1) { _, _, _, _ in [blue] }.apply(to: &edited)
    let layer = edited.layers[0]
    let object = try XCTUnwrap(layer.smartObject)
    XCTAssertEqual(object.width, LocalGenerativeFill.side)
    XCTAssertEqual(object.height, 9)
    XCTAssertNotNil(layer.affine)
    let pixels = try Renderer.composite(edited)
    XCTAssertGreaterThan(pixels.pixel(x: 6_199, y: 96).b, 0.85)
    XCTAssertEqual(pixels.pixel(x: 6_199, y: 96).a, 1)
    let loaded = try PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: .psb))
    XCTAssertEqual(loaded.layers[0].coordinateTransform.a, layer.coordinateTransform.a, accuracy: 1e-10)
    XCTAssertEqual(loaded.layers[0].coordinateTransform.d, layer.coordinateTransform.d, accuracy: 1e-10)
    XCTAssertEqual(loaded.layers[0].coordinateTransform.tx, layer.coordinateTransform.tx, accuracy: 1e-10)
    XCTAssertEqual(loaded.layers[0].coordinateTransform.ty, layer.coordinateTransform.ty, accuracy: 1e-10)
    XCTAssertEqual(try Renderer.composite(loaded).rgbaData(depth: .u8), try pixels.rgbaData(depth: .u8))
  }

  func testMissingOrCompletelyCoveredSubjectNeverReachesInference() throws {
    var source = try document()
    for mask: Surface? in [nil, try Surface(width: source.width, height: source.height, fill: .white),
      try Surface(width: source.width, height: source.height, fill: .black)] {
      source.layers[0].mask = mask
      XCTAssertThrowsError(try LocalGeneratedBackground.prepare(source, prompt: "open landscape", seed: 1, count: 1) { _, _, _, _ in
        XCTFail("An invalid subject reached inference.")
        return []
      })
    }
  }

  func testUnscaledRGB32BackgroundRoundTripsWithoutChangingOpaqueSubjectSamples() throws {
    let width = 92, height = 70
    let subject = IntRect(x: 18, y: 17, width: 46, height: 37)
    var source = try CraftDocument(width: width, height: height, depth: .f32)
    var pixels = try Surface(width: width, height: height, depth: .f32, colorEncoding: .linearRGB)
    var mask = try Surface(width: width, height: height, fill: .black)
    for y in subject.y..<(subject.y + subject.height) {
      for x in subject.x..<(subject.x + subject.width) {
        pixels.setLinearPixel(x: x, y: y, Pixel(1.48 + Float(x % 9) / 339, 0.22 + Float(y) / 473, 0.6))
        mask.setPixel(x: x, y: y, .white)
      }
    }
    source.layers[0].content = .raster(pixels)
    source.layers[0].mask = mask
    let expected = try Renderer.composite(source).cropped(to: subject).rgbaData(depth: .f32, colorEncoding: .linearRGB)
    let neutral = try generated(Pixel(0.65, 0.38, 0.18))
    var edited = source
    try LocalGeneratedBackground.prepare(source, prompt: "warm interior", seed: 18, count: 1) { _, _, _, _ in [neutral] }.apply(to: &edited)
    let native = try Renderer.composite(edited)
    let initial = try native.rgbaData(depth: .f32, colorEncoding: .linearRGB)
    XCTAssertEqual(try native.cropped(to: subject).rgbaData(depth: .f32, colorEncoding: .linearRGB), expected)
    for format in [PSDFileFormat.psd, .psb] {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: format))
      let result = try Renderer.composite(reopened)
      XCTAssertNotNil(reopened.layers.first?.affine)
      XCTAssertEqual(try result.rgbaData(depth: .f32, colorEncoding: .linearRGB), initial)
      XCTAssertEqual(try result.cropped(to: subject).rgbaData(depth: .f32, colorEncoding: .linearRGB), expected)
    }
  }

  func testMaximumWidthBackgroundSavesAndReopensWithoutClipping() throws {
    let width = Surface.maxDimension, height = 8
    var source = try CraftDocument(width: width, height: height)
    source.layers[0].content = .raster(try Surface(width: width, height: height, fill: Pixel(0.11, 0.25, 0.8)))
    var matte = try Surface(width: width, height: height, fill: .black)
    try matte.mapPixels(in: IntRect(x: 120_000, y: 0, width: 60_000, height: height)) { _, _, _ in .white }
    source.layers[0].mask = matte
    let output = try generated(Pixel(0.7, 0.43, 0.21))
    var document = source
    try LocalGeneratedBackground.prepare(source, prompt: "a warm studio", seed: 25, count: 1) { _, _, _, _ in
      [output]
    }.apply(to: &document)
    let edge = IntRect(x: width - 4, y: 0, width: 4, height: height)
    let original = try Renderer.composite(document, region: edge).cropped(to: edge)
    XCTAssertEqual(original.pixel(x: 3, y: 7).a, 1)
    let folder = FileManager.default.temporaryDirectory.appending(path: "Photato-Background-Maximum-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "Maximum Width.psb")
    try PSDCodec.writeRasterLayers(document, to: file, format: .psb)
    let reopened = try DocumentIO.read(file)
    let loaded = try Renderer.composite(reopened, region: edge).cropped(to: edge)
    XCTAssertEqual(try loaded.rgbaData(depth: .u8), try original.rgbaData(depth: .u8))
    XCTAssertTrue(GenerativeFillVariations.read(try XCTUnwrap(reopened.layers.first))?.isBackground == true)
    XCTAssertEqual(reopened.layers[1].mask, matte)
  }

  @MainActor func testRealBackgroundPropertiesAndHTTPUseSameSeed() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_PROMPT_FILL_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional local prompt model.")
    }
    let key = GenerativeFillModelPreference.promptKey
    let saved = UserDefaults.standard.data(forKey: key)
    UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: path, isDirectory: true)), forKey: key)
    defer { UserDefaults.standard.set(saved, forKey: key) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let source = try self.document()
      let subject = try XCTUnwrap(source.activeLayerID)
      let store = shared.store
      store.session = EditorSession(document: source)
      try service.share(shared)
      store.selectMask(subject)
      XCTAssertTrue(store.editingMask)
      store.beginLocalBackground()
      let draft = try XCTUnwrap(store.generativeFillDraft)
      XCTAssertEqual(draft.backgroundSubjectID, subject)
      draft.prompt = "an off-white studio with a warm light"
      draft.seed = 472125
      draft.variationCount = 1
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(store.document.layers.last, source.layers[0])
      let native = try Renderer.composite(store.document).rgbaData(depth: .u8)
      await store.undo()
      XCTAssertEqual(store.document, source)
      let status = try await helper.edit(service, shared, GenerativeFillAPI.background,
        ["foregroundLayerID": subject.uuidString, "prompt": draft.prompt, "seed": 472125, "variationCount": 1], timeout: 150)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(store.document.layers.last, source.layers[0])
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), native)
      XCTAssertEqual(store.selectedLayerIDs, Set(store.document.activeLayerID.map { [$0] } ?? []))
      await store.undo()
      XCTAssertEqual(store.document, source)
    }
  }
}

final class BackgroundReplacementTests: XCTestCase {
  private func document(depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 48, height: 32, depth: depth)
    document.layers[0].content = .raster(try Surface(width: 48, height: 32, depth: depth, fill: Pixel(0.1, 0.2, 0.8)))
    var mask = try Surface(width: 48, height: 32, fill: .black)
    try mask.mapPixels(in: .init(x: 18, y: 8, width: 12, height: 16)) { _, _, _ in .white }
    document.layers[0].mask = mask
    return document
  }

  private func artwork() throws -> Data {
    var source = try CraftDocument(width: 16, height: 24)
    var pixels = try Surface(width: 16, height: 24)
    pixels.mapPixels { x, y, _ in Pixel(Float(x) / 15, Float(y) / 23, 0.4) }
    source.layers[0].content = .raster(pixels)
    return try DocumentIO.encode(source, format: .png)
  }

  private func setBackground(_ document: CraftDocument, _ pixels: Data, _ fit: FrameFit) throws -> CraftDocument {
    var options = EmbeddedSourceOptions()
    options.background = .init(foregroundLayerID: try XCTUnwrap(document.activeLayerID), fit: fit)
    var result = document
    try EmbeddedSourceAPI.prepare(pixels, "Backdrop.png", document, options).apply(to: &result)
    return result
  }

  func testSolidColorReopensEditableAtAllRGBDepths() throws {
    for depth in [PixelDepth.u8, .u16, .f32] {
      let source = try document(depth: depth)
      let command = try BackgroundReplacement.color(Pixel(0.125, 0.5, 0.75), in: source, foregroundID: source.activeLayerID)
      var session = EditorSession(document: source)
      try session.executePrepared(PreparedEdit(command: command, document: source))
      let edited = session.document
      XCTAssertEqual(edited.layers.last, source.layers.last)
      let composite = try Renderer.composite(edited)
      let subject = try Renderer.composite(source)
      XCTAssertTrue(composite.pixel(x: 24, y: 16).hasSameBits(as: subject.pixel(x: 24, y: 16)))
      XCTAssertEqual(composite.pixel(x: 0, y: 0).a, 1)
      try session.undo()
      XCTAssertEqual(session.document, source)
      try session.redo()
      XCTAssertEqual(session.document, edited)
      for format in [DocumentIO.Format.native, .psd, .psb] {
        let reopened = try DocumentIO.decodeUpload(DocumentIO.encode(edited, format: format), native: format == .native,
          name: "Fill.\(format.rawValue)")
        guard case .fill = reopened.layers.first?.content else { return XCTFail("Background fill lost in \(format).") }
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: depth), try composite.rgbaData(depth: depth),
          "\(depth) \(format)")
      }
    }
  }

  func testArtworkPlacementModesPreserveSourceAndReopen() throws {
    let source = try document(), bytes = try artwork()
    for fit in FrameFit.allCases {
      let edited = try setBackground(source, bytes, fit)
      XCTAssertEqual(edited.layers.last, source.layers.last)
      let layer = edited.layers[0]
      XCTAssertEqual(layer.smartObject?.data, bytes)
      let transform = layer.coordinateTransform
      switch fit {
      case .fill: XCTAssertEqual(transform, .init(a: 3, d: 3, ty: -20))
      case .fit:
        XCTAssertEqual(transform.a, 4.0 / 3)
        XCTAssertEqual(transform.tx, 40.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(transform.ty, 0)
      case .original: XCTAssertEqual(transform, .translation(16, 4))
      }
      let pixels = try Renderer.composite(edited)
      XCTAssertEqual(pixels.pixel(x: 0, y: 0).a, fit == .fill ? 1 : 0)
      for format in [DocumentIO.Format.native, .psd, .psb] {
        let reopened = try DocumentIO.decodeUpload(DocumentIO.encode(edited, format: format), native: format == .native,
          name: "Artwork.\(format.rawValue)")
        XCTAssertEqual(reopened.layers[0].smartObject?.data, bytes)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8), try pixels.rgbaData(depth: .u8),
          "\(fit) \(format)")
      }
    }
  }

  func testMaskedSubjectWithinGroupAndIneligibleTargets() throws {
    var original = try document()
    let group = Layer(name: "Portrait", content: .group(.init()))
    original.layers[0].parentID = group.id
    original.layers.append(group)
    let subject = try XCTUnwrap(original.activeLayerID)
    let edit = try BackgroundReplacement.color(.black, in: original, foregroundID: subject)
    var result = original
    try edit.apply(to: &result)
    XCTAssertEqual(result.layers[0].parentID, group.id)
    XCTAssertEqual(Array(result.layers.dropFirst()), original.layers)
    XCTAssertThrowsError(try BackgroundReplacement.color(.black, in: original, foregroundID: UUID()))
    original.layers[1].visible = false
    XCTAssertNil(BackgroundReplacement.foreground(in: original))
    original.layers[1].visible = true
    original.layers[0].mask = nil
    XCTAssertNil(BackgroundReplacement.foreground(in: original))
  }

  func testMaximumWidthArtworkPreservesBothCanvasEdgesAndOriginalBytes() throws {
    let width = Surface.maxDimension, height = 8
    var source = try CraftDocument(width: width, height: height)
    var mask = try Surface(width: width, height: height, fill: .black)
    mask.setPixel(x: width / 2, y: height / 2, .white)
    source.layers[0].mask = mask
    let bytes = try artwork()
    let edited = try setBackground(source, bytes, .fill)
    let folder = try EmbeddedPlacementWorkflowTests().folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Wide background.psb")
    try PSDCodec.writeRasterLayers(edited, to: file, format: .psb)
    let reopened = try DocumentIO.read(file)
    XCTAssertEqual(reopened.layers[0].smartObject?.data, bytes)
    XCTAssertEqual(reopened.layers[1].mask, mask)
    for x in [0, width - 4] {
      let region = IntRect(x: x, y: 0, width: 4, height: height)
      let expected = try Renderer.composite(edited, region: region).cropped(to: region)
      let actual = try Renderer.composite(reopened, region: region).cropped(to: region)
      XCTAssertEqual(expected.pixel(x: 0, y: 0).a, 1)
      XCTAssertEqual(try actual.rgbaData(depth: .u8), try expected.rgbaData(depth: .u8))
    }
  }

  func testArtworkUploadPlacementRejectsMixedAndIncompleteOptions() throws {
    let id = UUID().uuidString
    XCTAssertThrowsError(try EmbeddedSourceAPI.options("""
      {"background":{"foregroundLayerID":"\(id)","fit":"fit"},"rasterize":true}
      """))
    XCTAssertThrowsError(try EmbeddedSourceAPI.options("""
      {"background":{"foregroundLayerID":"\(id)"}}
      """))
    XCTAssertThrowsError(try EmbeddedSourceAPI.options("""
      {"background":{"foregroundLayerID":"\(id)","fit":"extend"}}
      """))
    XCTAssertNotNil(try EmbeddedSourceAPI.options("""
      {"background":{"foregroundLayerID":"\(id)","fit":"original"}}
      """).background)
  }

  @MainActor func testNativeAndHTTPColorAndArtworkUseTheSameUndoableEdit() async throws {
    let source = try document(), bytes = try artwork()
    let subject = try XCTUnwrap(source.activeLayerID)
    let helper = AutomationTests(), uploads = EmbeddedPlacementWorkflowTests()
    let folder = try uploads.folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Backdrop.png")
    try bytes.write(to: file)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let store = shared.store
      store.session = EditorSession(document: source)
      try service.share(shared)
      store.selectMask(subject)
      XCTAssertTrue(store.editingMask)
      XCTAssertEqual(store.backgroundReplacementSubject, subject)

      store.applyBackgroundColor(Pixel(0.2, 0.4, 0.6), foregroundID: subject)
      await store.geometryTask?.value
      let nativeColor = try Renderer.composite(store.document).rgbaData(depth: .u8)
      XCTAssertNil(store.error)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertNil(store.maskEditingLayerID)
      await store.undo()
      store.selectMask(subject)
      let colorStatus = try await helper.edit(service, shared, BackgroundReplacementAPI.name,
        ["foregroundLayerID": subject.uuidString, "color": [0.2, 0.4, 0.6]])
      XCTAssertEqual(colorStatus, 200)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), nativeColor)
      let fill = try XCTUnwrap(store.document.activeLayerID)
      let recolorStatus = try await helper.edit(service, shared, BackgroundReplacementAPI.name,
        ["layerID": fill.uuidString, "color": [1, 0, 0]])
      XCTAssertEqual(recolorStatus, 200)
      XCTAssertEqual(try Renderer.composite(store.document).pixel(x: 0, y: 0), Pixel(1, 0, 0))
      await store.undo()
      await store.undo()
      XCTAssertEqual(store.document, source)

      store.selectMask(subject)
      store.importBackgroundArtwork(file, fit: .fill, foregroundID: subject)
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      let nativeArtwork = try Renderer.composite(store.document).rgbaData(depth: .u8)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()
      store.selectMask(subject)
      let background = ["background": ["foregroundLayerID": subject.uuidString, "fit": "fill"]]
      let denied = try await uploads.upload(service, shared, bytes, name: "Backdrop.png", options: background)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let stale = try await uploads.upload(service, shared, bytes, name: "Backdrop.png", options: background, revision: "older")
      XCTAssertEqual(stale.0.statusCode, 409)
      let imported = try await uploads.upload(service, shared, bytes, name: "Backdrop.png", options: background)
      XCTAssertEqual(imported.0.statusCode, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertNil(store.maskEditingLayerID)
      XCTAssertEqual(store.document.layers.first?.smartObject?.data, bytes)
      XCTAssertEqual(store.document.layers.last, source.layers.last)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), nativeArtwork)
      await store.undo()
      XCTAssertEqual(store.document, source)
    }
  }
}
