import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class ProcessChannelDeletionTests: XCTestCase {
  private func source(_ mode: DocumentColorMode, _ depth: PixelDepth, width: Int = 5, height: Int = 2)
    throws -> (CraftDocument, [UInt32]) {
    var document = try CraftDocument(width: width, height: height, depth: depth)
    var native = try NativeModeRaster(width: width, height: height, mode: mode, depth: depth)
    native = try native.replacingOpacity(with: Surface(width: width, height: height, depth: depth, fill: .white))
    let words: [UInt32] = depth == .u8 ? [17, 201, 31, 153] : [829, 27516, 52097, 3184]
    let scale: Float = depth == .u8 ? 255 : 65535
    for c in 0..<mode.componentCount {
      try native.set(Float(words[c]) / scale, component: c, index: width * height - 1)
    }
    document.layers[0].nativeMode = native
    document.layers[0].content = .raster(try native.surface())
    document.layers[0].background = true
    document.modeDescriptor = try .init(mode: mode, depth: depth, profile: native.profile)
    document.selection = .init(x: 0, y: 0, width: 1, height: 1)
    document.resolution = 244
    document.alphaChannels = [
      AlphaChannel(name: "Saved Mask", pixels: try Surface(width: width, height: height, depth: depth, fill: .white))
    ]
    return (document, words)
  }

  func testEachModeAndDepthKeepIndependentChannelNumbersAndSourceOrder() throws {
    for (mode, names) in [(DocumentColorMode.rgb, ["Cyan","Magenta","Yellow"]),
                          (.cmyk, ["Cyan","Magenta","Yellow","Black"]),
                          (.lab, ["Alpha 1","Alpha 2","Alpha 3"])] {
      for depth in [PixelDepth.u8, .u16] {
        let (document, words) = try source(mode, depth)
        let removed = [mode.componentCount - 1, 0]
        let indices = (0..<mode.componentCount).filter { !removed.contains($0) }
        let request = ProcessChannelDeletion(mode: mode, components: removed, mergeVisible: false)
        var session = EditorSession(document: document)
        try session.execute(InkModeInput.deleteProcess(request, in: document))
        guard case .multichannel(let result) = session.document.inkMode else { return XCTFail("Expected Multichannel") }
        XCTAssertEqual(result.plates.map(\.name), indices.map { names[$0] })
        let maximum: UInt32 = depth == .u8 ? 255 : 65535
        let expected = indices.map { mode == .cmyk ? words[$0] : maximum - words[$0] }
        XCTAssertEqual(result.plates.map { $0.samples.rawWord(at: 9) }, expected)
        XCTAssertEqual(session.document.alphaChannels, document.alphaChannels)
        XCTAssertEqual(session.document.selection, document.selection)
        XCTAssertEqual(session.document.resolution, document.resolution)
        XCTAssertTrue(session.document.layers.isEmpty)
        XCTAssertEqual(session.undoStack.count, 1)
        try session.undo()
        XCTAssertEqual(session.document, document)
      }
    }
  }

  func testMaximumSparseCMYKArchivesOnlySurvivingPlanes() throws {
    let (source, words) = try source(.cmyk, .u16, width: 300_000, height: 300_000)
    let request = ProcessChannelDeletion(mode: .cmyk, components: [1, 0], mergeVisible: false)
    var output = source
    try InkModeInput.deleteProcess(request, in: source).apply(to: &output)
    guard case .multichannel(let ink) = output.inkMode else { return XCTFail("Expected spare printing plates") }
    XCTAssertEqual(ink.plates.map(\.name), ["Yellow", "Black"])
    XCTAssertEqual(ink.plates.map { $0.samples.rawWord(at: source.width * source.height - 1) }, Array(words.suffix(2)))
    XCTAssertEqual(ink.plates.map { $0.samples.rawWord(at: 0) }, [0, 0])
    let data = try NativeArchive.encodeChunked(output)
    XCTAssertLessThan(data.count, 1_000_000)
    XCTAssertEqual(try NativeArchive.decodePaged(data), output)
  }

  func testLayeredCMYKHonorsConsentAndCompositesOnlySurvivingNumericBlack() throws {
    var document = try source(.cmyk, .u16, width: 2, height: 1).0
    var bottom = try XCTUnwrap(document.layers[0].nativeMode)
    try bottom.set(0.8, component: 3, index: 0)
    document.layers[0].nativeMode = bottom
    document.layers[0].content = .raster(try bottom.surface())
    var top = try NativeModeRaster(width: 2, height: 1, mode: .cmyk, depth: .u16)
    try top.set(0.2, component: 3, index: 0)
    try top.set(0.25, component: 4, index: 0)
    var topLayer = Layer(name: "Partial ink", content: .raster(try top.surface()))
    topLayer.nativeMode = top
    document.layers.append(topLayer)
    var hidden = topLayer
    hidden.id = UUID()
    hidden.visible = false
    document.layers.append(hidden)

    let rejected = ProcessChannelDeletion(mode: .cmyk, components: [0, 1, 2], mergeVisible: false)
    XCTAssertThrowsError(try InkModeInput.deleteProcess(rejected, in: document))
    let accepted = ProcessChannelDeletion(mode: .cmyk, components: [0, 1, 2], mergeVisible: true)
    var result = document
    try InkModeInput.deleteProcess(accepted, in: document).apply(to: &result)
    guard case .multichannel(let plates) = result.inkMode else { return XCTFail("Expected one process plate") }
    XCTAssertEqual(plates.plates.map(\.name), ["Black"])
    XCTAssertEqual(plates.plates[0].samples.value(at: 0), 0.65, accuracy: 2 / 65535)
    XCTAssertEqual(plates.plates[0].samples.rawWord(at: 1), bottom.rawWord(component: 3, index: 1))
    for format in [PSDFileFormat.psd, .psb] {
      let data = try PSDCodec.writeRasterLayers(result, format: format)
      let reopened = try PSDCodec.read(data)
      guard case .multichannel(let restored) = reopened.inkMode else { return XCTFail("Expected editable PSB ink") }
      XCTAssertEqual(restored.plates.map(\.samples), plates.plates.map(\.samples))
    }
  }

  func testRejectsDroppingEveryComponentWrongModeQuickMaskAndRGB32() throws {
    let rgb = try source(.rgb, .u8).0
    for request in [
      ProcessChannelDeletion(mode: .rgb, components: [], mergeVisible: true),
      ProcessChannelDeletion(mode: .rgb, components: [0, 1, 2], mergeVisible: true),
      ProcessChannelDeletion(mode: .rgb, components: [0, 0], mergeVisible: true),
      ProcessChannelDeletion(mode: .rgb, components: [3], mergeVisible: true),
      ProcessChannelDeletion(mode: .lab, components: [0], mergeVisible: true)
    ] {
      XCTAssertThrowsError(try InkModeInput.deleteProcess(request, in: rgb))
    }
    let request = ProcessChannelDeletion(mode: .rgb, components: [0], mergeVisible: true)
    var mask = rgb
    mask.quickMask = .init(name: "Quick Mask", pixels: try Surface(width: rgb.width, height: rgb.height, fill: .white))
    XCTAssertThrowsError(try InkModeInput.deleteProcess(request, in: mask))
    XCTAssertThrowsError(try InkModeInput.deleteProcess(request, in: CraftDocument(width: 3, height: 3, depth: .f32)))
  }
}
